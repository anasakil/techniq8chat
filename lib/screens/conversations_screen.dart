// screens/conversations_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:techniq8chat/screens/chat_screen.dart';
import 'package:techniq8chat/screens/profile_screen.dart';
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

class _ConversationsScreenState extends State<ConversationsScreen>
    with WidgetsBindingObserver {
  late HiveStorage _hiveStorage;
  late SocketService _socketService;
  List<Conversation> _conversations = [];
  bool _isLoading = true;
  bool _isConnected = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

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
    _newMessageSubscription =
        _socketService.onNewMessage.listen((message) async {
      print(
          'New message in conversation screen: ${message.id} from ${message.senderId}');

      // Update the conversation with the new message
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

  Future<void> _updateConversationWithNewMessage(Message message) async {
    print(
        'In ConversationsScreen: Updating conversation with message ID: ${message.id}');

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
      builder: (context) => Center(child: CircularProgressIndicator(
        color: const Color(0xFF2A64F6),
      )),
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

  void _filterConversations(String query) {
    setState(() {
      _searchQuery = query.toLowerCase();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectionSubscription?.cancel();
    _newMessageSubscription?.cancel();
    _userStatusSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Filter conversations based on search query
    List<Conversation> filteredConversations = _searchQuery.isEmpty
        ? _conversations
        : _conversations
            .where((conv) =>
                conv.name.toLowerCase().contains(_searchQuery) ||
                (conv.lastMessage?.toLowerCase().contains(_searchQuery) ??
                    false))
            .toList();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          // Search bar
          _buildSearchBar(),
          
          // Content
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadConversations,
              color: const Color(0xFF2A64F6),
              child: _isLoading
                  ? Center(child: CircularProgressIndicator(
                      color: const Color(0xFF2A64F6),
                    ))
                  : filteredConversations.isEmpty
                      ? _buildEmptyState()
                      : _buildConversationsList(filteredConversations),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => UsersListScreen()),
          ).then((_) => _loadConversations());
        },
        backgroundColor: const Color(0xFF2A64F6),
        child: Icon(Icons.chat_bubble_outline, color: Colors.white),
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
  elevation: 0,
  scrolledUnderElevation: 0,
  backgroundColor: Colors.white,
  surfaceTintColor: Colors.white,
  leadingWidth: 0, // Remove default leading space
  titleSpacing: 16, // Add padding to the left of the title
  centerTitle: false, // Left align the title
  title: Image.asset(
    'assets/TQ.png', // Make sure this image exists in your assets
    height: 32, // Appropriate size for the app bar
    fit: BoxFit.contain,
    alignment: Alignment.centerLeft,
  ),
  actions: [
  IconButton(
    icon: Icon(Icons.person_outline, color: Colors.black87),
    onPressed: () {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => ProfileScreen()),
      );
    },
  ),
  IconButton(
    icon: Icon(Icons.logout, color: Colors.black87),
    onPressed: _logout,
  ),
],
);
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: EdgeInsets.all(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: TextField(
          controller: _searchController,
          onChanged: _filterConversations,
          decoration: InputDecoration(
            hintText: 'Search conversations...',
            prefixIcon: Icon(Icons.search, color: Colors.grey[600], size: 20),
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          ),
          style: TextStyle(fontSize: 15),
        ),
      ),
    );
  }

  Widget _buildConversationsList(List<Conversation> conversations) {
    return ListView.builder(
      padding: EdgeInsets.only(top: 8),
      itemCount: conversations.length,
      itemBuilder: (context, index) {
        return _buildConversationItem(conversations[index]);
      },
    );
  }

  Widget _buildEmptyState() {
    if (_searchQuery.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 80,
              color: Colors.grey[300],
            ),
            SizedBox(height: 16),
            Text(
              'No conversations found',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Try a different search term',
              style: TextStyle(color: Colors.grey[600], fontSize: 15),
            ),
          ],
        ),
      );
    }

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
            'No conversations yet',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
          SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'Start a new conversation by tapping the button below',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], fontSize: 15),
            ),
          ),
          SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => UsersListScreen()),
              ).then((_) => _loadConversations());
            },
            icon: Icon(Icons.chat_bubble_outline),
            label: Text('New Conversation'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2A64F6),
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConversationItem(Conversation conversation) {
    return InkWell(
      onTap: () async {
        // Mark conversation as read before navigating
        if (conversation.unreadCount > 0) {
          await _hiveStorage.markConversationAsRead(conversation.id);

          // Also refresh the local list to update the UI
          final updatedConversation = conversation.copyWith(unreadCount: 0);
          final index =
              _conversations.indexWhere((c) => c.id == conversation.id);

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
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Colors.grey.withOpacity(0.1),
              width: 1,
            ),
          ),
        ),
        child: Row(
          children: [
            // Avatar with status indicator
            _buildAvatar(conversation),
            SizedBox(width: 16),
            
            // Conversation details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name and time
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          conversation.name,
                          style: TextStyle(
                            fontWeight: conversation.unreadCount > 0
                                ? FontWeight.bold
                                : FontWeight.w600,
                            fontSize: 16,
                            color: Colors.black87,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(width: 4),
                      if (conversation.lastMessageTime != null)
                        Text(
                          _formatTime(conversation.lastMessageTime!),
                          style: TextStyle(
                            color: conversation.unreadCount > 0
                                ? const Color(0xFF2A64F6)
                                : Colors.grey[500],
                            fontWeight: conversation.unreadCount > 0
                                ? FontWeight.bold
                                : FontWeight.normal,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                  
                  SizedBox(height: 4),
                  
          Row(
            children: [
              Expanded(
                child: Text(
                  conversation.lastMessage ?? 'No messages yet',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    
                        color: Colors.black87,
                        fontWeight: FontWeight.bold,
                  ),
                ),
              ),
             
            ],
          ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(Conversation conversation) {
    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 5,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: CircleAvatar(
            radius: 28,
            backgroundColor: const Color(0xFF2A64F6).withOpacity(0.1),
            backgroundImage: conversation.profilePicture != null &&
                    conversation.profilePicture!.isNotEmpty &&
                    !conversation.profilePicture!.contains('default-avatar')
                ? NetworkImage('http://192.168.100.242:4400/${conversation.profilePicture}')
                : null,
            child: (conversation.profilePicture == null ||
                    conversation.profilePicture!.isEmpty ||
                    conversation.profilePicture!.contains('default-avatar'))
                ? Text(
                    conversation.name.isNotEmpty
                        ? conversation.name[0].toUpperCase()
                        : "?",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF2A64F6),
                    ),
                  )
                : null,
          ),
        ),
        
        // Online status indicator
        if (conversation.status == 'online')
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
      ],
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
    } else if (now.difference(dateTime).inDays < 7) {
      return DateFormat('EEE').format(dateTime); // e.g., Mon, Tue
    } else {
      return DateFormat.MMMd().format(dateTime); // e.g., Jan 20
    }
  }
}