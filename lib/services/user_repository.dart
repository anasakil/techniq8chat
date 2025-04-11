// services/user_repository.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:techniq8chat/models/user_model.dart';

class UserRepository {
  final String baseUrl;
  final String token;
  
  UserRepository({required this.baseUrl, required this.token});

  // Get all users 
  Future<List<User>> getAllUsers() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/users/all'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> usersData = json.decode(response.body);
        return usersData.map((userData) => User.fromJson({
          ...userData,
          'token': '', // We don't need token for other users
        })).toList();
      } else {
        throw Exception('Failed to load users');
      }
    } catch (e) {
      print('Error getting all users: $e');
      return [];
    }
  }

  // Search users by username or email
  Future<List<User>> searchUsers(String query) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/users/search?query=$query'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> usersData = json.decode(response.body);
        return usersData.map((userData) => User.fromJson({
          ...userData,
          'token': '', // We don't need token for other users
        })).toList();
      } else {
        throw Exception('Failed to search users');
      }
    } catch (e) {
      print('Error searching users: $e');
      return [];
    }
  }

  // Get user by ID
  Future<User?> getUserById(String userId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/users/$userId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final userData = json.decode(response.body);
        return User.fromJson({
          ...userData,
          'token': '', // We don't need token for other users
        });
      } else {
        return null;
      }
    } catch (e) {
      print('Error getting user by ID: $e');
      return null;
    }
  }

  // Get user status
  Future<Map<String, dynamic>?> getUserStatus(String userId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/users/$userId/status'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        return null;
      }
    } catch (e) {
      print('Error getting user status: $e');
      return null;
    }
  }

  // Update current user's status
  Future<bool> updateStatus(String status) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/api/users/update-status'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({'status': status}),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Error updating status: $e');
      return false;
    }
  }

  // Get user contacts
  Future<List<User>> getUserContacts() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/users/contacts'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> contactsData = json.decode(response.body);
        return contactsData.map((userData) => User.fromJson({
          ...userData,
          'token': '', // We don't need token for other users
        })).toList();
      } else {
        throw Exception('Failed to load contacts');
      }
    } catch (e) {
      print('Error getting contacts: $e');
      return [];
    }
  }

  // Add user to contacts
  Future<bool> addContact(String userId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/users/contacts/$userId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      return response.statusCode == 201;
    } catch (e) {
      print('Error adding contact: $e');
      return false;
    }
  }

  // Remove user from contacts
  Future<bool> removeContact(String userId) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/api/users/contacts/$userId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Error removing contact: $e');
      return false;
    }
  }
}