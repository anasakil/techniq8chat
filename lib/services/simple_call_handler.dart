// services/simple_call_handler.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:techniq8chat/screens/incoming_call_screen.dart';
import 'package:techniq8chat/services/socket_service.dart';

/// A simplified call handler that focuses on UI display without notifications
class SimpleCallHandler {
  static final SimpleCallHandler _instance = SimpleCallHandler._internal();
  factory SimpleCallHandler() => _instance;
  SimpleCallHandler._internal();

  bool _isInitialized = false;
  bool _handlingCall = false;
  GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  
  // Handle to top-level overlay entry when showing call UI
  OverlayEntry? _activeCallOverlay;

  void initialize(SocketService socketService) {
    if (_isInitialized) return;
    
    print("Initializing SimpleCallHandler");
    
    // Set up listeners for incoming calls
    socketService.socket?.on('incoming_call', (data) {
      print("DIRECT INCOMING CALL EVENT: $data");
      _showIncomingCallUI(data);
    });
    
    socketService.socket?.on('webrtc_offer', (data) {
      print("DIRECT WEBRTC OFFER EVENT: $data");
      _showIncomingCallUI(data);
    });
    
    _isInitialized = true;
  }
  
  void _showIncomingCallUI(Map<String, dynamic> callData) {
    // Prevent multiple incoming call screens
    if (_handlingCall) {
      print("Already handling a call, ignoring new incoming call");
      return;
    }
    
    print("Attempting to show incoming call UI: $callData");
    _handlingCall = true;
    
    // Try to get current context
    final context = navigatorKey.currentContext;
    if (context == null) {
      print("ERROR: No valid context to show incoming call screen");
      _handlingCall = false;
      return;
    }
    
    // Try to wake up the device screen
    SystemChannels.platform.invokeMethod('SystemChrome.setEnabledSystemUIMode', []);
    
    // Ensure we're on the UI thread
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        print("SHOWING INCOMING CALL UI");
        
        // Try several methods to ensure UI appears
        
        // Method 1: Dialog
        _tryShowDialog(context, callData);
        
        // Method 2: Overlay (as backup)
        if (context.mounted) {
          _tryShowOverlay(context, callData);
        }
      } catch (e) {
        print("ERROR SHOWING INCOMING CALL UI: $e");
        _handlingCall = false;
      }
    });
  }
  
  void _tryShowDialog(BuildContext context, Map<String, dynamic> callData) {
    try {
      showGeneralDialog(
        context: context,
        barrierDismissible: false,
        transitionDuration: Duration(milliseconds: 300),
        barrierColor: Colors.black.withOpacity(0.5),
        pageBuilder: (context, animation, secondaryAnimation) {
          return WillPopScope(
            onWillPop: () async => false, // Prevent back button
            child: Material(
              type: MaterialType.transparency,
              child: IncomingCallScreen(
                callData: callData,
                onClose: () {
                  _handlingCall = false;
                },
              ),
            ),
          );
        },
      ).then((_) {
        // Ensure flag is reset if dialog is closed
        _handlingCall = false;
      });
      
      print("Dialog shown successfully");
    } catch (e) {
      print("Error showing dialog: $e");
    }
  }
  
  void _tryShowOverlay(BuildContext context, Map<String, dynamic> callData) {
    try {
      // Remove any existing overlay
      _activeCallOverlay?.remove();
      _activeCallOverlay = null;
      
      // Create new overlay
      final overlay = OverlayEntry(
        builder: (context) => Material(
          type: MaterialType.transparency,
          child: IncomingCallScreen(
            callData: callData,
            onClose: () {
              _activeCallOverlay?.remove();
              _activeCallOverlay = null;
              _handlingCall = false;
            },
          ),
        ),
      );
      
      // Insert the overlay
      Overlay.of(context).insert(overlay);
      _activeCallOverlay = overlay;
      
      print("Overlay shown successfully");
    } catch (e) {
      print("Error showing overlay: $e");
    }
  }
  
  void dismissCurrentCall() {
    if (_activeCallOverlay != null) {
      _activeCallOverlay?.remove();
      _activeCallOverlay = null;
    }
    _handlingCall = false;
  }
}