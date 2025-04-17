// screens/register_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:techniq8chat/screens/bottom_navigation_screen.dart';
import '../services/auth_service.dart';

class RegisterScreen extends StatefulWidget {
  @override
  _RegisterScreenState createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _keyController = TextEditingController();  // Added key controller
  bool _isLoading = false;
  String _errorMessage = '';
  bool _isValidatingKey = false;  // For key validation loading state
  String? _keyValidationMessage;  // For key validation message
  bool? _isKeyValid;  // For tracking key validation result
  
  // Add animation controller for consistent design with login screen
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  
  @override
  void initState() {
    super.initState();
    
    // Set up animations
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 800),
    );
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Interval(0.3, 1.0, curve: Curves.easeOut),
      ),
    );
    
    _animationController.forward();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _keyController.dispose();  // Dispose key controller
    _animationController.dispose();
    super.dispose();
  }

  // Validate the key when input is complete
  Future<void> _validateKey() async {
    if (_keyController.text.length != 10) return;
    
    setState(() {
      _isValidatingKey = true;
      _keyValidationMessage = null;
      _isKeyValid = null;
    });
    
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final isValid = await authService.checkKeyValidity(_keyController.text);
      
      setState(() {
        _isKeyValid = isValid;
        _keyValidationMessage = isValid 
            ? 'Valid registration key' 
            : 'Invalid or already used key';
        _isValidatingKey = false;
      });
    } catch (e) {
      setState(() {
        _isKeyValid = false;
        _keyValidationMessage = 'Error checking key';
        _isValidatingKey = false;
      });
    }
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      await authService.register(
        _usernameController.text,
        _emailController.text,
        _passwordController.text,
        _keyController.text,  // Add key to register method
      );
      
      // Navigate to bottom navigation screen instead of conversations screen
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => BottomNavigationScreen()),
      );
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: Colors.grey[800], size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Create Account',
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Logo
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: Column(
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: const Color(0xFF2A64F6).withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.person_add_outlined,
                            size: 40,
                            color: const Color(0xFF2A64F6),
                          ),
                        ),
                        SizedBox(height: 20),
                        Text(
                          'Join Techniq8Chat',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Create an account to get started',
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.grey[600],
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  
                  SizedBox(height: 32),
                  
                  // Username Field
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: _buildInputField(
                      controller: _usernameController,
                      hintText: 'Username',
                      icon: Icons.person_outline,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter a username';
                        }
                        if (value.length < 3) {
                          return 'Username must be at least 3 characters';
                        }
                        return null;
                      },
                    ),
                  ),
                  
                  SizedBox(height: 16),
                  
                  // Email Field
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: _buildInputField(
                      controller: _emailController,
                      hintText: 'Email',
                      icon: Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter an email';
                        }
                        final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                        if (!emailRegex.hasMatch(value)) {
                          return 'Please enter a valid email';
                        }
                        return null;
                      },
                    ),
                  ),
                  
                  SizedBox(height: 16),
                  
                  // Password Field
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: _buildInputField(
                      controller: _passwordController,
                      hintText: 'Password',
                      icon: Icons.lock_outline,
                      obscureText: true,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter a password';
                        }
                        if (value.length < 6) {
                          return 'Password must be at least 6 characters';
                        }
                        return null;
                      },
                    ),
                  ),
                  
                  SizedBox(height: 16),
                  
                  // Registration Key Field
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: _buildInputField(
                      controller: _keyController,
                      hintText: 'Registration Key (10 digits)',
                      icon: Icons.key_outlined,
                      keyboardType: TextInputType.number,
                      suffixIcon: _isValidatingKey 
                          ? SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.grey),
                                strokeWidth: 2,
                              ),
                            )
                          : _isKeyValid != null
                              ? Icon(
                                  _isKeyValid! ? Icons.check_circle : Icons.error,
                                  color: _isKeyValid! ? Colors.green : Colors.red,
                                )
                              : null,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter your registration key';
                        }
                        if (value.length != 10) {
                          return 'Key must be exactly 10 digits';
                        }
                        final keyRegex = RegExp(r'^\d{10}$');
                        if (!keyRegex.hasMatch(value)) {
                          return 'Key must be 10 numeric digits only';
                        }
                        // If key was validated and is invalid
                        if (_isKeyValid != null && !_isKeyValid!) {
                          return 'Please enter a valid registration key';
                        }
                        return null;
                      },
                      onChanged: (value) {
                        // Clear validation when changed
                        if (_isKeyValid != null) {
                          setState(() {
                            _isKeyValid = null;
                            _keyValidationMessage = null;
                          });
                        }
                        // Auto-validate when 10 digits entered
                        if (value.length == 10) {
                          _validateKey();
                        }
                      },
                    ),
                  ),
                  
                  // Key validation message
                  if (_keyValidationMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0, left: 8.0),
                      child: Text(
                        _keyValidationMessage!,
                        style: TextStyle(
                          color: _isKeyValid == true ? Colors.green : Colors.red,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  
                  SizedBox(height: 10),
                  
                  // Error Message
                  if (_errorMessage.isNotEmpty)
                    Container(
                      padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      margin: EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.red[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red[100]!),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, color: Colors.red[700], size: 20),
                          SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              _errorMessage,
                              style: TextStyle(color: Colors.red[700], fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                    ),
                  
                  SizedBox(height: 20),
                  
                  // Register Button
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _register,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2A64F6),
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: _isLoading
                          ? SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              'Create Account',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                  
                  SizedBox(height: 24),
                  
                  // Terms and Conditions
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: Text(
                      'By creating an account, you agree to our Terms of Service and Privacy Policy',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildInputField({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    bool obscureText = false,
    Widget? suffixIcon,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
    Function(String)? onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: TextFormField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        style: TextStyle(fontSize: 15),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(color: Colors.grey[400]),
          prefixIcon: Icon(icon, color: Colors.grey[600], size: 22),
          suffixIcon: suffixIcon,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: const Color(0xFF2A64F6), width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.red, width: 1),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.red, width: 1.5),
          ),
          filled: true,
          fillColor: Colors.grey[50],
          contentPadding: EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        ),
        validator: validator,
        onChanged: onChanged,
      ),
    );
  }
}