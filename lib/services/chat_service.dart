// // services/chat_service.dart
// import 'dart:async';
// import 'package:socket_io_client/socket_io_client.dart' as IO;
// import 'package:techniq8chat/models/user_model.dart';
// import '../models/message.dart';
// import '../models/conversation.dart';
// import '../services/local_storage.dart';
// import '../services/user_repository.dart';

// class ChatService {
//   // Socket connection
//   IO.Socket? _socket;
//   bool isConnected = false;
//   final String serverUrl;
  
//   // Services
//   final LocalStorage localStorage = LocalStorage();
//   late UserRepository userRepository;
  
//   // Current user
//   User? currentUser;
  
//   // StreamControllers for events
//   final _onConnected = StreamController<bool>.broadcast();
//   final _onNewMessage = StreamController<Message>.broadcast();
//   final _onConversationsUpdated = StreamController<List<Conversation>>.broadcast();
//   final _onTyping = StreamController<String>.broadcast();
//   final _onUserStatus = StreamController<Map<String, String>>.broadcast();
//   final _onMessageStatus = StreamController<Map<String, dynamic>>.broadcast();
  
//   // Streams
//   Stream<bool> get onConnected => _onConnected.stream;
//   Stream<Message> get onNewMessage => _onNewMessage.stream;
//   Stream<List<Conversation>> get onConversationsUpdated => _onConversationsUpdated.stream;
//   Stream<String> get onTyping => _onTyping.stream;
//   Stream<Map<String, String>> get onUserStatus => _onUserStatus.stream;
//   Stream<Map<String, dynamic>> get onMessageStatus => _onMessageStatus.stream;
  
//   // Message queue for when socket is disconnected
//   final List<Map<String, dynamic>> _messageQueue = [];
  
//   ChatService({required this.serverUrl});

//   // Initialize the service
//   Future<void> initialize(User user) async {
//     // Store current user
//     currentUser = user;
//     await localStorage.saveCurrentUser(user);
    
//     // Initialize user repository
//     userRepository = UserRepository(
//       baseUrl: serverUrl,
//       token: user.token,
//     );
    
//     // Initialize socket connection
//     _initSocket(user.token);
    
//     // Load and broadcast initial conversations
//     await _loadAndBroadcastConversations();
//   }

//   // Load conversations from local storage and broadcast them
//   Future<void> _loadAndBroadcastConversations() async {
//     final conversations = await localStorage.getConversations();
//     _onConversationsUpdated.add(conversations);
//   }

//   // Initialize socket connection
//   void _initSocket(String token) {
//     _socket = IO.io(serverUrl, <String, dynamic>{
//       'transports': ['websocket'],
//       'autoConnect': true,
//       'query': {'token': token},
//     });

//     _setupSocketListeners();
//   }

//   // Setup socket event listeners
//   void _setupSocketListeners() {
//     _socket?.onConnect((_) {
//       print('Socket connected');
//       isConnected = true;
//       _onConnected.add(true);
      
//       // Register user as connected
//       if (currentUser != null) {
//         _socket?.emit('user_connected', currentUser!.id);
//       }
      
//       // Process any queued messages
//       _processMessageQueue();
//     });

//     _socket?.onDisconnect((_) {
//       print('Socket disconnected');
//       isConnected = false;
//       _onConnected.add(false);
//     });

//     _socket?.onConnectError((error) {
//       print('Connection error: $error');
//       isConnected = false;
//       _onConnected.add(false);
//     });

//     // Listen for new messages
//     _socket?.on('new_message', (data) async {
//       print('New message received: $data');
//       if (currentUser == null) return;
      
//       // Create message object
//       final message = Message.fromSocketData(data, currentUser!.id);
      
//       // Save to local storage
//       await localStorage.saveMessage(message);
      
//       // Update conversation (will be created if it doesn't exist)
//       await localStorage.updateConversationFromMessage(message);
      
//       // Broadcast updated conversations
//       await _loadAndBroadcastConversations();
      
//       // Broadcast the new message
//       _onNewMessage.add(message);
      
//       // Mark as delivered
//       markMessageAsDelivered(message.id, message.senderId);
//     });

//     // Listen for message delivery status
//     _socket?.on('message_delivered', (data) async {
//       print('Message delivered: $data');
//       final messageId = data['messageId'];
      
//       // Update message status in local storage
//       await localStorage.updateMessageStatus(messageId, 'delivered');
      
//       // Broadcast status update
//       _onMessageStatus.add({
//         'messageId': messageId,
//         'status': 'delivered',
//       });
//     });

//     _socket?.on('message_pending', (data) async {
//       print('Message pending: $data');
//       final messageId = data['messageId'];
      
//       // Update message status in local storage
//       await localStorage.updateMessageStatus(messageId, 'pending');
      
//       // Broadcast status update
//       _onMessageStatus.add({
//         'messageId': messageId,
//         'status': 'pending',
//       });
//     });

//     _socket?.on('message_status_update', (data) async {
//       print('Message status update: $data');
//       final messageId = data['messageId'];
//       final status = data['status'];
      
//       // Update message status in local storage
//       await localStorage.updateMessageStatus(messageId, status);
      
//       // Broadcast status update
//       _onMessageStatus.add({
//         'messageId': messageId,
//         'status': status,
//       });
//     });

//     // Listen for user status changes
//     _socket?.on('user_status', (data) {
//       print('User status update: $data');
//       final userId = data['userId'];
//       final status = data['status'];
      
//       // Broadcast user status update
//       _onUserStatus.add({
//         'userId': userId,
//         'status': status,
//       });
      
//       // Update conversation status if exists
//       _updateConversationStatus(userId, status);
//     });

//     // Listen for typing indicator
//     _socket?.on('user_typing', (data) {
//       print('User typing: $data');
//       _onTyping.add(data['senderId']);
//     });

//     // Listen for conversation history response
//     _socket?.on('conversation_history', (data) async {
//       print('Received conversation history: $data');
//       if (currentUser == null) return;
      
//       final userId = data['userId'];
//       final messages = data['messages'] as List<dynamic>? ?? [];
      
//       // Save messages to local storage
//       final messagesList = messages.map((msg) => 
//         Message.fromSocketData(msg, currentUser!.id)
//       ).toList();
      
//       for (final message in messagesList) {
//         await localStorage.saveMessage(message);
//       }
      
//       // Update conversations
//       await _loadAndBroadcastConversations();
//     });
//   }

//   // Send a message
//   Future<Message> sendMessage(String receiverId, String content) async {
//     if (currentUser == null) {
//       throw Exception('No current user');
//     }
    
//     // Create temporary message
//     final tempMessage = Message.createTemp(
//       senderId: currentUser!.id,
//       receiverId: receiverId,
//       content: content,
//     );
    
//     // Save to local storage
//     await localStorage.saveMessage(tempMessage);
    
//     // Broadcast updated conversations
//     await _loadAndBroadcastConversations();
    
//     // Broadcast the new message
//     _onNewMessage.add(tempMessage);
    
//     // Send through socket
//     if (isConnected) {
//       _socket?.emit('send_message', {
//         'receiverId': receiverId,
//         'message': content,
//         'messageId': tempMessage.id,
//       });
//     } else {
//       // Queue for later
//       _messageQueue.add({
//         'receiverId': receiverId,
//         'message': content,
//         'messageId': tempMessage.id,
//       });
      
//       // Update status to pending
//       await localStorage.updateMessageStatus(tempMessage.id, 'pending');
      
//       // Broadcast status update
//       _onMessageStatus.add({
//         'messageId': tempMessage.id,
//         'status': 'pending',
//       });
//     }
    
//     return tempMessage;
//   }

//   // Process queued messages when socket reconnects
//   void _processMessageQueue() {
//     if (!isConnected || _messageQueue.isEmpty) return;
    
//     print('Processing ${_messageQueue.length} queued messages');
    
//     List<Map<String, dynamic>> processedQueue = List.from(_messageQueue);
//     _messageQueue.clear();
    
//     for (final messageData in processedQueue) {
//       _socket?.emit('send_message', messageData);
      
//       // Update status to sent
//       localStorage.updateMessageStatus(messageData['messageId'], 'sent');
      
//       // Broadcast status update
//       _onMessageStatus.add({
//         'messageId': messageData['messageId'],
//         'status': 'sent',
//       });
//     }
//   }

//   // Mark message as delivered
//   void markMessageAsDelivered(String messageId, String senderId) {
//     if (!isConnected) return;
    
//     _socket?.emit('message_status_update', {
//       'messageId': messageId,
//       'status': 'delivered',
//       'senderId': senderId,
//     });
//   }

//   // Mark message as read
//   Future<void> markMessageAsRead(String messageId, String senderId) async {
//     if (!isConnected) return;
    
//     _socket?.emit('message_read', {
//       'messageId': messageId,
//       'senderId': senderId,
//     });
    
//     // Update message status locally
//     await localStorage.updateMessageStatus(messageId, 'read');
//   }

//   // Mark all messages in a conversation as read
//   Future<void> markConversationAsRead(String conversationId) async {
//     // Get all messages for this conversation
//     final messages = await localStorage.getMessages(conversationId);
    
//     // Mark unread messages as read
//     for (final message in messages) {
//       if (!message.isSent && message.status != 'read') {
//         await markMessageAsRead(message.id, message.senderId);
//       }
//     }
    
//     // Update conversation unread count
//     await localStorage.markConversationAsRead(conversationId);
    
//     // Broadcast updated conversations
//     await _loadAndBroadcastConversations();
//   }

//   // Send typing indicator
//   void sendTyping(String receiverId) {
//     if (!isConnected) return;
    
//     _socket?.emit('typing', {
//       'receiverId': receiverId,
//     });
//   }

//   // Get conversation history from socket
//   void getConversationHistory(String otherUserId) {
//     if (!isConnected || currentUser == null) return;
    
//     _socket?.emit('get_conversation', {
//       'userId': currentUser!.id,
//       'otherUserId': otherUserId,
//     });
//   }

//   // Update a conversation's status
//   Future<void> _updateConversationStatus(String userId, String status) async {
//     final conversations = await localStorage.getConversations();
//     final index = conversations.indexWhere((c) => c.id == userId);
    
//     if (index >= 0) {
//       conversations[index] = conversations[index].copyWith(status: status);
//       await localStorage.saveConversations(conversations);
//       await _loadAndBroadcastConversations();
//     }
//   }

//   // Get or create a conversation with a user
//   Future<Conversation> getOrCreateConversation(User otherUser) async {
//     final conversations = await localStorage.getConversations();
//     final index = conversations.indexWhere((c) => c.id == otherUser.id);
    
//     if (index >= 0) {
//       return conversations[index];
//     } else {
//       // Create new conversation
//       final newConversation = Conversation(
//         id: otherUser.id,
//         name: otherUser.username,
//         profilePicture: otherUser.profilePicture,
//         status: otherUser.status,
//       );
      
//       await localStorage.upsertConversation(newConversation);
//       await _loadAndBroadcastConversations();
      
//       return newConversation;
//     }
//   }

//   // Get messages for a conversation
//   Future<List<Message>> getMessages(String conversationId) async {
//     return await localStorage.getMessages(conversationId);
//   }

//   // Delete a conversation
//   Future<void> deleteConversation(String conversationId) async {
//     await localStorage.deleteConversation(conversationId);
//     await _loadAndBroadcastConversations();
//   }

//   // Delete a message
//   Future<void> deleteMessage(String conversationId, String messageId) async {
//     final success = await localStorage.deleteMessage(conversationId, messageId);
//     if (success) {
//       await _loadAndBroadcastConversations();
//     }
//   }

//   // Disconnect and clean up
//   void dispose() {
//     _socket?.disconnect();
//     _socket = null;
//     isConnected = false;
    
//     _onConnected.close();
//     _onNewMessage.close();
//     _onConversationsUpdated.close();
//     _onTyping.close();
//     _onUserStatus.close();
//     _onMessageStatus.close();
//   }
// }