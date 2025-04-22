// lib/services/agora_service.dart
import 'dart:async';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:techniq8chat/models/user_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Call states for UI tracking
enum CallState {
  idle,
  outgoing,
  incoming,
  connecting,
  connected,
  error,
  ended
}

// Call types
enum CallType {
  audio,
  video
}

class AgoraService {
  // Singleton pattern
  static final AgoraService _instance = AgoraService._internal();
  factory AgoraService() => _instance;
  AgoraService._internal();

  // Agora constants
  final String _appId = 'd35effd01b264bac87f3e87a973d92a9'; // Your Agora app ID
  final String _baseUrl = 'http://51.178.138.50:4400/api'; // Your API base URL

  // Engine instance
  RtcEngine? _engine;
  
  // Call state tracking
  CallState _callState = CallState.idle;
  CallType _callType = CallType.audio;
  User? _remoteUser;
  User? _currentUser;
  String? _channelId;
  int? _uid;
  DateTime? _callStartTime;
  
  // Stream controllers for state changes
  final _callStateController = StreamController<CallState>.broadcast();
  final _remoteUserJoinedController = StreamController<int>.broadcast();
  final _remoteUserLeftController = StreamController<int>.broadcast();
  final _localUserJoinedController = StreamController<int>.broadcast();
  final _callTimeController = StreamController<Duration>.broadcast();
  final _errorController = StreamController<String>.broadcast();
  final _logController = StreamController<String>.broadcast();

  // Streams
  Stream<CallState> get onCallStateChanged => _callStateController.stream;
  Stream<int> get onRemoteUserJoined => _remoteUserJoinedController.stream;
  Stream<int> get onRemoteUserLeft => _remoteUserLeftController.stream;
  Stream<int> get onLocalUserJoined => _localUserJoinedController.stream;
  Stream<Duration> get onCallTimeChanged => _callTimeController.stream;
  Stream<String> get onError => _errorController.stream;
  Stream<String> get onLog => _logController.stream;

  // Getters
  CallState get callState => _callState;
  CallType get callType => _callType;
  User? get remoteUser => _remoteUser;
  String? get channelId => _channelId;
  bool get isInCall => _callState != CallState.idle && _callState != CallState.ended;
  RtcEngine? get engine => _engine;

  // Timer for tracking call duration
  Timer? _callTimer;

  // Initialize the service
  Future<void> initialize(User currentUser) async {
    _currentUser = currentUser;
    _log('Agora service initialized for user: ${currentUser.username}');
    
    // Create and initialize Agora engine
    await _createEngine();
  }

  // Create and initialize Agora engine
  Future<void> _createEngine() async {
    if (_engine != null) return;
    
    _log('Creating Agora engine');
    
    // Create RtcEngine
    _engine = createAgoraRtcEngine();
    
    // Initialize RtcEngine
    await _engine!.initialize(RtcEngineContext(
      appId: _appId,
      channelProfile: ChannelProfileType.channelProfileCommunication,
    ));
    
    // Set up event handlers
    _setupEventHandlers();
    
    _log('Agora engine created successfully');
  }

  // Set up event handlers for Agora engine
  void _setupEventHandlers() {
    _engine?.registerEventHandler(RtcEngineEventHandler(
      onError: (err, msg) {
        _log('Agora error: $err, $msg');
        _errorController.add('Agora error: $err, $msg');
        if (err.index >= 1) {
          // Significant error, end call
          _endCall(false);
        }
      },
      onJoinChannelSuccess: (connection, elapsed) {
        _log('Local user joined channel: ${connection.channelId}, uid: ${connection.localUid}');
        _uid = connection.localUid;
        _localUserJoinedController.add(connection.localUid!);
        
        // Update call state if we're not in connected state yet
        if (_callState == CallState.connecting || _callState == CallState.outgoing) {
          _updateCallState(CallState.connecting);
        }
      },
      onUserJoined: (connection, remoteUid, elapsed) {
        _log('Remote user joined: $remoteUid');
        _remoteUserJoinedController.add(remoteUid);
        _updateCallState(CallState.connected);
        _startCallTimer();
      },
      onUserOffline: (connection, remoteUid, reason) {
        _log('Remote user left: $remoteUid, reason: $reason');
        _remoteUserLeftController.add(remoteUid);
        // End the call if remote user left
        _endCall(false);
      },
      onConnectionStateChanged: (connection, state, reason) {
        _log('Connection state changed: $state, reason: $reason');
        
        if (state == ConnectionStateType.connectionStateDisconnected ||
            state == ConnectionStateType.connectionStateFailed) {
          _endCall(false);
        }
      },
      onTokenPrivilegeWillExpire: (connection, token) {
        _log('Token will expire soon for connection: ${connection.channelId}, renewing token');
        // In a production app, you would request a new token here
      },
      onRtcStats: (connection, stats) {
        // Useful for debugging call quality
        // _log('Call stats: ${stats.toJson()}');
      },
    ));
  }

  // Get a token from your token server
  Future<String?> _getToken(String channelId, {int uid = 0}) async {
    try {
      final token = _currentUser?.token;
      if (token == null) throw 'User not authenticated';
      
      _log('Requesting Agora token for channel: $channelId, uid: $uid');
      
      final response = await http.post(
        Uri.parse('$_baseUrl/calls/agora-token'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'channelName': channelId,
          'uid': uid,
        }),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _log('Received token for channel: $channelId');
        return data['token'];
      } else {
        throw 'Failed to get token: ${response.statusCode}, ${response.body}';
      }
    } catch (e) {
      _log('Error getting token: $e');
      return null;
    }
  }

  // Create a call record on the server
  Future<String?> _createCallRecord(String receiverId, CallType callType) async {
    try {
      final token = _currentUser?.token;
      if (token == null) throw 'User not authenticated';
      
      _log('Creating call record for receiver: $receiverId, type: $callType');
      
      final response = await http.post(
        Uri.parse('$_baseUrl/calls'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'receiverId': receiverId,
          'callType': callType == CallType.video ? 'video' : 'audio',
          'status': 'initiated',
        }),
      );
      
      if (response.statusCode == 201) {
        final data = json.decode(response.body);
        final callId = data['callId'];
        _log('Call record created with ID: $callId');
        return callId;
      } else {
        throw 'Failed to create call record: ${response.statusCode}, ${response.body}';
      }
    } catch (e) {
      _log('Error creating call record: $e');
      return null;
    }
  }

  // Update call status on the server
  Future<bool> _updateCallStatus(String callId, String status) async {
    try {
      final token = _currentUser?.token;
      if (token == null) throw 'User not authenticated';
      
      _log('Updating call status for call: $callId to: $status');
      
      final response = await http.put(
        Uri.parse('$_baseUrl/calls/$callId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'status': status,
        }),
      );
      
      if (response.statusCode == 200) {
        _log('Call status updated to: $status');
        return true;
      } else {
        throw 'Failed to update call status: ${response.statusCode}, ${response.body}';
      }
    } catch (e) {
      _log('Error updating call status: $e');
      return false;
    }
  }

  // Initiate a call to a user
  Future<bool> initiateCall(User user, CallType callType) async {
    if (isInCall) {
      _log('Already in a call, cannot start another');
      return false;
    }
    
    _remoteUser = user;
    _callType = callType;
    _updateCallState(CallState.outgoing);
    
    try {
      // Create call record on server
      _channelId = await _createCallRecord(user.id, callType);
      
      if (_channelId == null) {
        throw 'Failed to create call record';
      }
      
      // Get token for the channel
      final token = await _getToken(_channelId!);
      
      if (token == null) {
        throw 'Failed to get token';
      }
      
      // Configure audio/video settings
      await _configMediaOptions(callType);
      
      // Join the channel
      await _engine!.joinChannel(
        token: token,
        channelId: _channelId!,
        uid: 0, // 0 means let the server assign a uid
        options: ChannelMediaOptions(
          channelProfile: ChannelProfileType.channelProfileCommunication,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          autoSubscribeAudio: true,
          autoSubscribeVideo: callType == CallType.video,
          publishMicrophoneTrack: true,
          publishCameraTrack: callType == CallType.video,
        ),
      );
      
      _log('Joined channel: $_channelId');
      _updateCallState(CallState.connecting);
      return true;
      
    } catch (e) {
      _log('Error initiating call: $e');
      _errorController.add('Failed to start call: $e');
      _updateCallState(CallState.error);
      _cleanup();
      return false;
    }
  }

  // Accept an incoming call
  Future<bool> acceptCall(User caller, String channelId, CallType callType) async {
    if (isInCall) {
      _log('Already in a call, cannot accept another');
      return false;
    }
    
    _remoteUser = caller;
    _channelId = channelId;
    _callType = callType;
    _updateCallState(CallState.connecting);
    
    try {
      // Update call status on server
      await _updateCallStatus(channelId, 'connected');
      
      // Get token for the channel
      final token = await _getToken(channelId);
      
      if (token == null) {
        throw 'Failed to get token';
      }
      
      // Configure audio/video settings
      await _configMediaOptions(callType);
      
      // Join the channel
      await _engine!.joinChannel(
        token: token,
        channelId: channelId,
        uid: 0, // 0 means let the server assign a uid
        options: ChannelMediaOptions(
          channelProfile: ChannelProfileType.channelProfileCommunication,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          autoSubscribeAudio: true,
          autoSubscribeVideo: callType == CallType.video,
          publishMicrophoneTrack: true,
          publishCameraTrack: callType == CallType.video,
        ),
      );
      
      _log('Joined channel as recipient: $channelId');
      return true;
      
    } catch (e) {
      _log('Error accepting call: $e');
      _errorController.add('Failed to accept call: $e');
      _updateCallState(CallState.error);
      _cleanup();
      return false;
    }
  }

  // Configure media options based on call type
  Future<void> _configMediaOptions(CallType callType) async {
    // Configure video encode parameters if it's a video call
    if (callType == CallType.video) {
      await _engine!.enableVideo();
      
      // Set video encoder configuration
      await _engine!.setVideoEncoderConfiguration(
        const VideoEncoderConfiguration(
          dimensions: VideoDimensions(width: 640, height: 360),
          frameRate: 15,
          bitrate: 800,
          minBitrate: 500,
          orientationMode: OrientationMode.orientationModeAdaptive,
        ),
      );
    } else {
      await _engine!.disableVideo();
    }
    
    // Enable dual-stream mode for video calls (helpful for poor networks)
    if (callType == CallType.video) {
      await _engine!.enableDualStreamMode(enabled: true);
    }
    
    // Set audio profile
    await _engine!.setAudioProfile(
      profile: AudioProfileType.audioProfileDefault,
      scenario: AudioScenarioType.audioScenarioGameStreaming,
    );
    
    // Other configurations based on call type
    if (callType == CallType.audio) {
      // Enable audio volume indication for audio calls
      await _engine!.enableAudioVolumeIndication(
        interval: 200,
        smooth: 3,
        reportVad: true,
      );
    }
  }

  // End active call
  Future<void> endCall({bool notifyServer = true}) async {
    await _endCall(notifyServer);
  }

  // Internal end call implementation
  Future<void> _endCall(bool notifyServer) async {
    if (!isInCall) return;
    
    _log('Ending call, notifyServer: $notifyServer');
    
    // Update call status on server if needed
    if (notifyServer && _channelId != null) {
      await _updateCallStatus(_channelId!, 'ended');
    }
    
    // Stop call timer
    _callTimer?.cancel();
    _callTimer = null;
    
    // Update state and clean up resources
    _updateCallState(CallState.ended);
    await _cleanup();
    
    // Reset to idle state after a short delay
    Future.delayed(Duration(seconds: 1), () {
      _updateCallState(CallState.idle);
    });
  }

  // Clean up resources
  Future<void> _cleanup() async {
    try {
      // Leave the channel
      if (_engine != null && _channelId != null) {
        await _engine!.leaveChannel();
      }
      
      // Reset state variables
      _channelId = null;
      _uid = null;
      _callStartTime = null;
      _remoteUser = null;
    } catch (e) {
      _log('Error during cleanup: $e');
    }
  }

  // Update call state and notify listeners
  void _updateCallState(CallState newState) {
    _log('Call state changed from $_callState to $newState');
    _callState = newState;
    _callStateController.add(newState);
    
    // If connected, start tracking call time
    if (newState == CallState.connected && _callStartTime == null) {
      _callStartTime = DateTime.now();
    }
  }

  // Start timer to track call duration
  void _startCallTimer() {
    _callTimer?.cancel();
    _callStartTime = DateTime.now();
    
    _callTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (_callStartTime != null) {
        final duration = DateTime.now().difference(_callStartTime!);
        _callTimeController.add(duration);
      }
    });
  }

  // Toggle camera (switch between front and back)
  Future<void> switchCamera() async {
    if (_engine == null) return;
    
    try {
      await _engine!.switchCamera();
      _log('Camera switched');
    } catch (e) {
      _log('Error switching camera: $e');
    }
  }

  // Toggle microphone mute state
  Future<void> toggleMicrophone(bool muted) async {
    if (_engine == null) return;
    
    try {
      await _engine!.enableLocalAudio(!muted);
      _log('Microphone ${muted ? 'muted' : 'unmuted'}');
    } catch (e) {
      _log('Error toggling microphone: $e');
    }
  }

  // Toggle video enabled state
  Future<void> toggleVideo(bool enabled) async {
    if (_engine == null) return;
    
    try {
      if (enabled) {
        await _engine!.enableLocalVideo(true);
      } else {
        await _engine!.enableLocalVideo(false);
      }
      _log('Video ${enabled ? 'enabled' : 'disabled'}');
    } catch (e) {
      _log('Error toggling video: $e');
    }
  }

  // Set call log event handler
  void setLogHandler(Function(String) handler) {
    _logController.stream.listen(handler);
  }

  // Log message to stream and console
  void _log(String message) {
    print('[Agora] $message');
    _logController.add(message);
  }

  // Dispose resources
  void dispose() {
    // End any active call
    if (isInCall) {
      _endCall(true);
    }
    
    // Destroy engine
    _engine?.release();
    _engine = null;
    
    // Close streams
    _callStateController.close();
    _remoteUserJoinedController.close();
    _remoteUserLeftController.close();
    _localUserJoinedController.close();
    _callTimeController.close();
    _errorController.close();
    _logController.close();
    
    _log('Agora service disposed');
  }
}