// models/conversation.dart
import 'package:hive/hive.dart';
import 'package:techniq8chat/models/user_model.dart';

part 'conversation.g.dart';

@HiveType(typeId: 1)
class Conversation {
  @HiveField(0)
  final String id; // User ID for the other person
  
  @HiveField(1)
  final String name; // Username of the other person
  
  @HiveField(2)
  final String? lastMessage;
  
  @HiveField(3)
  final DateTime? lastMessageTime;
  
  @HiveField(4)
  final String? profilePicture;
  
  @HiveField(5)
  final String status;
  
  @HiveField(6)
  final int unreadCount;
  
  @HiveField(7)
  final bool isGroup;
  
  @HiveField(8)
  final List<String> participants; // Only used for group chats

  Conversation({
    required this.id,
    required this.name,
    this.lastMessage,
    this.lastMessageTime,
    this.profilePicture,
    required this.status,
    this.unreadCount = 0,
    this.isGroup = false,
    this.participants = const [],
  });

  factory Conversation.fromJson(Map<String, dynamic> json) {
    List<String> participantsList = [];
    if (json['participants'] != null) {
      participantsList = List<String>.from(json['participants']);
    }
    
    return Conversation(
      id: json['id'],
      name: json['name'],
      lastMessage: json['lastMessage'],
      lastMessageTime: json['lastMessageTime'] != null
          ? DateTime.parse(json['lastMessageTime'])
          : null,
      profilePicture: json['profilePicture'],
      status: json['status'] ?? 'offline',
      unreadCount: json['unreadCount'] ?? 0,
      isGroup: json['isGroup'] ?? false,
      participants: participantsList,
    );
  }

  // Create from a user object
  factory Conversation.fromUser(User user) {
    return Conversation(
      id: user.id,
      name: user.username,
      profilePicture: user.profilePicture,
      status: user.status,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'lastMessage': lastMessage,
      'lastMessageTime': lastMessageTime?.toIso8601String(),
      'profilePicture': profilePicture,
      'status': status,
      'unreadCount': unreadCount,
      'isGroup': isGroup,
      'participants': participants,
    };
  }

  Conversation copyWith({
    String? name,
    String? lastMessage,
    DateTime? lastMessageTime,
    String? profilePicture,
    String? status,
    int? unreadCount,
    bool? isGroup,
    List<String>? participants,
  }) {
    return Conversation(
      id: this.id,
      name: name ?? this.name,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      profilePicture: profilePicture ?? this.profilePicture,
      status: status ?? this.status,
      unreadCount: unreadCount ?? this.unreadCount,
      isGroup: isGroup ?? this.isGroup,
      participants: participants ?? this.participants,
    );
  }
}