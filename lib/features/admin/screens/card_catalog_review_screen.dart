import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/brand_tokens.dart';
import '../data/admin_catalog_repository.dart';
import '../widgets/benefit_enrichment_review_panel.dart';

Future<void> requestAdminReauthorization({
  required Future<void> Function() clearSession,
  required VoidCallback showLogin,
}) async {
  await clearSession();
  showLogin();
}

class CardCatalogReviewScreen extends StatefulWidget {
  const CardCatalogReviewScreen({super.key});

  @override
  State<CardCatalogReviewScreen> createState() =>
      _CardCatalogReviewScreenState();
}

class _CardCatalogReviewScreenState extends State<CardCatalogReviewScreen> {
  late Future<List<Map<String, dynamic>>> _items = _load();
  late final AdminCatalogRepository _benefitRepository =
      AdminCatalogRepository.live();
  String _status = 'pending';

  Future<Map<String, dynamic>> _invoke(Map<String, dynamic> body) async {
    late final FunctionResponse response;
    try {
      response = await Supabase.instance.client.functions.invoke(
        'admin-catalog-entry',
        body: body,
      );
    } catch (error) {
      throwAdminInvocationError(error);
    }
    if (response.status == 401) throw AdminAuthorizationRequired();
    if (response.status < 200 || response.status >= 300) {
      final data = response.data;
      final message = data is Map ? data['error'] : null;
      throw Exception(message ?? 'Admin request failed (${response.status})');
    }
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final data = await _invoke({'action': 'list', 'status': _status});
    return (data['items'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  void _reload() => setState(() => _items = _load());

  Future<void> _requestAuthorization() => requestAdminReauthorization(
    clearSession: () =>
        Supabase.instance.client.auth.signOut(scope: SignOutScope.local),
    showLogin: () {
      if (mounted) context.go('/login');
    },
  );

  Future<void> _act(
    String action,
    Map<String, dynamic> item, {
    Map<String, dynamic>? fields,
    String? mergeCardId,
    String? reason,
  }) async {
    final body = <String, dynamic>{
      'action': action,
      'review_item_id': item['id'],
    };
    if (fields != null) body['proposed_fields'] = fields;
    if (mergeCardId != null) body['merge_card_id'] = mergeCardId;
    if (reason != null) body['reason'] = reason;
    try {
      await _invoke(body);
      _reload();
      if (mounted) {
        final message = switch (action) {
          'approve' => 'Card approved and added to the catalog.',
          'edit_approve' => 'Edited card approved and added to the catalog.',
          'merge' => 'Discovery merged with the existing card.',
          'retry' => 'Official-source discovery queued again.',
          'reject' => 'Proposal rejected.',
          _ => 'Review updated.',
        };
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update this review: $error')),
        );
      }
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String actionLabel,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => context.pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => context.pop(true),
              child: Text(actionLabel),
            ),
          ],
        ),
      ) ??
      false;

  Future<String?> _askReason(String title, {bool required = false}) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: required ? 'Reason (required)' : 'Review note',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => context.pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (required && value.length < 2) return;
              context.pop(value);
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _editAndApprove(Map<String, dynamic> item) async {
    final original = Map<String, dynamic>.from(
      item['proposed_fields'] as Map? ?? const {},
    );
    final issuer = TextEditingController(
      text: (original['issuer'] ?? original['bank'] ?? '').toString(),
    );
    final name = TextEditingController(
      text: (original['cardName'] ?? original['card_name'] ?? '').toString(),
    );
    final network = TextEditingController(
      text: original['network']?.toString(),
    );
    final fields = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit and approve card'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: issuer,
                decoration: const InputDecoration(labelText: 'Issuer'),
              ),
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Card name'),
              ),
              TextField(
                controller: network,
                decoration: const InputDecoration(labelText: 'Network'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => context.pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => context.pop({
              ...original,
              'issuer': issuer.text.trim(),
              'cardName': name.text.trim(),
              'network': network.text.trim(),
            }),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
    issuer.dispose();
    name.dispose();
    network.dispose();
    if (fields != null) await _act('edit_approve', item, fields: fields);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: BrandColors.paper,
        appBar: AppBar(
          title: const Text('Catalog review'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/app/settings'),
          ),
          bottom: const AdminCatalogReviewTabs(),
        ),
        body: TabBarView(
          children: [
            _IdentityReviewPanel(
              items: _items,
              status: _status,
              onStatusChanged: (value) {
                if (value == null) return;
                setState(() {
                  _status = value;
                  _items = _load();
                });
              },
              onReload: _reload,
              onAuthorizationRequired: _requestAuthorization,
              onApprove: (item) async {
                final approved = await _confirm(
                  title: 'Approve as a new card?',
                  message:
                      'This creates a new catalog card from the proposed identity. Confirm that it is not a duplicate and the official source supports it.',
                  actionLabel: 'Approve as new card',
                );
                if (approved) await _act('approve', item);
              },
              onEditApprove: _editAndApprove,
              onMerge: (item, cardId) async {
                final approved = await _confirm(
                  title: 'Merge with this existing card?',
                  message:
                      'This links the discovery to the selected catalog card and prevents a new duplicate card from being created.',
                  actionLabel: 'Merge with existing',
                );
                if (approved) {
                  await _act('merge', item, mergeCardId: cardId);
                }
              },
              onRetry: (item) async {
                final note = await _askReason(
                  'Retry official-source discovery',
                );
                if (note != null) await _act('retry', item, reason: note);
              },
              onReject: (item) async {
                final reason = await _askReason(
                  'Reject catalog proposal',
                  required: true,
                );
                if (reason != null) await _act('reject', item, reason: reason);
              },
            ),
            BenefitEnrichmentReviewPanel(
              repository: _benefitRepository,
              onAuthorizationRequired: _requestAuthorization,
              onOpenUrl: (uri) =>
                  launchUrl(uri, mode: LaunchMode.externalApplication),
            ),
          ],
        ),
      ),
    );
  }
}

class AdminCatalogReviewTabs extends StatelessWidget
    implements PreferredSizeWidget {
  const AdminCatalogReviewTabs({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(kTextTabBarHeight);

  @override
  Widget build(BuildContext context) => TabBar(
    tabs: [
      Tab(
        child: _ReviewTabLabel(
          label: 'Card identity',
          tooltip: 'About card identity review',
          onHelp: () => _showReviewHelp(context, identity: true),
        ),
      ),
      Tab(
        child: _ReviewTabLabel(
          label: 'Benefit enrichment',
          tooltip: 'About benefit enrichment review',
          onHelp: () => _showReviewHelp(context, identity: false),
        ),
      ),
    ],
  );
}

class _ReviewTabLabel extends StatelessWidget {
  const _ReviewTabLabel({
    required this.label,
    required this.tooltip,
    required this.onHelp,
  });

  final String label;
  final String tooltip;
  final VoidCallback onHelp;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
      const SizedBox(width: 4),
      IconButton(
        tooltip: tooltip,
        onPressed: onHelp,
        icon: const Icon(Icons.info_outline, size: 18),
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      ),
    ],
  );
}

Future<void> _showReviewHelp(
  BuildContext context, {
  required bool identity,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => SafeArea(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 680),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: identity
              ? const [
                  _HelpHeading('Card identity review'),
                  _HelpItem(
                    'What this queue is for',
                    'Checks whether a discovered issuer page represents a new credit card, a known card, or something that is not a card at all.',
                  ),
                  _HelpItem(
                    'Evidence',
                    'The source URL, page title, extracted issuer and card name, and any matching cards already in the catalog. Use it to verify the proposal independently.',
                  ),
                  _HelpItem(
                    'Confidence',
                    'The system\'s estimate of extraction quality—not a guarantee that the page is a real or distinct card. Low confidence needs closer review.',
                  ),
                  _HelpItem(
                    'Warnings',
                    'Specific risk signals, such as weak issuer evidence, a non-card page, missing fields, or a possible duplicate. Resolve them before approval.',
                  ),
                  _HelpItem(
                    'Approve as new card',
                    'Creates a new catalog card from the proposed identity.',
                  ),
                  _HelpItem(
                    'Edit and approve',
                    'Lets you correct the proposed identity, then creates a new catalog card.',
                  ),
                  _HelpItem(
                    'Merge with existing',
                    'Links this discovery to an existing card instead of creating a duplicate.',
                  ),
                  _HelpItem(
                    'Retry discovery',
                    'Sends the item through official-source discovery again. Use this when the evidence is incomplete or stale.',
                  ),
                  _HelpItem(
                    'Reject proposal',
                    'Closes the proposal without adding or changing a catalog card. A reason is required for the audit trail.',
                  ),
                ]
              : const [
                  _HelpHeading('Benefit enrichment review'),
                  _HelpItem(
                    'What this queue is for',
                    'Reviews proposed additions or changes to benefits on an existing catalog card.',
                  ),
                  _HelpItem(
                    'Evidence',
                    'Source excerpts and URLs that support each proposed benefit.',
                  ),
                  _HelpItem(
                    'Confidence',
                    'The system\'s estimate that the extracted benefit fields match the source.',
                  ),
                  _HelpItem(
                    'Warnings',
                    'Signals that evidence, mapping, or extracted values need manual attention.',
                  ),
                  _HelpItem(
                    'Approve benefit changes',
                    'Applies the proposed benefit changes to the existing card.',
                  ),
                  _HelpItem(
                    'Edit proposed changes',
                    'Lets you choose or correct changes before applying them.',
                  ),
                  _HelpItem(
                    'Reject',
                    'Closes the proposal without applying its changes.',
                  ),
                  _HelpItem(
                    'Retry processing',
                    'Runs extraction and validation for this source again.',
                  ),
                  _HelpItem(
                    'Quarantine',
                    'Removes a suspicious item from the normal queue until it is investigated.',
                  ),
                ],
        ),
      ),
    ),
  ),
);

class _HelpHeading extends StatelessWidget {
  const _HelpHeading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(text, style: Theme.of(context).textTheme.headlineSmall),
  );
}

class _HelpItem extends StatelessWidget {
  const _HelpItem(this.title, this.description);
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(description, style: Theme.of(context).textTheme.bodyMedium),
      ],
    ),
  );
}

class _IdentityReviewPanel extends StatelessWidget {
  const _IdentityReviewPanel({
    required this.items,
    required this.status,
    required this.onStatusChanged,
    required this.onReload,
    required this.onAuthorizationRequired,
    required this.onApprove,
    required this.onEditApprove,
    required this.onMerge,
    required this.onRetry,
    required this.onReject,
  });

  final Future<List<Map<String, dynamic>>> items;
  final String status;
  final ValueChanged<String?> onStatusChanged;
  final VoidCallback onReload;
  final VoidCallback onAuthorizationRequired;
  final ValueChanged<Map<String, dynamic>> onApprove;
  final ValueChanged<Map<String, dynamic>> onEditApprove;
  final void Function(Map<String, dynamic>, String) onMerge;
  final ValueChanged<Map<String, dynamic>> onRetry;
  final ValueChanged<Map<String, dynamic>> onReject;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Decide whether each discovery is a new card, an existing card, or not a card.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: status,
                      items: const [
                        DropdownMenuItem(
                          value: 'pending',
                          child: Text('Pending'),
                        ),
                        DropdownMenuItem(
                          value: 'approved',
                          child: Text('Approved'),
                        ),
                        DropdownMenuItem(
                          value: 'merged',
                          child: Text('Merged'),
                        ),
                        DropdownMenuItem(
                          value: 'rejected',
                          child: Text('Rejected'),
                        ),
                      ],
                      onChanged: onStatusChanged,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Refresh card identity queue',
                    onPressed: onReload,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: items,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text('Loading card identity reviews…'),
                    ],
                  ),
                );
              }
              if (snapshot.hasError) {
                if (snapshot.error is AdminAuthorizationRequired) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Your session needs authorization.'),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: onAuthorizationRequired,
                            child: const Text('Sign in again'),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.cloud_off_outlined, size: 36),
                        const SizedBox(height: 12),
                        Text(
                          snapshot.error.toString().contains(
                                'Administrator access',
                              )
                              ? 'Administrator access required.'
                              : 'Could not load the card identity queue.',
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: onReload,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Try again'),
                        ),
                      ],
                    ),
                  ),
                );
              }
              final items = snapshot.data ?? const [];
              if (items.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.task_alt, size: 36),
                        const SizedBox(height: 12),
                        Text('No $status card identity reviews.'),
                      ],
                    ),
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(24),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 16),
                itemBuilder: (context, index) => CatalogIdentityReviewCard(
                  item: items[index],
                  onApprove: () => onApprove(items[index]),
                  onEditApprove: () => onEditApprove(items[index]),
                  onMerge: (cardId) => onMerge(items[index], cardId),
                  onRetry: () => onRetry(items[index]),
                  onReject: () => onReject(items[index]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class CatalogIdentityReviewCard extends StatelessWidget {
  const CatalogIdentityReviewCard({
    super.key,
    required this.item,
    required this.onApprove,
    required this.onEditApprove,
    required this.onMerge,
    required this.onRetry,
    required this.onReject,
  });

  final Map<String, dynamic> item;
  final VoidCallback onApprove;
  final VoidCallback onEditApprove;
  final ValueChanged<String> onMerge;
  final VoidCallback onRetry;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final fields = Map<String, dynamic>.from(
      item['proposed_fields'] as Map? ?? const {},
    );
    final job = Map<String, dynamic>.from(
      item['card_discovery_jobs'] as Map? ?? const {},
    );
    final evidence = Map<String, dynamic>.from(
      job['evidence'] as Map? ?? const {},
    );
    final sourceObservation = Map<String, dynamic>.from(
      fields['source_observation'] as Map? ?? const {},
    );
    final issuerDiscoveryQuarantine =
        sourceObservation['classification'] == 'issuer_discovery_quarantine' &&
        sourceObservation['kind'] == 'issuer_discovery_quarantine';
    final warnings = (item['validation_warnings'] as List? ?? const [])
        .map((warning) => _identityWarningLabel(warning.toString()))
        .toList(growable: false);
    final candidates = item['existing_candidates'] as List? ?? const [];
    final pending = item['status'] == 'pending';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (issuerDiscoveryQuarantine) ...[
              Text(
                'Issuer discovery quarantine',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              _line('Issuer', sourceObservation['issuer']),
              _line('Producer anchor', sourceObservation['anchor_job_id']),
              _line(
                'Reason',
                _identityWarningLabel(sourceObservation['reason'].toString()),
              ),
              if (pending) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton(
                      onPressed: onRetry,
                      child: const Text('Retry issuer discovery'),
                    ),
                    TextButton(
                      onPressed: onReject,
                      child: const Text('Keep quarantined'),
                    ),
                  ],
                ),
              ],
            ] else ...[
              Text(
                '${fields['issuer'] ?? job['issuer'] ?? 'Unknown issuer'} · '
                '${fields['cardName'] ?? fields['card_name'] ?? job['proposed_product'] ?? 'Unknown variant'}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 10),
              Text(
                'Proposed identity',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              _line('Subject', evidence['subject_product']),
              _line('PDF filename', evidence['filename_product']),
              _line('PDF header', evidence['pdf_header_product']),
              _line('Network', fields['network'] ?? evidence['network']),
              _line('Masked last four', evidence['last_four']),
              _line('Official source', fields['official_url']),
              const SizedBox(height: 10),
              Text(
                'Evidence and risk',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              _line('Confidence', _confidenceLabel(item['confidence'])),
              if (warnings.isNotEmpty) _line('Warnings', warnings.join(' · ')),
              if (evidence['pdf_header_excerpt'] != null)
                _line('Sanitized evidence', evidence['pdf_header_excerpt']),
              if (pending) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton(
                      onPressed: onApprove,
                      child: const Text('Approve as new card'),
                    ),
                    OutlinedButton(
                      onPressed: onEditApprove,
                      child: const Text('Edit and approve'),
                    ),
                    for (final candidate in candidates.whereType<Map>())
                      OutlinedButton(
                        onPressed: candidate['id'] is String
                            ? () => onMerge(candidate['id'] as String)
                            : null,
                        child: Text(
                          'Merge with ${candidate['card_name'] ?? 'existing card'}',
                        ),
                      ),
                    TextButton(
                      onPressed: onRetry,
                      child: const Text('Retry discovery'),
                    ),
                    TextButton(
                      onPressed: onReject,
                      child: const Text('Reject proposal'),
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  String _confidenceLabel(Object? value) {
    if (value is num) return '${(value * 100).round()}%';
    return value?.toString() ?? 'Not provided';
  }

  Widget _line(String label, Object? value) {
    if (value == null || value.toString().trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: SelectableText('$label: $value'),
    );
  }
}

String _identityWarningLabel(String warning) {
  const labels = {
    'crawler_discovered_without_statement_signal':
        'Crawler-only discovery; no independent statement evidence.',
    'possible_duplicate': 'Possible duplicate of an existing catalog card.',
    'missing_official_url': 'Official source URL is missing.',
    'low_confidence': 'Low identity extraction confidence.',
  };
  final known = labels[warning];
  if (known != null) return known;
  final words = warning.replaceAll('_', ' ').trim();
  if (words.isEmpty) return warning;
  return '${words[0].toUpperCase()}${words.substring(1)}.';
}
