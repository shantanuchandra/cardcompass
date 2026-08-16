import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/brand_tokens.dart';
import '../data/admin_catalog_repository.dart';
import '../widgets/benefit_enrichment_review_panel.dart';

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
    final response = await Supabase.instance.client.functions.invoke(
      'admin-catalog-entry',
      body: body,
    );
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
    await _invoke(body);
    _reload();
  }

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
              onApprove: (item) => _act('approve', item),
              onEditApprove: _editAndApprove,
              onMerge: (item, cardId) =>
                  _act('merge', item, mergeCardId: cardId),
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
              onAuthorizationRequired: () => context.go('/login'),
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
  Widget build(BuildContext context) => const TabBar(
    tabs: [
      Tab(text: 'Card identity'),
      Tab(text: 'Benefit enrichment'),
    ],
  );
}

class _IdentityReviewPanel extends StatelessWidget {
  const _IdentityReviewPanel({
    required this.items,
    required this.status,
    required this.onStatusChanged,
    required this.onReload,
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
          child: Row(
            children: [
              DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: status,
                  items: const [
                    DropdownMenuItem(value: 'pending', child: Text('Pending')),
                    DropdownMenuItem(
                      value: 'approved',
                      child: Text('Approved'),
                    ),
                    DropdownMenuItem(value: 'merged', child: Text('Merged')),
                    DropdownMenuItem(
                      value: 'rejected',
                      child: Text('Rejected'),
                    ),
                  ],
                  onChanged: onStatusChanged,
                ),
              ),
              const Spacer(),
              IconButton(onPressed: onReload, icon: const Icon(Icons.refresh)),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: items,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      snapshot.error.toString().contains('Administrator access')
                          ? 'Administrator access required.'
                          : 'Could not load catalog review: ${snapshot.error}',
                    ),
                  ),
                );
              }
              final items = snapshot.data ?? const [];
              if (items.isEmpty) {
                return Center(child: Text('No $status catalog items.'));
              }
              return ListView.separated(
                padding: const EdgeInsets.all(24),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 16),
                itemBuilder: (context, index) => _ReviewCard(
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

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
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
    final warnings = (item['validation_warnings'] as List? ?? const []).join(
      ', ',
    );
    final candidates = item['existing_candidates'] as List? ?? const [];
    final pending = item['status'] == 'pending';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${fields['issuer'] ?? job['issuer'] ?? 'Unknown issuer'} · '
              '${fields['cardName'] ?? fields['card_name'] ?? job['proposed_product'] ?? 'Unknown variant'}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            _line('Subject', evidence['subject_product']),
            _line('PDF filename', evidence['filename_product']),
            _line('PDF header', evidence['pdf_header_product']),
            _line('Network', fields['network'] ?? evidence['network']),
            _line('Masked last four', evidence['last_four']),
            _line('Official source', fields['official_url']),
            _line('Confidence', item['confidence']),
            if (warnings.isNotEmpty) _line('Warnings', warnings),
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
                    child: const Text('Approve'),
                  ),
                  OutlinedButton(
                    onPressed: onEditApprove,
                    child: const Text('Edit & approve'),
                  ),
                  for (final candidate in candidates.whereType<Map>())
                    OutlinedButton(
                      onPressed: candidate['id'] is String
                          ? () => onMerge(candidate['id'] as String)
                          : null,
                      child: Text(
                        'Merge: ${candidate['card_name'] ?? 'existing'}',
                      ),
                    ),
                  TextButton(
                    onPressed: onRetry,
                    child: const Text('Retry scrape'),
                  ),
                  TextButton(onPressed: onReject, child: const Text('Reject')),
                ],
              ),
            ],
          ],
        ),
      ),
    );
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
