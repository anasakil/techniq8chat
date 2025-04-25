import 'dart:async';
import 'dart:convert';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:techniq8chat/models/user_model.dart';
import '../models/message.dart';
import '../models/conversation.dart';
import 'hive_storage.dart';
import 'package:http/http.dart' as http;

class SocketService {
  // Socket connection
  IO.Socket? _socket;

  bool isConnected = false;
  final String serverUrl = 'http://192.168.100.83:4400';

  // Service dependencies
  final HiveStorage hiveStorage = HiveStorage();

  // Current user
  User? currentUser;

  // Stream controllers
  final _onConnected = StreamController<bool>.broadcast();
  final _onNewMessage = StreamController<Message>.broadcast();
  final _onMessageStatus = StreamController<Map<String, dynamic>>.broadcast();
  final _onUserStatus = StreamController<Map<String, String>>.broadcast();
  final _onTyping = StreamController<String>.broadcast();

  // WebRTC Stream controllers
  final _onWebRTCOffer = StreamController<Map<String, dynamic>>.broadcast();
  final _onWebRTCAnswer = StreamController<Map<String, dynamic>>.broadcast();
  final _onWebRTCIceCandidate =
      StreamController<Map<String, dynamic>>.broadcast();
  final _onWebRTCEndCall = StreamController<String>.broadcast();
  final _onWebRTCCallRejected = StreamController<String>.broadcast();

  // Streams
  Stream<bool> get onConnected => _onConnected.stream;
  Stream<Message> get onNewMessage => _onNewMessage.stream;
  Stream<Map<String, dynamic>> get onMessageStatus => _onMessageStatus.stream;
  Stream<Map<String, String>> get onUserStatus => _onUserStatus.stream;
  Stream<String> get onTyping => _onTyping.stream;

  // WebRTC Streams
  Stream<Map<String, dynamic>> get onWebRTCOffer => _onWebRTCOffer.stream;
  Stream<Map<String, dynamic>> get onWebRTCAnswer => _onWebRTCAnswer.stream;
  Stream<Map<String, dynamic>> get onWebRTCIceCandidate =>
      _onWebRTCIceCandidate.stream;
  Stream<String> get onWebRTCEndCall => _onWebRTCEndCall.stream;
  Stream<String> get onWebRTCCallRejected => _onWebRTCCallRejected.stream;

  // Message queue for when socket is disconnected
  final List<Map<String, dynamic>> _messageQueue = [];

  // Reconnection timer
  Timer? _reconnectTimer;

  // Socket getter for WebRTC service
  IO.Socket? get socket => _socket;

  // Singleton pattern
  static final SocketService _instance = SocketService._internal();

  factory SocketService() {
    return _instance;
  }

  SocketService._internal();

  // Initialize socket connection
  void initSocket(User user) {
    currentUser = user;

    print('Initializing socket with token: ${user.token.substring(0, 10)}...');

    _socket = IO.io(serverUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
      'query': {'token': user.token},
      'reconnection': true,
      'reconnectionDelay': 1000,
      'reconnectionDelayMax': 5000,
      'reconnectionAttempts': 10
    });

    _setupSocketListeners();
  }

  void _startConnectionCheck() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer.periodic(Duration(seconds: 5), (timer) {
      if (!isConnected && _socket != null) {
        print('Connection check: attempting reconnect');
        _socket!.connect();
      }
    });
  }

  // Set up socket event listeners
  void _setupSocketListeners() {
    _socket?.onConnect((_) {
      print('Socket connected');
      isConnected = true;
      _onConnected.add(true);

      // Register user as connected
      if (currentUser != null) {
        print('Emitting user_connected with ID: ${currentUser!.id}');
        _socket?.emit('user_connected', currentUser!.id);
      }

      // Process any queued messages
      _processMessageQueue();
    });

    _socket?.onDisconnect((_) {
      print('Socket disconnected');
      isConnected = false;
      _onConnected.add(false);

      // Start reconnection timer
      _startConnectionCheck();
    });

    _socket?.onConnectError((error) {
      print('Connection error: $error');
      isConnected = false;
      _onConnected.add(false);

      // Start reconnection timer
      _startConnectionCheck();
    });

    // Listen for new messages
    _socket?.on('new_message', (data) async {
      print('New message received: $data');
      if (currentUser == null) return;

      try {
        // Extract sender name from data if available
        String? senderName;
        if (data is Map) {
          // Check for sender name in various possible locations
          if (data['senderName'] != null) {
            senderName = data['senderName'].toString();
          } else if (data['sender'] is Map &&
              data['sender']['username'] != null) {
            senderName = data['sender']['username'].toString();
          }

          // If sender is the same as current user, use our username
          final senderId =
              data['sender'] is Map ? data['sender']['_id'] : data['sender'];
          if (senderId == currentUser!.id) {
            senderName = currentUser!.username;
          }
        }

        // Create message object
        final message = Message.fromSocketData(data, currentUser!.id);

        // Save to Hive storage
        print(
            'Saving message to Hive storage: ${message.id}, sender: ${message.senderName ?? "unknown"}');
        await hiveStorage.saveMessage(message);

        // Explicitly update the conversation with this message
        await _updateConversation(message);

        // Broadcast the new message
        _onNewMessage.add(message);

        // Mark as delivered
        print('Marking message as delivered: ${message.id}');
        markMessageAsDelivered(message.id, message.senderId);
      } catch (e) {
        print('Error processing new message: $e');
      }
    });

    // Listen for message status updates
    _socket?.on('message_delivered', (data) async {
      print('Message delivered: $data');
      final messageId = data['messageId'];

      try {
        // Update message status in Hive storage
        await hiveStorage.updateMessageStatus(messageId, 'delivered');

        // Broadcast status update
        _onMessageStatus.add({
          'messageId': messageId,
          'status': 'delivered',
        });
      } catch (e) {
        print('Error processing message_delivered: $e');
      }
    });

    _socket?.on('message_status_update', (data) async {
      print('Message status update: $data');
      final messageId = data['messageId'];
      final status = data['status'];

      try {
        // Update message status in Hive storage
        await hiveStorage.updateMessageStatus(messageId, status);

        // Broadcast status update
        _onMessageStatus.add({
          'messageId': messageId,
          'status': status,
        });
      } catch (e) {
        print('Error processing message_status_update: $e');
      }
    });

    // Listen for user status changes
    _socket?.on('user_status', (data) async {
      print('User status update: $data');
      final userId = data['userId'];
      final status = data['status'];

      try {
        // Update conversation status in storage
        final conversations = await hiveStorage.getConversations();
        final conversationIndex =
            conversations.indexWhere((c) => c.id == userId);

        if (conversationIndex >= 0) {
          final updatedConversation =
              conversations[conversationIndex].copyWith(status: status);
          await hiveStorage.upsertConversation(updatedConversation);
        }
      } catch (e) {
        print('Error updating conversation status: $e');
      }

      // Broadcast user status update
      _onUserStatus.add({
        'userId': userId,
        'status': status,
      });
    });

    // Listen for typing indicator
    _socket?.on('user_typing', (data) {
      print('User typing: $data');
      if (data != null && data['senderId'] != null) {
        _onTyping.add(data['senderId']);
      }
    });

    // Listen for conversation history
    _socket?.on('conversation_history', (data) async {
      print('Received conversation history: $data');
      if (currentUser == null) return;

      try {
        if (data['messages'] != null) {
          final messages = (data['messages'] as List).map((msg) {
            return Message.fromSocketData(msg, currentUser!.id);
          }).toList();

          // Debug print
          print('Conversation History Messages:');
          for (var msg in messages) {
            print(
                'Message ID: ${msg.id}, Sender: ${msg.senderId}, Receiver: ${msg.receiverId}, Content: ${msg.content}');
          }

          // Save messages to Hive storage
          for (final message in messages) {
            await hiveStorage.saveMessage(message);

            // Also update conversation for each message
            await _updateConversation(message);
          }
        }
      } catch (e) {
        print('Error processing conversation history: $e');
      }
    });

    // WebRTC related events
    _socket?.on('webrtc_offer', (data) {
      print('WebRTC offer received: $data');
      _onWebRTCOffer.add(data);
    });

    _socket?.on('webrtc_answer', (data) {
      print('WebRTC answer received: $data');
      _onWebRTCAnswer.add(data);
    });

    _socket?.on('webrtc_ice_candidate', (data) {
      print('WebRTC ICE candidate received: $data');
      _onWebRTCIceCandidate.add(data);
    });

    _socket?.on('webrtc_end_call', (data) {
      print('WebRTC end call received');
      final senderId = data['senderId'] ?? '';
      _onWebRTCEndCall.add(senderId);
    });

    _socket?.on('webrtc_call_rejected', (data) {
      print('WebRTC call rejected received');
      final receiverId = data['receiverId'] ?? '';
      _onWebRTCCallRejected.add(receiverId);
    });

    // Incoming call event
    _socket?.on('incoming_call', (data) {
      print('Incoming callERERERE received from socket: $data');
      try {
        // Extract data from the incoming call
        final callerId = data['callerId'];
        final callId = data['callId'];
        final callType = data['callType'] ?? 'audio';
        String? callerName = data['callerName'];

        if (callerName == null &&
            data['caller'] is Map &&
            data['caller']['username'] != null) {
          callerName = data['caller']['username'];
        }

        print(
            'Incoming callezeze from $callerId, call ID: $callId, type: $callType, caller name: $callerName');

       
        _onWebRTCOffer.add({
          'senderId': callerId,
          'callId': callId,
          'callType': callType,
          'callerName': callerName,
        });
      } catch (e) {
        print('Error processing incoming call event: $e');
      }
    });
  }

  Future<void> _updateConversation(Message message) async {
    if (currentUser == null) return;

    try {
      // Determine the other user ID (conversation partner)
      final conversationId =
          message.isSent ? message.receiverId : message.senderId;

      print(
          'Updating conversation for ID: $conversationId with message: "${message.content}"');

      // Get existing conversation if any
      final conversations = await hiveStorage.getConversations();
      final existingConversationIndex =
          conversations.indexWhere((c) => c.id == conversationId);

      if (existingConversationIndex >= 0) {
        // Update existing conversation
        final existingConversation = conversations[existingConversationIndex];

        // Calculate unread count
        int newUnreadCount = existingConversation.unreadCount;
        if (!message.isSent && message.senderId != currentUser!.id) {
          newUnreadCount += 1;
        }

        // Create updated conversation
        final updatedConversation = existingConversation.copyWith(
          lastMessage: message.content,
          lastMessageTime: message.createdAt,
          unreadCount: newUnreadCount,
        );

        // Save updated conversation
        await hiveStorage.upsertConversation(updatedConversation);
        print(
            'Updated existing conversation with ID: $conversationId, lastMessage: "${message.content}"');
      } else {
        // Create new conversation with name from message if available
        // If no name is available, fetch user details from API
        String conversationName;
        String? profilePicture;

        if (message.senderName != null && message.senderName!.isNotEmpty) {
          // Use sender name from message if available
          conversationName = message.senderName!;
        } else {
          // Fetch user details from the API
          try {
            final response = await http.get(
              Uri.parse('http://192.168.100.83:4400/api/users/$conversationId'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer ${currentUser!.token}',
              },
            );

            if (response.statusCode == 200) {
              final userData = json.decode(response.body);
              conversationName = userData['username'] ?? 'Unknown User';
              profilePicture = userData['profilePicture'];
              print(
                  'Fetched user details for $conversationId: $conversationName');
            } else {
              conversationName = 'User ($conversationId)';
              print(
                  'Failed to fetch user details, status: ${response.statusCode}');
            }
          } catch (e) {
            // Fallback if API request fails
            conversationName = 'User ($conversationId)';
            print('Error fetching user details: $e');
          }
        }

        final newConversation = Conversation(
          id: conversationId,
          name: conversationName,
          lastMessage: message.content,
          lastMessageTime: message.createdAt,
          status: 'offline',
          unreadCount: message.isSent ? 0 : 1,
          profilePicture: profilePicture,
        );

        await hiveStorage.upsertConversation(newConversation);
        print(
            'Created new conversation with ID: $conversationId, name: "$conversationName", lastMessage: "${message.content}"');
      }
    } catch (e) {
      print('Error updating conversation for message: $e');
    }
  }

  // WebRTC signaling methods
  void sendWebRTCOffer(String receiverId, dynamic offer, String callType) {
    if (!isConnected) {
      print('Cannot send WebRTC offer: socket disconnected');
      return;
    }

    _socket?.emit('webrtc_offer',
        {'receiverId': receiverId, 'offer': offer, 'callType': callType});
  }

  void sendWebRTCAnswer(String receiverId, dynamic answer) {
    if (!isConnected) {
      print('Cannot send WebRTC answer: socket disconnected');
      return;
    }

    print('Sending WebRTC answer to $receiverId');
    _socket
        ?.emit('webrtc_answer', {'receiverId': receiverId, 'answer': answer});
  }

  void sendWebRTCIceCandidate(String receiverId, dynamic candidate) {
    if (!isConnected) {
      print('Cannot send WebRTC ICE candidate: socket disconnected');
      return;
    }

    print('Sending WebRTC ICE candidate to $receiverId');
    _socket?.emit('webrtc_ice_candidate',
        {'receiverId': receiverId, 'candidate': candidate});
  }

  void sendWebRTCEndCall(String receiverId) {
    if (!isConnected) {
      print('Cannot send WebRTC end call: socket disconnected');
      return;
    }

    print('Sending WebRTC end call to $receiverId');
    _socket?.emit('webrtc_end_call', {'receiverId': receiverId});
  }

  void sendWebRTCRejectCall(String callerId) {
    if (!isConnected) {
      print('Cannot send WebRTC reject call: socket disconnected');
      return;
    }

    print('Sending WebRTC reject call to $callerId');
    _socket?.emit('webrtc_reject_call', {'callerId': callerId});
  }

  // Send a message
  Future<void> sendMessage(String receiverId, String content,
      {String? tempId}) async {
    print('Sending message to $receiverId: $content (tempId: $tempId)');

    // Ensure we always have the current user before proceeding
    if (currentUser == null) {
      print('Cannot send message: No current user available');
      return;
    }

    // Store message in Hive storage first (optimistic update)
    if (tempId != null) {
      final tempMessage = Message(
        id: tempId,
        senderId: currentUser!.id,
        receiverId: receiverId,
        content: content,
        contentType: 'text',
        createdAt: DateTime.now(),
        status: 'sending',
        isSent: true,
        senderName: currentUser!.username, // Include the sender's username
      );

      await hiveStorage.saveMessage(tempMessage);

      // Also update conversation for this message
      await _updateConversation(tempMessage);
    }

    if (!isConnected) {
      print('Socket not connected, queueing message for later');
      // Queue message for later
      _messageQueue.add({
        'receiverId': receiverId,
        'message': content,
        'messageId': tempId,
        'senderName': currentUser?.username, // Include sender name in the queue
      });

      // Try to reconnect the socket
      _socket?.connect();
      return;
    }

    // Send directly through socket
    final messageData = {
      'receiverId': receiverId,
      'message': content,
      'senderName':
          currentUser!.username, // Include sender name in the socket emission
    };

    // Add temp ID if available
    if (tempId != null) {
      messageData['messageId'] = tempId;
    }

    print('Emitting send_message event: $messageData');
    _socket?.emit('send_message', messageData);
  }

  // Process queued messages when socket reconnects
  void _processMessageQueue() {
    if (!isConnected || _messageQueue.isEmpty) return;

    print('Processing ${_messageQueue.length} queued messages');

    // Create a copy of the queue so we can safely modify the original
    final List<Map<String, dynamic>> processedQueue = List.from(_messageQueue);
    _messageQueue.clear();

    for (final messageData in processedQueue) {
      print('Processing queued message: $messageData');
      _socket?.emit('send_message', messageData);
    }
  }

  // Mark message as delivered
  void markMessageAsDelivered(String messageId, String senderId) {
    if (!isConnected) {
      print('Cannot mark message as delivered: socket disconnected');
      return;
    }

    print(
        'Marking message as delivered - messageId: $messageId, senderId: $senderId');
    _socket?.emit('message_status_update', {
      'messageId': messageId,
      'status': 'delivered',
      'senderId': senderId,
    });
  }

  // Mark message as read
  void markMessageAsRead(String messageId, String senderId) {
    if (!isConnected) {
      print('Cannot mark message as read: socket disconnected');
      return;
    }

    print(
        'Marking message as read - messageId: $messageId, senderId: $senderId');
    _socket?.emit('message_read', {
      'messageId': messageId,
      'senderId': senderId,
    });
  }

  // Send typing indicator
  void sendTyping(String receiverId) {
    if (!isConnected) return;

    _socket?.emit('typing', {
      'receiverId': receiverId,
    });
  }

  // Get conversation history
  void getConversationHistory(String userId, String otherUserId) {
    if (!isConnected) {
      print('Cannot get conversation history: socket disconnected');
      // Queue this request for when connection is restored
      _socket?.connect();
      return;
    }

    print('Getting conversation history between $userId and $otherUserId');
    _socket?.emit('get_conversation', {
      'userId': userId,
      'otherUserId': otherUserId,
    });
  }

  // Force a reconnection attempt
  void reconnect() {
    if (_socket != null) {
      print('Forcing socket reconnection');
      _socket!.connect();
    }
  }

  // Disconnect socket
  void disconnect() {
    _reconnectTimer?.cancel();
    _socket?.disconnect();
    _socket = null;
    isConnected = false;
  }

  // Clean up resources
  void dispose() {
    _reconnectTimer?.cancel();
    _onConnected.close();
    _onNewMessage.close();
    _onMessageStatus.close();
    _onUserStatus.close();
    _onTyping.close();

    // Close WebRTC stream controllers
    _onWebRTCOffer.close();
    _onWebRTCAnswer.close();
    _onWebRTCIceCandidate.close();
    _onWebRTCEndCall.close();
    _onWebRTCCallRejected.close();

    disconnect();
  }
}
