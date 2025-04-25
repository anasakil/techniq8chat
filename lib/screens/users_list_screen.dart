// screens/users_list_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:techniq8chat/models/user_model.dart';
import 'package:techniq8chat/screens/chat_screen.dart';
import 'package:techniq8chat/services/auth_service.dart';
import 'package:techniq8chat/services/socket_service.dart';
import 'package:techniq8chat/services/call_service.dart';

class UsersListScreen extends StatefulWidget {
  @override
  _UsersListScreenState createState() => _UsersListScreenState();
}

class _UsersListScreenState extends State<UsersListScreen> {
  List<User> _users = [];
  bool _isLoading = true;
  String _errorMessage = '';
  TextEditingController _searchController = TextEditingController();
  late SocketService _socketService;
  late CallService _callService;

  @override
  void initState() {
    super.initState();
    _fetchUsers();
    _initializeServices();
  }

  void _initializeServices() {
    final authService = Provider.of<AuthService>(context, listen: false);
    final currentUser = authService.currentUser;

    if (currentUser != null) {
      _socketService = Provider.of<SocketService>(context, listen: false);
      if (!_socketService.isConnected) {
        _socketService.initSocket(currentUser);
      }
      
      _callService = Provider.of<CallService>(context, listen: false);
    }
  }

  Future<void> _fetchUsers() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final currentUser = authService.currentUser;

      if (currentUser == null) {
        throw Exception('Not authenticated');
      }

      final response = await http.get(
        Uri.parse('${authService.baseUrl}/api/users/all'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${currentUser.token}',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> usersData = json.decode(response.body);
        final List<User> users = usersData
            .map((userData) => User.fromJson({
                  ...userData,
                  'token': '', // We don't need token for other users
                }))
            .toList();

        setState(() {
          _users = users;
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = 'Failed to load users: ${response.statusCode}';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error: $e';
        _isLoading = false;
      });
      print('Error fetching users: $e');
    }
  }

  void _initiateVoiceCall(User user) async {
    try {
      await _callService.makeCall(context, user.id, user.username, CallType.voice);
    } catch (e) {
      print('Error initiating voice call: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start call: $e')),
      );
    }
  }

  void _initiateVideoCall(User user) async {
    try {
      await _callService.makeCall(context, user.id, user.username, CallType.video);
    } catch (e) {
      print('Error initiating video call: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start call: $e')),
      );
    }
  }

  void _filterUsers(String query) {
    if (query.isEmpty) {
      _fetchUsers();
    } else {
      setState(() {
        _users = _users
            .where((user) =>
                user.username.toLowerCase().contains(query.toLowerCase()))
            .toList();
      });
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
        title: Text('All Users'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search users...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25.0),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.grey[200],
              ),
              onChanged: _filterUsers,
            ),
          ),
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator())
                : _errorMessage.isNotEmpty
                    ? Center(child: Text(_errorMessage))
                    : _users.isEmpty
                        ? Center(child: Text('No users found'))
                        : ListView.builder(
                            itemCount: _users.length,
                            itemBuilder: (context, index) {
                              final user = _users[index];
                              return UserListItem(
                                user: user,
                                onMessage: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => ChatScreen(
                                        conversationId: user.id,
                                        conversationName: user.username,
                                        profilePicture: user.profilePicture,
                                      ),
                                    ),
                                  );
                                },
                                onAudioCall: () {
                                  _initiateVoiceCall(user);
                                },
                                onVideoCall: () {
                                  _initiateVideoCall(user);
                                },
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

class UserListItem extends StatelessWidget {
  final User user;
  final VoidCallback onMessage;
  final VoidCallback onAudioCall;
  final VoidCallback onVideoCall;

  const UserListItem({
    Key? key,
    required this.user,
    required this.onMessage,
    required this.onAudioCall,
    required this.onVideoCall,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: const Color(0xFF2A64F6).withOpacity(0.1),
          radius: 24,
          backgroundImage: user.profilePicture != null &&
                  user.profilePicture!.isNotEmpty &&
                  !user.profilePicture!.contains('default-avatar')
              ? NetworkImage('http://192.168.100.83:4400/${user.profilePicture}')
              : null,
          child: (user.profilePicture == null ||
                  user.profilePicture!.isEmpty ||
                  user.profilePicture!.contains('default-avatar')) &&
              user.username.isNotEmpty
              ? Text(
                  user.username[0].toUpperCase(),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF2A64F6),
                  ),
                )
              : null,
        ),
        title: Text(
          user.username,
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: user.status == 'online' ? Colors.green : Colors.grey,
              ),
            ),
            SizedBox(width: 6),
            Text(user.status == 'online' ? 'Online' : 'Offline'),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(Icons.chat_bubble_outline),
              onPressed: onMessage,
              color: Colors.blue,
              tooltip: 'Message',
            ),
            IconButton(
              icon: Icon(Icons.phone_outlined),
              onPressed: onAudioCall,
              color: Colors.green,
              tooltip: 'Audio Call',
            ),
            // IconButton(
            //   icon: Icon(Icons.videocam_outlined),
            //   onPressed: onVideoCall,
            //   color: Colors.purple,
            //   tooltip: 'Video Call',
            // ),
          ],
        ),
      ),
    );
  }
}