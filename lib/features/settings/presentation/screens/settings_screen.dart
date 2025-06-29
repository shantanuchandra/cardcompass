import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Settings screen for app preferences and configurations
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _notificationsEnabled = true;
  bool _pushNotifications = true;
  bool _emailNotifications = false;
  bool _smsNotifications = false;
  bool _darkMode = false;
  bool _biometricAuth = false;
  bool _autoSync = true;
  String _currency = 'INR';
  String _language = 'English';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        elevation: 0,
      ),
      body: ListView(
        children: [
          // Notifications Section
          _buildSection(
            'Notifications',
            [
              SwitchListTile(
                title: const Text('Enable Notifications'),
                subtitle: const Text('Receive all app notifications'),
                value: _notificationsEnabled,
                onChanged: (value) {
                  setState(() {
                    _notificationsEnabled = value;
                  });
                },
              ),
              SwitchListTile(
                title: const Text('Push Notifications'),
                subtitle: const Text('Receive push notifications'),
                value: _pushNotifications,
                onChanged: _notificationsEnabled ? (value) {
                  setState(() {
                    _pushNotifications = value;
                  });
                } : null,
              ),
              SwitchListTile(
                title: const Text('Email Notifications'),
                subtitle: const Text('Receive email notifications'),
                value: _emailNotifications,
                onChanged: _notificationsEnabled ? (value) {
                  setState(() {
                    _emailNotifications = value;
                  });
                } : null,
              ),
              SwitchListTile(
                title: const Text('SMS Notifications'),
                subtitle: const Text('Receive SMS notifications'),
                value: _smsNotifications,
                onChanged: _notificationsEnabled ? (value) {
                  setState(() {
                    _smsNotifications = value;
                  });
                } : null,
              ),
            ],
          ),

          // Security Section
          _buildSection(
            'Security',
            [
              SwitchListTile(
                title: const Text('Biometric Authentication'),
                subtitle: const Text('Use fingerprint or face ID'),
                value: _biometricAuth,
                onChanged: (value) {
                  setState(() {
                    _biometricAuth = value;
                  });
                },
              ),
              ListTile(
                title: const Text('Change Password'),
                subtitle: const Text('Update your account password'),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () {
                  // TODO: Navigate to change password screen
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Change password coming soon')),
                  );
                },
              ),
              ListTile(
                title: const Text('Two-Factor Authentication'),
                subtitle: const Text('Add an extra layer of security'),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () {
                  // TODO: Navigate to 2FA setup
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('2FA setup coming soon')),
                  );
                },
              ),
            ],
          ),

          // Appearance Section
          _buildSection(
            'Appearance',
            [
              SwitchListTile(
                title: const Text('Dark Mode'),
                subtitle: const Text('Use dark theme'),
                value: _darkMode,
                onChanged: (value) {
                  setState(() {
                    _darkMode = value;
                  });
                  // TODO: Implement theme switching
                },
              ),
              ListTile(
                title: const Text('Language'),
                subtitle: Text(_language),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () => _showLanguageDialog(),
              ),
              ListTile(
                title: const Text('Currency'),
                subtitle: Text(_currency),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () => _showCurrencyDialog(),
              ),
            ],
          ),

          // Data & Sync Section
          _buildSection(
            'Data & Sync',
            [
              SwitchListTile(
                title: const Text('Auto Sync'),
                subtitle: const Text('Automatically sync data'),
                value: _autoSync,
                onChanged: (value) {
                  setState(() {
                    _autoSync = value;
                  });
                },
              ),
              ListTile(
                title: const Text('Backup Data'),
                subtitle: const Text('Create a backup of your data'),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () {
                  // TODO: Implement data backup
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Backup functionality coming soon')),
                  );
                },
              ),
              ListTile(
                title: const Text('Export Data'),
                subtitle: const Text('Export your data as CSV/PDF'),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () {
                  // TODO: Implement data export
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Export functionality coming soon')),
                  );
                },
              ),
              ListTile(
                title: const Text('Clear Cache'),
                subtitle: const Text('Clear app cache and temporary files'),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () => _showClearCacheDialog(),
              ),
            ],
          ),

          // About Section
          _buildSection(
            'About',
            [
              ListTile(
                title: const Text('App Version'),
                subtitle: const Text('1.0.0 (Build 1)'),
                trailing: const Icon(Icons.info),
                onTap: () => _showAppInfoDialog(),
              ),
              ListTile(
                title: const Text('Check for Updates'),
                subtitle: const Text('Check for app updates'),
                trailing: const Icon(Icons.system_update),
                onTap: () {
                  // TODO: Implement update check
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('You are using the latest version')),
                  );
                },
              ),
              ListTile(
                title: const Text('Feedback'),
                subtitle: const Text('Send feedback to developers'),
                trailing: const Icon(Icons.feedback),
                onTap: () {
                  // TODO: Implement feedback
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Feedback feature coming soon')),
                  );
                },
              ),
              ListTile(
                title: const Text('Rate App'),
                subtitle: const Text('Rate us on the app store'),
                trailing: const Icon(Icons.star),
                onTap: () {
                  // TODO: Implement app rating
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('App rating coming soon')),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).primaryColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(children: children),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  void _showLanguageDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Select Language'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              'English',
              'हिंदी (Hindi)',
              'বাংলা (Bengali)',
              'ગુજરાતી (Gujarati)',
              'தமிழ் (Tamil)',
              'తెలుగు (Telugu)',
              'ಕನ್ನಡ (Kannada)',
              'മലയാളം (Malayalam)',
              'मराठी (Marathi)',
              'ਪੰਜਾਬੀ (Punjabi)',
            ].map((language) {
              return ListTile(
                title: Text(language),
                onTap: () {
                  setState(() {
                    _language = language;
                  });
                  Navigator.pop(context);
                  // TODO: Implement language change
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Language changed to $language')),
                  );
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }

  void _showCurrencyDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Select Currency'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              'INR (₹)',
              'USD (\$)',
              'EUR (€)',
              'GBP (£)',
              'AED (د.إ)',
              'SAR (ر.س)',
            ].map((currency) {
              return ListTile(
                title: Text(currency),
                onTap: () {
                  setState(() {
                    _currency = currency.split(' ')[0];
                  });
                  Navigator.pop(context);
                  // TODO: Implement currency change
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Currency changed to $_currency')),
                  );
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }

  void _showClearCacheDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Clear Cache'),
          content: const Text(
            'This will clear all cached data and temporary files. Are you sure you want to continue?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                // TODO: Implement cache clearing
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Cache cleared successfully')),
                );
              },
              child: const Text('Clear'),
            ),
          ],
        );
      },
    );
  }

  void _showAppInfoDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('CardCompass'),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Version: 1.0.0'),
              Text('Build: 1'),
              SizedBox(height: 8),
              Text('CardCompass is your ultimate credit card management companion for optimizing benefits and tracking expenses.'),
              SizedBox(height: 8),
              Text('Developed with ❤️ in India'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }
}
