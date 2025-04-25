// utils/enhanced_call_handler.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:techniq8chat/models/user_model.dart';
import 'package:techniq8chat/services/socket_service.dart';
import 'package:techniq8chat/services/auth_service.dart';
import 'package:techniq8chat/services/call_manager.dart';
import 'package:techniq8chat/screens/agora_call_screen.dart';
import 'package:techniq8chat/screens/test_agora_call.dart';
import 'package:techniq8chat/services/user_repository.dart';

class EnhancedCallHandler {
  // Singleton instance
  static EnhancedCallHandler? _instance;
  static EnhancedCallHandler get instance {
    _instance ??= EnhancedCallHandler._();
    return _instance!;
  }

  // Services
  late SocketService _socketService;
  late AuthService _authService;
  
  // Variables
  BuildContext? _context;
  StreamSubscription? _incomingCallSubscription;
  User? _currentUser;
  
  // Private constructor
  EnhancedCallHandler._();
  
  // Initialize the handler
  void initialize(BuildContext context, SocketService socketService, AuthService authService) {
    _context = context;
    _socketService = socketService;
    _authService = authService;
    _currentUser = authService.currentUser;
    
    print('EnhancedCallHandler: Initializing with user ${_currentUser?.username ?? "Unknown"}');
    
    // Initialize call manager if needed
    if (CallManager.instance == null && _currentUser != null) {
      print('EnhancedCallHandler: Creating CallManager instance');
      CallManager(
        socketService, 
        _currentUser!, 
        'http://192.168.100.83:4400'
      );
    }
    
    // Set up listeners for incoming calls
    _setupIncomingCallListeners();
  }
  
  // Set up all listeners for incoming calls
  void _setupIncomingCallListeners() {
    print('EnhancedCallHandler: Setting up incoming call listeners');
    
    // Cancel existing subscriptions if any
    _incomingCallSubscription?.cancel();
    
    // Listen for WebRTC offer events (for CallManager-based calls)
    _incomingCallSubscription = _socketService.onWebRTCOffer.listen((data) {
      print('EnhancedCallHandler: Received WebRTC offer: $data');
      _handleIncomingCall(data);
    });
    
    // IMPORTANT: Also listen for the direct 'incoming_call' event from socket
    // This is the event that's actually being sent in your case
    _socketService.socket?.on('incoming_call', (data) {
      print('EnhancedCallHandler: Received direct incoming call: $data');
      _handleDirectIncomingCall(data);
    });
  }
  
  // Handle WebRTC-based incoming call
  void _handleIncomingCall(Map<String, dynamic> data) async {
    if (_context == null) {
      print('EnhancedCallHandler: Context is null, cannot show incoming call dialog');
      return;
    }
    
    final senderId = data['senderId'];
    final callType = data['callType'] == 'video' ? CallType.video : CallType.audio;
    
    // Fetch caller information
    String callerName = await _fetchCallerName(senderId);
    
    // Show incoming call dialog
    _showIncomingCallDialog(_context!, senderId, callerName, callType);
  }
  
  // Handle direct incoming call event
  void _handleDirectIncomingCall(dynamic data) async {
    if (_context == null) {
      print('EnhancedCallHandler: Context is null, cannot show incoming call dialog');
      return;
    }
    
    print('EnhancedCallHandler: Processing direct incoming call data: $data');
    
    try {
      // Extract data from the incoming call event
      final callerId = data['callerId'];
      final callId = data['callId'];
      final callType = data['callType'] == 'video' ? CallType.video : CallType.audio;
      String callerName = data['callerName'] ?? await _fetchCallerName(callerId);
      
      print('EnhancedCallHandler: Incoming call from $callerName ($callerId), call ID: $callId, type: ${callType.name}');
      
      // Show the incoming call dialog
      _showIncomingCallDialog(_context!, callerId, callerName, callType);
    } catch (e) {
      print('EnhancedCallHandler: Error handling direct incoming call: $e');
    }
  }
  
  // Fetch caller name
  Future<String> _fetchCallerName(String userId) async {
    try {
      // Try to get user details
      final userRepository = UserRepository(
        baseUrl: 'http://192.168.100.83:4400', 
        token: _currentUser?.token ?? '',
      );
      
      final callerInfo = await userRepository.getUserById(userId);
      return callerInfo?.username ?? 'Unknown User';
    } catch (e) {
      print('EnhancedCallHandler: Error fetching caller info: $e');
      return 'Unknown User';
    }
  }
  
  // Show incoming call dialog
  void _showIncomingCallDialog(
    BuildContext context, 
    String callerId, 
    String callerName, 
    CallType callType
  ) {
    print('EnhancedCallHandler: Showing incoming call dialog for $callerName');
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: Text('Incoming ${callType.name.toUpperCase()} Call'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: const Color(0xFF2A64F6).withOpacity(0.2),
                child: Text(
                  callerName.isNotEmpty ? callerName[0].toUpperCase() : '?',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF2A64F6),
                    fontSize: 24,
                  ),
                ),
              ),
              SizedBox(height: 16),
              Text('$callerName is calling you', textAlign: TextAlign.center),
            ],
          ),
          actions: [
            // Reject call button
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                
                // Reject the call
                _socketService.sendWebRTCRejectCall(callerId);
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.call_end, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Decline', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
            
            // Accept call button
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                // Navigate to call screen
                _navigateToCallScreen(context, callerId, callerName, callType, true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(callType == CallType.audio ? Icons.call : Icons.videocam, color: Colors.white),
                  SizedBox(width: 8),
                  Text('Accept', style: TextStyle(color: Colors.white)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
  
  // Navigate to call screen (with fallback to test screen)
  void _navigateToCallScreen(
    BuildContext context,
    String userId,
    String username,
    CallType callType,
    bool isIncoming
  ) {
    print('EnhancedCallHandler: Navigating to call screen for ${isIncoming ? "incoming" : "outgoing"} call');
    print('Remote user ID: $userId');
    print('Remote username: $username');
    
    try {
      // Always use the test screen for now as it's more reliable
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => TestAgoraCallScreen(),
        ),
      );
    } catch (e) {
      print('EnhancedCallHandler: Error navigating to call screen: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start call: $e')),
      );
    }
  }
  
  // Start an outgoing call
  Future<void> startCall(BuildContext context, String userId, String username, CallType callType) async {
    print('EnhancedCallHandler: Starting ${callType.name} call to $username ($userId)');
    
    // Update context if needed
    if (_context == null) {
      _context = context;
    }
    
    try {
      // Navigate to call screen (it will handle starting the call)
      _navigateToCallScreen(context, userId, username, callType, false);
    } catch (e) {
      print('EnhancedCallHandler: Error starting call: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start call: $e')),
      );
    }
  }
  
  // Dispose resources
  void dispose() {
    _incomingCallSubscription?.cancel();
    _context = null;
    _instance = null;
  }
}