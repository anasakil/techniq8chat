import 'dart:async';
import 'package:flutter/material.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:techniq8chat/services/auth_service.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:provider/provider.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:shared_preferences/shared_preferences.dart';

class TestAgoraCallScreen extends StatefulWidget {
  @override
  _TestAgoraCallScreenState createState() => _TestAgoraCallScreenState();
}

class _TestAgoraCallScreenState extends State {
  // Agora SDK constants
  final String appId = 'd35effd01b264bac87f3e87a973d92a9';
  final String baseUrl = 'http://192.168.100.83:4400';
  
  // UI state variables
  bool _isConnectedToServer = false;
  bool _isInCall = false;
  bool _localUserJoined = false;
  bool _remoteUserJoined = false;
  bool _isMuted = false;
  bool _isCameraOff = false;
  String _connectionStatus = 'Disconnected';
  String _callStatus = 'Idle';

  // User data variables
  String _userId = '';
  String _username = '';
  String? _token; 
  List _onlineUsers = [];
  String? _selectedUserId;
  String? _selectedUsername;
  String? _callerId;

  // Socket for signaling
  IO.Socket? _socket;

  // Agora engine instance
  RtcEngine? _engine;
  String? _channelName;
  String? _agoraToken;
  int? _uid;
  String _callType = 'audio'; // Default call type

  // Current call variables
  String? _currentCallId;
  Timer? _callTimer;
  int _callDuration = 0;
  bool _isReceivingCall = false;

  @override
  void initState() {
    super.initState();
    _loadTokenAndInitialize();
  }

  @override
  void dispose() {
    // Clean up resources
    _disposeAgora();
    _disconnectSocket();
    _callTimer?.cancel();
    super.dispose();
  }

  // Load token from SharedPreferences and initialize
  Future _loadTokenAndInitialize() async {
    try {
      // Get token from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final userData = prefs.getString('user_data');
      
      if (userData == null || userData.isEmpty) {
        setState(() {
          _token = null;
          _connectionStatus = 'Not Authenticated';
        });
        return;
      }
      
      // Parse the user data JSON
      final userJson = json.decode(userData);
      
      // Extract token and user information
      _token = userJson['token'];
      _userId = userJson['_id'] ?? '';
      _username = userJson['username'] ?? 'User';
      
      if (_token == null || _token!.isEmpty) {
        return;
      }
      
      // Initialize with loaded token
      await _initializeWithToken(_token!);
      
    } catch (e) {
      setState(() {
        _token = null;
        _connectionStatus = 'Authentication Error';
      });
    }
  }
  
  // Initialize with token
  Future _initializeWithToken(String token) async {
    try {
      // Initialize permissions
      await _initPermissions();

      // Connect to socket server
      _connectToSocket(token);

      // Initialize Agora engine
      await _initAgoraEngine();

      // Fetch users with token
      _fetchOnlineUsers();
    } catch (e) {
      // Handle initialization error
    }
  }

  // Initialize necessary permissions
  Future _initPermissions() async {
    // Request microphone and camera permissions
    await [
      Permission.microphone,
      Permission.camera,
    ].request();
  }

  // Connect to socket for signaling
  void _connectToSocket(String token) {
    _socket = IO.io(baseUrl, {
      'transports': ['websocket'],
      'autoConnect': true,
      'query': {'token': token},
      'reconnection': true,
      'reconnectionDelay': 1000,
      'reconnectionDelayMax': 5000,
      'reconnectionAttempts': 10
    });

    _setupSocketListeners();
  }

  // Setup socket event listeners
  void _setupSocketListeners() {
    _socket?.onConnect((_) {
      setState(() {
        _isConnectedToServer = true;
        _connectionStatus = 'Connected';
      });

      // Register user as connected
      _socket?.emit('user_connected', _userId);

      // Fetch online users after connection
      _fetchOnlineUsers();
    });

    _socket?.onDisconnect((_) {
      setState(() {
        _isConnectedToServer = false;
        _connectionStatus = 'Disconnected';
      });
    });

    _socket?.onConnectError((error) {
      setState(() {
        _isConnectedToServer = false;
        _connectionStatus = 'Connection Error';
      });
    });

    // Handle incoming calls
    _socket?.on('incoming_call', (data) {
      setState(() {
        _isReceivingCall = true;
        _callerId = data['callerId'];
        _currentCallId = data['callId'];
        _callType = data['callType'];
        _callStatus = 'Incoming call...';
      });

      // Show incoming call UI
      _showIncomingCallDialog(
          data['callerName'] ?? 'Unknown', data['callType']);
    });

    // Handle call status updates
    _socket?.on('call_status_update', (data) {
      if (data['status'] == 'ended') {
        _endCall(false); // False means don't send the end call signal again
      }
    });

    // WebRTC signaling messages
    _socket?.on('webrtc_offer', (data) {
      // In a real implementation, this would handle the WebRTC offer
    });

    _socket?.on('webrtc_answer', (data) {
      // In a real implementation, this would handle the WebRTC answer
    });

    _socket?.on('webrtc_ice_candidate', (data) {
      // In a real implementation, this would handle the ICE candidate
    });

    _socket?.on('webrtc_end_call', (data) {
      _endCall(false);
    });

    _socket?.on('webrtc_call_rejected', (data) {
      setState(() {
        _callStatus = 'Call rejected';
        _isInCall = false;
      });

      // Clean up Agora resources
      _leaveChannel();
    });

    // Listen for user status updates
    _socket?.on('user_status', (data) {
      // Refresh online users list
      _fetchOnlineUsers();
    });
  }

  // Initialize Agora engine
  Future _initAgoraEngine() async {
    try {
      // Create RTC engine instance
      _engine = createAgoraRtcEngine();
      if (_engine == null) {
        throw Exception('Failed to create Agora RTC engine');
      }

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
          // Handle errors
        },
      ));
    } catch (e) {
      _engine = null; // Reset engine on failure
    }
  }

  // Event handler when successfully joined the channel
  void _onJoinChannelSuccess(RtcConnection connection, int elapsed) {
    setState(() {
      _localUserJoined = true;
      _callStatus = 'Connected';
    });
  }

  // Event handler when a remote user joins the channel
  void _onUserJoined(RtcConnection connection, int remoteUid, int elapsed) {
    setState(() {
      _remoteUserJoined = true;
      _callStatus = 'In call';

      // Start call timer
      _startCallTimer();
    });
  }

  // Event handler when a remote user leaves the channel
  void _onUserOffline(
      RtcConnection connection, int remoteUid, UserOfflineReasonType reason) {
    setState(() {
      _remoteUserJoined = false;
    });

    // End the call since the remote user left
    _endCall(false);
  }

  // Fetch online users
  void _fetchOnlineUsers() async {
    try {
      if (_token == null || _token!.isEmpty) {
        return;
      }

      final response = await http.get(
        Uri.parse('$baseUrl/api/users/all'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token',
        },
      );

      if (response.statusCode == 200) {
        final List users = json.decode(response.body);

        setState(() {
          _onlineUsers = users.where((user) => user['_id'] != _userId).toList();
        });
      }
    } catch (e) {
      // Handle error
    }
  }

  // Initiate a call
  Future _initiateCall(String callType) async {
    if (_selectedUserId == null) {
      return;
    }

    try {
      // Check if token is available
      if (_token == null || _token!.isEmpty) {
        return;
      }

      // Create call record via API
      final callResponse = await http.post(
        Uri.parse('$baseUrl/api/calls'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token',
        },
        body: json.encode({
          'receiverId': _selectedUserId,
          'callType': callType,
          'status': 'initiated'
        }),
      );

      if (callResponse.statusCode != 201) {
        throw Exception(
            'Failed to create call record: ${callResponse.statusCode} - ${callResponse.body}');
      }

      final callData = json.decode(callResponse.body);
      final callId = callData['callId'];
      if (callId == null) {
        throw Exception('Call ID not returned from server');
      }

      _currentCallId = callId;

      // Get Agora token from server
      final tokenResponse = await http.post(
        Uri.parse('$baseUrl/api/calls/agora-token'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token',
        },
        body: json.encode({
          'channelName': _currentCallId,
          'uid': 0, // Server will assign a UID
        }),
      );

      final tokenData = json.decode(tokenResponse.body);

      // Check if token exists
      if (tokenData['token'] == null) {
        throw Exception(
            'Token field missing in response: ${tokenResponse.body}');
      }

      // Set the token from the response
      _agoraToken = tokenData['token'];
      // Use the current call ID as channel name
      _channelName = _currentCallId;
      // Use 0 as the default UID for local user
      _uid = 0;

      // Check if engine is initialized
      if (_engine == null) {
        throw Exception('Agora engine not initialized');
      }

      // Set role as host
      await _engine?.setClientRole(role: ClientRoleType.clientRoleBroadcaster);

      // Set up audio/video based on call type
      await _engine?.enableAudio();
      if (callType == 'video') {
        await _engine?.enableVideo();
      }

      // Join the channel - make sure all values are non-null
      if (_agoraToken == null || _channelName == null || _uid == null) {
        throw Exception('Missing required call parameters');
      }

      await _engine?.joinChannel(
          token: _agoraToken!,
          channelId: _channelName!,
          uid: _uid!,
          options: ChannelMediaOptions(
            clientRoleType: ClientRoleType.clientRoleBroadcaster,
            channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
          ));

      // Send call signal to receiver via socket
      if (_socket != null) {
        _socket?.emit('webrtc_offer', {
          'receiverId': _selectedUserId,
          'callType': callType,
          'callId': callId
        });
      }

      setState(() {
        _isInCall = true;
        _callType = callType;
        _callStatus = 'Calling...';
      });
    } catch (e) {
      setState(() {
        _callStatus = 'Call failed';
      });
    }
  }

  // Accept incoming call
  Future<void> _acceptCall() async {
    try {
      if (_callerId == null || _currentCallId == null) {
        return;
      }

      // Check if token is available
      if (_token == null || _token!.isEmpty) {
        return;
      }

      // Update call status
      await http.put(
        Uri.parse('$baseUrl/api/calls/$_currentCallId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token',
        },
        body: json.encode({'status': 'connected'}),
      );

      // Get Agora token for incoming call - THIS PART IS MISSING
      final tokenResponse = await http.post(
        Uri.parse('$baseUrl/api/calls/agora-token'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token',
        },
        body: json.encode({
          'channelName': _currentCallId,
          'uid': 0,
        }),
      );

      final tokenData = json.decode(tokenResponse.body);

      // Check if token exists
      if (tokenData['token'] == null) {
        throw Exception('Token field missing in response: ${tokenResponse.body}');
      }

      // Set the token from the response
      _agoraToken = tokenData['token'];
      // Use the current call ID as channel name
      _channelName = _currentCallId;
      // Use 0 as the default UID for local user
      _uid = 0;

      // Set role as host
      await _engine?.setClientRole(role: ClientRoleType.clientRoleBroadcaster);

      // Set up audio/video based on call type
      await _engine?.enableAudio();
      if (_callType == 'video') {
        await _engine?.enableVideo();
        // Set up local video view
        _engine?.setupLocalVideo(VideoCanvas(
          uid: 0,
          view: null, // Will be set after UI is built
          renderMode: RenderModeType.renderModeHidden,
        ));
      }

      // Join the channel
      await _engine?.joinChannel(
        token: _agoraToken!,
        channelId: _channelName!,
        uid: _uid!,
        options: ChannelMediaOptions(
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
        )
      );

      // Notify the caller that we answered
      _socket?.emit('call_answered', {'callerId': _callerId, 'callId': _currentCallId});

      setState(() {
        _isReceivingCall = false;
        _isInCall = true;
        _callStatus = 'Connected';
      });
    } catch (e) {
      setState(() {
        _isReceivingCall = false;
        _callStatus = 'Call failed';
      });
    }
  }

  // Reject incoming call
  void _rejectCall() {
    if (_callerId == null || _currentCallId == null) {
      return;
    }

    // Update call status
    http.put(
      Uri.parse('$baseUrl/api/calls/$_currentCallId'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      },
      body: json.encode({'status': 'rejected'}),
    );

    // Notify the caller about rejection
    _socket?.emit('webrtc_reject_call', {'callerId': _callerId});

    setState(() {
      _isReceivingCall = false;
      _callStatus = 'Call rejected';
      _callerId = null;
      _currentCallId = null;
    });
  }

  // End the current call
  void _endCall([bool notifyRemote = true]) {
    // Stop call timer
    _callTimer?.cancel();

    if (notifyRemote && _isInCall) {
      // Update call status on the server
      if (_currentCallId != null) {
        http.put(
          Uri.parse('$baseUrl/api/calls/$_currentCallId'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $_token',
          },
          body: json.encode({'status': 'ended'}),
        );
      }

      // Notify the remote peer that we're ending the call
      String? remoteUserId = _callerId ?? _selectedUserId;
      if (remoteUserId != null) {
        _socket?.emit('webrtc_end_call', {'receiverId': remoteUserId});
      }
    }

    // Leave the Agora channel
    _leaveChannel();

    setState(() {
      _isInCall = false;
      _localUserJoined = false;
      _remoteUserJoined = false;
      _callStatus = 'Call ended';
      _callDuration = 0;
      _currentCallId = null;
      _callerId = null;
    });
  }

  // Leave the Agora channel
  Future<void> _leaveChannel() async {
    try {
      await _engine?.leaveChannel();
    } catch (e) {
      // Handle error
    }
  }

  // Toggle microphone mute state
  void _toggleMute() async {
    if (_engine != null) {
      setState(() {
        _isMuted = !_isMuted;
      });

      await _engine?.muteLocalAudioStream(_isMuted);
    }
  }

  // Toggle camera state
  void _toggleCamera() async {
    if (_engine != null && _callType == 'video') {
      setState(() {
        _isCameraOff = !_isCameraOff;
      });

      await _engine?.muteLocalVideoStream(_isCameraOff);
    }
  }

  // Switch between front and back camera
  void _switchCamera() async {
    if (_engine != null && _callType == 'video') {
      await _engine?.switchCamera();
    }
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

  // Format call duration
  String _formatDuration(int seconds) {
    int minutes = seconds ~/ 60;
    int remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  // Show incoming call dialog
  void _showIncomingCallDialog(String callerName, String callType) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Color(0xFF0084FF).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    callType == 'video' ? Icons.videocam : Icons.call,
                    size: 40,
                    color: Color(0xFF0084FF),
                  ),
                ),
                SizedBox(height: 20),
                Text(
                  'Incoming ${callType.toUpperCase()} Call',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  callerName,
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey[700],
                  ),
                ),
                SizedBox(height: 30),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    GestureDetector(
                      onTap: () {
                        Navigator.of(context).pop();
                        _rejectCall();
                      },
                      child: Container(
                        padding: EdgeInsets.all(15),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.call_end,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        Navigator.of(context).pop();
                        _acceptCall();
                      },
                      child: Container(
                        padding: EdgeInsets.all(15),
                        decoration: BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          callType == 'video' ? Icons.videocam : Icons.call,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Clean up Agora resources
  void _disposeAgora() {
    _engine?.leaveChannel();
    _engine?.release();
  }

  // Disconnect socket
  void _disconnectSocket() {
    _socket?.disconnect();
    _socket?.dispose(    );
  }

  // UI for active call
  Widget _buildCallUI() {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 32),
          onPressed: () => _endCall(true),
        ),
        title: Column(
          children: [
            Text(
              _selectedUsername ?? _callerId ?? 'Unknown',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              _remoteUserJoined ? 'Connected' : 'Connecting...',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: Container(
        color: Colors.black,
        child: Stack(
          children: [
            // Remote video (full screen)
            if (_callType == 'video')
              Center(
                child: _remoteUserJoined
                  ? AgoraVideoView(
                      controller: VideoViewController.remote(
                        rtcEngine: _engine!,
                        canvas: VideoCanvas(uid: 1),
                        connection: RtcConnection(channelId: _channelName!),
                      ),
                    )
                  : Container(
                      color: Colors.black,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 120,
                              height: 120,
                              decoration: BoxDecoration(
                                color: Color(0xFF0084FF).withOpacity(0.2),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Icon(
                                  Icons.videocam_off,
                                  size: 40,
                                  color: Colors.white70,
                                ),
                              ),
                            ),
                            SizedBox(height: 16),
                            Text(
                              'Waiting for video...',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
              ),

            // Local video (small picture-in-picture)
            if (_callType == 'video' && _localUserJoined)
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

            // Audio call UI
            if (_callType == 'audio')
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: Color(0xFF0084FF).withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          (_selectedUsername ?? _callerId ?? '?')[0].toUpperCase(),
                          style: TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 24),
                    if (_callDuration > 0)
                      Text(
                        _formatDuration(_callDuration),
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.white70,
                        ),
                      ),
                  ],
                ),
              ),

            // Call controls (bottom)
            Positioned(
              left: 0,
              right: 0,
              bottom: 40,
              child: Column(
                children: [
                  // Call duration
                  if (_callDuration > 0 && _callType == 'video')
                    Padding(
                      padding: EdgeInsets.only(bottom: 20),
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _formatDuration(_callDuration),
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  // Control buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildRoundControlButton(
                        icon: _isMuted ? Icons.mic_off : Icons.mic,
                        backgroundColor: _isMuted ? Colors.white12 : Colors.white24,
                        onPressed: _toggleMute,
                        label: _isMuted ? 'Unmute' : 'Mute',
                      ),
                      _buildRoundControlButton(
                        icon: Icons.call_end,
                        backgroundColor: Colors.red,
                        size: 65,
                        iconSize: 30,
                        onPressed: () => _endCall(true),
                        label: 'End',
                      ),
                      _callType == 'video'
                        ? _buildRoundControlButton(
                            icon: _isCameraOff ? Icons.videocam_off : Icons.videocam,
                            backgroundColor: _isCameraOff ? Colors.white12 : Colors.white24,
                            onPressed: _toggleCamera,
                            label: _isCameraOff ? 'Camera On' : 'Camera Off',
                          )
                        : _buildRoundControlButton(
                            icon: Icons.volume_up,
                            backgroundColor: Colors.white24,
                            onPressed: () {}, // Volume control
                            label: 'Speaker',
                          ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper to build round control buttons
  Widget _buildRoundControlButton({
    required IconData icon,
    required Color backgroundColor,
    required VoidCallback onPressed,
    required String label,
    double size = 55,
    double iconSize = 24,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: backgroundColor,
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: Icon(icon, size: iconSize),
            color: Colors.white,
            onPressed: onPressed,
          ),
        ),
        SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: Colors.white70,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return _isInCall 
      ? _buildCallUI() 
      : Scaffold(
          appBar: AppBar(
            title: Text(
              'Contacts',
              style: TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.bold,
              ),
            ),
            backgroundColor: Colors.white,
            elevation: 0,
            actions: [
              IconButton(
                icon: Icon(Icons.refresh, color: Color(0xFF0084FF)),
                onPressed: _fetchOnlineUsers,
                tooltip: 'Refresh',
              ),
            ],
          ),
          body: _buildContactSelection(),
        );
        
  
  }

  // UI for user selection and call initiation
  Widget _buildContactSelection() {
    return Column(
      children: [
        // Status bar
        if (!_isConnectedToServer || _token == null || _token!.isEmpty)
          // Container(
          //   padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          //   color: Colors.amber.shade100,
          //   child: Row(
          //     children: [
          //       Icon(
          //         Icons.info_outline,
          //         color: Colors.amber.shade800,
          //         size: 20,
          //       ),
          //       SizedBox(width: 8),
          //       Expanded(
          //         child: Text(
          //           _token == null || _token!.isEmpty
          //             ? 'Sign in required to make calls'
          //             : 'Connecting to server...',
          //           style: TextStyle(color: Colors.amber.shade800),
          //         ),
          //       ),
          //     ],
          //   ),
          // ),

        
        Expanded(
          child: _onlineUsers.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.people_outline,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      SizedBox(height: 16),
                      Text(
                        'No contacts available',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _onlineUsers.length,
                  itemBuilder: (context, index) {
                    final user = _onlineUsers[index];
                    final isSelected = _selectedUserId == user['_id'];
                    final isOnline = user['status'] == 'online';

                    return Container(
                      decoration: BoxDecoration(
                        color: isSelected ? Color(0xFF0084FF).withOpacity(0.05) : Colors.white,
                        border: Border(
                          bottom: BorderSide(color: Colors.grey.shade200, width: 0.5),
                        ),
                      ),
                      child: ListTile(
                        leading: Stack(
                          children: [
                            CircleAvatar(
                              backgroundColor: Color(0xFF0084FF).withOpacity(0.1),
                              radius: 24,
                              child: Text(
                                user['username'][0].toUpperCase(),
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0084FF),
                                ),
                              ),
                            ),
                            if (isOnline)
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: Colors.green,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 2),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        title: Text(
                          user['username'],
                          style: TextStyle(
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            fontSize: 16,
                          ),
                        ),
                        subtitle: Text(
                          isOnline ? 'Online' : 'Offline',
                          style: TextStyle(
                            color: isOnline ? Colors.green : Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildCallActionButton(
                              icon: Icons.call,
                              color: Color(0xFF0084FF),
                              onPressed: () {
                                setState(() {
                                  _selectedUserId = user['_id'];
                                  _selectedUsername = user['username'];
                                  _callType = 'audio';
                                });
                                _initiateCall('audio');
                              },
                            ),
                            SizedBox(width: 8),
                            _buildCallActionButton(
                              icon: Icons.videocam,
                              color: Color(0xFF0084FF),
                              onPressed: () {
                                setState(() {
                                  _selectedUserId = user['_id'];
                                  _selectedUsername = user['username'];
                                  _callType = 'video';
                                });
                                _initiateCall('video');
                              },
                            ),
                          ],
                        ),
                        onTap: () {
                          setState(() {
                            _selectedUserId = user['_id'];
                            _selectedUsername = user['username'];
                          });
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // Call type selection button
  Widget _buildCallTypeButton({
    required String callType,
    required IconData icon,
    required String label,
  }) {
    final isSelected = _callType == callType;
    
    return GestureDetector(
      onTap: () {
        setState(() {
          _callType = callType;
        });
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Color(0xFF0084FF) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? Colors.white : Colors.grey[700],
            ),
            SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.grey[700],
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Call action button
  Widget _buildCallActionButton({
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(50),
      child: Container(
        padding: EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: color,
          size: 20,
        ),
      ),
    );
  }
}