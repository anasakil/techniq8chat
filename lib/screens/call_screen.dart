// lib/screens/call_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:techniq8chat/models/user_model.dart';
import 'package:techniq8chat/services/agora_service.dart';
import 'package:techniq8chat/services/auth_service.dart';

class CallScreen extends StatefulWidget {
  final User remoteUser;
  final CallType callType;
  final bool isIncoming;
  final String? callId;

  const CallScreen({
    Key? key,
    required this.remoteUser,
    required this.callType,
    this.isIncoming = false,
    this.callId,
  }) : super(key: key);

  @override
  _CallScreenState createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  // Agora service
  final AgoraService _agoraService = AgoraService();

  // UI state
  CallState _callState = CallState.idle;
  bool _isMuted = false;
  bool _isVideoEnabled = true;
  bool _isSpeakerEnabled = true;
  bool _isFrontCamera = true;
  String? _errorMessage;

  // Remote user state
  bool _isRemoteVideoEnabled = true;
  int? _remoteUid;

  // Call duration
  Duration _callDuration = Duration.zero;

  // Log messages
  List<String> _logs = [];
  ScrollController _logsScrollController = ScrollController();
  bool _showLogs = false;

  // Stream subscriptions
  StreamSubscription? _callStateSubscription;
  StreamSubscription? _callTimeSubscription;
  StreamSubscription? _remoteUserJoinedSubscription;
  StreamSubscription? _remoteUserLeftSubscription;
  StreamSubscription? _errorSubscription;
  StreamSubscription? _logSubscription;

  @override
  void initState() {
    super.initState();
    // Keep screen on during call
    WakelockPlus.enable(); // Keep screen awake

    // Initialize Agora service
    _initializeAgoraService();

    // Set up log handler
    _agoraService.setLogHandler(_addLog);
  }

  Future<void> _initializeAgoraService() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final currentUser = authService.currentUser;

    if (currentUser == null) {
      setState(() {
        _errorMessage = 'User not authenticated';
      });
      return;
    }

    try {
      // Initialize Agora service
      await _agoraService.initialize(currentUser);

      // Set up event listeners
      _setupEventListeners();

      // Start call or wait for incoming call
      if (widget.isIncoming && widget.callId != null) {
        // Accept incoming call
        await _agoraService.acceptCall(
          widget.remoteUser,
          widget.callId!,
          widget.callType,
        );
      } else {
        // Initiate outgoing call
        await _agoraService.initiateCall(
          widget.remoteUser,
          widget.callType,
        );
      }

      // Update video state based on call type
      setState(() {
        _isVideoEnabled = widget.callType == CallType.video;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to initialize call: $e';
      });
    }
  }

  void _setupEventListeners() {
    // Call state changes
    _callStateSubscription = _agoraService.onCallStateChanged.listen((state) {
      setState(() {
        _callState = state;
      });

      // Exit screen if call ended
      if (state == CallState.ended || state == CallState.error) {
        _handleCallEnded();
      }
    });

    // Call duration updates
    _callTimeSubscription = _agoraService.onCallTimeChanged.listen((duration) {
      setState(() {
        _callDuration = duration;
      });
    });

    // Remote user joined
    _remoteUserJoinedSubscription =
        _agoraService.onRemoteUserJoined.listen((uid) {
      setState(() {
        _remoteUid = uid;
      });
    });

    // Remote user left
    _remoteUserLeftSubscription = _agoraService.onRemoteUserLeft.listen((uid) {
      setState(() {
        _remoteUid = null;
      });
    });

    // Error notifications
    _errorSubscription = _agoraService.onError.listen((error) {
      setState(() {
        _errorMessage = error;
      });
    });

    // Log messages
    _logSubscription = _agoraService.onLog.listen(_addLog);
  }

  void _addLog(String log) {
    setState(() {
      _logs.add('${DateTime.now().toString().substring(11, 19)}: $log');
    });

    // Auto-scroll logs
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logsScrollController.hasClients) {
        _logsScrollController.animateTo(
          _logsScrollController.position.maxScrollExtent,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _handleCallEnded() {
    // If the call ended or had an error, return to previous screen
    Future.delayed(Duration(seconds: 1), () {
      if (mounted) {
        Navigator.pop(context);
      }
    });
  }

  // UI action handlers
  void _onToggleMute() {
    setState(() {
      _isMuted = !_isMuted;
    });
    _agoraService.toggleMicrophone(_isMuted);
  }

  void _onToggleVideo() {
    setState(() {
      _isVideoEnabled = !_isVideoEnabled;
    });
    _agoraService.toggleVideo(_isVideoEnabled);
  }

  void _onSwitchCamera() {
    setState(() {
      _isFrontCamera = !_isFrontCamera;
    });
    _agoraService.switchCamera();
  }

  void _onToggleSpeaker() {
    // Not currently implemented in Agora service
    setState(() {
      _isSpeakerEnabled = !_isSpeakerEnabled;
    });
  }

  void _onEndCall() {
    _agoraService.endCall(notifyServer: true);
  }

  void _toggleLogs() {
    setState(() {
      _showLogs = !_showLogs;
    });
  }

  @override
  void dispose() {
    // Cleanup
    WakelockPlus.disable(); 

    // Cancel subscriptions
    _callStateSubscription?.cancel();
    _callTimeSubscription?.cancel();
    _remoteUserJoinedSubscription?.cancel();
    _remoteUserLeftSubscription?.cancel();
    _errorSubscription?.cancel();
    _logSubscription?.cancel();
    _logsScrollController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Video views
          _buildVideoViews(),

          // UI overlay with user info and controls
          _buildUIOverlay(),

          // Error display
          if (_errorMessage != null) _buildErrorDisplay(),

          // Debug logs
          if (_showLogs) _buildLogs(),
        ],
      ),
    );
  }

  Widget _buildVideoViews() {
    if (widget.callType == CallType.audio) {
      return Container(
        color: const Color(0xFF0A3A59), // Dark blue background for audio calls
      );
    }

    return Stack(
      children: [
        // Remote video (full screen)
        if (_remoteUid != null && _isRemoteVideoEnabled)
          Positioned.fill(
            child: AgoraVideoView(
              controller: VideoViewController.remote(
                rtcEngine: _agoraService.engine!,
                canvas: VideoCanvas(uid: _remoteUid),
                connection: RtcConnection(channelId: _agoraService.channelId!),
              ),
            ),
          )
        else
          Positioned.fill(
            child: Container(
              color: const Color(0xFF0A3A59),
              child: Center(
                child: Icon(
                  Icons.videocam_off,
                  color: Colors.white,
                  size: 60,
                ),
              ),
            ),
          ),

        // Local video (picture-in-picture)
        if (_isVideoEnabled && widget.callType == CallType.video)
          Positioned(
            right: 20,
            top: 80,
            width: 120,
            height: 180,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white, width: 2),
              ),
              clipBehavior: Clip.hardEdge,
              child: AgoraVideoView(
                controller: VideoViewController(
                  rtcEngine: _agoraService.engine!,
                  canvas: const VideoCanvas(uid: 0),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildUIOverlay() {
    return SafeArea(
      child: Column(
        children: [
          // Top area with user info and call status
          _buildTopBar(),

          // Spacer
          Expanded(child: Container()),

          // Bottom area with call controls
          _buildBottomControls(),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withOpacity(0.6),
            Colors.transparent,
          ],
        ),
      ),
      child: Column(
        children: [
          // User info
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: Colors.blue.withOpacity(0.5),
                backgroundImage: widget.remoteUser.profilePicture != null &&
                        widget.remoteUser.profilePicture!.isNotEmpty &&
                        !widget.remoteUser.profilePicture!
                            .contains('default-avatar')
                    ? NetworkImage(
                        'http://51.178.138.50:4400/${widget.remoteUser.profilePicture}')
                    : null,
                child: (widget.remoteUser.profilePicture == null ||
                        widget.remoteUser.profilePicture!.isEmpty ||
                        widget.remoteUser.profilePicture!
                            .contains('default-avatar'))
                    ? Text(
                        widget.remoteUser.username.isNotEmpty
                            ? widget.remoteUser.username[0].toUpperCase()
                            : "?",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      )
                    : null,
              ),
              SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.remoteUser.username,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    _callStateText(),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.normal,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
              Spacer(),
              // Call timer
              if (_callState == CallState.connected)
                Text(
                  _formatDuration(_callDuration),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
              // Debug button
              IconButton(
                icon: Icon(
                  _showLogs ? Icons.bug_report : Icons.bug_report_outlined,
                  color: Colors.white70,
                ),
                onPressed: _toggleLogs,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls() {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 24, horizontal: 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withOpacity(0.6),
            Colors.transparent,
          ],
        ),
      ),
      child: Column(
        children: [
          // Call controls
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Mute button
              _buildControlButton(
                icon: _isMuted ? Icons.mic_off : Icons.mic,
                label: _isMuted ? 'Unmute' : 'Mute',
                onPressed: _onToggleMute,
                isEnabled: !_isMuted,
              ),

              // Video button (only for video calls)
              if (widget.callType == CallType.video)
                _buildControlButton(
                  icon: _isVideoEnabled ? Icons.videocam : Icons.videocam_off,
                  label: _isVideoEnabled ? 'Hide' : 'Show',
                  onPressed: _onToggleVideo,
                  isEnabled: _isVideoEnabled,
                ),

              // Camera flip (only for video calls)
              if (widget.callType == CallType.video)
                _buildControlButton(
                  icon: Icons.flip_camera_ios,
                  label: 'Flip',
                  onPressed: _onSwitchCamera,
                ),

              // Speaker button (only for audio calls)
              if (widget.callType == CallType.audio)
                _buildControlButton(
                  icon: _isSpeakerEnabled ? Icons.volume_up : Icons.volume_down,
                  label: _isSpeakerEnabled ? 'Speaker' : 'Earpiece',
                  onPressed: _onToggleSpeaker,
                  isEnabled: _isSpeakerEnabled,
                ),
            ],
          ),

          SizedBox(height: 24),

          // End call button
          _buildEndCallButton(),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    bool isEnabled = true,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: isEnabled
                ? Colors.grey[800]!.withOpacity(0.8)
                : Colors.red.withOpacity(0.8),
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: Icon(icon, color: Colors.white, size: 24),
            onPressed: onPressed,
          ),
        ),
        SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildEndCallButton() {
    return InkWell(
      onTap: _onEndCall,
      child: Container(
        width: 70,
        height: 70,
        decoration: BoxDecoration(
          color: Colors.red,
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.call_end,
          color: Colors.white,
          size: 36,
        ),
      ),
    );
  }

  Widget _buildErrorDisplay() {
    return Positioned(
      top: 100,
      left: 20,
      right: 20,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.9),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.error, color: Colors.white),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                _errorMessage!,
                style: TextStyle(color: Colors.white),
              ),
            ),
            IconButton(
              icon: Icon(Icons.close, color: Colors.white),
              onPressed: () {
                setState(() {
                  _errorMessage = null;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogs() {
    return Positioned(
      bottom: 180,
      left: 0,
      right: 0,
      top: 80,
      child: Container(
        color: Colors.black.withOpacity(0.85),
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Debug Logs',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: Colors.white),
                  onPressed: _toggleLogs,
                ),
              ],
            ),
            Divider(color: Colors.white30),
            Expanded(
              child: ListView.builder(
                controller: _logsScrollController,
                itemCount: _logs.length,
                itemBuilder: (context, index) {
                  final log = _logs[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      log,
                      style: TextStyle(
                        color: log.contains('error') || log.contains('Error')
                            ? Colors.red
                            : Colors.white70,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper methods
  String _callStateText() {
    switch (_callState) {
      case CallState.outgoing:
        return 'Calling...';
      case CallState.incoming:
        return 'Incoming call...';
      case CallState.connecting:
        return 'Connecting...';
      case CallState.connected:
        return 'Connected';
      case CallState.ended:
        return 'Call ended';
      case CallState.error:
        return 'Call failed';
      default:
        return '';
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    if (duration.inHours > 0) {
      return '${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds';
    } else {
      return '$twoDigitMinutes:$twoDigitSeconds';
    }
  }
}
