// import 'package:flutter/material.dart';
// import 'package:techniq8chat/models/user_model.dart';
// import 'package:techniq8chat/widgets/ChatDetailsPage.dart';

// class ChatHelper {
//   /// Safe navigation to the chat details page with proper null checking
//   static void navigateToChatDetails(BuildContext context, User? user) {
//     if (user == null) {
//       // Show an error message if user is null
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(content: Text('Error: Cannot open chat with null user')),
//       );
//       return;
//     }
    
//     // Now we know user is not null, we can safely navigate
//     Navigator.push(
//       context,
//       MaterialPageRoute(
//         builder: (context) => ChatDetailsPage(user: user),
//       ),
//     );
//   }
  
//   /// Create a user object from conversation participant data
//   static User? createUserFromParticipant(Map<String, dynamic> participant) {
//     if (participant == null) return null;
    
//     try {
//       return User(
//         id: participant['_id'] ?? '',
//         username: participant['username'] ?? 'Unknown User',
//         email: participant['email'] ?? '',
//         profilePicture: participant['profilePicture'] ?? '',
//         status: participant['status'] ?? 'offline',
//         bio: participant['bio'],
//       );
//     } catch (e) {
//       print('Error creating user from participant: $e');
//       return null;
//     }
//   }
// }