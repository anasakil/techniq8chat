import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:techniq8chat/screens/profile_screen.dart';
import 'package:techniq8chat/screens/login_screen.dart';
import 'package:techniq8chat/screens/agora_test_screen.dart'; // Add import for Agora test screen
import 'package:techniq8chat/services/auth_service.dart';
import 'package:techniq8chat/services/hive_storage.dart';

class SettingsScreen extends StatefulWidget {
  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notificationsEnabled = true;
  bool _darkModeEnabled = false;
  String _selectedLanguage = 'English';
  String? _username;
  String? _email;
  String? _profilePicture;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final currentUser = authService.currentUser;

    if (currentUser != null) {
      setState(() {
        _username = currentUser.username;
        _email = currentUser.email;
        _profilePicture = currentUser.profilePicture;
      });
    }
  }

  Future<void> _logout() async {
    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: CircularProgressIndicator(
          color: const Color(0xFF2A64F6),
        ),
      ),
    );

    try {
      // Clean up resources
      final hiveStorage = Provider.of<HiveStorage>(context, listen: false);
      await hiveStorage.clearAll();

      // Logout from auth service
      final authService = Provider.of<AuthService>(context, listen: false);
      await authService.logout();

      // Remove loading dialog
      Navigator.of(context).pop();

      // Navigate to login screen
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => LoginScreen()),
        (route) => false,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        titleSpacing: 16,
        centerTitle: false,
        title: Text(
          'Settings',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile section
            _buildProfileSection(),
            
            SizedBox(height: 20),
            
            // General settings
            _buildSectionHeader('General'),
            _buildSettingItem(
              icon: Icons.notifications_outlined,
              title: 'Notifications',
              trailing: Switch(
                value: _notificationsEnabled,
                activeColor: const Color(0xFF2A64F6),
                onChanged: (value) {
                  setState(() {
                    _notificationsEnabled = value;
                  });
                },
              ),
            ),
            
            SizedBox(height: 20),
            
            // Support and About
            _buildSectionHeader('Support and About'),
            _buildSettingItem(
              icon: Icons.help_outline,
              title: 'Help and Support',
              onTap: () {
                // Help screen navigation
              },
            ),
            _buildSettingItem(
              icon: Icons.info_outline,
              title: 'About TQCHAT',
              subtitle: 'Version 1.0.0',
              onTap: () {
                // About screen navigation
              },
            ),
            
             // Developer Tools
            _buildSectionHeader('Developer Tools'),
            _buildSettingItem(
              icon: Icons.call,
              title: 'WebRTC Call Test',
              subtitle: 'Original test call functionality',
              onTap: () {
                Navigator.pushNamed(context, '/test_call');
              },
            ),
            _buildSettingItem(
              icon: Icons.video_call,
              title: 'Agora Call Test',
              subtitle: 'Test Agora calling with debugging tools',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => AgoraTestScreen()),
                );
              },
            ),
            
            SizedBox(height: 20),
            
            // Logout button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ElevatedButton(
                onPressed: _logout,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red[50],
                  foregroundColor: Colors.red,
                  minimumSize: Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  'Log Out',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            
            SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileSection() {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => ProfileScreen()),
        ).then((_) => _loadUserData());
      },
      child: Container(
        padding: EdgeInsets.all(16),
        margin: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF2A64F6).withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            // Profile picture
            CircleAvatar(
              radius: 32,
              backgroundColor: const Color(0xFF2A64F6).withOpacity(0.1),
              backgroundImage: _profilePicture != null && 
                       _profilePicture!.isNotEmpty &&
                       !_profilePicture!.contains('default-avatar')
                ? NetworkImage('http://51.178.138.50:4400/${_profilePicture}')
                : null,
              child: (_profilePicture == null || 
                      _profilePicture!.isEmpty ||
                      _profilePicture!.contains('default-avatar')) &&
                      _username != null &&
                      _username!.isNotEmpty
                  ? Text(
                      _username![0].toUpperCase(),
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF2A64F6),
                      ),
                    )
                  : null,
            ),
            SizedBox(width: 16),
            
            // User info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _username ?? 'Loading...',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    _email ?? 'Loading...',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Tap to edit profile',
                    style: TextStyle(
                      fontSize: 12,
                      color: const Color(0xFF2A64F6),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            
            // Edit icon
            Icon(
              Icons.chevron_right,
              color: Colors.grey[400],
              size: 24,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8, top: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: const Color(0xFF2A64F6),
        ),
      ),
    );
  }

  Widget _buildSettingItem({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
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
            // Icon
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF2A64F6).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                color: const Color(0xFF2A64F6),
                size: 20,
              ),
            ),
            SizedBox(width: 16),
            
            // Title and subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                  ),
                  if (subtitle != null) ...[
                    SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            
            // Trailing widget (e.g., switch, icon)
            trailing ?? (onTap != null 
              ? Icon(
                  Icons.chevron_right,
                  color: Colors.grey[400],
                  size: 24,
                )
              : Container()),
          ],
        ),
      ),
    );
  }
}