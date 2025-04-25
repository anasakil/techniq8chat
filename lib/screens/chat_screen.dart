// screens/chat_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:techniq8chat/models/user_model.dart';
import 'package:techniq8chat/screens/user_details_page.dart';
import 'package:techniq8chat/screens/users_list_screen.dart';
import '../models/message.dart';
import '../services/auth_service.dart';
import '../services/socket_service.dart';
import '../services/hive_storage.dart';
import 'dart:math' as Math;


class ChatScreen extends StatefulWidget {
  final String conversationId;
  final String conversationName;
  final String? profilePicture; // Added this line

  ChatScreen({
    required this.conversationId,
    required this.conversationName,
    this.profilePicture, // Added this parameter
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
  bool _showEmojiPicker = false;

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
      print(
          'Marked conversation ${widget.conversationId} as read on screen load');
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
      print(
          "New message received in chat screen: ${message.id} from ${message.senderId}");
      // Only add messages for this conversation
      if (message.senderId == widget.conversationId ||
          message.receiverId == widget.conversationId) {
        _handleNewMessage(message);
      }
    });

    // Listen for message status updates
    _messageStatusSubscription = _socketService.onMessageStatus.listen((data) {
      print(
          "Message status update in chat screen: ${data['messageId']} - ${data['status']}");
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
      final messages = await _hiveStorage.getMessages(widget.conversationId,
          directUser: currentUser);

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
    final isRelevantMessage = (message.senderId == widget.conversationId &&
            message.receiverId == currentUser.id) ||
        (message.receiverId == widget.conversationId &&
            message.senderId == currentUser.id);

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
      _showEmojiPicker = false; // Hide emoji picker if open
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
      backgroundColor: Colors.white,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(
                    color: const Color(0xFF2A64F6),
                  ))
                : _messages.isEmpty
                    ? _buildEmptyState()
                    : _buildMessagesList(),
          ),
          // Typing indicator
          if (_typingUserId != null) _buildTypingIndicatorBar(),

          // Message input area
          _buildMessageInput(),
        ],
      ),
    );
  }
PreferredSizeWidget _buildAppBar() {
  return AppBar(
    elevation: 0,
    backgroundColor: Colors.white,
    foregroundColor: Colors.black87,
    titleSpacing: 0,
    leading: IconButton(
      icon: Icon(Icons.arrow_back_ios_new, size: 20),
      onPressed: () => Navigator.of(context).pop(),
    ),
    title: GestureDetector(
      onTap: () {
        // Navigate to user details page when tapping on the user info
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => UserDetailsPage(
              userId: widget.conversationId,
              initialUsername: widget.conversationName,
              initialProfilePicture: widget.profilePicture,
            ),
          ),
        );
      },
      child: Row(
        children: [
          // Make the avatar clickable as well
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => UserDetailsPage(
                    userId: widget.conversationId,
                    initialUsername: widget.conversationName,
                    initialProfilePicture: widget.profilePicture,
                  ),
                ),
              );
            },
            child: CircleAvatar(
              backgroundColor: const Color(0xFF2A64F6).withOpacity(0.1),
              radius: 20,
              backgroundImage: widget.profilePicture != null && 
                           widget.profilePicture!.isNotEmpty &&
                           !widget.profilePicture!.contains('default-avatar')
                  ? NetworkImage('http://192.168.100.5:4400/${widget.profilePicture}')
                  : null,
              child: (widget.profilePicture == null || 
                     widget.profilePicture!.isEmpty ||
                     widget.profilePicture!.contains('default-avatar')) &&
                     widget.conversationName.isNotEmpty
                  ? Text(
                      widget.conversationName[0].toUpperCase(),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF2A64F6),
                      ),
                    )
                  : null,
            ),
          ),
          SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.conversationName,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.black87,
                ),
              ),
              Text(
                _isConnected ? 'Online' : 'Offline',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.normal,
                  color: _isConnected ? Colors.green : Colors.grey,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
    actions: [
      IconButton(
        icon: Icon(Icons.phone_outlined),
        onPressed: () {
          Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => UsersListScreen()
          )
        );
        
        },
      ),
      IconButton(
        icon: Icon(Icons.more_vert),
        onPressed: () {
          // More options menu placeholder
        },
      ),
    ],
  );
}

  Widget _buildTypingIndicatorBar() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          _buildTypingDots(),
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
    );
  }

  Widget _buildTypingDots() {
    return SizedBox(
      width: 40,
      child: Row(
        children: List.generate(3, (index) {
          return Container(
            height: 8,
            width: 8,
            margin: EdgeInsets.only(right: 4),
            child: TweenAnimationBuilder(
              tween: Tween<double>(begin: 0, end: 1),
              duration: Duration(milliseconds: 800),
              curve: Curves.easeInOut,
              builder: (context, double value, child) {
                return Transform.scale(
                  scale: 0.5 +
                      (0.5 *
                          Math.sin(
                              (value * 2 * Math.pi) + (index * Math.pi / 2))),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A64F6).withOpacity(0.6),
                      shape: BoxShape.circle,
                    ),
                  ),
                );
              },
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
          Icon(
            Icons.chat_bubble_outline,
            size: 100,
            color: Colors.grey[300],
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
          SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              FocusScope.of(context).requestFocus(FocusNode());
              _messageController.text = "Hello! 👋";
              _scrollToBottom();
            },
            icon: Icon(Icons.emoji_emotions_outlined),
            label: Text('Say Hello'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2A64F6),
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesList() {
    // Group messages by date for better sectioning
    final Map<String, List<Message>> messagesByDate = {};

    for (final message in _messages) {
      final String dateKey = _formatDate(message.createdAt);
      if (!messagesByDate.containsKey(dateKey)) {
        messagesByDate[dateKey] = [];
      }
      messagesByDate[dateKey]!.add(message);
    }

    // Build sections for each date
    final List<Widget> sections = [];
    messagesByDate.forEach((date, messagesForDate) {
      sections.add(_buildDateDivider(date));

      // Add message bubbles
      for (int i = 0; i < messagesForDate.length; i++) {
        final message = messagesForDate[i];
        final showSenderInfo = i == 0 ||
            messagesForDate[i - 1].senderId != message.senderId ||
            message.createdAt
                    .difference(messagesForDate[i - 1].createdAt)
                    .inMinutes >
                5;

        sections.add(
          AnimatedBuilder(
            animation: _animationControllers[message.id] ??
                AnimationController(vsync: this, duration: Duration.zero),
            builder: (context, child) {
              final animation = CurvedAnimation(
                parent: _animationControllers[message.id] ??
                    AnimationController(vsync: this, duration: Duration.zero)
                  ..value = 1.0,
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
            child: _buildMessageBubble(
              message,
              showSenderInfo: showSenderInfo,
              isLastInGroup: i == messagesForDate.length - 1 ||
                  messagesForDate[i + 1].senderId != message.senderId,
            ),
          ),
        );
      }
    });

    return ListView(
      controller: _scrollController,
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: sections,
    );
  }

  Widget _buildDateDivider(String date) {
    return Container(
      margin: EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: Divider(
              color: Colors.grey[300],
              thickness: 0.5,
            ),
          ),
          Container(
            margin: EdgeInsets.symmetric(horizontal: 16),
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              date,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Divider(
              color: Colors.grey[300],
              thickness: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Message message,
      {bool showSenderInfo = true, bool isLastInGroup = true}) {
    final isSent = message.isSent;

    // Time formatter
    final timeString = DateFormat.jm().format(message.createdAt);

    return Padding(
      padding: EdgeInsets.only(
        top: showSenderInfo ? 12 : 2,
        bottom: isLastInGroup ? 12 : 2,
      ),
      child: Row(
        mainAxisAlignment:
            isSent ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Avatar (only for received messages and only show for first message in group)
          if (!isSent && showSenderInfo)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: CircleAvatar(
                radius: 16,
                backgroundColor: const Color(0xFF2A64F6).withOpacity(0.1),
                child: Text(
                  widget.conversationName.isNotEmpty
                      ? widget.conversationName[0].toUpperCase()
                      : "?",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF2A64F6),
                  ),
                ),
              ),
            )
          else if (!isSent && !showSenderInfo)
            SizedBox(width: 40), // Space for alignment when avatar is not shown

          // Bubble content
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              decoration: BoxDecoration(
                color: isSent ? const Color(0xFF2A64F6) : Colors.grey[100],
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(isSent ? 18 : 4),
                  bottomRight: Radius.circular(isSent ? 4 : 18),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 3,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Message text
                  Text(
                    message.content,
                    style: TextStyle(
                      color: isSent ? Colors.white : Colors.black87,
                      fontSize: 15,
                    ),
                  ),

                  // Time and status
                  SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        timeString,
                        style: TextStyle(
                          color: isSent
                              ? Colors.white.withOpacity(0.7)
                              : Colors.grey[600],
                          fontSize: 10,
                        ),
                      ),

                      // Message status indicator (only for sent messages)
                      // if (isSent) ...[
                      //   SizedBox(width: 4),
                      //   _buildStatusIndicator(message.status),
                      // ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Widget _buildStatusIndicator(String? status) {
  //   IconData iconData;
  //   Color iconColor;

  //   switch (status) {
  //     case 'sent':
  //       iconData = Icons.check;
  //       iconColor = Colors.white.withOpacity(0.7);
  //       break;
  //     case 'delivered':
  //       iconData = Icons.done_all;
  //       iconColor = Colors.white.withOpacity(0.7);
  //       break;
  //     case 'read':
  //       iconData = Icons.done_all;
  //       iconColor = Colors.lightBlueAccent;
  //       break;
  //     default:
  //       iconData = Icons.access_time;
  //       iconColor = Colors.white.withOpacity(0.7);
  //   }

  //   return Icon(
  //     iconData,
  //     size: 14,
  //     color: iconColor,
  //   );
  // }

  Widget _buildMessageInput() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            offset: Offset(0, -1),
            blurRadius: 8,
            color: Colors.black.withOpacity(0.05),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            // Text input field
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TextField(
                  controller: _messageController,
                  decoration: InputDecoration(
                    hintText: 'Message',
                    hintStyle: TextStyle(color: Colors.grey[500], fontSize: 15),
                    border: InputBorder.none,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  style: TextStyle(fontSize: 15),
                  maxLines: null,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => _sendTypingIndicator(),
                ),
              ),
            ),

            // Send button
            Container(
              margin: EdgeInsets.only(left: 8),
              child: FloatingActionButton(
                onPressed: _sendMessage,
                backgroundColor: const Color(0xFF2A64F6),
                elevation: 0,
                mini: true,
                child: Icon(Icons.send, color: Colors.white, size: 20),
              ),
            ),
          ],
        ),
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
