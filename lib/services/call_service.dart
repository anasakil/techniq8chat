// services/call_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:techniq8chat/screens/call_screen.dart';
import 'package:techniq8chat/screens/incoming_call_screen.dart';
import 'package:techniq8chat/services/auth_service.dart';
import 'package:techniq8chat/services/socket_service.dart';

class CallService {
  static final CallService _instance = CallService._internal();
  factory CallService() => _instance;
  CallService._internal();

  // Agora
  RtcEngine? _engine;
  final String agoraAppId = 'd35effd01b264bac87f3e87a973d92a9';
  
  // Call state
  bool isCallActive = false;
  bool isCallConnected = false;
  bool isLocalAudioMuted = false;
  CallType callType = CallType.voice;
  String? currentCallId;
  String? remoteUserId;
  String? remoteUsername;

  // Stream controllers
  final StreamController<Map<String, dynamic>> _onIncomingCall = StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _onCallStatusChange = StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<bool> _onRemoteUserJoined = StreamController<bool>.broadcast();
  final StreamController<bool> _onCallEnded = StreamController<bool>.broadcast();

  // Streams
  Stream<Map<String, dynamic>> get onIncomingCall => _onIncomingCall.stream;
  Stream<Map<String, dynamic>> get onCallStatusChange => _onCallStatusChange.stream;
  Stream<bool> get onRemoteUserJoined => _onRemoteUserJoined.stream;
  Stream<bool> get onCallEnded => _onCallEnded.stream;

  // Initialize the call service and set up listeners
  Future<void> initialize(SocketService socketService) async {
    print('Initializing CallService');
    
    // Set up socket listeners
    socketService.socket?.on('incoming_call', (data) {
      print('Incoming call received in CallService: $data');
      
      // Extract data from the incoming call event
      final callerId = data['callerId'];
      final callerName = data['callerName'] ?? 'Unknown User';
      final callId = data['callId'];
      final callType = data['callType'] ?? 'voice';
      
      // Add the call data to the stream
      _onIncomingCall.add({
        'callerId': callerId,
        'callerName': callerName,
        'callId': callId,
        'callType': callType,
      });
      
      print('Emitted incoming call to stream: $callerId, $callerName, $callId');
    });
    
    // Also listen for webrtc_offer as an alternative event name
    socketService.socket?.on('webrtc_offer', (data) {
      print('WebRTC offer received in CallService: $data');
      
      // Extract data from the offer event
      final senderId = data['senderId'];
      final callId = data['callId'];
      final callType = data['callType'] ?? 'voice';
      
      // Get the sender name (might need to be fetched)
      final callerName = data['callerName'] ?? 'Unknown User';
      
      // Add the call data to the stream
      _onIncomingCall.add({
        'callerId': senderId,
        'callerName': callerName,
        'callId': callId,
        'callType': callType,
      });
      
      print('Emitted WebRTC offer to stream: $senderId, $callerName, $callId');
    });

    socketService.socket?.on('call_status_update', (data) {
      print('Call status update: $data');
      _onCallStatusChange.add(data);
      
      if (data['status'] == 'ended') {
        endCall();
      }
    });

    socketService.socket?.on('call_answered', (data) {
      print('Call answered: $data');
      _onRemoteUserJoined.add(true);
    });

    socketService.socket?.on('call_rejected', (data) {
      print('Call rejected: $data');
      _onCallEnded.add(true);
    });

    socketService.socket?.on('call_ended', (data) {
      print('Call ended by remote user: $data');
      _onCallEnded.add(true);
      endCall();
    });
  }

  // Initialize Agora engine
  Future<void> _initializeAgoraEngine() async {
    if (_engine != null) return;
    
    _engine = createAgoraRtcEngine();
    await _engine!.initialize(RtcEngineContext(
      appId: agoraAppId,
      channelProfile: ChannelProfileType.channelProfileCommunication,
    ));

    _engine!.registerEventHandler(RtcEngineEventHandler(
      onJoinChannelSuccess: (connection, elapsed) {
        print('Local user joined the channel');
      },
      onUserJoined: (connection, remoteUid, elapsed) {
        print('Remote user joined: $remoteUid');
        _onRemoteUserJoined.add(true);
      },
      onUserOffline: (connection, remoteUid, reason) {
        print('Remote user left: $remoteUid, reason: $reason');
        _onCallEnded.add(true);
      },
      onError: (err, msg) {
        print('Agora error: $err, $msg');
      },
    ));
  }

  // Make a call to another user
  Future<void> makeCall(BuildContext context, String receiverId, String receiverName, CallType type) async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final socketService = Provider.of<SocketService>(context, listen: false);
      
      if (authService.currentUser == null) {
        throw Exception('Not authenticated');
      }

      // Create call record on server
      final response = await http.post(
        Uri.parse('${authService.baseUrl}/api/calls'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${authService.currentUser!.token}',
        },
        body: json.encode({
          'receiverId': receiverId,
          'callType': type == CallType.voice ? 'audio' : 'video',
          'status': 'initiated'
        }),
      );

      if (response.statusCode != 201) {
        throw Exception('Failed to create call record');
      }

      final callData = json.decode(response.body);
      final callId = callData['callId'];
      
      // Update state
      isCallActive = true;
      currentCallId = callId;
      remoteUserId = receiverId;
      remoteUsername = receiverName;
      callType = type;
      
      // Initialize Agora engine
      await _initializeAgoraEngine();
      
      // Request token from server
      final tokenResponse = await http.post(
        Uri.parse('${authService.baseUrl}/api/calls/agora-token'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${authService.currentUser!.token}',
        },
        body: json.encode({
          'channelName': callId,
          'uid': 0, // Use 0 for a dynamically assigned uid
        }),
      );
      
      String? token;
      if (tokenResponse.statusCode == 200) {
        final tokenData = json.decode(tokenResponse.body);
        token = tokenData['token'];
      }
      
      // Enable audio
      await _engine!.enableAudio();
      
      // Disable video for voice calls
      if (type == CallType.voice) {
        await _engine!.disableVideo();
      } else {
        await _engine!.enableVideo();
      }
      
      // Join channel
      await _engine!.joinChannel(
        token: token ?? '',
        channelId: callId,
        uid: 0,
        options: const ChannelMediaOptions(
          channelProfile: ChannelProfileType.channelProfileCommunication,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
        ),
      );
      
      // Navigate to call screen
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => CallScreen(
            userId: receiverId,
            username: receiverName,
            callType: type,
            callId: callId,
          ),
        ),
      );
      
      // Send signal to receiver via socket
      socketService.socket?.emit('webrtc_offer', {
        'receiverId': receiverId,
        'callType': type == CallType.voice ? 'audio' : 'video',
        'callId': callId
      });

    } catch (e) {
      print('Error making call: $e');
      isCallActive = false;
      currentCallId = null;
      remoteUserId = null;
      remoteUsername = null;
      throw e;
    }
  }

  // Answer an incoming call
  Future<void> answerCall(BuildContext context, Map<String, dynamic> callData) async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final socketService = Provider.of<SocketService>(context, listen: false);
      
      final callerId = callData['callerId'];
      final callerName = callData['callerName'];
      final callId = callData['callId'];
      final callTypeStr = callData['callType'];
      
      // Update server with call status
      await http.put(
        Uri.parse('${authService.baseUrl}/api/calls/${callId}'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${authService.currentUser!.token}',
        },
        body: json.encode({'status': 'connected'}),
      );
      
      // Update state
      isCallActive = true;
      currentCallId = callId;
      remoteUserId = callerId;
      remoteUsername = callerName;
      callType = callTypeStr == 'video' ? CallType.video : CallType.voice;
      
      // Initialize Agora engine
      await _initializeAgoraEngine();
      
      // Request token from server
      final tokenResponse = await http.post(
        Uri.parse('${authService.baseUrl}/api/calls/agora-token'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${authService.currentUser!.token}',
        },
        body: json.encode({
          'channelName': callId,
          'uid': 0,
        }),
      );
      
      String? token;
      if (tokenResponse.statusCode == 200) {
        final tokenData = json.decode(tokenResponse.body);
        token = tokenData['token'];
      }
      
      // Enable audio
      await _engine!.enableAudio();
      
      // Configure video based on call type
      if (callType == CallType.voice) {
        await _engine!.disableVideo();
      } else {
        await _engine!.enableVideo();
      }
      
      // Join channel
      await _engine!.joinChannel(
        token: token ?? '',
        channelId: callId,
        uid: 0,
        options: const ChannelMediaOptions(
          channelProfile: ChannelProfileType.channelProfileCommunication,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
        ),
      );
      
      // Navigate to call screen
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => CallScreen(
            userId: callerId,
            username: callerName,
            callType: callType,
            callId: callId,
          ),
        ),
      );
      
      // Notify caller that call was answered
      socketService.socket?.emit('call_answered', {
        'callerId': callerId,
        'callId': callId,
      });
      
    } catch (e) {
      print('Error answering call: $e');
      isCallActive = false;
      currentCallId = null;
      remoteUserId = null;
      remoteUsername = null;
      throw e;
    }
  }

  // Reject an incoming call
  Future<void> rejectCall(BuildContext context, Map<String, dynamic> callData) async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final socketService = Provider.of<SocketService>(context, listen: false);
      
      final callerId = callData['callerId'];
      final callId = callData['callId'];
      
      // Update call status on server
      await http.put(
        Uri.parse('${authService.baseUrl}/api/calls/${callId}'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${authService.currentUser!.token}',
        },
        body: json.encode({'status': 'rejected'}),
      );
      
      // Notify caller that call was rejected
      socketService.socket?.emit('call_rejected', {
        'callerId': callerId,
        'callId': callId,
        'reason': 'rejected'
      });
      
    } catch (e) {
      print('Error rejecting call: $e');
    }
  }

  // End the current call
  Future<void> endCall() async {
    if (!isCallActive || currentCallId == null || remoteUserId == null) return;
    
    try {
      // Leave the channel
      await _engine?.leaveChannel();
      
      // Update state
      isCallActive = false;
      isCallConnected = false;
      
      // If there's an active socket connection, notify the other party
      SocketService().socket?.emit('call_ended', {
        'receiverId': remoteUserId,
        'callId': currentCallId
      });
      
      // Update call status on server if we have a token
      final authService = AuthService();
      if (authService.currentUser != null) {
        await http.put(
          Uri.parse('${authService.baseUrl}/api/calls/${currentCallId}'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${authService.currentUser!.token}',
          },
          body: json.encode({'status': 'ended'}),
        );
      }
      
      // Reset call data
      currentCallId = null;
      remoteUserId = null;
      remoteUsername = null;
      
    } catch (e) {
      print('Error ending call: $e');
    }
  }

  // Toggle local audio mute
  Future<bool> toggleMute() async {
    if (!isCallActive || _engine == null) return false;
    
    try {
      isLocalAudioMuted = !isLocalAudioMuted;
      await _engine!.muteLocalAudioStream(isLocalAudioMuted);
      return isLocalAudioMuted;
    } catch (e) {
      print('Error toggling mute: $e');
      return isLocalAudioMuted;
    }
  }

  // Dispose resources
  void dispose() {
    _engine?.release();
    _engine = null;
    _onIncomingCall.close();
    _onCallStatusChange.close();
    _onRemoteUserJoined.close();
    _onCallEnded.close();
  }
}

enum CallType {
  voice,
  video,
}