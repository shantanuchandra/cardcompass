import 'package:flutter/material.dart';

import '../../../core/theme/brand_components.dart';
import '../../../core/theme/brand_tokens.dart';
import 'feedback_models.dart';

class FeedbackSection extends StatefulWidget {
  const FeedbackSection({super.key, required this.load, required this.onOpen});
  final Future<AdminFeedbackPage> Function({
    int page,
    int limit,
    String? reviewStatus,
  })
  load;
  final ValueChanged<String> onOpen;

  @override
  State<FeedbackSection> createState() => _FeedbackSectionState();
}

class _FeedbackSectionState extends State<FeedbackSection> {
  String? status;
  AdminFeedbackPage? content;
  Object? error;
  bool loading = false;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload({int? page}) async {
    if (loading) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final next = await widget.load(
        page: page ?? content?.page ?? 1,
        limit: 25,
        reviewStatus: status,
      );
      if (mounted) setState(() => content = next);
    } catch (value) {
      if (mounted) setState(() => error = value);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (error != null && content == null) {
      return BrandStateView(
        title: 'Feedback could not be loaded.',
        message: 'Try again.',
        icon: Icons.cloud_off_outlined,
        actionLabel: 'Try again',
        onAction: reload,
      );
    }
    if (content == null) {
      return const BrandLoadingSkeleton(
        semanticLabel: 'Loading feedback workspace',
        minHeight: 280,
      );
    }
    final page = content!;
    return ListView(
      key: const Key('feedback-workspace-list'),
      padding: const EdgeInsets.all(BrandSpacing.lg),
      children: [
        Text('Feedback', style: Theme.of(context).textTheme.headlineMedium),
        const Text(
          'Reopen pending, drafted, approved, routed, or retired feedback.',
        ),
        const SizedBox(height: BrandSpacing.md),
        DropdownButtonFormField<String?>(
          key: const Key('feedback-status-filter'),
          initialValue: status,
          decoration: const InputDecoration(labelText: 'Review status'),
          items: const [
            DropdownMenuItem(value: null, child: Text('All statuses')),
            DropdownMenuItem(value: 'pending', child: Text('Pending')),
            DropdownMenuItem(
              value: 'eval_created',
              child: Text('Eval created'),
            ),
            DropdownMenuItem(value: 'data_issue', child: Text('Data issue')),
            DropdownMenuItem(
              value: 'product_defect',
              child: Text('Product defect'),
            ),
            DropdownMenuItem(value: 'dismissed', child: Text('Dismissed')),
          ],
          onChanged: (value) {
            status = value;
            content = null;
            reload(page: 1);
          },
        ),
        if (loading)
          const LinearProgressIndicator(key: Key('feedback-refresh-progress')),
        if (error != null)
          Row(
            children: [
              const Expanded(
                child: Text('Refresh failed. Showing the last loaded page.'),
              ),
              TextButton(onPressed: reload, child: const Text('Retry')),
            ],
          ),
        const SizedBox(height: BrandSpacing.md),
        if (page.items.isEmpty) const Text('No feedback matches this filter.'),
        for (final item in page.items)
          Card(
            child: ListTile(
              key: Key('feedback-row-${item.id}'),
              title: Text('${item.feature} · ${item.reviewStatus}'),
              subtitle: Text(
                '${item.severity} · ${item.triageStatus} · ${item.createdAt.toLocal()}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => widget.onOpen(item.id),
            ),
          ),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: BrandSpacing.sm,
          runSpacing: BrandSpacing.sm,
          children: [
            OutlinedButton(
              key: const Key('feedback-previous-page'),
              onPressed: !loading && page.page > 1
                  ? () => reload(page: page.page - 1)
                  : null,
              child: const Text('Previous'),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('Page ${page.page} · ${page.total} total'),
            ),
            OutlinedButton(
              key: const Key('feedback-next-page'),
              onPressed: !loading && page.hasMore
                  ? () => reload(page: page.page + 1)
                  : null,
              child: const Text('Next'),
            ),
          ],
        ),
      ],
    );
  }
}
