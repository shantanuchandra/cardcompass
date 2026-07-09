import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cardcompass/core/providers/service_providers.dart';

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
  bool _biometricAuth = false;
  bool _autoSync = true;
  String _currency = 'INR';
  String _language = 'English';

  @override
  void initState() {
    super.initState();
    final prefs = ref.read(appPreferencesProvider);
    _notificationsEnabled = prefs.notificationsEnabled;
    _biometricAuth = prefs.biometricEnabled;
    _autoSync = prefs.autoSyncEnabled;
    _language = prefs.language;
    _currency = prefs.currency;
  }

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
                  ref.read(appPreferencesProvider).setNotificationsEnabled(value);
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
                  ref.read(appPreferencesProvider).setBiometricEnabled(value);
                },
              ),
              ListTile(
                title: const Text('Change Password'),
                subtitle: const Text('Update your account password'),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () => _showUnavailableDialog(
                  'Change Password',
                  'Password changes require a signed-in Google account. This isn\'t available in guest mode or for the current build.',
                ),
              ),
              ListTile(
                title: const Text('Two-Factor Authentication'),
                subtitle: const Text('Add an extra layer of security'),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () => _showUnavailableDialog(
                  'Two-Factor Authentication',
                  '2FA setup requires a connected backend account and isn\'t available yet.',
                ),
              ),
            ],
          ),

          // Appearance Section
          _buildSection(
            'Appearance',
            [
              SwitchListTile(
                title: const Text('Dark Mode'),
                subtitle: const Text('Follows your device setting'),
                value: Theme.of(context).brightness == Brightness.dark,
                onChanged: null,
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
                  ref.read(appPreferencesProvider).setAutoSyncEnabled(value);
                },
              ),
              ListTile(
                title: const Text('Backup Data'),
                subtitle: const Text('Create a backup of your data'),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () => _showUnavailableDialog(
                  'Backup Data',
                  'Cloud backup isn\'t available right now. Your data stays on this device.',
                ),
              ),
              ListTile(
                title: const Text('Export Data'),
                subtitle: const Text('Export your data as CSV/PDF'),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () => _showUnavailableDialog(
                  'Export Data',
                  'CSV/PDF export isn\'t available yet in this build.',
                ),
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
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('You are using the latest version')),
                  );
                },
              ),
              ListTile(
                title: const Text('Feedback'),
                subtitle: const Text('Send feedback to developers'),
                trailing: const Icon(Icons.feedback),
                onTap: () => _showUnavailableDialog(
                  'Feedback',
                  'In-app feedback isn\'t wired up yet. Please reach out to the team directly.',
                ),
              ),
              ListTile(
                title: const Text('Rate App'),
                subtitle: const Text('Rate us on the app store'),
                trailing: const Icon(Icons.star),
                onTap: () => _showUnavailableDialog(
                  'Rate App',
                  'This build isn\'t distributed through an app store yet.',
                ),
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

  void _showUnavailableDialog(String feature, String reason) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(feature),
        content: Text(reason),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
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
                  ref.read(appPreferencesProvider).setLanguage(language);
                  Navigator.pop(context);
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
                  ref.read(appPreferencesProvider).setCurrency(_currency);
                  Navigator.pop(context);
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
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('There is no cache to clear in this build')),
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
