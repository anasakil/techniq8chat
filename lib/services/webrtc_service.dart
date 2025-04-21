// lib/services/webrtc_service.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:techniq8chat/models/user_model.dart';
import 'package:techniq8chat/services/socket_service.dart';

enum CallState {
  idle,
  outgoing,
  incoming,
  connecting,
  connected,
  error,
  ended
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

  // WebRTC components
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  RTCVideoRenderer? localRenderer;
  RTCVideoRenderer? remoteRenderer;

  // Call state tracking
  CallState _callState = CallState.idle;
  CallType _callType = CallType.audio;
  User? _remoteUser;
  User? _currentUser;
  String? _callId;
  DateTime? _callStartTime;

  // Stream controllers for state changes
  final _callStateController = StreamController<CallState>.broadcast();
  final _remoteStreamController = StreamController<MediaStream?>.broadcast();
  final _localStreamController = StreamController<MediaStream?>.broadcast();
  final _callTimeController = StreamController<Duration>.broadcast();

  // Streams
  Stream<CallState> get onCallStateChanged => _callStateController.stream;
  Stream<MediaStream?> get onRemoteStreamChanged => _remoteStreamController.stream;
  Stream<MediaStream?> get onLocalStreamChanged => _localStreamController.stream;
  Stream<Duration> get onCallTimeChanged => _callTimeController.stream;

  // Getters
  CallState get callState => _callState;
  CallType get callType => _callType;
  User? get remoteUser => _remoteUser;
  bool get isInCall => _callState != CallState.idle && _callState != CallState.ended;
  String? get callId => _callId;

  // Timer for tracking call duration
  Timer? _callTimer;

  // Debug logger function
  Function(String)? logger;

  // Initialize the service
  Future<void> initialize(User currentUser) async {
    _currentUser = currentUser;
    _log('WebRTC service initialized for user: ${currentUser.username}');
    
    // Initialize renderers
    localRenderer = RTCVideoRenderer();
    remoteRenderer = RTCVideoRenderer();
    await localRenderer!.initialize();
    await remoteRenderer!.initialize();
    
    // Connect socket listeners for WebRTC signaling
    _setupSocketListeners();
  }

  // Set up socket event listeners
  void _setupSocketListeners() {
    final socket = SocketService();
    
    // WebRTC offer
    socket.onWebRTCOffer.listen((data) {
      _log('Received WebRTC offer from ${data['senderId']}');
      
      if (isInCall) {
        _log('Already in a call, rejecting');
        // Auto-reject if already in a call
        socket.sendWebRTCRejectCall(data['senderId']);
        return;
      }
      
      // Handle incoming call
      _handleIncomingCall(data);
    });
    
    // WebRTC answer
    socket.onWebRTCAnswer.listen((data) {
      _log('Received WebRTC answer');
      _handleRemoteAnswer(data);
    });
    
    // ICE candidates
    socket.onWebRTCIceCandidate.listen((data) {
      _log('Received ICE candidate');
      _handleRemoteIceCandidate(data);
    });
    
    // Call end
    socket.onWebRTCEndCall.listen((senderId) {
      _log('Remote peer ended the call');
      _endCall(false); // don't notify remote as they initiated the end
    });
    
    // Call rejected
    socket.onWebRTCCallRejected.listen((receiverId) {
      _log('Call rejected by receiver');
      _updateCallState(CallState.ended);
      _cleanupCall();
    });
  }

  // Log messages
  void _log(String message) {
    print('[WebRTC] $message');
    if (logger != null) {
      logger!(message);
    }
  }

  // Create PeerConnection with config
  Future<RTCPeerConnection> _createPeerConnection() async {
    final config = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
      ],
      'sdpSemantics': 'unified-plan'
    };
    
    final pc = await createPeerConnection(config);
    
    // Set up event handlers
    pc.onIceCandidate = (RTCIceCandidate candidate) {
      _log('Generated ICE candidate');
      _sendIceCandidate(candidate);
    };
    
    pc.onConnectionState = (RTCPeerConnectionState state) {
      _log('Connection state changed: $state');
      
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _updateCallState(CallState.connected);
        _startCallTimer();
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
                state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
                state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        _endCall(false);
      }
    };
    
    pc.onAddStream = (MediaStream stream) {
      _log('Remote stream added');
      _remoteStream = stream;
      remoteRenderer?.srcObject = stream;
      _remoteStreamController.add(stream);
    };
    
    return pc;
  }

  // Set up local media stream
  Future<MediaStream> _getUserMedia(bool videoEnabled) async {
    final Map<String, dynamic> constraints = {
      'audio': true,
      'video': videoEnabled
    };
    
    try {
      _log('Getting user media: audio=${constraints['audio']}, video=${constraints['video']}');
      final stream = await navigator.mediaDevices.getUserMedia(constraints);
      _localStream = stream;
      localRenderer?.srcObject = stream;
      _localStreamController.add(stream);
      return stream;
    } catch (e) {
      _log('Error getting user media: $e');
      throw Exception('Could not access camera or microphone: $e');
    }
  }

  // Initiate call to a user
  Future<bool> initiateCall(User user, CallType callType) async {
    if (isInCall) {
      _log('Already in a call, cannot start another');
      return false;
    }
    
    if (_currentUser == null) {
      _log('Current user not set');
      return false;
    }
    
    _remoteUser = user;
    _callType = callType;
    _updateCallState(CallState.outgoing);
    
    try {
      // Set up media
      _log('Setting up ${callType == CallType.video ? 'video' : 'audio'} call');
      await _getUserMedia(callType == CallType.video);
      
      // Create peer connection
      _peerConnection = await _createPeerConnection();
      
      // Add local tracks to peer connection
      _localStream!.getTracks().forEach((track) {
        _peerConnection!.addTrack(track, _localStream!);
      });
      
      // Create offer
      final RTCSessionDescription offer = await _peerConnection!.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': callType == CallType.video,
      });
      
      // Set local description
      await _peerConnection!.setLocalDescription(offer);
      _log('Created and set local offer');
      
      // Send offer to receiver via socket
      final socket = SocketService();
      socket.sendWebRTCOffer(
        user.id,
        offer.toMap(),
        callType == CallType.video ? 'video' : 'audio',
      );
      
      _log('Sent offer to ${user.username}');
      return true;
    } catch (e) {
      _log('Error initiating call: $e');
      _updateCallState(CallState.error);
      _cleanupCall();
      return false;
    }
  }

  // Handle incoming call from socket
  Future<void> _handleIncomingCall(Map<String, dynamic> data) async {
    try {
      _callType = data['callType'] == 'video' ? CallType.video : CallType.audio;
      _updateCallState(CallState.incoming);
      
      // TODO: Fetch caller user details and set _remoteUser
      // This would typically involve a call to your user service
      
      // Store the offer for later use when call is accepted
      _pendingOffer = data['offer'];
      _pendingCallerId = data['senderId'];
      
      // Notification handling would go here
      
    } catch (e) {
      _log('Error handling incoming call: $e');
    }
  }

  // Temporary storage for pending call data
  dynamic _pendingOffer;
  String? _pendingCallerId;

  // Accept an incoming call
  Future<bool> acceptIncomingCall(User caller) async {
    if (_callState != CallState.incoming || _pendingOffer == null) {
      _log('No incoming call to accept');
      return false;
    }
    
    _remoteUser = caller;
    
    try {
      // Set up media
      await _getUserMedia(_callType == CallType.video);
      
      // Create peer connection
      _peerConnection = await _createPeerConnection();
      
      // Add local tracks to peer connection
      _localStream!.getTracks().forEach((track) {
        _peerConnection!.addTrack(track, _localStream!);
      });
      
      // Set remote description (the offer)
      await _peerConnection!.setRemoteDescription(
        RTCSessionDescription(
          _pendingOffer['sdp'],
          _pendingOffer['type'],
        ),
      );
      
      _log('Set remote description from offer');
      
      // Create answer
      final answer = await _peerConnection!.createAnswer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': _callType == CallType.video,
      });
      
      await _peerConnection!.setLocalDescription(answer);
      _log('Created and set local answer');
      
      // Send answer
      final socket = SocketService();
      socket.sendWebRTCAnswer(_pendingCallerId!, answer.toMap());
      _log('Sent answer to caller');
      
      _updateCallState(CallState.connecting);
      
      // Clear pending offer
      _pendingOffer = null;
      _pendingCallerId = null;
      
      return true;
    } catch (e) {
      _log('Error accepting call: $e');
      _updateCallState(CallState.error);
      _cleanupCall();
      return false;
    }
  }

  // Reject incoming call
  void rejectIncomingCall() {
    if (_callState != CallState.incoming || _pendingCallerId == null) {
      return;
    }
    
    final socket = SocketService();
    socket.sendWebRTCRejectCall(_pendingCallerId!);
    _log('Call rejected');
    
    _pendingOffer = null;
    _pendingCallerId = null;
    _updateCallState(CallState.idle);
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

  // Send ICE candidate to peer
  void _sendIceCandidate(RTCIceCandidate candidate) {
    if (_remoteUser == null) return;
    
    final socket = SocketService();
    socket.sendWebRTCIceCandidate(
      _remoteUser!.id,
      candidate.toMap(),
    );
  }

  // Handle remote ICE candidate
  Future<void> _handleRemoteIceCandidate(Map<String, dynamic> data) async {
    if (_peerConnection == null) return;
    
    try {
      final candidateMap = data['candidate'];
      final candidate = RTCIceCandidate(
        candidateMap['candidate'],
        candidateMap['sdpMid'],
        candidateMap['sdpMLineIndex'],
      );
      
      await _peerConnection!.addCandidate(candidate);
      _log('Added remote ICE candidate');
    } catch (e) {
      _log('Error adding remote ICE candidate: $e');
    }
  }

  // Handle remote answer to our offer
  Future<void> _handleRemoteAnswer(Map<String, dynamic> data) async {
    if (_peerConnection == null) return;
    
    try {
      final sdp = data['answer']['sdp'];
      final type = data['answer']['type'];
      
      await _peerConnection!.setRemoteDescription(
        RTCSessionDescription(sdp, type),
      );
      
      _log('Set remote description from answer');
      _updateCallState(CallState.connecting);
    } catch (e) {
      _log('Error setting remote description: $e');
    }
  }

  // End active call
  Future<void> endCall([bool notifyRemote = true]) async {
    await _endCall(notifyRemote);
  }

  // Internal end call implementation
  Future<void> _endCall(bool notifyRemote) async {
    if (!isInCall) return;
    
    // Notify the other peer if requested
    if (notifyRemote && _remoteUser != null) {
      final socket = SocketService();
      socket.sendWebRTCEndCall(_remoteUser!.id);
      _log('Sent end call signal');
    }
    
    // Stop call timer
    _callTimer?.cancel();
    _callTimer = null;
    
    // Update state and clean up resources
    _updateCallState(CallState.ended);
    await _cleanupCall();
    
    // Reset to idle state after a short delay
    Future.delayed(Duration(seconds: 1), () {
      _updateCallState(CallState.idle);
    });
  }

  // Clean up WebRTC resources
  Future<void> _cleanupCall() async {
    // Stop tracks and dispose local stream
    _localStream?.getTracks().forEach((track) {
      track.stop();
    });
    
    // Close peer connection
    await _peerConnection?.close();
    
    // Clear streams
    _localStreamController.add(null);
    _remoteStreamController.add(null);
    
    // Reset state
    _localStream = null;
    _remoteStream = null;
    _peerConnection = null;
    _callStartTime = null;
    _remoteUser = null;
    
    // Clear renderer sources
    localRenderer?.srcObject = null;
    remoteRenderer?.srcObject = null;
    
    _log('Call resources cleaned up');
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
    if (_localStream == null) return;
    
    final videoTrack = _localStream!.getVideoTracks().firstWhere(
      (track) => track.kind == 'video',
      orElse: () => throw Exception('No video track found'),
    );
    
    if (videoTrack != null) {
      await Helper.switchCamera(videoTrack);
      _log('Camera switched');
    }
  }

  // Toggle microphone mute state
  void toggleMicrophone(bool muted) {
    if (_localStream == null) return;
    
    _localStream!.getAudioTracks().forEach((track) {
      track.enabled = !muted;
    });
    
    _log('Microphone ${muted ? 'muted' : 'unmuted'}');
  }

  // Toggle video enabled state
  void toggleVideo(bool enabled) {
    if (_localStream == null) return;
    
    _localStream!.getVideoTracks().forEach((track) {
      track.enabled = enabled;
    });
    
    _log('Video ${enabled ? 'enabled' : 'disabled'}');
  }

  // Dispose resources
  void dispose() {
    // End any active call
    if (isInCall) {
      _endCall(true);
    }
    
    // Dispose renderers
    localRenderer?.dispose();
    remoteRenderer?.dispose();
    
    // Close streams
    _callStateController.close();
    _remoteStreamController.close();
    _localStreamController.close();
    _callTimeController.close();
    
    _log('WebRTC service disposed');
  }
}