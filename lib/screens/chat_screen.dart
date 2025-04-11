// screens/chat_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/message.dart';
import '../services/auth_service.dart';
import '../services/socket_service.dart';
import '../services/local_storage.dart';

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

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final LocalStorage _localStorage = LocalStorage();
  
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

  @override
  void initState() {
    super.initState();
    _initializeServices();
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

    // Set up socket service
    _socketService = SocketService();
    if (!_socketService.isConnected) {
      _socketService.initSocket(currentUser);
    }

    // Set up listeners
    _setupListeners();

    // Load messages
    await _loadMessages();

    // Mark conversation as read
    await _localStorage.markConversationAsRead(widget.conversationId);

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

  Future<void> _loadMessages() async {
    try {
      final messages = await _localStorage.getMessages(widget.conversationId);
      
      setState(() {
        _messages = messages;
        _isLoading = false;
      });
      
      // Scroll to bottom after loading
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });
    } catch (e) {
      print('Error loading messages: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _handleNewMessage(Message message) async {
    print("Handling new message: ${message.id}");
    
    // Mark message as delivered if it's from the other user
    if (!message.isSent) {
      _socketService.markMessageAsDelivered(message.id, message.senderId);
      
      // Also mark as read since we're in the chat
      _socketService.markMessageAsRead(message.id, message.senderId);
    }

    // Check if message is already in the list
    if (!_messages.any((m) => m.id == message.id)) {
      // Add to messages list
      setState(() {
        _messages.add(message);
        _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      });

      // Scroll to bottom
      _scrollToBottom();
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
    
    if (currentUser == null) return;

    // Clear input field
    _messageController.clear();

    // Create a temporary message
    final tempMessage = Message.createTemp(
      senderId: currentUser.id,
      receiverId: widget.conversationId,
      content: text,
    );

    print("Creating temporary message: ${tempMessage.id}");

    // Add to messages list immediately
    setState(() {
      _messages.add(tempMessage);
    });

    // Scroll to bottom
    _scrollToBottom();

    // Send through socket
    _socketService.sendMessage(
      widget.conversationId,
      text,
      tempId: tempMessage.id,
    );

    // Save message to local storage
    await _localStorage.saveMessage(tempMessage);
    
    print("Message sent and saved locally: ${tempMessage.id}");
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.conversationName),
            Text(
              _isConnected ? 'Online' : 'Offline',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        actions: [
          Container(
            margin: EdgeInsets.only(right: 16),
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isConnected ? Colors.green : Colors.red,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
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
              alignment: Alignment.centerLeft,
              child: Text(
                'Typing...',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 80,
            color: Colors.grey[400],
          ),
          SizedBox(height: 16),
          Text(
            'No messages yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Start the conversation with a message',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesList() {
    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.all(16),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        final showDate = index == 0 || 
            !_isSameDay(message.createdAt, _messages[index - 1].createdAt);
            
        return Column(
          children: [
            if (showDate) _buildDateDivider(message.createdAt),
            _buildMessageItem(message),
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
          Expanded(child: Divider()),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              _formatDate(date),
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 12,
              ),
            ),
          ),
          Expanded(child: Divider()),
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
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: message.isSent
              ? Theme.of(context).primaryColor.withOpacity(0.9)
              : Colors.grey[200],
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.content,
              style: TextStyle(
                color: message.isSent ? Colors.white : Colors.black87,
              ),
            ),
            SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  DateFormat.jm().format(message.createdAt),
                  style: TextStyle(
                    color: message.isSent ? Colors.white70 : Colors.grey[600],
                    fontSize: 10,
                  ),
                ),
                SizedBox(width: 4),
                if (message.isSent) _buildMessageStatus(message.status),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageStatus(String status) {
    IconData iconData;
    Color color;
    
    switch (status) {
      case 'sending':
        iconData = Icons.access_time;
        color = Colors.white70;
        break;
      case 'sent':
        iconData = Icons.check;
        color = Colors.white70;
        break;
      case 'delivered':
        iconData = Icons.done_all;
        color = Colors.white70;
        break;
      case 'read':
        iconData = Icons.done_all;
        color = Colors.blue[100]!;
        break;
      case 'error':
        iconData = Icons.error_outline;
        color = Colors.red[300]!;
        break;
      default:
        iconData = Icons.check;
        color = Colors.white70;
    }
    
    return Icon(
      iconData,
      size: 12,
      color: color,
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            offset: Offset(0, -2),
            blurRadius: 4,
            color: Colors.black.withOpacity(0.1),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: InputDecoration(
                hintText: 'Type a message...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                filled: true,
                fillColor: Colors.grey[200],
              ),
              maxLines: null,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => _sendTypingIndicator(),
            ),
          ),
          SizedBox(width: 8),
          CircleAvatar(
            radius: 20,
            backgroundColor: Theme.of(context).primaryColor,
            child: IconButton(
              icon: Icon(Icons.send, color: Colors.white, size: 20),
              onPressed: _sendMessage,
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