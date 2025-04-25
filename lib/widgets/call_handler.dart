// widgets/call_handler.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:techniq8chat/screens/incoming_call_screen.dart';
import 'package:techniq8chat/services/call_service.dart';

class CallHandler extends StatefulWidget {
  final Widget child;
  
  const CallHandler({
    Key? key,
    required this.child,
  }) : super(key: key);

  @override
  _CallHandlerState createState() => _CallHandlerState();
}

class _CallHandlerState extends State<CallHandler> {
  StreamSubscription? _incomingCallSubscription;
  bool _isHandlingCall = false;

  @override
  void initState() {
    super.initState();
    // Delay setup to ensure context is available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupCallListener();
    });
  }

  void _setupCallListener() {
    print("Setting up call listener in CallHandler");
    final callService = Provider.of<CallService>(context, listen: false);
    
    _incomingCallSubscription = callService.onIncomingCall.listen((callData) {
      print("Incoming call received in CallHandler: $callData");
      
      // Prevent multiple call screens from opening
      if (_isHandlingCall) {
        print("Already handling a call, ignoring");
        return;
      }
      
      setState(() {
        _isHandlingCall = true;
      });
      
      // Debug - ensure we have the required data
      final callerId = callData['callerId'];
      final callerName = callData['callerName'];
      final callId = callData['callId'];
      
      print("Call from: $callerName ($callerId), Call ID: $callId");
      
      // Ensure we're on UI thread
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Navigate to incoming call screen
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => IncomingCallScreen(callData: callData),
          ),
        ).then((_) {
          setState(() {
            _isHandlingCall = false;
          });
        });
      });
    });

    print("Call listener setup complete");
  }

  @override
  void dispose() {
    print("Disposing CallHandler");
    _incomingCallSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}