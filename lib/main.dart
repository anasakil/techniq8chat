// main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:techniq8chat/screens/welcome_screen.dart';
import 'package:techniq8chat/screens/bottom_navigation_screen.dart';
import 'package:techniq8chat/screens/splash_screen.dart';
import 'package:techniq8chat/utils/enhanced_call_handler.dart';
import 'services/auth_service.dart';
import 'services/hive_storage.dart';
import 'services/socket_service.dart';

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
        Provider<SocketService>(
          create: (_) => SocketService(),
          // Dispose the socket service when the app is closed
          dispose: (_, service) => service.dispose(),
        ),
      ],
      child: AppWithAuth(),
    );
  }
}

class AppWithAuth extends StatefulWidget {
  @override
  _AppWithAuthState createState() => _AppWithAuthState();
}

class _AppWithAuthState extends State<AppWithAuth> with WidgetsBindingObserver {
  bool _isInitialized = false;
  
  @override
  void initState() {
    super.initState();
    // Add observer for app lifecycle changes
    WidgetsBinding.instance.addObserver(this);
    
    // Initialize auth and socket services
    _initializeServices();
  }
  
  @override
  void dispose() {
    // Remove lifecycle observer
    WidgetsBinding.instance.removeObserver(this);
    
    // Clean up call handler
    EnhancedCallHandler.instance.dispose();
    
    super.dispose();
  }
  
  // Handle app lifecycle changes
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final socketService = Provider.of<SocketService>(context, listen: false);
    
    if (authService.currentUser != null) {
      switch (state) {
        case AppLifecycleState.resumed:
          // App is visible and running in foreground
          print('App resumed - reconnecting socket and updating status');
          socketService.reconnect();
          authService.updateStatus('online');
          break;
        case AppLifecycleState.inactive:
          // App is inactive (in the process of pausing)
          print('App inactive');
          break;
        case AppLifecycleState.paused:
          // App is in background
          print('App paused - updating status to away');
          authService.updateStatus('away');
          break;
        case AppLifecycleState.detached:
          // App is detached (terminated)
          print('App detached - updating status to offline');
          authService.updateStatus('offline');
          break;
        case AppLifecycleState.hidden:
          // App is hidden (not visible to the user)
          print('App hidden');
          break;
      }
    }
  }
  
  // Initialize auth and socket services
  Future<void> _initializeServices() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      
      // Load saved user data
      await authService.loadUserData();
      
      // If we have a current user, initialize socket connection
      if (authService.currentUser != null) {
        final socketService = Provider.of<SocketService>(context, listen: false);
        
        // Initialize socket with current user
        socketService.initSocket(authService.currentUser!);
        
        // Update user status to online
        authService.updateStatus('online');
      }
      
      // Mark initialization as complete
      setState(() {
        _isInitialized = true;
      });
    } catch (e) {
      print('Error initializing services: $e');
      setState(() {
        _isInitialized = true;  // Set to true anyway to show the app
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
      home: _isInitialized 
          ? AppStartScreen()
          : SplashScreen(),
    );
  }
}

class AppStartScreen extends StatefulWidget {
  @override
  _AppStartScreenState createState() => _AppStartScreenState();
}

class _AppStartScreenState extends State<AppStartScreen> {
  @override
  void initState() {
    super.initState();
    
    // Set up call handler after first frame is rendered
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeCallHandler();
    });
  }
  
  // Initialize the enhanced call handler
  void _initializeCallHandler() {
    final authService = Provider.of<AuthService>(context, listen: false);
    final socketService = Provider.of<SocketService>(context, listen: false);
    
    // Only initialize call handler if user is logged in
    if (authService.currentUser != null) {
      print('Initializing call handler in AppStartScreen');
      EnhancedCallHandler.instance.initialize(
        context,
        socketService,
        authService
      );
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    
    // If user is logged in, show the main screen, otherwise show welcome screen
    return authService.currentUser != null
        ? BottomNavigationScreen()
        : WelcomeScreen();
  }
}