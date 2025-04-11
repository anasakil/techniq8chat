// import 'dart:async';
// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';
// import 'package:techniq8chat/controller/auth_provider.dart';
// import 'package:techniq8chat/models/message.dart';
// import 'package:techniq8chat/models/user_model.dart';
// import 'package:techniq8chat/services/chat_service.dart';
// import 'package:techniq8chat/services/socket_service.dart';
// import 'package:intl/intl.dart';

// class ChatDetailsPage extends StatefulWidget {
//   final User user;

//   const ChatDetailsPage({Key? key, required this.user}) : super(key: key);

//   @override
//   _ChatDetailsPageState createState() => _ChatDetailsPageState();
// }

// class _ChatDetailsPageState extends State<ChatDetailsPage> {
//   final TextEditingController _messageController = TextEditingController();
//   final ScrollController _scrollController = ScrollController();
//   final ChatService _chatService = ChatService();
//   final List<Message> _messages = [];
//   bool _isLoading = true;
//   bool _isSending = false;
//   String _error = '';
//   Timer? _typingTimer;
//   bool _isTyping = false;
//   StreamSubscription? _socketSubscription;
//   StreamSubscription? _statusSubscription;
//   StreamSubscription? _typingSubscription;

//   @override
//   void initState() {
//     super.initState();
//     _loadMessages();
//     _initSocketListeners();
//   }

//   @override
//   void dispose() {
//     _messageController.dispose();
//     _scrollController.dispose();
//     _socketSubscription?.cancel();
//     _statusSubscription?.cancel();
//     _typingSubscription?.cancel();
//     _typingTimer?.cancel();
//     super.dispose();
//   }

//   void _initSocketListeners() {
//     // Cancel any existing subscription
//     _socketSubscription?.cancel();
//     _statusSubscription?.cancel();
//     _typingSubscription?.cancel();
    
//     print('Setting up socket listeners for user: ${widget.user.id}');
    
//     // Listen for new messages from this specific user
//     _socketSubscription = SocketService.instance.onMessageReceived(widget.user.id)
//         .listen((message) {
//       print('Message received from ${widget.user.username}: ${message.content}');
      
//       // Update message sender details with our known user
//       final updatedMessage = Message(
//         id: message.id,
//         conversationId: message.conversationId,
//         sender: widget.user,
//         content: message.content,
//         contentType: message.contentType,
//         fileUrl: message.fileUrl,
//         fileName: message.fileName,
//         fileSize: message.fileSize,
//         status: message.status,
//         readBy: message.readBy,
//         reactions: message.reactions,
//         forwardedFrom: message.forwardedFrom,
//         encrypted: message.encrypted,
//         createdAt: message.createdAt,
//       );
      
//       setState(() {
//         _messages.insert(0, updatedMessage);
//         _isTyping = false;
//       });
      
//       // Scroll to bottom
//       _scrollToBottom();
      
//       // Mark message as read
//       SocketService.instance.markMessageAsRead(message.id, message.sender.id);
//     });

//     // Listen for typing indicator
//     _typingSubscription = SocketService.instance.onUserTyping(widget.user.id).listen((senderId) {
//       print('User is typing: $senderId');
//       setState(() {
//         _isTyping = true;
//       });
//       // Hide typing indicator after 3 seconds
//       Timer(const Duration(seconds: 3), () {
//         if (mounted) {
//           setState(() {
//             _isTyping = false;
//           });
//         }
//       });
//     });
    
//     // Listen for status updates
//     _statusSubscription = SocketService.instance.onMessageStatusUpdated().listen((data) {
//       print('Message status update: ${data['messageId']} -> ${data['status']}');
      
//       // Find message and update its status
//       final messageIndex = _messages.indexWhere((msg) => msg.id == data['messageId']);
//       if (messageIndex != -1) {
//         setState(() {
//           final updatedMessage = Message(
//             id: _messages[messageIndex].id,
//             conversationId: _messages[messageIndex].conversationId,
//             sender: _messages[messageIndex].sender,
//             content: _messages[messageIndex].content,
//             contentType: _messages[messageIndex].contentType,
//             fileUrl: _messages[messageIndex].fileUrl,
//             fileName: _messages[messageIndex].fileName,
//             fileSize: _messages[messageIndex].fileSize,
//             status: data['status'],
//             readBy: _messages[messageIndex].readBy,
//             reactions: _messages[messageIndex].reactions,
//             forwardedFrom: _messages[messageIndex].forwardedFrom,
//             encrypted: _messages[messageIndex].encrypted,
//             createdAt: _messages[messageIndex].createdAt,
//           );
//           _messages[messageIndex] = updatedMessage;
//         });
//       }
//     });
    
//     // Request conversation history
//     SocketService.instance.requestConversationHistory(widget.user.id);
//   }

//   void _scrollToBottom() {
//     if (_scrollController.hasClients) {
//       _scrollController.animateTo(
//         0.0,
//         duration: const Duration(milliseconds: 300),
//         curve: Curves.easeOut,
//       );
//     }
//   }

//   Future<void> _loadMessages() async {
//     setState(() {
//       _isLoading = true;
//       _error = '';
//     });

//     try {
//       print('Loading messages for user: ${widget.user.id}');
//       final messages = await _chatService.getMessagesByUser(widget.user.id);
//       print('Loaded ${messages.length} messages');
      
//       setState(() {
//         _messages.clear();
//         _messages.addAll(messages);
//         _isLoading = false;
//       });
      
//       // Mark all unread messages as read
//       _chatService.markConversationAsRead(widget.user.id);
//     } catch (e) {
//       print('Error loading messages: $e');
//       setState(() {
//         _error = 'Failed to load messages: ${e.toString()}';
//         _isLoading = false;
//       });
//     }
//   }

//   Future<void> _sendMessage() async {
//     if (_messageController.text.trim().isEmpty) return;

//     final messageText = _messageController.text.trim();
//     _messageController.clear();

//     // Show user we're sending
//     setState(() {
//       _isSending = true;
//     });

//     try {
//       final authProvider = Provider.of<AuthProvider>(context, listen: false);
//       final currentUser = authProvider.currentUser;
//       if (currentUser == null) {
//         setState(() {
//           _error = 'User not logged in';
//           _isSending = false;
//         });
//         return;
//       }
      
//       // Create temporary message to display immediately
//       final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
//       final tempMessage = Message(
//         id: tempId,
//         conversationId: '',
//         sender: currentUser,
//         content: messageText,
//         contentType: 'text',
//         status: 'sending',
//         readBy: [],
//         reactions: [],
//         encrypted: true,
//         createdAt: DateTime.now(),
//       );

//       setState(() {
//         _messages.insert(0, tempMessage);
//       });
      
//       // Scroll to bottom
//       _scrollToBottom();

//       // First send via socket for real-time delivery
//       print('Sending message to ${widget.user.id} via socket: $messageText');
//       SocketService.instance.sendMessage(
//         widget.user.id,
//         messageText,
//         tempId,
//       );
      
//       // Then save to server via API
//       print('Sending message to server via API: $messageText');
//       try {
//         final sentMessage = await _chatService.sendMessage(
//           widget.user.id, 
//           messageText,
//         );

//         // Update message with server response
//         setState(() {
//           final index = _messages.indexWhere((m) => m.id == tempId);
//           if (index != -1) {
//             _messages[index] = sentMessage;
//           }
//         });
        
//         // Send message with the real ID via socket
//         if (tempId != sentMessage.id) {
//           SocketService.instance.sendMessage(
//             widget.user.id,
//             messageText,
//             sentMessage.id,
//           );
//         }
        
//         print('Message saved to server with ID: ${sentMessage.id}');
//       } catch (e) {
//         print('API error but message was sent via socket: $e');
//         // Just update status to sent since message was delivered via socket
//         setState(() {
//           final index = _messages.indexWhere((m) => m.id == tempId);
//           if (index != -1) {
//             _messages[index] = Message(
//               id: tempId,
//               conversationId: '',
//               sender: currentUser,
//               content: messageText,
//               contentType: 'text',
//               status: 'sent',
//               readBy: [],
//               reactions: [],
//               encrypted: true,
//               createdAt: DateTime.now(),
//             );
//           }
//         });
//       }
//     } catch (e) {
//       print('Error sending message: $e');
//       setState(() {
//         _error = 'Failed to send message: ${e.toString()}';
//       });
//     } finally {
//       setState(() {
//         _isSending = false;
//       });
//     }
//   }

//   void _onTyping() {
//     _typingTimer?.cancel();
//     SocketService.instance.sendTypingIndicator(widget.user.id);
//     _typingTimer = Timer(const Duration(seconds: 2), () {});
//   }

//   @override
//   Widget build(BuildContext context) {
//     final currentUser = Provider.of<AuthProvider>(context).currentUser;

//     return Scaffold(
//       appBar: AppBar(
//         elevation: 0,
//         backgroundColor: Colors.white,
//         leading: IconButton(
//           icon: const Icon(Icons.arrow_back, color: Colors.black),
//           onPressed: () => Navigator.pop(context),
//         ),
//         title: Row(
//           children: [
//             CircleAvatar(
//               backgroundColor: Colors.deepOrange,
//               child: Text(
//                 widget.user.username.substring(0, 1).toUpperCase(),
//                 style: const TextStyle(color: Colors.white),
//               ),
//             ),
//             const SizedBox(width: 10),
//             Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Text(
//                   widget.user.username,
//                   style: const TextStyle(
//                     color: Colors.black,
//                     fontWeight: FontWeight.bold,
//                   ),
//                 ),
//                 Text(
//                   widget.user.status,
//                   style: TextStyle(
//                     color: widget.user.status == 'online' 
//                         ? Colors.green 
//                         : Colors.grey,
//                     fontSize: 12,
//                   ),
//                 ),
//               ],
//             ),
//           ],
//         ),
//         actions: [
//           IconButton(
//             icon: const Icon(Icons.call, color: Colors.black),
//             onPressed: () {
//               // Implement call functionality
//             },
//           ),
//           IconButton(
//             icon: const Icon(Icons.more_vert, color: Colors.black),
//             onPressed: () {
//               // Show more options
//             },
//           ),
//         ],
//       ),
//       body: Column(
//         children: [
//           // Error message if any
//           if (_error.isNotEmpty)
//             Container(
//               padding: const EdgeInsets.all(8),
//               color: Colors.red.shade100,
//               width: double.infinity,
//               child: Row(
//                 children: [
//                   const Icon(Icons.error_outline, color: Colors.red),
//                   const SizedBox(width: 8),
//                   Expanded(
//                     child: Text(
//                       _error,
//                       style: const TextStyle(color: Colors.red),
//                     ),
//                   ),
//                   IconButton(
//                     icon: const Icon(Icons.close, color: Colors.red),
//                     onPressed: () => setState(() => _error = ''),
//                     iconSize: 16,
//                   ),
//                 ],
//               ),
//             ),
          
//           // Typing indicator
//           if (_isTyping)
//             Container(
//               padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
//               alignment: Alignment.centerLeft,
//               child: Text(
//                 '${widget.user.username} is typing...',
//                 style: TextStyle(
//                   color: Colors.grey[600],
//                   fontStyle: FontStyle.italic,
//                 ),
//               ),
//             ),
          
//           // Messages list
//           Expanded(
//             child: _isLoading
//                 ? const Center(child: CircularProgressIndicator())
//                 : _messages.isEmpty
//                     ? Center(
//                         child: Text(
//                           'No messages yet. Say hi to ${widget.user.username}!',
//                           style: TextStyle(color: Colors.grey[600]),
//                         ),
//                       )
//                     : ListView.builder(
//                         controller: _scrollController,
//                         reverse: true,
//                         padding: const EdgeInsets.all(10),
//                         itemCount: _messages.length,
//                         itemBuilder: (context, index) {
//                           final message = _messages[index];
//                           final isSent = message.sender.id == currentUser?.id;
                          
//                           return _buildMessageItem(message, isSent);
//                         },
//                       ),
//           ),
          
//           // Message input area
//           Container(
//             padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
//             decoration: BoxDecoration(
//               color: Colors.white,
//               boxShadow: [
//                 BoxShadow(
//                   offset: const Offset(0, -2),
//                   blurRadius: 4,
//                   color: Colors.black.withOpacity(0.1),
//                 ),
//               ],
//             ),
//             child: SafeArea(
//               child: Row(
//                 children: [
//                   IconButton(
//                     icon: const Icon(Icons.attach_file),
//                     color: Colors.grey[600],
//                     onPressed: () {
//                       // Implement file attachment
//                     },
//                   ),
//                   Expanded(
//                     child: TextField(
//                       controller: _messageController,
//                       onChanged: (_) => _onTyping(),
//                       decoration: InputDecoration(
//                         hintText: 'Type a message...',
//                         border: OutlineInputBorder(
//                           borderRadius: BorderRadius.circular(20),
//                           borderSide: BorderSide.none,
//                         ),
//                         filled: true,
//                         fillColor: Colors.grey[200],
//                         contentPadding: const EdgeInsets.symmetric(
//                           horizontal: 20,
//                           vertical: 10,
//                         ),
//                       ),
//                       maxLines: null,
//                       textInputAction: TextInputAction.send,
//                       onSubmitted: (_) => _sendMessage(),
//                     ),
//                   ),
//                   const SizedBox(width: 8),
//                   FloatingActionButton(
//                     onPressed: _isSending ? null : _sendMessage,
//                     backgroundColor: Colors.deepOrange,
//                     elevation: 0,
//                     mini: true,
//                     child: _isSending
//                         ? const SizedBox(
//                             width: 20,
//                             height: 20,
//                             child: CircularProgressIndicator(
//                               color: Colors.white,
//                               strokeWidth: 2,
//                             ),
//                           )
//                         : const Icon(Icons.send),
//                   ),
//                 ],
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildMessageItem(Message message, bool isMe) {
//     // Format timestamp
//     final time = DateFormat('h:mm a').format(message.createdAt);
    
//     return Padding(
//       padding: const EdgeInsets.symmetric(vertical: 5),
//       child: Row(
//         mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
//         crossAxisAlignment: CrossAxisAlignment.end,
//         children: [
//           if (!isMe) ...[
//             CircleAvatar(
//               radius: 16,
//               backgroundColor: Colors.grey[300],
//               child: Text(
//                 message.sender.username.substring(0, 1).toUpperCase(),
//                 style: const TextStyle(fontSize: 14),
//               ),
//             ),
//             const SizedBox(width: 8),
//           ],
          
//           Container(
//             constraints: BoxConstraints(
//               maxWidth: MediaQuery.of(context).size.width * 0.7,
//             ),
//             padding: const EdgeInsets.all(12),
//             decoration: BoxDecoration(
//               color: isMe ? Colors.deepOrange.shade50 : Colors.grey[200],
//               borderRadius: BorderRadius.circular(20).copyWith(
//                 bottomRight: isMe ? const Radius.circular(0) : null,
//                 bottomLeft: !isMe ? const Radius.circular(0) : null,
//               ),
//             ),
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Text(
//                   message.content,
//                   style: const TextStyle(fontSize: 16),
//                 ),
//                 const SizedBox(height: 5),
//                 Row(
//                   mainAxisSize: MainAxisSize.min,
//                   children: [
//                     Text(
//                       time,
//                       style: TextStyle(
//                         fontSize: 12,
//                         color: Colors.grey[600],
//                       ),
//                     ),
//                     if (isMe) ...[
//                       const SizedBox(width: 5),
//                       Icon(
//                         message.status == 'sending'
//                             ? Icons.access_time
//                             : message.status == 'sent'
//                                 ? Icons.check
//                                 : message.status == 'delivered'
//                                     ? Icons.done_all
//                                     : Icons.done_all,
//                         size: 14,
//                         color: message.status == 'read'
//                             ? Colors.blue
//                             : Colors.grey[600],
//                       ),
//                     ],
//                   ],
//                 ),
//               ],
//             ),
//           ),
          
//           if (isMe) const SizedBox(width: 24), // Space for symmetry
//         ],
//       ),
//     );
//   }
// }