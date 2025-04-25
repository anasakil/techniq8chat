// main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:techniq8chat/screens/welcome_screen.dart';
import 'package:techniq8chat/screens/bottom_navigation_screen.dart';
import 'package:techniq8chat/screens/splash_screen.dart';
import 'package:techniq8chat/services/auth_service.dart';
import 'package:techniq8chat/services/hive_storage.dart';
import 'package:techniq8chat/services/socket_service.dart';
import 'package:techniq8chat/services/call_service.dart';
import 'package:techniq8chat/services/standalone_call_handler.dart';
import 'package:permission_handler/permission_handler.dart';

void main() async {
  // Ensure Flutter is initialized
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Hive
  await HiveStorage.initialize();
  
  // Request necessary permissions
  await _requestPermissions();
  
  // Create standalone call handler
  final callHandler = StandaloneCallHandler();
  
  runApp(MyApp(callHandler: callHandler));
}

// Request permissions needed for calls
Future<void> _requestPermissions() async {
  await Permission.microphone.request();
  await Permission.camera.request();
}

class MyApp extends StatelessWidget {
  final StandaloneCallHandler callHandler;
  
  const MyApp({Key? key, required this.callHandler}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        Provider<HiveStorage>(create: (_) => HiveStorage()),
        Provider<SocketService>(
          create: (_) => SocketService(),
          dispose: (_, service) => service.dispose(),
        ),
        Provider<CallService>(
          create: (context) {
            final callService = CallService();
            return callService;
          },
          dispose: (_, service) => service.dispose(),
        ),
        Provider<StandaloneCallHandler>.value(value: callHandler),
      ],
      child: Builder(
        builder: (context) {
          // Get services after they've been created
          final socketService = Provider.of<SocketService>(context, listen: false);
          final callService = Provider.of<CallService>(context, listen: false);
          final authService = Provider.of<AuthService>(context, listen: false);
          
          // Initialize call service with socket service
          callService.initialize(socketService);
          
          // Initialize call handler with socket service
          callHandler.initialize(socketService);
          
          return MaterialApp(
            title: 'Techniq8Chat',
            navigatorKey: callHandler.navigatorKey,
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
            home: Consumer<AuthService>(
              builder: (context, authService, _) {
                // Check if user is already logged in
                if (authService.currentUser != null) {
                  // If user is logged in, go to bottom navigation
                  return BottomNavigationScreen();
                } else {
                  // If not logged in, show splash/welcome screen
                  return SplashScreen();
                }
              },
            ),
          );
        }
      ),
    );
  }
}