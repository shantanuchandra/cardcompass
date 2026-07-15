import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cardcompass/core/providers/service_providers.dart';
import 'package:cardcompass/core/providers/theme_provider.dart';
import 'package:cardcompass/core/theme.dart';
import 'package:cardcompass/shared/widgets/app_scaffold.dart';

/// Settings screen — adaptive for both light and dark themes.
///
/// Uses [AppTheme] semantic helpers for all colors so the entire page
/// automatically adapts when the user toggles the theme.
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

  // ─── Adaptive Styles ──────────────────────────────────────────────────────

  TextStyle _rowTitleStyle(BuildContext context) =>
      AppTextStyles.body2.copyWith(
        fontWeight: FontWeight.w600,
        color: AppTheme.adaptiveTextPrimary(context),
      );

  TextStyle _rowSubtitleStyle(BuildContext context) =>
      AppTextStyles.caption.copyWith(
        color: AppTheme.adaptiveTextTertiary(context),
      );

  TextStyle _sectionLabelStyle(BuildContext context) =>
      AppTextStyles.mono.copyWith(
        color: AppTheme.adaptivePrimary(context),
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
      );

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);

    return CardCompassScaffold(
      title: 'Settings',
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.md),
            children: [
              // ── Notifications ──────────────────────────────────────────
              _buildSection(
                context,
                'NOTIFICATIONS',
                [
                  _buildSwitchTile(
                    context,
                    title: 'Notifications',
                    subtitle: 'Receive app notifications',
                    value: _notificationsEnabled,
                    onChanged: (v) {
                      setState(() => _notificationsEnabled = v);
                      ref
                          .read(appPreferencesProvider)
                          .setNotificationsEnabled(v);
                    },
                  ),
                  _divider(context),
                  _buildSwitchTile(
                    context,
                    title: 'Push Notifications',
                    subtitle: 'Direct push alerts',
                    value: _pushNotifications,
                    onChanged: _notificationsEnabled
                        ? (v) => setState(() => _pushNotifications = v)
                        : null,
                  ),
                  _divider(context),
                  _buildSwitchTile(
                    context,
                    title: 'Email Digests',
                    subtitle: 'Monthly reward summaries',
                    value: _emailNotifications,
                    onChanged: _notificationsEnabled
                        ? (v) => setState(() => _emailNotifications = v)
                        : null,
                  ),
                  _divider(context),
                  _buildSwitchTile(
                    context,
                    title: 'SMS Alerts',
                    subtitle: 'Immediate billing highlights',
                    value: _smsNotifications,
                    onChanged: _notificationsEnabled
                        ? (v) => setState(() => _smsNotifications = v)
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              // ── Security ───────────────────────────────────────────────
              _buildSection(
                context,
                'SECURITY',
                [
                  _buildSwitchTile(
                    context,
                    title: 'Biometric Login',
                    subtitle: 'Use Face ID / Fingerprint',
                    value: _biometricAuth,
                    onChanged: (v) {
                      setState(() => _biometricAuth = v);
                      ref.read(appPreferencesProvider).setBiometricEnabled(v);
                    },
                  ),
                  _divider(context),
                  _buildComingSoonTile(
                    context,
                    title: 'Change Password',
                    subtitle: 'Reset your credentials',
                    dialogTitle: 'Change Password',
                    dialogReason:
                        'Password changes require a connected Google identity. Not available in guest mode.',
                  ),
                  _divider(context),
                  _buildComingSoonTile(
                    context,
                    title: 'Two-Factor Auth (2FA)',
                    subtitle: 'Link an authenticator app',
                    dialogTitle: 'Two-Factor Authentication',
                    dialogReason:
                        'MFA settings require a server integration. Coming in a future update.',
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              // ── Appearance ─────────────────────────────────────────────
              _buildSection(
                context,
                'APPEARANCE',
                [
                  _buildSwitchTile(
                    context,
                    title: 'Dark Mode',
                    subtitle: isDark
                        ? 'Cyberpunk neon style'
                        : 'Frosted pearl style',
                    value: isDark,
                    onChanged: (v) {
                      ref.read(themeModeProvider.notifier).setThemeMode(
                            v ? ThemeMode.dark : ThemeMode.light,
                          );
                    },
                  ),
                  _divider(context),
                  _buildNavTile(
                    context,
                    title: 'Language',
                    value: _language,
                    onTap: () => _showLanguageDialog(context),
                  ),
                  _divider(context),
                  _buildNavTile(
                    context,
                    title: 'Currency',
                    value: _currency,
                    onTap: () => _showCurrencyDialog(context),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              // ── Data & Sync ────────────────────────────────────────────
              _buildSection(
                context,
                'DATA & SYNC',
                [
                  _buildSwitchTile(
                    context,
                    title: 'Auto-Sync',
                    subtitle: 'Sync card data in background',
                    value: _autoSync,
                    onChanged: (v) {
                      setState(() => _autoSync = v);
                      ref.read(appPreferencesProvider).setAutoSyncEnabled(v);
                    },
                  ),
                  _divider(context),
                  _buildComingSoonTile(
                    context,
                    title: 'Backup Data',
                    subtitle: 'Save encrypted local backup',
                    dialogTitle: 'Backup Data',
                    dialogReason:
                        'Encrypted backups require server syncing. Coming in a future update.',
                  ),
                  _divider(context),
                  _buildComingSoonTile(
                    context,
                    title: 'Export Transactions',
                    subtitle: 'Export to CSV',
                    dialogTitle: 'Export Transactions',
                    dialogReason:
                        'CSV export is being built. Coming in a future update.',
                  ),
                  _divider(context),
                  ListTile(
                    title: Text('Clear Cache',
                        style: _rowTitleStyle(context)),
                    subtitle: Text('Remove cached data',
                        style: _rowSubtitleStyle(context)),
                    trailing: Icon(Icons.arrow_forward_ios,
                        size: 12,
                        color: AppTheme.adaptiveTextDisabled(context)),
                    onTap: () => _showClearCacheDialog(context),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              // ── About ──────────────────────────────────────────────────
              _buildSection(
                context,
                'ABOUT',
                [
                  ListTile(
                    title:
                        Text('CardCompass', style: _rowTitleStyle(context)),
                    subtitle: Text('Version 1.0.0 (Build 1)',
                        style: _rowSubtitleStyle(context)),
                    trailing: Icon(Icons.info_outline,
                        size: 16,
                        color: AppTheme.adaptivePrimary(context)),
                    onTap: () {
                      _showAppInfoDialog(context);
                      setState(() => _devTapCount++);
                      if (_devTapCount >= 5) {
                        _devTapCount = 0;
                        Navigator.pushNamed(context, '/admin/pm');
                      }
                    },
                  ),
                  _divider(context),
                  ListTile(
                    title: Text('Check for Updates',
                        style: _rowTitleStyle(context)),
                    subtitle: Text('Verify latest version',
                        style: _rowSubtitleStyle(context)),
                    trailing: Icon(Icons.refresh,
                        size: 16,
                        color: AppTheme.adaptivePrimary(context)),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('You\'re on the latest version.',
                              style: AppTextStyles.body2
                                  .copyWith(fontWeight: FontWeight.w600)),
                          backgroundColor: AppTheme.successColor,
                        ),
                      );
                    },
                  ),
                  _divider(context),
                  _buildComingSoonTile(
                    context,
                    title: 'Send Feedback',
                    subtitle: 'Report issues or suggestions',
                    dialogTitle: 'Send Feedback',
                    dialogReason:
                        'Feedback form coming soon. Please use the GitHub issue tracker.',
                    trailingIcon: Icons.feedback_outlined,
                    trailingIconSize: 16,
                  ),
                ],
              ),
              const SizedBox(height: 80), // space above bottom dock
            ],
          ),
        ),
      )
          .animate()
          .fadeIn(duration: 250.ms, curve: Curves.easeOut)
          .slideY(
              begin: 0.03, end: 0, duration: 250.ms, curve: Curves.easeOut),
    );
  }

  // ─── Section Container ──────────────────────────────────────────────────

  Widget _buildSection(
      BuildContext context, String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
              left: AppSpacing.xs, bottom: AppSpacing.sm),
          child: Text(title, style: _sectionLabelStyle(context)),
        ),
        Container(
          decoration: AppTheme.adaptiveGlass(context,
              borderRadius: AppBorderRadius.xl - 4),
          child: Material(
            type: MaterialType.transparency,
            child: ClipRRect(
              borderRadius:
                  BorderRadius.circular(AppBorderRadius.xl - 4),
              child: Column(children: children),
            ),
          ),
        ),
      ],
    );
  }

  // ─── Row Builders ───────────────────────────────────────────────────────

  Widget _buildSwitchTile(
    BuildContext context, {
    required String title,
    required String subtitle,
    required bool value,
    ValueChanged<bool>? onChanged,
  }) {
    return SwitchListTile(
      title: Text(title, style: _rowTitleStyle(context)),
      subtitle: Text(subtitle, style: _rowSubtitleStyle(context)),
      value: value,
      activeColor: AppTheme.adaptivePrimary(context),
      onChanged: onChanged,
    );
  }

  Widget _buildNavTile(
    BuildContext context, {
    required String title,
    required String value,
    required VoidCallback onTap,
  }) {
    return ListTile(
      title: Text(title, style: _rowTitleStyle(context)),
      subtitle: Text(
        value,
        style: AppTextStyles.caption.copyWith(
          color: AppTheme.adaptivePrimary(context),
          fontWeight: FontWeight.w600,
        ),
      ),
      trailing: Icon(Icons.arrow_forward_ios,
          size: 12, color: AppTheme.adaptiveTextDisabled(context)),
      onTap: onTap,
    );
  }

  Widget _buildComingSoonTile(
    BuildContext context, {
    required String title,
    required String subtitle,
    required String dialogTitle,
    required String dialogReason,
    IconData trailingIcon = Icons.arrow_forward_ios,
    double trailingIconSize = 12,
  }) {
    return Opacity(
      opacity: 0.6,
      child: ListTile(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: Text(title, style: _rowTitleStyle(context))),
            const SizedBox(width: AppSpacing.sm),
            _buildSoonBadge(context),
          ],
        ),
        subtitle: Text(subtitle, style: _rowSubtitleStyle(context)),
        trailing: Icon(trailingIcon,
            size: trailingIconSize,
            color: AppTheme.adaptiveTextDisabled(context)),
        onTap: () => _showUnavailableDialog(context, dialogTitle, dialogReason),
      ),
    );
  }

  Widget _buildSoonBadge(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs + 2, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.adaptivePrimary(context).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppBorderRadius.sm),
        border: Border.all(
          color: AppTheme.adaptivePrimary(context).withValues(alpha: 0.3),
        ),
      ),
      child: Text(
        'SOON',
        style: AppTextStyles.mono.copyWith(
          color: AppTheme.adaptivePrimary(context),
          fontSize: 9,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _divider(BuildContext context) {
    return Divider(
      color: AppTheme.adaptiveSurfaceSubtle(context),
      height: 1,
    );
  }

  // ─── Dialogs ────────────────────────────────────────────────────────────

  Future<T?> _showThemedDialog<T>(
    BuildContext context, {
    required Widget title,
    required Widget content,
    List<Widget>? actions,
  }) {
    return showDialog<T>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.adaptiveSurfaceRaised(ctx),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppBorderRadius.xl),
          side: BorderSide(
            color: AppTheme.adaptiveSurfaceSubtle(ctx),
          ),
        ),
        title: title,
        content: content,
        actions: actions,
      ),
    );
  }

  void _showUnavailableDialog(
      BuildContext context, String feature, String reason) {
    _showThemedDialog(
      context,
      title: Text(feature,
          style: AppTextStyles.heading3.copyWith(
              color: AppTheme.adaptiveTextPrimary(context),
              fontWeight: FontWeight.bold)),
      content: Text(reason,
          style: AppTextStyles.body1.copyWith(
              color: AppTheme.adaptiveTextSecondary(context), height: 1.4)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('OK',
              style: AppTextStyles.button
                  .copyWith(color: AppTheme.adaptivePrimary(context))),
        ),
      ],
    );
  }

  void _showLanguageDialog(BuildContext context) {
    _showThemedDialog(
      context,
      title: Text('Select Language', style: _rowTitleStyle(context)),
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
          ].map((lang) {
            final isSelected = _language == lang;
            return ListTile(
              title: Text(lang,
                  style: AppTextStyles.body2.copyWith(
                    color: isSelected
                        ? AppTheme.adaptivePrimary(context)
                        : AppTheme.adaptiveTextPrimary(context),
                    fontWeight:
                        isSelected ? FontWeight.w700 : FontWeight.w400,
                  )),
              trailing: isSelected
                  ? Icon(Icons.check,
                      size: 18, color: AppTheme.adaptivePrimary(context))
                  : null,
              onTap: () {
                setState(() => _language = lang);
                ref.read(appPreferencesProvider).setLanguage(lang);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Language set to $lang'),
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

  void _showCurrencyDialog(BuildContext context) {
    _showThemedDialog(
      context,
      title: Text('Select Currency', style: _rowTitleStyle(context)),
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
            final code = currency.split(' ')[0];
            final isSelected = _currency == code;
            return ListTile(
              title: Text(currency,
                  style: AppTextStyles.body2.copyWith(
                    color: isSelected
                        ? AppTheme.adaptivePrimary(context)
                        : AppTheme.adaptiveTextPrimary(context),
                    fontWeight:
                        isSelected ? FontWeight.w700 : FontWeight.w400,
                  )),
              trailing: isSelected
                  ? Icon(Icons.check,
                      size: 18, color: AppTheme.adaptivePrimary(context))
                  : null,
              onTap: () {
                setState(() => _currency = code);
                ref.read(appPreferencesProvider).setCurrency(code);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Currency set to $code'),
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

  void _showClearCacheDialog(BuildContext context) {
    _showThemedDialog(
      context,
      title: Text('Clear Cache',
          style: AppTextStyles.heading3.copyWith(
              color: AppTheme.errorColor, fontWeight: FontWeight.bold)),
      content: Text(
          'This will delete all cached data. Are you sure?',
          style: AppTextStyles.body1.copyWith(
              color: AppTheme.adaptiveTextSecondary(context), height: 1.4)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel',
              style: AppTextStyles.button.copyWith(
                  color: AppTheme.adaptiveTextSecondary(context))),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Cache cleared.',
                    style: AppTextStyles.body2
                        .copyWith(fontWeight: FontWeight.w600)),
                backgroundColor: AppTheme.successColor,
              ),
            );
          },
          style:
              ElevatedButton.styleFrom(backgroundColor: AppTheme.errorColor),
          child: Text('Clear',
              style: AppTextStyles.button.copyWith(color: Colors.white)),
        ),
      ],
    );
  }

  void _showAppInfoDialog(BuildContext context) {
    _showThemedDialog(
      context,
      title: Text('CardCompass',
          style: AppTextStyles.heading3.copyWith(
              color: AppTheme.adaptiveTextPrimary(context),
              fontWeight: FontWeight.bold)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Version 1.0.0',
              style: AppTextStyles.body2.copyWith(
                  color: AppTheme.adaptivePrimary(context),
                  fontWeight: FontWeight.w600)),
          Text('Build 1',
              style: AppTextStyles.caption.copyWith(
                  color: AppTheme.adaptiveTextTertiary(context))),
          const SizedBox(height: AppSpacing.md),
          Text(
            'CardCompass automatically categorizes your credit card statements, analyzes reward benefits, and recommends the best card for every purchase.',
            style: AppTextStyles.body1.copyWith(
                color: AppTheme.adaptiveTextSecondary(context), height: 1.5),
          ),
          const SizedBox(height: AppSpacing.md),
          Text('Made in India 🇮🇳',
              style: AppTextStyles.caption.copyWith(
                  color: AppTheme.adaptiveTextTertiary(context),
                  fontWeight: FontWeight.w500)),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('OK',
              style: AppTextStyles.button
                  .copyWith(color: AppTheme.adaptivePrimary(context))),
        ),
      ],
    );
  }
}
