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
  // Store the call service to avoid Provider access in dispose
  late CallService _callService;
  bool _isConnected = false;
  bool _isMuted = false;
  bool _isSpeakerOn = false;
  bool _isEnding = false;
  Timer? _callTimer;
  Timer? _connectionTimeoutTimer;
  int _callDuration = 0;
  StreamSubscription? _remoteUserJoinedSubscription;
  StreamSubscription? _callEndedSubscription;
  StreamSubscription? _callStatusChangeSubscription;

  // Connection status animation
  double _connectionDotOpacity = 1.0;
  Timer? _connectionAnimationTimer;

  // Sound wave animation for voice calls
  final List<double> _soundWaveHeights = List.generate(7, (_) => 0.3);
  Timer? _soundWaveAnimationTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Keep screen on
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
        overlays: SystemUiOverlay.values);

    // Start connection dot animation
    _startConnectionAnimation();

    // Start sound wave animation
    if (widget.callType == CallType.voice) {
      _startSoundWaveAnimation();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Get and store call service during didChangeDependencies
    _callService = Provider.of<CallService>(context, listen: false);
    _isMuted = _callService.isLocalAudioMuted;

    // Check initial speaker state
    _checkInitialSpeakerState();

    // Set up listeners only once
    if (_remoteUserJoinedSubscription == null) {
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
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Call failed to connect')));
          }
        });
      }
    }
  }

  void _startConnectionAnimation() {
    _connectionAnimationTimer =
        Timer.periodic(Duration(milliseconds: 800), (timer) {
      if (mounted && !_isConnected) {
        setState(() {
          _connectionDotOpacity = _connectionDotOpacity == 1.0 ? 0.3 : 1.0;
        });
      } else if (_isConnected) {
        timer.cancel();
      }
    });
  }

  void _startSoundWaveAnimation() {
    _soundWaveAnimationTimer =
        Timer.periodic(Duration(milliseconds: 150), (timer) {
      if (mounted && _isConnected && !_isMuted) {
        setState(() {
          for (int i = 0; i < _soundWaveHeights.length; i++) {
            // Random heights between 0.2 and 1.0
            _soundWaveHeights[i] = 0.2 +
                (0.8 *
                    (i % 3 == 0
                        ? 0.9
                        : i % 2 == 0
                            ? 0.6
                            : 0.3));
          }
        });
      }
    });
  }

  // Check initial speaker state
  Future<void> _checkInitialSpeakerState() async {
    if (_callService.isCallActive && mounted) {
      try {
        // Get initial speaker state from Agora engine
        final speakerEnabled = await _callService.isSpeakerEnabled();
        setState(() {
          _isSpeakerOn = speakerEnabled;
        });
      } catch (e) {
        print('Error checking initial speaker state: $e');
      }
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
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final remainingSeconds = seconds % 60;

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
    } else {
      return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
    }
  }

  Future<void> _toggleMute() async {
    final muted = await _callService.toggleMute();
    if (mounted) {
      setState(() {
        _isMuted = muted;
      });
    }
  }

  Future<void> _toggleSpeaker() async {
    try {
      // Call the actual Agora engine method through CallService
      final speakerOn = await _callService.toggleSpeaker();

      if (mounted) {
        setState(() {
          _isSpeakerOn = speakerOn;
        });
      }

      // Show feedback to user (optional)
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Speaker ${_isSpeakerOn ? 'enabled' : 'disabled'}'),
            duration: Duration(seconds: 1),
            backgroundColor: Color(0xFF2A64F6),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      print('Error toggling speaker: $e');
      // Show error feedback
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to toggle speaker mode'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
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
    _connectionTimeoutTimer?.cancel();
    _connectionAnimationTimer?.cancel();
    _soundWaveAnimationTimer?.cancel();

    // Notify the CallService that the call is ending FIRST
    _callService.endCall();

    // Clear any UI resources
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge,
        overlays: SystemUiOverlay.values);

    // Give a small delay to let endCall complete before navigation
    Future.delayed(Duration(milliseconds: 50), () {
      if (mounted) {
        print('Attempting to pop call screen');
        // Pop to a named route instead of just popping
        try {
          Navigator.of(context)
              .pushNamedAndRemoveUntil('/home', (route) => false);
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
    _connectionAnimationTimer?.cancel();
    _soundWaveAnimationTimer?.cancel();
    _remoteUserJoinedSubscription?.cancel();
    _callEndedSubscription?.cancel();
    _callStatusChangeSubscription?.cancel();

    // Allow normal screen timeout again
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge,
        overlays: SystemUiOverlay.values);

    // Make sure all resources are cleaned up
    // Use the cached _callService instead of Provider
    if (!_isEnding) {
      _callService.endCall();
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Get screen dimensions for responsive layout
    final screenSize = MediaQuery.of(context).size;
    final isVideoCall = widget.callType == CallType.video;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF2A64F6),
              Color(0xFF0A42A8),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Status bar with subtle styling
              Container(
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                margin: EdgeInsets.only(top: 16),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Call type icon
                    Icon(
                      isVideoCall ? Icons.videocam : Icons.call,
                      color: Colors.white,
                      size: 16,
                    ),
                    SizedBox(width: 8),

                    // Call status
                    Text(
                      _isConnected ? 'Connected' : 'Connecting',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),

                    // Connection animation dot
                    if (!_isConnected) ...[
                      SizedBox(width: 4),
                      AnimatedOpacity(
                        opacity: _connectionDotOpacity,
                        duration: Duration(milliseconds: 300),
                        child: Text(
                          '•',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Call header with caller info
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Avatar with container shadow for depth
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 15,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: CircleAvatar(
                        radius: 50,
                        backgroundColor: Colors.white.withOpacity(0.9),
                        child: Text(
                          widget.username.isNotEmpty
                              ? widget.username[0].toUpperCase()
                              : "?",
                          style: TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF2A64F6),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Username with shadow for better readability
                    Text(
                      widget.username,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        shadows: [
                          Shadow(
                            blurRadius: 8,
                            color: Colors.black26,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Call status/duration
                    Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _isConnected
                            ? _formatDuration(_callDuration)
                            : "Connecting...",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Sound wave visualization for voice calls
              if (widget.callType == CallType.voice && _isConnected)
                Container(
                  height: 80,
                  margin: EdgeInsets.symmetric(horizontal: 50),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: List.generate(
                      _soundWaveHeights.length,
                      (index) => AnimatedContainer(
                        duration: Duration(milliseconds: 150),
                        width: 6,
                        height: _isMuted ? 10 : 60 * _soundWaveHeights[index],
                        decoration: BoxDecoration(
                          color: _isMuted
                              ? Colors.grey.withOpacity(0.5)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ),

              const Spacer(),

              // Call actions
              Container(
                margin: EdgeInsets.only(bottom: 50),
                child: Column(
                  children: [
                    // Main actions row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildActionButton(
                          icon: _isMuted
                              ? Icons.mic_off_rounded
                              : Icons.mic_rounded,
                          backgroundColor: _isMuted
                              ? Colors.white.withOpacity(0.3)
                              : Colors.white.withOpacity(0.2),
                          isActive: _isMuted,
                          onPressed: _toggleMute,
                        ),
                        SizedBox(width: 24),
                        _buildActionButton(
                          icon: Icons.call_end_rounded,
                          backgroundColor: Colors.red,
                          onPressed: _endCall,
                          size: 70,
                        ),
                        SizedBox(width: 24),
                        _buildActionButton(
                          icon: _isSpeakerOn
                              ? Icons.volume_up_rounded
                              : Icons.volume_down_rounded,
                          backgroundColor: _isSpeakerOn
                              ? Colors.white.withOpacity(0.3)
                              : Colors.white.withOpacity(0.2),
                          isActive: _isSpeakerOn,
                          onPressed: _toggleSpeaker,
                        ),
                      ],
                    ),

                    // Labels for buttons
                    SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildActionLabel("Mute", width: 70),
                        SizedBox(width: 24),
                        _buildActionLabel("End Call", width: 70),
                        SizedBox(width: 24),
                        _buildActionLabel("Speaker", width: 70),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required Color backgroundColor,
    required VoidCallback onPressed,
    double size = 60,
    bool isActive = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: backgroundColor.withOpacity(0.5),
            spreadRadius: 1,
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: InkWell(
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
              color: isActive ? Color(0xFF2A64F6) : Colors.white,
              size: size * 0.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionLabel(String label, {required double width}) {
    return Container(
      width: width,
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
