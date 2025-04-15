// screens/users_list_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:techniq8chat/models/user_model.dart';
import '../models/conversation.dart';
import '../services/auth_service.dart';
import '../services/hive_storage.dart';
import 'chat_screen.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class UsersListScreen extends StatefulWidget {
  @override
  _UsersListScreenState createState() => _UsersListScreenState();
}

class _UsersListScreenState extends State<UsersListScreen> {
  List<User> _users = [];
  List<User> _filteredUsers = [];
  bool _isLoading = true;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  late HiveStorage _hiveStorage;

  @override
  void initState() {
    super.initState();
    // Get HiveStorage instance from provider
    _hiveStorage = Provider.of<HiveStorage>(context, listen: false);
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    try {
      setState(() {
        _isLoading = true;
      });
      
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
          _filteredUsers = users;
          _isLoading = false;
        });
      } else {
        print('Failed to load users. Status code: ${response.statusCode}');
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

  void _filterUsers(String query) {
    setState(() {
      _searchQuery = query.toLowerCase();
      if (_searchQuery.isEmpty) {
        _filteredUsers = _users;
      } else {
        _filteredUsers = _users.where((user) {
          return user.username.toLowerCase().contains(_searchQuery) || 
                (user.email?.toLowerCase().contains(_searchQuery) ?? false);
        }).toList();
      }
    });
  }

  Future<void> _startConversation(User user) async {
    try {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Center(
          child: CircularProgressIndicator(
            color: Color(0xFF2A64F6),
          ),
        ),
      );
      
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
      
      // Close loading dialog
      Navigator.of(context).pop();
      
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
      // Close loading dialog
      Navigator.of(context).pop();
      
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF2A64F6),
        title: Text(
          'New Chat',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadUsers,
            tooltip: 'Refresh Users',
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF2A64F6),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            padding: EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search users...',
                prefixIcon: Icon(Icons.search, color: Colors.grey[600]),
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
                  borderSide: BorderSide(color: Colors.white, width: 1.5),
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: EdgeInsets.symmetric(vertical: 12),
              ),
              onChanged: _filterUsers,
            ),
          ),
          
          // Users list
          Expanded(
            child: _isLoading
              ? Center(
                  child: CircularProgressIndicator(
                    color: const Color(0xFF2A64F6),
                  )
                )
              : _filteredUsers.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    itemCount: _filteredUsers.length,
                    itemBuilder: (context, index) {
                      final user = _filteredUsers[index];
                      return _buildUserItem(user);
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
              color: Colors.grey[300],
            ),
            SizedBox(height: 16),
            Text(
              'No users found',
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
                'Try a different search term',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600], fontSize: 15),
              ),
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
              color: Colors.grey[300],
            ),
            SizedBox(height: 16),
            Text(
              'No users available',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
              ),
            ),
            SizedBox(height: 24),
            ElevatedButton.icon(
              icon: Icon(Icons.refresh),
              label: Text('Refresh'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2A64F6),
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              onPressed: _loadUsers,
            ),
          ],
        ),
      );
    }
  }

  Widget _buildUserItem(User user) {
    final hasPicture = user.profilePicture != null && 
                       user.profilePicture!.isNotEmpty &&
                       !user.profilePicture!.contains('default-avatar');
    
    return Card(
      margin: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 0.3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _startConversation(user),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // Avatar with status indicator
              Stack(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: const Color(0xFF2A64F6).withOpacity(0.2),
                    backgroundImage: hasPicture
                        ? NetworkImage('http://192.168.100.76:4400/${user.profilePicture}')
                        : null,
                    child: !hasPicture && user.username.isNotEmpty
                        ? Text(
                            user.username[0].toUpperCase(),
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF2A64F6),
                            ),
                          )
                        : null,
                  ),
                  // Status indicator
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: user.status == 'online' 
                            ? Colors.green 
                            : user.status == 'away'
                                ? Colors.orange
                                : Colors.grey[400],
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(width: 16),
              // User details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.username,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      user.email ?? '',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // Status badge
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: user.status == 'online' 
                      ? Colors.green.withOpacity(0.1)
                      : user.status == 'away'
                          ? Colors.orange.withOpacity(0.1)
                          : Colors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: user.status == 'online' 
                        ? Colors.green.withOpacity(0.3)
                        : user.status == 'away'
                            ? Colors.orange.withOpacity(0.3)
                            : Colors.grey.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Text(
                  user.status == 'online' ? 'Online' : 
                  user.status == 'away' ? 'Away' : 'Offline',
                  style: TextStyle(
                    color: user.status == 'online' 
                        ? Colors.green[700] 
                        : user.status == 'away'
                            ? Colors.orange[700]
                            : Colors.grey[700],
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}