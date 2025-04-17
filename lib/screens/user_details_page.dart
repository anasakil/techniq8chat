// screens/user_details_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:techniq8chat/models/user_model.dart';
import 'package:techniq8chat/services/auth_service.dart';
import 'package:techniq8chat/services/user_repository.dart';
import 'package:intl/intl.dart';

class UserDetailsPage extends StatefulWidget {
  final String userId;
  final String initialUsername;
  final String? initialProfilePicture;

  const UserDetailsPage({
    Key? key,
    required this.userId,
    required this.initialUsername,
    this.initialProfilePicture,
  }) : super(key: key);

  @override
  _UserDetailsPageState createState() => _UserDetailsPageState();
}

class _UserDetailsPageState extends State<UserDetailsPage> {
  bool _isLoading = true;
  User? _userDetails;
  String? _errorMessage;
  late UserRepository _userRepository;

  @override
  void initState() {
    super.initState();
    _initializeUserRepository();
    _fetchUserDetails();
  }

  void _initializeUserRepository() {
    final authService = Provider.of<AuthService>(context, listen: false);
    final currentUser = authService.currentUser;
    
    if (currentUser != null) {
      _userRepository = UserRepository(
        baseUrl: 'http://192.168.100.5:4400',
        token: currentUser.token,
      );
    }
  }

  Future<void> _fetchUserDetails() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final userDetails = await _userRepository.getUserById(widget.userId);
      
      setState(() {
        _userDetails = userDetails;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load user details: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: _isLoading
          ? _buildLoadingState()
          : _errorMessage != null
              ? _buildErrorState()
              : _buildUserDetails(),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: CircularProgressIndicator(
        color: const Color(0xFF2A64F6),
      ),
    );
  }

  Widget _buildErrorState() {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildBackButton(),
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 70,
                    color: Colors.grey[400],
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Could not load profile',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[700],
                    ),
                  ),
                  SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: _fetchUserDetails,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2A64F6),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    ),
                    child: Text('Try Again'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackButton() {
    return Padding(
      padding: const EdgeInsets.only(left: 8.0, top: 16.0),
      child: IconButton(
        icon: Icon(Icons.arrow_back_ios, size: 20),
        onPressed: () => Navigator.of(context).pop(),
      ),
    );
  }

  Widget _buildUserDetails() {
    // Use either the fetched user details or fall back to initial data
    final username = _userDetails?.username ?? widget.initialUsername;
    final profilePicture = _userDetails?.profilePicture ?? widget.initialProfilePicture;
    final email = _userDetails?.email ?? '';
    final status = _userDetails?.status ?? 'offline';
    final lastSeen = _userDetails?.lastSeen;
    
    final hasPicture = profilePicture != null && 
                       profilePicture.isNotEmpty &&
                       !profilePicture.contains('default-avatar');
    
    return CustomScrollView(
      slivers: [
        // App Bar
        SliverAppBar(
          pinned: true,
          expandedHeight: 250.0,
          backgroundColor: Colors.white,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios, color: Colors.black87),
            onPressed: () => Navigator.of(context).pop(),
          ),
          flexibleSpace: FlexibleSpaceBar(
            background: Stack(
              fit: StackFit.expand,
              children: [
                // Background gradient
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        const Color(0xFF2A64F6).withOpacity(0.1),
                        Colors.white,
                      ],
                    ),
                  ),
                ),
                // Profile picture
                Center(
                  child: Container(
                    margin: EdgeInsets.only(top: 40),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.07),
                                blurRadius: 20,
                                offset: Offset(0, 10),
                              ),
                            ],
                          ),
                          child: CircleAvatar(
                            radius: 60,
                            backgroundColor: const Color(0xFF2A64F6).withOpacity(0.1),
                            backgroundImage: hasPicture
                                ? NetworkImage('http://192.168.100.5:4400/$profilePicture')
                                : null,
                            child: !hasPicture && username.isNotEmpty
                                ? Text(
                                    username[0].toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 48,
                                      fontWeight: FontWeight.bold,
                                      color: const Color(0xFF2A64F6),
                                    ),
                                  )
                                : null,
                          ),
                        ),
                        SizedBox(height: 20),
                        Text(
                          username,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        
        // Content
        SliverToBoxAdapter(
          child: Column(
            children: [
              // Status indicator
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: status == 'online' 
                        ? Colors.green.withOpacity(0.1)
                        : status == 'away'
                            ? Colors.orange.withOpacity(0.1)
                            : Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    status == 'online' ? 'Active Now' : 
                    status == 'away' ? 'Away' : lastSeen != null ? 'Active ${_formatLastSeen(lastSeen)}' : 'Offline',
                    style: TextStyle(
                      color: status == 'online' 
                          ? Colors.green[700] 
                          : status == 'away'
                              ? Colors.orange[700]
                              : Colors.grey[700],
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              
              // Divider
              Divider(height: 1, thickness: 1, color: Colors.grey[200]),
              
              // Message button
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: ElevatedButton.icon(
                  onPressed: () {
                    // Navigate back to chat
                    Navigator.pop(context);
                  },
                  icon: Icon(Icons.chat_outlined),
                  label: Text('Message'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2A64F6),
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
              
              SizedBox(height: 16),
              
              // User information section
              if (email.isNotEmpty || lastSeen != null) ...[
                Padding(
                  padding: const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "Details",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ),
                
                Divider(height: 1, thickness: 1, color: Colors.grey[200]),
                
                if (email.isNotEmpty)
                  _buildDetailItem(Icons.email_outlined, 'Email', email),
                
                if (lastSeen != null)
                  _buildDetailItem(
                    Icons.access_time,
                    'Last Active',
                    _formatLastSeen(lastSeen),
                  ),
              ],
              
              SizedBox(height: 24),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDetailItem(IconData icon, String label, String value) {
    return Column(
      children: [
        ListTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF2A64F6).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: const Color(0xFF2A64F6),
              size: 20,
            ),
          ),
          title: Text(
            label,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
            ),
          ),
          subtitle: Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.black87,
            ),
          ),
        ),
        Divider(height: 1, thickness: 1, indent: 70, color: Colors.grey[200]),
      ],
    );
  }

  String _formatLastSeen(DateTime lastSeen) {
    final now = DateTime.now();
    final difference = now.difference(lastSeen);
    
    if (difference.inSeconds < 60) {
      return 'just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return DateFormat.MMMMd().format(lastSeen);
    }
  }
}