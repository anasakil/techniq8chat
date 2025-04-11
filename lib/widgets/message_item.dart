// widgets/message_item.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/message.dart';

class MessageItem extends StatelessWidget {
  final Message message;
  final bool showDate;

  const MessageItem({
    Key? key,
    required this.message,
    this.showDate = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (showDate) _buildDateDivider(context),
        Align(
          alignment: message.isSent ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            margin: EdgeInsets.only(
              bottom: 8,
              left: message.isSent ? 50 : 0,
              right: message.isSent ? 0 : 50,
            ),
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: message.isSent
                  ? Theme.of(context).primaryColor.withOpacity(0.9)
                  : Colors.grey[200],
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.content,
                  style: TextStyle(
                    color: message.isSent ? Colors.white : Colors.black87,
                  ),
                ),
                SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      DateFormat.jm().format(message.createdAt),
                      style: TextStyle(
                        color: message.isSent ? Colors.white70 : Colors.grey[600],
                        fontSize: 10,
                      ),
                    ),
                    SizedBox(width: 4),
                    if (message.isSent) _buildStatusIcon(),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDateDivider(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(child: Divider()),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              _formatDate(message.createdAt),
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 12,
              ),
            ),
          ),
          Expanded(child: Divider()),
        ],
      ),
    );
  }

  Widget _buildStatusIcon() {
    IconData iconData;
    Color color;
    
    switch (message.status) {
      case 'sending':
        iconData = Icons.access_time;
        color = Colors.white70;
        break;
      case 'sent':
        iconData = Icons.check;
        color = Colors.white70;
        break;
      case 'delivered':
        iconData = Icons.done_all;
        color = Colors.white70;
        break;
      case 'read':
        iconData = Icons.done_all;
        color = Colors.blue[100]!;
        break;
      case 'error':
        iconData = Icons.error_outline;
        color = Colors.red[300]!;
        break;
      default:
        iconData = Icons.check;
        color = Colors.white70;
    }
    
    return Icon(
      iconData,
      size: 12,
      color: color,
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(Duration(days: 1));
    final dateToCheck = DateTime(date.year, date.month, date.day);

    if (dateToCheck == today) {
      return 'Today';
    } else if (dateToCheck == yesterday) {
      return 'Yesterday';
    } else {
      return DateFormat.yMMMd().format(date); // e.g., Jan 20, 2023
    }
  }
}