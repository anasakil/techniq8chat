// services/socket_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:techniq8chat/models/user_model.dart';
import '../models/message.dart';
import '../models/conversation.dart'; // Add this import
import 'hive_storage.dart';

class SocketService {
  // Socket connection
  IO.Socket? _socket;
  bool isConnected = false;
  final String serverUrl = 'http://192.168.100.76:4400';

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

  // Streams
  Stream<bool> get onConnected => _onConnected.stream;
  Stream<Message> get onNewMessage => _onNewMessage.stream;
  Stream<Map<String, dynamic>> get onMessageStatus => _onMessageStatus.stream;
  Stream<Map<String, String>> get onUserStatus => _onUserStatus.stream;
  Stream<String> get onTyping => _onTyping.stream;

  // Message queue for when socket is disconnected
  final List<Map<String, dynamic>> _messageQueue = [];

  // Reconnection timer
  Timer? _reconnectTimer;

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
      'reconnectionAttempts': 5
    });

    _setupSocketListeners();

    // Start a periodic check for connection
    _startConnectionCheck();
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
    });

    _socket?.onConnectError((error) {
      print('Connection error: $error');
      isConnected = false;
      _onConnected.add(false);
    });

    // Listen for new messages
    _socket?.on('new_message', (data) async {
      print('New message received: $data');
      if (currentUser == null) return;

      try {
        // Create message object
        final message = Message.fromSocketData(data, currentUser!.id);

        // Save to Hive storage
        print('Saving message to Hive storage: ${message.id}');
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

    // Listen for message delivery status
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

    _socket?.on('message_pending', (data) async {
      print('Message pending: $data');
      final messageId = data['messageId'];

      try {
        // Update message status in Hive storage
        await hiveStorage.updateMessageStatus(messageId, 'pending');

        // Broadcast status update
        _onMessageStatus.add({
          'messageId': messageId,
          'status': 'pending',
        });
      } catch (e) {
        print('Error processing message_pending: $e');
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
        final conversationIndex = conversations.indexWhere((c) => c.id == userId);
        
        if (conversationIndex >= 0) {
          final updatedConversation = conversations[conversationIndex].copyWith(status: status);
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
  }

  // NEW METHOD: Update conversation when a message is processed
  Future<void> _updateConversation(Message message) async {
    if (currentUser == null) return;
    
    try {
      // Determine the other user ID (conversation partner)
      final conversationId = message.isSent ? message.receiverId : message.senderId;
      
      print('Updating conversation for ID: $conversationId with message: "${message.content}"');
      
      // Get existing conversation if any
      final conversations = await hiveStorage.getConversations();
      final existingConversationIndex = conversations.indexWhere((c) => c.id == conversationId);
      
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
        print('Updated existing conversation with ID: $conversationId, lastMessage: "${message.content}"');
      } else {
        // Create new conversation
        final newConversation = Conversation(
          id: conversationId,
          name: message.isSent ? conversationId : message.senderId, // Placeholder
          lastMessage: message.content,
          lastMessageTime: message.createdAt,
          status: 'offline',
          unreadCount: message.isSent ? 0 : 1,
        );
        
        await hiveStorage.upsertConversation(newConversation);
        print('Created new conversation with ID: $conversationId, lastMessage: "${message.content}"');
      }
    } catch (e) {
      print('Error updating conversation for message: $e');
    }
  }

  // Send a message
  Future<void> sendMessage(String receiverId, String content,
      {String? tempId}) async {
    print('Sending message to $receiverId: $content (tempId: $tempId)');

    // Store message in Hive storage first (optimistic update)
    if (tempId != null && currentUser != null) {
      final tempMessage = Message(
        id: tempId,
        senderId: currentUser!.id,
        receiverId: receiverId,
        content: content,
        contentType: 'text',
        createdAt: DateTime.now(),
        status: 'sending',
        isSent: true,
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
      });

      // Try to reconnect the socket
      _socket?.connect();
      return;
    }

    // Send directly through socket
    final messageData = {
      'receiverId': receiverId,
      'message': content,
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
    disconnect();
  }
}