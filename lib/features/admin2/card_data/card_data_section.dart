import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/brand_components.dart';
import '../../../core/theme/brand_tokens.dart';
import '../data/admin_operator_repository.dart';
import 'card_data_models.dart';

final class CardReviewQuery {
  const CardReviewQuery({
    required this.lane,
    this.page = 1,
    this.limit = 25,
    this.status,
  });

  final CardReviewLane lane;
  final int page;
  final int limit;
  final String? status;
}

abstract interface class CardDataSource {
  Future<CardReviewPage> list(CardReviewQuery query);
  Future<void> act(CardReviewAction action);
}

class CardDataSection extends ConsumerStatefulWidget {
  const CardDataSection({
    super.key,
    required this.repository,
    this.initialTargetId,
    this.onAuthenticationRequired,
    this.onAccessDenied,
  });

  final CardDataSource repository;
  final String? initialTargetId;
  final Future<void> Function()? onAuthenticationRequired;
  final VoidCallback? onAccessDenied;

  @override
  ConsumerState<CardDataSection> createState() => _CardDataSectionState();
}

class _CardDataSectionState extends ConsumerState<CardDataSection> {
  CardReviewLane _lane = CardReviewLane.identity;
  CardReviewPage? _page;
  CardReviewItem? _selected;
  String? _status;
  Object? _error;
  String? _notice;
  bool _loading = true;
  bool _refreshing = false;
  bool _submitting = false;
  bool _compactDetail = false;

  @override
  void initState() {
    super.initState();
    _load(initial: true);
  }

  Future<void> _load({bool initial = false, int? page}) async {
    if (mounted) {
      setState(() {
        if (initial && _page == null) _loading = true;
        if (_page != null) _refreshing = true;
        _error = null;
      });
    }
    try {
      final next = await widget.repository.list(
        CardReviewQuery(
          lane: _lane,
          page: page ?? _page?.page ?? 1,
          status: _status,
        ),
      );
      if (!mounted) return;
      final target = initial ? widget.initialTargetId : _selected?.id;
      setState(() {
        _page = next;
        _selected =
            next.items.where((item) => item.id == target).firstOrNull ??
            next.items.firstOrNull;
        _loading = false;
        _refreshing = false;
      });
    } catch (error) {
      if (!mounted) return;
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

  Future<void> _changeLane(CardReviewLane lane) async {
    if (_lane == lane || _submitting) return;
    setState(() {
      _lane = lane;
      _page = null;
      _selected = null;
      _status = null;
      _compactDetail = false;
    });
    await _load(initial: true, page: 1);
  }

  Future<void> _confirm(CardReviewOperation operation) async {
    final item = _selected;
    if (item == null || _submitting) return;
    final reasonRequired =
        operation == CardReviewOperation.reject ||
        operation == CardReviewOperation.quarantine;
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => _ConfirmationDialog(
        operation: operation,
        reasonRequired: reasonRequired,
      ),
    );
    if (reason == null) return;
    final payload = <String, dynamic>{};
    if (item.lane == CardReviewLane.benefit &&
        {
          CardReviewOperation.approve,
          CardReviewOperation.editApprove,
          CardReviewOperation.reject,
        }.contains(operation)) {
      payload['decisions'] = [
        {
          'action': switch (operation) {
            CardReviewOperation.approve => 'approve',
            CardReviewOperation.editApprove => 'edit',
            _ => 'reject',
          },
        },
      ];
    }
    if (item.lane == CardReviewLane.identity &&
        operation == CardReviewOperation.merge) {
      // Merge target selection is intentionally explicit rather than inferred.
      final mergeId = reason.trim();
      payload['merge_card_id'] = mergeId;
    }
    setState(() {
      _submitting = true;
      _notice = null;
    });
    try {
      await widget.repository.act(
        CardReviewAction(
          lane: item.lane,
          operation: operation,
          targetId: item.id,
          observedUpdatedAt: item.updatedAt.toIso8601String(),
          stagingId: item.stagingId,
          reason: reasonRequired ? reason.trim() : null,
          payload: payload,
        ),
      );
      if (!mounted) return;
      setState(() => _notice = '${_operationLabel(operation)} confirmed.');
      await _load();
    } on AdminStateConflict {
      if (!mounted) return;
      setState(() => _notice = 'This review changed. Check the latest state.');
      await _load();
    } catch (error) {
      if (error is AdminAuthenticationRequired) {
        await widget.onAuthenticationRequired?.call();
      } else if (error is AdminAccessDenied) {
        widget.onAccessDenied?.call();
      } else if (mounted) {
        setState(
          () => _notice = 'Action failed. Review the item and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_page == null) {
      return _FailureState(error: _error, onRetry: () => _load(initial: true));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1024;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_refreshing) const LinearProgressIndicator(minHeight: 2),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                BrandSpacing.lg,
                BrandSpacing.lg,
                BrandSpacing.lg,
                BrandSpacing.md,
              ),
              child: _Header(
                compact: !wide,
                lane: _lane,
                page: _page!,
                status: _status,
                disabled: _submitting,
                onLane: _changeLane,
                onStatus: (value) {
                  setState(() {
                    _status = value;
                    _page = null;
                    _selected = null;
                  });
                  _load(initial: true, page: 1);
                },
                onRefresh: _refreshing ? null : _load,
              ),
            ),
            if (_notice case final notice?)
              Semantics(
                liveRegion: true,
                child: Container(
                  margin: const EdgeInsets.fromLTRB(
                    BrandSpacing.lg,
                    0,
                    BrandSpacing.lg,
                    BrandSpacing.sm,
                  ),
                  padding: const EdgeInsets.all(BrandSpacing.compact),
                  color: BrandColors.ledger,
                  child: Text(notice),
                ),
              ),
            if (_error != null && _page != null)
              Semantics(
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
                  child: const Text(
                    'Refresh failed. Showing the last loaded queue.',
                  ),
                ),
              ),
            Expanded(
              child: _page!.items.isEmpty
                  ? const BrandStateView(
                      title: 'Queue clear.',
                      message: 'No reviews match this lane and status.',
                      icon: Icons.task_alt,
                    )
                  : wide
                  ? Row(
                      key: const Key('card-data-wide-layout'),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: 360,
                          child: _Queue(
                            page: _page!,
                            selected: _selected,
                            onSelected: (item) =>
                                setState(() => _selected = item),
                            onPage: (value) => _load(page: value),
                          ),
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(child: _detail()),
                      ],
                    )
                  : _compactDetail
                  ? KeyedSubtree(
                      key: const Key('card-data-compact-layout'),
                      child: _detail(compact: true),
                    )
                  : KeyedSubtree(
                      key: const Key('card-data-compact-layout'),
                      child: _Queue(
                        page: _page!,
                        selected: _selected,
                        onSelected: (item) => setState(() {
                          _selected = item;
                          _compactDetail = true;
                        }),
                        onPage: (value) => _load(page: value),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _detail({bool compact = false}) => _ReviewDetail(
    item: _selected,
    submitting: _submitting,
    compact: compact,
    onBack: compact ? () => setState(() => _compactDetail = false) : null,
    onOperation: _confirm,
  );
}

class _Header extends StatelessWidget {
  const _Header({
    required this.compact,
    required this.lane,
    required this.page,
    required this.status,
    required this.disabled,
    required this.onLane,
    required this.onStatus,
    required this.onRefresh,
  });
  final bool compact;
  final CardReviewLane lane;
  final CardReviewPage page;
  final String? status;
  final bool disabled;
  final ValueChanged<CardReviewLane> onLane;
  final ValueChanged<String?> onStatus;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      BrandPageHeader(
        eyebrow: 'Card operations ledger',
        title: 'Card Data',
        description: compact
            ? null
            : 'Resolve identity and benefit evidence one item at a time.',
        trailing: IconButton(
          tooltip: 'Refresh queue',
          onPressed: disabled ? null : onRefresh,
          icon: const Icon(Icons.refresh),
        ),
      ),
      const SizedBox(height: BrandSpacing.md),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            SegmentedButton<CardReviewLane>(
              segments: const [
                ButtonSegment(
                  value: CardReviewLane.identity,
                  label: Text('Identity'),
                ),
                ButtonSegment(
                  value: CardReviewLane.benefit,
                  label: Text('Benefits'),
                ),
              ],
              selected: {lane},
              onSelectionChanged: disabled
                  ? null
                  : (value) => onLane(value.single),
            ),
            const SizedBox(width: BrandSpacing.sm),
            SizedBox(
              width: compact ? 190 : 210,
              child: DropdownButton<String?>(
                isExpanded: true,
                value: status,
                hint: const Text('All statuses'),
                onChanged: disabled ? null : onStatus,
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('All statuses'),
                  ),
                  for (final value
                      in lane == CardReviewLane.identity
                          ? const ['pending', 'approved', 'merged', 'rejected']
                          : const [
                              'queued',
                              'processing',
                              'review_required',
                              'failed',
                              'staged',
                              'quarantined',
                              'completed',
                            ])
                    DropdownMenuItem(
                      value: value,
                      child: Text(value.replaceAll('_', ' ')),
                    ),
                ],
              ),
            ),
            const SizedBox(width: BrandSpacing.md),
            Text(_formatRefresh(page.refreshedAt)),
          ],
        ),
      ),
    ],
  );
}

class _Queue extends StatelessWidget {
  const _Queue({
    required this.page,
    required this.selected,
    required this.onSelected,
    required this.onPage,
  });
  final CardReviewPage page;
  final CardReviewItem? selected;
  final ValueChanged<CardReviewItem> onSelected;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: ListView.separated(
          padding: const EdgeInsets.all(BrandSpacing.md),
          itemCount: page.items.length,
          separatorBuilder: (_, _) => const SizedBox(height: BrandSpacing.sm),
          itemBuilder: (context, index) {
            final item = page.items[index];
            return Semantics(
              selected: selected?.id == item.id,
              button: true,
              child: ListTile(
                minTileHeight: 64,
                selected: selected?.id == item.id,
                selectedTileColor: BrandColors.ledger,
                shape: RoundedRectangleBorder(
                  side: const BorderSide(color: BrandColors.ruleOnPaper),
                  borderRadius: BorderRadius.circular(BrandRadius.control),
                ),
                title: Text(
                  item.cardName ??
                      item.proposedFields['card_name']?.toString() ??
                      'Untitled card',
                ),
                subtitle: Text(
                  '${item.bank ?? item.proposedFields['bank'] ?? 'Issuer pending'} · ${item.status}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => onSelected(item),
              ),
            );
          },
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(BrandSpacing.md),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: page.page > 1 ? () => onPage(page.page - 1) : null,
                child: const Text('Previous page'),
              ),
            ),
            const SizedBox(width: BrandSpacing.sm),
            Expanded(
              child: OutlinedButton(
                onPressed: page.hasMore ? () => onPage(page.page + 1) : null,
                child: const Text('Next page'),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _ReviewDetail extends StatelessWidget {
  const _ReviewDetail({
    required this.item,
    required this.submitting,
    required this.compact,
    required this.onBack,
    required this.onOperation,
  });
  final CardReviewItem? item;
  final bool submitting;
  final bool compact;
  final VoidCallback? onBack;
  final ValueChanged<CardReviewOperation> onOperation;

  @override
  Widget build(BuildContext context) {
    final value = item;
    if (value == null) {
      return const Center(child: Text('Select a review item.'));
    }
    final operations = value.lane == CardReviewLane.identity
        ? const [
            CardReviewOperation.approve,
            CardReviewOperation.merge,
            CardReviewOperation.reject,
            CardReviewOperation.retry,
          ]
        : const [
            CardReviewOperation.approve,
            CardReviewOperation.reject,
            CardReviewOperation.retry,
            CardReviewOperation.quarantine,
          ];
    return Stack(
      children: [
        FocusTraversalGroup(
          child: ListView(
            padding: const EdgeInsets.all(BrandSpacing.lg),
            children: [
              if (compact)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Back to review queue'),
                  ),
                ),
              _StateRail(item: value),
              const SizedBox(height: BrandSpacing.lg),
              Text(
                value.cardName ??
                    value.proposedFields['card_name']?.toString() ??
                    'Untitled card',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: BrandSpacing.xs),
              SelectableText(value.id),
              const SizedBox(height: BrandSpacing.lg),
              const Text(
                'Proposed fields',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: BrandSpacing.sm),
              if (value.proposedFields.isEmpty)
                const Text('No field changes supplied.')
              else
                for (final entry in value.proposedFields.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: BrandSpacing.sm),
                    child: Text(
                      '${entry.key.replaceAll('_', ' ')}: ${entry.value}',
                    ),
                  ),
              if (value.warningCodes.isNotEmpty) ...[
                const SizedBox(height: BrandSpacing.md),
                Text('Checks: ${value.warningCodes.join(', ')}'),
              ],
              const SizedBox(height: BrandSpacing.lg),
              const Text(
                'Evidence',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: BrandSpacing.sm),
              for (final evidence in value.evidence)
                BrandSurface(
                  tone: BrandSurfaceTone.evidence,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (evidence.excerpt case final excerpt?) Text(excerpt),
                      if (evidence.officialUrl case final url?) ...[
                        const SizedBox(height: BrandSpacing.sm),
                        SelectableText(url),
                      ],
                    ],
                  ),
                ),
              const SizedBox(height: BrandSpacing.lg),
              Wrap(
                spacing: BrandSpacing.sm,
                runSpacing: BrandSpacing.sm,
                children: [
                  for (final operation in operations)
                    SizedBox(
                      height: 48,
                      child: operation == CardReviewOperation.approve
                          ? FilledButton(
                              onPressed: submitting
                                  ? null
                                  : () => onOperation(operation),
                              child: Text(_operationLabel(operation)),
                            )
                          : OutlinedButton(
                              onPressed: submitting
                                  ? null
                                  : () => onOperation(operation),
                              child: Text(_operationLabel(operation)),
                            ),
                    ),
                ],
              ),
            ],
          ),
        ),
        if (submitting)
          const Positioned.fill(
            child: IgnorePointer(
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
      ],
    );
  }
}

class _StateRail extends StatelessWidget {
  const _StateRail({required this.item});
  final CardReviewItem item;

  @override
  Widget build(BuildContext context) => Semantics(
    label:
        'Selected review ${item.status}, last updated ${item.updatedAt.toIso8601String()}',
    child: Container(
      padding: const EdgeInsets.all(BrandSpacing.compact),
      decoration: const BoxDecoration(
        color: BrandColors.ledger,
        border: Border(
          left: BorderSide(color: BrandColors.focusDark, width: 4),
        ),
      ),
      child: Wrap(
        spacing: BrandSpacing.lg,
        runSpacing: BrandSpacing.sm,
        children: [
          Text(item.lane == CardReviewLane.identity ? 'IDENTITY' : 'BENEFIT'),
          Text('STATE  ${item.status.toUpperCase()}'),
          Text('UPDATED  ${_shortUtc(item.updatedAt)}'),
          if (item.confidence case final confidence?)
            Text('CONFIDENCE  ${(confidence * 100).round()}%'),
          if (item.parserVersion case final parser?) Text(parser),
        ],
      ),
    ),
  );
}

class _ConfirmationDialog extends StatefulWidget {
  const _ConfirmationDialog({
    required this.operation,
    required this.reasonRequired,
  });
  final CardReviewOperation operation;
  final bool reasonRequired;

  @override
  State<_ConfirmationDialog> createState() => _ConfirmationDialogState();
}

class _ConfirmationDialogState extends State<_ConfirmationDialog> {
  final controller = TextEditingController();
  String? error;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final merge = widget.operation == CardReviewOperation.merge;
    final needsInput = widget.reasonRequired || merge;
    return AlertDialog(
      title: Text('Confirm ${_operationLabel(widget.operation).toLowerCase()}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('This change is written only after the server confirms it.'),
          if (needsInput) ...[
            const SizedBox(height: BrandSpacing.md),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: merge ? 'Merge card ID' : 'Reason',
                errorText: error,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (needsInput && controller.text.trim().length < 2) {
              setState(
                () => error = merge
                    ? 'Add a card ID to continue.'
                    : 'Add a reason to continue.',
              );
              return;
            }
            Navigator.pop(context, needsInput ? controller.text : 'confirmed');
          },
          child: Text(switch (widget.operation) {
            CardReviewOperation.approve => 'Confirm approval',
            CardReviewOperation.merge => 'Confirm merge',
            CardReviewOperation.reject => 'Confirm rejection',
            CardReviewOperation.retry => 'Confirm retry',
            CardReviewOperation.quarantine => 'Confirm quarantine',
            CardReviewOperation.unquarantine => 'Confirm unquarantine',
            CardReviewOperation.editApprove => 'Confirm edits',
          }),
        ),
      ],
    );
  }
}

class _FailureState extends StatelessWidget {
  const _FailureState({required this.error, required this.onRetry});
  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => BrandStateView(
    title: error is AdminAuthenticationRequired
        ? 'Sign in again to continue.'
        : error is AdminAccessDenied
        ? 'Administrator access required.'
        : 'Card review queue could not be loaded.',
    message: 'The current queue is unchanged. Try again when ready.',
    icon: Icons.cloud_off_outlined,
    actionLabel: 'Try again',
    onAction: onRetry,
  );
}

String _operationLabel(CardReviewOperation value) => switch (value) {
  CardReviewOperation.approve => 'Approve',
  CardReviewOperation.editApprove => 'Edit & approve',
  CardReviewOperation.merge => 'Merge',
  CardReviewOperation.reject => 'Reject',
  CardReviewOperation.retry => 'Retry',
  CardReviewOperation.quarantine => 'Quarantine',
  CardReviewOperation.unquarantine => 'Unquarantine',
};

String _formatRefresh(DateTime value) =>
    'Refreshed ${value.day} ${_months[value.month - 1]} ${value.year}, ${_two(value.hour)}:${_two(value.minute)} UTC';
String _shortUtc(DateTime value) =>
    '${_two(value.day)} ${_months[value.month - 1]} ${_two(value.hour)}:${_two(value.minute)} UTC';
String _two(int value) => value.toString().padLeft(2, '0');
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
