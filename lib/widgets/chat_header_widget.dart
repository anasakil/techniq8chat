// widgets/chat_header_widget.dart
import 'package:flutter/material.dart';
import 'package:techniq8chat/screens/user_details_page.dart';

class ChatHeaderWidget extends StatelessWidget {
  final String userId;
  final String username;
  final String? profilePicture;
  final bool isOnline;
  final VoidCallback onBackPressed;
  final VoidCallback? onCallPressed;
  final VoidCallback? onMoreOptionsPressed;

  const ChatHeaderWidget({
    Key? key,
    required this.userId,
    required this.username,
    this.profilePicture,
    required this.isOnline,
    required this.onBackPressed,
    this.onCallPressed,
    this.onMoreOptionsPressed,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      elevation: 0,
      backgroundColor: Colors.white,
      foregroundColor: Colors.black87,
      titleSpacing: 0,
      leading: IconButton(
        icon: Icon(Icons.arrow_back_ios_new, size: 20),
        onPressed: onBackPressed,
      ),
      title: GestureDetector(
        onTap: () {
          // Navigate to user details page
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => UserDetailsPage(
                userId: userId,
                initialUsername: username,
                initialProfilePicture: profilePicture,
              ),
            ),
          );
        },
        child: Row(
          children: [
            _buildAvatar(context),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    username,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.black87,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    isOnline ? 'Online' : 'Offline',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.normal,
                      color: isOnline ? Colors.green : Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (onCallPressed != null)
          IconButton(
            icon: Icon(Icons.phone_outlined),
            onPressed: onCallPressed,
          ),
        if (onMoreOptionsPressed != null)
          IconButton(
            icon: Icon(Icons.more_vert),
            onPressed: onMoreOptionsPressed,
          ),
      ],
    );
  }

  Widget _buildAvatar(BuildContext context) {
    final hasPicture = profilePicture != null && 
                     profilePicture!.isNotEmpty &&
                     !profilePicture!.contains('default-avatar');
                     
    return GestureDetector(
      onTap: () {
        // Navigate to user details page
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => UserDetailsPage(
              userId: userId,
              initialUsername: username,
              initialProfilePicture: profilePicture,
            ),
          ),
        );
      },
      child: CircleAvatar(
        backgroundColor: const Color(0xFF2A64F6).withOpacity(0.1),
        radius: 20,
        backgroundImage: hasPicture
            ? NetworkImage('http://192.168.100.5:4400/$profilePicture')
            : null,
        child: !hasPicture && username.isNotEmpty
            ? Text(
                username[0].toUpperCase(),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF2A64F6),
                ),
              )
            : null,
      ),
    );
  }
}