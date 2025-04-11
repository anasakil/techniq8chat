import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techniq8chat/controller/auth_provider.dart';

class AuthMiddleware {
  // Handle navigation based on authentication status
  static Future<void> handleAuthNavigation(
    BuildContext context, {
    required Function(BuildContext) onAuthenticated,
    required Function(BuildContext) onUnauthenticated,
  }) async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');

      if (token != null) {
        // Check if user profile is loaded
        if (authProvider.currentUser == null) {
          // Try to load user profile
          await authProvider.checkLoginStatus();
        }

        // If user is logged in, call onAuthenticated
        if (authProvider.isLoggedIn) {
          onAuthenticated(context);
          return;
        }
      }

      // If we reach here, user is not authenticated
      onUnauthenticated(context);
    } catch (e) {
      print('Auth middleware error: $e');
      // In case of error, assume user is not authenticated
      onUnauthenticated(context);
    }
  }
}