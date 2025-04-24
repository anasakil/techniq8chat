// widgets/conversation_item.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/conversation.dart';

class ConversationItem extends StatelessWidget {
  final Conversation conversation;
  final VoidCallback onTap;

  const ConversationItem({
    Key? key,
    required this.conversation,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: _buildAvatar(),
      title: Row(
        children: [
           Expanded(
          child: Text(
            // Make sure we're checking if lastMessage is null or empty
            (conversation.lastMessage != null && conversation.lastMessage!.isNotEmpty)
                ? conversation.lastMessage!
                : 'No messages yet',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: conversation.unreadCount > 0 
                  ? Colors.black87 
                  : Colors.grey[600],
              fontWeight: conversation.unreadCount > 0 
                  ? FontWeight.bold 
                  : FontWeight.normal,
            ),
          ),
        ),
        ],
      ),
      subtitle: Row(
        children: [
          Expanded(
            child: Text(
              conversation.lastMessage ?? 'No messages yet',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: conversation.unreadCount > 0 
                    ? Colors.black87 
                    : Colors.grey[600],
                fontWeight: conversation.unreadCount > 0 
                    ? FontWeight.bold 
                    : FontWeight.normal,
              ),
            ),
          ),
          _buildStatusIndicator(),
          SizedBox(width: 4),
          if (conversation.unreadCount > 0)
            Container(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                conversation.unreadCount.toString(),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
      onTap: onTap,
    );
  }

  Widget _buildAvatar() {
    if (conversation.profilePicture != null && 
        conversation.profilePicture!.isNotEmpty &&
        !conversation.profilePicture!.contains('default-avatar')) {
      return CircleAvatar(
        backgroundImage: NetworkImage('http://192.168.100.242:4400/${conversation.profilePicture}'),
      );
    } else {
      return CircleAvatar(
        backgroundColor: Colors.blue.shade200,
        child: Text(
          conversation.name.isNotEmpty
              ? conversation.name[0].toUpperCase()
              : '?',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }
  }

  Widget _buildStatusIndicator() {
    Color statusColor = Colors.grey;
    
    switch (conversation.status) {
      case 'online':
        statusColor = Colors.green;
        break;
      case 'away':
        statusColor = Colors.orange;
        break;
      case 'offline':
      default:
        statusColor = Colors.grey;
    }
    
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: statusColor,
        shape: BoxShape.circle,
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final messageDate = DateTime(time.year, time.month, time.day);
    
    if (messageDate == today) {
      return DateFormat.jm().format(time); // e.g. 5:08 PM
    } else if (messageDate == yesterday) {
      return 'Yesterday';
    } else if (now.difference(time).inDays < 7) {
      return DateFormat.E().format(time); // e.g. Tue
    } else {
      return DateFormat.MMMd().format(time); // e.g. Mar 9
    }
  }
}