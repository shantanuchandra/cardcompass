import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cardcompass/features/auth/providers/auth_provider.dart';
import 'package:cardcompass/core/providers/service_providers.dart';
import 'package:cardcompass/core/theme.dart';

/// Profile screen for user information and settings in cyber-fintech style
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  String _getAppVersion() {
    const buildDate = String.fromEnvironment('BUILD_DATE', defaultValue: '2025-10-03 10:01');
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
    return buildDate;
  }
  
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _isEditing = false;
  bool _notificationsEnabled = true;
  bool _biometricEnabled = false;

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
    }
    final prefs = ref.read(appPreferencesProvider);
    _notificationsEnabled = prefs.notificationsEnabled;
    _biometricEnabled = prefs.biometricEnabled;
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    return Scaffold(
      backgroundColor: const Color(0xFF050B18),
      appBar: AppBar(
        title: Text(
          'USER PROFILE',
          style: GoogleFonts.spaceGrotesk(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
            fontSize: 16,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(_isEditing ? Icons.check : Icons.edit_outlined, color: AppTheme.primaryColor),
            onPressed: _isEditing ? _saveProfile : _toggleEdit,
          ),
        ],
      ),
      body: authState.isLoading
          ? const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(AppTheme.primaryColor)))
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    // Glowing Profile Avatar
                    Center(
                      child: Stack(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.3), width: 2),
                              boxShadow: AppTheme.neonGlow(color: AppTheme.primaryColor, opacity: 0.15, blurRadius: 15),
                            ),
                            child: const CircleAvatar(
                              radius: 54,
                              backgroundColor: Color(0xFF0C152B),
                              child: Icon(
                                Icons.person_outline,
                                size: 50,
                                color: AppTheme.primaryColor,
                              ),
                            ),
                          ),
                          if (_isEditing)
                            Positioned(
                              bottom: 2,
                              right: 2,
                              child: Container(
                                decoration: const BoxDecoration(
                                  color: AppTheme.primaryColor,
                                  shape: BoxShape.circle,
                                ),
                                child: IconButton(
                                  icon: const Icon(Icons.camera_alt, color: Color(0xFF050B18), size: 20),
                                  onPressed: _changeProfilePicture,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Personal Information Section
                    _buildSectionWrapper(
                      title: 'PERSONAL INFORMATION',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextFormField(
                            controller: _nameController,
                            enabled: _isEditing,
                            style: GoogleFonts.plusJakartaSans(color: Colors.white),
                            decoration: const InputDecoration(
                              labelText: 'Full Name',
                              prefixIcon: Icon(Icons.person_outline, color: AppTheme.primaryColor),
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
                            style: GoogleFonts.plusJakartaSans(color: Colors.white),
                            decoration: const InputDecoration(
                              labelText: 'Email Address',
                              prefixIcon: Icon(Icons.email_outlined, color: AppTheme.primaryColor),
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
                            style: GoogleFonts.plusJakartaSans(color: Colors.white),
                            decoration: const InputDecoration(
                              labelText: 'Phone Number',
                              prefixIcon: Icon(Icons.phone_outlined, color: AppTheme.primaryColor),
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
                    const SizedBox(height: 20),

                    // Account Settings Section
                    _buildSectionWrapper(
                      title: 'SYSTEM SETTINGS',
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.notifications_none, color: AppTheme.primaryColor),
                            title: Text('PUSH NOTIFICATIONS', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                            trailing: Switch(
                              value: _notificationsEnabled,
                              activeColor: AppTheme.primaryColor,
                              onChanged: _isEditing ? (value) {
                                setState(() => _notificationsEnabled = value);
                                ref.read(appPreferencesProvider).setNotificationsEnabled(value);
                              } : null,
                            ),
                          ),
                          const Divider(color: Color(0xFF1E293B), height: 1),
                          ListTile(
                            leading: const Icon(Icons.fingerprint, color: AppTheme.primaryColor),
                            title: Text('BIOMETRIC CREDENTIALS', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                            trailing: Switch(
                              value: _biometricEnabled,
                              activeColor: AppTheme.primaryColor,
                              onChanged: _isEditing ? (value) {
                                setState(() => _biometricEnabled = value);
                                ref.read(appPreferencesProvider).setBiometricEnabled(value);
                              } : null,
                            ),
                          ),
                          const Divider(color: Color(0xFF1E293B), height: 1),
                          ListTile(
                            leading: const Icon(Icons.dark_mode_outlined, color: AppTheme.primaryColor),
                            title: Text('DARK MODE ALWAYS', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                            subtitle: Text('Cyber-neon default mode', style: GoogleFonts.plusJakartaSans(color: Colors.white30, fontSize: 10)),
                            trailing: Switch(
                              value: true,
                              activeColor: AppTheme.primaryColor,
                              onChanged: null,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // App Information Section
                    _buildSectionWrapper(
                      title: 'SYSTEM INTEL',
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.info_outline, color: AppTheme.primaryColor),
                            title: Text('LEDGER VERSION', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                            trailing: Text(
                              _getAppVersion(),
                              style: GoogleFonts.spaceGrotesk(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                            onTap: () {
                              showDialog(
                                context: context,
                                builder: (context) => AlertDialog(
                                  backgroundColor: const Color(0xFF0C152B),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                    side: const BorderSide(color: Color(0xFF1E293B)),
                                  ),
                                  title: Text('CARDCOMPASS ENGINE', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                                  content: Text('Terminal Version: ${_getAppVersion()}', style: GoogleFonts.plusJakartaSans(color: Colors.white70)),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: Text('OK', style: GoogleFonts.spaceGrotesk(color: AppTheme.primaryColor, fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          const Divider(color: Color(0xFF1E293B), height: 1),
                          ListTile(
                            leading: const Icon(Icons.privacy_tip_outlined, color: AppTheme.primaryColor),
                            title: Text('PRIVACY REGISTRY', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                            trailing: const Icon(Icons.arrow_forward_ios, size: 12, color: Colors.white30),
                            onTap: () => _showInfoDialog(
                              'PRIVACY POLICY',
                              'CardCompass stores your credit card details locally on your physical device. We do not transmit or sell account numbers. Signed-in sessions utilize encrypted database records, while guest mode remains permanently sandboxed on this client.',
                            ),
                          ),
                          const Divider(color: Color(0xFF1E293B), height: 1),
                          ListTile(
                            leading: const Icon(Icons.description_outlined, color: AppTheme.primaryColor),
                            title: Text('TERMS OF PROTOCOL', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                            trailing: const Icon(Icons.arrow_forward_ios, size: 12, color: Colors.white30),
                            onTap: () => _showInfoDialog(
                              'TERMS OF SERVICE',
                              'CardCompass is provided as-is without warranties. Optimization levels, reward calculations, and interest rates are local simulations based on document parsing parameters and may differ from your exact credit card statement.',
                            ),
                          ),
                          const Divider(color: Color(0xFF1E293B), height: 1),
                          ListTile(
                            leading: const Icon(Icons.help_outline, color: AppTheme.primaryColor),
                            title: Text('HELP & SUPPORT TERMINAL', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                            trailing: const Icon(Icons.arrow_forward_ios, size: 12, color: Colors.white30),
                            onTap: () => _showInfoDialog(
                              'HELP & SUPPORT',
                              'Verify email synchronization and credential profiles in the main dashboard. If statement classification parameters fail, consider signing out to reset the local cache.',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Danger Zone Section
                    _buildSectionWrapper(
                      title: 'RESTRICTED OPERATION ZONE',
                      padding: EdgeInsets.zero,
                      borderColor: AppTheme.errorColor.withValues(alpha: 0.3),
                      child: Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.delete_forever_outlined, color: AppTheme.errorColor),
                            title: Text('TERMINATE USER ACCOUNT', style: GoogleFonts.spaceGrotesk(color: AppTheme.errorColor, fontSize: 12, fontWeight: FontWeight.bold)),
                            trailing: const Icon(Icons.arrow_forward_ios, size: 12, color: AppTheme.errorColor),
                            onTap: _showDeleteAccountDialog,
                          ),
                          const Divider(color: Color(0xFF1E293B), height: 1),
                          ListTile(
                            leading: const Icon(Icons.logout_outlined, color: AppTheme.errorColor),
                            title: Text('DESTROY ACTIVE SESSION', style: GoogleFonts.spaceGrotesk(color: AppTheme.errorColor, fontSize: 12, fontWeight: FontWeight.bold)),
                            trailing: const Icon(Icons.arrow_forward_ios, size: 12, color: AppTheme.errorColor),
                            onTap: _signOut,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 80), // space above bottom dock
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSectionWrapper({
    required String title,
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(16),
    Color? borderColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title,
            style: GoogleFonts.spaceGrotesk(
              color: Colors.white60,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
            ),
          ),
        ),
        Container(
          padding: padding,
          decoration: BoxDecoration(
            color: const Color(0xFF0C152B),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: borderColor ?? Colors.white.withValues(alpha: 0.06),
              width: 1.2,
            ),
          ),
          child: child,
        ),
      ],
    );
  }

  void _toggleEdit() {
    setState(() {
      _isEditing = !_isEditing;
    });
  }

  void _saveProfile() async {
    if (_formKey.currentState!.validate()) {
      final user = ref.read(authStateProvider).user;
      if (user != null) {
        final service = ref.read(userProfileServiceProvider);
        final profile = await service.getUserProfile(user.id);
        await service.updateUserProfile(
          user.id,
          profile.copyWith(
            name: _nameController.text,
            email: _emailController.text,
            phoneNumber: _phoneController.text,
          ),
        );
      }
      if (!mounted) return;
      setState(() {
        _isEditing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile details updated.'),
          backgroundColor: AppTheme.successColor,
        ),
      );
    }
  }

  void _showInfoDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0C152B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFF1E293B)),
        ),
        title: Text(
          title,
          style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: Text(
          message,
          style: GoogleFonts.plusJakartaSans(color: Colors.white70, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK', style: GoogleFonts.spaceGrotesk(color: AppTheme.primaryColor, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _changeProfilePicture() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0C152B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'UPDATE AVATAR SOURCE',
                    style: GoogleFonts.spaceGrotesk(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
                const Divider(color: Color(0xFF1E293B)),
                ListTile(
                  leading: const Icon(Icons.camera_alt_outlined, color: AppTheme.primaryColor),
                  title: Text('CAMERA CAPTURE', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                  onTap: () async {
                    Navigator.pop(context);
                    final picker = ImagePicker();
                    final image = await picker.pickImage(source: ImageSource.camera);
                    if (image != null && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Photo captured.'),
                          backgroundColor: AppTheme.successColor,
                        ),
                      );
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_outlined, color: AppTheme.primaryColor),
                  title: Text('GALLERY DIRECTORY', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                  onTap: () async {
                    Navigator.pop(context);
                    final picker = ImagePicker();
                    final image = await picker.pickImage(source: ImageSource.gallery);
                    if (image != null && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Photo selected.'),
                          backgroundColor: AppTheme.successColor,
                        ),
                      );
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: AppTheme.errorColor),
                  title: Text('REMOVE AVATAR', style: GoogleFonts.spaceGrotesk(color: AppTheme.errorColor, fontSize: 12, fontWeight: FontWeight.bold)),
                  onTap: () {
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showDeleteAccountDialog() {
    final isGuest = ref.read(authStateProvider).user?.id == 'guest';
    if (isGuest) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF0C152B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFF1E293B)),
          ),
          title: Text(
            'RESTRICTED OPERATION',
            style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          content: Text(
            'Guest sessions are temporary and cannot trigger account termination requests. Sign in with Google to configure account parameters.',
            style: GoogleFonts.plusJakartaSans(color: Colors.white70, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('OK', style: GoogleFonts.spaceGrotesk(color: AppTheme.primaryColor, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0C152B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFF1E293B)),
          ),
          title: Text(
            'DELETE ACCOUNT',
            style: GoogleFonts.spaceGrotesk(color: AppTheme.errorColor, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          content: Text(
            'Are you sure you want to permanently delete your account? All encrypted cards, ledgers, and statement data will be unrecoverably erased from the server.',
            style: GoogleFonts.plusJakartaSans(color: Colors.white70, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('CANCEL', style: GoogleFonts.spaceGrotesk(color: Colors.white70)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Termination request logged.'),
                    backgroundColor: AppTheme.successColor,
                  ),
                );
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorColor),
              child: Text('TERMINATE', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.bold)),
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
          backgroundColor: const Color(0xFF0C152B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFF1E293B)),
          ),
          title: Text(
            'DESTROY ACTIVE SESSION',
            style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          content: Text(
            'Are you sure you want to destroy your current session? You will be logged out of this device.',
            style: GoogleFonts.plusJakartaSans(color: Colors.white70, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('CANCEL', style: GoogleFonts.spaceGrotesk(color: Colors.white70)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                ref.read(authStateProvider.notifier).signOut();
                Navigator.pushReplacementNamed(context, '/login');
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorColor),
              child: Text('SIGN OUT', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }
}
