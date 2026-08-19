import 'package:flutter/material.dart';

import '../../../core/theme/brand_components.dart';
import '../../../core/theme/brand_tokens.dart';
import '../data/admin_operator_repository.dart';
import 'inbox_models.dart';

typedef InboxLoader = Future<InboxSnapshot> Function();

class ActionInboxSection extends StatefulWidget {
  const ActionInboxSection({
    super.key,
    required this.loadInbox,
    required this.onOpenCardTarget,
    this.onAuthenticationRequired,
    this.onAccessDenied,
  });

  final InboxLoader loadInbox;
  final ValueChanged<AdminInboxDestination> onOpenCardTarget;
  final Future<void> Function()? onAuthenticationRequired;
  final VoidCallback? onAccessDenied;

  @override
  State<ActionInboxSection> createState() => _ActionInboxSectionState();
}

class _ActionInboxSectionState extends State<ActionInboxSection> {
  InboxSnapshot? _snapshot;
  Object? _error;
  bool _loading = true;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      if (_snapshot == null) {
        _loading = true;
      } else {
        _refreshing = true;
      }
    });
    try {
      final next = await widget.loadInbox();
      if (!mounted) return;
      setState(() {
        _snapshot = next;
        _loading = false;
        _refreshing = false;
      });
    } catch (error) {
      if (error is AdminAuthenticationRequired) {
        await widget.onAuthenticationRequired?.call();
      } else if (error is AdminAccessDenied) {
        widget.onAccessDenied?.call();
      }
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
        _refreshing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const BrandLoadingSkeleton(
        semanticLabel: 'Loading action inbox',
        minHeight: 280,
      );
    }
    final snapshot = _snapshot;
    if (snapshot == null) {
      return BrandStateView(
        title: 'Action Inbox could not be loaded.',
        message: 'Check your connection and try again.',
        icon: Icons.cloud_off_outlined,
        actionLabel: 'Try again',
        onAction: _load,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_refreshing) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: ListView(
                padding: const EdgeInsets.only(bottom: BrandSpacing.lg),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      BrandSpacing.lg,
                      BrandSpacing.lg,
                      BrandSpacing.lg,
                      BrandSpacing.sm,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Expanded(
                          child: BrandPageHeader(
                            eyebrow: 'Ranked operator queue',
                            title: 'Action Inbox',
                            description:
                                'Work the highest-impact card issues first.',
                          ),
                        ),
                        IconButton(
                          tooltip: 'Refresh inbox',
                          onPressed: _refreshing ? null : _load,
                          icon: const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                  ),
                  if (_error != null)
                    const _Notice(
                      text: 'Refresh failed. Showing the last loaded inbox.',
                    ),
                  for (final source in snapshot.partialFailures)
                    _Notice(text: _partialFailureMessage(source)),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: BrandSpacing.lg,
                    ),
                    child: Text(
                      'Refreshed ${_formatTimestamp(snapshot.refreshedAt)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(height: BrandSpacing.sm),
                  if (snapshot.items.isEmpty)
                    const SizedBox(
                      height: 280,
                      child: BrandStateView(
                        title: 'Inbox clear.',
                        message: 'No card operations need attention right now.',
                        icon: Icons.task_alt,
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: BrandSpacing.lg,
                      ),
                      child: Column(
                        children: [
                          for (final severity in AdminInboxSeverity.values)
                            _SeverityGroup(
                              severity: severity,
                              items: snapshot.items
                                  .where((item) => item.severity == severity)
                                  .toList(growable: false),
                              onOpen: widget.onOpenCardTarget,
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SeverityGroup extends StatelessWidget {
  const _SeverityGroup({
    required this.severity,
    required this.items,
    required this.onOpen,
  });

  final AdminInboxSeverity severity;
  final List<AdminInboxItem> items;
  final ValueChanged<AdminInboxDestination> onOpen;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: BrandSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: BrandSpacing.sm),
            child: Text(
              _severityLabel(severity),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          for (var index = 0; index < items.length; index++) ...[
            _InboxItem(item: items[index], onOpen: onOpen),
            if (index != items.length - 1)
              const SizedBox(height: BrandSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _InboxItem extends StatelessWidget {
  const _InboxItem({required this.item, required this.onOpen});

  final AdminInboxItem item;
  final ValueChanged<AdminInboxDestination> onOpen;

  @override
  Widget build(BuildContext context) => Semantics(
    key: Key('inbox-item-${item.id}'),
    label:
        '${_severityLabel(item.severity)}. ${item.title}. ${item.explanation}. Status ${item.sourceStatus}. ${_formatAge(item.ageSeconds)} old.',
    button: true,
    onTap: () => onOpen(item.destination),
    excludeSemantics: true,
    child: OutlinedButton(
      onPressed: () => onOpen(item.destination),
      style: OutlinedButton.styleFrom(
        alignment: Alignment.centerLeft,
        minimumSize: const Size(44, 72),
        padding: const EdgeInsets.all(BrandSpacing.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_severityIcon(item.severity), size: 22),
          const SizedBox(width: BrandSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: BrandSpacing.xs),
                Text(item.explanation),
                const SizedBox(height: BrandSpacing.xs),
                Text(
                  '${item.sourceStatus.replaceAll('_', ' ')} · ${_formatAge(item.ageSeconds)} old',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
    ),
  );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      margin: const EdgeInsets.fromLTRB(
        BrandSpacing.lg,
        0,
        BrandSpacing.lg,
        BrandSpacing.sm,
      ),
      padding: const EdgeInsets.all(BrandSpacing.compact),
      color: BrandColors.paperDeep,
      child: Text(text),
    ),
  );
}

String _partialFailureMessage(InboxSource source) => switch (source) {
  InboxSource.cardIdentity => 'Card identity is temporarily unavailable.',
  InboxSource.benefitEnrichment =>
    'Benefit enrichment is temporarily unavailable.',
};

String _severityLabel(AdminInboxSeverity severity) => switch (severity) {
  AdminInboxSeverity.critical => 'Critical',
  AdminInboxSeverity.high => 'High',
  AdminInboxSeverity.normal => 'Normal',
};

IconData _severityIcon(AdminInboxSeverity severity) => switch (severity) {
  AdminInboxSeverity.critical => Icons.error_outline,
  AdminInboxSeverity.high => Icons.priority_high,
  AdminInboxSeverity.normal => Icons.info_outline,
};

String _formatAge(int seconds) {
  if (seconds < 60) return '${seconds}s';
  if (seconds < 3600) return '${seconds ~/ 60}m';
  if (seconds < 86400) return '${seconds ~/ 3600}h';
  return '${seconds ~/ 86400}d';
}

String _formatTimestamp(DateTime value) {
  final local = value.toLocal();
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.day}/${local.month}/${local.year} ${local.hour}:$minute';
}
