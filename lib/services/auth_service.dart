// services/auth_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techniq8chat/models/user_model.dart';

class AuthService with ChangeNotifier {
  final String baseUrl = 'http://51.178.138.50:4400';
  User? _currentUser;

  User? get currentUser => _currentUser;

  // Login user
  Future<User> login(String email, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'email': email,
        'password': password,
      }),
    );

    if (response.statusCode == 200) {
      final userData = json.decode(response.body);
      final user = User.fromJson(userData);
      
      // Save user data and token
      _currentUser = user;
      await _saveUserData(user);
      notifyListeners();
      
      return user;
    } else {
      final error = json.decode(response.body);
      throw Exception(error['message'] ?? 'Login failed');
    }
  }

  // Register user with key
  Future<User> register(String username, String email, String password, String key) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'username': username,
        'email': email,
        'password': password,
        'key': key, // Add the registration key
      }),
    );

    if (response.statusCode == 201) {
      final userData = json.decode(response.body);
      final user = User.fromJson(userData);
      
      // Save user data and token
      _currentUser = user;
      await _saveUserData(user);
      notifyListeners();
      
      return user;
    } else {
      final error = json.decode(response.body);
      throw Exception(error['message'] ?? 'Registration failed');
    }
  }

  // Check if a key is valid
  Future<bool> checkKeyValidity(String key) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/check-key'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'key': key}),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['valid'] ?? false;
    }
    return false;
  }

  // Validate token and get user data
  Future<User?> validateToken(String token) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/users/me'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final userData = json.decode(response.body);
        // Add token to user data since it's not included in the response
        userData['token'] = token;
        
        final user = User.fromJson(userData);
        _currentUser = user;
        notifyListeners();
        return user;
      }
    } catch (e) {
      print('Token validation error: $e');
    }
    
    // Clear invalid token
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    
    return null;
  }

  // Logout user
  Future<void> logout() async {
    final token = _currentUser?.token;
    
    if (token != null) {
      try {
        await http.post(
          Uri.parse('$baseUrl/api/auth/logout'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
        );
      } catch (e) {
        print('Logout API error: $e');
      }
    }
    
    // Clear user data regardless of API response
    _currentUser = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('user_data');
    
    notifyListeners();
  }

  // Update user status
  Future<void> updateStatus(String status) async {
    if (_currentUser == null) return;
    
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/api/users/update-status'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${_currentUser!.token}',
        },
        body: json.encode({'status': status}),
      );

      if (response.statusCode == 200) {
        _currentUser = _currentUser!.copyWith(status: status);
        notifyListeners();
      }
    } catch (e) {
      print('Update status error: $e');
    }
  }

  // Save user data to SharedPreferences
  Future<void> _saveUserData(User user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', user.token);
    await prefs.setString('user_data', json.encode(user.toJson()));
  }

  // Load user data from SharedPreferences
  Future<void> loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final userData = prefs.getString('user_data');
    final token = prefs.getString('token');
    
    if (userData != null && token != null) {
      try {
        _currentUser = User.fromJson(json.decode(userData));
        notifyListeners();
      } catch (e) {
        print('Error loading user data: $e');
      }
    }
  }
}