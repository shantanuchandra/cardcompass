import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/providers/supabase_provider.dart';
import '../../../core/theme/brand_components.dart';
import '../../../core/theme/brand_tokens.dart';
import '../../auth/providers/auth_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final name =
        user?.userMetadata?['full_name'] as String? ?? user?.email ?? 'User';
    final email = user?.email ?? '';
    final avatar = user?.userMetadata?['avatar_url'] as String?;

    return Scaffold(
      backgroundColor: BrandColors.paper,
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(BrandSpacing.md),
        children: [
          _ProfileCard(name: name, email: email, avatar: avatar),
          const SizedBox(height: BrandSpacing.lg),
          const SettingsActionList(),
          const SizedBox(height: BrandSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Sign out?'),
                    content: const Text(
                      'You\'ll need to sign in again to access your data.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Sign out'),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await ref.read(authNotifierProvider.notifier).signOut();
                }
              },
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: const Text('Sign out'),
              style: OutlinedButton.styleFrom(
                foregroundColor: BrandColors.error,
                side: const BorderSide(color: BrandColors.error),
                minimumSize: const Size(0, 48),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.name,
    required this.email,
    required this.avatar,
  });

  final String name;
  final String email;
  final String? avatar;

  @override
  Widget build(BuildContext context) => BrandSurface(
    padding: const EdgeInsets.all(BrandSpacing.md),
    child: Row(
      children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: BrandColors.paperDeep,
          backgroundImage: avatar != null ? NetworkImage(avatar!) : null,
          child: avatar == null
              ? Text(
                  name[0].toUpperCase(),
                  style: const TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: BrandColors.focusDark,
                  ),
                )
              : null,
        ),
        const SizedBox(width: BrandSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: Theme.of(context).textTheme.titleMedium),
              if (email.isNotEmpty)
                Text(email, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Product settings with an explicit outcome for every visible row.
class SettingsActionList extends StatelessWidget {
  const SettingsActionList({super.key, this.onOpenUri});

  final Future<bool> Function(Uri uri)? onOpenUri;

  Uri _siteUri(String path) => Uri.base.resolve(path);

  Future<void> _open(String uri) async {
    final destination = uri.startsWith('mailto:')
        ? Uri.parse(uri)
        : _siteUri(uri);
    await (onOpenUri?.call(destination) ??
        launchUrl(destination, mode: LaunchMode.externalApplication));
  }

  void _showAbout(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'CardCompass',
      applicationVersion: '2.0.0',
      applicationLegalese:
          'Understand the calculation behind every recommendation.',
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const BrandActionRow(
        title: 'Notifications',
        description: 'Bill reminders and reward alerts',
        leading: Icon(Icons.notifications_outlined),
        unavailable: true,
      ),
      BrandActionRow(
        title: 'Privacy',
        description: 'How CardCompass handles your information',
        leading: const Icon(Icons.privacy_tip_outlined),
        onTap: () => _open('/privacy/'),
      ),
      BrandActionRow(
        title: 'Data & Security',
        description: 'Our data and account safeguards',
        leading: const Icon(Icons.security_outlined),
        onTap: () => _open('/data-security/'),
      ),
      BrandActionRow(
        title: 'Terms',
        description: 'Read the CardCompass terms',
        leading: const Icon(Icons.description_outlined),
        onTap: () => _open('/terms/'),
      ),
      BrandActionRow(
        title: 'Help & Support',
        description: 'Email the CardCompass support team',
        leading: const Icon(Icons.help_outline_rounded),
        onTap: () => _open(
          'mailto:support@cardcompass.in?subject=CardCompass%20support',
        ),
      ),
      BrandActionRow(
        title: 'About',
        description: 'CardCompass version information',
        leading: const Icon(Icons.info_outline_rounded),
        onTap: () => _showAbout(context),
      ),
    ],
  );
}
