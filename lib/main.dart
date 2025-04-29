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
import 'package:flutter/services.dart';

void main() async {
  // Ensure Flutter is initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Set preferred orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Add error handling
  FlutterError.onError = (FlutterErrorDetails details) {
    // Log the error
    print('Uncaught Flutter error: ${details.exception}');
    // You could send to a crash reporting service here
  };

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
  await Permission.notification.request();
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
            // IMPORTANT: We DO NOT initialize the socket handlers in CallService
            // Only the agora engine and call functions will be used
            return callService;
          },
          dispose: (_, service) => service.dispose(),
        ),
        Provider<StandaloneCallHandler>.value(value: callHandler),
      ],
      child: Builder(builder: (context) {
        // Get services after they've been created
        final socketService = Provider.of<SocketService>(context, listen: false);
        final callService = Provider.of<CallService>(context, listen: false);
        final authService = Provider.of<AuthService>(context, listen: false);

        // Load user data first, then connect services
        _initializeServices(context, authService, socketService, callService, callHandler);

        return AppLifecycleManager(
          child: MaterialApp(
            title: 'Techniq8Chat',
            navigatorKey: callHandler.navigatorKey,
            theme: ThemeData(
              primaryColor: const Color(0xFF2A64F6),
              primarySwatch: Colors.blue,
              visualDensity: VisualDensity.adaptivePlatformDensity,
              fontFamily: 'Roboto',
              appBarTheme: const AppBarTheme(
                backgroundColor: Colors.white,
                elevation: 0,
              ),
            ),
            // Define routes for navigation after calls end
            routes: {
              '/home': (context) => BottomNavigationScreen(),
              '/reset': (context) {
                // Emergency reset route
                callHandler.forceCloseAndReset();
                return BottomNavigationScreen();
              },
            },
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
          ),
        );
      }),
    );
  }
  
  // New method to properly sequence initialization
  Future<void> _initializeServices(
    BuildContext context,
    AuthService authService,
    SocketService socketService,
    CallService callService,
    StandaloneCallHandler callHandler
  ) async {
    // Try to load user data first
    await authService.loadUserData();
    
    // Initialize standalone call handler
    if (authService.currentUser != null) {
      // Initialize socket service first
      socketService.initSocket(authService.currentUser!);
      
      // CRITICAL: Only initialize ONE call handler
      // This handler will manage incoming call UI and avoid duplicates
      callHandler.initialize(socketService);
      
      // DO NOT initialize socket handling in CallService
      // callService.initialize(socketService); <- DO NOT UNCOMMENT
      
      print('Services initialized for user: ${authService.currentUser!.username}');
    } else {
      print('No current user found, services will be initialized after login');
    }
  }
}

// Enhanced AppLifecycleManager to help ensure app stays responsive to incoming calls
class AppLifecycleManager extends StatefulWidget {
  final Widget child;

  const AppLifecycleManager({Key? key, required this.child}) : super(key: key);

  @override
  _AppLifecycleManagerState createState() => _AppLifecycleManagerState();
}

class _AppLifecycleManagerState extends State<AppLifecycleManager>
    with WidgetsBindingObserver {
  // Store references to services to avoid Provider lookups in lifecycle methods
  late StandaloneCallHandler _callHandler;
  late SocketService _socketService;
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Cache the services when dependencies change
    _callHandler = Provider.of<StandaloneCallHandler>(context, listen: false);
    _socketService = Provider.of<SocketService>(context, listen: false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    print('App lifecycle state changed to: $state');

    if (state == AppLifecycleState.resumed) {
      // App came to foreground
      
      // 1. Ensure socket is connected
      if (!_socketService.isConnected) {
        _socketService.reconnect();
      }
      
      // 2. Check for stuck call screens
      if (!_callHandler.isCallActive() && Navigator.of(context).canPop()) {
        // If we're not handling a call but screens are stacked, reset
        _callHandler.forceCloseAndReset();
      }
    } else if (state == AppLifecycleState.paused) {
      // App went to background
      print('App moved to background');
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}