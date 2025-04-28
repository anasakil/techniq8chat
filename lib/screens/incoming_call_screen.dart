import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:techniq8chat/services/call_service.dart';
import 'dart:async';

import 'package:techniq8chat/services/socket_service.dart';

class IncomingCallScreen extends StatefulWidget {
  final Map<String, dynamic> callData;
  final VoidCallback? onClose;

  const IncomingCallScreen({
    Key? key,
    required this.callData,
    this.onClose,
  }) : super(key: key);

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen>
    with WidgetsBindingObserver {
  bool _isAccepting = false;
  bool _isRejecting = false;
  bool _isClosing = false;

  // Timer to keep screen awake and show audio visuals
  Timer? _pulseTimer;
  double _pulseValue = 1.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    print("INCOMING CALL SCREEN INITIALIZED WITH DATA: ${widget.callData}");

    // Start pulse animation for the avatar
    _startPulseAnimation();

    // Force the screen to be in portrait mode
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);

    // Keep screen on while call screen is displayed
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
        overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom]);

    // Keep device awake
    SystemChannels.platform.invokeMethod('SystemChrome.setEnabledSystemUIMode',
        SystemUiMode.immersiveSticky.toString());

    // Ensure the screen stays visible by playing haptic feedback
    HapticFeedback.mediumImpact();

    // Start a timer to periodically ensure the screen stays awake
    Timer.periodic(Duration(seconds: 3), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      HapticFeedback.selectionClick();
    });
  }

  void _startPulseAnimation() {
    _pulseTimer = Timer.periodic(Duration(milliseconds: 1000), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        _pulseValue = _pulseValue == 1.0 ? 1.2 : 1.0;
      });
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Ensure we stay visible if app lifecycle changes
    if (state == AppLifecycleState.resumed) {
      // App is active again - ensure UI is still visible
      HapticFeedback.mediumImpact();
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
          overlays: SystemUiOverlay.values);
    }
  }

  @override
void dispose() {
  WidgetsBinding.instance.removeObserver(this);
  _pulseTimer?.cancel();

  // Restore system UI and orientation
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge,
      overlays: SystemUiOverlay.values);

  // Ensure call is marked as processed
  if (widget.callData['callId'] != null) {
    try {
      final socketService = Provider.of<SocketService>(context, listen: false);
      socketService.completeCallProcessing(widget.callData['callId']);
    } catch (e) {
      print('Error in dispose: $e');
    }
  }

  super.dispose();
}

  @override
  Widget build(BuildContext context) {
    final callerName = widget.callData['callerName'] ?? 'Unknown';
    final callType = widget.callData['callType'] ?? 'voice';
    final callId = widget.callData['callId'];

    // Add debug info
    print(
        "Building incoming call UI for: $callerName, ID: $callId, Type: $callType");

    return Scaffold(
      backgroundColor: const Color(0xFF2A64F6),
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Incoming call header
            Padding(
              padding: const EdgeInsets.only(top: 60),
              child: Column(
                children: [
                  Text(
                    'Incoming ${callType == 'video' ? 'Video' : 'Voice'} Call',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 40),
                  // Animated avatar
                  AnimatedScale(
                    scale: _pulseValue,
                    duration: Duration(milliseconds: 500),
                    curve: Curves.easeInOut,
                    child: CircleAvatar(
                      radius: 60,
                      backgroundColor: Colors.white.withOpacity(0.2),
                      child: Text(
                        callerName.isNotEmpty
                            ? callerName[0].toUpperCase()
                            : "?",
                        style: const TextStyle(
                          fontSize: 50,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    callerName,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),

            // Call actions
            Padding(
              padding: const EdgeInsets.only(bottom: 60),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Decline button
                  _buildActionButton(
                    icon: Icons.call_end_rounded,
                    backgroundColor: Colors.red,
                    text: 'Decline',
                    isLoading: _isRejecting,
                    onPressed:
                        (_isAccepting || _isClosing) ? null : _handleRejectCall,
                  ),

                  // Accept button
                  _buildActionButton(
                    icon: Icons.call_rounded,
                    backgroundColor: Colors.green,
                    text: 'Accept',
                    isLoading: _isAccepting,
                    onPressed:
                        (_isRejecting || _isClosing) ? null : _handleAcceptCall,
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
    required String text,
    required VoidCallback? onPressed,
    bool isLoading = false,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(35),
          child: Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: backgroundColor,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: isLoading
                  ? CircularProgressIndicator(color: Colors.white)
                  : Icon(
                      icon,
                      color: Colors.white,
                      size: 35,
                    ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          text,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  void _handleAcceptCall() async {
    print("ACCEPTING CALL: ${widget.callData}");

    if (_isAccepting || _isRejecting || _isClosing) return;

    setState(() {
      _isAccepting = true;
      _isClosing = true; // Set closing flag to prevent multiple calls
    });

    // Capture callback locally to prevent issues
    final onCloseCallback = widget.onClose;

    // Make a copy of call data
    final Map<String, dynamic> callDataCopy =
        Map<String, dynamic>.from(widget.callData);

    // Get services FIRST
    CallService? callService;
    try {
      callService = Provider.of<CallService>(context, listen: false);
    } catch (e) {
      print("Error getting CallService: $e");
    }

    // Close the UI first (do this before any heavy processing)
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (onCloseCallback != null) {
          onCloseCallback();
        } else if (mounted && Navigator.canPop(context)) {
          // Only try to pop if we're still mounted
          Navigator.of(context, rootNavigator: true).pop();
        }
      });
    }

    // Wait a moment for UI to update
    await Future.delayed(Duration(milliseconds: 100));

    // Now process the call acceptance if the service is available
    if (callService != null) {
      try {
        await callService.answerCall(context, callDataCopy);
      } catch (e) {
        print("Error answering call: $e");
      }
    }
  }

  void _handleRejectCall() async {
    print("REJECTING CALL: ${widget.callData}");

    if (_isAccepting || _isRejecting || _isClosing) return;

    setState(() {
      _isRejecting = true;
      _isClosing = true; // Set closing flag to prevent multiple calls
    });

    // Capture callback locally to prevent issues
    final onCloseCallback = widget.onClose;

    // Make a copy of call data
    final Map<String, dynamic> callDataCopy =
        Map<String, dynamic>.from(widget.callData);

    // Get service FIRST
    CallService? callService;
    try {
      callService = Provider.of<CallService>(context, listen: false);
    } catch (e) {
      print("Error getting CallService: $e");
    }

    // Close the UI first (do this before any heavy processing)
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (onCloseCallback != null) {
          onCloseCallback();
        } else if (mounted && Navigator.canPop(context)) {
          // Only try to pop if we're still mounted
          Navigator.of(context, rootNavigator: true).pop();
        }
      });
    }

    // Wait a moment for UI to update
    await Future.delayed(Duration(milliseconds: 100));

    // Now process the call rejection if the service is available
    if (callService != null) {
      try {
        await callService.rejectCall(context, callDataCopy);
      } catch (e) {
        print("Error rejecting call: $e");
      }
    }
  }
}
