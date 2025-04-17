import 'dart:async';
import 'package:flutter/material.dart';
import 'package:techniq8chat/screens/call_screen.dart';
import 'package:techniq8chat/services/webrtc_service.dart';

class IncomingCallWidget extends StatefulWidget {
  final String callerId;
  final String callerName;
  final String? profilePicture;
  final CallType callType;
  final Function() onReject;

  const IncomingCallWidget({
    Key? key,
    required this.callerId,
    required this.callerName,
    this.profilePicture,
    required this.callType,
    required this.onReject,
  }) : super(key: key);

  @override
  _IncomingCallWidgetState createState() => _IncomingCallWidgetState();
}

class _IncomingCallWidgetState extends State<IncomingCallWidget> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  
  Timer? _autoRejectTimer;
  int _remainingSeconds = 30; // Auto-reject after 30 seconds
  bool _isAccepting = false;

  @override
  void initState() {
    super.initState();
    
    // Set up animations
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 300),
    );
    
    _slideAnimation = Tween<Offset>(
      begin: Offset(0, -1),
      end: Offset(0, 0),
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    ));
    
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    ));
    
    // Start animations
    _animationController.forward();
    
    // Set up auto-reject timer
    _startAutoRejectTimer();
  }
  
  void _startAutoRejectTimer() {
    _autoRejectTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _remainingSeconds--;
        });
        
        if (_remainingSeconds <= 0) {
          _rejectCall();
        }
      }
    });
  }
  
  void _acceptCall() {
    if (_isAccepting) return; // Prevent multiple taps
    
    setState(() {
      _isAccepting = true;
    });
    
    _autoRejectTimer?.cancel();
    
    // Run animation to hide the widget
    _animationController.reverse().then((_) {
      // Navigate to call screen after the animation completes
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => CallScreen(
            userId: widget.callerId,
            userName: widget.callerName,
            profilePicture: widget.profilePicture,
            callType: widget.callType,
            isOutgoing: false,
          ),
        ),
      );
    });
  }
  
  void _rejectCall() {
    _autoRejectTimer?.cancel();
    
    // Run exit animation and then call onReject
    _animationController.reverse().then((_) {
      widget.onReject();
    });
  }
  
  @override
  void dispose() {
    _animationController.dispose();
    _autoRejectTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isVideoCall = widget.callType == CallType.video;
    
    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 8,
                offset: Offset(0, 4),
              ),
            ],
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(12),
              bottomRight: Radius.circular(12),
            ),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Call info
                Row(
                  children: [
                    // Caller avatar
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: const Color(0xFF2A64F6).withOpacity(0.1),
                      backgroundImage: widget.profilePicture != null && 
                                      widget.profilePicture!.isNotEmpty
                          ? NetworkImage('http://192.168.100.96:4400/${widget.profilePicture}')
                          : null,
                      child: (widget.profilePicture == null || widget.profilePicture!.isEmpty) && 
                              widget.callerName.isNotEmpty
                          ? Text(
                              widget.callerName[0].toUpperCase(),
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF2A64F6),
                              ),
                            )
                          : null,
                    ),
                    SizedBox(width: 12),
                    
                    // Call details
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.callerName,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(
                                isVideoCall ? Icons.videocam : Icons.call,
                                size: 16,
                                color: Colors.green,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Incoming ${isVideoCall ? 'video' : 'audio'} call',
                                style: TextStyle(
                                  color: Colors.grey[700],
                                  fontSize: 14,
                                ),
                              ),
                              SizedBox(width: 4),
                              Text(
                                '($_remainingSeconds)',
                                style: TextStyle(
                                  color: Colors.grey[500],
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                
                SizedBox(height: 16),
                
                // Call actions
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Reject button
                    ElevatedButton.icon(
                      onPressed: _rejectCall,
                      icon: Icon(Icons.call_end, color: Colors.white),
                      label: Text('Decline', style: TextStyle(color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      ),
                    ),
                    
                    // Accept button
                    ElevatedButton.icon(
                      onPressed: _isAccepting ? null : _acceptCall,
                      icon: _isAccepting 
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Icon(
                              isVideoCall ? Icons.videocam : Icons.call,
                              color: Colors.white,
                            ),
                      label: Text('Answer', style: TextStyle(color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        disabledBackgroundColor: Colors.green.withOpacity(0.6),
                      ),
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
}