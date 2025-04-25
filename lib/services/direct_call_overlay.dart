// services/direct_call_overlay.dart
import 'package:flutter/material.dart';
import 'package:techniq8chat/screens/incoming_call_screen.dart';
import 'package:techniq8chat/services/socket_service.dart';

class DirectCallOverlay {
  static final DirectCallOverlay _instance = DirectCallOverlay._internal();
  factory DirectCallOverlay() => _instance;
  DirectCallOverlay._internal();
 
  // Track if a call is being displayed to prevent duplicates
  bool _isShowingCall = false;
  
  // Global navigator key - must be set in MaterialApp
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  // Set up socket listeners
  void initialize(SocketService socketService) {
    print("DirectCallOverlay: Initializing");
   
    // Direct socket listener for incoming calls
    socketService.socket?.on('incoming_call', (data) {
      print("DirectCallOverlay: Incoming call received: $data");
      _showSimpleCallScreen(data);
    });
   
    // Also listen to webrtc_offer events as an alternative
    socketService.socket?.on('webrtc_offer', (data) {
      print("DirectCallOverlay: WebRTC offer received: $data");
      _showSimpleCallScreen(data);
    });
  }

  // Simple function to show incoming call UI
  void _showSimpleCallScreen(Map<String, dynamic> callData) {
    // Prevent showing multiple call screens
    if (_isShowingCall) {
      print("DirectCallOverlay: Already showing a call, ignoring");
      return;
    }
    
    print("DirectCallOverlay: Attempting to show simple call UI");
    
    // Get the context from our navigatorKey
    final context = navigatorKey.currentContext;
    if (context == null) {
      print("DirectCallOverlay: No valid context found");
      return;
    }
    
    _isShowingCall = true;
    
    // Show a simple full-screen dialog
    WidgetsBinding.instance.addPostFrameCallback((_) {
      print("DirectCallOverlay: Building the call screen");
      
      // Create basic incoming call screen widget
      final callScreen = Scaffold(
        backgroundColor: Colors.blue[800],
        body: IncomingCallScreen(
          callData: callData,
          onClose: () {
            print("DirectCallOverlay: Call screen closed");
            _isShowingCall = false;
            Navigator.of(context).pop();
          },
        ),
      );
      
      try {
        // Show a basic material route
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => callScreen,
            fullscreenDialog: true,
          ),
        ).then((_) {
          _isShowingCall = false;
          print("DirectCallOverlay: Call screen navigator route closed");
        });
        
        print("DirectCallOverlay: Call UI push completed");
      } catch (e) {
        print("DirectCallOverlay: Error showing call UI: $e");
        _isShowingCall = false;
      }
    });
  }
  
  // Clear the current call UI
  void clearCallUI() {
    _isShowingCall = false;
    print("DirectCallOverlay: clearCallUI called");
  }
}