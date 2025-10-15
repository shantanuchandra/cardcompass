import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cardcompass/features/auth/providers/auth_provider.dart';

/// Profile screen for user information and settings
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  String _getAppVersion() {
    // Returns version string in format yyyy.MMdd.HH-mm (e.g., 2025.1003.10-01)
    const buildDate = String.fromEnvironment('BUILD_DATE', defaultValue: '2025-10-03 10:01');
    // Expecting buildDate in 'yyyy-MM-dd HH:mm' format
    final regex = RegExp(r'^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})');
    final match = regex.firstMatch(buildDate);
    if (match != null) {
      final year = match.group(1);
      final month = match.group(2);
      final day = match.group(3);
      final hour = match.group(4);
      final minute = match.group(5);
      return '$year.$month$day.$hour-$minute';
    }
    // Fallback to raw buildDate if parsing fails
    return buildDate;
  }
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _loadUserData() {
    final authState = ref.read(authStateProvider);
    if (authState.isAuthenticated && authState.user != null) {
      final user = authState.user!;
      _nameController.text = user.fullName ?? user.name ?? '';
      _emailController.text = user.email;
      _phoneController.text = user.phoneNumber ?? '';
    } else {
      _nameController.text = '';
      _emailController.text = '';
      _phoneController.text = '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(_isEditing ? Icons.check : Icons.edit),
            onPressed: _isEditing ? _saveProfile : _toggleEdit,
          ),
        ],
      ),
      body: authState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    // Profile Picture Section
                                // (Profile image section hidden as per request)
                                const SizedBox(height: 32),
                                // ...existing code...
                    const SizedBox(height: 32),
                    // ...existing code...
              Center(
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 60,
                      backgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                      child: Icon(
                        Icons.person,
                        size: 60,
                        color: Theme.of(context).primaryColor,
                      ),
                    ),
                    if (_isEditing)
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Theme.of(context).primaryColor,
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.camera_alt, color: Colors.white),
                            onPressed: _changeProfilePicture,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Personal Information Section
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Personal Information',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _nameController,
                        enabled: _isEditing,
                        decoration: const InputDecoration(
                          labelText: 'Full Name',
                          prefixIcon: Icon(Icons.person),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter your name';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _emailController,
                        enabled: _isEditing,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.email),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter your email';
                          }
                          if (!value.contains('@')) {
                            return 'Please enter a valid email';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _phoneController,
                        enabled: _isEditing,
                        decoration: const InputDecoration(
                          labelText: 'Phone Number',
                          prefixIcon: Icon(Icons.phone),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter your phone number';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Account Settings Section
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.notifications),
                      title: const Text('Notifications'),
                      trailing: Switch(
                        value: true,
                        onChanged: _isEditing ? (value) {
                          // TODO: Implement notification settings
                        } : null,
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.fingerprint),
                      title: const Text('Biometric Authentication'),
                      trailing: Switch(
                        value: false,
                        onChanged: _isEditing ? (value) {
                          // TODO: Implement biometric settings
                        } : null,
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.dark_mode),
                      title: const Text('Dark Mode'),
                      trailing: Switch(
                        value: false,
                        onChanged: _isEditing ? (value) {
                          // TODO: Implement theme settings
                        } : null,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // App Information Section
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.info),
                      title: const Text('App Version'),
                      trailing: Text(_getAppVersion()),
                      onTap: () {
                        // TODO: Show app info
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.privacy_tip),
                      title: const Text('Privacy Policy'),
                      trailing: const Icon(Icons.arrow_forward_ios),
                      onTap: () {
                        // TODO: Show privacy policy
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Privacy policy coming soon')),
                        );
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.description),
                      title: const Text('Terms of Service'),
                      trailing: const Icon(Icons.arrow_forward_ios),
                      onTap: () {
                        // TODO: Show terms of service
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Terms of service coming soon')),
                        );
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.help),
                      title: const Text('Help & Support'),
                      trailing: const Icon(Icons.arrow_forward_ios),
                      onTap: () {
                        // TODO: Show help and support
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Help & support coming soon')),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),              // Danger Zone Section
              Card(
                color: Colors.red.withValues(alpha: 0.1),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.delete_forever, color: Colors.red),
                      title: const Text(
                        'Delete Account',
                        style: TextStyle(color: Colors.red),
                      ),
                      trailing: const Icon(Icons.arrow_forward_ios, color: Colors.red),
                      onTap: _showDeleteAccountDialog,
                    ),
                    ListTile(
                      leading: const Icon(Icons.logout, color: Colors.red),
                      title: const Text(
                        'Sign Out',
                        style: TextStyle(color: Colors.red),
                      ),
                      trailing: const Icon(Icons.arrow_forward_ios, color: Colors.red),
                      onTap: _signOut,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  void _toggleEdit() {
    setState(() {
      _isEditing = !_isEditing;
    });
  }

  void _saveProfile() {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isEditing = false;
      });
      
      // TODO: Save profile data
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully')),
      );
    }
  }

  void _changeProfilePicture() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Camera'),
                onTap: () {
                  Navigator.pop(context);
                  // TODO: Implement camera capture
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Camera functionality coming soon')),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Gallery'),
                onTap: () {
                  Navigator.pop(context);
                  // TODO: Implement gallery selection
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Gallery functionality coming soon')),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete),
                title: const Text('Remove Photo'),
                onTap: () {
                  Navigator.pop(context);
                  // TODO: Implement photo removal
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Photo removed')),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showDeleteAccountDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Account'),
          content: const Text(
            'Are you sure you want to delete your account? This action cannot be undone and all your data will be permanently removed.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                // TODO: Implement account deletion
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Account deletion coming soon')),
                );
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  void _signOut() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Sign Out'),
          content: const Text('Are you sure you want to sign out?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(              onPressed: () {
                Navigator.pop(context);
                ref.read(authStateProvider.notifier).signOut();
                Navigator.pushReplacementNamed(context, '/login');
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Sign Out'),
            ),
          ],
        );
      },
    );
  }
}
