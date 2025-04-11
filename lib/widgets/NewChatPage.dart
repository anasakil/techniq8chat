import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:techniq8chat/controller/auth_provider.dart';
import 'package:techniq8chat/models/user_model.dart';
import 'package:techniq8chat/widgets/ChatDetailsPage.dart';
import 'package:techniq8chat/widgets/ChatHelper.dart';
import 'package:techniq8chat/services/chat_service.dart';

class NewChatPage extends StatefulWidget {
  const NewChatPage({Key? key}) : super(key: key);

  @override
  _NewChatPageState createState() => _NewChatPageState();
}

class _NewChatPageState extends State<NewChatPage> {
  final ChatService _chatService = ChatService();
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = true;
  String _error = '';
  List<User> _users = [];
  List<User> _filteredUsers = [];
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      print('Loading all users...');
      final users = await _chatService.getAllUsers();
      print('Loaded ${users.length} users');
      
      setState(() {
        _users = users;
        _filteredUsers = users;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading users: $e');
      setState(() {
        _error = 'Failed to load users: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  void _searchUsers(String query) {
    setState(() {
      _isSearching = query.isNotEmpty;
      
      if (query.isEmpty) {
        _filteredUsers = _users;
      } else {
        _filteredUsers = _users.where((user) => 
          user.username.toLowerCase().contains(query.toLowerCase()) ||
          (user.email.isNotEmpty && user.email.toLowerCase().contains(query.toLowerCase()))
        ).toList();
      }
    });
  }

  Future<void> _createConversation(User user) async {
    try {
      // Create conversation
      await _chatService.createConversation(user.id);
      
      // Navigate to chat screen
      if (mounted) {
        ChatHelper.navigateToChatDetails(context, user);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to create conversation: ${e.toString()}';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = Provider.of<AuthProvider>(context).currentUser;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'New Chat',
          style: TextStyle(color: Colors.black),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // Search field
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              onChanged: _searchUsers,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search for users...',
                prefixIcon: const Icon(Icons.search, color: Color(0xFF4F3835)),
                fillColor: Colors.grey[200],
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide.none,
                ),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _searchUsers('');
                        },
                      )
                    : null,
              ),
            ),
          ),
          
          // Error message
          if (_error.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(8),
              margin: const EdgeInsets.symmetric(horizontal: 16),
              color: Colors.red.shade100,
              width: double.infinity,
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.red),
                    onPressed: () => setState(() => _error = ''),
                    iconSize: 16,
                  ),
                ],
              ),
            ),
          
          // Results
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredUsers.isEmpty
                    ? Center(
                        child: _isSearching
                            ? const Text('No users found')
                            : const Text('No users available'),
                      )
                    : ListView.builder(
                        itemCount: _filteredUsers.length,
                        itemBuilder: (context, index) {
                          final user = _filteredUsers[index];
                          
                          // Skip current user
                          if (currentUser != null && user.id == currentUser.id) {
                            return const SizedBox.shrink();
                          }
                          
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: _getAvatarColor(user.username),
                              child: Text(
                                user.username.substring(0, 1).toUpperCase(),
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                            title: Text(user.username),
                            subtitle: user.email.isNotEmpty
                                ? Text(user.email)
                                : null,
                            trailing: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: user.status == 'online'
                                    ? Colors.green
                                    : Colors.grey,
                              ),
                            ),
                            onTap: () => _createConversation(user),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Color _getAvatarColor(String name) {
    final List<Color> colors = [
      Colors.red,
      Colors.green,
      Colors.blue,
      Colors.orange,
      Colors.purple,
      Colors.teal,
      Colors.pink,
    ];
    
    if (name.isEmpty) return colors[0];
    
    // Simple hash to get consistent color for the same name
    int hash = 0;
    for (var i = 0; i < name.length; i++) {
      hash = name.codeUnitAt(i) + ((hash << 5) - hash);
    }
    
    return colors[hash.abs() % colors.length];
  }
}