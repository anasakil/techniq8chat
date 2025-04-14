// models/message.dart
class Message {
  final String id;
  final String senderId;
  final String receiverId;
  final String content;
  final String contentType; // text, image, video, etc.
  final DateTime createdAt;
  final String status; // sending, sent, delivered, read, failed
  final bool isSent; // Whether current user is the sender
  final String? fileUrl;
  final String? fileName;

  Message({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.content,
    this.contentType = 'text',
    required this.createdAt,
    required this.status,
    required this.isSent,
    this.fileUrl,
    this.fileName,
  });

  factory Message.fromJson(Map<String, dynamic> json, String currentUserId) {
    final senderId = json['sender'] is Map ? json['sender']['_id'] : json['sender'];
    
    return Message(
      id: json['_id'],
      senderId: senderId,
      receiverId: json['receiver'] is Map ? json['receiver']['_id'] : json['receiver'],
      content: json['content'],
      contentType: json['contentType'] ?? 'text',
      createdAt: DateTime.parse(json['createdAt']),
      status: json['status'] ?? 'sent',
      isSent: senderId == currentUserId,
      fileUrl: json['fileUrl'],
      fileName: json['fileName'],
    );
  }

  // Create from socket data with improved error handling
  factory Message.fromSocketData(Map<String, dynamic> data, String currentUserId) {
    try {
      // Handle different possible formats for sender and receiver
      String senderId = '';
      if (data['sender'] is Map) {
        senderId = data['sender']['_id'] ?? data['sender']['id'] ?? '';
      } else {
        senderId = data['sender'] ?? '';
      }
      
      String receiverId = '';
      if (data['receiver'] is Map) {
        receiverId = data['receiver']['_id'] ?? data['receiver']['id'] ?? '';
      } else {
        receiverId = data['receiver'] ?? '';
      }
      
      // Get content - may need to decrypt if it's encrypted
      String content = data['content'] ?? '';
      
      // Handle different date formats
      DateTime createdAt;
      if (data['createdAt'] != null) {
        try {
          createdAt = DateTime.parse(data['createdAt']);
        } catch (e) {
          print('Error parsing date: ${data['createdAt']}. Using current time.');
          createdAt = DateTime.now();
        }
      } else {
        createdAt = DateTime.now();
      }
      
      // Determine if message is sent by current user
      final isSent = senderId == currentUserId;
      
      return Message(
        id: data['_id'] ?? data['id'] ?? 'msg_${DateTime.now().millisecondsSinceEpoch}',
        senderId: senderId,
        receiverId: receiverId,
        content: content,
        contentType: data['contentType'] ?? 'text',
        createdAt: createdAt,
        status: data['status'] ?? (isSent ? 'sent' : 'delivered'),
        isSent: isSent,
        fileUrl: data['fileUrl'],
        fileName: data['fileName'],
      );
    } catch (e) {
      print('Error creating Message from socket data: $e');
      print('Raw data: $data');
      
      // Fallback to creating a basic message
      return Message(
        id: 'error_${DateTime.now().millisecondsSinceEpoch}',
        senderId: data['sender']?.toString() ?? '',
        receiverId: data['receiver']?.toString() ?? '',
        content: data['content']?.toString() ?? 'Message could not be displayed',
        contentType: 'text',
        createdAt: DateTime.now(),
        status: 'sent',
        isSent: data['sender'] == currentUserId,
      );
    }
  }

  // Create a temporary message for optimistic UI updates
  factory Message.createTemp({
    required String senderId,
    required String receiverId,
    required String content,
    String contentType = 'text',
    String? fileUrl,
    String? fileName,
  }) {
    final now = DateTime.now();
    return Message(
      id: 'temp_${now.millisecondsSinceEpoch}',
      senderId: senderId,
      receiverId: receiverId,
      content: content,
      contentType: contentType,
      createdAt: now,
      status: 'sending',
      isSent: true,
      fileUrl: fileUrl,
      fileName: fileName,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'sender': senderId,
      'receiver': receiverId,
      'content': content,
      'contentType': contentType,
      'createdAt': createdAt.toIso8601String(),
      'status': status,
      'isSent': isSent,
      'fileUrl': fileUrl,
      'fileName': fileName,
    };
  }

  Message copyWith({
    String? id,
    String? status,
    String? content,
    String? contentType,
    String? fileUrl,
    String? fileName,
  }) {
    return Message(
      id: id ?? this.id,
      senderId: this.senderId,
      receiverId: this.receiverId,
      content: content ?? this.content,
      contentType: contentType ?? this.contentType,
      createdAt: this.createdAt,
      status: status ?? this.status,
      isSent: this.isSent,
      fileUrl: fileUrl ?? this.fileUrl,
      fileName: fileName ?? this.fileName,
    );
  }
}