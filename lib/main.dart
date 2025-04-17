// main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:techniq8chat/screens/welcome_screen.dart';
import 'package:techniq8chat/screens/bottom_navigation_screen.dart';
import 'package:techniq8chat/widgets/call_wrapper.dart';
import 'services/auth_service.dart';
import 'services/hive_storage.dart';
import 'services/webrtc_service.dart';
import 'screens/splash_screen.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

void main() async {
  // Ensure Flutter is initialized
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Hive
  await HiveStorage.initialize();
  
  // Request permissions required for WebRTC
  await _requestPermissions();
  
  runApp(MyApp());
}

// Request necessary permissions for WebRTC
Future<void> _requestPermissions() async {
  await Permission.camera.request();
  await Permission.microphone.request();
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        Provider<HiveStorage>(create: (_) => HiveStorage()),
        Provider<WebRTCService>(create: (_) => WebRTCService()),
      ],
      child: MaterialApp(
        title: 'Techniq8Chat',
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
        home: CallWrapper(
          child: SplashScreen(),
        ),
      ),
    );
  }
}