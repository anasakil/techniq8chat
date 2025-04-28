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
            return callService;
          },
          dispose: (_, service) => service.dispose(),
        ),
        Provider<StandaloneCallHandler>.value(value: callHandler),
      ],
      child: Builder(builder: (context) {
        // Get services after they've been created
        final socketService =
            Provider.of<SocketService>(context, listen: false);
        final callService = Provider.of<CallService>(context, listen: false);
        final authService = Provider.of<AuthService>(context, listen: false);

        // CRITICAL: Initialize ONLY ONE call handler!
        // We'll use StandaloneCallHandler and disable CallService socket handlers
        callHandler.initialize(socketService);

        // IMPORTANT: DO NOT initialize the CallService for socket events
        // This is causing duplicate call notifications
        // callService.initialize(socketService); // COMMENTED OUT to prevent duplicates

        return MaterialApp(
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
        );
      }),
    );
  }
}

// Add this class to help ensure app stays responsive to incoming calls
class AppLifecycleManager extends StatefulWidget {
  final Widget child;

  const AppLifecycleManager({Key? key, required this.child}) : super(key: key);

  @override
  _AppLifecycleManagerState createState() => _AppLifecycleManagerState();
}

class _AppLifecycleManagerState extends State<AppLifecycleManager>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
      // App came to foreground - check for stuck call screens
      final callHandler =
          Provider.of<StandaloneCallHandler>(context, listen: false);
      if (!callHandler.isCallActive() && Navigator.of(context).canPop()) {
        // If we're not handling a call but screens are stacked, reset
        callHandler.forceCloseAndReset();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
