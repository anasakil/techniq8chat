// utils/call_integration_helper.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:techniq8chat/models/user_model.dart';
import 'package:techniq8chat/services/socket_service.dart';
import 'package:techniq8chat/services/auth_service.dart';
import 'package:techniq8chat/services/call_manager.dart';
import 'package:techniq8chat/screens/agora_call_screen.dart';
import 'package:techniq8chat/screens/test_agora_call.dart';
import 'package:techniq8chat/services/user_repository.dart';

class CallIntegrationHelper {
  // Singleton instance
  static CallIntegrationHelper? _instance;
  static CallIntegrationHelper get instance {
    _instance ??= CallIntegrationHelper._();
    return _instance!;
  }

  // Services
  late SocketService _socketService;
  late AuthService _authService;
  
  // Variables
  BuildContext? _context;
  StreamSubscription? _incomingCallSubscription;
  
  // Private constructor
  CallIntegrationHelper._();
  
  // Initialize the helper
  void initialize(BuildContext context, SocketService socketService, AuthService authService) {
    _context = context;
    _socketService = socketService;
    _authService = authService;
    
    // Initialize call manager if needed
    if (CallManager.instance == null && authService.currentUser != null) {
      CallManager(
        socketService, 
        authService.currentUser!, 
        'http://192.168.100.83:4400'
      );
    }
    
    // Listen for incoming calls
    _setupIncomingCallListener();
  }
  
  // Set up listener for incoming calls
  void _setupIncomingCallListener() {
    // Cancel existing subscription if any
    _incomingCallSubscription?.cancel();
    
    // Listen for incoming calls via socket
    _incomingCallSubscription = _socketService.onWebRTCOffer.listen((data) {
      _handleIncomingCall(data);
    });
  }
  
  // Handle incoming call
  void _handleIncomingCall(Map<String, dynamic> data) async {
    if (_context == null) return;
    
    final senderId = data['senderId'];
    final callType = data['callType'] == 'video' ? CallType.video : CallType.audio;
    
    // Fetch caller information (if possible)
    String callerName = 'Unknown User';
    
    try {
      // Try to get user details
      final userRepository = await _getUserRepository();
      final callerInfo = await userRepository.getUserById(senderId);
      
      if (callerInfo != null) {
        callerName = callerInfo.username;
      }
    } catch (e) {
      print('Error fetching caller info: $e');
    }
    
    // Show incoming call dialog
    _showIncomingCallDialog(_context!, senderId, callerName, callType);
  }
  
  // Create a UserRepository instance
  Future<UserRepository> _getUserRepository() async {
    final currentUser = _authService.currentUser;
    if (currentUser == null) {
      throw Exception('No authenticated user');
    }
    
    return UserRepository(
      baseUrl: 'http://192.168.100.83:4400', 
      token: currentUser.token,
    );
  }
  
  // Show incoming call dialog
  void _showIncomingCallDialog(
    BuildContext context, 
    String callerId, 
    String callerName, 
    CallType callType
  ) {
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
                  callerName[0].toUpperCase(),
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
                CallManager.instance?.rejectCall();
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
  
  // Navigate to call screen for incoming or outgoing calls
 void _navigateToCallScreen(
  BuildContext context,
  String userId,
  String username,
  CallType callType,
  bool isIncoming
) {
  print('Navigating to call screen for ${isIncoming ? "incoming" : "outgoing"} ${callType.name} call');
  print('Remote user ID: $userId');
  print('Remote username: $username');
  
  try {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AgoraCallScreen(
          remoteUserId: userId,
          remoteUsername: username,
          callType: callType,
          isIncoming: isIncoming,
        ),
      ),
    ).then((_) {
      print('Returned from call screen');
    }).catchError((error) {
      print('ERROR during or after call screen: $error');
    });
  } catch (e) {
    print('ERROR creating call screen route: $e');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Failed to navigate to call screen: $e')),
    );
  }
}
  
  // Start an outgoing call
 Future<void> startCall(BuildContext context, String userId, String username, CallType callType) async {
  print('CallIntegrationHelper: Starting ${callType.name} call to $username ($userId)');
  
  // Check if context is available
  if (_context == null) {
    print('ERROR: Context is null, reinitializing with current context');
    _context = context;
  }
  
  // Initialize call manager if needed
  if (CallManager.instance == null) {
    if (_authService.currentUser == null) {
      print('ERROR: No authenticated user available');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('You must be logged in to make calls')),
      );
      return;
    }
    
    print('Initializing CallManager with user: ${_authService.currentUser!.username}');
    
    // Make sure socket service is initialized
    if (!_socketService.isConnected) {
      print('Socket is not connected, initializing...');
      _socketService.initSocket(_authService.currentUser!);
    }
    
    // Create call manager instance
    CallManager(
      _socketService, 
      _authService.currentUser!, 
      'http://192.168.100.83:4400'
    );
    
    // Ensure it was created successfully
    if (CallManager.instance == null) {
      print('ERROR: Failed to create CallManager instance');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not initialize call system')),
      );
      return;
    }
  }
  
  print('Call manager initialized, proceeding to call screen');
  
  try {
    // Navigate to call screen (it will handle starting the call)
    _navigateToCallScreen(context, userId, username, callType, false);
  } catch (e) {
    print('ERROR navigating to call screen: $e');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Failed to start call: $e')),
    );
  }
}

  
  // Launch the test screen
  void launchTestScreen(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => TestAgoraCallScreen()),
    );
  }
  
  // Dispose resources
  void dispose() {
    _incomingCallSubscription?.cancel();
    _incomingCallSubscription = null;
    _context = null;
    _instance = null;
  }
}

