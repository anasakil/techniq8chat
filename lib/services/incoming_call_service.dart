// screens/incoming_call_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:techniq8chat/services/call_service.dart';

class IncomingCallScreen extends StatefulWidget {
  final Map<String, dynamic> callData;
  final VoidCallback? onClose;

  const IncomingCallScreen({
    Key? key,
    required this.callData,
    this.onClose,
  }) : super(key: key);

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> {
  bool _isAccepting = false;
  bool _isRejecting = false;

  @override
  void initState() {
    super.initState();
    print("INCOMING CALL SCREEN INITIALIZED WITH DATA: ${widget.callData}");
    
    // Force the screen to be in portrait mode
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    
    // Keep screen on while call screen is displayed
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual, 
      overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom]
    );
    
    // You could play a ringtone here
  }
  
  @override
  void dispose() {
    // Restore system UI and orientation
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values
    );
    
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final callerName = widget.callData['callerName'] ?? 'Unknown';
    final callType = widget.callData['callType'] ?? 'voice';
    final callId = widget.callData['callId'];
    final callerId = widget.callData['callerId'];
    
    // Add debug info
    print("Building incoming call UI for: $callerName, ID: $callId, Caller ID: $callerId, Type: $callType");
    
    return Scaffold(
      backgroundColor: const Color(0xFF2A64F6),
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Incoming call header
            Padding(
              padding: const EdgeInsets.only(top: 60),
              child: Column(
                children: [
                  Text(
                    'Incoming ${callType == 'video' ? 'Video' : 'Voice'} Call',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 40),
                  CircleAvatar(
                    radius: 60,
                    backgroundColor: Colors.white.withOpacity(0.2),
                    child: Text(
                      callerName.isNotEmpty ? callerName[0].toUpperCase() : "?",
                      style: const TextStyle(
                        fontSize: 50,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    callerName,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            
            // Call actions
            Padding(
              padding: const EdgeInsets.only(bottom: 60),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Decline button
                  _buildActionButton(
                    icon: Icons.call_end_rounded,
                    backgroundColor: Colors.red,
                    text: 'Decline',
                    isLoading: _isRejecting,
                    onPressed: _isAccepting ? null : _handleRejectCall,
                  ),
                  
                  // Accept button
                  _buildActionButton(
                    icon: Icons.call_rounded,
                    backgroundColor: Colors.green,
                    text: 'Accept',
                    isLoading: _isAccepting,
                    onPressed: _isRejecting ? null : _handleAcceptCall,
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
    required Color backgroundColor,
    required String text,
    required VoidCallback? onPressed,
    bool isLoading = false,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(35),
          child: Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: backgroundColor,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: isLoading
                  ? CircularProgressIndicator(color: Colors.white)
                  : Icon(
                      icon,
                      color: Colors.white,
                      size: 35,
                    ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          text,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  void _handleAcceptCall() async {
    print("ACCEPTING CALL: ${widget.callData}");
    
    if (_isAccepting) return;
    
    setState(() {
      _isAccepting = true;
    });
    
    try {
      // Important: Only use CallService, not DirectCallOverlay
      final callService = Provider.of<CallService>(context, listen: false);
      
      // Call the onClose callback first to prevent UI issues
      if (widget.onClose != null) {
        widget.onClose!();
      } else {
        print("Warning: No onClose callback provided");
      }
      
      // Answer the call
      await callService.answerCall(context, widget.callData);
    } catch (e) {
      print('Error accepting call: $e');
      
      // Show error briefly
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to accept call: $e')),
      );
      
      // Close the incoming call screen on error
      if (widget.onClose != null) {
        widget.onClose!();
      } else {
        // Try to pop the screen if no callback
        Navigator.of(context).pop();
      }
    }
  }

  void _handleRejectCall() async {
    print("REJECTING CALL: ${widget.callData}");
    
    if (_isRejecting) return;
    
    setState(() {
      _isRejecting = true;
    });
    
    try {
      // Important: Only use CallService, not DirectCallOverlay
      final callService = Provider.of<CallService>(context, listen: false);
      
      // Reject the call
      await callService.rejectCall(context, widget.callData);
      
      // Call the onClose callback
      if (widget.onClose != null) {
        widget.onClose!();
      } else {
        print("Warning: No onClose callback provided");
        Navigator.of(context).pop();
      }
    } catch (e) {
      print('Error rejecting call: $e');
      
      // Ensure UI is dismissed
      if (widget.onClose != null) {
        widget.onClose!();
      } else {
        Navigator.of(context).pop();
      }
    }
  }
}