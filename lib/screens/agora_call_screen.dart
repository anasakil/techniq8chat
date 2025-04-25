import 'dart:async';
import 'package:flutter/material.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:techniq8chat/services/call_manager.dart';

class AgoraCallScreen extends StatefulWidget {
  final String remoteUserId;
  final String remoteUsername;
  final CallType callType;
  final bool isIncoming;

  const AgoraCallScreen({
    Key? key,
    required this.remoteUserId,
    required this.remoteUsername,
    required this.callType,
    this.isIncoming = false,
  }) : super(key: key);

  @override
  _AgoraCallScreenState createState() => _AgoraCallScreenState();
}

class _AgoraCallScreenState extends State<AgoraCallScreen> {
  // Call manager instance
  late CallManager _callManager;
  
  // Local state variables
  CallState _callState = CallState.idle;
  bool _remoteUserJoined = false;
  bool _localMuted = false;
  bool _localVideoOff = false;
  int _callDuration = 0;
  
  // Stream subscriptions
  StreamSubscription? _callStateSubscription;
  StreamSubscription? _remoteUserJoinedSubscription;
  StreamSubscription? _remoteUserLeftSubscription;
  StreamSubscription? _errorSubscription;
  StreamSubscription? _durationSubscription;
  
  @override
  void initState() {
    super.initState();
    _callManager = CallManager.instance!;
    
    // Setup listeners
    _setupListeners();
    
    // Start or accept call based on isIncoming
    _initializeCall();
  }
  
  @override
  void dispose() {
    // Clean up subscriptions
    _callStateSubscription?.cancel();
    _remoteUserJoinedSubscription?.cancel();
    _remoteUserLeftSubscription?.cancel();
    _errorSubscription?.cancel();
    _durationSubscription?.cancel();
    
    // End call if still active
    if (_callManager.callState != CallState.idle) {
      _callManager.endCall(true);
    }
    
    super.dispose();
  }
  
  // Setup stream listeners
  void _setupListeners() {
    // Call state changes
    _callStateSubscription = _callManager.onCallStateChanged.listen((state) {
      setState(() {
        _callState = state;
        
        // If call disconnected or ended, navigate back
        if (state == CallState.disconnected || state == CallState.idle) {
          // Add a short delay to show the disconnected state
          Future.delayed(Duration(seconds: 1), () {
            if (mounted) {
              Navigator.of(context).pop();
            }
          });
        }
      });
    });
    
    // Remote user joined
    _remoteUserJoinedSubscription = _callManager.onRemoteUserJoined.listen((_) {
      setState(() {
        _remoteUserJoined = true;
      });
    });
    
    // Remote user left
    _remoteUserLeftSubscription = _callManager.onRemoteUserLeft.listen((_) {
      setState(() {
        _remoteUserJoined = false;
      });
    });
    
    // Errors
    _errorSubscription = _callManager.onError.listen((error) {
      _showErrorSnackbar(error);
    });
    
    // Call duration
    _durationSubscription = _callManager.onCallDurationChanged.listen((duration) {
      setState(() {
        _callDuration = duration;
      });
    });
  }
  
  // Initialize the call
   Future<void> _initializeCall() async {
    try {
      print('Initializing ${widget.callType.name} call with ${widget.remoteUsername}');
      print('Remote user ID: ${widget.remoteUserId}');
      print('Is incoming call: ${widget.isIncoming}');
      
      // Verify CallManager instance exists
      if (CallManager.instance == null) {
        throw Exception("Call manager not initialized");
      }
      _callManager = CallManager.instance!;
      
      if (widget.isIncoming) {
        // For incoming calls, just accept the call
        print('Accepting incoming call');
        final success = await _callManager.acceptCall();
        
        if (!success) {
          throw Exception("Failed to accept call");
        }
      } else {
        // For outgoing calls, start a new call
        print('Starting outgoing call');
        
        // Debug info before starting
        print('Call parameters:');
        print('- Remote user ID: ${widget.remoteUserId}');
        print('- Remote username: ${widget.remoteUsername}');
        print('- Call type: ${widget.callType.name}');
        
        final success = await _callManager.startCall(
          widget.remoteUserId, 
          widget.remoteUsername,
          widget.callType
        );
        
        if (!success) {
          throw Exception("Failed to start call");
        }
      }
    } catch (e) {
      print('Error initializing call: $e');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Call error: $e'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
        
        // Wait a moment before popping to ensure the error is visible
        Future.delayed(Duration(seconds: 1), () {
          if (mounted) {
            Navigator.of(context).pop();
          }
        });
      }
    }
  }
  
  // Add this helper method to show detailed information in case of error
  void _debugPrintCallState() {
    print('=== CALL STATE DEBUG INFO ===');
    print('Call state: ${_callManager.callState}');
    print('Is initiator: ${_callManager.isInitiator}');
    print('Call type: ${_callManager.callType}');
    print('Channel ID: ${_callManager.channelId}');
    print('Remote user ID: ${_callManager.remoteUserId}');
    print('Engine initialized: ${_callManager.engine != null}');
    print('============================');
  }
  // Show error message
  void _showErrorSnackbar(String message) {
    if (mounted) {
      _debugPrintCallState();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Dismiss',
            textColor: Colors.white,
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
            },
          ),
        ),
      );
    }
  }
  
  // Format call duration
  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Main content
          _buildMainContent(),
          
          // Call UI overlay
          SafeArea(
            child: Column(
              children: [
                // Top bar with user info and call status
                _buildTopBar(),
                
                Spacer(),
                
                // Bottom call controls
                _buildCallControls(),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  // Build main content based on call type and state
  Widget _buildMainContent() {
    // For video calls, show video views
    if (_callManager.callType == CallType.video) {
      return Stack(
        children: [
          // Remote video (full screen)
          if (_remoteUserJoined)
            Center(
              child: _renderRemoteVideo(),
            )
          else
            Center(
              child: Container(
                color: Colors.grey[900],
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(
                        radius: 50,
                        backgroundColor: const Color(0xFF2A64F6).withOpacity(0.3),
                        child: Text(
                          widget.remoteUsername[0].toUpperCase(),
                          style: TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      SizedBox(height: 20),
                      Text(
                        _callState == CallState.calling
                            ? 'Calling...'
                            : 'Connecting...',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                        ),
                      )
                    ],
                  ),
                ),
              ),
            ),
            
          // Local video (picture-in-picture)
          if (_callManager.engine != null)
            Positioned(
              right: 16,
              top: 100,
              width: 120,
              height: 160,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: _renderLocalVideo(),
                ),
              ),
            ),
        ],
      );
    } 
    // For audio calls, show caller info
    else {
      return Container(
        color: const Color(0xFF2A64F6).withOpacity(0.1),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 80,
                backgroundColor: const Color(0xFF2A64F6).withOpacity(0.3),
                child: Text(
                  widget.remoteUsername[0].toUpperCase(),
                  style: TextStyle(
                    fontSize: 60,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              SizedBox(height: 30),
              Text(
                widget.remoteUsername,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 12),
              Text(
                _getStatusText(),
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white70,
                ),
              ),
              if (_callState == CallState.connected)
                Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    _formatDuration(_callDuration),
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white70,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }
  }
  
  // Render local video view
  Widget _renderLocalVideo() {
    if (_localVideoOff) {
      return Container(
        color: Colors.grey[800],
        child: Center(
          child: Icon(
            Icons.videocam_off,
            color: Colors.white,
            size: 40,
          ),
        ),
      );
    }
    
    return AgoraVideoView(
      controller: VideoViewController(
        rtcEngine: _callManager.engine!,
        canvas: const VideoCanvas(uid: 0),
      ),
    );
  }
  
  // Render remote video view
  Widget _renderRemoteVideo() {
    return AgoraVideoView(
      controller: VideoViewController.remote(
        rtcEngine: _callManager.engine!,
        canvas: VideoCanvas(uid: 1),
        connection: RtcConnection(channelId: _callManager.channelId!),
      ),
    );
  }
  
  // Build top bar with user info and call status
  Widget _buildTopBar() {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      child: Row(
        children: [
          // Back button
          IconButton(
            icon: Icon(Icons.arrow_back_ios, color: Colors.white),
            onPressed: () {
              _callManager.endCall(true);
              Navigator.pop(context);
            },
          ),
          
          SizedBox(width: 16),
          
          // Call info
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.remoteUsername,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                _getStatusText(),
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          
          Spacer(),
          
          // Call duration
          if (_callState == CallState.connected)
            Text(
              _formatDuration(_callDuration),
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
              ),
            ),
        ],
      ),
    );
  }
  
  // Build call control buttons
  Widget _buildCallControls() {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Mute button
          _buildControlButton(
            icon: _localMuted ? Icons.mic_off : Icons.mic,
            backgroundColor: _localMuted ? Colors.red : Colors.white38,
            onPressed: () async {
              final muted = await _callManager.toggleMute();
              setState(() {
                _localMuted = muted;
              });
            },
            tooltip: _localMuted ? 'Unmute' : 'Mute',
          ),
          
          SizedBox(width: 20),
          
          // End call button
          _buildControlButton(
            icon: Icons.call_end,
            backgroundColor: Colors.red,
            size: 64,
            iconSize: 30,
            onPressed: () {
              _callManager.endCall(true);
              Navigator.pop(context);
            },
            tooltip: 'End Call',
          ),
          
          SizedBox(width: 20),
          
          // Video or speaker button
          widget.callType == CallType.video
              ? _buildControlButton(
                  icon: _localVideoOff ? Icons.videocam_off : Icons.videocam,
                  backgroundColor: _localVideoOff ? Colors.red : Colors.white38,
                  onPressed: () async {
                    final videoOff = await _callManager.toggleCamera();
                    setState(() {
                      _localVideoOff = videoOff;
                    });
                  },
                  tooltip: _localVideoOff ? 'Turn on camera' : 'Turn off camera',
                )
              : _buildControlButton(
                  icon: Icons.volume_up,
                  backgroundColor: Colors.white38,
                  onPressed: () {
                    // TODO: Implement speaker toggle
                  },
                  tooltip: 'Speaker',
                ),
        ],
      ),
    );
  }
  
  // Helper to build control buttons
  Widget _buildControlButton({
    required IconData icon, 
    required Color backgroundColor,
    required VoidCallback onPressed,
    required String tooltip,
    double size = 56,
    double iconSize = 24,
  }) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: backgroundColor,
      ),
      width: size,
      height: size,
      child: IconButton(
        icon: Icon(icon, size: iconSize),
        color: Colors.white,
        onPressed: onPressed,
        tooltip: tooltip,
      ),
    );
  }
  
  // Get call status text based on state
  String _getStatusText() {
    switch (_callState) {
      case CallState.calling:
        return 'Calling...';
      case CallState.connecting:
        return 'Connecting...';
      case CallState.connected:
        return _remoteUserJoined ? 'Connected' : 'Waiting for connection...';
      case CallState.disconnected:
        return 'Disconnected';
      default:
        return '';
    }
  }
}