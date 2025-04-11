// models/user.dart
class User {
  final String id;
  final String username;
  final String? email;
  final String token;
  final String status;
  final String? profilePicture;
  final DateTime? lastSeen;
  final String? bio;

  User({
    required this.id,
    required this.username,
    this.email,
    required this.token,
    required this.status,
    this.profilePicture,
    this.lastSeen,
    this.bio,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    // Safely extract values with null handling
    String id = json['_id'] ?? '';
    String username = json['username'] ?? '';
    String? email = json['email'];
    String token = json['token'] ?? '';
    String status = json['status'] ?? 'offline';
    String? profilePicture = json['profilePicture'];
    
    // Handle lastSeen parsing safely
    DateTime? lastSeen;
    if (json['lastSeen'] != null) {
      try {
        lastSeen = DateTime.parse(json['lastSeen']);
      } catch (e) {
        print('Error parsing lastSeen: $e');
      }
    }
    
    return User(
      id: id,
      username: username,
      email: email,
      token: token,
      status: status,
      profilePicture: profilePicture,
      lastSeen: lastSeen,
      bio: json['bio'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'username': username,
      'email': email,
      'token': token,
      'status': status,
      'profilePicture': profilePicture,
      'lastSeen': lastSeen?.toIso8601String(),
      'bio': bio,
    };
  }

  User copyWith({
    String? username,
    String? email,
    String? token,
    String? status,
    String? profilePicture,
    DateTime? lastSeen,
    String? bio,
  }) {
    return User(
      id: this.id,
      username: username ?? this.username,
      email: email ?? this.email,
      token: token ?? this.token,
      status: status ?? this.status,
      profilePicture: profilePicture ?? this.profilePicture,
      lastSeen: lastSeen ?? this.lastSeen,
      bio: bio ?? this.bio,
    );
  }
}