// services/standalone_call_handler.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:techniq8chat/screens/incoming_call_screen.dart';
import 'package:techniq8chat/services/socket_service.dart';

class StandaloneCallHandler {
  // Singleton pattern
  static final StandaloneCallHandler _instance = StandaloneCallHandler._internal();
  factory StandaloneCallHandler() => _instance;
  StandaloneCallHandler._internal();

  // Global navigator key
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  
  // Call tracking variables
  String? _currentCallId;
  bool _isInitialized = false;
  bool _isHandlingCall = false;
  StreamSubscription? _callSubscription;

  // Initialize call handler
  void initialize(SocketService socketService) {
    // Prevent multiple initializations
    if (_isInitialized) {
      print('StandaloneCallHandler: Already initialized');
      return;
    }

    print('StandaloneCallHandler: Initializing');
    _isInitialized = true;

    // Listen to WebRTC offer stream
    _callSubscription = socketService.onWebRTCOffer.listen(
      (callData) {
        print('StandaloneCallHandler: Received call data - $callData');
        _handleIncomingCall(callData);
      },
      onError: (error) {
        print('StandaloneCallHandler: Error in call stream - $error');
      },
      cancelOnError: false,
    );
  }

  // Handle incoming call
  void _handleIncomingCall(Map<String, dynamic> callData) {
    // Validate call data
    final callId = callData['callId'];
    final callerId = callData['callerId'];
    final callerName = callData['callerName'] ?? 'Unknown User';
    final callType = callData['callType'] ?? 'audio';

    // Ignore invalid or duplicate calls
    if (callId == null || callerId == null) {
      print('StandaloneCallHandler: Invalid call data - $callData');
      return;
    }

    // Prevent multiple call screens
    if (_isHandlingCall || _currentCallId == callId) {
      print('StandaloneCallHandler: Already handling call $callId');
      return;
    }

    // Ensure we have a valid context
    final context = navigatorKey.currentContext;
    if (context == null) {
      print('StandaloneCallHandler: No valid navigator context');
      return;
    }

    // Mark as handling call
    _isHandlingCall = true;
    _currentCallId = callId;

    // Prepare call data for screen
    final processedCallData = {
      'callId': callId,
      'callerId': callerId,
      'callerName': callerName,
      'callType': callType,
    };

    // Dispatch call on main thread
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showIncomingCallScreen(context, processedCallData);
    });
  }

  // Show incoming call screen
  void _showIncomingCallScreen(
    BuildContext context, 
    Map<String, dynamic> callData
  ) {
    // Ensure screen is not already showing and context is valid
    if (!_isHandlingCall || context == null) {
      print('StandaloneCallHandler: Cannot show call screen');
      _resetCallState();
      return;
    }

    try {
      // Wake up device
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual, 
        overlays: SystemUiOverlay.values
      );

      // Show full-screen dialog
      showGeneralDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withOpacity(0.5),
        transitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (dialogContext, animation, secondaryAnimation) {
          return WillPopScope(
            onWillPop: () async => false, // Prevent back button
            child: IncomingCallScreen(
              callData: callData,
              onClose: () {
                print('StandaloneCallHandler: Call screen closed');
                _resetCallState();
                Navigator.of(dialogContext).pop();
              },
            ),
          );
        },
      ).then((_) {
        // Ensure call state is reset if dialog is dismissed
        _resetCallState();
      });
    } catch (e) {
      print('StandaloneCallHandler: Error showing call screen - $e');
      _resetCallState();
    }
  }

  // Reset call handling state
  void _resetCallState() {
    print('StandaloneCallHandler: Resetting call state');
    _isHandlingCall = false;
    _currentCallId = null;
  }

  // Clean up resources
  void dispose() {
    print('StandaloneCallHandler: Disposing');
    _callSubscription?.cancel();
    _resetCallState();
    _isInitialized = false;
  }
}