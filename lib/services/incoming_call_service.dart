// services/incoming_call_service.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:techniq8chat/screens/incoming_call_screen.dart';
import 'package:techniq8chat/services/socket_service.dart';

/// A simpler, more direct service to handle incoming calls
/// This bypasses some of the complexity that might be causing issues
class IncomingCallService {
  static final IncomingCallService _instance = IncomingCallService._internal();
  factory IncomingCallService() => _instance;
  IncomingCallService._internal();

  bool _isInitialized = false;
  bool _handlingCall = false;
  BuildContext? _context;
  
  // Initialize with the global navigator key so we can show overlays from anywhere
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  void initialize(SocketService socketService) {
    if (_isInitialized) return;
    
    print("Initializing IncomingCallService");
    
    // Set up listeners for incoming calls
    socketService.socket?.on('incoming_call', (data) {
      print("DIRECT INCOMING CALL EVENT: $data");
      _showIncomingCallScreen(data);
    });
    
    socketService.socket?.on('webrtc_offer', (data) {
      print("DIRECT WEBRTC OFFER EVENT: $data");
      _showIncomingCallScreen(data);
    });
    
    _isInitialized = true;
  }
  
  void setContext(BuildContext context) {
    _context = context;
  }

  void _showIncomingCallScreen(Map<String, dynamic> callData) {
    // Prevent multiple incoming call screens
    if (_handlingCall) {
      print("Already handling a call, ignoring new incoming call");
      return;
    }
    
    _handlingCall = true;
    
    // Try to find a valid context to show the incoming call screen
    BuildContext? context = _context;
    
    // Use the navigator key if we don't have a direct context
    if (context == null && navigatorKey.currentContext != null) {
      context = navigatorKey.currentContext;
    }
    
    if (context == null) {
      print("ERROR: No valid context to show incoming call screen");
      _handlingCall = false;
      return;
    }
    
    // Ensure we're on the UI thread
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        print("SHOWING INCOMING CALL SCREEN");
        
        // Show full-screen dialog for incoming call
        showDialog(
          context: context!,
          barrierDismissible: false,
          useSafeArea: false,
          builder: (_) => IncomingCallScreen(callData: callData),
        ).then((_) {
          _handlingCall = false;
        });
      } catch (e) {
        print("ERROR SHOWING INCOMING CALL SCREEN: $e");
        _handlingCall = false;
      }
    });
  }
}