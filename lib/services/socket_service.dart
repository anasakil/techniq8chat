// services/socket_service.dart
import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:techniq8chat/models/user_model.dart';
import '../models/message.dart';
import 'local_storage.dart';

class SocketService {
  // Socket connection
  IO.Socket? _socket;
  bool isConnected = false;
  final String serverUrl = 'http://192.168.100.76:4400';
  
  // Service dependencies
  final LocalStorage localStorage = LocalStorage();
  
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

  // Initialize socket connection
  void initSocket(User user) {
    currentUser = user;
    
    _socket = IO.io(serverUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
      'query': {'token': user.token},
    });

    _setupSocketListeners();
  }

  // Set up socket event listeners
  void _setupSocketListeners() {
    _socket?.onConnect((_) {
      print('Socket connected');
      isConnected = true;
      _onConnected.add(true);
      
      // Register user as connected
      if (currentUser != null) {
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
      
      // Create message object
      final message = Message.fromSocketData(data, currentUser!.id);
      
      // Save to local storage
      await localStorage.saveMessage(message);
      
      // Broadcast the new message
      _onNewMessage.add(message);
      
      // Mark as delivered
      markMessageAsDelivered(message.id, message.senderId);
    });

    // Listen for message delivery status
    _socket?.on('message_delivered', (data) {
      print('Message delivered: $data');
      final messageId = data['messageId'];
      
      // Broadcast status update
      _onMessageStatus.add({
        'messageId': messageId,
        'status': 'delivered',
      });
    });

    _socket?.on('message_pending', (data) {
      print('Message pending: $data');
      final messageId = data['messageId'];
      
      // Broadcast status update
      _onMessageStatus.add({
        'messageId': messageId,
        'status': 'pending',
      });
    });

    _socket?.on('message_status_update', (data) {
      print('Message status update: $data');
      final messageId = data['messageId'];
      final status = data['status'];
      
      // Broadcast status update
      _onMessageStatus.add({
        'messageId': messageId,
        'status': status,
      });
    });

    // Listen for user status changes
    _socket?.on('user_status', (data) {
      print('User status update: $data');
      final userId = data['userId'];
      final status = data['status'];
      
      // Broadcast user status update
      _onUserStatus.add({
        'userId': userId,
        'status': status,
      });
    });

    // Listen for typing indicator
    _socket?.on('user_typing', (data) {
      print('User typing: $data');
      _onTyping.add(data['senderId']);
    });

    // Listen for conversation history
    _socket?.on('conversation_history', (data) async {
      print('Received conversation history: $data');
      if (currentUser == null) return;
      
      final messages = data['messages'] as List<dynamic>? ?? [];
      
      // Save messages to local storage
      for (final msg in messages) {
        final message = Message.fromSocketData(msg, currentUser!.id);
        await localStorage.saveMessage(message);
      }
    });
  }

  // Send a message
  void sendMessage(String receiverId, String content, {String? tempId}) {
    if (!isConnected) {
      // Queue message for later
      _messageQueue.add({
        'receiverId': receiverId,
        'message': content,
        'messageId': tempId,
      });
      return;
    }
    
    _socket?.emit('send_message', {
      'receiverId': receiverId,
      'message': content,
      if (tempId != null) 'messageId': tempId,
    });
  }

  // Process queued messages when socket reconnects
  void _processMessageQueue() {
    if (!isConnected || _messageQueue.isEmpty) return;
    
    print('Processing ${_messageQueue.length} queued messages');
    
    List<Map<String, dynamic>> processedQueue = List.from(_messageQueue);
    _messageQueue.clear();
    
    for (final messageData in processedQueue) {
      _socket?.emit('send_message', messageData);
    }
  }

  // Mark message as delivered
  void markMessageAsDelivered(String messageId, String senderId) {
    if (!isConnected) return;
    
    _socket?.emit('message_status_update', {
      'messageId': messageId,
      'status': 'delivered',
      'senderId': senderId,
    });
  }

  // Mark message as read
  void markMessageAsRead(String messageId, String senderId) {
    if (!isConnected) return;
    
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
    if (!isConnected) return;
    
    _socket?.emit('get_conversation', {
      'userId': userId,
      'otherUserId': otherUserId,
    });
  }

  // Disconnect socket
  void disconnect() {
    _socket?.disconnect();
    _socket = null;
    isConnected = false;
  }

  // Clean up resources
  void dispose() {
    _onConnected.close();
    _onNewMessage.close();
    _onMessageStatus.close();
    _onUserStatus.close();
    _onTyping.close();
    disconnect();
  }
}