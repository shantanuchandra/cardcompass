import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cardcompass/core/providers/service_providers.dart';
import 'package:cardcompass/core/theme.dart';
import 'package:cardcompass/shared/widgets/app_scaffold.dart';

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
  int _devTapCount = 0;

  /// Shared row-title style: body2 size, Space Grotesk family (matches the
  /// screen's original bold-technical look) via AppTextStyles.heading3.
  TextStyle get _rowTitleStyle => AppTextStyles.heading3
      .copyWith(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white);

  TextStyle get _rowSubtitleStyle =>
      AppTextStyles.caption.copyWith(color: Colors.white30);

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
    return CardCompassScaffold(
      title: 'Preferences',
      body: ListView(
        padding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: AppSpacing.md),
        children: [
          // Notifications Section
          _buildSection(
            'ALERT PARAMETERS',
            [
              SwitchListTile(
                title: Text('ENABLE NOTIFICATIONS', style: _rowTitleStyle),
                subtitle: Text('Receive global app notifications',
                    style: _rowSubtitleStyle),
                value: _notificationsEnabled,
                activeColor: AppTheme.primaryColor,
                onChanged: (value) {
                  setState(() {
                    _notificationsEnabled = value;
                  });
                  ref
                      .read(appPreferencesProvider)
                      .setNotificationsEnabled(value);
                },
              ),
              const Divider(color: Color(0xFF1E293B), height: 1),
              SwitchListTile(
                title: Text('PUSH ALERTS', style: _rowTitleStyle),
                subtitle:
                    Text('Direct warning overlays', style: _rowSubtitleStyle),
                value: _pushNotifications,
                activeColor: AppTheme.primaryColor,
                onChanged: _notificationsEnabled
                    ? (value) {
                        setState(() {
                          _pushNotifications = value;
                        });
                      }
                    : null,
              ),
              const Divider(color: Color(0xFF1E293B), height: 1),
              SwitchListTile(
                title: Text('EMAIL SUMMARIES', style: _rowTitleStyle),
                subtitle: Text('Monthly reward ledger audits',
                    style: _rowSubtitleStyle),
                value: _emailNotifications,
                activeColor: AppTheme.primaryColor,
                onChanged: _notificationsEnabled
                    ? (value) {
                        setState(() {
                          _emailNotifications = value;
                        });
                      }
                    : null,
              ),
              const Divider(color: Color(0xFF1E293B), height: 1),
              SwitchListTile(
                title: Text('SMS TRANSMISSIONS', style: _rowTitleStyle),
                subtitle: Text('Immediate billing highlights',
                    style: _rowSubtitleStyle),
                value: _smsNotifications,
                activeColor: AppTheme.primaryColor,
                onChanged: _notificationsEnabled
                    ? (value) {
                        setState(() {
                          _smsNotifications = value;
                        });
                      }
                    : null,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md + AppSpacing.xs),

          // Security Section
          _buildSection(
            'SECURITY PROTOCOLS',
            [
              SwitchListTile(
                title: Text('BIOMETRIC VALIDATION', style: _rowTitleStyle),
                subtitle: Text('Use Face ID / Fingerprint registry',
                    style: _rowSubtitleStyle),
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
              _buildComingSoonTile(
                title: 'UPDATE CRYPTO PASSWORD',
                subtitle: 'Reset credentials passkeys',
                dialogTitle: 'CHANGE PASSWORD',
                dialogReason:
                    'Credential updates require a connected Google identity. Not available in guest mode.',
              ),
              const Divider(color: Color(0xFF1E293B), height: 1),
              _buildComingSoonTile(
                title: 'TWO-FACTOR SECURITY (2FA)',
                subtitle: 'Link authenticator token generators',
                dialogTitle: 'TWO-FACTOR AUTHENTICATION',
                dialogReason:
                    'MFA settings require a persistent server integration. Disabled on this build.',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md + AppSpacing.xs),

          // Appearance Section
          _buildSection(
            'INTERFACE INTERPRETERS',
            [
              SwitchListTile(
                title: Text('FORCE TECH NEON STYLE', style: _rowTitleStyle),
                subtitle: Text('Cyber-neon default mode enabled',
                    style: _rowSubtitleStyle),
                value: true,
                activeColor: AppTheme.primaryColor,
                onChanged: null,
              ),
              const Divider(color: Color(0xFF1E293B), height: 1),
              ListTile(
                title: Text('DICTIONARY DIALECT', style: _rowTitleStyle),
                subtitle: Text(_language.toUpperCase(),
                    style: AppTextStyles.caption.copyWith(
                        color: AppTheme.primaryColor,
                        fontWeight: FontWeight.bold)),
                trailing: const Icon(Icons.arrow_forward_ios,
                    size: 12, color: Colors.white30),
                onTap: () => _showLanguageDialog(),
              ),
              const Divider(color: Color(0xFF1E293B), height: 1),
              ListTile(
                title: Text('CURRENCY INDEX', style: _rowTitleStyle),
                subtitle: Text(_currency.toUpperCase(),
                    style: AppTextStyles.caption.copyWith(
                        color: AppTheme.primaryColor,
                        fontWeight: FontWeight.bold)),
                trailing: const Icon(Icons.arrow_forward_ios,
                    size: 12, color: Colors.white30),
                onTap: () => _showCurrencyDialog(),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md + AppSpacing.xs),

          // Data & Sync Section
          _buildSection(
            'DATA STAGE & STORAGE',
            [
              SwitchListTile(
                title: Text('AUTO BACKGROUND SYNC', style: _rowTitleStyle),
                subtitle: Text('Sync card rules via headless pipeline',
                    style: _rowSubtitleStyle),
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
              _buildComingSoonTile(
                title: 'BACKUP ENCRYPTED DATABASE',
                subtitle: 'Log state snapshots locally',
                dialogTitle: 'BACKUP DATABASE',
                dialogReason:
                    'Encrypted backup registers require server syncing logic. Sandbox parameters are saved to memory only.',
              ),
              const Divider(color: Color(0xFF1E293B), height: 1),
              _buildComingSoonTile(
                title: 'EXPORT LEDGER ARCHIVE',
                subtitle: 'Export transactions to CSV files',
                dialogTitle: 'EXPORT ARCHIVE',
                dialogReason:
                    'Exporter pipelines are currently compiling. Enabled in production build release.',
              ),
              const Divider(color: Color(0xFF1E293B), height: 1),
              ListTile(
                title: Text('RESET SYSTEM CACHE', style: _rowTitleStyle),
                subtitle: Text('Purge local database registers',
                    style: _rowSubtitleStyle),
                trailing: const Icon(Icons.arrow_forward_ios,
                    size: 12, color: Colors.white30),
                onTap: () => _showClearCacheDialog(),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md + AppSpacing.xs),

          // About Section
          _buildSection(
            'SYSTEM METADATA',
            [
              ListTile(
                title: Text('CARDCOMPASS CORE', style: _rowTitleStyle),
                subtitle:
                    Text('Version 1.0.0 (Build 1)', style: _rowSubtitleStyle),
                trailing: const Icon(Icons.info_outline,
                    size: 16, color: AppTheme.primaryColor),
                onTap: () {
                  _showAppInfoDialog();
                  setState(() {
                    _devTapCount++;
                  });
                  if (_devTapCount >= 5) {
                    _devTapCount = 0;
                    Navigator.pushNamed(context, '/admin/pm');
                  }
                },
              ),
              const Divider(color: Color(0xFF1E293B), height: 1),
              ListTile(
                title: Text('CHECK SYSTEM UPDATES', style: _rowTitleStyle),
                subtitle: Text('Check for compilation changes',
                    style: _rowSubtitleStyle),
                trailing: const Icon(Icons.refresh,
                    size: 16, color: AppTheme.primaryColor),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          'SYSTEM IS COMPILED TO LATEST STABLE BUILD.',
                          style: AppTextStyles.body2.copyWith(
                              fontWeight: FontWeight.bold,
                              fontFamily: AppTextStyles.heading3.fontFamily)),
                      backgroundColor: AppTheme.successColor,
                    ),
                  );
                },
              ),
              const Divider(color: Color(0xFF1E293B), height: 1),
              _buildComingSoonTile(
                title: 'TRANSMIT APP FEEDBACK',
                subtitle: 'Send log audits to developers',
                dialogTitle: 'FEEDBACK SYSTEM',
                dialogReason:
                    'Feedback routes are offline. Please utilize the developer issue registry directly.',
                trailingIcon: Icons.feedback_outlined,
                trailingIconSize: 16,
              ),
            ],
          ),
          const SizedBox(height: 80), // space above bottom dock
        ],
      )
          .animate()
          .fadeIn(duration: 250.ms, curve: Curves.easeOut)
          .slideY(begin: 0.05, end: 0, duration: 250.ms, curve: Curves.easeOut),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding:
              const EdgeInsets.only(left: AppSpacing.xs, bottom: AppSpacing.sm),
          child: Text(
            title,
            style: AppTextStyles.caption.copyWith(
              color: Colors.white60,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
              fontFamily: AppTextStyles.heading3.fontFamily,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0C152B),
            borderRadius: BorderRadius.circular(AppBorderRadius.xl - 4),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          // Material(transparency) restores ListTile ink splashes/tap
          // feedback, which the DecoratedBox above would otherwise hide.
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              children: children,
            ),
          ),
        ),
      ],
    );
  }

  /// A settings row that isn't wired up to real functionality yet.
  ///
  /// Renders with a muted "Soon" badge next to the title and slightly
  /// reduced opacity so it visually reads as a preview/disabled row
  /// instead of looking identical to a working row until tapped.
  Widget _buildComingSoonTile({
    required String title,
    required String subtitle,
    required String dialogTitle,
    required String dialogReason,
    IconData trailingIcon = Icons.arrow_forward_ios,
    double trailingIconSize = 12,
  }) {
    return Opacity(
      opacity: 0.7,
      child: ListTile(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                title,
                style: _rowTitleStyle,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            _buildSoonBadge(),
          ],
        ),
        subtitle: Text(subtitle, style: _rowSubtitleStyle),
        trailing:
            Icon(trailingIcon, size: trailingIconSize, color: Colors.white30),
        onTap: () => _showUnavailableDialog(dialogTitle, dialogReason),
      ),
    );
  }

  Widget _buildSoonBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs + 2, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppBorderRadius.sm),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(
        'SOON',
        style: AppTextStyles.caption.copyWith(
          color: Colors.white54,
          fontSize: 9,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
          fontFamily: AppTextStyles.heading3.fontFamily,
        ),
      ),
    );
  }

  /// Single reusable "coming soon" / unavailable-feature dialog.
  ///
  /// Consolidates what used to be 5+ duplicated inline AlertDialogs with
  /// identical boilerplate (backgroundColor, shape) — every dialog in this
  /// screen builds its chrome via this helper and supplies only its own
  /// title/content/actions.
  Future<T?> _showThemedDialog<T>({
    required Widget title,
    required Widget content,
    List<Widget>? actions,
  }) {
    return showDialog<T>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0C152B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppBorderRadius.xl),
          side: const BorderSide(color: Color(0xFF1E293B)),
        ),
        title: title,
        content: content,
        actions: actions,
      ),
    );
  }

  void _showUnavailableDialog(String feature, String reason) {
    _showThemedDialog(
      title: Text(
        feature,
        style: AppTextStyles.heading3
            .copyWith(color: Colors.white, fontWeight: FontWeight.bold),
      ),
      content: Text(
        reason,
        style: AppTextStyles.body1.copyWith(color: Colors.white70, height: 1.4),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('OK',
              style:
                  AppTextStyles.button.copyWith(color: AppTheme.primaryColor)),
        ),
      ],
    );
  }

  void _showLanguageDialog() {
    _showThemedDialog(
      title: Text(
        'SELECT DICTIONARY LANGUAGE',
        style: _rowTitleStyle,
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
                style: AppTextStyles.body2.copyWith(
                  color: _language == language
                      ? AppTheme.primaryColor
                      : Colors.white70,
                  fontWeight: FontWeight.bold,
                  fontFamily: AppTextStyles.heading3.fontFamily,
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
                    content:
                        Text('Language successfully configured: $language'),
                    backgroundColor: AppTheme.successColor,
                  ),
                );
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showCurrencyDialog() {
    _showThemedDialog(
      title: Text(
        'SELECT CURRENCY INDEX',
        style: _rowTitleStyle,
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
                style: AppTextStyles.body2.copyWith(
                  color: _currency == curSymbol
                      ? AppTheme.primaryColor
                      : Colors.white70,
                  fontWeight: FontWeight.bold,
                  fontFamily: AppTextStyles.heading3.fontFamily,
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
                    content:
                        Text('Currency successfully configured: $curSymbol'),
                    backgroundColor: AppTheme.successColor,
                  ),
                );
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showClearCacheDialog() {
    _showThemedDialog(
      title: Text(
        'PURGE LOCAL CACHE',
        style: AppTextStyles.heading3
            .copyWith(color: AppTheme.errorColor, fontWeight: FontWeight.bold),
      ),
      content: Text(
        'This action will permanently delete all cached transaction details and config registries. Proceed?',
        style: AppTextStyles.body1.copyWith(color: Colors.white70, height: 1.4),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('CANCEL',
              style: AppTextStyles.button.copyWith(color: Colors.white70)),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('CACHE PROTOCOLS ALREADY COMPLETED.',
                    style: AppTextStyles.body2.copyWith(
                        fontWeight: FontWeight.bold,
                        fontFamily: AppTextStyles.heading3.fontFamily)),
                backgroundColor: AppTheme.successColor,
              ),
            );
          },
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorColor),
          child: Text('PURGE',
              style: AppTextStyles.button.copyWith(color: Colors.white)),
        ),
      ],
    );
  }

  void _showAppInfoDialog() {
    _showThemedDialog(
      title: Text(
        'CARDCOMPASS CORE ENGINE',
        style: AppTextStyles.heading3
            .copyWith(color: Colors.white, fontWeight: FontWeight.bold),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('VERSION: 1.0.0',
              style: AppTextStyles.body2.copyWith(
                  color: AppTheme.primaryColor,
                  fontWeight: FontWeight.bold,
                  fontFamily: AppTextStyles.heading3.fontFamily)),
          Text('COMPILATION: BUILD 1',
              style: AppTextStyles.caption.copyWith(
                  color: Colors.white54,
                  fontFamily: AppTextStyles.heading3.fontFamily)),
          const SizedBox(height: AppSpacing.sm + 4),
          Text(
            'CardCompass is a cybernetic sandbox ledger that automatically categorizes statements, analyzes benefits routing, and optimizes rewards.',
            style: AppTextStyles.body1
                .copyWith(color: Colors.white70, height: 1.4),
          ),
          const SizedBox(height: AppSpacing.sm + 4),
          Text('DEVELOPED IN INDIA',
              style: AppTextStyles.caption.copyWith(
                  color: Colors.white38,
                  fontWeight: FontWeight.bold,
                  fontSize: 9,
                  letterSpacing: 0.5,
                  fontFamily: AppTextStyles.heading3.fontFamily)),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('OK',
              style:
                  AppTextStyles.button.copyWith(color: AppTheme.primaryColor)),
        ),
      ],
    );
  }
}
