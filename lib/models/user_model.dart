class User {
  final String id;
  final String username;
  final String email;
  final String profilePicture;
  String status; // Changed from final to non-final so it can be updated
  final String? bio;

  User({
    required this.id,
    required this.username,
    required this.email,
    required this.profilePicture,
    required this.status,
    this.bio,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['_id'] ?? '',
      username: json['username'] ?? 'Unknown User',
      email: json['email'] ?? '',
      profilePicture: json['profilePicture'] ?? '',
      status: json['status'] ?? 'offline',
      bio: json['bio'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'username': username,
      'email': email,
      'profilePicture': profilePicture,
      'status': status,
      'bio': bio,
    };
  }
}