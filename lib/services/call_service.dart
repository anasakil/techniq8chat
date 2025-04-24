// services/call_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:techniq8chat/models/user_model.dart';

enum CallStatus {
  idle,
  connecting,
  connected,
  disconnected,
}

enum CallType {
  audio,
  video,
}

class CallDetails {
  final String callId;
  final String callerId;
  final String callerName;
  final String receiverId;
  final String receiverName;
  final CallType callType;
  
  CallDetails({
    required this.callId,
    required this.callerId,
    required this.callerName,
    required this.receiverId,
    required this.receiverName,
    required this.callType,
  });
}

class CallService {
  final String baseUrl;
  final String token;
  final User currentUser;
  final IO.Socket socket;

  // Agora SDK instances
  RtcEngine? _engine;
  // Add a public getter for the engine
  RtcEngine? get engine => _engine;
  
  StreamController<CallStatus> _callStatusController = StreamController<CallStatus>.broadcast();
  StreamController<CallDetails> _incomingCallController = StreamController<CallDetails>.broadcast();
  
  // Call details
  CallDetails? currentCall;
  CallStatus callStatus = CallStatus.idle;
  
  // Streams for the UI to listen to
  Stream<CallStatus> get callStatusStream => _callStatusController.stream;
  Stream<CallDetails> get incomingCallStream => _incomingCallController.stream;
  
  // Agora App ID from your Agora account
  final String appId = 'd35effd01b264bac87f3e87a973d92a9'; // Replace with your App ID

  CallService({
    required this.baseUrl,
    required this.token,
    required this.currentUser,
    required this.socket,
  }) {
    _initializeListeners();
  }

  void _initializeListeners() {
    // Listen for incoming calls
    socket.on('incoming_call', (data) {
      print('Incoming call: $data');
      final callDetails = CallDetails(
        callId: data['callId'],
        callerId: data['callerId'],
        callerName: data['callerName'] ?? 'Unknown',
        receiverId: currentUser.id,
        receiverName: currentUser.username,
        callType: data['callType'] == 'video' ? CallType.video : CallType.audio,
      );
      
      currentCall = callDetails;
      _incomingCallController.add(callDetails);
    });

    // Listen for call status updates
    socket.on('call_status_update', (data) {
      print('Call status update: $data');
      if (data['status'] == 'ended') {
        endCall();
      }
    });

    // Listen for call answers
    socket.on('call_answered', (data) {
      print('Call answered: $data');
      _callStatusController.add(CallStatus.connected);
      callStatus = CallStatus.connected;
    });

    // Listen for call rejections
    socket.on('call_rejected', (data) {
      print('Call rejected: $data');
      _endCall();
      _callStatusController.add(CallStatus.disconnected);
      callStatus = CallStatus.disconnected;
    });

    // Listen for call ended events
    socket.on('call_ended', (data) {
      print('Call ended: $data');
      _endCall();
      _callStatusController.add(CallStatus.disconnected);
      callStatus = CallStatus.disconnected;
    });
  }

  // Initialize Agora engine
  Future<void> _initAgoraEngine() async {
    if (_engine != null) return;

    _engine = createAgoraRtcEngine();
    await _engine!.initialize(RtcEngineContext(
      appId: appId,
      channelProfile: ChannelProfileType.channelProfileCommunication,
    ));

    _engine!.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (connection, elapsed) {
          print("Local user joined");
          _callStatusController.add(CallStatus.connected);
          callStatus = CallStatus.connected;
        },
        onLeaveChannel: (connection, stats) {
          print("Local user left channel");
          _callStatusController.add(CallStatus.disconnected);
          callStatus = CallStatus.disconnected;
        },
        onUserJoined: (connection, remoteUid, elapsed) {
          print("Remote user joined: $remoteUid");
        },
        onUserOffline: (connection, remoteUid, reason) {
          print("Remote user left: $remoteUid");
        },
        onTokenPrivilegeWillExpire: (connection, token) {
          print("Token privilege will expire");
          // Handle token refresh here
        },
      ),
    );
  }

  // Get Agora token from your server
  Future<String> _getAgoraToken(String channelName) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/calls/agora-token'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'channelName': channelName,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['token'];
      } else {
        throw Exception('Failed to get Agora token');
      }
    } catch (e) {
      print('Error getting Agora token: $e');
      throw e;
    }
  }

  // Create a call record on the server
  Future<String> _createCallRecord(String receiverId, CallType callType) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/calls'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'receiverId': receiverId,
          'callType': callType == CallType.video ? 'video' : 'audio',
          'status': 'initiated'
        }),
      );

      if (response.statusCode == 201) {
        final data = json.decode(response.body);
        return data['callId'];
      } else {
        throw Exception('Failed to create call record');
      }
    } catch (e) {
      print('Error creating call record: $e');
      throw e;
    }
  }

  // Update call record status
  Future<void> _updateCallStatus(String callId, String status) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/api/calls/$callId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'status': status,
        }),
      );

      if (response.statusCode != 200) {
        print('Failed to update call status: ${response.body}');
      }
    } catch (e) {
      print('Error updating call status: $e');
    }
  }

  // Make a call to another user
  Future<void> makeCall(String receiverId, String receiverName, CallType callType) async {
    try {
      // Check permissions
      await [Permission.microphone, Permission.camera].request();
      
      // Create call record
      final callId = await _createCallRecord(receiverId, callType);
      
      // Set current call details
      currentCall = CallDetails(
        callId: callId,
        callerId: currentUser.id,
        callerName: currentUser.username,
        receiverId: receiverId,
        receiverName: receiverName,
        callType: callType,
      );
      
      // Update UI
      _callStatusController.add(CallStatus.connecting);
      callStatus = CallStatus.connecting;
      
      // Initialize Agora engine
      await _initAgoraEngine();
      
      // Set call options
      if (callType == CallType.video) {
        await _engine!.enableVideo();
        await _engine!.startPreview();
      } else {
        await _engine!.disableVideo();
      }
      
      // Get token for the channel (call)
      final agoraToken = await _getAgoraToken(callId);
      
      // Join the channel
      await _engine!.joinChannel(
        token: agoraToken,
        channelId: callId,
        uid: 0,
        options: const ChannelMediaOptions(
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          channelProfile: ChannelProfileType.channelProfileCommunication,
        ),
      );
      
      // Notify receiver through socket
      socket.emit('webrtc_offer', {
        'receiverId': receiverId,
        'callType': callType == CallType.video ? 'video' : 'audio',
        'callId': callId
      });
      
    } catch (e) {
      print('Error making call: $e');
      _callStatusController.add(CallStatus.disconnected);
      callStatus = CallStatus.disconnected;
      currentCall = null;
    }
  }

  // Answer an incoming call
  Future<void> answerCall() async {
    if (currentCall == null) return;
    
    try {
      // Check permissions
      await [Permission.microphone, Permission.camera].request();
      
      // Update call status to connected
      await _updateCallStatus(currentCall!.callId, 'connected');
      
      // Update UI
      _callStatusController.add(CallStatus.connecting);
      callStatus = CallStatus.connecting;
      
      // Initialize Agora engine
      await _initAgoraEngine();
      
      // Set call options
      if (currentCall!.callType == CallType.video) {
        await _engine!.enableVideo();
        await _engine!.startPreview();
      } else {
        await _engine!.disableVideo();
      }
      
      // Get token for the channel (call)
      final agoraToken = await _getAgoraToken(currentCall!.callId);
      
      // Join the channel
      await _engine!.joinChannel(
        token: agoraToken,
        channelId: currentCall!.callId,
        uid: 0,
        options: const ChannelMediaOptions(
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          channelProfile: ChannelProfileType.channelProfileCommunication,
        ),
      );
      
      // Notify caller through socket
      socket.emit('call_answered', {
        'callerId': currentCall!.callerId,
        'callId': currentCall!.callId
      });
      
    } catch (e) {
      print('Error answering call: $e');
      _callStatusController.add(CallStatus.disconnected);
      callStatus = CallStatus.disconnected;
    }
  }

  // Reject an incoming call
  Future<void> rejectCall() async {
    if (currentCall == null) return;
    
    try {
      // Update call status to rejected
      await _updateCallStatus(currentCall!.callId, 'rejected');
      
      // Notify caller through socket
      socket.emit('call_rejected', {
        'callerId': currentCall!.callerId,
        'callId': currentCall!.callId,
        'reason': 'rejected'
      });
      
      // Clear call state
      currentCall = null;
      _callStatusController.add(CallStatus.idle);
      callStatus = CallStatus.idle;
      
    } catch (e) {
      print('Error rejecting call: $e');
    }
  }

  // End an ongoing call
  Future<void> endCall() async {
    if (currentCall == null) return;
    
    try {
      // Update call status to ended
      await _updateCallStatus(currentCall!.callId, 'ended');
      
      // Notify other party through socket
      socket.emit('call_ended', {
        'receiverId': currentCall!.callerId == currentUser.id 
            ? currentCall!.receiverId 
            : currentCall!.callerId,
        'callId': currentCall!.callId
      });
      
      // End the call in Agora
      await _endCall();
      
      // Clear call state
      currentCall = null;
      _callStatusController.add(CallStatus.idle);
      callStatus = CallStatus.idle;
      
    } catch (e) {
      print('Error ending call: $e');
    }
  }

  // Handle audio muting
  Future<bool> toggleMicrophone() async {
    if (_engine == null) return false;
    
    try {
      await _engine!.enableLocalAudio(false);
      return true;
    } catch (e) {
      print('Error toggling microphone: $e');
      return false;
    }
  }

  // Handle video enabling/disabling
  Future<bool> toggleVideo() async {
    if (_engine == null || currentCall?.callType == CallType.audio) return false;
    
    try {
      await _engine!.enableLocalVideo(false);
      return true;
    } catch (e) {
      print('Error toggling video: $e');
      return false;
    }
  }

  // Internal method to end the Agora call
  Future<void> _endCall() async {
    if (_engine != null) {
      try {
        await _engine!.leaveChannel();
        await _engine!.stopPreview();
      } catch (e) {
        print('Error in _endCall: $e');
      }
    }
  }

  // Dispose resources
  void dispose() {
    _endCall();
    _callStatusController.close();
    _incomingCallController.close();
    _engine?.release();
  }
}