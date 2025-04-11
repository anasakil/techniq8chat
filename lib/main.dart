import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techniq8chat/controller/auth_provider.dart';
import 'package:techniq8chat/screens/MessagesPage.dart';
import 'package:techniq8chat/services/socket_service.dart';
import 'screens/welcome_screen.dart';

void main() async {
  // Ensure Flutter is initialized
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize app services
  await initializeAppServices();
  
  runApp(
    // Wrap the entire app with the AuthProvider
    ChangeNotifierProvider(
      create: (_) => AuthProvider(),
      child: const MyApp(),
    ),
  );
}

// Initialize app services like shared preferences and other startup tasks
Future<void> initializeAppServices() async {
  try {
    // Initialize SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    
    // Try to initialize socket if user is logged in
    final token = prefs.getString('token');
    final userId = prefs.getString('userId');
    
    if (token != null && userId != null) {
      // Set up socket connection asynchronously
      SocketService.instance.init(userId).catchError((e) {
        print('Error initializing socket at startup: $e');
        // Socket will retry automatically
      });
    }
  } catch (e) {
    print('Error initializing app services: $e');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Techniq8chat',
      theme: ThemeData(
        primarySwatch: Colors.deepOrange,
        scaffoldBackgroundColor: Colors.white,
      ),
      debugShowCheckedModeBanner: false,
      home: FutureBuilder(
        // Initialize auth check when app starts
        future: Provider.of<AuthProvider>(context, listen: false).checkLoginStatus(),
        builder: (context, snapshot) {
          // Show loading indicator while checking auth status
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(
                  color: Colors.deepOrange,
                ),
              ),
            );
          }
          
          // After auth check completes, go to the welcome screen
          // The welcome screen will decide whether to redirect to MessagesPage or stay
          return WelcomeScreen();
        },
      ),
    );
  }
}