// screens/users_list_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:techniq8chat/models/user_model.dart';
import '../models/conversation.dart';
import '../services/auth_service.dart';
import '../services/hive_storage.dart'; // Changed from local_storage
import '../widgets/user_item.dart';
import 'chat_screen.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class UsersListScreen extends StatefulWidget {
  @override
  _UsersListScreenState createState() => _UsersListScreenState();
}

class _UsersListScreenState extends State<UsersListScreen> {
  List<User> _users = [];
  bool _isLoading = true;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  late HiveStorage _hiveStorage; // Changed from _localStorage

  @override
  void initState() {
    super.initState();
    // Get HiveStorage instance from provider
    _hiveStorage = Provider.of<HiveStorage>(context, listen: false);
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final currentUser = authService.currentUser;
      
      if (currentUser == null) {
        Navigator.of(context).pop();
        return;
      }
      
      // Make API request to get all users
      final response = await http.get(
        Uri.parse('http://192.168.100.76:4400/api/users/all'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${currentUser.token}',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> usersData = json.decode(response.body);
        
        // Debug print to see raw data
        print('Raw user data: ${usersData.take(2)}'); // Show first 2 users for debugging
        
        // Convert to User objects and filter out current user
        final List<User> parsedUsers = [];
        
        for (var userData in usersData) {
          try {
            // Ensure required fields are not null
            if (userData['_id'] != null && userData['username'] != null) {
              parsedUsers.add(User.fromJson({
                '_id': userData['_id'],
                'username': userData['username'],
                'email': userData['email'] ?? '', // Provide default for potentially null fields
                'token': '',  // We don't need tokens for other users
                'status': userData['status'] ?? 'offline',
                'profilePicture': userData['profilePicture'],
                'lastSeen': userData['lastSeen'],
              }));
            }
          } catch (e) {
            print('Error parsing user: $userData, Error: $e');
          }
        }
        
        final users = parsedUsers.where((user) => user.id != currentUser.id).toList();
        
        setState(() {
          _users = users;
          _isLoading = false;
        });
      } else {
        print('Failed to load users. Status code: ${response.statusCode}');
        print('Response body: ${response.body}');
        throw Exception('Failed to load users');
      }
    } catch (e) {
      print('Error loading users: $e');
      setState(() {
        _isLoading = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load users: $e')),
      );
    }
  }

  void _filterUsers() {
    setState(() {
      _searchQuery = _searchController.text.toLowerCase();
    });
  }

  List<User> get _filteredUsers {
    if (_searchQuery.isEmpty) {
      return _users;
    }
    
    return _users.where((user) {
      return user.username.toLowerCase().contains(_searchQuery) || 
             (user.email?.toLowerCase().contains(_searchQuery) ?? false);
    }).toList();
  }

  Future<void> _startConversation(User user) async {
    try {
      // Check if conversation already exists
      final conversations = await _hiveStorage.getConversations();
      final existingConversation = conversations.firstWhere(
        (c) => c.id == user.id,
        orElse: () => Conversation(
          id: user.id,
          name: user.username,
          profilePicture: user.profilePicture,
          status: user.status,
        ),
      );
      
      // Save/update conversation in Hive
      await _hiveStorage.upsertConversation(existingConversation);
      
      // Navigate to chat screen
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => ChatScreen(
            conversationId: user.id,
            conversationName: user.username,
          ),
        ),
      );
    } catch (e) {
      print('Error starting conversation: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start conversation: $e')),
      );
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('New Conversation'),
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search users...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                filled: true,
                fillColor: Colors.grey[100],
              ),
              onChanged: (_) => _filterUsers(),
            ),
          ),
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator())
                : _filteredUsers.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        itemCount: _filteredUsers.length,
                        itemBuilder: (context, index) {
                          final user = _filteredUsers[index];
                          return UserItem(
                            user: user,
                            onTap: () => _startConversation(user),
                          );
                        },
                      ),
          ),
        ],
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
              'No users found',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey[600],
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Try a different search term',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    } else {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline,
              size: 80,
              color: Colors.grey[400],
            ),
            SizedBox(height: 16),
            Text(
              'No users available',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }
  }
}