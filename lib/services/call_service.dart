// services/call_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:techniq8chat/screens/call_screen.dart';
import 'package:techniq8chat/screens/incoming_call_screen.dart';
import 'package:techniq8chat/services/auth_service.dart';
import 'package:techniq8chat/services/socket_service.dart';

class CallService {
  static final CallService _instance = CallService._internal();
  factory CallService() => _instance;
  CallService._internal();

  // Agora
  RtcEngine? _engine;
  final String agoraAppId = 'd35effd01b264bac87f3e87a973d92a9';

  // Call state
  bool isCallActive = false;
  bool isCallConnected = false;
  bool isLocalAudioMuted = false;
  CallType callType = CallType.voice;
  String? currentCallId;
  String? remoteUserId;
  String? remoteUsername;

  // Stream controllers
  final StreamController<Map<String, dynamic>> _onIncomingCall =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _onCallStatusChange =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<bool> _onRemoteUserJoined =
      StreamController<bool>.broadcast();
  final StreamController<bool> _onCallEnded =
      StreamController<bool>.broadcast();

  // Streams
  Stream<Map<String, dynamic>> get onIncomingCall => _onIncomingCall.stream;
  Stream<Map<String, dynamic>> get onCallStatusChange =>
      _onCallStatusChange.stream;
  Stream<bool> get onRemoteUserJoined => _onRemoteUserJoined.stream;
  Stream<bool> get onCallEnded => _onCallEnded.stream;

  // Initialize the call service and set up listeners
  Future<void> initialize(SocketService socketService) async {
    print('Initializing CallService');

    // Set up socket listeners
    socketService.socket?.on('incoming_call', (data) {
      print('Incoming call received in CallService: $data');

      // Extract data from the incoming call event
      final callerId = data['callerId'] ?? data['senderId'];
      final callerName = data['callerName'] ?? 'Unknown User';
      final callId = data['callId'];
      final callType = data['callType'] ?? 'voice';

      if (callerId == null || callId == null) {
        print('Invalid incoming call data: $data');
        return;
      }

      // Add the call data to the stream with normalized format
      _onIncomingCall.add({
        'callerId': callerId,
        'callerName': callerName,
        'callId': callId,
        'callType': callType,
      });

      print('Emitted incoming call to stream: $callerId, $callerName, $callId');
    });

    // Also listen for webrtc_offer as an alternative event name
    socketService.socket?.on('webrtc_offer', (data) {
      print('WebRTC offer received in CallService: $data');

      // Extract data from the offer event
      final senderId = data['senderId'] ?? data['callerId'];
      final callId = data['callId'];
      final callType = data['callType'] ?? 'voice';

      if (senderId == null || callId == null) {
        print('Invalid webrtc_offer data: $data');
        return;
      }

      // Get the sender name (might need to be fetched)
      final callerName = data['callerName'] ?? 'Unknown User';

      // Add the call data to the stream with normalized format
      _onIncomingCall.add({
        'callerId': senderId,
        'callerName': callerName,
        'callId': callId,
        'callType': callType,
      });

      print('Emitted WebRTC offer to stream: $senderId, $callerName, $callId');
    });

    socketService.socket?.on('call_status_update', (data) {
      print('Call status update: $data');
      _onCallStatusChange.add(data);

      if (data['status'] == 'ended') {
        print('Call ended via status update');
        _onCallEnded.add(true);
        endCall();
      }
    });

    socketService.socket?.on('call_answered', (data) {
      print('Call answered: $data');
      isCallConnected = true;
      _onRemoteUserJoined.add(true);
    });

    socketService.socket?.on('call_rejected', (data) {
      print('Call rejected: $data');
      _onCallEnded.add(true);

      // Reset state
      isCallActive = false;
      isCallConnected = false;
      currentCallId = null;
      remoteUserId = null;
      remoteUsername = null;
    });

    socketService.socket?.on('call_ended', (data) {
      print('Call ended by remote user: $data');
      _onCallEnded.add(true);
      endCall();
    });

    // Handle the event when socket disconnects during a call
    socketService.socket?.on('disconnect', (_) {
      print('Socket disconnected during call check');
      if (isCallActive) {
        print('Socket disconnected during active call - ending call');
        _onCallEnded.add(true);
      }
    });
  }




  // Toggle speaker mode
Future<bool> toggleSpeaker() async {
  if (!isCallActive || _engine == null) return false;

  try {
    // Get current speaker status first
    final currentStatus = await _engine!.isSpeakerphoneEnabled();
    
    // Toggle to opposite state
    await _engine!.setEnableSpeakerphone(!currentStatus);
    
    // Verify the new state
    final newStatus = await _engine!.isSpeakerphoneEnabled();
    
    print('Speaker toggled from $currentStatus to $newStatus');
    return newStatus;
  } catch (e) {
    print('Error toggling speaker: $e');
    // Return the previous value as fallback
    try {
      return await _engine!.isSpeakerphoneEnabled();
    } catch (_) {
      return false;
    }
  }
}

// Check if speaker is enabled
Future<bool> isSpeakerEnabled() async {
  if (!isCallActive || _engine == null) return false;

  try {
    return await _engine!.isSpeakerphoneEnabled();
  } catch (e) {
    print('Error checking speaker status: $e');
    return false;
  }
}




  // Initialize Agora engine
  Future<void> _initializeAgoraEngine() async {
    if (_engine != null) return;

    _engine = createAgoraRtcEngine();
    await _engine!.initialize(RtcEngineContext(
      appId: agoraAppId,
      channelProfile: ChannelProfileType.channelProfileCommunication,
    ));

    _engine!.registerEventHandler(RtcEngineEventHandler(
      onJoinChannelSuccess: (connection, elapsed) {
        print('Local user joined the channel');
      },
      onUserJoined: (connection, remoteUid, elapsed) {
        print('Remote user joined: $remoteUid');
        _onRemoteUserJoined.add(true);
      },
      onUserOffline: (connection, remoteUid, reason) {
        print('Remote user left: $remoteUid, reason: $reason');
        _onCallEnded.add(true);
      },
      onError: (err, msg) {
        print('Agora error: $err, $msg');
      },
    ));
  }

  // Make a call to another user
  Future<void> makeCall(BuildContext context, String receiverId,
      String receiverName, CallType type) async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final socketService = Provider.of<SocketService>(context, listen: false);

      if (authService.currentUser == null) {
        throw Exception('Not authenticated');
      }

      // Create call record on server
      final response = await http.post(
        Uri.parse('${authService.baseUrl}/api/calls'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${authService.currentUser!.token}',
        },
        body: json.encode({
          'receiverId': receiverId,
          'callType': type == CallType.voice ? 'audio' : 'video',
          'status': 'initiated'
        }),
      );

      if (response.statusCode != 201) {
        throw Exception('Failed to create call record');
      }

      final callData = json.decode(response.body);
      final callId = callData['callId'];

      // Update state
      isCallActive = true;
      currentCallId = callId;
      remoteUserId = receiverId;
      remoteUsername = receiverName;
      callType = type;

      // Initialize Agora engine
      await _initializeAgoraEngine();

      // Request token from server
      final tokenResponse = await http.post(
        Uri.parse('${authService.baseUrl}/api/calls/agora-token'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${authService.currentUser!.token}',
        },
        body: json.encode({
          'channelName': callId,
          'uid': 0, // Use 0 for a dynamically assigned uid
        }),
      );

      String? token;
      if (tokenResponse.statusCode == 200) {
        final tokenData = json.decode(tokenResponse.body);
        token = tokenData['token'];
      }

      // Enable audio
      await _engine!.enableAudio();

      // Disable video for voice calls
      if (type == CallType.voice) {
        await _engine!.disableVideo();
      } else {
        await _engine!.enableVideo();
      }

      // Join channel
      await _engine!.joinChannel(
        token: token ?? '',
        channelId: callId,
        uid: 0,
        options: const ChannelMediaOptions(
          channelProfile: ChannelProfileType.channelProfileCommunication,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
        ),
      );

      // Navigate to call screen
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => CallScreen(
            userId: receiverId,
            username: receiverName,
            callType: type,
            callId: callId,
          ),
        ),
      );

      // Send signal to receiver via socket
      socketService.socket?.emit('webrtc_offer', {
        'receiverId': receiverId,
        'callType': type == CallType.voice ? 'audio' : 'video',
        'callId': callId,
        'callerName': authService.currentUser!.username,
      });
    } catch (e) {
      print('Error making call: $e');
      isCallActive = false;
      currentCallId = null;
      remoteUserId = null;
      remoteUsername = null;
      throw e;
    }
  }

  // Update this method in your call_service.dart file

// In call_service.dart, update the answerCall method

  // In call_service.dart, update the answerCall method with better null checks

  Future<void> answerCall(
      BuildContext context, Map<String, dynamic> callData) async {
    try {
      // First check that the callData is valid
      if (callData == null) {
        throw Exception('Call data is null');
      }

      final authService = Provider.of<AuthService>(context, listen: false);
      final socketService = Provider.of<SocketService>(context, listen: false);

      // Extract values with null safety
      final callerId = callData['callerId'];
      final callerName = callData['callerName'] ?? 'Unknown';
      final callId = callData['callId'];
      final callTypeStr = callData['callType'] ?? 'audio';

      print(
          'Answering call: callerId=$callerId, callId=$callId, type=$callTypeStr');

      if (callerId == null || callId == null) {
        throw Exception('Invalid call data: missing callerId or callId');
      }

      // Update state first so UI can respond accordingly
      isCallActive = true;
      isCallConnected = true;
      currentCallId = callId;
      remoteUserId = callerId;
      remoteUsername = callerName;
      callType = callTypeStr == 'video' ? CallType.video : CallType.voice;

      // Make sure we have initialized the engine before proceeding
      if (_engine == null) {
        print('Initializing Agora engine before answering call');
        await _initializeAgoraEngine();
      }

      // Verify the engine was initialized successfully
      if (_engine == null) {
        throw Exception('Failed to initialize Agora engine');
      }

      // Navigate to call screen first so the user sees something happening
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => CallScreen(
            userId: callerId,
            username: callerName,
            callType: callType,
            callId: callId,
          ),
        ),
      );

      // Update server with call status - with null check for authService.currentUser
      if (authService.currentUser != null) {
        try {
          await http.put(
            Uri.parse('${authService.baseUrl}/api/calls/${callId}'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${authService.currentUser!.token}',
            },
            body: json.encode({'status': 'connected'}),
          );
        } catch (e) {
          print('Warning: Failed to update call status on server: $e');
          // Continue anyway - this is non-critical
        }
      } else {
        print('Warning: authService.currentUser is null, skipping API call');
      }

      // Request token from server - with null check for authService.currentUser
      String? token;
      if (authService.currentUser != null) {
        try {
          final tokenResponse = await http.post(
            Uri.parse('${authService.baseUrl}/api/calls/agora-token'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${authService.currentUser!.token}',
            },
            body: json.encode({
              'channelName': callId,
              'uid': 0,
            }),
          );

          if (tokenResponse.statusCode == 200) {
            final tokenData = json.decode(tokenResponse.body);
            token = tokenData['token'];
          }
        } catch (e) {
          print('Warning: Failed to get Agora token: $e');
          // Continue without token - might work for testing
        }
      }

      // Null check the engine again before calling methods on it
      if (_engine != null) {
        // Enable audio - with try/catch
        try {
          await _engine!.enableAudio();
        } catch (e) {
          print('Warning: Failed to enable audio: $e');
          // Continue - other features might still work
        }

        // Configure video based on call type - with try/catch
        try {
          if (callType == CallType.voice) {
            await _engine!.disableVideo();
          } else {
            await _engine!.enableVideo();
          }
        } catch (e) {
          print('Warning: Failed to configure video: $e');
          // Continue - audio might still work
        }
      } else {
        print('Error: _engine is null after initialization');
        throw Exception('Agora engine is null after initialization');
      }

      // Join channel - retry a few times if it fails
      bool joined = false;
      Exception? lastException;

      // Verify _engine isn't null before trying to join
      if (_engine != null) {
        for (int attempt = 0; attempt < 3; attempt++) {
          try {
            print('Joining Agora channel: attempt ${attempt + 1}');
            await _engine!.joinChannel(
              token: token ?? '',
              channelId: callId,
              uid: 0,
              options: const ChannelMediaOptions(
                channelProfile: ChannelProfileType.channelProfileCommunication,
                clientRoleType: ClientRoleType.clientRoleBroadcaster,
              ),
            );

            print('Successfully joined the channel');
            joined = true;
            break;
          } catch (e) {
            print('Error joining channel (attempt ${attempt + 1}): $e');
            lastException = e is Exception ? e : Exception(e.toString());

            // Wait a bit before retrying
            if (attempt < 2) {
              await Future.delayed(Duration(milliseconds: 500));
            }
          }
        }
      } else {
        throw Exception('Cannot join channel: Agora engine is null');
      }

      if (!joined) {
        print('Failed to join Agora channel after 3 attempts');
        if (lastException != null) {
          throw lastException;
        } else {
          throw Exception('Failed to join Agora channel');
        }
      }

      // Notify caller that call was answered - verify socket isn't null
      if (socketService.socket != null) {
        socketService.socket?.emit('call_answered', {
          'callerId': callerId,
          'callId': callId,
        });

        print('Successfully answered call and joined channel');
      } else {
        print('Warning: socket is null, cannot send call_answered event');
      }
    } catch (e) {
      print('Error answering call: $e');
      // Reset state
      isCallActive = false;
      isCallConnected = false;
      currentCallId = null;
      remoteUserId = null;
      remoteUsername = null;

      // Rethrow for the UI layer to handle
      throw e;
    }
  }

  // Reject an incoming call
  Future<void> rejectCall(
      BuildContext context, Map<String, dynamic> callData) async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final socketService = Provider.of<SocketService>(context, listen: false);

      final callerId = callData['callerId'];
      final callId = callData['callId'];

      if (callerId == null || callId == null) {
        print('Invalid call data for rejection: $callData');
        return;
      }

      print('Rejecting call: callerId=$callerId, callId=$callId');

      // Update call status on server
      await http.put(
        Uri.parse('${authService.baseUrl}/api/calls/${callId}'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${authService.currentUser!.token}',
        },
        body: json.encode({'status': 'rejected'}),
      );

      // Notify caller that call was rejected
      socketService.socket?.emit('call_rejected',
          {'callerId': callerId, 'callId': callId, 'reason': 'rejected'});

      print('Call rejection sent to caller: $callerId');
    } catch (e) {
      print('Error rejecting call: $e');
    }
  }

  // End the current call
  Future<void> endCall() async {
    if (!isCallActive) {
      print('Call not active, skipping endCall');
      return;
    }

    print('Ending call: callId=$currentCallId, remoteUser=$remoteUserId');

    try {
      // Leave the channel
      if (_engine != null) {
        await _engine?.leaveChannel();
      }

      // Update state
      isCallActive = false;
      isCallConnected = false;

      // If there's an active socket connection, notify the other party
      SocketService().socket?.emit(
          'call_ended', {'receiverId': remoteUserId, 'callId': currentCallId});

      // Update call status on server if we have a token
      final authService = AuthService();
      if (authService.currentUser != null && currentCallId != null) {
        try {
          await http.put(
            Uri.parse('${authService.baseUrl}/api/calls/${currentCallId}'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${authService.currentUser!.token}',
            },
            body: json.encode({'status': 'ended'}),
          );
        } catch (e) {
          print('Warning: Failed to update call status on server: $e');
        }
      }

      // Emit the call ended event
      _onCallEnded.add(true);

      // Finally reset call data
      final oldCallId = currentCallId;
      final oldRemoteUserId = remoteUserId;

      currentCallId = null;
      remoteUserId = null;
      remoteUsername = null;

      print(
          'Call ended successfully. Old callId=$oldCallId, userId=$oldRemoteUserId');
    } catch (e) {
      print('Error ending call: $e');

      // Still reset state even if there was an error
      isCallActive = false;
      isCallConnected = false;
      currentCallId = null;
      remoteUserId = null;
      remoteUsername = null;
    }
  }

  // Toggle local audio mute
  Future<bool> toggleMute() async {
    if (!isCallActive || _engine == null) return false;

    try {
      isLocalAudioMuted = !isLocalAudioMuted;
      await _engine!.muteLocalAudioStream(isLocalAudioMuted);
      return isLocalAudioMuted;
    } catch (e) {
      print('Error toggling mute: $e');
      return isLocalAudioMuted;
    }
  }

  // Dispose resources
  void dispose() {
    _engine?.release();
    _engine = null;
    _onIncomingCall.close();
    _onCallStatusChange.close();
    _onRemoteUserJoined.close();
    _onCallEnded.close();
  }
}

enum CallType {
  voice,
  video,
}
