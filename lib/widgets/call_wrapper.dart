import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:techniq8chat/services/auth_service.dart';
import 'package:techniq8chat/services/socket_service.dart';
import 'package:techniq8chat/services/webrtc_service.dart';
import 'package:techniq8chat/widgets/incoming_call_widget.dart';

class CallWrapper extends StatefulWidget {
  final Widget child;

  const CallWrapper({
    Key? key, 
    required this.child
  }) : super(key: key);

  @override
  _CallWrapperState createState() => _CallWrapperState();
}

class _CallWrapperState extends State<CallWrapper> {
  final SocketService _socketService = SocketService();
  final WebRTCService _webRTCService = WebRTCService();
  
  // Incoming call data
  String? _incomingCallerId;
  String? _incomingCallerName;
  String? _incomingCallerPhoto;
  CallType? _incomingCallType;
  
  // Stream subscriptions
  StreamSubscription? _offerSubscription;

  @override
  void initState() {
    super.initState();
    _setupWebRTCListener();
  }
  
  void _setupWebRTCListener() {
    // Listen for WebRTC offers (incoming calls)
    _offerSubscription = _socketService.onWebRTCOffer.listen((data) async {
      final authService = Provider.of<AuthService>(context, listen: false);
      final currentUser = authService.currentUser;
      
      if (currentUser == null) return;
      
      // Don't show incoming call if we're already in a call
      if (_webRTCService.isInCall) return;
      
      // Get the caller ID and call type
      final callerId = data['senderId'];
      final callType = data['callType'] == 'video' ? CallType.video : CallType.audio;
      
      // Fetch caller details
      String callerName = 'Unknown User';
      String? callerPhoto;
      
      try {
        // The WebRTC service will fetch user info and update UI accordingly
        // Wait for it to populate the remote user info
        _incomingCallerId = callerId;
        _incomingCallType = callType;
        
        // Show incoming call UI with available info
        setState(() {
          _incomingCallerName = 'Incoming Call';
          _incomingCallerPhoto = null;
        });
        
        // Start a timeout to get caller info
        Timer(Duration(milliseconds: 500), () async {
          // Try to get user info from remote
          final remoteInfoStream = _webRTCService.onRemoteUserInfo.first;
          
          // Set a timeout for the first event
          remoteInfoStream.timeout(
            Duration(seconds: 2),
            onTimeout: () => {
              'userId': callerId,
              'name': 'Unknown User',
              'profilePicture': '',
            },
          ).then((info) {
            setState(() {
              _incomingCallerName = info['name'] ?? 'Unknown User';
              _incomingCallerPhoto = info['profilePicture'];
            });
          });
        });
      } catch (e) {
        print('Error getting caller details: $e');
      }
    });
  }
  
  void _handleRejectCall() {
    if (_incomingCallerId != null) {
      _webRTCService.rejectIncomingCall();
      
      setState(() {
        _incomingCallerId = null;
        _incomingCallerName = null;
        _incomingCallerPhoto = null;
        _incomingCallType = null;
      });
    }
  }
  
  @override
  void dispose() {
    _offerSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Main app content
        widget.child,
        
        // Incoming call widget (if there's an incoming call)
        if (_incomingCallerId != null && _incomingCallType != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IncomingCallWidget(
              callerId: _incomingCallerId!,
              callerName: _incomingCallerName ?? 'Unknown User',
              profilePicture: _incomingCallerPhoto,
              callType: _incomingCallType!,
              onReject: _handleRejectCall,
            ),
          ),
      ],
    );
  }
}