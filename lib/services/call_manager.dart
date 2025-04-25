// services/call_manager.dart (UPDATED)
import 'dart:async';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:permission_handler/permission_handler.dart';
import 'package:techniq8chat/services/socket_service.dart';
import 'package:techniq8chat/models/user_model.dart';

enum CallState {
  idle,
  calling,
  connecting,
  connected,
  disconnected,
}

enum CallType {
  audio,
  video
}

class CallManager {
  // Singleton instance
  static CallManager? _instance;
  static CallManager? get instance => _instance;

  // Services and configuration
  final String baseUrl;
  final String agoraAppId = 'd35effd01b264bac87f3e87a973d92a9';
  final User currentUser;
  final SocketService socketService;
  
  // Call state variables
  CallState _callState = CallState.idle;
  CallType _callType = CallType.audio;
  String? _channelId;
  String? _agoraToken;
  int? _uid;
  String? _remoteUserId;
  String? _remoteUsername;
  bool _isInitiator = false;
  bool _isLocalMuted = false;
  bool _isLocalVideoEnabled = true;
  bool _engineInitialized = false;
  
  // Agora engine
  RtcEngine? _engine;
  
  // Call timer
  int _callDuration = 0;
  Timer? _callTimer;
  
  // Streams for state changes
  final _callStateController = StreamController<CallState>.broadcast();
  final _remoteUserJoinedController = StreamController<int>.broadcast();
  final _remoteUserLeftController = StreamController<int>.broadcast();
  final _errorController = StreamController<String>.broadcast();
  final _callDurationController = StreamController<int>.broadcast();
  
  // Stream getters
  Stream<CallState> get onCallStateChanged => _callStateController.stream;
  Stream<int> get onRemoteUserJoined => _remoteUserJoinedController.stream;
  Stream<int> get onRemoteUserLeft => _remoteUserLeftController.stream;
  Stream<String> get onError => _errorController.stream;
  Stream<int> get onCallDurationChanged => _callDurationController.stream;
  
  // State getters
  CallState get callState => _callState;
  CallType get callType => _callType;
  bool get isInCall => _callState != CallState.idle;
  bool get isLocalMuted => _isLocalMuted;
  bool get isLocalVideoEnabled => _isLocalVideoEnabled;
  String? get remoteUserId => _remoteUserId;
  String? get channelId => _channelId;
  RtcEngine? get engine => _engine;
  int get callDuration => _callDuration;
  bool get isInitiator => _isInitiator;
  
  // Factory constructor to maintain singleton instance
  factory CallManager(SocketService socketService, User currentUser, String baseUrl) {
    if (_instance == null) {
      _instance = CallManager._internal(socketService, currentUser, baseUrl);
    }
    return _instance!;
  }
  
  // Internal constructor
  CallManager._internal(this.socketService, this.currentUser, this.baseUrl) {
    print('Creating new CallManager instance');
    _setupSocketListeners();
    _initializeAgoraEngine();
  }
  
  // Initialize Agora engine
  Future<void> _initializeAgoraEngine() async {
    if (_engineInitialized) {
      print('Agora engine already initialized');
      return;
    }
    
    try {
      print('Initializing Agora RTC engine');
      _engine = createAgoraRtcEngine();
      
      await _engine?.initialize(RtcEngineContext(
        appId: agoraAppId,
        channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
      ));
      
      _setupAgoraEventHandlers();
      
      _engineInitialized = true;
      print('Agora engine initialized successfully');
    } catch (e) {
      print('Error initializing Agora engine: $e');
      _errorController.add('Failed to initialize voice/video call system: $e');
    }
  }
  
  // Setup Agora event handlers
  void _setupAgoraEventHandlers() {
    if (_engine == null) return;
    
    print('Setting up Agora event handlers');
    
    _engine?.registerEventHandler(RtcEngineEventHandler(
      onJoinChannelSuccess: (connection, elapsed) {
        print('Local user ${connection.localUid} joined channel ${connection.channelId}');
        if (_callState == CallState.calling || _callState == CallState.connecting) {
          _updateCallState(CallState.connecting);
        }
      },
      onUserJoined: (connection, remoteUid, elapsed) {
        print('Remote user $remoteUid joined channel');
        _remoteUserJoinedController.add(remoteUid);
        _updateCallState(CallState.connected);
        
        // Start call timer when connected
        _startCallTimer();
      },
      onUserOffline: (connection, remoteUid, reason) {
        print('Remote user $remoteUid left channel (reason: $reason)');
        _remoteUserLeftController.add(remoteUid);
        
        // End call if remote user left
        endCall(false);
      },
      onError: (err, msg) {
        print('Agora error: $err - $msg');
        _errorController.add('Call error: $msg');
        
        // Handle critical errors
        if (err == ErrorCodeType.errTokenExpired) {
          endCall(false);
        }
      },
      onConnectionStateChanged: (connection, state, reason) {
        print('Connection state changed: $state, reason: $reason');
        
        // Handle disconnections
        if (state == ConnectionStateType.connectionStateDisconnected || 
            state == ConnectionStateType.connectionStateFailed) {
          if (_callState == CallState.connected) {
            _updateCallState(CallState.disconnected);
          }
        }
      },
      onRejoinChannelSuccess: (connection, elapsed) {
        print('Rejoined channel ${connection.channelId}');
        if (_callState == CallState.disconnected) {
          _updateCallState(CallState.connected);
        }
      },
    ));
  }
  
  // Setup socket listeners for WebRTC signaling
  void _setupSocketListeners() {
    print('Setting up socket listeners for calls');
    
    // Incoming call
    socketService.onWebRTCOffer.listen((data) {
      print('Received WebRTC offer: $data');
      if (!isInCall && data['senderId'] != null) {
        _remoteUserId = data['senderId'];
        _channelId = data['callId'];
        _callType = data['callType'] == 'video' ? CallType.video : CallType.audio;
        _isInitiator = false;
        
        print('Incoming ${_callType.name} call from $_remoteUserId');
        
        // Emit incoming call event which UI can listen to
        _updateCallState(CallState.connecting);
      }
    });
    
    // Call ended remotely
    socketService.onWebRTCEndCall.listen((data) {
      print('Received WebRTC end call event from: $data');
      if (isInCall && data == _remoteUserId) {
        print('Call ended by remote user');
        endCall(false);
      }
    });
    
    // Call rejected
    socketService.onWebRTCCallRejected.listen((data) {
      print('Received WebRTC call rejected event from: $data');
      if (isInCall && data == _remoteUserId) {
        print('Call rejected by remote user');
        _updateCallState(CallState.disconnected);
        endCall(false);
      }
    });
  }
  
  // Start a new call
  Future<bool> startCall(String userId, String username, CallType type) async {
    // Check if already in a call
    if (isInCall) {
      print('Already in a call');
      return false;
    }
    
    try {
      print('Starting ${type.name} call to user: $userId ($username)');
      
      // Request permissions
      final permissionStatus = await _requestPermissions(type);
      if (!permissionStatus) {
        _errorController.add('Call permissions not granted');
        return false;
      }
      
      // Set call parameters
      _remoteUserId = userId;
      _remoteUsername = username;
      _callType = type;
      _isInitiator = true;
      
      // Create a call record on the server
      final callRecord = await _createCallRecord(userId, type.name);
      if (callRecord == null) {
        _errorController.add('Failed to create call record');
        print('ERROR: Failed to create call record on server');
        return false;
      }
      
      _channelId = callRecord['callId'];
      print('Call record created successfully with ID: $_channelId');
      
      // Get Agora token
      final tokenResult = await _getAgoraToken(_channelId!);
      if (!tokenResult) {
        _errorController.add('Failed to get call token');
        print('ERROR: Failed to get Agora token from server');
        return false;
      }
      
      print('Agora token obtained successfully');
      
      // Setup media for the call
      await _setupMediaForCall();
      
      // Join the Agora channel
      final joinSuccess = await _joinChannel();
      if (!joinSuccess) {
        _errorController.add('Failed to join call channel');
        return false;
      }
      
      // Send WebRTC offer to remote user
      socketService.sendWebRTCOffer(
        userId, 
        {'callId': _channelId}, 
        type.name
      );
      
      // Update state
      _updateCallState(CallState.calling);
      
      print('Call started successfully');
      return true;
    } catch (e) {
      print('Error starting call: $e');
      _errorController.add('Failed to start call: $e');
      _resetCallState();
      return false;
    }
  }
  
  // Accept an incoming call
  Future<bool> acceptCall() async {
    if (_callState != CallState.connecting || _channelId == null || _remoteUserId == null) {
      print('No incoming call to accept');
      return false;
    }
    
    try {
      print('Accepting incoming call from $_remoteUserId, channel: $_channelId');
      
      // Request permissions
      final permissionStatus = await _requestPermissions(_callType);
      if (!permissionStatus) {
        _errorController.add('Call permissions not granted');
        rejectCall();
        return false;
      }
      
      // Update call status on server
      final success = await _updateCallStatus(_channelId!, 'connected');
      if (!success) {
        _errorController.add('Failed to update call status');
        return false;
      }
      
      // Get Agora token for the channel
      final tokenResult = await _getAgoraToken(_channelId!);
      if (!tokenResult) {
        _errorController.add('Failed to get call token');
        return false;
      }
      
      // Setup media
      await _setupMediaForCall();
      
      // Join the channel
      final joinSuccess = await _joinChannel();
      if (!joinSuccess) {
        _errorController.add('Failed to join call channel');
        return false;
      }
      
      // Send WebRTC answer
      socketService.sendWebRTCAnswer(_remoteUserId!, {'accepted': true});
      
      // Update call state
      _updateCallState(CallState.connected);
      
      return true;
    } catch (e) {
      print('Error accepting call: $e');
      _errorController.add('Failed to accept call: $e');
      return false;
    }
  }
  
  // Reject an incoming call
  Future<void> rejectCall() async {
    if (_callState != CallState.connecting || _remoteUserId == null || _channelId == null) {
      return;
    }
    
    try {
      print('Rejecting call from $_remoteUserId');
      
      // Update call status on server
      await _updateCallStatus(_channelId!, 'rejected');
      
      // Send reject message
      socketService.sendWebRTCRejectCall(_remoteUserId!);
      
      // Reset state
      _resetCallState();
    } catch (e) {
      print('Error rejecting call: $e');
    }
  }
  
  // End a call
  Future<void> endCall(bool notifyRemote) async {
    if (!isInCall) {
      return;
    }
    
    try {
      print('Ending call, notifyRemote: $notifyRemote');
      
      // Stop timer
      _stopCallTimer();
      
      // Update call status if we have a channel ID
      if (_channelId != null) {
        await _updateCallStatus(_channelId!, 'ended');
      }
      
      // Notify remote user if requested
      if (notifyRemote && _remoteUserId != null) {
        socketService.sendWebRTCEndCall(_remoteUserId!);
      }
      
      // Leave the channel
      await _engine?.leaveChannel();
      
      // Reset state
      _resetCallState();
    } catch (e) {
      print('Error ending call: $e');
    }
  }
  
  // Toggle microphone mute state
  Future<bool> toggleMute() async {
    if (!isInCall || _engine == null) {
      return false;
    }
    
    try {
      _isLocalMuted = !_isLocalMuted;
      await _engine!.muteLocalAudioStream(_isLocalMuted);
      return _isLocalMuted;
    } catch (e) {
      print('Error toggling mute: $e');
      return false;
    }
  }
  
  // Toggle camera state (video calls only)
  Future<bool> toggleCamera() async {
    if (!isInCall || _engine == null || _callType != CallType.video) {
      return false;
    }
    
    try {
      _isLocalVideoEnabled = !_isLocalVideoEnabled;
      await _engine!.muteLocalVideoStream(!_isLocalVideoEnabled);
      return !_isLocalVideoEnabled;
    } catch (e) {
      print('Error toggling camera: $e');
      return false;
    }
  }
  
  // Switch between front and back camera
  Future<void> switchCamera() async {
    if (!isInCall || _engine == null || _callType != CallType.video) {
      return;
    }
    
    try {
      await _engine!.switchCamera();
    } catch (e) {
      print('Error switching camera: $e');
    }
  }
  
  // Request necessary permissions based on call type
  Future<bool> _requestPermissions(CallType type) async {
    try {
      List<Permission> permissions = [];
      
      // Always need microphone for both call types
      permissions.add(Permission.microphone);
      
      // Camera only needed for video calls
      if (type == CallType.video) {
        permissions.add(Permission.camera);
      }
      
      // Request permissions
      Map<Permission, PermissionStatus> statuses = await permissions.request();
      
      // Check if all required permissions are granted
      return !statuses.values.any((status) => status != PermissionStatus.granted);
    } catch (e) {
      print('Error requesting permissions: $e');
      return false;
    }
  }
  
  // Create a call record on the server
  Future<Map<String, dynamic>?> _createCallRecord(String receiverId, String callType) async {
    try {
      print('Creating call record: receiverId=$receiverId, callType=$callType');
      
      final response = await http.post(
        Uri.parse('$baseUrl/api/calls'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${currentUser.token}',
        },
        body: jsonEncode({
          'receiverId': receiverId,
          'callType': callType.toLowerCase(),
          'status': 'initiated'
        }),
      );
      
      if (response.statusCode == 201) {
        final data = json.decode(response.body);
        print('Call record created: ${data['callId']}');
        return data;
      } else {
        print('Error creating call record: ${response.statusCode} ${response.body}');
        return null;
      }
    } catch (e) {
      print('Error creating call record: $e');
      return null;
    }
  }
  
  // Get Agora token from server
  Future<bool> _getAgoraToken(String channelName) async {
    try {
      print('Requesting Agora token for channel: $channelName');
      
      final response = await http.post(
        Uri.parse('$baseUrl/api/calls/agora-token'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${currentUser.token}',
        },
        body: jsonEncode({
          'channelName': channelName,
        }),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        // Store token
        _agoraToken = data['token'];
        
        // Use default UID if not provided
        _uid = data['uid'] ?? 0;
        
        print('Got Agora token successfully. UID: $_uid');
        return true;
      } else {
        print('Error getting Agora token: ${response.statusCode} ${response.body}');
        return false;
      }
    } catch (e) {
      print('Error getting Agora token: $e');
      return false;
    }
  }
  
  // Update call status on server
  Future<bool> _updateCallStatus(String callId, String status) async {
    try {
      print('Updating call status: callId=$callId, status=$status');
      
      final response = await http.put(
        Uri.parse('$baseUrl/api/calls/$callId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${currentUser.token}',
        },
        body: jsonEncode({
          'status': status
        }),
      );
      
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      print('Error updating call status: $e');
      return false;
    }
  }
  
  // Setup media based on call type
  Future<void> _setupMediaForCall() async {
    try {
      if (_engine == null) {
        throw Exception('Agora engine not initialized');
      }
      
      print('Setting up media for call type: ${_callType.name}');
      
      // Set client role to broadcaster (needed for sending audio/video)
      await _engine!.setClientRole(role: ClientRoleType.clientRoleBroadcaster);
      
      // Enable audio for all call types
      await _engine!.enableAudio();
      
      // For video calls, enable video too
      if (_callType == CallType.video) {
        await _engine!.enableVideo();
        
        // Set video enhancement parameters for better quality
        await _engine!.setVideoEncoderConfiguration(
          const VideoEncoderConfiguration(
            dimensions: VideoDimensions(width: 640, height: 360),
            frameRate: 15,
            bitrate: 800,
          ),
        );
      } else {
        await _engine!.disableVideo();
      }
    } catch (e) {
      print('Error setting up media: $e');
      throw e;
    }
  }
  
  // Join the Agora channel
  Future<bool> _joinChannel() async {
    try {
      if (_engine == null) {
        throw Exception('Agora engine not initialized');
      }
      
      if (_channelId == null || _channelId!.isEmpty) {
        throw Exception('Channel ID is null or empty');
      }
      
      if (_agoraToken == null || _agoraToken!.isEmpty) {
        throw Exception('Agora token is null or empty');
      }
      
      print('Joining Agora channel: $_channelId with UID: $_uid');
      
      await _engine!.joinChannel(
        token: _agoraToken!,
        channelId: _channelId!,
        uid: _uid ?? 0,
        options: ChannelMediaOptions(
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
          // Publish audio in both call types
          publishMicrophoneTrack: true,
          // Only publish video in video calls
          publishCameraTrack: _callType == CallType.video,
          // Auto-subscribe to audio/video streams
          autoSubscribeAudio: true,
          autoSubscribeVideo: _callType == CallType.video,
        ),
      );
      
      print('Successfully joined Agora channel: $_channelId');
      return true;
    } catch (e) {
      print('Error joining channel: $e');
      return false;
    }
  }

  // Start call timer
  void _startCallTimer() {
    _callTimer?.cancel();
    _callDuration = 0;
    
    _callTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      _callDuration++;
      _callDurationController.add(_callDuration);
    });
  }
  
  // Stop call timer
  void _stopCallTimer() {
    _callTimer?.cancel();
    _callTimer = null;
  }
  
  // Update call state and notify listeners
  void _updateCallState(CallState newState) {
    if (_callState != newState) {
      print('Call state changing: $_callState -> $newState');
      _callState = newState;
      _callStateController.add(newState);
    }
  }
  
  // Reset call state
  void _resetCallState() {
    print('Resetting call state');
    _callState = CallState.idle;
    _channelId = null;
    _agoraToken = null;
    _uid = null;
    _remoteUserId = null;
    _remoteUsername = null;
    _isInitiator = false;
    _isLocalMuted = false;
    _isLocalVideoEnabled = true;
    _callDuration = 0;
    
    _callStateController.add(CallState.idle);
  }
  
  // Dispose resources
  void dispose() {
    print('Disposing CallManager');
    _stopCallTimer();
    _engine?.leaveChannel();
    _engine?.release();
    
    _callStateController.close();
    _remoteUserJoinedController.close();
    _remoteUserLeftController.close();
    _errorController.close();
    _callDurationController.close();
    
    _instance = null;
  }
}