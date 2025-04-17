import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';
import 'package:techniq8chat/services/webrtc_service.dart';
import 'package:techniq8chat/services/auth_service.dart';
import 'package:wakelock_plus/wakelock_plus.dart';



class CallScreen extends StatefulWidget {
  final String userId;
  final String userName;
  final String? profilePicture;
  final CallType callType;
  final bool isOutgoing;

  const CallScreen({
    Key? key,
    required this.userId,
    required this.userName,
    this.profilePicture,
    required this.callType,
    required this.isOutgoing,
  }) : super(key: key);

  @override
  _CallScreenState createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  // WebRTC service instance
  late final WebRTCService _webRTCService;
  
  // Stream renderers
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();
  
  // Call settings
  bool _micEnabled = true;
  bool _speakerEnabled = true;
  bool _cameraEnabled = true;
  
  // UI states
  String _callStatus = '';
  bool _isCallConnected = false;
  Timer? _callTimer;
  String _callDuration = '00:00';
  
  @override
  void initState() {
    super.initState();
     final authService = Provider.of<AuthService>(context, listen: false);
    final currentUser = authService.currentUser;
    
    if (currentUser == null) {
      // Handle error: no current user
      Navigator.of(context).pop();
      return;
    }
    _webRTCService = WebRTCService();
    _webRTCService.setCurrentUser(currentUser);
    
    // Initialize renderers
    _initRenderers();
    
    // Enable wakelock to keep screen on during call
    // Wakelock.enable();
    
    // Set up listeners
    _setupListeners();
    
    // Start outgoing call if needed
    if (widget.isOutgoing) {
      _startOutgoingCall();
    }
  }
  
  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }
  
  void _setupListeners() {
    // Call state listener
    _webRTCService.onCallStateChanged.listen((state) {
      setState(() {
        switch (state) {
          case CallState.idle:
            _callStatus = 'Idle';
            _isCallConnected = false;
            break;
          case CallState.calling:
            _callStatus = 'Calling...';
            _isCallConnected = false;
            break;
          case CallState.ringing:
            _callStatus = 'Ringing...';
            _isCallConnected = false;
            break;
          case CallState.connected:
            _callStatus = 'Connected';
            _isCallConnected = true;
            _startCallTimer();
            break;
          case CallState.ended:
            _callStatus = 'Call ended';
            _isCallConnected = false;
            _stopCallTimer();
            _navigateBack();
            break;
          case CallState.busy:
            _callStatus = 'User is busy';
            _isCallConnected = false;
            Future.delayed(Duration(seconds: 2), _navigateBack);
            break;
          case CallState.rejected:
            _callStatus = 'Call rejected';
            _isCallConnected = false;
            Future.delayed(Duration(seconds: 2), _navigateBack);
            break;
          case CallState.notAnswered:
            _callStatus = 'No answer';
            _isCallConnected = false;
            Future.delayed(Duration(seconds: 2), _navigateBack);
            break;
        }
      });
    });
    
    // Local stream listener
    _webRTCService.onLocalStream.listen((stream) {
      if (stream != null) {
        setState(() {
          _localRenderer.srcObject = stream;
        });
      }
    });
    
    // Remote stream listener
    _webRTCService.onRemoteStream.listen((stream) {
      if (stream != null) {
        setState(() {
          _remoteRenderer.srcObject = stream;
        });
      }
    });
  }
  
  Future<void> _startOutgoingCall() async {
    // Wait for the widget to be properly initialized
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final success = await _webRTCService.initiateCall(
        widget.userId,
        widget.callType,
      );
      
      if (!success && mounted) {
        // Show error message and close screen
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start call')),
        );
        
        Navigator.of(context).pop();
      }
    });
  }
  
  void _startCallTimer() {
    _callTimer?.cancel();
    _callTimer = Timer.periodic(Duration(seconds: 1), (_) {
      if (mounted) {
        final duration = _webRTCService.callDuration;
        final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
        final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
        
        setState(() {
          if (duration.inHours > 0) {
            final hours = duration.inHours.toString().padLeft(2, '0');
            _callDuration = '$hours:$minutes:$seconds';
          } else {
            _callDuration = '$minutes:$seconds';
          }
        });
      }
    });
  }
  
  void _stopCallTimer() {
    _callTimer?.cancel();
    _callTimer = null;
  }
  
  void _navigateBack() {
    if (mounted) {
      Future.delayed(Duration(milliseconds: 500), () {
        Navigator.of(context).pop();
      });
    }
  }
  
  void _toggleMicrophone() {
    setState(() {
      _micEnabled = !_micEnabled;
      _webRTCService.toggleMicrophone(!_micEnabled);
    });
  }
  
  void _toggleCamera() {
    setState(() {
      _cameraEnabled = !_cameraEnabled;
      _webRTCService.toggleVideo(_cameraEnabled);
    });
  }
  
  void _switchCamera() {
    _webRTCService.toggleCamera();
  }
  
  void _toggleSpeaker() {
    setState(() {
      _speakerEnabled = !_speakerEnabled;
      // Implement speaker toggle logic here
      // This requires adjusting audio output which is platform-specific
    });
  }
  
  void _endCall() {
    _webRTCService.endCall();
  }
  
  void _acceptCall() {
    _webRTCService.acceptIncomingCall();
  }
  
  void _rejectCall() {
    _webRTCService.rejectIncomingCall();
    Navigator.of(context).pop();
  }
  
  @override
  void dispose() {
    _stopCallTimer();
    // Wakelock.disable();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    
    // Note: We don't dispose WebRTCService here because it's a singleton
    // The service handles its internal cleanup on call end
    
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isVideoCall = widget.callType == CallType.video;
    
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Video views (only for video calls)
          if (isVideoCall) ...[
            // Remote video (fullscreen)
            if (_isCallConnected)
              RTCVideoView(
                _remoteRenderer,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              )
            else
              Container(color: Colors.black),
              
            // Local video (small picture-in-picture)
            if (_cameraEnabled)
              Positioned(
                right: 16,
                top: 80,
                width: screenSize.width * 0.3,
                height: screenSize.width * 0.4,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white38, width: 1),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: RTCVideoView(
                      _localRenderer,
                      mirror: true,
                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    ),
                  ),
                ),
              ),
          ],
          
          // Audio call UI
          if (!isVideoCall)
            Container(
              width: double.infinity,
              height: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF2A64F6),
                    const Color(0xFF2A64F6).withOpacity(0.5),
                  ],
                ),
              ),
            ),
            
          // Call info overlay
          SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Top area: user info
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      SizedBox(height: 20),
                      
                      // Profile picture or avatar
                      CircleAvatar(
                        radius: 40,
                        backgroundColor: Colors.grey[300],
                        backgroundImage: widget.profilePicture != null && widget.profilePicture!.isNotEmpty
                            ? NetworkImage('http://192.168.100.5:4400/${widget.profilePicture}')
                            : null,
                        child: (widget.profilePicture == null || widget.profilePicture!.isEmpty)
                            ? Text(
                                widget.userName.isNotEmpty 
                                    ? widget.userName[0].toUpperCase()
                                    : '?',
                                style: TextStyle(
                                  fontSize: 36,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue[700],
                                ),
                              )
                            : null,
                      ),
                      SizedBox(height: 16),
                      
                      // User name
                      Text(
                        widget.userName,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
                      
                      // Call status
                      Text(
                        _isCallConnected ? _callDuration : _callStatus,
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Bottom area: call controls
                Column(
                  children: [
                    if (!widget.isOutgoing && _webRTCService.callState == CallState.ringing)
                      // Incoming call controls
                      Padding(
                        padding: const EdgeInsets.only(bottom: 40.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            // Reject button
                            FloatingActionButton(
                              heroTag: 'reject',
                              backgroundColor: Colors.red,
                              child: Icon(Icons.call_end, color: Colors.white),
                              onPressed: _rejectCall,
                            ),
                            SizedBox(width: 80),
                            // Accept button
                            FloatingActionButton(
                              heroTag: 'accept',
                              backgroundColor: Colors.green,
                              child: Icon(Icons.call, color: Colors.white),
                              onPressed: _acceptCall,
                            ),
                          ],
                        ),
                      )
                    else
                      // Active call controls
                      Padding(
                        padding: const EdgeInsets.only(bottom: 40.0),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                // Microphone toggle
                                _buildCallControlButton(
                                  icon: _micEnabled ? Icons.mic : Icons.mic_off,
                                  label: _micEnabled ? 'Mute' : 'Unmute',
                                  onPressed: _toggleMicrophone,
                                ),
                                
                                // End call
                                FloatingActionButton(
                                  heroTag: 'endCall',
                                  backgroundColor: Colors.red,
                                  child: Icon(Icons.call_end, color: Colors.white),
                                  onPressed: _endCall,
                                ),
                                
                                // Speaker toggle
                                _buildCallControlButton(
                                  icon: _speakerEnabled ? Icons.volume_up : Icons.volume_down,
                                  label: _speakerEnabled ? 'Speaker' : 'Earpiece',
                                  onPressed: _toggleSpeaker,
                                ),
                              ],
                            ),
                            
                            // Video call specific controls
                            if (isVideoCall)
                              Padding(
                                padding: const EdgeInsets.only(top: 16.0),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                  children: [
                                    // Camera toggle
                                    _buildCallControlButton(
                                      icon: _cameraEnabled ? Icons.videocam : Icons.videocam_off,
                                      label: _cameraEnabled ? 'Camera Off' : 'Camera On',
                                      onPressed: _toggleCamera,
                                    ),
                                    
                                    // Switch camera
                                    _buildCallControlButton(
                                      icon: Icons.flip_camera_ios,
                                      label: 'Flip',
                                      onPressed: _switchCamera,
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildCallControlButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton(
          heroTag: label,
          backgroundColor: Colors.white24,
          child: Icon(icon, color: Colors.white),
          onPressed: onPressed,
          mini: true,
        ),
        SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }
}