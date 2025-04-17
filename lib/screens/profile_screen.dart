// screens/profile_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:techniq8chat/services/auth_service.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:http_parser/http_parser.dart';

class ProfileScreen extends StatefulWidget {
  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = true;
  bool _isEditing = false;
  bool _isUpdating = false;

  // User data
  String _username = "";
  String _email = "";
  String _bio = "";
  String? _profilePicture;

  // Controllers
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();

  // File for new profile picture
  File? _imageFile;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');

      if (token == null) {
        // Handle no token case
        Navigator.of(context).pushReplacementNamed('/login');
        return;
      }

      // Fetch user data from API
      final response = await http.get(
        Uri.parse('http://192.168.100.96:4400/api/users/me'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final userData = json.decode(response.body);

        setState(() {
          _username = userData['username'] ?? "";
          _email = userData['email'] ?? "";
          _bio = userData['bio'] ?? "";
          _profilePicture = userData['profilePicture'];

          // Set controllers
          _usernameController.text = _username;
          _emailController.text = _email;
          _bioController.text = _bio;

          _isLoading = false;
        });
      } else {
        _showErrorSnackBar('Failed to load profile data.');
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      _showErrorSnackBar('Error: ${e.toString()}');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _updateProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isUpdating = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');

      if (token == null) {
        _showErrorSnackBar('Authentication error. Please login again.');
        setState(() {
          _isUpdating = false;
        });
        return;
      }

      // Create multipart request
      var request = http.MultipartRequest(
        'PUT',
        Uri.parse('http://192.168.100.96:4400/api/users/me'),
      );

      // Add headers
      request.headers.addAll({
        'Authorization': 'Bearer $token',
      });

      // Add text fields
      request.fields['username'] = _usernameController.text;
      request.fields['email'] = _emailController.text;
      request.fields['bio'] = _bioController.text;

      // Add profile picture if selected
      if (_imageFile != null) {
        // Get file extension and determine MIME type
        final String extension = _imageFile!.path.split('.').last.toLowerCase();
        String contentType;

        switch (extension) {
          case 'jpg':
          case 'jpeg':
            contentType = 'image/jpeg';
            break;
          case 'png':
            contentType = 'image/png';
            break;
          case 'gif':
            contentType = 'image/gif';
            break;
          default:
            _showErrorSnackBar(
                'Unsupported file type. Please use JPG, JPEG, PNG or GIF.');
            setState(() {
              _isUpdating = false;
            });
            return;
        }

        try {
          final fileStream = http.ByteStream(_imageFile!.openRead());
          final fileLength = await _imageFile!.length();

          final multipartFile = http.MultipartFile(
            'profilePicture',
            fileStream,
            fileLength,
            filename: 'profile_image.$extension',
            contentType: MediaType.parse(contentType),
          );

          request.files.add(multipartFile);
        } catch (e) {
          _showErrorSnackBar('Error preparing image: ${e.toString()}');
          setState(() {
            _isUpdating = false;
          });
          return;
        }
      }

      // Send request
      try {
        final streamedResponse =
            await request.send().timeout(Duration(seconds: 30));
        final response = await http.Response.fromStream(streamedResponse);

        if (response.statusCode == 200) {
          final updatedData = json.decode(response.body);

          setState(() {
            _username = updatedData['username'];
            _email = updatedData['email'];
            _bio = updatedData['bio'];
            _profilePicture = updatedData['profilePicture'];

            _isEditing = false;
            _isUpdating = false;
          });

          // Update AuthService with new user data
          final authService = Provider.of<AuthService>(context, listen: false);
          // authService.updateUserData(updatedData);

          _showSuccessSnackBar('Profile updated successfully!');
        } else {
          // Try to parse error message from response body
          String errorMessage = 'Failed to update profile.';
          try {
            final errorData = json.decode(response.body);
            errorMessage = errorData['message'] ?? errorMessage;
          } catch (_) {}

          _showErrorSnackBar(errorMessage);
          setState(() {
            _isUpdating = false;
          });
        }
      } catch (e) {
        if (e is TimeoutException) {
          _showErrorSnackBar('Request timed out. Please try again.');
        } else {
          _showErrorSnackBar('Error sending request: ${e.toString()}');
        }
        setState(() {
          _isUpdating = false;
        });
      }
    } catch (e) {
      _showErrorSnackBar('Error: ${e.toString()}');
      setState(() {
        _isUpdating = false;
      });
    }
  }

  Future<void> _pickImage() async {
    try {
      // First, show a dialog to let the user choose between gallery and camera
      final source = await showDialog<ImageSource>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('Select Image Source'),
            content: SingleChildScrollView(
              child: ListBody(
                children: <Widget>[
                  GestureDetector(
                    child: Text('Gallery'),
                    onTap: () {
                      Navigator.of(context).pop(ImageSource.gallery);
                    },
                  ),
                  SizedBox(height: 16),
                  GestureDetector(
                    child: Text('Camera'),
                    onTap: () {
                      Navigator.of(context).pop(ImageSource.camera);
                    },
                  ),
                ],
              ),
            ),
          );
        },
      );

      if (source == null) return; // User canceled the dialog

      final pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        // Check file extension to validate file type
        final String extension = pickedFile.path.split('.').last.toLowerCase();
        final List<String> allowedExtensions = ['jpg', 'jpeg', 'png', 'gif'];

        if (!allowedExtensions.contains(extension)) {
          _showErrorSnackBar(
              'File type not supported. Please use JPG, JPEG, PNG or GIF.');
          return;
        }

        // Check file size (limit to 5MB)
        final File file = File(pickedFile.path);
        final int fileSize = await file.length();
        if (fileSize > 5 * 1024 * 1024) {
          _showErrorSnackBar('Image too large. Maximum size is 5MB.');
          return;
        }

        setState(() {
          _imageFile = File(pickedFile.path);
        });
      }
    } catch (e) {
      _showErrorSnackBar('Error picking image: ${e.toString()}');
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red[700],
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green[700],
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        leadingWidth: 0,
        titleSpacing: 16,
        centerTitle: false,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                Icons.arrow_back_ios,
                size: 20,
                color: Colors.black87,
              ),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
        actions: [
          if (_isEditing)
            IconButton(
              icon: Icon(Icons.close, color: Colors.black87),
              onPressed: () {
                setState(() {
                  _isEditing = false;
                  // Reset form values
                  _usernameController.text = _username;
                  _emailController.text = _email;
                  _bioController.text = _bio;
                  _imageFile = null;
                });
              },
            )
          else
            IconButton(
              icon: Icon(Icons.edit, color: Colors.black87),
              onPressed: () {
                setState(() {
                  _isEditing = true;
                });
              },
            ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(color: const Color(0xFF2A64F6)))
          : SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Profile Picture Section
                    Center(
                      child: _buildProfilePicture(),
                    ),
                    SizedBox(height: 32),

                    // Profile Details Section
                    Text(
                      'Profile Information',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    SizedBox(height: 16),

                    // Username Field
                    _buildFormField(
                      label: 'Username',
                      controller: _usernameController,
                      enabled: _isEditing,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Username is required';
                        }
                        if (value.length < 3) {
                          return 'Username must be at least 3 characters';
                        }
                        return null;
                      },
                      prefixIcon: Icons.person,
                    ),
                    SizedBox(height: 16),

                    // Email Field
                    _buildFormField(
                      label: 'Email',
                      controller: _emailController,
                      enabled: _isEditing,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Email is required';
                        }
                        if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$')
                            .hasMatch(value)) {
                          return 'Enter a valid email address';
                        }
                        return null;
                      },
                      prefixIcon: Icons.email,
                    ),
                    SizedBox(height: 16),

                    // Bio Field
                    _buildFormField(
                      label: 'Bio',
                      controller: _bioController,
                      enabled: _isEditing,
                      validator: (value) {
                        if (value != null && value.length > 200) {
                          return 'Bio must be less than 200 characters';
                        }
                        return null;
                      },
                      prefixIcon: Icons.info_outline,
                    ),
                    SizedBox(height: 32),

                    // Update Button
                    if (_isEditing) _buildUpdateButton(),

                    SizedBox(height: 24),

                    // Account Settings Section
                    Text(
                      'Account Settings',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    SizedBox(height: 16),

                    // Change Password Button
                    _buildSettingsOption(
                      icon: Icons.lock_outline,
                      title: 'Change Password',
                      onTap: () {
                        // Navigate to change password screen
                      },
                    ),

                    // Privacy Settings
                    _buildSettingsOption(
                      icon: Icons.privacy_tip_outlined,
                      title: 'Privacy Settings',
                      onTap: () {
                        // Navigate to privacy settings screen
                      },
                    ),

                    // Blocked Users
                    _buildSettingsOption(
                      icon: Icons.block_outlined,
                      title: 'Blocked Users',
                      onTap: () {
                        // Navigate to blocked users screen
                      },
                    ),

                    // Notifications
                    _buildSettingsOption(
                      icon: Icons.notifications_outlined,
                      title: 'Notification Settings',
                      onTap: () {
                        // Navigate to notification settings screen
                      },
                    ),

                    SizedBox(height: 24),

                    // Logout Button
                    _buildLogoutButton(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildProfilePicture() {
    return Stack(
      children: [
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF2A64F6).withOpacity(0.1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(60),
            child: _imageFile != null
                ? Image.file(
                    _imageFile!,
                    width: 120,
                    height: 120,
                    fit: BoxFit.cover,
                  )
                : _profilePicture != null && _profilePicture!.isNotEmpty
                    ? Image.network(
                        'http://192.168.100.96:4400/${_profilePicture}',
                        width: 120,
                        height: 120,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Center(
                            child: Icon(
                              Icons.person,
                              size: 50,
                              color: const Color(0xFF2A64F6),
                            ),
                          );
                        },
                      )
                    : Center(
                        child: Text(
                          _username.isNotEmpty
                              ? _username[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF2A64F6),
                          ),
                        ),
                      ),
          ),
        ),
        if (_isEditing)
          Positioned(
            bottom: 0,
            right: 0,
            child: InkWell(
              onTap: _pickImage,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF2A64F6),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Icon(
                  Icons.camera_alt,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildFormField({
    required String label,
    required TextEditingController controller,
    required bool enabled,
    required IconData prefixIcon,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      validator: validator,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: enabled ? 'Enter your $label' : null,
        prefixIcon: Icon(prefixIcon, color: Colors.grey[600]),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: const Color(0xFF2A64F6), width: 1.5),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[200]!),
        ),
        fillColor: enabled ? Colors.white : Colors.grey[50],
        filled: true,
      ),
    );
  }

  Widget _buildUpdateButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isUpdating ? null : _updateProfile,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF2A64F6),
          foregroundColor: Colors.white,
          padding: EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
        child: _isUpdating
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : Text(
                'Save Changes',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }

  Widget _buildSettingsOption({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Colors.grey[200]!,
              width: 1,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: Colors.grey[700],
              size: 20,
            ),
            SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.black87,
                ),
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              color: Colors.grey[400],
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogoutButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: () async {
          final authService = Provider.of<AuthService>(context, listen: false);
          await authService.logout();
          Navigator.of(context).pushReplacementNamed('/login');
        },
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.red[700],
          side: BorderSide(color: Colors.red[700]!, width: 1.5),
          padding: EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(
          'Logout',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
