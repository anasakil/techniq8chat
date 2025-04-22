// lib/services/call_handler_service.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:techniq8chat/models/user_model.dart';
import 'package:techniq8chat/services/agora_service.dart';
import 'package:techniq8chat/services/socket_service.dart';
import 'package:techniq8chat/services/auth_service.dart';
import 'package:techniq8chat/widgets/incoming_call_notification.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class CallHandlerService {
  // Singleton pattern
  static final CallHandlerService _instance = CallHandlerService._internal();
  factory CallHandlerService() => _instance;
  CallHandlerService._internal();
  
  // Services
  final SocketService _socketService = SocketService();
  final AgoraService _agoraService = AgoraService();
  AuthService? _authService;
  
  // State
  bool _isInitialized = false;
  BuildContext? _overlayContext;
  OverlayEntry? _currentCallOverlay;
  
  // Stream controller for logging
  final _logController = StreamController<String>.broadcast();
  Stream<String> get onLog => _logController.stream;
  
  // Initialize the service
  Future<void> initialize(BuildContext context, AuthService authService) async {
    if (_isInitialized) return;
    
    _authService = authService;
    _overlayContext = context;
    
    // Initialize Agora service
    final currentUser = authService.currentUser;
    if (currentUser != null) {
      await _agoraService.initialize(currentUser);
    }
    
    // Set up socket listener for incoming calls
    _setupSocketListeners();
    
    _isInitialized = true;
    _log('Call handler service initialized');
  }
  
  // Setup socket listeners for call events
  void _setupSocketListeners() {
    // Listen for incoming call events
    _socketService.socket?.on('incoming_call', (data) async {
      _log('Incoming call received: $data');
      
      try {
        final callerId = data['callerId'];
        final callerName = data['callerName'];
        final callId = data['callId'];
        final callType = data['callType'] == 'video' ? CallType.video : CallType.audio;
        
        // Get caller details
        final caller = await _getUserDetails(callerId);
        
        if (caller != null) {
          // Show incoming call UI
          _showIncomingCallUI(caller, callId, callType);
        } else {
          _log('Could not get caller details');
        }
      } catch (e) {
        _log('Error handling incoming call: $e');
      }
    });
    
    // Listen for call ended events
    _socketService.socket?.on('call_ended', (data) {
      _log('Call ended by remote user: $data');
      
      // Dismiss call UI if shown
      _dismissIncomingCallUI();
      
      // End any active call
      if (_agoraService.isInCall) {
        _agoraService.endCall(notifyServer: false);
      }
    });
    
    // Listen for call status updates
    _socketService.socket?.on('call_status_update', (data) {
      _log('Call status update: $data');
      
      final status = data['status'];
      
      if (status == 'rejected') {
        _dismissIncomingCallUI();
      }
    });
  }
  
  // Get user details from API
  Future<User?> _getUserDetails(String userId) async {
    try {
      final currentUser = _authService?.currentUser;
      if (currentUser == null) return null;
      
      final response = await http.get(
        Uri.parse('http://51.178.138.50:4400/api/users/$userId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${currentUser.token}',
        },
      );
      
      if (response.statusCode == 200) {
        final userData = json.decode(response.body);
        
        return User.fromJson({
          '_id': userData['_id'],
          'username': userData['username'],
          'email': userData['email'] ?? '',
          'token': '',
          'status': userData['status'] ?? 'offline',
          'profilePicture': userData['profilePicture'],
          'lastSeen': userData['lastSeen'],
        });
      } else {
        throw Exception('Failed to load user details: ${response.statusCode}');
      }
    } catch (e) {
      _log('Error getting user details: $e');
      return null;
    }
  }
  
  // Show incoming call UI
  void _showIncomingCallUI(User caller, String callId, CallType callType) {
    if (_overlayContext == null) {
      _log('Cannot show call UI: overlay context is null');
      return;
    }
    
    // Dismiss any existing overlay
    _dismissIncomingCallUI();
    
    // Create notification widget
    final overlay = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(_overlayContext!).padding.top + 20,
        left: 20,
        right: 20,
        child: IncomingCallNotification(
          caller: caller,
          callId: callId,
          callType: callType,
          onReject: () {
            _rejectCall(caller.id, callId);
            _dismissIncomingCallUI();
          },
          onAccept: () {
            _acceptCall(caller, callId, callType);
            _dismissIncomingCallUI();
          },
        ),
      ),
    );
    
    // Show the overlay
    Overlay.of(_overlayContext!).insert(overlay);
    _currentCallOverlay = overlay;
    
    _log('Showing incoming call UI for ${caller.username}');
  }
  
  // Dismiss incoming call UI if shown
  void _dismissIncomingCallUI() {
    if (_currentCallOverlay != null) {
      _currentCallOverlay!.remove();
      _currentCallOverlay = null;
      _log('Dismissed incoming call UI');
    }
  }
  
  // Reject a call
  void _rejectCall(String callerId, String callId) {
    _log('Rejecting call from $callerId, call ID: $callId');
    
    // Emit socket event for rejection
    _socketService.socket?.emit('call_rejected', {
      'callerId': callerId,
      'callId': callId,
      'reason': 'rejected_by_user'
    });
    
    // Update call status on server
    _updateCallStatus(callId, 'rejected');
  }
  
  // Accept a call
  void _acceptCall(User caller, String callId, CallType callType) {
    _log('Accepting call from ${caller.username}, call ID: $callId');
    
    // Update call status on server
    _updateCallStatus(callId, 'connected');
  }
  
  // Update call status on server
  Future<void> _updateCallStatus(String callId, String status) async {
    try {
      final currentUser = _authService?.currentUser;
      if (currentUser == null) return;
      
      final response = await http.put(
        Uri.parse('http://51.178.138.50:4400/api/calls/$callId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${currentUser.token}',
        },
        body: json.encode({
          'status': status,
        }),
      );
      
      if (response.statusCode == 200) {
        _log('Call status updated to $status');
      } else {
        _log('Failed to update call status: ${response.statusCode}');
      }
    } catch (e) {
      _log('Error updating call status: $e');
    }
  }
  
  // Log message
  void _log(String message) {
    print('[CallHandler] $message');
    _logController.add(message);
  }
  
  // Dispose resources
  void dispose() {
    _dismissIncomingCallUI();
    _logController.close();
    _isInitialized = false;
  }
}