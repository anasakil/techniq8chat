// services/socket_service.dart
import 'dart:async';
import 'dart:convert';
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
        
        // Save to local storage
        print('Saving message to local storage: ${message.id}');
        await localStorage.saveMessage(message);
        
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
        // Update message status in local storage
        await localStorage.updateMessageStatus(messageId, 'delivered');
        
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
        // Update message status in local storage
        await localStorage.updateMessageStatus(messageId, 'pending');
        
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
        // Update message status in local storage
        await localStorage.updateMessageStatus(messageId, status);
        
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
          
          // Save messages to local storage
          for (final message in messages) {
            await localStorage.saveMessage(message);
          }
        }
      } catch (e) {
        print('Error processing conversation history: $e');
      }
    });
  }

  // Send a message
  Future<void> sendMessage(String receiverId, String content, {String? tempId}) async {
    print('Sending message to $receiverId: $content (tempId: $tempId)');
    
    // Store message in local storage first (optimistic update)
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
      
      await localStorage.saveMessage(tempMessage);
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
    
    print('Marking message as delivered - messageId: $messageId, senderId: $senderId');
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
    
    print('Marking message as read - messageId: $messageId, senderId: $senderId');
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