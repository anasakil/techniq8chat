// services/standalone_call_handler.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:techniq8chat/screens/incoming_call_screen.dart';
import 'package:techniq8chat/services/socket_service.dart';

class StandaloneCallHandler {
  // Singleton pattern
  static final StandaloneCallHandler _instance =
      StandaloneCallHandler._internal();
  factory StandaloneCallHandler() => _instance;
  StandaloneCallHandler._internal();

  // Global navigator key
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  // Call tracking variables
  String? _currentCallId;
  bool _isInitialized = false;
  bool _isHandlingCall = false;
  StreamSubscription? _callSubscription;
  StreamSubscription? _callEndedSubscription;
  bool isCallActive() {
  return _isHandlingCall;
}

  // Timer to reset state if call UI fails to show
  Timer? _callStateResetTimer;

  // Flag to force show call UI on next app resume
  bool _hasPendingCall = false;
  Map<String, dynamic>? _pendingCallData;

  // Initialize call handler
  void initialize(SocketService socketService) {
    // Prevent multiple initializations
    if (_isInitialized) {
      print('StandaloneCallHandler: Already initialized');
      return;
    }

    print('StandaloneCallHandler: Initializing');
    _isInitialized = true;

    // Monitor app lifecycle
    WidgetsBinding.instance.addObserver(_LifecycleObserver(this));

    // Listen to WebRTC offer stream
    _callSubscription = socketService.onWebRTCOffer.listen(
      (callData) {
        print(
            'StandaloneCallHandler: Received call data from stream - $callData');
        _handleIncomingCall(callData);
      },
      onError: (error) {
        print('StandaloneCallHandler: Error in call stream - $error');
      },
      cancelOnError: false,
    );

    // Listen to call ended events
    _callEndedSubscription = socketService.onWebRTCEndCall.listen(
      (callerId) {
        print('StandaloneCallHandler: Call ended by caller - $callerId');
        if (_isHandlingCall) {
          _resetCallState();
          // Try to close any open call dialogs
          final context = navigatorKey.currentContext;
          if (context != null && Navigator.canPop(context)) {
            Navigator.of(context).pop();
          }
        }
      },
      onError: (error) {
        print('StandaloneCallHandler: Error in call ended stream - $error');
      },
      cancelOnError: false,
    );

    socketService.socket?.on('call_rejected', (data) {
      print('StandaloneCallHandler: Call rejected event - $data');
      final callId = data['callId'];
      if (callId != null) {
        onCallEnded(callId);
      }
    });

    socketService.socket?.on('call_ended', (data) {
      print('StandaloneCallHandler: Call ended event - $data');
      final callId = data['callId'];
      if (callId != null) {
        onCallEnded(callId);
      }
    });

    socketService.socket?.on('webrtc_end_call', (data) {
      print('StandaloneCallHandler: WebRTC end call event - $data');
      if (_currentCallId != null) {
        onCallEnded(_currentCallId!);
      }
    });

    // Also listen directly to socket events as backup
    socketService.socket?.on('incoming_call', (data) {
      print('StandaloneCallHandler: Direct incoming call event - $data');
      _handleIncomingCall(data);
    });

    socketService.socket?.on('webrtc_offer', (data) {
      print('StandaloneCallHandler: Direct webrtc_offer event - $data');
      _handleIncomingCall(data);
    });

    socketService.socket?.on('call_ended', (data) {
      print('StandaloneCallHandler: Direct call_ended event - $data');
      if (_isHandlingCall) {
        _resetCallState();
        // Try to close any open call dialogs
        final context = navigatorKey.currentContext;
        if (context != null && Navigator.canPop(context)) {
          Navigator.of(context).pop();
        }
      }
    });
  }

  // Add this method to StandaloneCallHandler class
  void onCallEnded(String callId) {
    print('StandaloneCallHandler: Call ended notification for callId: $callId');
    if (_currentCallId == callId) {
      _forceCloseCallScreen();
      _resetCallState();
    }
  }

// Add this method to StandaloneCallHandler class to force close call screens
  void _forceCloseCallScreen() {
    print('StandaloneCallHandler: Force closing call screen');
    final context = navigatorKey.currentContext;
    if (context != null) {
      try {
        // First try to pop directly
        Navigator.of(context, rootNavigator: true).pop();

        // As a fallback, try to pop until we get back to main app
        Navigator.of(context, rootNavigator: true).popUntil((route) {
          return route.isFirst;
        });

        // Reset our state variables
        _isHandlingCall = false;
        _currentCallId = null;
        _hasPendingCall = false;
        _pendingCallData = null;
      } catch (e) {
        print('Error closing call screen: $e');
      }
    }
  }

  void forceCloseAndReset() {
  print('StandaloneCallHandler: Force closing and resetting all call UI');
  final context = navigatorKey.currentContext;
  if (context != null) {
    try {
      // Try to navigate to home rather than just popping
      Navigator.of(context, rootNavigator: true)
        .pushNamedAndRemoveUntil('/home', (route) => false);
    } catch (e) {
      print('Navigation error: $e');
      // As fallback, try simple pop
      try {
        Navigator.of(context, rootNavigator: true).pop();
      } catch (e) {
        print('Pop fallback error: $e');
      }
    }
  }
  
  // Complete reset of all state variables
  _callStateResetTimer?.cancel();
  _callStateResetTimer = null;
  _isHandlingCall = false;
  _currentCallId = null;
  _hasPendingCall = false;
  _pendingCallData = null;
  
  print('StandaloneCallHandler: State completely reset');
}



  // Called when app lifecycle changes
  void _onAppLifecycleChanged(AppLifecycleState state) {
    print('StandaloneCallHandler: App lifecycle changed to $state');

    // If app becomes active and we have a pending call, process it
    if (state == AppLifecycleState.resumed &&
        _hasPendingCall &&
        _pendingCallData != null) {
      print('StandaloneCallHandler: Processing pending call on app resume');

      // Wait a moment for the app to fully initialize
      Timer(Duration(milliseconds: 500), () {
        final callData = _pendingCallData;
        _pendingCallData = null;
        _hasPendingCall = false;

        if (callData != null) {
          _handleIncomingCall(callData);
        }
      });
    } else if (state == AppLifecycleState.paused) {
      // App is going to background - ensure we have a valid call state
      if (_isHandlingCall && _currentCallId != null) {
        // Keep track of the current call so we can resume it if needed
        print(
            'StandaloneCallHandler: App going to background with active call');
      }
    }
  }

  // Handle incoming call
  void _handleIncomingCall(Map<String, dynamic> callData) {
    // Wake up device first to ensure UI is visible
    HapticFeedback.heavyImpact();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
        overlays: SystemUiOverlay.values);

    // Normalize the call data field names
    final Map<String, dynamic> normalizedCallData = Map.from(callData);

    // Handle different field name patterns
    if (normalizedCallData['callerId'] == null &&
        normalizedCallData['senderId'] != null) {
      normalizedCallData['callerId'] = normalizedCallData['senderId'];
    }

    if (normalizedCallData['senderId'] == null &&
        normalizedCallData['callerId'] != null) {
      normalizedCallData['senderId'] = normalizedCallData['callerId'];
    }

    // Extract normalized data
    final callId = normalizedCallData['callId'];
    final callerId =
        normalizedCallData['callerId'] ?? normalizedCallData['senderId'];
    final callerName = normalizedCallData['callerName'] ?? 'Unknown User';
    final callType = normalizedCallData['callType'] ?? 'audio';

    print(
        'StandaloneCallHandler: Normalized call data - caller: $callerId, call: $callId, type: $callType');

    // Validate normalized data
    if (callId == null || callerId == null) {
      print('StandaloneCallHandler: Invalid call data after normalization');
      return;
    }

    // If we're already handling a call, but it's been a while, we might have a stale state
    // Force reset if it's the same call ID (might be a retry)
    if (_isHandlingCall && _currentCallId == callId) {
      print(
          'StandaloneCallHandler: Same call ID detected, forcing reset of state');
      _resetCallState();
    }
    // For different call while handling another, just log and exit
    else if (_isHandlingCall) {
      print(
          'StandaloneCallHandler: Already handling a different call, ignoring new call');
      return;
    }

    // Ensure we have a valid context
    final context = navigatorKey.currentContext;
    if (context == null) {
      print(
          'StandaloneCallHandler: No valid navigator context, saving as pending call');
      _hasPendingCall = true;
      _pendingCallData = normalizedCallData;
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
        print(
            'StandaloneCallHandler: State still showing handling, but UI might have failed - resetting');
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

    print(
        'StandaloneCallHandler: Processed call data ready for screen - $processedCallData');

    // Use multiple approaches to ensure the call screen shows
    // First try the standard post-frame callback
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showIncomingCallScreen(context, processedCallData);
    });

    // Also immediately try to show as a fallback
    _showIncomingCallScreen(context, processedCallData);
  }

  // Show incoming call screen with improved reliability
  void _showIncomingCallScreen(
      BuildContext context, Map<String, dynamic> callData) {
    // Double-check our state
    if (!_isHandlingCall) {
      print(
          'StandaloneCallHandler: Not handling call anymore, aborting screen display');
      return;
    }

    try {
      // Wake up device again to be extra sure
      HapticFeedback.heavyImpact();
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
          overlays: SystemUiOverlay.values);

      print(
          'StandaloneCallHandler: Attempting to show incoming call screen now');

      // Make sure we're on the UI thread
      if (!WidgetsBinding.instance.isRootWidgetAttached) {
        print(
            'StandaloneCallHandler: Root widget not attached, delaying screen show');
        Future.delayed(Duration(milliseconds: 500), () {
          if (_isHandlingCall) {
            _showIncomingCallScreen(context, callData);
          }
        });
        return;
      }

      // Use showDialog with high elevation to ensure it appears on top
      showDialog(
        context: context,
        barrierDismissible: false,
        useRootNavigator: true,
        barrierColor: Colors.black54,
        builder: (dialogContext) {
          print('StandaloneCallHandler: Dialog builder called');
          return WillPopScope(
            onWillPop: () async => false, // Prevent back button
            child: Material(
              type: MaterialType.transparency,
              elevation: 999, // Very high elevation to ensure visibility
              child: IncomingCallScreen(
                callData: callData,
                onClose: () {
                  print('StandaloneCallHandler: Call screen closing callback');
                  if (Navigator.canPop(dialogContext)) {
                    Navigator.of(dialogContext).pop();
                  }
                  _resetCallState();
                },
              ),
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
    _hasPendingCall = false;
    _pendingCallData = null;
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
    _callEndedSubscription?.cancel();
    _callStateResetTimer?.cancel();
    _resetCallState();
    _isInitialized = false;
  }
}

// Lifecycle observer to track app state
class _LifecycleObserver with WidgetsBindingObserver {
  final StandaloneCallHandler _handler;

  _LifecycleObserver(this._handler) {
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _handler._onAppLifecycleChanged(state);
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }
}
