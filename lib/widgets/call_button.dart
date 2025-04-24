// widgets/call_button.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:techniq8chat/models/user_model.dart';
import 'package:techniq8chat/screens/call_screen.dart';
import 'package:techniq8chat/services/call_service.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:techniq8chat/services/auth_service.dart';

class CallButton extends StatelessWidget {
  final User contactUser;
  final CallType callType;
  
  const CallButton({
    Key? key,
    required this.contactUser,
    this.callType = CallType.audio,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        callType == CallType.audio ? Icons.call : Icons.videocam,
        color: const Color(0xFF2A64F6),
      ),
      onPressed: () => _initiateCall(context),
      tooltip: callType == CallType.audio ? 'Voice Call' : 'Video Call',
    );
  }

  void _initiateCall(BuildContext context) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final currentUser = authService.currentUser;
    
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('You need to be logged in to make calls'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      // Get or create socket instance
      final baseUrl = authService.baseUrl;
      final socket = IO.io(baseUrl, IO.OptionBuilder()
        .setTransports(['websocket'])
        .setQuery({'token': currentUser.token})
        .build());
      
      // Create call service instance
      final callService = CallService(
        baseUrl: baseUrl,
        token: currentUser.token,
        currentUser: currentUser,
        socket: socket,
      );
      
      // Create call details
      final callDetails = CallDetails(
        callId: DateTime.now().millisecondsSinceEpoch.toString(), // Temporary ID
        callerId: currentUser.id,
        callerName: currentUser.username,
        receiverId: contactUser.id,
        receiverName: contactUser.username,
        callType: callType,
      );
      
      // Navigate to call screen
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => CallScreen(
            callService: callService,
            callDetails: callDetails,
            isIncoming: false,
          ),
        ),
      );
      
      // Start the call
      await callService.makeCall(
        contactUser.id,
        contactUser.username,
        callType,
      );
    } catch (e) {
      print('Error initiating call: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to start call: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}