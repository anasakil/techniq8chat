// screens/enhanced_call_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:techniq8chat/services/auth_service.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:provider/provider.dart';

class EnhancedCallScreen extends StatefulWidget {
  final String remoteUserId;
  final String remoteUsername;
  final String? profilePicture;
  final String callType;
  final bool isIncoming;

  const EnhancedCallScreen({
    Key? key,
    required this.remoteUserId,
    required this.remoteUsername,
    this.profilePicture,
    required this.callType,
    this.isIncoming = false,
  }) : super(key: key);

  @override
  _EnhancedCallScreenState createState() => _EnhancedCallScreenState();
}

class _EnhancedCallScreenState extends State<EnhancedCallScreen> with SingleTickerProviderStateMixin {
  // Agora SDK constants
  final String appId = 'd35effd01b264bac87f3e87a973d92a9';
  final String baseUrl = 'http://192.168.100.83:4400';
  
  // UI state variables
  bool _isInCall = false;
  bool _localUserJoined = false;
  bool _remoteUserJoined = false;
  bool _isMuted = false;
  bool _isCameraOff = false;
  bool _isSpeakerOn = false;
  String _callStatus = 'Connecting...';

  // Call data variables
  String? _token;
  String? _channelName;
  String? _agoraToken;
  int? _uid = 0;
  bool _isInitialized = false;

  // Agora engine instance
  RtcEngine? _engine;
  
  // Call timer
  Timer? _callTimer;
  int _callDuration = 0;

  // Animation controller for call buttons
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    
    // Initialize animation controller
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.9).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    
    // Initialize the call
    _initializeCall();
  }

  @override
  void dispose() {
    // Clean up resources
    _disposeAgora();
    _callTimer?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  // Initialize the call
  Future<void> _initializeCall() async {
    try {
      // Get token from AuthService
      final authService = Provider.of<AuthService>(context, listen: false);
      _token = authService.currentUser?.token;
      
      if (_token == null) {
        _showErrorMessage('Authentication error');
        return;
      }
      
      // Initialize permissions
      await _initPermissions();

      // Initialize Agora engine
      await _initAgoraEngine();
      
      // Setup call based on incoming or outgoing
      if (widget.isIncoming) {
        await _setupIncomingCall();
      } else {
        await _initiateOutgoingCall();
      }
      
      setState(() {
        _isInitialized = true;
      });
    } catch (e) {
      _showErrorMessage('Failed to initialize call: $e');
    }
  }

  // Initialize necessary permissions
  Future<void> _initPermissions() async {
    List<Permission> permissions = [Permission.microphone];
    
    // Add camera permission for video calls
    if (widget.callType == 'video') {
      permissions.add(Permission.camera);
    }
    
    // Request permissions
    await permissions.request();
  }

  // Initialize Agora engine
  Future<void> _initAgoraEngine() async {
    try {
      // Create RTC engine instance
      _engine = createAgoraRtcEngine();
      await _engine?.initialize(RtcEngineContext(
        appId: appId,
        channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
      ));

      // Setup event handlers
      _engine?.registerEventHandler(RtcEngineEventHandler(
        onJoinChannelSuccess: _onJoinChannelSuccess,
        onUserJoined: _onUserJoined,
        onUserOffline: _onUserOffline,
        onError: (err, msg) {
          print('Agora error: $err - $msg');
        },
      ));
      
      // Enable audio for all calls
      await _engine?.enableAudio();
      
      // Enable video for video calls only
      if (widget.callType == 'video') {
        await _engine?.enableVideo();
      }
      
      // Set client role as broadcaster
      await _engine?.setClientRole(role: ClientRoleType.clientRoleBroadcaster);
      
      print('Agora engine initialized successfully');
    } catch (e) {
      print('Error initializing Agora engine: $e');
      throw Exception('Failed to initialize Agora engine: $e');
    }
  }

  // Setup for incoming call
  Future<void> _setupIncomingCall() async {
    try {
      // For incoming calls, we should already have a channel name from the socket event
      // Here we'll use the remoteUserId as placeholder - in a real app, get this from socket
      _channelName = 'call_${widget.remoteUserId}_${DateTime.now().millisecondsSinceEpoch}';
      
      // Get Agora token
      await _getAgoraToken();
      
      // Join the channel
      await _joinChannel();
      
      setState(() {
        _isInCall = true;
        _callStatus = 'Connecting...';
      });
    } catch (e) {
      print('Error setting up incoming call: $e');
      throw Exception('Failed to setup incoming call: $e');
    }
  }

  // Initiate outgoing call
  Future<void> _initiateOutgoingCall() async {
    try {
      // Create call record via API
      final callResponse = await http.post(
        Uri.parse('$baseUrl/api/calls'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token',
        },
        body: json.encode({
          'receiverId': widget.remoteUserId,
          'callType': widget.callType,
          'status': 'initiated'
        }),
      );

      if (callResponse.statusCode != 201) {
        throw Exception('Failed to create call record: ${callResponse.statusCode}');
      }

      final callData = json.decode(callResponse.body);
      _channelName = callData['callId'];
      
      if (_channelName == null) {
        throw Exception('Call ID not returned from server');
      }
      
      print('Call record created with ID: $_channelName');
      
      // Get Agora token
      await _getAgoraToken();
      
      // Join the channel
      await _joinChannel();
      
      setState(() {
        _isInCall = true;
        _callStatus = 'Calling...';
      });
    } catch (e) {
      print('Error initiating outgoing call: $e');
      throw Exception('Failed to initiate call: $e');
    }
  }

  // Get Agora token from server
  Future<void> _getAgoraToken() async {
    try {
      final tokenResponse = await http.post(
        Uri.parse('$baseUrl/api/calls/agora-token'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token',
        },
        body: json.encode({
          'channelName': _channelName,
          'uid': 0, // Server will assign a UID
        }),
      );

      final tokenData = json.decode(tokenResponse.body);
      
      if (tokenData['token'] == null) {
        throw Exception('Token field missing in response');
      }

      _agoraToken = tokenData['token'];
      _uid = tokenData['uid'] ?? 0;
      
      print('Agora token obtained: ${_agoraToken?.substring(0, 15)}...');
    } catch (e) {
      print('Error getting Agora token: $e');
      throw Exception('Failed to get Agora token: $e');
    }
  }

  // Join the Agora channel
  Future<void> _joinChannel() async {
    try {
      if (_engine == null || _agoraToken == null || _channelName == null) {
        throw Exception('Missing required call parameters');
      }

      print('Joining channel: $_channelName');
      
      await _engine?.joinChannel(
        token: _agoraToken!,
        channelId: _channelName!,
        uid: _uid!,
        options: ChannelMediaOptions(
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
          publishMicrophoneTrack: true,
          publishCameraTrack: widget.callType == 'video',
        )
      );
    } catch (e) {
      print('Error joining channel: $e');
      throw Exception('Failed to join channel: $e');
    }
  }

  // Event handler when successfully joined the channel
  void _onJoinChannelSuccess(RtcConnection connection, int elapsed) {
    print('Local user joined channel successfully');
    setState(() {
      _localUserJoined = true;
    });
  }

  // Event handler when a remote user joins the channel
  void _onUserJoined(RtcConnection connection, int remoteUid, int elapsed) {
    print('Remote user $remoteUid joined the channel');
    setState(() {
      _remoteUserJoined = true;
      _callStatus = 'Connected';
    });

    // Start call timer
    _startCallTimer();
  }

  // Event handler when a remote user leaves the channel
  void _onUserOffline(RtcConnection connection, int remoteUid, UserOfflineReasonType reason) {
    print('Remote user $remoteUid left the channel');
    setState(() {
      _remoteUserJoined = false;
    });

    // End the call since the remote user left
    _endCall();
  }

  // Start call timer
  void _startCallTimer() {
    _callTimer?.cancel();
    _callTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _callDuration++;
        });
      }
    });
  }

  // End the current call
  void _endCall() {
    _callTimer?.cancel();

    // Update call status on the server
    if (_channelName != null) {
      http.put(
        Uri.parse('$baseUrl/api/calls/$_channelName'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token',
        },
        body: json.encode({'status': 'ended'}),
      );
    }

    // Leave the channel
    _engine?.leaveChannel();

    // Close the screen
    Navigator.of(context).pop();
  }

  // Toggle microphone mute state
  void _toggleMute() {
    if (_engine != null) {
      setState(() {
        _isMuted = !_isMuted;
      });

      _engine?.muteLocalAudioStream(_isMuted);
    }
  }

  // Toggle speaker mode
  void _toggleSpeaker() {
    if (_engine != null) {
      setState(() {
        _isSpeakerOn = !_isSpeakerOn;
      });

      _engine?.setEnableSpeakerphone(_isSpeakerOn);
    }
  }

  // Toggle camera state
  void _toggleCamera() {
    if (_engine != null && widget.callType == 'video') {
      setState(() {
        _isCameraOff = !_isCameraOff;
      });

      _engine?.muteLocalVideoStream(_isCameraOff);
    }
  }

  // Switch between front and back camera
  void _switchCamera() {
    if (_engine != null && widget.callType == 'video') {
      _engine?.switchCamera();
    }
  }

  // Clean up Agora resources
  void _disposeAgora() {
    _engine?.leaveChannel();
    _engine?.release();
  }

  // Show error message
  void _showErrorMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  // Format call duration
  String _formatDuration(int seconds) {
    int minutes = seconds ~/ 60;
    int remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 28),
          onPressed: _endCall,
        ),
        title: Column(
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
              _callStatus,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: _isInitialized 
          ? _buildCallUI()
          : Center(
              child: CircularProgressIndicator(
                color: Colors.white,
              ),
            ),
    );
  }

  // UI for the call screen
  Widget _buildCallUI() {
    return Stack(
      children: [
        // Background - black for audio calls, video feed for video calls
        widget.callType == 'video' 
            ? _buildVideoCallBackground()
            : _buildAudioCallBackground(),
        
        // Call controls overlay (bottom)
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: EdgeInsets.only(top: 20, bottom: 48),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Colors.black.withOpacity(0.7),
                  Colors.transparent,
                ],
              ),
            ),
            child: Column(
              children: [
                // Call duration
                if (_callDuration > 0)
                  Padding(
                    padding: EdgeInsets.only(bottom: 20),
                    child: Text(
                      _formatDuration(_callDuration),
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white,
                      ),
                    ),
                  ),
                
                // Call controls
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildCallControlButton(
                      icon: _isMuted ? Icons.mic_off : Icons.mic,
                      label: _isMuted ? 'Unmute' : 'Mute',
                      isActive: _isMuted,
                      onPressed: _toggleMute,
                    ),
                    _buildCallControlButton(
                      icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_down,
                      label: _isSpeakerOn ? 'Speaker Off' : 'Speaker',
                      isActive: _isSpeakerOn,
                      onPressed: _toggleSpeaker,
                    ),
                    if (widget.callType == 'video')
                      _buildCallControlButton(
                        icon: _isCameraOff ? Icons.videocam_off : Icons.videocam,
                        label: _isCameraOff ? 'Camera On' : 'Camera Off',
                        isActive: _isCameraOff,
                        onPressed: _toggleCamera,
                      )
                    else
                      _buildCallControlButton(
                        icon: Icons.person,
                        label: 'Profile',
                        onPressed: () {
                          // Navigate to user profile
                        },
                      ),
                    _buildEndCallButton(),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // Video call background with remote user's video
  Widget _buildVideoCallBackground() {
    return Stack(
      children: [
        // Remote video (full screen)
        if (_remoteUserJoined)
          Center(
            child: AgoraVideoView(
              controller: VideoViewController.remote(
                rtcEngine: _engine!,
                canvas: VideoCanvas(uid: 1),
                connection: RtcConnection(channelId: _channelName!),
              ),
            ),
          )
        else
          Container(
            color: Colors.black,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: const Color(0xFF2A64F6).withOpacity(0.3),
                    backgroundImage: widget.profilePicture != null 
                        ? NetworkImage('$baseUrl/${widget.profilePicture}')
                        : null,
                    child: widget.profilePicture == null
                        ? Text(
                            widget.remoteUsername[0].toUpperCase(),
                            style: TextStyle(
                              fontSize: 40,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          )
                        : null,
                  ),
                  SizedBox(height: 24),
                  Text(
                    _callStatus,
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Local video (small picture-in-picture)
        if (widget.callType == 'video' && _localUserJoined && !_isCameraOff)
          Positioned(
            right: 16,
            top: 100,
            width: 120,
            height: 160,
            child: GestureDetector(
              onTap: _switchCamera,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: AgoraVideoView(
                    controller: VideoViewController(
                      rtcEngine: _engine!,
                      canvas: const VideoCanvas(uid: 0),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // Audio call background with user avatar
  Widget _buildAudioCallBackground() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF2A64F6),
            Color(0xFF0A3983),
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // User avatar
            Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withOpacity(0.5), width: 4),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 20,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: CircleAvatar(
                backgroundColor: Colors.white.withOpacity(0.2),
                backgroundImage: widget.profilePicture != null 
                    ? NetworkImage('$baseUrl/${widget.profilePicture}')
                    : null,
                child: widget.profilePicture == null
                    ? Text(
                        widget.remoteUsername[0].toUpperCase(),
                        style: TextStyle(
                          fontSize: 70,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      )
                    : null,
              ),
            ),
            SizedBox(height: 30),
            
            // User name
            Text(
              widget.remoteUsername,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 10),
            
            // Call status
            Text(
              _callStatus,
              style: TextStyle(
                fontSize: 16,
                color: Colors.white.withOpacity(0.8),
              ),
            ),
            
            // Call duration
            if (_callDuration > 0)
              Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text(
                  _formatDuration(_callDuration),
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white.withOpacity(0.8),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Call control button with animation
  Widget _buildCallControlButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    bool isActive = false,
  }) {
    return GestureDetector(
      onTap: onPressed,
      onTapDown: (_) => _animationController.forward(),
      onTapUp: (_) => _animationController.reverse(),
      onTapCancel: () => _animationController.reverse(),
      child: AnimatedBuilder(
        animation: _animationController,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: child,
          );
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: isActive 
                    ? Colors.white.withOpacity(0.3)
                    : Colors.white.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: Colors.white,
                size: 24,
              ),
            ),
            SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // End call button
  Widget _buildEndCallButton() {
    return GestureDetector(
      onTap: _endCall,
      onTapDown: (_) => _animationController.forward(),
      onTapUp: (_) => _animationController.reverse(),
      onTapCancel: () => _animationController.reverse(),
      child: AnimatedBuilder(
        animation: _animationController,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: child,
          );
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.red.withOpacity(0.4),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Icon(
                Icons.call_end,
                color: Colors.white,
                size: 28,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'End',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}