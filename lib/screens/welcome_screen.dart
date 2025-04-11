import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import '../middleware/auth_middleware.dart';
import 'MessagesPage.dart';
import 'create_account_screen.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  _WelcomeScreenState createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    // Check authentication when screen initializes
    _checkAuthentication();
  }

  Future<void> _checkAuthentication() async {
    // Slight delay to allow the UI to render first
    await Future.delayed(Duration(milliseconds: 100));
    
    AuthMiddleware.handleAuthNavigation(
      context,
      onAuthenticated: (context) {
        // User has token and data in local storage, go to Messages page
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => MessagesPage()),
        );
      },
      onUnauthenticated: (context) {
        // No valid token in local storage, stay on welcome screen
        setState(() {
          _isLoading = false;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: _isLoading
            ? Center(
                child: CircularProgressIndicator(
                  color: Colors.deepOrange,
                ),
              )
            : Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Lottie.asset(
                      'assets/welcome.json',
                      height: 300,
                      width: MediaQuery.of(context).size.width * 0.8,
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Welcome to Techniq8chat',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Chat easily with friends using Techniq8chat, your go-to platform for seamless conversations.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 40),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const CreateAccountScreen()),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepOrange,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                            side: const BorderSide(color: Colors.deepOrange),
                          ),
                        ),
                        child: const Text(
                          'Get Started',
                          style: TextStyle(fontSize: 16, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}