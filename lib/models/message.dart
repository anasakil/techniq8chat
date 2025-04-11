import 'package:techniq8chat/models/user_model.dart';

class Message {
  final String id;
  final String conversationId;
  final User sender;
  final String content;
  final String contentType;
  final String? fileUrl;
  final String? fileName;
  final int? fileSize;
  final String status;
  final List<MessageRead> readBy;
  final List<MessageReaction> reactions;
  final String? forwardedFrom;
  final bool encrypted;
  final DateTime createdAt;
  
  Message({
    required this.id,
    required this.conversationId,
    required this.sender,
    required this.content,
    required this.contentType,
    this.fileUrl,
    this.fileName,
    this.fileSize,
    required this.status,
    required this.readBy,
    required this.reactions,
    this.forwardedFrom,
    required this.encrypted,
    required this.createdAt,
  });
  
  factory Message.fromJson(Map<String, dynamic> json) {
    List<MessageRead> readByList = [];
    if (json['readBy'] != null) {
      readByList = (json['readBy'] as List)
          .map((read) => MessageRead.fromJson(read))
          .toList();
    }
    
    List<MessageReaction> reactionsList = [];
    if (json['reactions'] != null) {
      reactionsList = (json['reactions'] as List)
          .map((reaction) => MessageReaction.fromJson(reaction))
          .toList();
    }
    
    return Message(
      id: json['_id'],
      conversationId: json['conversationId'] ?? '',
      sender: User.fromJson(json['sender']),
      content: json['content'],
      contentType: json['contentType'] ?? 'text',
      fileUrl: json['fileUrl'],
      fileName: json['fileName'],
      fileSize: json['fileSize'],
      status: json['status'] ?? 'sent',
      readBy: readByList,
      reactions: reactionsList,
      forwardedFrom: json['forwardedFrom'],
      encrypted: json['encrypted'] ?? true,
      createdAt: DateTime.parse(json['createdAt']),
    );
  }
}

class MessageRead {
  final User user;
  final DateTime readAt;
  
  MessageRead({
    required this.user,
    required this.readAt,
  });
  
  factory MessageRead.fromJson(Map<String, dynamic> json) {
    return MessageRead(
      user: User.fromJson(json['user']),
      readAt: DateTime.parse(json['readAt']),
    );
  }
}

class MessageReaction {
  final User user;
  final String type;
  final DateTime createdAt;
  
  MessageReaction({
    required this.user,
    required this.type,
    required this.createdAt,
  });
  
  factory MessageReaction.fromJson(Map<String, dynamic> json) {
    return MessageReaction(
      user: User.fromJson(json['user']),
      type: json['type'],
      createdAt: DateTime.parse(json['createdAt']),
    );
  }
}