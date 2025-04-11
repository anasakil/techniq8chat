// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';
// import 'package:intl/intl.dart';
// import 'package:techniq8chat/controller/auth_provider.dart';
// import 'package:techniq8chat/models/user_model.dart';
// import 'package:techniq8chat/widgets/ChatDetailsPage.dart';
// import 'package:techniq8chat/widgets/ChatHelper.dart';
// import 'package:techniq8chat/widgets/NewChatPage.dart';
// import 'package:techniq8chat/services/chat_service.dart';
// import 'package:techniq8chat/services/socket_service.dart';
// import 'package:techniq8chat/widgets/ChatBottomNavBar.dart';

// class ConversationListPage extends StatefulWidget {
//   const ConversationListPage({Key? key}) : super(key: key);

//   @override
//   _ConversationListPageState createState() => _ConversationListPageState();
// }

// class _ConversationListPageState extends State<ConversationListPage> {
//   final ChatService _chatService = ChatService();
//   bool _isLoading = true;
//   String _error = '';
//   List<dynamic> _conversations = [];
//   final TextEditingController _searchController = TextEditingController();

//   @override
//   void initState() {
//     super.initState();
//     _initializeSocket();
//     _loadConversations();
//   }

//   @override
//   void dispose() {
//     _searchController.dispose();
//     super.dispose();
//   }

//   Future<void> _initializeSocket() async {
//     try {
//       final currentUser = Provider.of<AuthProvider>(context, listen: false).currentUser;
//       if (currentUser != null) {
//         await SocketService.instance.init(currentUser.id);
        
//         // Listen for message status updates
//         SocketService.instance.onMessageStatusUpdated().listen((_) {
//           // Refresh the list when a message status changes
//           _loadConversations();
//         });
        
//         // Listen for user status changes
//         SocketService.instance.onUserStatusChanged().listen((_) {
//           // Refresh the list when a user status changes
//           _loadConversations();
//         });
//       }
//     } catch (e) {
//       print('Error initializing socket: $e');
//     }
//   }

//   Future<void> _loadConversations() async {
//     setState(() {
//       _isLoading = true;
//       _error = '';
//     });

//     try {
//       print('Loading conversations...');
//       final conversations = await _chatService.getConversations();
//       print('Loaded ${conversations.length} conversations');
      
//       setState(() {
//         _conversations = conversations;
//         _isLoading = false;
//       });
//     } catch (e) {
//       print('Error loading conversations: $e');
//       setState(() {
//         _error = 'Failed to load conversations: ${e.toString()}';
//         _isLoading = false;
//       });
//     }
//   }

//   void _filterConversations(String query) {
//     // Filter conversations based on the search query
//     // This would be implemented if needed
//   }

//   void _navigateToChat(dynamic conversation) {
//     // Extract the other user from the conversation
//     final currentUser = Provider.of<AuthProvider>(context, listen: false).currentUser;
//     if (currentUser == null) return;

//     if (conversation['isGroup'] == true) {
//       // Handle group chat navigation (not implemented in this example)
//       return;
//     }

//     // Find the other participant in the conversation
//     User? otherUser;
//     for (var participant in conversation['participants']) {
//       if (participant['_id'] != currentUser.id) {
//         otherUser = ChatHelper.createUserFromParticipant(participant);
//         break;
//       }
//     }

//     // Navigate using the helper which handles null safety
//     ChatHelper.navigateToChatDetails(context, otherUser);
    
//     // Refresh conversations when returning
//     _loadConversations();
//   }

//   void _navigateToNewChat() {
//     Navigator.push(
//       context,
//       MaterialPageRoute(
//         builder: (context) => const NewChatPage(),
//       ),
//     ).then((_) => _loadConversations()); // Refresh when returning
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       body: SafeArea(
//         child: Column(
//           children: [
//             Padding(
//               padding: const EdgeInsets.all(16.0),
//               child: TextField(
//                 controller: _searchController,
//                 onChanged: _filterConversations,
//                 decoration: InputDecoration(
//                   hintText: 'Search conversations...',
//                   prefixIcon: const Icon(Icons.search, color: Color(0xFF4F3835)),
//                   fillColor: Colors.grey[200],
//                   filled: true,
//                   border: OutlineInputBorder(
//                     borderRadius: BorderRadius.circular(15),
//                     borderSide: BorderSide.none,
//                   ),
//                 ),
//               ),
//             ),
            
//             // Error message
//             if (_error.isNotEmpty)
//               Container(
//                 padding: const EdgeInsets.all(8),
//                 margin: const EdgeInsets.symmetric(horizontal: 16),
//                 color: Colors.red.shade100,
//                 width: double.infinity,
//                 child: Row(
//                   children: [
//                     const Icon(Icons.error_outline, color: Colors.red),
//                     const SizedBox(width: 8),
//                     Expanded(
//                       child: Text(
//                         _error,
//                         style: const TextStyle(color: Colors.red),
//                       ),
//                     ),
//                     IconButton(
//                       icon: const Icon(Icons.close, color: Colors.red),
//                       onPressed: () => setState(() => _error = ''),
//                       iconSize: 16,
//                     ),
//                   ],
//                 ),
//               ),
            
//             // Conversations list
//             Expanded(
//               child: _isLoading
//                   ? const Center(child: CircularProgressIndicator())
//                   : _conversations.isEmpty
//                       ? Center(
//                           child: Column(
//                             mainAxisAlignment: MainAxisAlignment.center,
//                             children: [
//                               const Icon(
//                                 Icons.chat_bubble_outline,
//                                 size: 64,
//                                 color: Colors.grey,
//                               ),
//                               const SizedBox(height: 16),
//                               const Text(
//                                 'No conversations yet',
//                                 style: TextStyle(
//                                   fontSize: 18,
//                                   fontWeight: FontWeight.bold,
//                                   color: Colors.grey,
//                                 ),
//                               ),
//                               const SizedBox(height: 8),
//                               const Text(
//                                 'Start chatting with someone',
//                                 style: TextStyle(color: Colors.grey),
//                               ),
//                               const SizedBox(height: 24),
//                               ElevatedButton(
//                                 onPressed: _navigateToNewChat,
//                                 style: ElevatedButton.styleFrom(
//                                   backgroundColor: Colors.deepOrange,
//                                   padding: const EdgeInsets.symmetric(
//                                     horizontal: 24,
//                                     vertical: 12,
//                                   ),
//                                   shape: RoundedRectangleBorder(
//                                     borderRadius: BorderRadius.circular(20),
//                                   ),
//                                 ),
//                                 child: const Text('Start New Chat'),
//                               ),
//                             ],
//                           ),
//                         )
//                       : ListView.builder(
//                           itemCount: _conversations.length,
//                           itemBuilder: (context, index) {
//                             final conversation = _conversations[index];
//                             return _buildConversationItem(conversation);
//                           },
//                         ),
//             ),
//           ],
//         ),
//       ),
//       floatingActionButton: FloatingActionButton(
//         onPressed: _navigateToNewChat,
//         backgroundColor: Colors.deepOrange,
//         child: const Icon(Icons.chat),
//       ),
//       bottomNavigationBar: CustomBottomNavBar(
//         onTap: (index) {
//           // Handle navigation bar tap
//         },
//       ),
//     );
//   }

//   Widget _buildConversationItem(dynamic conversation) {
//     final currentUser = Provider.of<AuthProvider>(context).currentUser;
//     if (currentUser == null) return const SizedBox();

//     // Determine the conversation name and image
//     String name = conversation['isGroup'] 
//         ? conversation['groupName'] 
//         : '';
    
//     String avatar = '';
//     String lastMessage = 'No messages yet';
//     String lastMessageTime = '';
//     bool hasUnread = false;
//     String status = 'offline';
    
//     // Find the other participant in one-on-one conversations
//     if (!conversation['isGroup']) {
//       for (var participant in conversation['participants']) {
//         if (participant['_id'] != currentUser.id) {
//           name = participant['username'];
//           avatar = participant['profilePicture'];
//           status = participant['status'] ?? 'offline';
//           break;
//         }
//       }
//     }
    
//     // Get last message details
//     if (conversation['lastMessage'] != null) {
//       lastMessage = conversation['lastMessage']['content'];
//       final DateTime date = DateTime.parse(conversation['lastMessage']['createdAt']);
//       lastMessageTime = _formatTime(date);
//     }
    
//     // Check for unread messages
//     if (conversation['unreadCount'] != null) {
//       final int unreadCount = conversation['unreadCount'] ?? 0;
//       hasUnread = unreadCount > 0;
//     }
    
//     // First letter for avatar
//     final String initials = name.isNotEmpty ? name[0].toUpperCase() : '?';
    
//     return ListTile(
//       leading: Stack(
//         children: [
//           CircleAvatar(
//             backgroundColor: _getAvatarColor(name),
//             child: Text(initials, style: const TextStyle(color: Colors.white)),
//           ),
//           if (status == 'online')
//             Positioned(
//               bottom: 0,
//               right: 0,
//               child: Container(
//                 width: 12,
//                 height: 12,
//                 decoration: BoxDecoration(
//                   color: Colors.green,
//                   shape: BoxShape.circle,
//                   border: Border.all(color: Colors.white, width: 2),
//                 ),
//               ),
//             ),
//         ],
//       ),
//       title: Text(
//         name,
//         style: const TextStyle(fontWeight: FontWeight.bold),
//       ),
//       subtitle: Text(
//         lastMessage,
//         maxLines: 1,
//         overflow: TextOverflow.ellipsis,
//       ),
//       trailing: Column(
//         mainAxisAlignment: MainAxisAlignment.center,
//         crossAxisAlignment: CrossAxisAlignment.end,
//         children: [
//           Text(
//             lastMessageTime,
//             style: TextStyle(color: Colors.grey, fontSize: 12),
//           ),
//           if (hasUnread)
//             Container(
//               margin: const EdgeInsets.only(top: 4),
//               padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
//               decoration: BoxDecoration(
//                 color: Colors.green,
//                 borderRadius: BorderRadius.circular(10),
//               ),
//               child: const Text(
//                 '1',
//                 style: TextStyle(color: Colors.white, fontSize: 10),
//               ),
//             ),
//         ],
//       ),
//       onTap: () => _navigateToChat(conversation),
//     );
//   }

//   Color _getAvatarColor(String name) {
//     final List<Color> colors = [
//       Colors.red,
//       Colors.green,
//       Colors.blue,
//       Colors.orange,
//       Colors.purple,
//       Colors.teal,
//       Colors.pink,
//     ];
    
//     if (name.isEmpty) return colors[0];
    
//     // Simple hash to get consistent color for the same name
//     int hash = 0;
//     for (var i = 0; i < name.length; i++) {
//       hash = name.codeUnitAt(i) + ((hash << 5) - hash);
//     }
    
//     return colors[hash.abs() % colors.length];
//   }

//   String _formatTime(DateTime dateTime) {
//     final now = DateTime.now();
//     final difference = now.difference(dateTime);
    
//     if (difference.inDays > 7) {
//       // If more than a week ago, show the date
//       return DateFormat.MMMd().format(dateTime);
//     } else if (difference.inDays > 0) {
//       // If more than a day ago but less than a week, show the day name
//       return DateFormat.E().format(dateTime);
//     } else {
//       // If today, show the time
//       return DateFormat.jm().format(dateTime);
//     }
//   }
// }