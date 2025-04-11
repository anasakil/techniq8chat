
class ApiConstants {
  // Base URL
  static const String baseUrl = 'http://192.168.100.76:4400/api';
  
  // Auth endpoints
  static const String login = '$baseUrl/auth/login';
  static const String register = '$baseUrl/auth/register';
  static const String logout = '$baseUrl/auth/logout';
  static const String profile = '$baseUrl/auth/profile';
  
  // User endpoints
  static const String users = '$baseUrl/users';
  static const String currentUser = '$baseUrl/users/me';
  static const String searchUsers = '$baseUrl/users/search';  
  static const String userContacts = '$baseUrl/users/contacts';
  
  // Message endpoints
  static const String sendMessage = '$baseUrl/messages/send';
  static const String messagesByUser = '$baseUrl/messages/user'; // Append /{userId}
  static const String conversations = '$baseUrl/messages/conversations';
  static const String unreadCount = '$baseUrl/messages/unread';
  
  // Conversation endpoints
  static const String conversationsApi = '$baseUrl/conversations';
  
  // Socket server URL
  static const String socketUrl = 'http://192.168.100.76:4400';

  
}