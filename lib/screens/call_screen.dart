// screens/call_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:techniq8chat/services/call_service.dart';

class CallScreen extends StatefulWidget {
  final String userId;
  final String username;
  final CallType callType;
  final String callId;

  const CallScreen({
    Key? key,
    required this.userId,
    required this.username,
    required this.callType,
    required this.callId,
  }) : super(key: key);

  @override
  _CallScreenState createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> with WidgetsBindingObserver {
  late CallService _callService;
  bool _isConnected = false;
  bool _isMuted = false;
  bool _isEnding = false;
  Timer? _callTimer;
  Timer? _connectionTimeoutTimer;
  int _callDuration = 0;
  StreamSubscription? _remoteUserJoinedSubscription;
  StreamSubscription? _callEndedSubscription;
  StreamSubscription? _callStatusChangeSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Keep screen on
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
        overlays: SystemUiOverlay.values);

    _callService = Provider.of<CallService>(context, listen: false);
    _isMuted = _callService.isLocalAudioMuted;

    // Listen for remote user joining
    _remoteUserJoinedSubscription =
        _callService.onRemoteUserJoined.listen((joined) {
      if (joined && mounted) {
        setState(() {
          _isConnected = true;
        });
        _startCallTimer();
        // Cancel timeout timer if it's running
        _connectionTimeoutTimer?.cancel();
      }
    });

    // Listen for call ended events
    _callEndedSubscription = _callService.onCallEnded.listen((ended) {
      if (ended && mounted) {
        _endCall();
      }
    });

    // Also listen for call status changes
    _callStatusChangeSubscription =
        _callService.onCallStatusChange.listen((data) {
      print('Call status update on CallScreen: $data');
      if (data['status'] == 'ended' && mounted) {
        _endCall();
      }
    });

    // If we're answering a call, we're already connected
    if (_callService.isCallConnected) {
      _isConnected = true;
      _startCallTimer();
    } else {
      // Start a connection timeout timer
      _connectionTimeoutTimer = Timer(Duration(seconds: 30), () {
        if (!_isConnected && mounted) {
          print('Call connection timeout - ending call');
          _endCall();

          // Show a toast/snackbar
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Call failed to connect')));
        }
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Check if the call is still active when app is resumed
      if (_callService.currentCallId != widget.callId) {
        print('Call no longer active on app resume - closing call screen');
        if (mounted) {
          _endCall();
        }
      }
    }
  }

  void _startCallTimer() {
    _callTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _callDuration++;
        });
      }
    });
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  Future<void> _toggleMute() async {
    final muted = await _callService.toggleMute();
    if (mounted) {
      setState(() {
        _isMuted = muted;
      });
    }
  }

  void _endCall() {
  // Prevent multiple calls to endCall
  if (_isEnding) return;
  
  // Set flag first to prevent multiple calls
  _isEnding = true;
  print('Call screen - endCall() called, starting cleanup');

  // Cancel timers first
  _callTimer?.cancel();
  _callTimer = null;
  _connectionTimeoutTimer?.cancel();
  _connectionTimeoutTimer = null;

  // Notify the CallService that the call is ending FIRST
  _callService.endCall();
  
  // Clear any UI resources
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.edgeToEdge,
    overlays: SystemUiOverlay.values
  );

  // Give a small delay to let endCall complete before navigation
  Future.delayed(Duration(milliseconds: 50), () {
    if (mounted) {
      print('Attempting to pop call screen');
      // Pop to a named route instead of just popping
      try {
        Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
      } catch (e) {
        print('Error navigating: $e');
        // Fallback navigation approach
        if (mounted && Navigator.canPop(context)) {
          Navigator.of(context).pop();
        }
      }
    }
  });
}

  @override
  void dispose() {
    print('CallScreen - dispose called');
    WidgetsBinding.instance.removeObserver(this);

    _callTimer?.cancel();
    _connectionTimeoutTimer?.cancel();
    _remoteUserJoinedSubscription?.cancel();
    _callEndedSubscription?.cancel();
    _callStatusChangeSubscription?.cancel();

    // Allow normal screen timeout again
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge,
        overlays: SystemUiOverlay.values);

    // Make sure all resources are cleaned up
    if (!_isEnding) {
      _callService.endCall();
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2A64F6),
      body: SafeArea(
        child: Column(
          children: [
            // Call header
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: Colors.white.withOpacity(0.2),
                    child: Text(
                      widget.username.isNotEmpty
                          ? widget.username[0].toUpperCase()
                          : "?",
                      style: const TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    widget.username,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isConnected
                        ? _formatDuration(_callDuration)
                        : "Calling...",
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white.withOpacity(0.8),
                    ),
                  ),
                ],
              ),
            ),

            const Spacer(),

            // Call actions
            Container(
              margin: const EdgeInsets.only(bottom: 50),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildActionButton(
                    icon: _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                    backgroundColor: Colors.white.withOpacity(0.2),
                    onPressed: _toggleMute,
                  ),
                  _buildActionButton(
                    icon: Icons.call_end_rounded,
                    backgroundColor: Colors.red,
                    onPressed: _endCall,
                    size: 70,
                  ),
                  _buildActionButton(
                    icon: Icons.volume_up_rounded,
                    backgroundColor: Colors.white.withOpacity(0.2),
                    onPressed: () {
                      // Toggle speaker (not implemented)
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required Color backgroundColor,
    required VoidCallback onPressed,
    double size = 60,
  }) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(size / 2),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: backgroundColor,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Icon(
            icon,
            color: Colors.white,
            size: size * 0.5,
          ),
        ),
      ),
    );
  }
}
