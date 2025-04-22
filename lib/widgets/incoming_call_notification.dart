// lib/widgets/incoming_call_notification.dart
import 'package:flutter/material.dart';
import 'package:techniq8chat/models/user_model.dart';
import 'package:techniq8chat/screens/call_screen.dart';
import 'package:techniq8chat/services/agora_service.dart';

class IncomingCallNotification extends StatefulWidget {
  final User caller;
  final String callId;
  final CallType callType;
  final VoidCallback onReject;
  final VoidCallback onAccept;

  const IncomingCallNotification({
    Key? key,
    required this.caller,
    required this.callId,
    required this.callType,
    required this.onReject,
    required this.onAccept,
  }) : super(key: key);

  @override
  _IncomingCallNotificationState createState() => _IncomingCallNotificationState();
}

class _IncomingCallNotificationState extends State<IncomingCallNotification> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  
  @override
  void initState() {
    super.initState();
    
    // Initialize animations
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 400),
    );
    
    _slideAnimation = Tween<Offset>(
      begin: Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    ));
    
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeIn,
    ));
    
    // Play entrance animation
    _animationController.forward();
  }
  
  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }
  
  void _dismiss() {
    _animationController.reverse().then((_) {
      if (mounted) {
        widget.onReject();
      }
    });
  }
  
  void _accept() {
    _animationController.reverse().then((_) {
      if (mounted) {
        widget.onAccept();
        
        // Navigate to call screen
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CallScreen(
              remoteUser: widget.caller,
              callType: widget.callType,
              isIncoming: true,
              callId: widget.callId,
            ),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 10,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Call type badge
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: widget.callType == CallType.video
                        ? Colors.blue.withOpacity(0.1)
                        : Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        widget.callType == CallType.video
                            ? Icons.videocam
                            : Icons.call,
                        color: widget.callType == CallType.video
                            ? Colors.blue
                            : Colors.green,
                        size: 16,
                      ),
                      SizedBox(width: 4),
                      Text(
                        widget.callType == CallType.video
                            ? 'Video Call'
                            : 'Audio Call',
                        style: TextStyle(
                          color: widget.callType == CallType.video
                              ? Colors.blue
                              : Colors.green,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 16),
                
                // Caller avatar
                CircleAvatar(
                  radius: 36,
                  backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
                  backgroundImage: widget.caller.profilePicture != null &&
                                 widget.caller.profilePicture!.isNotEmpty &&
                                 !widget.caller.profilePicture!.contains('default-avatar')
                      ? NetworkImage('http://51.178.138.50:4400/${widget.caller.profilePicture}')
                      : null,
                  child: (widget.caller.profilePicture == null ||
                         widget.caller.profilePicture!.isEmpty ||
                         widget.caller.profilePicture!.contains('default-avatar'))
                      ? Text(
                          widget.caller.username.isNotEmpty
                              ? widget.caller.username[0].toUpperCase()
                              : "?",
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).primaryColor,
                          ),
                        )
                      : null,
                ),
                SizedBox(height: 16),
                
                // Caller name
                Text(
                  widget.caller.username,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 4),
                
                // Call description
                Text(
                  'Incoming call...',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                  ),
                ),
                SizedBox(height: 24),
                
                // Call actions
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Reject button
                    _buildCallActionButton(
                      icon: Icons.call_end,
                      color: Colors.red,
                      onTap: _dismiss,
                      label: 'Decline',
                    ),
                    
                    // Accept button
                    _buildCallActionButton(
                      icon: widget.callType == CallType.video
                          ? Icons.videocam
                          : Icons.call,
                      color: Colors.green,
                      onTap: _accept,
                      label: 'Accept',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildCallActionButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    required String label,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 30,
            ),
          ),
        ),
        SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}