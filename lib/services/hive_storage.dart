// services/hive_storage.dart
import 'dart:convert';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/message.dart';
import '../models/conversation.dart';
import '../models/user_model.dart';

class HiveStorage {
  // Box names
  static const String messagesBoxName = 'messages';
  static const String conversationsBoxName = 'conversations';
  static const String _currentUserKey = 'current_user';
  
  // Get message box
  Box<Map> _getMessagesBox() {
    return Hive.box<Map>(messagesBoxName);
  }
  
  // Get conversations box
  Box<Map> _getConversationsBox() {
    return Hive.box<Map>(conversationsBoxName);
  }
  
  // Initialize Hive
  static Future<void> initialize() async {
    try {
      await Hive.initFlutter();
      
      // Open boxes if not already open
      if (!Hive.isBoxOpen(messagesBoxName)) {
        await Hive.openBox<Map>(messagesBoxName);
      }
      
      if (!Hive.isBoxOpen(conversationsBoxName)) {
        await Hive.openBox<Map>(conversationsBoxName);
      }
      
      print('Hive storage initialized successfully');
    } catch (e) {
      print('Error initializing Hive: $e');
    }
  }
  
  // Get the current user
 Future<User?> getCurrentUser() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final userData = prefs.getString(_currentUserKey);
    
    if (userData == null) {
      print('No user data found in SharedPreferences');
      return null;
    }
    
    final user = User.fromJson(json.decode(userData));
    print('Successfully retrieved current user: ${user.id}');
    return user;
  } catch (e) {
    print('Error getting current user: $e');
    return null;
  }
}

  // Save the current user
  Future<void> saveCurrentUser(User user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_currentUserKey, json.encode(user.toJson()));
  }

  // Clear the current user (for logout)
  Future<void> clearCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_currentUserKey);
  }

  // Get conversations
 Future<List<Conversation>> getConversations() async {
  try {
    final box = _getConversationsBox();
    final List<Conversation> conversations = [];
    
    // Debug info
    print('Retrieving conversations: ${box.length} entries in box');
    
    // Convert all values to Conversation objects
    for (var entry in box.values) {
      if (entry is Map) {
        try {
          final conversation = Conversation.fromJson(Map<String, dynamic>.from(entry));
          print('Retrieved conversation: ${conversation.id}, last message: ${conversation.lastMessage}, time: ${conversation.lastMessageTime}');
          conversations.add(conversation);
        } catch (e) {
          print('Error converting conversation: $e');
        }
      }
    }
    
    // Sort conversations by latest message timestamp (most recent first)
    conversations.sort((a, b) {
      if (a.lastMessageTime == null && b.lastMessageTime == null) {
        return 0;
      } else if (a.lastMessageTime == null) {
        return 1; // null timestamps go to the end
      } else if (b.lastMessageTime == null) {
        return -1; // null timestamps go to the end
      } else {
        return b.lastMessageTime!.compareTo(a.lastMessageTime!); // Most recent first
      }
    });
    
    print('Retrieved ${conversations.length} conversations from Hive, sorted by most recent');
    return conversations;
  } catch (e) {
    print('Error getting conversations: $e');
    return [];
  }
}

  // Save conversations
  Future<void> saveConversations(List<Conversation> conversations) async {
    final box = _getConversationsBox();
    await box.clear();
    
    for (final conversation in conversations) {
      await box.put(conversation.id, conversation.toJson());
    }
    
    print('Saved ${conversations.length} conversations to Hive');
  }

  // Add or update a conversation
  Future<void> upsertConversation(Conversation conversation) async {
    final box = _getConversationsBox();
    await box.put(conversation.id, conversation.toJson());
    print('Upserted conversation: ${conversation.id}');
  }

 // This is an enhanced version of the updateConversationFromMessage method
// to be added to your services/hive_storage.dart file
// Updated method to add to hive_storage.dart
Future<void> updateConversationFromMessage(Message message) async {
  final currentUser = await getCurrentUser();
  if (currentUser == null) {
    print('Cannot update conversation: No current user found');
    return;
  }
  
  // Determine the other user ID (conversation ID)
  final conversationId = message.isSent ? message.receiverId : message.senderId;
  
  print('HiveStorage: Updating conversation for ID: $conversationId with message: "${message.content}"');
  
  // Get the conversations box
  final box = _getConversationsBox();
  
  // Check if conversation exists
  final conversationJson = box.get(conversationId);
  
  if (conversationJson != null) {
    // Update existing conversation
    try {
      final conversation = Conversation.fromJson(Map<String, dynamic>.from(conversationJson));
      
      // Only increment unread count for incoming messages that aren't from current user
      int newUnreadCount = conversation.unreadCount;
      if (!message.isSent && message.senderId != currentUser.id) {
        newUnreadCount += 1;
      }
      
      // Create updated conversation with new message info
      final updatedConversation = conversation.copyWith(
        lastMessage: message.content,
        lastMessageTime: message.createdAt,
        unreadCount: newUnreadCount,
      );
      
      // Save the updated conversation
      await box.put(conversationId, updatedConversation.toJson());
      print('HiveStorage: Updated conversation: $conversationId with last message: "${message.content}", time: ${message.createdAt}');
    } catch (e) {
      print('HiveStorage: Error updating conversation: $e');
    }
  } else {
    // Create a placeholder conversation until we get user details
    print('HiveStorage: Creating new conversation from message for: $conversationId');
    final newConversation = Conversation(
      id: conversationId,
      name: message.isSent ? 'User' : message.senderId, // Placeholder
      lastMessage: message.content,
      lastMessageTime: message.createdAt,
      status: 'offline',
      unreadCount: message.isSent ? 0 : 1,
    );
    
    await box.put(conversationId, newConversation.toJson());
    print('HiveStorage: Created new conversation: $conversationId with last message: "${message.content}"');
  }
}
  // Delete a conversation
  Future<void> deleteConversation(String conversationId) async {
    final conversationsBox = _getConversationsBox();
    await conversationsBox.delete(conversationId);
    
    // Also delete messages for this conversation
    await deleteMessages(conversationId);
    print('Deleted conversation: $conversationId');
  }

  // Enhanced markConversationAsRead for hive_storage.dart
Future<void> markConversationAsRead(String conversationId) async {
  print('HiveStorage: Marking conversation as read: $conversationId');
  final box = _getConversationsBox();
  final conversationJson = box.get(conversationId);
  
  if (conversationJson != null) {
    try {
      final conversation = Conversation.fromJson(Map<String, dynamic>.from(conversationJson));
      
      // Only update if there are unread messages
      if (conversation.unreadCount > 0) {
        final updatedConversation = conversation.copyWith(unreadCount: 0);
        
        await box.put(conversationId, updatedConversation.toJson());
        print('HiveStorage: Successfully marked conversation as read: ${conversationId}');
      } else {
        print('HiveStorage: Conversation already marked as read: ${conversationId}');
      }
    } catch (e) {
      print('HiveStorage: Error marking conversation as read: $e');
    }
  } else {
    print('HiveStorage: Conversation not found: $conversationId');
  }
  
  // Get messages for this conversation to mark as read
  final currentUser = await getCurrentUser();
  if (currentUser != null) {
    // Also mark the actual messages as read
    final messagesBox = _getMessagesBox();
    
    for (var key in messagesBox.keys) {
      final messageData = messagesBox.get(key);
      
      if (messageData != null) {
        try {
          final senderId = messageData['sender'] is Map 
              ? messageData['sender']['_id'] 
              : messageData['sender'];
          
          // Is this a message from the conversation partner?
          if (senderId == conversationId) {
            // Update message status to read if needed
            if (messageData['status'] != 'read') {
              messageData['status'] = 'read';
              await messagesBox.put(key, messageData);
            }
          }
        } catch (e) {
          print('Error updating message read status: $e');
        }
      }
    }
  }
}
  // Get messages with fallback to direct currentUser parameter
Future<List<Message>> getMessages(String conversationId, {User? directUser}) async {
  // Try to get current user, with fallback to directUser parameter
  User? currentUser = directUser;
  if (currentUser == null) {
    currentUser = await getCurrentUser();
  }
  
  if (currentUser == null) {
    print('Cannot get messages: No current user found');
    return [];
  }
  
  try {
    final box = _getMessagesBox();
    final List<Message> allMessages = [];
    
    // Debug message to track execution
    print('Retrieving messages for conversation: $conversationId');
    print('Current user ID: ${currentUser.id}');
    
    // First, let's check what messages we actually have in the box
    print('Total messages in storage: ${box.length}');
    
    // Look through all keys in the messages box
    for (var key in box.keys) {
      final messageData = box.get(key);
      
      if (messageData != null) {
        try {
          final Map<String, dynamic> messageMap = Map<String, dynamic>.from(messageData);
          
          // Get sender and receiver from message data
          final senderId = messageMap['sender'] is Map 
              ? messageMap['sender']['_id'] 
              : messageMap['sender'];
          final receiverId = messageMap['receiver'] is Map 
              ? messageMap['receiver']['_id'] 
              : messageMap['receiver'];
          
          // Check if this message belongs to the current conversation
          bool isRelevantMessage = 
              (senderId == currentUser.id && receiverId == conversationId) ||
              (receiverId == currentUser.id && senderId == conversationId);
              
          if (isRelevantMessage) {
            final message = Message.fromJson(messageMap, currentUser.id);
            allMessages.add(message);
            print('Added message to result: ${message.id}, content: ${message.content}');
          }
        } catch (e) {
          print('Error converting message data: $e');
        }
      }
    }
    
    // Sort messages by time
    allMessages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    
    print('Retrieved ${allMessages.length} messages for conversation: $conversationId');
    if (allMessages.isNotEmpty) {
      print('First message: ${allMessages.first.content}');
      print('Last message: ${allMessages.last.content}');
    }
    
    return allMessages;
  } catch (e) {
    print('Error getting messages: $e');
    return [];
  }
}

  // Save a single message
  Future<void> saveMessage(Message message) async {
    try {
      final box = _getMessagesBox();
      
      // Generate a unique key for the message that includes conversation context
      final key = '${message.isSent ? message.receiverId : message.senderId}:${message.id}';
      
      // Store the message in the box
      await box.put(key, message.toJson());
      
      print('Successfully saved message to Hive: ${message.id}, content: ${message.content}');
      
      // Update conversation for this message
      await updateConversationFromMessage(message);
    } catch (e) {
      print('Error saving message: $e');
    }
  }

  // Update a message's status
  Future<void> updateMessageStatus(String messageId, String status) async {
    final box = _getMessagesBox();
    
    // We need to search all messages to find this one
    for (var key in box.keys) {
      final messageJson = box.get(key);
      
      if (messageJson != null && messageJson['_id'] == messageId) {
        try {
          // Found the message, update its status
          messageJson['status'] = status;
          await box.put(key, messageJson);
          print('Updated message status to $status: $messageId');
          break;
        } catch (e) {
          print('Error updating message status: $e');
        }
      }
    }
  }

  // Replace a temporary message with a real one
  Future<void> replaceTempMessage(String tempId, Message realMessage) async {
    final box = _getMessagesBox();
    
    // Find temp message
    String? tempKey;
    for (var key in box.keys) {
      final messageJson = box.get(key);
      if (messageJson != null && messageJson['_id'] == tempId) {
        tempKey = key.toString();
        break;
      }
    }
    
    if (tempKey != null) {
      // Delete temp message
      await box.delete(tempKey);
      
      // Save real message
      final newKey = '${realMessage.isSent ? realMessage.receiverId : realMessage.senderId}:${realMessage.id}';
      
      await box.put(newKey, realMessage.toJson());
      print('Replaced temp message $tempId with real message: ${realMessage.id}');
      
      // Update conversation
      await updateConversationFromMessage(realMessage);
    }
  }

  // Delete messages for a conversation
  Future<void> deleteMessages(String conversationId) async {
    final box = _getMessagesBox();
    
    // Find all message keys for this conversation
    final keysToDelete = <dynamic>[];
    
    for (var key in box.keys) {
      if (key.toString().startsWith('$conversationId:')) {
        keysToDelete.add(key);
      }
    }
    
    // Delete all found messages
    for (var key in keysToDelete) {
      await box.delete(key);
    }
    
    print('Deleted ${keysToDelete.length} messages for conversation: $conversationId');
  }

  // Clear all storage (for logout)
  Future<void> clearAll() async {
    try {
      final messagesBox = _getMessagesBox();
      final conversationsBox = _getConversationsBox();
      
      await messagesBox.clear();
      await conversationsBox.clear();
      await clearCurrentUser();
      
      print('Cleared all storage data');
    } catch (e) {
      print('Error clearing storage: $e');
    }
  }
  
  // Debug method to print all stored data
  void debugPrintAllData() {
    try {
      final messagesBox = _getMessagesBox();
      final conversationsBox = _getConversationsBox();
      
      print('===== DEBUG: ALL HIVE DATA =====');
      print('Conversations: ${conversationsBox.length}');
      
      for (var key in conversationsBox.keys) {
        final conversation = conversationsBox.get(key);
        print('Conversation: $key, ${conversation?['name']}, Last msg: ${conversation?['lastMessage']}');
      }
      
      print('Messages: ${messagesBox.length}');
      
      // Print first 5 messages details
      int count = 0;
      for (var key in messagesBox.keys) {
        if (count < 5) {
          final message = messagesBox.get(key);
          print('Message key: $key');
          print('Message data: ${message?['_id']}, Content: ${message?['content']}');
          count++;
        } else {
          break;
        }
      }
      
      print('=================================');
    } catch (e) {
      print('Error in debugPrintAllData: $e');
    }
  }
}