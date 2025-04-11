import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techniq8chat/models/message.dart';
import 'package:techniq8chat/models/user_model.dart';
import 'package:techniq8chat/services/api_constants.dart';

class ChatService {
  // Headers for API requests
  Future<Map<String, String>> _getHeaders() async {
    Map<String, String> headers = {
      'Content-Type': 'application/json',
    };

    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('token');
    
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
      print('Token found and added to headers: ${token.substring(0, min(10, token.length))}...');
    } else {
      print('No token found in SharedPreferences');
    }
    
    return headers;
  }
  
  // Get messages between current user and another user
  Future<List<Message>> getMessagesByUser(String userId) async {
    try {
      print('Fetching messages with user: $userId');
      print('URL: ${ApiConstants.messagesByUser}/$userId');
      
      final headers = await _getHeaders();
      print('Headers: $headers');
      
      final response = await http.get(
        Uri.parse('${ApiConstants.messagesByUser}/$userId'),
        headers: headers,
      );

      print('Response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<Message> messages = [];
        
        if (data['messages'] != null) {
          print('Message count: ${data['messages'].length}');
          for (var messageData in data['messages']) {
            messages.add(Message.fromJson(messageData));
          }
        } else {
          print('No messages found in response');
        }
        
        return messages;
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Failed to get messages');
      }
    } catch (e) {
      print('Error getting messages: $e');
      throw Exception('Error getting messages: $e');
    }
  }
  
  // Send a message to a user
  Future<Message> sendMessage(String receiverId, String content, {String contentType = 'text'}) async {
    try {
      final headers = await _getHeaders();
      print('Sending message to: $receiverId with content: $content');
      
      final response = await http.post(
        Uri.parse(ApiConstants.sendMessage),
        headers: headers,
        body: jsonEncode({
          'receiverId': receiverId,
          'content': content,
          'contentType': contentType,
        }),
      );

      print('Send message response status: ${response.statusCode}');
      
      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return Message.fromJson(data);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Failed to send message');
      }
    } catch (e) {
      print('Error sending message: $e');
      throw Exception('Error sending message: $e');
    }
  }
  
  // Mark conversation as read
  Future<void> markConversationAsRead(String userId) async {
    try {
      // First check if there's a conversation ID
      final conversationId = await _getConversationId(userId);
      
      if (conversationId == null) {
        // No conversation yet, so nothing to mark as read
        return;
      }
      
      final headers = await _getHeaders();
      final response = await http.put(
        Uri.parse('${ApiConstants.conversationsApi}/$conversationId/read'),
        headers: headers,
      );
      
      print('Mark as read response: ${response.statusCode}');
      
      if (response.statusCode != 200) {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Failed to mark conversation as read');
      }
    } catch (e) {
      print('Error marking conversation as read: $e');
      throw Exception('Error marking conversation as read: $e');
    }
  }
  
  // Get conversation ID for two users
  Future<String?> _getConversationId(String otherUserId) async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse(ApiConstants.conversationsApi),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final List<dynamic> conversations = jsonDecode(response.body);
        
        // Find conversation with the other user
        for (var conv in conversations) {
          final List<dynamic> participants = conv['participants'];
          
          bool hasOtherUser = false;
          bool isOneOnOne = !conv['isGroup'] && participants.length == 2;
          
          if (isOneOnOne) {
            for (var participant in participants) {
              if (participant['_id'] == otherUserId) {
                hasOtherUser = true;
                break;
              }
            }
            
            if (hasOtherUser) {
              return conv['_id'];
            }
          }
        }
      }
      
      return null;
    } catch (e) {
      print('Error getting conversation ID: $e');
      return null;
    }
  }
  
  // Get all recent conversations
  Future<List<dynamic>> getConversations() async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse(ApiConstants.conversations),
        headers: headers,
      );

      print('Get conversations response: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final List<dynamic> conversationsData = jsonDecode(response.body);
        
        // Process the data to make it easier to use
        List<dynamic> processedConversations = [];
        
        for (var conversation in conversationsData) {
          // Find the other participant (for one-on-one chats)
          dynamic otherParticipant;
          if (conversation['participants'] is List && conversation['participants'].length > 0) {
            // Get current user from SharedPreferences to compare
            SharedPreferences prefs = await SharedPreferences.getInstance();
            String? currentUserId = prefs.getString('userId');
            
            for (var participant in conversation['participants']) {
              if (participant['_id'] != currentUserId) {
                otherParticipant = participant;
                break;
              }
            }
          }
          
          // If we found another participant, add conversation with their details
          if (otherParticipant != null) {
            processedConversations.add({
              '_id': conversation['_id'],
              'username': otherParticipant['username'],
              'profilePicture': otherParticipant['profilePicture'],
              'status': otherParticipant['status'] ?? 'offline',
              'lastMessage': conversation['lastMessage'],
              'unreadCount': conversation['unreadCount']?.toString(),
              'updatedAt': conversation['updatedAt'],
              'isGroup': conversation['isGroup'] ?? false,
              'participants': conversation['participants'],
            });
          }
        }
        
        return processedConversations;
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Failed to get conversations');
      }
    } catch (e) {
      print('Error getting conversations: $e');
      throw Exception('Error getting conversations: $e');
    }
  }
  
  // Create a new conversation
  Future<Map<String, dynamic>> createConversation(String otherUserId) async {
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse(ApiConstants.conversationsApi),
        headers: headers,
        body: jsonEncode({
          'participants': [otherUserId],
          'isGroup': false,
        }),
      );

      print('Create conversation response: ${response.statusCode}');
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Failed to create conversation');
      }
    } catch (e) {
      print('Error creating conversation: $e');
      throw Exception('Error creating conversation: $e');
    }
  }
  
  // Get all users
  Future<List<User>> getAllUsers() async {
    try {
      print('Fetching all users');
      
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse(ApiConstants.searchUsers),
        headers: headers,
      );

      print('Get all users response: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final List<dynamic> userData = jsonDecode(response.body);
        print('Found ${userData.length} users');
        return userData.map((data) => User.fromJson(data)).toList();
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Failed to get users');
      }
    } catch (e) {
      print('Error getting users: $e');
      throw Exception('Error getting users: $e');
    }
  }
  
  // Search users
  Future<List<User>> searchUsers(String query) async {
    try {
      print('Searching users with query: $query');
      
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('${ApiConstants.searchUsers}?query=$query'),
        headers: headers,
      );

      print('Search users response: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final List<dynamic> userData = jsonDecode(response.body);
        print('Found ${userData.length} users matching query');
        return userData.map((data) => User.fromJson(data)).toList();
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Failed to search users');
      }
    } catch (e) {
      print('Error searching users: $e');
      throw Exception('Error searching users: $e');
    }
  }
}