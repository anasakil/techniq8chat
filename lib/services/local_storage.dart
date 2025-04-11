// services/local_storage.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techniq8chat/models/user_model.dart';
import '../models/message.dart';
import '../models/conversation.dart';

class LocalStorage {
  // Keys for SharedPreferences
  static const String _conversationsKey = 'conversations';
  static const String _messagesPrefix = 'messages_';
  static const String _currentUserKey = 'current_user';

  // Get the current user
  Future<User?> getCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userData = prefs.getString(_currentUserKey);
    if (userData == null) return null;
    
    try {
      return User.fromJson(json.decode(userData));
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
    final prefs = await SharedPreferences.getInstance();
    final conversationsData = prefs.getString(_conversationsKey);
    
    if (conversationsData == null) return [];
    
    try {
      final List<dynamic> decoded = json.decode(conversationsData);
      return decoded.map((item) => Conversation.fromJson(item)).toList();
    } catch (e) {
      print('Error getting conversations: $e');
      return [];
    }
  }

  // Save conversations
  Future<void> saveConversations(List<Conversation> conversations) async {
    final prefs = await SharedPreferences.getInstance();
    final data = conversations.map((c) => c.toJson()).toList();
    await prefs.setString(_conversationsKey, json.encode(data));
  }

  // Add or update a conversation
  Future<void> upsertConversation(Conversation conversation) async {
    final conversations = await getConversations();
    final index = conversations.indexWhere((c) => c.id == conversation.id);
    
    if (index >= 0) {
      conversations[index] = conversation;
    } else {
      conversations.add(conversation);
    }
    
    // Sort conversations by latest message
    conversations.sort((a, b) {
      final aTime = a.lastMessageTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = b.lastMessageTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime); // Most recent first
    });
    
    await saveConversations(conversations);
  }

  // Update conversation based on a message
  Future<void> updateConversationFromMessage(Message message) async {
    final currentUser = await getCurrentUser();
    if (currentUser == null) return;
    
    // Determine the other user ID (conversation ID)
    final conversationId = message.isSent ? message.receiverId : message.senderId;
    
    // Find existing conversation or create new one
    final conversations = await getConversations();
    final index = conversations.indexWhere((c) => c.id == conversationId);
    
    if (index >= 0) {
      // Update existing conversation
      conversations[index] = conversations[index].copyWith(
        lastMessage: message.content,
        lastMessageTime: message.createdAt,
        unreadCount: message.isSent 
            ? conversations[index].unreadCount 
            : conversations[index].unreadCount + 1,
      );
    } else {
      // Create a placeholder conversation until we get user details
      conversations.add(Conversation(
        id: conversationId,
        name: 'User', // Placeholder
        lastMessage: message.content,
        lastMessageTime: message.createdAt,
        status: 'offline',
        unreadCount: message.isSent ? 0 : 1,
      ));
    }
    
    // Sort conversations by latest message
    conversations.sort((a, b) {
      final aTime = a.lastMessageTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = b.lastMessageTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime); // Most recent first
    });
    
    await saveConversations(conversations);
  }

  // Delete a conversation
  Future<void> deleteConversation(String conversationId) async {
    final conversations = await getConversations();
    conversations.removeWhere((c) => c.id == conversationId);
    await saveConversations(conversations);
    
    // Also delete messages for this conversation
    await deleteMessages(conversationId);
  }

  // Mark a conversation as read
  Future<void> markConversationAsRead(String conversationId) async {
    final conversations = await getConversations();
    final index = conversations.indexWhere((c) => c.id == conversationId);
    
    if (index >= 0) {
      conversations[index] = conversations[index].copyWith(unreadCount: 0);
      await saveConversations(conversations);
    }
  }

  // Get messages key for a conversation
  String _getMessagesKey(String conversationId) {
    return '$_messagesPrefix$conversationId';
  }

  // Get messages for a conversation
  Future<List<Message>> getMessages(String conversationId) async {
    final currentUser = await getCurrentUser();
    if (currentUser == null) return [];
    
    final prefs = await SharedPreferences.getInstance();
    final messagesData = prefs.getString(_getMessagesKey(conversationId));
    
    if (messagesData == null) return [];
    
    try {
      final List<dynamic> decoded = json.decode(messagesData);
      return decoded
          .map((item) => Message.fromJson(item, currentUser.id))
          .toList();
    } catch (e) {
      print('Error getting messages: $e');
      return [];
    }
  }

  // Save messages for a conversation
  Future<void> saveMessages(String conversationId, List<Message> messages) async {
    final prefs = await SharedPreferences.getInstance();
    final data = messages.map((m) => m.toJson()).toList();
    await prefs.setString(_getMessagesKey(conversationId), json.encode(data));
  }

  // Save a single message
  Future<void> saveMessage(Message message) async {
    final currentUser = await getCurrentUser();
    if (currentUser == null) return;
    
    // Determine the conversation ID based on the other user
    final conversationId = message.isSent ? message.receiverId : message.senderId;
    
    // Get existing messages
    final messages = await getMessages(conversationId);
    
    // Check if message already exists
    final existingIndex = messages.indexWhere((m) => m.id == message.id);
    if (existingIndex >= 0) {
      // Update existing message
      messages[existingIndex] = message;
    } else {
      // Add new message
      messages.add(message);
      
      // Sort messages by timestamp
      messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }
    
    // Save messages
    await saveMessages(conversationId, messages);
    
    // Update conversation with last message
    await updateConversationFromMessage(message);
  }

  // Update a message's status
  Future<void> updateMessageStatus(String messageId, String status) async {
    final currentUser = await getCurrentUser();
    if (currentUser == null) return;
    
    // We need to find which conversation this message belongs to
    final conversations = await getConversations();
    
    for (final conversation in conversations) {
      final messages = await getMessages(conversation.id);
      final messageIndex = messages.indexWhere((m) => m.id == messageId);
      
      if (messageIndex >= 0) {
        // Update the message
        messages[messageIndex] = messages[messageIndex].copyWith(status: status);
        await saveMessages(conversation.id, messages);
        break;
      }
    }
  }

  // Replace a temporary message with a real one
  Future<void> replaceTempMessage(String tempId, Message realMessage) async {
    final currentUser = await getCurrentUser();
    if (currentUser == null) return;
    
    // Determine the conversation ID
    final conversationId = realMessage.isSent ? realMessage.receiverId : realMessage.senderId;
    
    // Get existing messages
    final messages = await getMessages(conversationId);
    
    // Find and replace the temp message
    final tempIndex = messages.indexWhere((m) => m.id == tempId);
    if (tempIndex >= 0) {
      messages[tempIndex] = realMessage;
      await saveMessages(conversationId, messages);
      
      // Also update conversation last message if needed
      if (tempIndex == messages.length - 1) {
        await updateConversationFromMessage(realMessage);
      }
    }
  }

  // Delete messages for a conversation
  Future<void> deleteMessages(String conversationId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_getMessagesKey(conversationId));
  }

  // Clear all storage (for logout)
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    
    for (final key in keys) {
      if (key == _conversationsKey || key.startsWith(_messagesPrefix)) {
        await prefs.remove(key);
      }
    }
    
    await clearCurrentUser();
  }
}