import 'package:techniq8chat/models/message.dart';

class LocalMessageData {
  final String conversationId;
  final List<Message> messages;
  final DateTime lastUpdated;

  LocalMessageData({
    required this.conversationId,
    required this.messages,
    required this.lastUpdated,
  });

  factory LocalMessageData.fromJson(Map<String, dynamic> json, String currentUserId) {
    List<Message> messagesList = [];
    if (json['messages'] != null) {
      messagesList = (json['messages'] as List)
          .map((msg) => Message.fromJson(msg, currentUserId))
          .toList();
    }
    
    return LocalMessageData(
      conversationId: json['conversationId'],
      messages: messagesList,
      lastUpdated: DateTime.parse(json['lastUpdated']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'conversationId': conversationId,
      'messages': messages.map((m) => m.toJson()).toList(),
      'lastUpdated': lastUpdated.toIso8601String(),
    };
  }
}