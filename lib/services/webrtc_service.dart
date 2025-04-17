// lib/services/webrtc_service.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:techniq8chat/models/user_model.dart';
import 'package:techniq8chat/services/socket_service.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

enum CallState {
  idle,
  calling,
  ringing,
  connected,
  ended,
  busy,
  notAnswered,
  rejected
}

enum CallType {
  audio,
  video
}

class WebRTCService {
  // Singleton pattern
  static final WebRTCService _instance = WebRTCService._internal();
  factory WebRTCService() => _instance;
  WebRTCService._internal();

  // Socket service
  final SocketService _socketService = SocketService();

  // WebRTC related objects
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  
  // Call related data
  CallState _callState = CallState.idle;
  CallType _callType = CallType.audio;
  User? _currentUser;
  String? _remoteUserId;
  String? _remoteName;
  DateTime? _callStartTime;
  String? _callId;
  
  // Stream controllers for event handling
  final _callStateController = StreamController<CallState>.broadcast();
  final _localStreamController = StreamController<MediaStream?>.broadcast();
  final _remoteStreamController = StreamController<MediaStream?>.broadcast();
  final _remoteUserInfoController = StreamController<Map<String, String>>.broadcast();
  
  // Public streams
  Stream<CallState> get onCallStateChanged => _callStateController.stream;
  Stream<MediaStream?> get onLocalStream => _localStreamController.stream;
  Stream<MediaStream?> get onRemoteStream => _remoteStreamController.stream;
  Stream<Map<String, String>> get onRemoteUserInfo => _remoteUserInfoController.stream;
  
  // Getters
  CallState get callState => _callState;
  CallType get callType => _callType;
  bool get isInCall => _callState != CallState.idle && _callState != CallState.ended;
  String? get remoteUserId => _remoteUserId;
  String? get remoteName => _remoteName;
  DateTime? get callStartTime => _callStartTime;
  Duration get callDuration => 
      _callStartTime != null ? DateTime.now().difference(_callStartTime!) : Duration.zero;
  String? get callId => _callId;
  
  // Initialize the service
 Future<void> initialize(User currentUser) async {
    _currentUser = currentUser;
    
    // Setup socket event listeners
    _setupSocketListeners();
  }

  // Add a method to manually set the current user
  void setCurrentUser(User user) {
    _currentUser = user;
  }
  
  // Set up socket event listeners
  void _setupSocketListeners() {
    // WebRTC offer from another user
    _socketService.onWebRTCOffer.listen((data) async {
      print('WebRTC: Received offer from ${data['senderId']}');
      
      if (isInCall) {
        // Auto-reject if already in a call
        _rejectIncomingCall(data['senderId']);
        return;
      }
      
      // Store the remote user ID
      _remoteUserId = data['senderId'];
      _callType = data['callType'] == 'video' ? CallType.video : CallType.audio;
      
      // Get remote user info
      await _fetchRemoteUserInfo();
      
      // Update call state to ringing
      _updateCallState(CallState.ringing);
      
      // Store the offer for later use when the call is accepted
      _pendingOffer = data['offer'];
    });
    
    // WebRTC answer from callee
    _socketService.onWebRTCAnswer.listen((data) async {
      print('WebRTC: Received answer');
      
      if (_peerConnection == null) {
        print('WebRTC: No peer connection, ignoring answer');
        return;
      }
      
      try {
        RTCSessionDescription description = RTCSessionDescription(
          data['answer']['sdp'],
          data['answer']['type'],
        );
        
        await _peerConnection!.setRemoteDescription(description);
        print('WebRTC: Set remote description from answer');
      } catch (e) {
        print('WebRTC: Error setting remote description: $e');
      }
    });
    
    // ICE candidate from peer
    _socketService.onWebRTCIceCandidate.listen((data) async {
      if (_peerConnection == null) {
        print('WebRTC: No peer connection, ignoring ICE candidate');
        return;
      }
      
      try {
        RTCIceCandidate candidate = RTCIceCandidate(
          data['candidate']['candidate'],
          data['candidate']['sdpMid'],
          data['candidate']['sdpMLineIndex'],
        );
        
        await _peerConnection!.addCandidate(candidate);
        print('WebRTC: Added ICE candidate');
      } catch (e) {
        print('WebRTC: Error adding ICE candidate: $e');
      }
    });
    
    // End call signal
    _socketService.onWebRTCEndCall.listen((senderId) {
      print('WebRTC: Remote peer ended the call');
      _handleCallEnded();
    });
  }
  
  // Temp variable to store an offer while waiting for user to accept/reject
  dynamic _pendingOffer;
  
  // Fetch remote user information
  Future<void> _fetchRemoteUserInfo() async {
    if (_remoteUserId == null || _currentUser == null) return;
    
    try {
      final response = await http.get(
        Uri.parse('http://192.168.100.5:4400/api/users/$_remoteUserId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${_currentUser!.token}',
        },
      );
      
      if (response.statusCode == 200) {
        final userData = json.decode(response.body);
        _remoteName = userData['username'] ?? 'Unknown User';
        
        // Notify listeners about remote user info
        _remoteUserInfoController.add({
          'userId': _remoteUserId!,
          'name': _remoteName!,
          'profilePicture': userData['profilePicture'] ?? '',
        });
      }
    } catch (e) {
      print('WebRTC: Error fetching remote user info: $e');
      _remoteName = 'Unknown User';
    }
  }
  
  // Update call state and notify listeners
  void _updateCallState(CallState newState) {
    print('WebRTC: Call state changed from $_callState to $newState');
    _callState = newState;
    _callStateController.add(newState);
    
    // Update call start time if connected
    if (newState == CallState.connected && _callStartTime == null) {
      _callStartTime = DateTime.now();
    }
  }
  
  // Create WebRTC peer connection with configuration
  Future<RTCPeerConnection> _createPeerConnection() async {
    final configuration = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
      ],
      'sdpSemantics': 'unified-plan'
    };
    
    final pc = await createPeerConnection(configuration);
    
    // Handle ICE candidates
    pc.onIceCandidate = (RTCIceCandidate candidate) {
      print('WebRTC: Generated ICE candidate');
      if (_remoteUserId != null) {
        _socketService.sendWebRTCIceCandidate(_remoteUserId!, candidate.toMap());
      }
    };
    
    // Handle connection state changes
    pc.onConnectionState = (RTCPeerConnectionState state) {
      print('WebRTC: Connection state: $state');
      
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _updateCallState(CallState.connected);
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed || 
                state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
                state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        _handleCallEnded();
      }
    };
    
    // Handle ICE connection state changes
    pc.onIceConnectionState = (RTCIceConnectionState state) {
      print('WebRTC: ICE connection state: $state');
    };
    
    // Handle remote stream
    pc.onAddStream = (MediaStream stream) {
      print('WebRTC: Remote stream added');
      _remoteStream = stream;
      _remoteStreamController.add(stream);
    };
    
    return pc;
  }
  
  // Set up local media stream (audio/video)
  Future<MediaStream> _setupLocalStream(bool videoEnabled) async {
    final mediaConstraints = {
      'audio': true,
      'video': videoEnabled ? {
        'mandatory': {
          'minWidth': '640',
          'minHeight': '480',
          'minFrameRate': '30',
        },
        'facingMode': 'user',
        'optional': [],
      } : false,
    };
    
    try {
      final stream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      _localStream = stream;
      _localStreamController.add(stream);
      return stream;
    } catch (e) {
      print('WebRTC: Error getting user media: $e');
      throw Exception('Could not access camera or microphone. Please check your device settings.');
    }
  }
  
 Future<bool> initiateCall(String receiverId, CallType callType) async {
  if (isInCall) {
    print('WebRTC: Already in a call, cannot initiate another');
    return false;
  }

  if (_currentUser == null) {
    print('WebRTC: No current user, cannot initiate call');
    return false;
  }

  // Set call data
  _remoteUserId = receiverId;
  _callType = callType;
  _updateCallState(CallState.calling);

  try {
    // Set up media
    await _setupLocalStream(callType == CallType.video);

    // Fetch remote user information
    await _fetchRemoteUserInfo();

    // Create peer connection
    _peerConnection = await _createPeerConnection();

    // Add local tracks to peer connection
    _localStream!.getTracks().forEach((track) {
      _peerConnection!.addTrack(track, _localStream!);
    });

    // Create offer
    final offer = await _peerConnection!.createOffer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': callType == CallType.video,
    });

    await _peerConnection!.setLocalDescription(offer);

    // Send offer to receiver via socket
    // Use SocketService to send the WebRTC offer
    SocketService().sendWebRTCOffer(
      receiverId,
      offer.toMap(),
      callType == CallType.video ? 'video' : 'audio',
    );

    print('WebRTC: Call initiated to $receiverId');
    return true;
  } catch (e) {
    print('WebRTC: Error initiating call: $e');
    _handleCallEnded();
    return false;
  }
}
  
  // Create call record on server
  Future<void> _createCallRecord(String receiverId, CallType callType) async {
    if (_currentUser == null) return;
    
    try {
      final response = await http.post(
        Uri.parse('http://192.168.100.5:4400/api/calls'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${_currentUser!.token}',
        },
        body: json.encode({
          'receiverId': receiverId,
          'callType': callType == CallType.video ? 'video' : 'audio',
          'status': 'initiated'
        }),
      );
      
      if (response.statusCode == 201) {
        final callData = json.decode(response.body);
        _callId = callData['callId'];
        print('WebRTC: Call record created with ID: $_callId');
      } else {
        print('WebRTC: Failed to create call record, status code: ${response.statusCode}');
      }
    } catch (e) {
      print('WebRTC: Error creating call record: $e');
    }
  }
  
  // Update call status on server
  Future<void> _updateCallStatus(String status) async {
    if (_callId == null || _currentUser == null) return;
    
    try {
      await http.put(
        Uri.parse('http://192.168.100.5:4400/api/calls/$_callId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${_currentUser!.token}',
        },
        body: json.encode({
          'status': status,
        }),
      );
      
      print('WebRTC: Call status updated to $status');
    } catch (e) {
      print('WebRTC: Error updating call status: $e');
    }
  }
  
  // Accept an incoming call
  Future<bool> acceptIncomingCall() async {
    if (_callState != CallState.ringing || _pendingOffer == null) {
      print('WebRTC: No pending call to accept');
      return false;
    }
    
    try {
      // Set up media
      await _setupLocalStream(_callType == CallType.video);
      
      // Create peer connection
      _peerConnection = await _createPeerConnection();
      
      // Add tracks to peer connection
      _localStream!.getTracks().forEach((track) {
        _peerConnection!.addTrack(track, _localStream!);
      });
      
      // Set remote description (the offer)
      final remoteDesc = RTCSessionDescription(
        _pendingOffer['sdp'],
        _pendingOffer['type'],
      );
      
      await _peerConnection!.setRemoteDescription(remoteDesc);
      
      // Create answer
      final answer = await _peerConnection!.createAnswer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': _callType == CallType.video,
      });
      
      await _peerConnection!.setLocalDescription(answer);
      
      // Send answer to caller
      if (_remoteUserId != null) {
        _socketService.sendWebRTCAnswer(_remoteUserId!, answer.toMap());
      }
      
      // Update call status
      _updateCallState(CallState.connected);
      
      // Update call status on server
      await _updateCallStatus('connected');
      
      print('WebRTC: Call accepted');
      return true;
    } catch (e) {
      print('WebRTC: Error accepting call: $e');
      _handleCallEnded();
      return false;
    }
  }
  
  // Reject an incoming call
  void rejectIncomingCall() {
    if (_callState != CallState.ringing || _remoteUserId == null) {
      return;
    }
    
    _rejectIncomingCall(_remoteUserId!);
    _updateCallState(CallState.rejected);
    
    // Update call status on server
    _updateCallStatus('rejected');
  }
  
  // Helper method to reject incoming call via socket
  void _rejectIncomingCall(String callerId) {
    _socketService.sendWebRTCRejectCall(callerId);
    print('WebRTC: Call rejected');
  }
  
  // End an ongoing call
  void endCall() {
    if (!isInCall) {
      return;
    }
    
    // Notify the other peer
    if (_remoteUserId != null) {
      _socketService.sendWebRTCEndCall(_remoteUserId!);
    }
    
    // Update call status on server
    _updateCallStatus('ended');
    
    // Clean up resources
    _handleCallEnded();
  }
  
  // Handle call ended (clean up resources)
  void _handleCallEnded() {
    print('WebRTC: Handling call end');
    
    // Clean up streams
    _disposeMediaStreams();
    
    // Close peer connection
    if (_peerConnection != null) {
      _peerConnection!.close();
      _peerConnection = null;
    }
    
    // Reset call state
    _updateCallState(CallState.ended);
    
    // Clear call data after delay to allow UI to react
    Future.delayed(Duration(seconds: 2), () {
      _remoteUserId = null;
      _remoteName = null;
      _callStartTime = null;
      _pendingOffer = null;
      _updateCallState(CallState.idle);
    });
  }
  
  // Dispose media streams
  void _disposeMediaStreams() {
    // Stop all tracks and dispose local stream
    if (_localStream != null) {
      _localStream!.getTracks().forEach((track) => track.stop());
      _localStream!.dispose();
      _localStream = null;
      _localStreamController.add(null);
    }
    
    // Dispose remote stream
    if (_remoteStream != null) {
      _remoteStream!.dispose();
      _remoteStream = null;
      _remoteStreamController.add(null);
    }
  }
  
  // Toggle camera (switch between front and back)
  Future<void> toggleCamera() async {
    if (_localStream == null) return;
    
    final videoTrack = _localStream!.getVideoTracks().first;
    await Helper.switchCamera(videoTrack);
  }
  
  // Toggle microphone mute state
  void toggleMicrophone(bool muted) {
    if (_localStream == null) return;
    
    _localStream!.getAudioTracks().forEach((track) {
      track.enabled = !muted;
    });
  }
  
  // Toggle video enabled state
  void toggleVideo(bool enabled) {
    if (_localStream == null) return;
    
    _localStream!.getVideoTracks().forEach((track) {
      track.enabled = enabled;
    });
  }
  
  // Dispose resources
  void dispose() {
    // End any active call
    if (isInCall) {
      endCall();
    }
    
    // Clean up resources
    _disposeMediaStreams();
    
    // Close streams
    if (!_callStateController.isClosed) _callStateController.close();
    if (!_localStreamController.isClosed) _localStreamController.close();
    if (!_remoteStreamController.isClosed) _remoteStreamController.close();
    if (!_remoteUserInfoController.isClosed) _remoteUserInfoController.close();
  }
}