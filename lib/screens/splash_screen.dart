// screens/splash_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';
import 'bottom_navigation_screen.dart';
import 'welcome_screen.dart';

class SplashScreen extends StatefulWidget {
  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  
  @override
  void initState() {
    super.initState();
    
    // Set up animation
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 1200),
    );
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOut,
      ),
    );
    
    // Start animation immediately
    _animationController.forward();
    
    // Start login check after a delay
    _checkLogin();
  }
  
  Future<void> _checkLogin() async {
    try {
      // Small delay to show splash screen
      await Future.delayed(Duration(milliseconds: 2000));
      
      // Check for stored token
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      
      if (token != null) {
        // Try to validate the token
        final authService = Provider.of<AuthService>(context, listen: false);
        await authService.loadUserData();
        
        if (authService.currentUser != null) {
          // Valid token, go to bottom navigation screen instead of just conversations
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => BottomNavigationScreen()),
          );
          return;
        }
      }
      
      // No valid token, go to welcome screen
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => WelcomeScreen()),
      );
    } catch (e) {
      print('Error during login check: $e');
      
      // In case of error, go to welcome screen
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => WelcomeScreen()),
      );
    }
  }
  
  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // App logo
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: const Color(0xFF2A64F6).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.chat_bubble_outline,
                  size: 60,
                  color: const Color(0xFF2A64F6),
                ),
              ),
              SizedBox(height: 28),
              
              // App name
              Text(
                'TQCHAT',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF2A64F6),
                  letterSpacing: 0.5,
                ),
              ),
              SizedBox(height: 16),
              
              // Tagline
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: Text(
                  'Connect with friends and colleagues in real-time',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                    height: 1.4,
                  ),
                ),
              ),
              
              SizedBox(height: 60),
              
              // Loading indicator
              SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                  color: const Color(0xFF2A64F6),
                  strokeWidth: 3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}