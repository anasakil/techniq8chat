// main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:techniq8chat/screens/welcome_screen.dart';
import 'package:techniq8chat/screens/bottom_navigation_screen.dart';
import 'package:techniq8chat/screens/agora_test_screen.dart'; // Import for Agora test
import 'package:techniq8chat/services/auth_service.dart';
import 'package:techniq8chat/services/hive_storage.dart';
import 'package:techniq8chat/services/call_handler_service.dart'; // Import call handler service
import 'screens/splash_screen.dart';

void main() async {
  // Ensure Flutter is initialized
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Hive
  await HiveStorage.initialize();
  
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // Key for Navigator to access context
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  
  @override
  void initState() {
    super.initState();
    // Initialize services after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeServices();
    });
  }
  
  Future<void> _initializeServices() async {
    try {
      // Get context from navigator key
      final context = navigatorKey.currentContext;
      if (context == null) return;
      
      // Get auth service
      final authService = Provider.of<AuthService>(context, listen: false);
      
      // Initialize call handler service
      final callHandlerService = CallHandlerService();
      await callHandlerService.initialize(context, authService);
    } catch (e) {
      print('Error initializing services: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        Provider<HiveStorage>(create: (_) => HiveStorage()),
      ],
      child: MaterialApp(
        title: 'Techniq8Chat',
        navigatorKey: navigatorKey, // Add navigator key
        theme: ThemeData(
          primaryColor: const Color(0xFF2A64F6),
          primarySwatch: Colors.blue,
          visualDensity: VisualDensity.adaptivePlatformDensity,
          fontFamily: 'Roboto',
          appBarTheme: AppBarTheme(
            backgroundColor: Colors.white,
            elevation: 0,
          ),
        ),
        debugShowCheckedModeBanner: false,
        home: SplashScreen(),
        routes: {
          '/agora_test': (context) => AgoraTestScreen(), // Add route for Agora test screen
        },
      ),
    );
  }
}