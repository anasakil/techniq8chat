import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:techniq8chat/screens/login_screen.dart';
import 'forgot_password_screen.dart';

class CreateAccountScreen extends StatefulWidget {
  const CreateAccountScreen({super.key});

  @override
  _CreateAccountScreenState createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends State<CreateAccountScreen> {
  bool _obscurePassword = true;
  bool _obscureRetypePassword = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Center(
                child: Lottie.asset('assets/create.json', height: 150),
              ),
              const SizedBox(height: 20),
              const Center(
                child: Text(
                  'Create an Account',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _buildInputField(label: 'Full Name'),
              const SizedBox(height: 15),
              _buildInputField(label: 'Phone Number', prefixText: '+93 '),
              const SizedBox(height: 15),
              _buildInputField(label: 'Email Address'),
              const SizedBox(height: 15),
              _buildPasswordField(
                label: 'Password',
                obscureText: _obscurePassword,
                onChanged: (value) => setState(() {
                  _obscurePassword = !_obscurePassword;
                }),
              ),
              const SizedBox(height: 15),
              _buildPasswordField(
                label: 'Retype Password',
                obscureText: _obscureRetypePassword,
                onChanged: (value) => setState(() {
                  _obscureRetypePassword = !_obscureRetypePassword;
                }),
              ),
              const SizedBox(height: 8),
              _buildActionButton(
                label: 'Create',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const ForgotPasswordScreen()),
                  );
                },
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Already have an account?'),
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const LoginScreen()),
                      );
                    },
                    child: const Text(
                      'Login',
                      style: TextStyle(color: Colors.deepOrange),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputField({required String label, String? prefixText}) {
    return TextFormField(
      decoration: InputDecoration(
        labelText: label,
        prefixText: prefixText,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20), // Consistent rounded corners
        ),
      ),
    );
  }

  Widget _buildPasswordField({
    required String label,
    required bool obscureText,
    required void Function(String) onChanged,
  }) {
    return TextFormField(
      obscureText: obscureText,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20), // Consistent rounded corners
        ),
        suffixIcon: IconButton(
          icon: Icon(obscureText ? Icons.visibility_off : Icons.visibility),
          onPressed: () => onChanged(''),
        ),
      ),
    );
  }

  Widget _buildActionButton({required String label, required void Function() onPressed}) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.deepOrange,
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 16, color: Colors.white),
        ),
      ),
    );
  }
}
