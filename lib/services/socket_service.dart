import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:techniq8chat/services/api_constants.dart';
import 'package:techniq8chat/models/message.dart';
import 'package:techniq8chat/models/user_model.dart';

class SocketService {
  // Singleton instance
  static final SocketService _instance = SocketService._internal();
  static SocketService get instance => _instance;
  
  // Socket instance
  IO.Socket? _socket;
  
  // Stream controllers for various events
  final _messageReceivedController = StreamController<Message>.broadcast();
  final _messageStatusController = StreamController<Map<String, dynamic>>.broadcast();
  final _typingController = StreamController<String>.broadcast();
  final _userStatusController = StreamController<Map<String, String>>.broadcast();
  final _connectionStatusController = StreamController<bool>.broadcast();
  
  // Connection status
  bool _isConnected = false;
  bool get isConnected => _isConnected;
  Stream<bool> get connectionStatus => _connectionStatusController.stream;
  
  // Current user ID
  String? _currentUserId = '';
  
  // Message queue for when socket is disconnected
  List<Map<String, dynamic>> _messageQueue = [];
  
  // Connection retry
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int MAX_RECONNECT_ATTEMPTS = 5;
  
  // Private constructor
  SocketService._internal();
  
  // Initialize socket connection
  Future<void> init(String userId) async {
    if (_socket != null) {
      _socket!.disconnect();
      _socket = null;
    }
    
    _currentUserId = userId;
    _reconnectAttempts = 0;
    print('Initializing socket for user: $_currentUserId');
    
    try {
      await _connectSocket();
    } catch (e) {
      print('Error during initial socket connection: $e');
      _scheduleReconnect();
    }
  }
  
  Future<void> _connectSocket() async {
    // Get auth token for socket connection
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    
    if (token == null) {
      print('No auth token available for socket connection');
      throw Exception('No auth token available for socket connection');
    }
    
    // Connect to socket with detailed options and debugging
    _socket = IO.io(ApiConstants.socketUrl, {
      'transports': ['websocket'],
      'autoConnect': true,
      'query': {'token': token},
      'extraHeaders': {'Authorization': 'Bearer $token'},
      'forceNew': true,
      'reconnection': true,
      'reconnectionAttempts': 10,
      'reconnectionDelay': 1000,
      'reconnectionDelayMax': 5000,
      'timeout': 20000,
    });
    
    // Set up socket event listeners
    _setupSocketListeners();
  }
  
  void _setupSocketListeners() {
    if (_socket == null) return;
    
    // Clear any previous listeners to avoid duplicates
    _socket!.clearListeners();
    
    // Connection events
    _socket!.onConnect((_) {
      print('Socket connected: ${_socket!.id}');
      _isConnected = true;
      _reconnectAttempts = 0;
      _connectionStatusController.add(true);
      
      // Register user as connected
      if (_currentUserId != null && _currentUserId!.isNotEmpty) {
        print('Emitting user_connected event with ID: $_currentUserId');
        _socket!.emit('user_connected', _currentUserId);
      }
      
      // Process any queued messages
      _processMessageQueue();
    });
    
    _socket!.onDisconnect((_) {
      print('Socket disconnected');
      _isConnected = false;
      _connectionStatusController.add(false);
      _scheduleReconnect();
    });
    
    _socket!.onConnectError((error) {
      print('Socket connect error: $error');
      _isConnected = false;
      _connectionStatusController.add(false);
      _scheduleReconnect();
    });
    
    _socket!.onError((error) {
      print('Socket error: $error');
    });
    
    // Set up message listeners
    _setupMessageListeners();
  }
  
  void _scheduleReconnect() {
    // Cancel any existing reconnect timer
    _reconnectTimer?.cancel();
    
    // Only try to reconnect if we haven't exceeded the maximum attempts
    if (_reconnectAttempts < MAX_RECONNECT_ATTEMPTS) {
      _reconnectAttempts++;
      
      // Exponential backoff: delay increases with each attempt
      final delay = Duration(seconds: 2 * _reconnectAttempts);
      
      print('Scheduling socket reconnect attempt $_reconnectAttempts in ${delay.inSeconds} seconds');
      
      _reconnectTimer = Timer(delay, () async {
        try {
          await _connectSocket();
        } catch (e) {
          print('Reconnect attempt failed: $e');
        }
      });
    } else {
      print('Maximum reconnect attempts reached. Manual reconnection required.');
    }
  }
  
  void _setupMessageListeners() {
    if (_socket == null) return;
    
    // New message received
    _socket!.on('new_message', (data) {
      print('New message received: $data');
      
      try {
        // Handle different message formats
        Map<String, dynamic> messageData;
        if (data is Map) {
          messageData = Map<String, dynamic>.from(data);
        } else if (data is String) {
          messageData = jsonDecode(data);
        } else {
          print('Unrecognized message format: ${data.runtimeType}');
          return;
        }
        
        final String senderId = messageData['sender'] is String 
            ? messageData['sender'] 
            : messageData['sender']?['_id'] ?? '';
            
        final String content = messageData['content'] ?? '';
        final String messageId = messageData['_id'] ?? DateTime.now().millisecondsSinceEpoch.toString();
        final String contentType = messageData['contentType'] ?? 'text';
        final String status = messageData['status'] ?? 'delivered';
        final DateTime createdAt = messageData['createdAt'] != null 
            ? DateTime.parse(messageData['createdAt']) 
            : DateTime.now();
        
        // Create a sender User object
        final User sender = User(
          id: senderId,
          username: 'User', // This will be updated by the app when displayed
          email: '',
          profilePicture: '',
          status: 'online',
        );
        
        // Create a message object
        final message = Message(
          id: messageId,
          conversationId: messageData['conversationId'] ?? '',
          sender: sender,
          content: content,
          contentType: contentType,
          status: status,
          readBy: [],
          reactions: [],
          encrypted: false, // Already decrypted when received
          createdAt: createdAt,
        );
        
        // Add to stream
        _messageReceivedController.add(message);
        
        // Mark as delivered
        markMessageAsDelivered(messageId, senderId);
      } catch (e) {
        print('Error processing received message: $e');
      }
    });
    
    // Message status updates
    _socket!.on('message_status_update', (data) {
      print('Message status update: $data');
      if (data is Map) {
        _messageStatusController.add({
          'messageId': data['messageId'],
          'status': data['status']
        });
      }
    });
    
    // Message delivered confirmation
    _socket!.on('message_delivered', (data) {
      print('Message delivered: $data');
      if (data is Map) {
        _messageStatusController.add({
          'messageId': data['messageId'],
          'status': 'delivered'
        });
      }
    });
    
    // User typing indicator
    _socket!.on('user_typing', (data) {
      print('User typing: $data');
      
      String senderId = '';
      if (data is Map) {
        senderId = data['senderId'] ?? '';
      } else if (data is String) {
        try {
          final Map<String, dynamic> typingData = jsonDecode(data);
          senderId = typingData['senderId'] ?? '';
        } catch (e) {
          print('Error parsing typing data: $e');
        }
      }
      
      if (senderId.isNotEmpty) {
        _typingController.add(senderId);
      }
    });
    
    // User status changes
    _socket!.on('user_status', (data) {
      print('User status changed: $data');
      
      Map<String, String> statusData = {};
      if (data is Map) {
        statusData = {
          'userId': data['userId']?.toString() ?? '',
          'status': data['status']?.toString() ?? 'offline'
        };
      } else if (data is String) {
        try {
          final Map<String, dynamic> parsedData = jsonDecode(data);
          statusData = {
            'userId': parsedData['userId']?.toString() ?? '',
            'status': parsedData['status']?.toString() ?? 'offline'
          };
        } catch (e) {
          print('Error parsing status data: $e');
        }
      }
      
      if (statusData.isNotEmpty && statusData['userId'] != null) {
        _userStatusController.add(statusData);
      }
    });
  }
  
  // Process queued messages when connection is restored
  void _processMessageQueue() {
    print('Processing message queue (${_messageQueue.length} messages)');
    
    if (!_isConnected || _socket == null || _messageQueue.isEmpty) {
      return;
    }
    
    // Create a copy of the queue and clear the original
    final messagesToSend = List<Map<String, dynamic>>.from(_messageQueue);
    _messageQueue.clear();
    
    // Send each queued message
    for (final messageData in messagesToSend) {
      print('Sending queued message: ${messageData['message']} to ${messageData['receiverId']}');
      _socket!.emit('send_message', messageData);
    }
  }
  
  // Send a message via socket
  void sendMessage(String receiverId, String message, String messageId) {
    final messageData = {
      'receiverId': receiverId,
      'message': message,
      'messageId': messageId,
      'senderId': _currentUserId,
    };
    
    if (!_isConnected || _socket == null) {
      print('Socket not connected, queuing message for later');
      _messageQueue.add(messageData);
      return;
    }
    
    print('Emitting send_message event: $messageData');
    _socket!.emit('send_message', messageData);
  }
  
  // Mark a message as delivered
  void markMessageAsDelivered(String messageId, String senderId) {
    if (!_isConnected || _socket == null) return;
    
    final deliveryData = {
      'messageId': messageId,
      'senderId': senderId,
      'status': 'delivered'
    };
    
    print('Emitting message_delivered event: $deliveryData');
    _socket!.emit('message_delivered', deliveryData);
  }
  
  // Mark a message as read
  void markMessageAsRead(String messageId, String senderId) {
    if (!_isConnected || _socket == null) {
      // Queue this operation for when we're connected
      _messageQueue.add({
        'type': 'read',
        'messageId': messageId,
        'senderId': senderId
      });
      return;
    }
    
    final readData = {
      'messageId': messageId,
      'senderId': senderId
    };
    
    print('Emitting message_read event: $readData');
    _socket!.emit('message_read', readData);
  }
  
  // Send typing indicator
  void sendTypingIndicator(String receiverId) {
    if (!_isConnected || _socket == null) return;
    
    final typingData = {
      'receiverId': receiverId,
      'senderId': _currentUserId
    };
    
    print('Emitting typing event: $typingData');
    _socket!.emit('typing', typingData);
  }
  
  // Update user status
  void updateUserStatus(String status) {
    if (!_isConnected || _socket == null) {
      // Queue this operation for when we're connected
      _messageQueue.add({
        'type': 'status',
        'status': status
      });
      return;
    }
    
    final statusData = {
      'status': status
    };
    
    print('Emitting update_status event: $statusData');
    _socket!.emit('update_status', statusData);
  }
  
  // Force reconnection attempt
  Future<void> reconnect() async {
    if (_socket != null) {
      _socket!.disconnect();
      _socket = null;
    }
    
    _reconnectAttempts = 0;
    try {
      await _connectSocket();
    } catch (e) {
      print('Forced reconnect failed: $e');
      _scheduleReconnect();
    }
  }
  
  // Get stream of new messages from a specific user
  Stream<Message> onMessageReceived(String senderId) {
    print('Creating message stream for sender: $senderId');
    return _messageReceivedController.stream.where(
      (message) => message.sender.id == senderId
    );
  }
  
  // Get stream of message status updates
  Stream<Map<String, dynamic>> onMessageStatusUpdated() {
    return _messageStatusController.stream;
  }
  
  // Get stream of typing indicators from a specific user
  Stream<String> onUserTyping(String userId) {
    return _typingController.stream.where(
      (senderId) => senderId == userId
    );
  }
  
  // Get stream of user status updates
  Stream<Map<String, String>> onUserStatusChanged() {
    return _userStatusController.stream;
  }
  
  // Request conversation history
  void requestConversationHistory(String otherUserId) {
    if (!_isConnected || _socket == null) {
      // Queue this operation for when we're connected
      _messageQueue.add({
        'type': 'history',
        'otherUserId': otherUserId
      });
      return;
    }
    
    final requestData = {
      'userId': _currentUserId,
      'otherUserId': otherUserId
    };
    
    print('Requesting conversation history: $requestData');
    _socket!.emit('get_conversation', requestData);
  }
  
  // Check if socket is connected
  bool isSocketConnected() {
    return _isConnected && _socket != null;
  }
  
  // Close socket connection
  void disconnect() {
    _reconnectTimer?.cancel();
    _socket?.disconnect();
    _socket = null;
    _isConnected = false;
    _connectionStatusController.add(false);
  }
  
  // Dispose all resources
  void dispose() {
    disconnect();
    _messageReceivedController.close();
    _messageStatusController.close();
    _typingController.close();
    _userStatusController.close();
    _connectionStatusController.close();
  }
}