import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

class VerifyPhoneScreen extends StatelessWidget {
  const VerifyPhoneScreen({super.key});

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
              // Lottie Animation
              Center(
                child: Lottie.asset('assets/otp1.json', height: 250),
              ),
              const SizedBox(height: 20),

              // Title
              const Text(
                'Verify Phone',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),

              // Subtitle
              Text(
                'Code has been sent to +91 987654320',
                style: TextStyle(color: Colors.grey[600]),
              ),
              const SizedBox(height: 30),

              // OTP Input Field
              _buildOtpField(),
              const SizedBox(height: 30),

              // Verify Button
              _buildActionButton(
                label: 'Verify',
                onPressed: () {
                  // Handle verification logic
                },
              ),
              const SizedBox(height: 20),

              // Resend OTP
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Didn't get OTP Code?"),
                  TextButton(
                    onPressed: () {
                      // Handle resend code logic
                    },
                    child: const Text(
                      'Resend Code',
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

  // OTP Input Field (Single TextField)
  Widget _buildOtpField() {
    return TextField(
      textAlign: TextAlign.center,
      keyboardType: TextInputType.number,
      maxLength: 6, // Adjust based on OTP length
      style: const TextStyle(fontSize: 20, letterSpacing: 10),
      decoration: InputDecoration(
        labelText: 'Enter OTP',
        labelStyle: TextStyle(color: Colors.grey[600]),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15), // Consistent rounded corners
        ),
      ),
    );
  }

  // Reusable Button
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
