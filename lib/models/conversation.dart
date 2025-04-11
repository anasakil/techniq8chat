import 'package:techniq8chat/models/user_model.dart';

import 'message.dart';

class Conversation {
  final String id;
  final List<User> participants;
  final bool isGroup;
  final String? groupName;
  final User? groupAdmin;
  final Message? lastMessage;
  final int unreadCount;
  
  Conversation({
    required this.id,
    required this.participants,
    required this.isGroup,
    this.groupName,
    this.groupAdmin,
    this.lastMessage,
    this.unreadCount = 0,
  });
  
  factory Conversation.fromJson(Map<String, dynamic> json) {
    List<User> participantsList = [];
    if (json['participants'] != null) {
      participantsList = (json['participants'] as List)
          .map((participant) => User.fromJson(participant))
          .toList();
    }
    
    return Conversation(
      id: json['_id'],
      participants: participantsList,
      isGroup: json['isGroup'] ?? false,
      groupName: json['groupName'],
      groupAdmin: json['groupAdmin'] != null ? User.fromJson(json['groupAdmin']) : null,
      lastMessage: json['lastMessage'] != null ? Message.fromJson(json['lastMessage']) : null,
      unreadCount: json['unreadCount'] ?? 0,
    );
  }
}