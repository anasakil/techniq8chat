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
  
  // Timer to reset state if call UI fails to show
  Timer? _callStateResetTimer;

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
        print('StandaloneCallHandler: Received call data from stream - $callData');
        _handleIncomingCall(callData);
      },
      onError: (error) {
        print('StandaloneCallHandler: Error in call stream - $error');
      },
      cancelOnError: false,
    );
    
    // Also listen directly to socket events as backup
    socketService.socket?.on('incoming_call', (data) {
      print('StandaloneCallHandler: Direct incoming call event - $data');
      _handleIncomingCall(data);
    });
    
    socketService.socket?.on('webrtc_offer', (data) {
      print('StandaloneCallHandler: Direct webrtc_offer event - $data');
      _handleIncomingCall(data);
    });
  }

  // Handle incoming call
  void _handleIncomingCall(Map<String, dynamic> callData) {
    // Normalize the call data field names
    final Map<String, dynamic> normalizedCallData = Map.from(callData);
    
    // Handle different field name patterns
    if (normalizedCallData['callerId'] == null && normalizedCallData['senderId'] != null) {
      normalizedCallData['callerId'] = normalizedCallData['senderId'];
    }
    
    if (normalizedCallData['senderId'] == null && normalizedCallData['callerId'] != null) {
      normalizedCallData['senderId'] = normalizedCallData['callerId'];
    }
    
    // Extract normalized data
    final callId = normalizedCallData['callId'];
    final callerId = normalizedCallData['callerId'] ?? normalizedCallData['senderId'];
    final callerName = normalizedCallData['callerName'] ?? 'Unknown User';
    final callType = normalizedCallData['callType'] ?? 'audio';

    print('StandaloneCallHandler: Normalized call data - caller: $callerId, call: $callId, type: $callType');

    // Validate normalized data
    if (callId == null || callerId == null) {
      print('StandaloneCallHandler: Invalid call data after normalization');
      return;
    }

    // If we're already handling a call, but it's been a while, we might have a stale state
    // Force reset if it's the same call ID (might be a retry)
    if (_isHandlingCall && _currentCallId == callId) {
      print('StandaloneCallHandler: Same call ID detected, forcing reset of state');
      _resetCallState();
    }
    // For different call while handling another, just log and exit
    else if (_isHandlingCall) {
      print('StandaloneCallHandler: Already handling a different call, ignoring new call');
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
    
    // Set a timer to reset state if the UI doesn't show after 10 seconds
    _callStateResetTimer?.cancel();
    _callStateResetTimer = Timer(Duration(seconds: 10), () {
      print('StandaloneCallHandler: Call state reset timer triggered');
      if (_isHandlingCall) {
        print('StandaloneCallHandler: State still showing handling, but UI might have failed - resetting');
        _resetCallState();
      }
    });

    // Prepare call data for screen - ensure it has the expected fields
    final processedCallData = {
      'callId': callId,
      'callerId': callerId,
      'callerName': callerName,
      'callType': callType,
    };

    print('StandaloneCallHandler: Processed call data ready for screen - $processedCallData');

    // Ensure we're on the UI thread with a post-frame callback
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showIncomingCallScreen(context, processedCallData);
    });
  }

  // Show incoming call screen
  void _showIncomingCallScreen(
    BuildContext context, 
    Map<String, dynamic> callData
  ) {
    // Double-check our state
    if (!_isHandlingCall) {
      print('StandaloneCallHandler: Not handling call anymore, aborting screen display');
      return;
    }

    try {
      // Wake up device
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual, 
        overlays: SystemUiOverlay.values
      );

      print('StandaloneCallHandler: Attempting to show incoming call screen now');

      // Use showDialog instead of showGeneralDialog for simpler implementation
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          print('StandaloneCallHandler: Dialog builder called');
          return WillPopScope(
            onWillPop: () async => false, // Prevent back button
            child: IncomingCallScreen(
              callData: callData,
              onClose: () {
                print('StandaloneCallHandler: Call screen closing callback');
                Navigator.of(dialogContext).pop();
                _resetCallState();
              },
            ),
          );
        },
      ).then((_) {
        print('StandaloneCallHandler: Dialog closed');
        _resetCallState();
      });
      
      print('StandaloneCallHandler: showDialog called successfully');
    } catch (e) {
      print('StandaloneCallHandler: Error showing call screen - $e');
      _resetCallState();
    }
  }

  // Reset call handling state
  void _resetCallState() {
    print('StandaloneCallHandler: Resetting call state');
    _callStateResetTimer?.cancel();
    _callStateResetTimer = null;
    _isHandlingCall = false;
    _currentCallId = null;
  }

  // Force reset the call state (for external use)
  void forceResetState() {
    print('StandaloneCallHandler: Force reset called externally');
    _resetCallState();
  }

  // Clean up resources
  void dispose() {
    print('StandaloneCallHandler: Disposing');
    _callSubscription?.cancel();
    _callStateResetTimer?.cancel();
    _resetCallState();
    _isInitialized = false;
  }
}