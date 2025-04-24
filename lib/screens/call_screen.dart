// screens/call_screen.dart
import 'package:flutter/material.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:techniq8chat/services/call_service.dart';

class CallScreen extends StatefulWidget {
  final CallService callService;
  final CallDetails callDetails;
  final bool isIncoming;
  
  const CallScreen({
    Key? key,
    required this.callService,
    required this.callDetails,
    this.isIncoming = false,
  }) : super(key: key);

  @override
  _CallScreenState createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  bool _localAudioMuted = false;
  bool _localVideoMuted = false;
  RtcEngine? get _engine => widget.callService.engine; // Get engine via public getter
  CallStatus _callStatus = CallStatus.connecting;
  int? _remoteUid;

  @override
  void initState() {
    super.initState();
    _setupCall();
  }

  void _setupCall() async {
    // Listen for call status changes
    widget.callService.callStatusStream.listen((status) {
      setState(() {
        _callStatus = status;
      });
      
      if (status == CallStatus.disconnected) {
        // Call ended, navigate back
        Navigator.of(context).pop();
      }
    });
    
    // If it's an incoming call, answer it
    if (widget.isIncoming) {
      await widget.callService.answerCall();
    }
    
    // Set up video event handlers if using the video call
    if (widget.callDetails.callType == CallType.video && _engine != null) {
      _engine!.registerEventHandler(RtcEngineEventHandler(
        onUserJoined: (connection, remoteUid, elapsed) {
          setState(() {
            _remoteUid = remoteUid;
          });
        },
        onUserOffline: (connection, remoteUid, reason) {
          setState(() {
            _remoteUid = null;
          });
        },
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Background (or video feed for video calls)
          _buildCallBackground(),
          
          // Call info and UI
          SafeArea(
            child: Column(
              children: [
                // Top bar with user info
                _buildTopBar(),
                
                Spacer(),
                
                // Call controls
                _buildCallControls(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCallBackground() {
    // For video calls, show the video feed
    if (widget.callDetails.callType == CallType.video) {
      return Stack(
        children: [
          // Remote video view (full screen)
          if (_remoteUid != null && _engine != null)
            Positioned.fill(
              child: AgoraVideoView(
                controller: VideoViewController.remote(
                  rtcEngine: _engine!,
                  canvas: VideoCanvas(uid: _remoteUid),
                  connection: RtcConnection(channelId: widget.callDetails.callId),
                ),
              ),
            ),
          
          // Local video view (small corner)
          Positioned(
            right: 20,
            top: 100,
            width: 120,
            height: 180,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.hardEdge,
              child: !_localVideoMuted && _engine != null
                  ? AgoraVideoView(
                      controller: VideoViewController(
                        rtcEngine: _engine!,
                        canvas: const VideoCanvas(uid: 0),
                      ),
                    )
                  : Center(
                      child: Icon(
                        Icons.videocam_off,
                        color: Colors.white,
                        size: 40,
                      ),
                    ),
            ),
          ),
        ],
      );
    }
    
    // For audio calls, show a gradient background
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF2A64F6),
            const Color(0xFF2A64F6).withOpacity(0.8),
            const Color(0xFF2A64F6).withOpacity(0.6),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final isRemote = widget.callDetails.callerId != widget.callService.currentUser.id;
    final displayName = isRemote 
        ? widget.callDetails.callerName 
        : widget.callDetails.receiverName;
    
    return Container(
      padding: EdgeInsets.all(20),
      child: Column(
        children: [
          SizedBox(height: 20),
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: Colors.white24,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                displayName.isNotEmpty ? displayName[0].toUpperCase() : "?",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          SizedBox(height: 16),
          Text(
            displayName,
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8),
          Text(
            _getCallStatusText(),
            style: TextStyle(
              color: Colors.white70,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  String _getCallStatusText() {
    switch (_callStatus) {
      case CallStatus.connecting:
        return "Connecting...";
      case CallStatus.connected:
        return widget.callDetails.callType == CallType.video 
            ? "Video Call" 
            : "Voice Call";
      case CallStatus.disconnected:
        return "Call Ended";
      default:
        return "";
    }
  }

  Widget _buildCallControls() {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 40),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Mute/Unmute audio button
          _buildControlButton(
            icon: _localAudioMuted ? Icons.mic_off : Icons.mic,
            backgroundColor: Colors.white30,
            onPressed: _toggleMute,
            tooltip: _localAudioMuted ? 'Unmute' : 'Mute',
          ),
          
          SizedBox(width: 24),
          
          // End call button
          _buildControlButton(
            icon: Icons.call_end,
            backgroundColor: Colors.red,
            onPressed: _onEndCallPressed,
            size: 70,
            iconSize: 32,
            tooltip: 'End Call',
          ),
          
          SizedBox(width: 24),
          
          // Video on/off button (for video calls only)
          if (widget.callDetails.callType == CallType.video)
            _buildControlButton(
              icon: _localVideoMuted ? Icons.videocam_off : Icons.videocam,
              backgroundColor: Colors.white30,
              onPressed: _toggleVideo,
              tooltip: _localVideoMuted ? 'Turn on camera' : 'Turn off camera',
            )
          else
            _buildControlButton(
              icon: Icons.volume_up,
              backgroundColor: Colors.white30,
              onPressed: () {
                // Toggle speaker
              },
              tooltip: 'Speaker',
            ),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required Color backgroundColor,
    required VoidCallback onPressed,
    double size = 60,
    double iconSize = 28,
    required String tooltip,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor,
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: Icon(icon, size: iconSize),
        color: Colors.white,
        onPressed: onPressed,
        tooltip: tooltip,
      ),
    );
  }

  void _toggleMute() async {
    setState(() {
      _localAudioMuted = !_localAudioMuted;
    });
    if (_engine != null) {
      await _engine?.enableLocalAudio(!_localAudioMuted);
    }
  }

  void _toggleVideo() async {
    setState(() {
      _localVideoMuted = !_localVideoMuted;
    });
    if (_engine != null) {
      await _engine?.enableLocalVideo(!_localVideoMuted);
    }
  }

  void _onEndCallPressed() async {
    await widget.callService.endCall();
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    super.dispose();
  }
}