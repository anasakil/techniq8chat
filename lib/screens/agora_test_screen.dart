// lib/screens/agora_test_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:techniq8chat/models/user_model.dart';
import 'package:techniq8chat/screens/call_screen.dart';
import 'package:techniq8chat/services/agora_service.dart';
import 'package:techniq8chat/services/auth_service.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class AgoraTestScreen extends StatefulWidget {
  const AgoraTestScreen({Key? key}) : super(key: key);

  @override
  _AgoraTestScreenState createState() => _AgoraTestScreenState();
}

class _AgoraTestScreenState extends State<AgoraTestScreen> {
  // Service instances
  final AgoraService _agoraService = AgoraService();
  
  // State
  bool _isLoading = true;
  List<User> _users = [];
  List<String> _logs = [];
  ScrollController _logsScrollController = ScrollController();
  String? _errorMessage;
  User? _selectedUser;
  
  // Connection indicators
  bool _isServiceInitialized = false;
  bool _isSocketConnected = false;
  
  // Stream subscriptions
  StreamSubscription? _logSubscription;

  @override
  void initState() {
    super.initState();
    _initServices();
  }
  
  Future<void> _initServices() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    
    try {
      // Get current user
      final authService = Provider.of<AuthService>(context, listen: false);
      final currentUser = authService.currentUser;
      
      if (currentUser == null) {
        setState(() {
          _errorMessage = 'User not authenticated';
          _isLoading = false;
        });
        return;
      }
      
      // Initialize Agora service
      await _agoraService.initialize(currentUser);
      
      // Set up log handler
      _logSubscription = _agoraService.onLog.listen(_addLog);
      
      // Load user list
      await _loadUsers();
      
      setState(() {
        _isServiceInitialized = true;
        _isLoading = false;
      });
      
      // Log success
      _addLog('Services initialized successfully');
      
    } catch (e) {
      setState(() {
        _errorMessage = 'Error initializing services: $e';
        _isLoading = false;
      });
    }
  }
  
  Future<void> _loadUsers() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final currentUser = authService.currentUser;
      
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }
      
      final response = await http.get(
        Uri.parse('http://51.178.138.50:4400/api/users/all'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${currentUser.token}',
        },
      );
      
      if (response.statusCode == 200) {
        final List<dynamic> usersJson = json.decode(response.body);
        
        final users = usersJson
            .map((userData) => User.fromJson({
                  '_id': userData['_id'],
                  'username': userData['username'],
                  'email': userData['email'] ?? '',
                  'token': '',
                  'status': userData['status'] ?? 'offline',
                  'profilePicture': userData['profilePicture'],
                  'lastSeen': userData['lastSeen'],
                }))
            .where((user) => user.id != currentUser.id) // Exclude current user
            .toList();
        
        setState(() {
          _users = users;
        });
        
        _addLog('Loaded ${users.length} users');
      } else {
        throw Exception('Failed to load users: ${response.statusCode}');
      }
    } catch (e) {
      _addLog('Error loading users: $e');
      rethrow;
    }
  }
  
  void _addLog(String log) {
    setState(() {
      _logs.add('${DateTime.now().toString().substring(11, 19)}: $log');
    });
    
    // Auto-scroll logs
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logsScrollController.hasClients) {
        _logsScrollController.animateTo(
          _logsScrollController.position.maxScrollExtent,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }
  
  void _clearLogs() {
    setState(() {
      _logs.clear();
    });
  }
  
  void _startAudioCall() {
    if (_selectedUser == null) {
      _addLog('Error: No user selected');
      return;
    }
    
    _initiateCall(CallType.audio);
  }
  
  void _startVideoCall() {
    if (_selectedUser == null) {
      _addLog('Error: No user selected');
      return;
    }
    
    _initiateCall(CallType.video);
  }
  
  void _initiateCall(CallType callType) {
    _addLog('Initiating ${callType.name} call with ${_selectedUser!.username}');
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CallScreen(
          remoteUser: _selectedUser!,
          callType: callType,
          isIncoming: false,
        ),
      ),
    ).then((_) {
      // Refresh users when returning from call
      _loadUsers();
    });
  }
  
  void _refreshUsers() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      await _loadUsers();
    } catch (e) {
      _addLog('Error refreshing users: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _logSubscription?.cancel();
    _logsScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Agora Call Test'),
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _refreshUsers,
            tooltip: 'Refresh Users',
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Service status indicators
                _buildStatusPanel(),
                
                // User selection
                _buildUserSelection(),
                
                // Call controls
                _buildCallControls(),
                
                // Logs panel
                _buildLogsPanel(),
              ],
            ),
    );
  }
  
  Widget _buildStatusPanel() {
    return Container(
      margin: EdgeInsets.all(16),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Service Status',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          SizedBox(height: 12),
          _buildStatusRow(
            'Agora Service',
            _isServiceInitialized,
            _isServiceInitialized
                ? 'Initialized'
                : _errorMessage ?? 'Not initialized',
          ),
          SizedBox(height: 8),
          _buildStatusRow(
            'Socket Connection',
            _isSocketConnected,
            _isSocketConnected ? 'Connected' : 'Disconnected',
          ),
        ],
      ),
    );
  }
  
  Widget _buildStatusRow(String label, bool isActive, String status) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive ? Colors.green : Colors.red,
          ),
        ),
        SizedBox(width: 8),
        Text(
          '$label:',
          style: TextStyle(
            fontWeight: FontWeight.w500,
          ),
        ),
        SizedBox(width: 8),
        Text(status),
      ],
    );
  }
  
  Widget _buildUserSelection() {
    return Container(
      height: 120,
      margin: EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Select User to Call:',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          SizedBox(height: 8),
          Expanded(
            child: _users.isEmpty
                ? Center(
                    child: Text(
                      'No users available',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  )
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _users.length,
                    itemBuilder: (context, index) {
                      final user = _users[index];
                      final isSelected = _selectedUser?.id == user.id;
                      
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedUser = user;
                          });
                          _addLog('Selected user: ${user.username}');
                        },
                        child: Container(
                          width: 80,
                          margin: EdgeInsets.only(right: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected ? Theme.of(context).primaryColor : Colors.grey[300]!,
                              width: isSelected ? 2 : 1,
                            ),
                            color: isSelected ? Theme.of(context).primaryColor.withOpacity(0.1) : Colors.white,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Stack(
                                children: [
                                  CircleAvatar(
                                    radius: 24,
                                    backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
                                    backgroundImage: user.profilePicture != null &&
                                                    user.profilePicture!.isNotEmpty &&
                                                    !user.profilePicture!.contains('default-avatar')
                                        ? NetworkImage('http://51.178.138.50:4400/${user.profilePicture}')
                                        : null,
                                    child: (user.profilePicture == null ||
                                           user.profilePicture!.isEmpty ||
                                           user.profilePicture!.contains('default-avatar'))
                                        ? Text(
                                            user.username.isNotEmpty
                                                ? user.username[0].toUpperCase()
                                                : "?",
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: Theme.of(context).primaryColor,
                                            ),
                                          )
                                        : null,
                                  ),
                                  // Status indicator
                                  Positioned(
                                    right: 0,
                                    bottom: 0,
                                    child: Container(
                                      width: 12,
                                      height: 12,
                                      decoration: BoxDecoration(
                                        color: user.status == 'online' ? Colors.green : Colors.grey,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.white, width: 2),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 8),
                              Text(
                                user.username,
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildCallControls() {
    final bool userSelected = _selectedUser != null;
    
    return Container(
      margin: EdgeInsets.all(16),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Call Controls',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Audio call button
              _buildCallButton(
                icon: Icons.call,
                label: 'Audio Call',
                color: Colors.green,
                onTap: userSelected ? _startAudioCall : null,
              ),
              
              // Video call button
              _buildCallButton(
                icon: Icons.videocam,
                label: 'Video Call',
                color: Colors.blue,
                onTap: userSelected ? _startVideoCall : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildCallButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onTap,
  }) {
    final bool isEnabled = onTap != null;
    
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: isEnabled ? color : Colors.grey,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 30,
            ),
          ),
          SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: isEnabled ? Colors.black87 : Colors.grey,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildLogsPanel() {
    return Expanded(
      child: Container(
        margin: EdgeInsets.fromLTRB(16, 0, 16, 16),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Container(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
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
                    icon: Icon(Icons.clear_all, color: Colors.white, size: 20),
                    onPressed: _clearLogs,
                    tooltip: 'Clear logs',
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: _logsScrollController,
                padding: EdgeInsets.all(16),
                itemCount: _logs.length,
                itemBuilder: (context, index) {
                  final log = _logs[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      log,
                      style: TextStyle(
                        color: log.contains('error') || log.contains('Error')
                            ? Colors.red
                            : log.contains('success')
                                ? Colors.green[400]
                                : Colors.white70,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}