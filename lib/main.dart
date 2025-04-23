// main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:techniq8chat/screens/welcome_screen.dart';
import 'package:techniq8chat/screens/bottom_navigation_screen.dart';
import 'services/auth_service.dart';
import 'services/hive_storage.dart';
import 'screens/splash_screen.dart';

void main() async {
  // Ensure Flutter is initialized
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Hive
  await HiveStorage.initialize();
  
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        Provider<HiveStorage>(create: (_) => HiveStorage()),
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
        home: SplashScreen(),
        
      ),
    );
  }
}