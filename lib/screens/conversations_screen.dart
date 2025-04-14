// screens/conversations_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:techniq8chat/screens/chat_screen.dart';
import 'package:techniq8chat/screens/users_list_screen.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../services/auth_service.dart';
import '../services/socket_service.dart';
import '../services/hive_storage.dart'; 
import 'login_screen.dart';
import 'package:intl/intl.dart';

class ConversationsScreen extends StatefulWidget {
  @override
  _ConversationsScreenState createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> with WidgetsBindingObserver {
  late HiveStorage _hiveStorage; 
  late SocketService _socketService;
  List<Conversation> _conversations = [];
  bool _isLoading = true;
  bool _isConnected = false;

  StreamSubscription? _connectionSubscription;
  StreamSubscription? _newMessageSubscription;
  StreamSubscription? _userStatusSubscription;

  @override
  void initState() {
    super.initState();
    // Get HiveStorage instance from provider
    _hiveStorage = Provider.of<HiveStorage>(context, listen: false);
    WidgetsBinding.instance.addObserver(this);
    _initializeServices();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // App came to foreground
      _loadConversations();
      
      // Try to reconnect socket if needed
      if (_socketService.isConnected == false) {
        print('App resumed, attempting to reconnect socket');
        _socketService.reconnect();
      }
    }
  }

  Future<void> _initializeServices() async {
    // Get current user from AuthService
    final authService = Provider.of<AuthService>(context, listen: false);
    final currentUser = authService.currentUser;
    
    if (currentUser == null) {
      // Go to login if not authenticated
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => LoginScreen()),
      );
      return;
    }

    // Initialize socket service
    _socketService = SocketService();
    if (!_socketService.isConnected) {
      _socketService.initSocket(currentUser);
    }

    // Load conversations from Hive storage
    await _loadConversations();

    // Set up listeners
    _setupListeners();
    
    // Debug: print all stored data
    _hiveStorage.debugPrintAllData();
  }

  Future<void> _loadConversations() async {
    try {
      print('Loading conversations from Hive storage');
      final conversations = await _hiveStorage.getConversations();
      
      setState(() {
        _conversations = conversations;
        _isLoading = false;
      });
      
      print('Loaded ${conversations.length} conversations');
    } catch (e) {
      print('Error loading conversations: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _setupListeners() {
    // Listen for socket connection status
    _connectionSubscription = _socketService.onConnected.listen((connected) {
      setState(() {
        _isConnected = connected;
      });
      
      if (connected) {
        // Refresh conversations when connection is established
        _loadConversations();
      }
    });

    // Listen for new messages to update conversation list
    _newMessageSubscription = _socketService.onNewMessage.listen((message) async {
      print('New message in conversation screen: ${message.id} from ${message.senderId}');
      
      // Update the conversation with the new message
      // This will call HiveStorage.updateConversationFromMessage internally
      await _updateConversationWithNewMessage(message);
      
      // Then refresh the conversations list
      await _loadConversations();
      
      // Force a UI refresh
      if (mounted) {
        setState(() {});
      }
    });

    // Listen for user status changes
    _userStatusSubscription = _socketService.onUserStatus.listen((data) async {
      print('User status update: ${data['userId']} - ${data['status']}');
      
      // Update conversation if user status changes
      await _updateUserStatus(data['userId']!, data['status']!);
    });
  }

  // Add this method to handle updating conversation data when a new message is received
  // Updated _updateConversationWithNewMessage method for conversations_screen.dart
Future<void> _updateConversationWithNewMessage(Message message) async {
  print('In ConversationsScreen: Updating conversation with message ID: ${message.id}');

  try {
    // Let HiveStorage handle the update
    await _hiveStorage.updateConversationFromMessage(message);
    
    // Force reload conversations to ensure UI is updated
    await _loadConversations();
    
    // Log success
    print('Successfully updated conversation for message: ${message.id}');
  } catch (e) {
    print('Error updating conversation with message: $e');
  }
}
  Future<void> _updateUserStatus(String userId, String status) async {
    print('Updating status for user $userId to $status');
    final conversations = await _hiveStorage.getConversations();
    final index = conversations.indexWhere((c) => c.id == userId);
    
    if (index >= 0) {
      // Update conversation status
      final updatedConversation = conversations[index].copyWith(status: status);
      await _hiveStorage.upsertConversation(updatedConversation);
      
      // Refresh conversations list
      await _loadConversations();
    }
  }

  Future<void> _logout() async {
    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(child: CircularProgressIndicator()),
    );
    
    try {
      // Clean up listeners
      _connectionSubscription?.cancel();
      _newMessageSubscription?.cancel();
      _userStatusSubscription?.cancel();
      
      // Disconnect socket
      _socketService.disconnect();
      
      // Clear Hive storage
      await _hiveStorage.clearAll();
      
      // Logout from auth service
      final authService = Provider.of<AuthService>(context, listen: false);
      await authService.logout();
      
      // Remove loading dialog
      Navigator.of(context).pop();
      
      // Navigate to login screen
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => LoginScreen()),
      );
    } catch (e) {
      // Remove loading dialog
      Navigator.of(context).pop();
      
      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Logout failed: $e')),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectionSubscription?.cancel();
    _newMessageSubscription?.cancel();
    _userStatusSubscription?.cancel();
    super.dispose();
  }

  // Rest of the widget build methods remain the same
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Conversations'),
        actions: [
          // Connection status indicator
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isConnected ? Colors.green : Colors.red,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadConversations,
        child: _isLoading
            ? Center(child: CircularProgressIndicator())
            : _conversations.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    itemCount: _conversations.length,
                    itemBuilder: (context, index) {
                      return _buildConversationItem(_conversations[index]);
                    },
                  ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => UsersListScreen()),
          ).then((_) => _loadConversations());
        },
        child: Icon(Icons.message),
        tooltip: 'New message',
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
            'No conversations yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Start a new conversation by clicking the button below',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[600]),
          ),
          SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => UsersListScreen()),
              ).then((_) => _loadConversations());
            },
            icon: Icon(Icons.add),
            label: Text('Start a conversation'),
          ),
        ],
      ),
    );
  }

 // Updated _buildConversationItem method for conversations_screen.dart
Widget _buildConversationItem(Conversation conversation) {
  return ListTile(
    leading: CircleAvatar(
      backgroundImage: conversation.profilePicture != null && 
                       conversation.profilePicture!.isNotEmpty &&
                       !conversation.profilePicture!.contains('default-avatar')
          ? NetworkImage('http://192.168.100.76:4400/${conversation.profilePicture}')
          : null,
      child: (conversation.profilePicture == null || 
              conversation.profilePicture!.isEmpty || 
              conversation.profilePicture!.contains('default-avatar')) &&
             conversation.name.isNotEmpty
          ? Text(conversation.name[0].toUpperCase())
          : null,
      backgroundColor: Colors.blue.shade300,
    ),
    title: Row(
      children: [
        Expanded(
          child: Text(
            conversation.name,
            style: TextStyle(
              fontWeight: conversation.unreadCount > 0 
                  ? FontWeight.bold 
                  : FontWeight.normal,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (conversation.lastMessageTime != null)
          Text(
            _formatTime(conversation.lastMessageTime!),
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
      ],
    ),
    subtitle: Row(
      children: [
        Expanded(
          child: Text(
            conversation.lastMessage ?? 'No messages yet',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: conversation.unreadCount > 0 
                  ? Colors.black87 
                  : Colors.grey[600],
              fontWeight: conversation.unreadCount > 0 
                  ? FontWeight.bold 
                  : FontWeight.normal,
            ),
          ),
        ),
        _buildStatusIndicator(conversation.status),
        SizedBox(width: 4),
        if (conversation.unreadCount > 0)
          Container(
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              conversation.unreadCount.toString(),
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
              ),
            ),
          ),
      ],
    ),
    onTap: () async {
      // Mark conversation as read before navigating
      if (conversation.unreadCount > 0) {
        await _hiveStorage.markConversationAsRead(conversation.id);
        
        // Also refresh the local list to update the UI
        final updatedConversation = conversation.copyWith(unreadCount: 0);
        final index = _conversations.indexWhere((c) => c.id == conversation.id);
        
        if (index >= 0) {
          setState(() {
            _conversations[index] = updatedConversation;
          });
        }
      }
      
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatScreen(
            conversationId: conversation.id,
            conversationName: conversation.name,
          ),
        ),
      ).then((_) {
        // Refresh the conversations when returning from chat screen
        _loadConversations();
      });
    },
  );
}

  Widget _buildStatusIndicator(String status) {
    Color color;
    switch (status) {
      case 'online':
        color = Colors.green;
        break;
      case 'away':
        color = Colors.orange;
        break;
      default:
        color = Colors.grey;
    }

    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(Duration(days: 1));
    final dateToCheck = DateTime(dateTime.year, dateTime.month, dateTime.day);

    if (dateToCheck == today) {
      return DateFormat.jm().format(dateTime); // e.g., 5:08 PM
    } else if (dateToCheck == yesterday) {
      return 'Yesterday';
    } else {
      return DateFormat.MMMd().format(dateTime); // e.g., Jan 20
    }
  }
}