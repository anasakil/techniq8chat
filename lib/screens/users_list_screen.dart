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
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';

class UsersListScreen extends StatefulWidget {
  @override
  _UsersListScreenState createState() => _UsersListScreenState();
}

class _UsersListScreenState extends State<UsersListScreen> with SingleTickerProviderStateMixin {
  List<User> _users = [];
  List<User> _filteredUsers = [];
  bool _isLoading = true;
  String _errorMessage = '';
  TextEditingController _searchController = TextEditingController();
  late SocketService _socketService;
  late CallService _callService;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    
    // Setup animations
    _fadeController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 300),
    );
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeIn)
    );
    
    _fetchUsers();
    _initializeServices();
    
    // Start animation after the screen loads
    Future.delayed(Duration(milliseconds: 150), () {
      _fadeController.forward();
    });
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
          _filteredUsers = users;
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
      _showErrorSnackBar('Failed to start call: $e');
    }
  }

  void _initiateVideoCall(User user) async {
    try {
      await _callService.makeCall(context, user.id, user.username, CallType.video);
    } catch (e) {
      print('Error initiating video call: $e');
      _showErrorSnackBar('Failed to start call: $e');
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        margin: EdgeInsets.all(10),
      ),
    );
  }

  void _filterUsers(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredUsers = _users;
      } else {
        _filteredUsers = _users
            .where((user) =>
                user.username.toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  Future<void> _refreshUsers() async {
    await _fetchUsers();
    return Future.value();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(
          'Contacts',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        centerTitle: false,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _refreshUsers,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: RefreshIndicator(
          onRefresh: _refreshUsers,
          child: Column(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.05),
                      spreadRadius: 1,
                      blurRadius: 3,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search contacts...',
                    hintStyle: TextStyle(color: Colors.grey[400]),
                    prefixIcon: Icon(Icons.search, color: Colors.grey[400]),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(25.0),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Colors.grey[100],
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                  onChanged: _filterUsers,
                ),
              ),
              Expanded(
                child: _isLoading
                    ? Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(const Color(0xFF2A64F6)),
                        ),
                      )
                    : _errorMessage.isNotEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
                                SizedBox(height: 16),
                                Text(
                                  _errorMessage,
                                  style: TextStyle(color: Colors.grey[700]),
                                  textAlign: TextAlign.center,
                                ),
                                SizedBox(height: 24),
                                ElevatedButton(
                                  onPressed: _fetchUsers,
                                  child: Text('Try Again'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF2A64F6),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : _filteredUsers.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.person_search, size: 64, color: Colors.grey[300]),
                                    SizedBox(height: 16),
                                    Text(
                                      'No contacts found',
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : AnimationLimiter(
                                child: ListView.builder(
                                  padding: EdgeInsets.only(top: 8),
                                  itemCount: _filteredUsers.length,
                                  itemBuilder: (context, index) {
                                    final user = _filteredUsers[index];
                                    return AnimationConfiguration.staggeredList(
                                      position: index,
                                      duration: const Duration(milliseconds: 375),
                                      child: SlideAnimation(
                                        verticalOffset: 50.0,
                                        child: FadeInAnimation(
                                          child: UserListItem(
                                            user: user,
                                            onMessage: () {
                                              Navigator.push(
                                                context,
                                                PageRouteBuilder(
                                                  pageBuilder: (context, animation, secondaryAnimation) => ChatScreen(
                                                    conversationId: user.id,
                                                    conversationName: user.username,
                                                    profilePicture: user.profilePicture,
                                                  ),
                                                  transitionsBuilder: (context, animation, secondaryAnimation, child) {
                                                    var begin = Offset(1.0, 0.0);
                                                    var end = Offset.zero;
                                                    var curve = Curves.easeInOut;
                                                    var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
                                                    return SlideTransition(
                                                      position: animation.drive(tween),
                                                      child: child,
                                                    );
                                                  },
                                                ),
                                              );
                                            },
                                            onAudioCall: () {
                                              _initiateVoiceCall(user);
                                            },
                                            onVideoCall: () {
                                              _initiateVideoCall(user);
                                            },
                                          ),
                                        ),
                                      ),
                                    );
                                  },
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
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        color: Colors.white,
        child: InkWell(
          onTap: onMessage,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: ListTile(
              contentPadding: EdgeInsets.symmetric(horizontal: 12),
              leading: Hero(
                tag: 'avatar-${user.id}',
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: user.status == 'online' 
                          ? Colors.green.shade300
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: Stack(
                    children: [
                      CircleAvatar(
                        backgroundColor: const Color(0xFF2A64F6).withOpacity(0.1),
                        radius: 26,
                        backgroundImage: user.profilePicture != null &&
                                user.profilePicture!.isNotEmpty &&
                                !user.profilePicture!.contains('default-avatar')
                            ? NetworkImage('http://51.178.138.50:4400/${user.profilePicture}')
                            : null,
                        child: (user.profilePicture == null ||
                                user.profilePicture!.isEmpty ||
                                user.profilePicture!.contains('default-avatar')) &&
                                user.username.isNotEmpty
                            ? Text(
                                user.username[0].toUpperCase(),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 22,
                                  color: const Color(0xFF2A64F6),
                                ),
                              )
                            : null,
                      ),
                      if (user.status == 'online')
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
                ),
              ),
              title: Text(
                user.username,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              subtitle: Text(
                user.status == 'online' ? 'Active now' : 'Offline',
                style: TextStyle(
                  color: user.status == 'online' ? Colors.green : Colors.grey,
                  fontSize: 13,
                ),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: Icon(Icons.chat_bubble_rounded),
                      onPressed: onMessage,
                      color: Colors.blue,
                      iconSize: 20,
                      tooltip: 'Message',
                    ),
                  ),
                  SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: Icon(Icons.phone_rounded),
                      onPressed: onAudioCall,
                      color: Colors.green,
                      iconSize: 20,
                      tooltip: 'Audio Call',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}