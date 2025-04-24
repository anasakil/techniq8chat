// services/call_manager.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:techniq8chat/models/user_model.dart';
import 'package:techniq8chat/screens/incoming_call_screen.dart';
import 'package:techniq8chat/screens/call_screen.dart';
import 'package:techniq8chat/services/call_service.dart';

class CallManager {
  // For global access
  static CallManager? _instance;
  static CallManager? get instance => _instance;
  
  // Required parameters
  final User currentUser;
  final String baseUrl;
  final String token;
  final IO.Socket socket;

  // Global navigator key for showing UI overlays
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  
  // Call service
  late CallService _callService;
  CallService get callService => _callService;
  
  // Call state
  bool _isInCall = false;
  bool get isInCall => _isInCall;
  
  // Stream subscriptions
  StreamSubscription? _incomingCallSubscription;
  StreamSubscription? _callStatusSubscription;
  
  // Constructor
  CallManager({
    required this.currentUser,
    required this.baseUrl,
    required this.token,
    required this.socket,
  }) {
    _initializeCallService();
    _instance = this;
  }
  
  void _initializeCallService() {
    _callService = CallService(
      baseUrl: baseUrl,
      token: token,
      currentUser: currentUser,
      socket: socket,
    );
    
    // Subscribe to incoming calls
    _incomingCallSubscription = _callService.incomingCallStream.listen(_handleIncomingCall);
    
    // Subscribe to call status changes to update isInCall flag
    _callStatusSubscription = _callService.callStatusStream.listen((status) {
      _isInCall = status == CallStatus.connected || status == CallStatus.connecting;
    });
  }
  
  // Handle an incoming call
  void _handleIncomingCall(CallDetails callDetails) {
    // If already in a call, automatically reject
    if (_isInCall) {
      _callService.rejectCall();
      return;
    }
    
    // Find a valid context for showing the incoming call screen
    BuildContext? context;
    
    // Try to use the navigator key's context first
    if (navigatorKey.currentContext != null) {
      context = navigatorKey.currentContext!;
    } else {
      // Fall back to getting the context from overlay
      context = _getOverlayContext();
    }
    
    if (context != null) {
      _showIncomingCallScreen(context, callDetails);
    } else {
      // If we can't get a context, just reject the call
      print('No context available to show incoming call screen');
      _callService.rejectCall();
    }
  }
  
  // Try to get the context from the overlay
  BuildContext? _getOverlayContext() {
    BuildContext? overlayContext;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final overlay = OverlayEntry(
        builder: (context) {
          overlayContext = context;
          return const SizedBox.shrink();
        },
      );
      Overlay.of(navigatorKey.currentContext!)?.insert(overlay);
      overlay.remove();
    });
    return overlayContext;
  }
  
  // Show the incoming call screen
  void _showIncomingCallScreen(BuildContext context, CallDetails callDetails) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => IncomingCallScreen(
        callService: _callService,
        callDetails: callDetails,
      ),
    );
  }
  
  // Initiate a call to another user
  Future<void> startCall(
    BuildContext context, 
    User recipient, 
    CallType callType
  ) async {
    if (_isInCall) {
      // Already in a call, show error message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You are already in a call'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    // Create call details
    final callDetails = CallDetails(
      // We'll get the real callId after making the call
      callId: DateTime.now().millisecondsSinceEpoch.toString(),
      callerId: currentUser.id,
      callerName: currentUser.username,
      receiverId: recipient.id,
      receiverName: recipient.username,
      callType: callType,
    );
    
    // Navigate to call screen
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CallScreen(
          callService: _callService,
          callDetails: callDetails,
          isIncoming: false,
        ),
      ),
    );
    
    // Start the call
    try {
      await _callService.makeCall(
        recipient.id,
        recipient.username,
        callType,
      );
    } catch (e) {
      print('Error making call: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to make call: $e'),
          backgroundColor: Colors.red,
        ),
      );
      // Navigate back if there was an error
      Navigator.of(context).pop();
    }
  }
  
  // Dispose resources
  void dispose() {
    _incomingCallSubscription?.cancel();
    _callStatusSubscription?.cancel();
    _callService.dispose();
    _instance = null;
  }
}