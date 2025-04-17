// // lib/services/call_manager.dart
// import 'dart:async';
// import 'package:flutter/material.dart';
// import 'package:techniq8chat/screens/calls_screen.dart';
// import 'package:techniq8chat/services/webrtc_service.dart';
// import 'package:techniq8chat/services/socket_service.dart';
// import 'package:techniq8chat/services/user_repository.dart';

// class CallManager {
//   // Singleton instance
//   static final CallManager _instance = CallManager._internal();
//   factory CallManager() => _instance;
//   CallManager._internal();

//   // Services
//   final WebRTCService _webRTCService = WebRTCService();
//   final SocketService _socketService = SocketService();
  
//   // State
//   BuildContext? _context;
//   UserRepository? _userRepository;
//   Timer? _incomingCallTimeoutTimer;
//   bool _initialized = false;
  
//   // Initialize with context and token
//   Future<void> initialize(BuildContext context, String token) async {
//     if (_initialized) return;
    
//     _context = context;
//     _userRepository = UserRepository(
//       baseUrl: 'http://192.168.100.96:4400',
//       token: token,
//     );
    
//     // Initialize WebRTC service
//     await _webRTCService.initialize();
    
//     // Setup listeners for incoming calls
//     _setupIncomingCallListener();
    
//     _initialized = true;
//   }
  
//   void _setupIncomingCallListener() {
//     // Listen for WebRTC offers which signal incoming calls
//     _socketService.onWebRTCOffer.listen((data) async {
//       final senderId = data['senderId'];
//       final callType = data['callType'];
      
//       // Get caller info
//       String callerName = 'Unknown';
//       try {
//         final caller = await _userRepository?.getUserById(senderId);
//         if (caller != null) {
//           callerName = caller.username;
//         }
//       } catch (e) {
//         print('Error fetching caller info: $e');
//       }
      
//       // Present incoming call UI
//       _showIncomingCall(senderId, callerName, callType);
      
//       // Set timeout for auto-rejection after 30 seconds
//       _incomingCallTimeoutTimer?.cancel();
//       _incomingCallTimeoutTimer = Timer(Duration(seconds: 30), () {
//         if (_webRTCService.callState == CallState.ringing) {
//           _webRTCService.rejectCall();
//         }
//       });
//     });
//   }
  
//   void _showIncomingCall(String callerId, String callerName, String callType) {
//     if (_context == null) {
//       print('Cannot show incoming call: context is null');
//       return;
//     }
    
//     // Navigate to call screen
//     Navigator.of(_context!, rootNavigator: true).push(
//       MaterialPageRoute(
//         builder: (context) => CallScreen(
//           remoteUserId: callerId,
//           remoteUsername: callerName,
//           callType: callType,
//           isIncoming: true,
//         ),
//       ),
//     );
//   }
  
//   // Make an outgoing call
//   Future<void> startCall(String userId, String username, String callType) async {
//     if (_context == null) {
//       print('Cannot start call: context is null');
//       return;
//     }
    
//     // Navigate to call screen
//     Navigator.of(_context!, rootNavigator: true).push(
//       MaterialPageRoute(
//         builder: (context) => CallScreen(
//           remoteUserId: userId,
//           remoteUsername: username,
//           callType: callType,
//           isIncoming: false,
//         ),
//       ),
//     );
//   }
  
//   // Clean up resources
//   void dispose() {
//     _incomingCallTimeoutTimer?.cancel();
//     _initialized = false;
//   }
// }