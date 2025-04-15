// screens/chat_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:techniq8chat/models/user_model.dart';
import '../models/message.dart';
import '../services/auth_service.dart';
import '../services/socket_service.dart';
import '../services/hive_storage.dart';
import 'dart:math' as Math;

class ChatScreen extends StatefulWidget {
  final String conversationId;
  final String conversationName;

  ChatScreen({
    required this.conversationId,
    required this.conversationName,
  });

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late HiveStorage _hiveStorage;
  
  List<Message> _messages = [];
  bool _isLoading = true;
  String? _typingUserId;
  Timer? _typingTimer;
  bool _isConnected = false;
  
  late SocketService _socketService;
  late StreamSubscription _connectionSubscription;
  late StreamSubscription _newMessageSubscription;
  late StreamSubscription _messageStatusSubscription;
  late StreamSubscription _typingSubscription;
  
  // For message animation
  final Map<String, AnimationController> _animationControllers = {};

  @override
  void initState() {
    super.initState();
    // Get HiveStorage instance from provider
    _hiveStorage = Provider.of<HiveStorage>(context, listen: false);
    _initializeServices();
    _markConversationAsRead();
  }

  Future<void> _markConversationAsRead() async {
    try {
      // Mark conversation as read in Hive storage
      await _hiveStorage.markConversationAsRead(widget.conversationId);
      print('Marked conversation ${widget.conversationId} as read on screen load');
    } catch (e) {
      print('Error marking conversation as read: $e');
    }
  }
  
  Future<void> _initializeServices() async {
    // Get the current user
    final authService = Provider.of<AuthService>(context, listen: false);
    final currentUser = authService.currentUser;
    
    if (currentUser == null) {
      // Handle case where user is not logged in
      Navigator.of(context).pop();
      return;
    }

    print("Current user ID in Chat Screen: ${currentUser.id}");

    // Set up socket service
    _socketService = SocketService();
    if (!_socketService.isConnected) {
      _socketService.initSocket(currentUser);
    }

    // Set up listeners
    _setupListeners();

    // Load messages - pass the current user directly to avoid timing issues
    await _loadMessages(currentUser);

    // Mark conversation as read
    await _hiveStorage.markConversationAsRead(widget.conversationId);

    // Request conversation history from server
    _socketService.getConversationHistory(
      currentUser.id,
      widget.conversationId,
    );
  }

  void _setupListeners() {
    // Listen for connection status
    _connectionSubscription = _socketService.onConnected.listen((connected) {
      setState(() {
        _isConnected = connected;
      });
    });

    // Listen for new messages
    _newMessageSubscription = _socketService.onNewMessage.listen((message) {
      print("New message received in chat screen: ${message.id} from ${message.senderId}");
      // Only add messages for this conversation
      if (message.senderId == widget.conversationId || 
          message.receiverId == widget.conversationId) {
        _handleNewMessage(message);
      }
    });

    // Listen for message status updates
    _messageStatusSubscription = _socketService.onMessageStatus.listen((data) {
      print("Message status update in chat screen: ${data['messageId']} - ${data['status']}");
      _updateMessageStatus(data['messageId'], data['status']);
    });

    // Listen for typing indicators
    _typingSubscription = _socketService.onTyping.listen((userId) {
      if (userId == widget.conversationId) {
        _showTypingIndicator();
      }
    });
  }

  Future<void> _loadMessages([User? directUser]) async {
    try {
      print("LOADING MESSAGES FOR CONVERSATION: ${widget.conversationId}");
      
      // Get the current user to help with debugging
      final authService = Provider.of<AuthService>(context, listen: false);
      final currentUser = directUser ?? authService.currentUser;
      
      if (currentUser == null) {
        print("ERROR: No current user available for message loading");
        setState(() {
          _isLoading = false;
        });
        return;
      }
      
      print("Current user ID for message loading: ${currentUser.id}");
      
      // Print conversation details for debug
      _hiveStorage.debugPrintAllData();
      
      // Pass the current user directly to getMessages to avoid timing issues
      final messages = await _hiveStorage.getMessages(
        widget.conversationId, 
        directUser: currentUser
      );
      
      // Debug print to verify messages
      print('Loaded ${messages.length} messages for UI');
      
      if (mounted) {
        setState(() {
          _messages = messages;
          _isLoading = false;
        });
        
        // Create animation controllers for each message
        for (final message in messages) {
          _createAnimationController(message.id);
        }
        
        // Scroll to bottom after messages are loaded
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToBottom();
        });
      }
    } catch (e) {
      print('Error loading messages: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Force refresh messages - useful for debugging
  Future<void> _forceRefreshMessages() async {
    print('Force refreshing messages for conversation: ${widget.conversationId}');
    
    try {
      // Get current user
      final authService = Provider.of<AuthService>(context, listen: false);
      final currentUser = authService.currentUser;
      
      if (currentUser == null) {
        print("ERROR: No current user available for force refresh");
        return;
      }
      
      // Print all stored data to help debug
      _hiveStorage.debugPrintAllData();
      
      // Pass current user directly
      final messages = await _hiveStorage.getMessages(
        widget.conversationId,
        directUser: currentUser
      );
      
      print('Force refresh found ${messages.length} messages');
      
      // Manual loading of messages if the standard method fails
      if (messages.isEmpty) {
        // Try to manually get conversation history again
        _socketService.getConversationHistory(
          currentUser.id,
          widget.conversationId,
        );
        
        print("Manual request for conversation history sent");
      }
      
      // Update the UI regardless of whether we found messages
      setState(() {
        _messages = messages;
        _isLoading = false;
      });
      
      // Make sure to scroll to bottom after setting state
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });
    } catch (e) {
      print('Error in force refresh: $e');
    }
  }

  void _handleNewMessage(Message message) async {
    print("Handling new message: ${message.id}, content: ${message.content}");
    
    // Get current user for consistent handling
    final authService = Provider.of<AuthService>(context, listen: false);
    final currentUser = authService.currentUser;
    
    if (currentUser == null) {
      print("ERROR: No current user available when handling new message");
      return;
    }
    
    // Check if message is for this conversation
    final isRelevantMessage = 
      (message.senderId == widget.conversationId && message.receiverId == currentUser.id) ||
      (message.receiverId == widget.conversationId && message.senderId == currentUser.id);
    
    if (!isRelevantMessage) {
      print("Message not relevant to this conversation");
      return;
    }
    
    // Mark message as delivered if it's from the other user
    if (!message.isSent) {
      _socketService.markMessageAsDelivered(message.id, message.senderId);
      
      // Also mark as read since we're in the chat
      _socketService.markMessageAsRead(message.id, message.senderId);
    }

    // Check if message is already in the list
    final existingIndex = _messages.indexWhere((m) => m.id == message.id);
    if (existingIndex == -1) {
      // Create animation controller for the new message
      _createAnimationController(message.id);
      
      // Add to messages list
      setState(() {
        _messages.add(message);
        _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      });

      // Save message to storage
      await _hiveStorage.saveMessage(message);
      
      // Explicitly update the conversation for this message
      await _hiveStorage.updateConversationFromMessage(message);

      // Scroll to bottom
      _scrollToBottom();
      
      // Play animation for new message
      _animationControllers[message.id]?.forward();
    } else {
      // Update the message in case the status changed
      setState(() {
        _messages[existingIndex] = message;
      });
    }
  }

  void _createAnimationController(String messageId) {
    if (!_animationControllers.containsKey(messageId)) {
      final controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 350),
      );
      _animationControllers[messageId] = controller;
    }
  }

  void _updateMessageStatus(String messageId, String status) {
    setState(() {
      final index = _messages.indexWhere((m) => m.id == messageId);
      if (index >= 0) {
        _messages[index] = _messages[index].copyWith(status: status);
      }
    });
  }

  void _showTypingIndicator() {
    setState(() {
      _typingUserId = widget.conversationId;
    });

    // Hide typing indicator after a timeout
    _typingTimer?.cancel();
    _typingTimer = Timer(Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _typingUserId = null;
        });
      }
    });
  }

  void _sendTypingIndicator() {
    _socketService.sendTyping(widget.conversationId);
  }

  void _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final authService = Provider.of<AuthService>(context, listen: false);
    final currentUser = authService.currentUser;
    
    if (currentUser == null) {
      print("ERROR: No current user available when sending message");
      return;
    }

    print("Sending message to ${widget.conversationId}: $text");
    
    // Clear input field
    _messageController.clear();

    // Create a temporary message with sender's username
    final tempMessage = Message.createTemp(
      senderId: currentUser.id,
      receiverId: widget.conversationId,
      content: text,
      senderName: currentUser.username, // Include sender's username
    );

    print("Creating temporary message: ${tempMessage.id}, content: $text");

    // Create animation controller for the new message
    _createAnimationController(tempMessage.id);

    // Add to messages list immediately
    setState(() {
      _messages.add(tempMessage);
    });

    // Play animation for new message
    _animationControllers[tempMessage.id]?.forward();

    // Scroll to bottom
    _scrollToBottom();

    // Send through socket
    _socketService.sendMessage(
      widget.conversationId,
      text,
      tempId: tempMessage.id,
    );

    // Save message to storage
    await _hiveStorage.saveMessage(tempMessage);
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _typingTimer?.cancel();
    _connectionSubscription.cancel();
    _newMessageSubscription.cancel();
    _messageStatusSubscription.cancel();
    _typingSubscription.cancel();
    
    // Dispose all animation controllers
    for (final controller in _animationControllers.values) {
      controller.dispose();
    }
    
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF2A64F6),
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: Color(0xFF2A64F6).withOpacity(0.2),
              radius: 18,
              child: Text(
                widget.conversationName.isNotEmpty 
                  ? widget.conversationName[0].toUpperCase() 
                  : "?",
                style: TextStyle(
                  fontSize: 16, 
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            SizedBox(width: 12),
            Text(
              widget.conversationName,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ],
        ),
        actions: [],
      ),
      body: Container(
        decoration: BoxDecoration(
          // Chat background pattern - light pattern with subtle grid
          color: Colors.grey[100],
          image: DecorationImage(
            image: AssetImage('assets/images/chat_bg.png'), // Add this asset
            fit: BoxFit.cover,
            opacity: 0.15,
            // If asset is missing, fallback gracefully
            onError: (exception, stackTrace) {},
          ),
        ),
        child: Column(
          children: [
            // Connection status indicator if offline - REMOVED
            /* Removed offline status message */
            
            Expanded(
              child: _isLoading
                  ? Center(child: CircularProgressIndicator())
                  : _messages.isEmpty
                      ? _buildEmptyState()
                      : _buildMessagesList(),
            ),
            if (_typingUserId != null)
              Container(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: Colors.white,
                alignment: Alignment.centerLeft,
                child: Row(
                  children: [
                    _buildTypingIndicator(),
                    SizedBox(width: 8),
                    Text(
                      'Typing...',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            _buildMessageInput(),
          ],
        ),
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return SizedBox(
      width: 40,
      child: Row(
        children: List.generate(3, (index) {
          return Container(
            height: 8,
            width: 8,
            margin: EdgeInsets.only(right: 4),
            decoration: BoxDecoration(
              color: Color(0xFF2A64F6).withOpacity(0.6),
              shape: BoxShape.circle,
            ),
            child: TweenAnimationBuilder(
              tween: Tween<double>(begin: 0, end: 1),
              duration: Duration(milliseconds: 800),
              curve: Curves.easeInOut,
              builder: (context, double value, child) {
                return Transform.scale(
                  scale: 0.5 + (0.5 * (index == 0 ? value : (index == 1 ? (value + 0.3) % 1 : (value + 0.6) % 1))),
                  child: child,
                );
              },
              child: Container(
                decoration: BoxDecoration(
                  color: Color(0xFF2A64F6).withOpacity(0.6),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(
            'assets/images/empty_chat.png', // Add this asset
            width: 120,
            height: 120,
            fit: BoxFit.contain,
            // Fallback if image asset is missing
            errorBuilder: (context, error, stackTrace) {
              return Icon(
                Icons.chat_bubble_outline,
                size: 100,
                color: Colors.grey[400],
              );
            },
          ),
          SizedBox(height: 24),
          Text(
            'No messages yet',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey[700],
            ),
          ),
          SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'Start the conversation with a message',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesList() {
    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        final showDate = index == 0 || 
            !_isSameDay(message.createdAt, _messages[index - 1].createdAt);
            
        return Column(
          children: [
            if (showDate) _buildDateDivider(message.createdAt),
            AnimatedBuilder(
              animation: _animationControllers[message.id] ?? AnimationController(vsync: this, duration: Duration.zero),
              builder: (context, child) {
                final animation = CurvedAnimation(
                  parent: _animationControllers[message.id] ?? AnimationController(vsync: this, duration: Duration.zero)..value = 1.0,
                  curve: Curves.easeOutQuad,
                );
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: message.isSent ? Offset(0.2, 0) : Offset(-0.2, 0),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: _buildMessageItem(message),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDateDivider(DateTime date) {
    return Container(
      margin: EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(child: Divider(color: Colors.grey[300])),
          Container(
            margin: EdgeInsets.symmetric(horizontal: 16),
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _formatDate(date),
              style: TextStyle(
                color: Colors.grey[700],
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(child: Divider(color: Colors.grey[300])),
        ],
      ),
    );
  }

  Widget _buildMessageItem(Message message) {
    return Align(
      alignment: message.isSent ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        margin: EdgeInsets.only(
          bottom: 8,
          left: message.isSent ? 50 : 0,
          right: message.isSent ? 0 : 50,
        ),
        child: Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(message.isSent ? 18 : 0),
              topRight: Radius.circular(message.isSent ? 0 : 18),
              bottomLeft: Radius.circular(18),
              bottomRight: Radius.circular(18),
            ),
          ),
          color: message.isSent
              ? const Color(0xFF2A64F6) // Sender bubble color
              : Colors.white, // Receiver bubble color
          elevation: 0.5,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.content,
                  style: TextStyle(
                    color: message.isSent ? Colors.white : Colors.black87,
                    fontSize: 15,
                  ),
                ),
                SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      DateFormat.jm().format(message.createdAt),
                      style: TextStyle(
                        color: message.isSent ? Colors.white70 : Colors.grey[600],
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Message status builder removed as requested

  Widget _buildMessageInput() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            offset: Offset(0, -2),
            blurRadius: 4,
            color: Colors.black.withOpacity(0.08),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.emoji_emotions_outlined, color: Colors.grey[600]),
            onPressed: () {}, // Placeholder for emoji picker
          ),
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: InputDecoration(
                hintText: 'Type a message...',
                hintStyle: TextStyle(color: Colors.grey[500]),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                filled: true,
                fillColor: Colors.grey[100],
              ),
              maxLines: null,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => _sendTypingIndicator(),
            ),
          ),
          SizedBox(width: 12),
          Material(
            color: const Color(0xFF2A64F6),
            borderRadius: BorderRadius.circular(22),
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: _sendMessage,
              child: Container(
                padding: EdgeInsets.all(10),
                child: Icon(
                  Icons.send,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(Duration(days: 1));
    final dateToCheck = DateTime(date.year, date.month, date.day);

    if (dateToCheck == today) {
      return 'Today';
    } else if (dateToCheck == yesterday) {
      return 'Yesterday';
    } else if (now.difference(date).inDays < 7) {
      return DateFormat('EEEE').format(date); // e.g., Monday, Tuesday
    } else {
      return DateFormat.yMMMd().format(date); // e.g., Jan 20, 2023
    }
  }

  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year && 
           date1.month == date2.month && 
           date1.day == date2.day;
  }
  }