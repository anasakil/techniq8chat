// screens/incoming_call_screen.dart
import 'package:flutter/material.dart';
import 'package:techniq8chat/services/call_service.dart';
import 'package:techniq8chat/screens/call_screen.dart';

class IncomingCallScreen extends StatelessWidget {
  final CallService callService;
  final CallDetails callDetails;
  
  const IncomingCallScreen({
    Key? key,
    required this.callService,
    required this.callDetails,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withOpacity(0.85),
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(height: 60),
            
            // Caller information
            Container(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                children: [
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        callDetails.callerName.isNotEmpty 
                            ? callDetails.callerName[0].toUpperCase() 
                            : "?",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 24),
                  Text(
                    callDetails.callerName,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 12),
                  Text(
                    "Incoming ${callDetails.callType == CallType.video ? 'Video' : 'Voice'} Call",
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ),
            
            Spacer(),
            
            // Call action buttons
            Container(
              padding: EdgeInsets.symmetric(horizontal: 40, vertical: 50),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Decline button
                  _buildActionButton(
                    icon: Icons.call_end,
                    color: Colors.red,
                    label: "Decline",
                    onPressed: () => _declineCall(context),
                  ),
                  
                  SizedBox(width: 40),
                  
                  // Accept button
                  _buildActionButton(
                    icon: callDetails.callType == CallType.video 
                        ? Icons.videocam 
                        : Icons.call,
                    color: Colors.green,
                    label: "Accept",
                    onPressed: () => _acceptCall(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onPressed,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 70,
          height: 70,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: Icon(icon, size: 32),
            color: Colors.white,
            onPressed: onPressed,
          ),
        ),
        SizedBox(height: 12),
        Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
          ),
        ),
      ],
    );
  }

  void _acceptCall(BuildContext context) {
    // Navigate to call screen
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => CallScreen(
          callService: callService,
          callDetails: callDetails,
          isIncoming: true,
        ),
      ),
    );
  }

  void _declineCall(BuildContext context) async {
    await callService.rejectCall();
    Navigator.of(context).pop();
  }
}