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
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF2A64F6),
        title: Text(
          'Techniq8Chat',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
        actions: [
          // Status indicator removed as requested
          IconButton(
            icon: Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Container(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: _filterConversations,
              decoration: InputDecoration(
                hintText: 'Search conversations...',
                prefixIcon: Icon(Icons.search, color: Colors.grey),
                filled: true,
                fillColor: Colors.white,
                contentPadding: EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(color: Color(0xFF2A64F6), width: 1.5),
                ),
              ),
            ),
          ),

          // Connection status indicator if offline - REMOVED AS REQUESTED
          /* Removed offline status message */

          // Conversations list
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadConversations,
              child: _isLoading
                  ? Center(child: CircularProgressIndicator())
                  : filteredConversations.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          itemCount: filteredConversations.length,
                          itemBuilder: (context, index) {
                            return _buildConversationItem(
                                filteredConversations[index]);
                          },
                        ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => UsersListScreen()),
          ).then((_) => _loadConversations());
        },
        backgroundColor: const Color(0xFF2A64F6),
        icon: Icon(Icons.chat_bubble_outline, color: Colors.white),
        label: Text('New Chat',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        elevation: 4,
      ),
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
              color: Colors.grey[400],
            ),
            SizedBox(height: 16),
            Text(
              'No conversations found',
              style: TextStyle(
                fontSize: 18,
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
          Image.asset(
            'assets/images/empty_chat.png', // Add this asset to your pubspec.yaml
            width: 120,
            height: 120,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return Icon(
                Icons.chat_bubble_outline,
                size: 100,
                color: Colors.grey[300],
              );
            },
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
            icon: Icon(Icons.add),
            label: Text('Start chatting'),
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

  Widget _buildConversationItem(Conversation conversation) {
    return Card(
      margin: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      elevation: 0.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
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
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // Avatar with status indicator
              Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: CircleAvatar(
                      radius: 28,
                      backgroundColor: const Color(0xFF2A64F6).withOpacity(0.2),
                      backgroundImage: conversation.profilePicture != null &&
                              conversation.profilePicture!.isNotEmpty &&
                              !conversation.profilePicture!
                                  .contains('default-avatar')
                          ? NetworkImage(
                              'http://192.168.100.76:4400/${conversation.profilePicture}')
                          : null,
                      child: (conversation.profilePicture == null ||
                              conversation.profilePicture!.isEmpty ||
                              conversation.profilePicture!
                                  .contains('default-avatar'))
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
              ),
              SizedBox(width: 12),
              // Message content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                          Container(
                            child: Text(
                              _formatTime(conversation.lastMessageTime!),
                              style: TextStyle(
                                color: conversation.unreadCount > 0
                                    ? const Color(0xFF2A64F6)
                                    : Colors.grey[600],
                                fontWeight: conversation.unreadCount > 0
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                    SizedBox(height: 4),
                    // Badge without displaying the number count
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            conversation.lastMessage ?? 'No messages yet',
                            style: TextStyle(
                              color: conversation.unreadCount > 0
                                  ? Colors.black87
                                  : Colors.grey[600],
                              fontWeight: conversation.unreadCount > 0
                                  ? FontWeight.w500
                                  : FontWeight.normal,
                              fontSize: 13,
                              height: 1.3,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        SizedBox(width: 8),
                        // Only show a dot indicator without the number
                        if (conversation.unreadCount > 0)
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: const Color(0xFF2A64F6),
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    )
                  ],
                ),
              ),
            ],
          ),
        ),
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
    } else if (now.difference(dateTime).inDays < 7) {
      return DateFormat('EEE').format(dateTime); // e.g., Mon, Tue
    } else {
      return DateFormat.MMMd().format(dateTime); // e.g., Jan 20
    }
  }
}
