import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'verify_phone_screen.dart';

class ForgotPasswordScreen extends StatelessWidget {
  const ForgotPasswordScreen({super.key});

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
      body: SingleChildScrollView(  // Added SingleChildScrollView for responsiveness
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Lottie.asset('assets/reset.json', height: 250), // Lottie animation
            ),
            const SizedBox(height: 20),
            const Text(
              'Forgot Password',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            _buildInputField(),
            const SizedBox(height: 30),
            _buildActionButton(
              label: 'Submit',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const VerifyPhoneScreen()),
                );
              },
            ),
            const SizedBox(height: 20),  // Add spacing to prevent overflow
          ],
        ),
      ),
    );
  }

  Widget _buildInputField() {
    return TextFormField(
      decoration: InputDecoration(
        labelText: 'Email Address',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15), // Consistent rounded corners
        ),
        prefixIcon: const Icon(Icons.email_outlined),
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
            borderRadius: BorderRadius.circular(15), // Consistent rounded corners
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
