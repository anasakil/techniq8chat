import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:techniq8chat/models/user_model.dart';
import 'package:techniq8chat/services/auth_service.dart';

class TestCallPage extends StatefulWidget {
  const TestCallPage({Key? key}) : super(key: key);

  @override
  _TestCallPageState createState() => _TestCallPageState();
}

class _TestCallPageState extends State<TestCallPage> {
  List<User> _users = [];
  bool _isLoading = true;
  String _error = '';
  ScrollController _logScrollController = ScrollController();
  List<String> _logs = [];

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  @override
  void dispose() {
    _logScrollController.dispose();
    super.dispose();
  }

  // Add log entries
  void _log(String message) {
    setState(() {
      _logs.add("${DateTime.now().toString().substring(11, 19)}: $message");
    });
    // Auto-scroll to bottom of logs
    Future.delayed(Duration(milliseconds: 100), () {
      if (_logScrollController.hasClients) {
        _logScrollController.animateTo(
          _logScrollController.position.maxScrollExtent,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // Fetch all users from the API
  Future<void> _fetchUsers() async {
    setState(() {
      _isLoading = true;
      _error = '';
      _log('Fetching users...');
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final currentUser = authService.currentUser;

      if (currentUser == null) {
        throw Exception('Not logged in');
      }

      final response = await http.get(
        Uri.parse('http://192.168.100.96:4400/api/users/all'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${currentUser.token}',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        
        // Convert to User objects and exclude current user
        final users = data
            .map((userData) => User.fromJson(userData))
            .where((user) => user.id != currentUser.id)
            .toList();
        
        setState(() {
          _users = users;
          _isLoading = false;
          _log('Successfully loaded ${users.length} users');
        });
      } else {
        throw Exception('Failed to load users: ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
        _log('Error: $e');
      });
    }
  }

  // Initialize a WebRTC call with a user
  void _initiateCall(User user, bool isVideoCall) {
    _log('Initiating ${isVideoCall ? 'video' : 'audio'} call with ${user.username}');
    
    try {
      // Here you would implement the actual WebRTC call logic
      // This is just for testing the UI and debug
      _log('Call type: ${isVideoCall ? 'Video' : 'Audio'}');
      _log('User ID: ${user.id}');
      _log('User status: ${user.status}');
      
      // Show a snackbar to indicate call attempt
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Initiating ${isVideoCall ? 'video' : 'audio'} call with ${user.username}'),
          duration: Duration(seconds: 2),
        ),
      );
      
      // Simulate a call attempt response
      Future.delayed(Duration(seconds: 2), () {
        if (user.status == 'online') {
          _log('👍 User is online, call would connect');
        } else {
          _log('⚠️ User is not online, call might fail');
        }
      });
    } catch (e) {
      _log('❌ Call error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'WebRTC Call Test',
          style: TextStyle(color: Colors.black87),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: Colors.black87),
            onPressed: _fetchUsers,
          ),
        ],
      ),
      body: Column(
        children: [
          // Users list
          Expanded(
            flex: 2,
            child: _isLoading
              ? Center(child: CircularProgressIndicator())
              : _error.isNotEmpty
                ? _buildErrorWidget()
                : _users.isEmpty
                  ? _buildEmptyState()
                  : _buildUsersList(),
          ),
          
          // Logs panel
          Expanded(
            flex: 1,
            child: Container(
              margin: EdgeInsets.all(8),
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Debug Logs',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.clear_all, color: Colors.white, size: 16),
                        onPressed: () {
                          setState(() {
                            _logs.clear();
                          });
                        },
                      )
                    ],
                  ),
                  Expanded(
                    child: ListView.builder(
                      controller: _logScrollController,
                      itemCount: _logs.length,
                      itemBuilder: (context, index) {
                        return Text(
                          _logs[index],
                          style: TextStyle(
                            color: _logs[index].contains('Error') || _logs[index].contains('❌') 
                                ? Colors.red 
                                : _logs[index].contains('⚠️')
                                    ? Colors.yellow
                                    : _logs[index].contains('👍')
                                        ? Colors.green
                                        : Colors.white70,
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 48, color: Colors.red),
          SizedBox(height: 16),
          Text('Error: $_error', textAlign: TextAlign.center),
          SizedBox(height: 16),
          ElevatedButton(
            onPressed: _fetchUsers,
            child: Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2A64F6),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: 48, color: Colors.grey),
          SizedBox(height: 16),
          Text('No users available'),
          SizedBox(height: 16),
          ElevatedButton(
            onPressed: _fetchUsers,
            child: Text('Refresh'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2A64F6),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUsersList() {
    return ListView.builder(
      itemCount: _users.length,
      itemBuilder: (context, index) {
        final user = _users[index];
        return Card(
          margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          elevation: 1,
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: const Color(0xFF2A64F6).withOpacity(0.1),
              backgroundImage: user.profilePicture != null && user.profilePicture!.isNotEmpty
                ? NetworkImage('http://192.168.100.96:4400/${user.profilePicture}')
                : null,
              child: (user.profilePicture == null || user.profilePicture!.isEmpty) && user.username.isNotEmpty
                ? Text(
                    user.username[0].toUpperCase(),
                    style: TextStyle(
                      color: const Color(0xFF2A64F6),
                      fontWeight: FontWeight.bold,
                    ),
                  )
                : null,
            ),
            title: Text(user.username),
            subtitle: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: user.status == 'online'
                        ? Colors.green
                        : user.status == 'away'
                            ? Colors.orange
                            : Colors.grey,
                    shape: BoxShape.circle,
                  ),
                ),
                SizedBox(width: 4),
                Text(user.status ?? 'offline'),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Audio call button
                IconButton(
                  icon: Icon(Icons.call, color: Colors.green),
                  onPressed: () => _initiateCall(user, false),
                  tooltip: 'Audio Call',
                ),
                // Video call button
                IconButton(
                  icon: Icon(Icons.videocam, color: const Color(0xFF2A64F6)),
                  onPressed: () => _initiateCall(user, true),
                  tooltip: 'Video Call',
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}