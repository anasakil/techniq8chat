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

  // Create from socket data
  factory Message.fromSocketData(Map<String, dynamic> data, String currentUserId) {
    final senderId = data['sender'] is Map ? data['sender']['_id'] : data['sender'];
    final receiverId = data['receiver'] is Map ? data['receiver']['_id'] : data['receiver'];
    
    return Message(
      id: data['_id'],
      senderId: senderId,
      receiverId: receiverId,
      content: data['content'],
      contentType: data['contentType'] ?? 'text',
      createdAt: data['createdAt'] != null 
          ? DateTime.parse(data['createdAt']) 
          : DateTime.now(),
      status: data['status'] ?? 'sent',
      isSent: senderId == currentUserId,
      fileUrl: data['fileUrl'],
      fileName: data['fileName'],
    );
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