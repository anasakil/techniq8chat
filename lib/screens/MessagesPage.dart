// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';
// import 'package:techniq8chat/controller/auth_provider.dart';
// import 'package:techniq8chat/widgets/ConversationListPage.dart';
// import 'package:techniq8chat/screens/login_screen.dart';
// import 'package:techniq8chat/services/socket_service.dart';
// import 'package:shared_preferences/shared_preferences.dart';

// class MessagesPage extends StatefulWidget {
//   const MessagesPage({Key? key}) : super(key: key);

//   @override
//   _MessagesPageState createState() => _MessagesPageState();
// }

// class _MessagesPageState extends State<MessagesPage> {
//   bool _isSocketInitialized = false;
//   bool _isInitializing = false;

//   @override
//   void initState() {
//     super.initState();
//     // Schedule socket initialization for after the first frame
//     WidgetsBinding.instance.addPostFrameCallback((_) {
//       _initializeSocket();
//     });
//   }

//   Future<void> _initializeSocket() async {
//     if (_isSocketInitialized || _isInitializing) return;
    
//     setState(() {
//       _isInitializing = true;
//     });
    
//     final authProvider = Provider.of<AuthProvider>(context, listen: false);
    
//     if (authProvider.isLoggedIn) {
//       try {
//         final currentUser = authProvider.currentUser;
//         if (currentUser != null) {
//           // Make sure user ID is saved in SharedPreferences for socket reconnection
//           final prefs = await SharedPreferences.getInstance();
//           await prefs.setString('userId', currentUser.id);
          
//           // Initialize socket
//           await SocketService.instance.init(currentUser.id);
          
//           if (mounted) {
//             setState(() {
//               _isSocketInitialized = true;
//               _isInitializing = false;
//             });
//           }
          
//           print('Socket initialized successfully for user: ${currentUser.id}');
//         } else {
//           if (mounted) {
//             setState(() {
//               _isInitializing = false;
//             });
//           }
//         }
//       } catch (e) {
//         print('Error initializing socket: $e');
//         if (mounted) {
//           setState(() {
//             _isInitializing = false;
//           });
//         }
        
//         // Schedule a retry after a delay
//         Future.delayed(const Duration(seconds: 3), () {
//           if (mounted) {
//             _initializeSocket();
//           }
//         });
//       }
//     } else {
//       if (mounted) {
//         setState(() {
//           _isInitializing = false;
//         });
//       }
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     // Check if user is logged in
//     final authProvider = Provider.of<AuthProvider>(context);
    
//     // If not logged in, redirect to login
//     if (!authProvider.isLoggedIn) {
//       // Use a Future.delayed to avoid calling Navigator during build
//       Future.delayed(Duration.zero, () {
//         Navigator.of(context).pushReplacement(
//           MaterialPageRoute(builder: (context) => const LoginScreen()),
//         );
//       });
//       return const Scaffold(
//         body: Center(
//           child: CircularProgressIndicator(),
//         ),
//       );
//     }
    
//     // If socket not initialized yet and not already initializing, try again
//     if (!_isSocketInitialized && !_isInitializing) {
//       _initializeSocket();
//     }
    
//     // Show the conversation list with a status indicator if socket is initializing
//     return Scaffold(
//       body: Stack(
//         children: [
//           const ConversationListPage(),
//           if (_isInitializing)
//             Positioned(
//               top: 0,
//               left: 0,
//               right: 0,
//               child: Container(
//                 padding: const EdgeInsets.symmetric(vertical: 4),
//                 color: Colors.orange.shade300,
//                 child: const Center(
//                   child: Text(
//                     'Connecting to chat server...',
//                     style: TextStyle(color: Colors.white),
//                   ),
//                 ),
//               ),
//             ),
//         ],
//       ),
//     );
//   }
// }