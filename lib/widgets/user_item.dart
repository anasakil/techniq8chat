import 'package:flutter/material.dart';
import 'package:techniq8chat/models/user_model.dart';

class UserItem extends StatelessWidget {
  final User user;
  final VoidCallback onTap;

  const UserItem({
    Key? key,
    required this.user,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: _buildAvatar(),
      title: Text(user.username),
      subtitle: user.email != null && user.email!.isNotEmpty
          ? Text(user.email!)
          : null,
      trailing: _buildStatusIndicator(),
      onTap: onTap,
    );
  }

  Widget _buildAvatar() {
    // Safe check for profile picture
    final hasPicture = user.profilePicture != null && 
                       user.profilePicture!.isNotEmpty &&
                       !user.profilePicture!.contains('default-avatar');
    
    if (hasPicture) {
      try {
        return CircleAvatar(
          backgroundColor: Colors.grey[200],
          backgroundImage: NetworkImage('http://192.168.100.242:4400/${user.profilePicture}'),
          // Fallback for when image fails to load
          onBackgroundImageError: (_, __) => CircleAvatar(
            backgroundColor: Colors.blue.shade300,
            child: Text(
              _getInitial(),
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
      } catch (e) {
        print('Error displaying avatar image: $e');
        // Fallback on exception
        return _buildInitialAvatar();
      }
    } else {
      return _buildInitialAvatar();
    }
  }

  // Helper method to build avatar with initials
  Widget _buildInitialAvatar() {
    return CircleAvatar(
      backgroundColor: Colors.blue.shade300,
      child: Text(
        _getInitial(),
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  // Helper method to safely get user initial
  String _getInitial() {
    if (user.username.isNotEmpty) {
      return user.username[0].toUpperCase();
    } else {
      return '?';
    }
  }

  Widget _buildStatusIndicator() {
    Color color;
    String statusText;
    
    switch (user.status) {
      case 'online':
        color = Colors.green;
        statusText = 'Online';
        break;
      case 'away':
        color = Colors.orange;
        statusText = 'Away';
        break;
      default:
        color = Colors.grey;
        statusText = 'Offline';
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        SizedBox(width: 4),
        Text(
          statusText,
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}