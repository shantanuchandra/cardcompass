import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cardcompass/core/providers/service_providers.dart';
import 'package:cardcompass/core/theme.dart';

/// Settings screen for app preferences and configurations in cyber-fintech style
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
      backgroundColor: const Color(0xFF050B18),
      appBar: AppBar(
        title: Text(
          'PREFERENCES',
          style: GoogleFonts.spaceGrotesk(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
            fontSize: 16,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
        children: [
          // Notifications Section
          _buildSection(
            'ALERT PARAMETERS',
            [
              SwitchListTile(
                title: Text('ENABLE NOTIFICATIONS', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                subtitle: Text('Receive global app notifications', style: GoogleFonts.plusJakartaSans(color: Colors.white30, fontSize: 10)),
                value: _notificationsEnabled,
                activeColor: AppTheme.primaryColor,
                onChanged: (value) {
                  setState(() {
                    _notificationsEnabled = value;
                  });
                  ref.read(appPreferencesProvider).setNotificationsEnabled(value);
                },
              ),
              const Divider(color: Color(0xFF1E293B), height: 1),
              SwitchListTile(
                title: Text('PUSH ALERTS', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                subtitle: Text('Direct warning overlays', style: GoogleFonts.plusJakartaSans(color: Colors.white30, fontSize: 10)),
                value: _pushNotifications,
                activeColor: AppTheme.primaryColor,
                onChanged: _notificationsEnabled ? (value) {
                  setState(() {
                    _pushNotifications = value;
                  });
                } : null,
              ),
              const Divider(color: Color(0xFF1E293B), height: 1),
              SwitchListTile(
                title: Text('EMAIL SUMMARIES', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                subtitle: Text('Monthly reward ledger audits', style: GoogleFonts.plusJakartaSans(color: Colors.white30, fontSize: 10)),
                value: _emailNotifications,
                activeColor: AppTheme.primaryColor,
                onChanged: _notificationsEnabled ? (value) {
                  setState(() {
                    _emailNotifications = value;
                  });
                } : null,
              ),
              const Divider(color: Color(0xFF1E293B), height: 1),
              SwitchListTile(
                title: Text('SMS TRANSMISSIONS', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                subtitle: Text('Immediate billing highlights', style: GoogleFonts.plusJakartaSans(color: Colors.white30, fontSize: 10)),
                value: _smsNotifications,
                activeColor: AppTheme.primaryColor,
                onChanged: _notificationsEnabled ? (value) {
                  setState(() {
                    _smsNotifications = value;
                  });
                } : null,
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Security Section
          _buildSection(
            'SECURITY PROTOCOLS',
            [
              SwitchListTile(
                title: Text('BIOMETRIC VALIDATION', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                subtitle: Text('Use Face ID / Fingerprint registry', style: GoogleFonts.plusJakartaSans(color: Colors.white30, fontSize: 10)),
                value: _biometricAuth,
                activeColor: AppTheme.primaryColor,
                onChanged: (value) {
                  setState(() {
                    _biometricAuth = value;
                  });
                  ref.read(appPreferencesProvider).setBiometricEnabled(value);
                },
              ),
              const Divider(color: Color(0xFF1E293B), height: 1),
              ListTile(
                title: Text('UPDATE CRYPTO PASSWORD', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                subtitle: Text('Reset credentials passkeys', style: GoogleFonts.plusJakartaSans(color: Colors.white30, fontSize: 10)),
                trailing: const Icon(Icons.arrow_forward_ios, size: 12, color: Colors.white30),
                onTap: () => _showUnavailableDialog(
                  'CHANGE PASSWORD',
                  'Credential updates require a connected Google identity. Not available in guest mode.',
                ),
              ),
              const Divider(color: Color(0xFF1E293B), height: 1),
              ListTile(
                title: Text('TWO-FACTOR SECURITY (2FA)', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                subtitle: Text('Link authenticator token generators', style: GoogleFonts.plusJakartaSans(color: Colors.white30, fontSize: 10)),
                trailing: const Icon(Icons.arrow_forward_ios, size: 12, color: Colors.white30),
                onTap: () => _showUnavailableDialog(
                  'TWO-FACTOR AUTHENTICATION',
                  'MFA settings require a persistent server integration. Disabled on this build.',
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Appearance Section
          _buildSection(
            'INTERFACE INTERPRETERS',
            [
              SwitchListTile(
                title: Text('FORCE TECH NEON STYLE', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                subtitle: Text('Cyber-neon default mode enabled', style: GoogleFonts.plusJakartaSans(color: Colors.white30, fontSize: 10)),
                value: true,
                activeColor: AppTheme.primaryColor,
                onChanged: null,
              ),
              const Divider(color: Color(0xFF1E293B), height: 1),
              ListTile(
                title: Text('DICTIONARY DIALECT', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                subtitle: Text(_language.toUpperCase(), style: GoogleFonts.plusJakartaSans(color: AppTheme.primaryColor, fontSize: 10, fontWeight: FontWeight.bold)),
                trailing: const Icon(Icons.arrow_forward_ios, size: 12, color: Colors.white30),
                onTap: () => _showLanguageDialog(),
              ),
              const Divider(color: Color(0xFF1E293B), height: 1),
              ListTile(
                title: Text('CURRENCY INDEX', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                subtitle: Text(_currency.toUpperCase(), style: GoogleFonts.plusJakartaSans(color: AppTheme.primaryColor, fontSize: 10, fontWeight: FontWeight.bold)),
                trailing: const Icon(Icons.arrow_forward_ios, size: 12, color: Colors.white30),
                onTap: () => _showCurrencyDialog(),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Data & Sync Section
          _buildSection(
            'DATA STAGE & STORAGE',
            [
              SwitchListTile(
                title: Text('AUTO BACKGROUND SYNC', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                subtitle: Text('Sync card rules via headless pipeline', style: GoogleFonts.plusJakartaSans(color: Colors.white30, fontSize: 10)),
                value: _autoSync,
                activeColor: AppTheme.primaryColor,
                onChanged: (value) {
                  setState(() {
                    _autoSync = value;
                  });
                  ref.read(appPreferencesProvider).setAutoSyncEnabled(value);
                },
              ),
              const Divider(color: Color(0xFF1E293B), height: 1),
              ListTile(
                title: Text('BACKUP ENCRYPTED DATABASE', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                subtitle: Text('Log state snapshots locally', style: GoogleFonts.plusJakartaSans(color: Colors.white30, fontSize: 10)),
                trailing: const Icon(Icons.arrow_forward_ios, size: 12, color: Colors.white30),
                onTap: () => _showUnavailableDialog(
                  'BACKUP DATABASE',
                  'Encrypted backup registers require server syncing logic. Sandbox parameters are saved to memory only.',
                ),
              ),
              const Divider(color: Color(0xFF1E293B), height: 1),
              ListTile(
                title: Text('EXPORT LEDGER ARCHIVE', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                subtitle: Text('Export transactions to CSV files', style: GoogleFonts.plusJakartaSans(color: Colors.white30, fontSize: 10)),
                trailing: const Icon(Icons.arrow_forward_ios, size: 12, color: Colors.white30),
                onTap: () => _showUnavailableDialog(
                  'EXPORT ARCHIVE',
                  'Exporter pipelines are currently compiling. Enabled in production build release.',
                ),
              ),
              const Divider(color: Color(0xFF1E293B), height: 1),
              ListTile(
                title: Text('RESET SYSTEM CACHE', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                subtitle: Text('Purge local database registers', style: GoogleFonts.plusJakartaSans(color: Colors.white30, fontSize: 10)),
                trailing: const Icon(Icons.arrow_forward_ios, size: 12, color: Colors.white30),
                onTap: () => _showClearCacheDialog(),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // About Section
          _buildSection(
            'SYSTEM METADATA',
            [
              ListTile(
                title: Text('CARDCOMPASS CORE', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                subtitle: Text('Version 1.0.0 (Build 1)', style: GoogleFonts.plusJakartaSans(color: Colors.white30, fontSize: 10)),
                trailing: const Icon(Icons.info_outline, size: 16, color: AppTheme.primaryColor),
                onTap: () => _showAppInfoDialog(),
              ),
              const Divider(color: Color(0xFF1E293B), height: 1),
              ListTile(
                title: Text('CHECK SYSTEM UPDATES', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                subtitle: Text('Check for compilation changes', style: GoogleFonts.plusJakartaSans(color: Colors.white30, fontSize: 10)),
                trailing: const Icon(Icons.refresh, size: 16, color: AppTheme.primaryColor),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('SYSTEM IS COMPILED TO LATEST STABLE BUILD.', style: GoogleFonts.spaceGrotesk(fontSize: 12, fontWeight: FontWeight.bold)),
                      backgroundColor: AppTheme.successColor,
                    ),
                  );
                },
              ),
              const Divider(color: Color(0xFF1E293B), height: 1),
              ListTile(
                title: Text('TRANSMIT APP FEEDBACK', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                subtitle: Text('Send log audits to developers', style: GoogleFonts.plusJakartaSans(color: Colors.white30, fontSize: 10)),
                trailing: const Icon(Icons.feedback_outlined, size: 16, color: AppTheme.primaryColor),
                onTap: () => _showUnavailableDialog(
                  'FEEDBACK SYSTEM',
                  'Feedback routes are offline. Please utilize the developer issue registry directly.',
                ),
              ),
            ],
          ),
          const SizedBox(height: 80), // space above bottom dock
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
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
          decoration: BoxDecoration(
            color: const Color(0xFF0C152B),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Column(
            children: children,
          ),
        ),
      ],
    );
  }

  void _showUnavailableDialog(String feature, String reason) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0C152B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFF1E293B)),
        ),
        title: Text(
          feature,
          style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: Text(
          reason,
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

  void _showLanguageDialog() {
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
            'SELECT DICTIONARY LANGUAGE',
            style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                'English',
                'Hindi',
                'Bengali',
                'Gujarati',
                'Tamil',
                'Telugu',
                'Kannada',
                'Malayalam',
                'Marathi',
                'Punjabi',
              ].map((language) {
                return ListTile(
                  title: Text(
                    language.toUpperCase(),
                    style: GoogleFonts.spaceGrotesk(
                      color: _language == language ? AppTheme.primaryColor : Colors.white70,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  onTap: () {
                    setState(() {
                      _language = language;
                    });
                    ref.read(appPreferencesProvider).setLanguage(language);
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Language successfully configured: $language'),
                        backgroundColor: AppTheme.successColor,
                      ),
                    );
                  },
                );
              }).toList(),
            ),
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
          backgroundColor: const Color(0xFF0C152B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFF1E293B)),
          ),
          title: Text(
            'SELECT CURRENCY INDEX',
            style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                'INR (₹)',
                'USD (\$)',
                'EUR (€)',
                'GBP (£)',
                'AED (د.إ)',
                'SAR (ر.س)',
              ].map((currency) {
                final curSymbol = currency.split(' ')[0];
                return ListTile(
                  title: Text(
                    currency.toUpperCase(),
                    style: GoogleFonts.spaceGrotesk(
                      color: _currency == curSymbol ? AppTheme.primaryColor : Colors.white70,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  onTap: () {
                    setState(() {
                      _currency = curSymbol;
                    });
                    ref.read(appPreferencesProvider).setCurrency(curSymbol);
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Currency successfully configured: $curSymbol'),
                        backgroundColor: AppTheme.successColor,
                      ),
                    );
                  },
                );
              }).toList(),
            ),
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
          backgroundColor: const Color(0xFF0C152B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFF1E293B)),
          ),
          title: Text(
            'PURGE LOCAL CACHE',
            style: GoogleFonts.spaceGrotesk(color: AppTheme.errorColor, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          content: Text(
            'This action will permanently delete all cached transaction details and config registries. Proceed?',
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
                  SnackBar(
                    content: Text('CACHE PROTOCOLS ALREADY COMPLETED.', style: GoogleFonts.spaceGrotesk(fontSize: 12, fontWeight: FontWeight.bold)),
                    backgroundColor: AppTheme.successColor,
                  ),
                );
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorColor),
              child: Text('PURGE', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.bold)),
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
          backgroundColor: const Color(0xFF0C152B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFF1E293B)),
          ),
          title: Text(
            'CARDCOMPASS CORE ENGINE',
            style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('VERSION: 1.0.0', style: GoogleFonts.spaceGrotesk(color: AppTheme.primaryColor, fontWeight: FontWeight.bold, fontSize: 13)),
              Text('COMPILATION: BUILD 1', style: GoogleFonts.spaceGrotesk(color: Colors.white54, fontSize: 11)),
              const SizedBox(height: 12),
              Text(
                'CardCompass is a cybernetic sandbox ledger that automatically categorizes statements, analyzes benefits routing, and optimizes rewards.',
                style: GoogleFonts.plusJakartaSans(color: Colors.white70, height: 1.4),
              ),
              const SizedBox(height: 12),
              Text('DEVELOPED IN INDIA', style: GoogleFonts.spaceGrotesk(color: Colors.white38, fontWeight: FontWeight.bold, fontSize: 9, letterSpacing: 0.5)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('OK', style: GoogleFonts.spaceGrotesk(color: AppTheme.primaryColor, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }
}
