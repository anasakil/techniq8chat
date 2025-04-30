// screens/incoming_call_screen.dart
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
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  bool _isAccepting = false;
  bool _isRejecting = false;
  bool _isClosing = false;

  // Store services to avoid accessing Provider in dispose
  late CallService _callService;
  late SocketService _socketService;

  // Animation controllers
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Ripple animations for the avatar
  final List<double> _rippleRadii = [0, 0, 0];
  final List<double> _rippleOpacities = [0.6, 0.4, 0.2];
  
  // Timer for updating ripple animations
  Timer? _rippleTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    print("INCOMING CALL SCREEN INITIALIZED WITH DATA: ${widget.callData}");

    // Set up pulse animation for caller avatar
    _pulseController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Initialize ripple animations
    _startRippleAnimation();

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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Cache the services when dependencies change
    _callService = Provider.of<CallService>(context, listen: false);
    _socketService = Provider.of<SocketService>(context, listen: false);
  }

  void _startRippleAnimation() {
    _rippleTimer = Timer.periodic(Duration(milliseconds: 50), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        // Update ripple sizes
        for (int i = 0; i < _rippleRadii.length; i++) {
          _rippleRadii[i] += 0.5;
          if (_rippleRadii[i] > 40) {
            _rippleRadii[i] = 0;
          }
        }
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
    _pulseController.dispose();
    _rippleTimer?.cancel();

    // Restore system UI and orientation
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge,
        overlays: SystemUiOverlay.values);

    // Use the cached service instead of Provider
    if (widget.callData['callId'] != null) {
      try {
        _socketService.completeCallProcessing(widget.callData['callId']);
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
    final isVideoCall = callType.toLowerCase().contains('video');

    // Get screen size for responsive layout
    final screenSize = MediaQuery.of(context).size;
    
    // Add debug info
    print(
        "Building incoming call UI for: $callerName, ID: $callId, Type: $callType");

    return Scaffold(
      backgroundColor: Colors.transparent,
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Header with caller info
              Padding(
                padding: EdgeInsets.only(top: screenSize.height * 0.08),
                child: Column(
                  children: [
                    // Call type indicator
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black12,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isVideoCall ? Icons.videocam : Icons.call,
                            color: Colors.white,
                            size: 18,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Incoming ${isVideoCall ? 'Video' : 'Voice'} Call',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    SizedBox(height: screenSize.height * 0.06),
                    
                    // Animated avatar with ripples
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        // Ripple effects
                        for (int i = 0; i < _rippleRadii.length; i++)
                          if (_rippleRadii[i] > 0)
                            Opacity(
                              opacity: _rippleOpacities[i] * (1 - _rippleRadii[i] / 40),
                              child: Container(
                                width: 100 + _rippleRadii[i] * 2,
                                height: 100 + _rippleRadii[i] * 2,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            
                        // Pulsing avatar
                        AnimatedBuilder(
                          animation: _pulseController,
                          builder: (context, child) {
                            return Transform.scale(
                              scale: _pulseAnimation.value,
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black26,
                                      blurRadius: 10,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                child: CircleAvatar(
                                  radius: 50,
                                  backgroundColor: Colors.white.withOpacity(0.9),
                                  child: Text(
                                    callerName.isNotEmpty
                                        ? callerName[0].toUpperCase()
                                        : "?",
                                    style: TextStyle(
                                      fontSize: 40,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF2A64F6),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),

                    SizedBox(height: 24),
                    
                    // Caller name with shadow for better readability
                    Text(
                      callerName,
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
                    
                    // Optional: Add status text or additional info
                    SizedBox(height: 8),
                    Text(
                      "Wants to talk with you",
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white.withOpacity(0.8),
                      ),
                    ),
                  ],
                ),
              ),

              // Call actions
              Container(
                margin: EdgeInsets.only(bottom: 50),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Decline button
                    _buildActionButton(
                      icon: Icons.call_end_rounded,
                      text: 'Decline',
                      backgroundColor: Colors.red,
                      isLoading: _isRejecting,
                      onPressed: (_isAccepting || _isClosing) ? null : _handleRejectCall,
                    ),

                    // Accept button
                    _buildActionButton(
                      icon: isVideoCall ? Icons.videocam : Icons.call,
                      text: 'Accept',
                      backgroundColor: Colors.green,
                      isLoading: _isAccepting,
                      onPressed: (_isRejecting || _isClosing) ? null : _handleAcceptCall,
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
    required String text,
    required Color backgroundColor,
    required VoidCallback? onPressed,
    bool isLoading = false,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
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
                    ? SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Icon(
                        icon,
                        color: Colors.white,
                        size: 35,
                      ),
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
            shadows: [
              Shadow(
                blurRadius: 4,
                color: Colors.black26,
                offset: Offset(0, 1),
              ),
            ],
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

    // Now process the call acceptance using cached service
    try {
      await _callService.answerCall(context, callDataCopy);
    } catch (e) {
      print("Error answering call: $e");
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

    // Now process the call rejection using cached service
    try {
      await _callService.rejectCall(context, callDataCopy);
    } catch (e) {
      print("Error rejecting call: $e");
    }
  }
}