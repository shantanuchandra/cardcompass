import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

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
    this.targetId,
  });

  final CardReviewLane lane;
  final int page;
  final int limit;
  final String? status;
  final String? targetId;
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
    this.initialLane = CardReviewLane.identity,
    this.openExternalUrl,
    this.onAuthenticationRequired,
    this.onAccessDenied,
  });

  final CardDataSource repository;
  final String? initialTargetId;
  final CardReviewLane initialLane;
  final Future<bool> Function(Uri url)? openExternalUrl;
  final Future<void> Function()? onAuthenticationRequired;
  final VoidCallback? onAccessDenied;

  @override
  ConsumerState<CardDataSection> createState() => _CardDataSectionState();
}

class _CardDataSectionState extends ConsumerState<CardDataSection> {
  late CardReviewLane _lane;
  String? _targetId;
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
    _lane = widget.initialLane;
    _targetId = widget.initialTargetId;
    _load(initial: true);
  }

  Future<void> _load({
    bool initial = false,
    int? page,
    bool retainMissingTarget = false,
  }) async {
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
          targetId: _targetId,
        ),
      );
      if (!mounted) return;
      final target = _targetId ?? _selected?.id;
      setState(() {
        final exact = next.items.where((item) => item.id == target).firstOrNull;
        if (retainMissingTarget && _targetId != null && exact == null) {
          _notice =
              'This review changed and is no longer available. The prior review context was not replaced.';
          _loading = false;
          _refreshing = false;
          return;
        }
        _page = next;
        _selected = exact;
        if (_targetId != null && exact != null) {
          _compactDetail = true;
        }
        if (_selected == null && _targetId == null && target == null) {
          _selected = next.items.firstOrNull;
        }
        if (_targetId != null && _selected == null) {
          _notice = 'This review is no longer available in the latest state.';
        }
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
      _targetId = null;
      _compactDetail = false;
    });
    await _load(initial: true, page: 1);
  }

  Future<void> _confirm(
    CardReviewOperation operation, {
    Map<String, dynamic> payload = const {},
    String? suppliedReason,
  }) async {
    final item = _selected;
    if (item == null || _submitting) return;
    final reasonRequired =
        operation == CardReviewOperation.reject ||
        operation == CardReviewOperation.quarantine;
    final reason =
        suppliedReason ??
        await showDialog<String>(
          context: context,
          builder: (context) => _ConfirmationDialog(
            operation: operation,
            reasonRequired: reasonRequired,
          ),
        );
    if (reason == null) return;
    final actionPayload = <String, dynamic>{...payload};
    if (item.lane == CardReviewLane.identity &&
        operation == CardReviewOperation.merge) {
      // Merge target selection is intentionally explicit rather than inferred.
      final mergeId = reason.trim();
      actionPayload['merge_card_id'] = mergeId;
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
          stagingId:
              item.lane == CardReviewLane.benefit &&
                  {
                    CardReviewOperation.approve,
                    CardReviewOperation.editApprove,
                    CardReviewOperation.reject,
                  }.contains(operation)
              ? item.stagingId
              : null,
          reason: (reasonRequired || suppliedReason != null)
              ? reason.trim()
              : null,
          payload: actionPayload,
        ),
      );
      if (!mounted) return;
      setState(() => _notice = '${_operationLabel(operation)} confirmed.');
      await _load();
    } on AdminStateConflict {
      if (!mounted) return;
      setState(() => _notice = 'This review changed. Check the latest state.');
      await _load(retainMissingTarget: true);
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
                    _targetId = null;
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
    onOpenUrl:
        widget.openExternalUrl ??
        (url) => launchUrl(url, mode: LaunchMode.externalApplication),
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

typedef _ReviewAction =
    Future<void> Function(
      CardReviewOperation operation, {
      Map<String, dynamic> payload,
      String? suppliedReason,
    });

class _ReviewDetail extends StatefulWidget {
  const _ReviewDetail({
    required this.item,
    required this.submitting,
    required this.compact,
    required this.onBack,
    required this.onOperation,
    required this.onOpenUrl,
  });
  final CardReviewItem? item;
  final bool submitting;
  final bool compact;
  final VoidCallback? onBack;
  final _ReviewAction onOperation;
  final Future<bool> Function(Uri url) onOpenUrl;

  @override
  State<_ReviewDetail> createState() => _ReviewDetailState();
}

class _ReviewDetailState extends State<_ReviewDetail> {
  static const _editableIdentityFields = {
    'cardName',
    'card_name',
    'network',
    'joining_fee',
    'annual_fee',
    'apr',
  };

  final _identityControllers = <String, TextEditingController>{};
  final _decisions = <String, String>{};
  final _benefitControllers = <String, Map<String, TextEditingController>>{};
  final _benefitReasonControllers = <String, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    _resetFor(widget.item);
  }

  @override
  void didUpdateWidget(covariant _ReviewDetail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item?.id != widget.item?.id ||
        oldWidget.item?.updatedAt != widget.item?.updatedAt) {
      _resetFor(widget.item);
    }
  }

  void _resetFor(CardReviewItem? item) {
    for (final controller in _identityControllers.values) {
      controller.dispose();
    }
    _identityControllers.clear();
    for (final controller in [
      ..._benefitControllers.values.expand((value) => value.values),
      ..._benefitReasonControllers.values,
    ]) {
      controller.dispose();
    }
    _benefitControllers.clear();
    _benefitReasonControllers.clear();
    _decisions.clear();
    if (item == null) return;
    for (final entry in item.proposedFields.entries.where(
      (entry) => _editableIdentityFields.contains(entry.key),
    )) {
      _identityControllers[entry.key] = TextEditingController(
        text: entry.value.toString(),
      );
    }
    for (final proposal in item.benefitProposals) {
      _decisions[proposal.key] = switch (proposal.kind) {
        BenefitProposalKind.removal ||
        BenefitProposalKind.unchanged => 'keep_existing',
        _ when !proposal.canApprove => 'reject',
        _ => 'approve',
      };
      _benefitControllers[proposal.key] = {
        for (final spec in _benefitFieldSpecs)
          spec.key: TextEditingController(
            text: _editableValue(proposal.proposed, spec),
          ),
      };
      _benefitReasonControllers[proposal.key] = TextEditingController();
    }
  }

  @override
  void dispose() {
    for (final controller in _identityControllers.values) {
      controller.dispose();
    }
    for (final controller in [
      ..._benefitControllers.values.expand((value) => value.values),
      ..._benefitReasonControllers.values,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> _editedIdentityPayload(CardReviewItem item) {
    final edited = <String, dynamic>{};
    for (final entry in _identityControllers.entries) {
      final original = item.proposedFields[entry.key];
      final text = entry.value.text.trim();
      edited[entry.key] = original is num ? num.tryParse(text) ?? text : text;
    }
    return {'proposed_fields': edited};
  }

  List<Map<String, dynamic>> _benefitDecisions(CardReviewItem item) =>
      item.benefitProposals.map((proposal) {
        final action = _decisions[proposal.key]!;
        final decision = proposal.decision(
          action,
          edited: _editedBenefit(proposal),
        );
        if (action == 'reject') {
          final reason = _benefitReasonControllers[proposal.key]!.text.trim();
          if (reason.isNotEmpty) decision['reason'] = reason;
        }
        return decision;
      }).toList();

  Map<String, dynamic> _editedBenefit(BenefitReviewProposal proposal) {
    final edited = <String, dynamic>{...proposal.proposed};
    final controllers = _benefitControllers[proposal.key]!;
    for (final spec in _benefitFieldSpecs) {
      final text = controllers[spec.key]!.text.trim();
      final original = _readPath(proposal.proposed, spec.key);
      if (text.isEmpty && original == null) continue;
      final Object value = switch (spec.kind) {
        _BenefitFieldKind.number =>
          num.tryParse(text) ??
              (throw FormatException('${spec.label} must be a number.')),
        _BenefitFieldKind.date => _validDate(text, spec.label),
        _BenefitFieldKind.list =>
          text
              .split(',')
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .take(50)
              .toList(),
        _BenefitFieldKind.text => text,
      };
      _writePath(edited, spec.key, value);
    }
    return edited;
  }

  Future<void> _submitBenefit(CardReviewItem item) async {
    final List<Map<String, dynamic>> decisions;
    try {
      decisions = _benefitDecisions(item);
    } on FormatException catch (error) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message.toString())));
      return;
    }
    if (decisions.isEmpty) return;
    final actions = decisions.map((value) => value['action']).toSet();
    final operation = actions.difference({'approve', 'keep_existing'}).isEmpty
        ? CardReviewOperation.approve
        : actions.length == 1 && actions.single == 'reject'
        ? CardReviewOperation.reject
        : CardReviewOperation.editApprove;
    if (operation == CardReviewOperation.editApprove &&
        decisions.any(
          (value) =>
              value['action'] == 'reject' &&
              (value['reason'] as String? ?? '').trim().length < 2,
        )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add a reason for each rejected benefit.'),
        ),
      );
      return;
    }
    await widget.onOperation(operation, payload: {'decisions': decisions});
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.item;
    if (value == null) {
      return const Center(child: Text('Select a review item.'));
    }
    return Stack(
      children: [
        FocusTraversalGroup(
          child: ListView(
            padding: const EdgeInsets.all(BrandSpacing.lg),
            children: [
              if (widget.compact)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: widget.onBack,
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
              if (value.lane == CardReviewLane.identity)
                _identityComparison(value)
              else
                _benefitComparison(value),
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
                      for (final field in evidence.fieldEvidence.entries)
                        Text(
                          '${field.key.replaceAll('_', ' ')}: ${field.value}',
                        ),
                      if ((evidence.officialUrl ?? evidence.sourceUrl)
                          case final url?) ...[
                        const SizedBox(height: BrandSpacing.sm),
                        TextButton.icon(
                          onPressed: () => widget.onOpenUrl(Uri.parse(url)),
                          icon: const Icon(Icons.open_in_new, size: 18),
                          label: Text(url),
                        ),
                      ],
                      if (evidence.retrievedAt case final retrieved?)
                        Text('Retrieved ${_shortUtc(retrieved)}'),
                    ],
                  ),
                ),
              const SizedBox(height: BrandSpacing.lg),
              _actions(value),
            ],
          ),
        ),
        if (widget.submitting)
          const Positioned.fill(
            child: IgnorePointer(
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
      ],
    );
  }

  Widget _identityComparison(CardReviewItem item) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Current vs proposed',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: BrandSpacing.sm),
      if (item.identityCandidates.isEmpty)
        const Text('No current catalog match. This will create a new identity.')
      else
        for (final candidate in item.identityCandidates)
          Text(
            'Current: ${candidate.bank ?? candidate.issuer ?? 'Unknown issuer'} · ${candidate.cardName ?? candidate.id}',
          ),
      const SizedBox(height: BrandSpacing.md),
      for (final entry in item.proposedFields.entries)
        if (_identityControllers[entry.key] case final controller?)
          Padding(
            padding: const EdgeInsets.only(bottom: BrandSpacing.sm),
            child: TextField(
              controller: controller,
              enabled: !widget.submitting && item.status == 'pending',
              decoration: InputDecoration(
                labelText: 'Proposed ${entry.key.replaceAll('_', ' ')}',
              ),
            ),
          )
        else if (entry.value is String ||
            entry.value is num ||
            entry.value is bool)
          Padding(
            padding: const EdgeInsets.only(bottom: BrandSpacing.sm),
            child: SelectableText(
              'Proposed ${entry.key.replaceAll('_', ' ')}: ${entry.value}',
            ),
          ),
    ],
  );

  Widget _benefitComparison(CardReviewItem item) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Benefit decisions',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      if (item.retrievedAt case final retrieved?)
        Text('Extraction retrieved ${_shortUtc(retrieved)}'),
      if (item.confidence case final confidence?)
        Text('Calculated confidence ${(confidence * 100).toStringAsFixed(0)}%'),
      if (item.attemptCount case final attempts?) Text('Attempts $attempts'),
      if (item.failureCategory case final failure?)
        Text('Failure category $failure'),
      if (item.nextRetryAt case final retry?)
        Text('Next retry ${_shortUtc(retry)}'),
      if (item.validationReasonCodes.isNotEmpty)
        Text('Validation reasons: ${item.validationReasonCodes.join(', ')}'),
      if (item.warningCodes.isNotEmpty)
        Text('Validation warnings: ${item.warningCodes.join(', ')}'),
      if (item.priorDecisionSummaries.isNotEmpty)
        Text('Prior decisions: ${item.priorDecisionSummaries.join('; ')}'),
      const SizedBox(height: BrandSpacing.sm),
      if (item.benefitProposals.isEmpty)
        const Text('No complete staged benefit proposal is available.')
      else
        for (final proposal in item.benefitProposals)
          BrandSurface(
            padding: const EdgeInsets.all(BrandSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  proposal.title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  'Current: ${proposal.current.isEmpty ? 'None' : proposal.current}',
                ),
                Text(
                  'Proposed: ${proposal.proposed.isEmpty ? 'None' : proposal.proposed}',
                ),
                DropdownButton<String>(
                  value: _decisions[proposal.key],
                  onChanged: widget.submitting
                      ? null
                      : (value) =>
                            setState(() => _decisions[proposal.key] = value!),
                  items: [
                    for (final action in _allowedDecisionActions(proposal))
                      DropdownMenuItem(
                        value: action,
                        child: Text(switch (action) {
                          'approve' => 'Approve proposal',
                          'edit' => 'Edit proposal',
                          'reject' => 'Reject proposal',
                          _ => 'Keep existing',
                        }),
                      ),
                  ],
                ),
                if (_decisions[proposal.key] == 'edit')
                  Wrap(
                    spacing: BrandSpacing.sm,
                    runSpacing: BrandSpacing.sm,
                    children: [
                      for (final spec in _benefitFieldSpecs)
                        SizedBox(
                          width: 280,
                          child: TextField(
                            key: Key(
                              'benefit-edit-${proposal.key}-${spec.key}',
                            ),
                            controller:
                                _benefitControllers[proposal.key]![spec.key],
                            enabled: !widget.submitting,
                            keyboardType: spec.kind == _BenefitFieldKind.number
                                ? const TextInputType.numberWithOptions(
                                    decimal: true,
                                  )
                                : spec.kind == _BenefitFieldKind.date
                                ? TextInputType.datetime
                                : TextInputType.text,
                            inputFormatters: [
                              LengthLimitingTextInputFormatter(
                                spec.kind == _BenefitFieldKind.list
                                    ? 4000
                                    : 2000,
                              ),
                            ],
                            decoration: InputDecoration(
                              labelText: spec.label,
                              helperText: switch (spec.kind) {
                                _BenefitFieldKind.list =>
                                  'Comma-separated values',
                                _ => null,
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
                if (_decisions[proposal.key] == 'reject')
                  TextField(
                    controller: _benefitReasonControllers[proposal.key],
                    decoration: const InputDecoration(
                      labelText: 'Benefit rejection reason',
                    ),
                  ),
              ],
            ),
          ),
      if (item.benefitConflictCodes.isNotEmpty) ...[
        const SizedBox(height: BrandSpacing.sm),
        Text(
          'Unresolved conflicts: ${item.benefitConflictCodes.join(', ')}. Refresh or quarantine this extraction before deciding.',
        ),
      ],
    ],
  );

  List<String> _allowedDecisionActions(BenefitReviewProposal proposal) {
    if (!proposal.canApprove) {
      return proposal.current.isEmpty
          ? const ['reject']
          : const ['reject', 'keep_existing'];
    }
    return switch (proposal.kind) {
      BenefitProposalKind.addition => const ['approve', 'edit', 'reject'],
      BenefitProposalKind.modification => const [
        'approve',
        'edit',
        'reject',
        'keep_existing',
      ],
      BenefitProposalKind.removal => const ['reject', 'keep_existing'],
      BenefitProposalKind.unchanged => const ['keep_existing'],
    };
  }

  Widget _actions(CardReviewItem item) {
    final controls = <Widget>[];
    void add(
      String label,
      CardReviewOperation operation, {
      Map<String, dynamic> payload = const {},
    }) {
      controls.add(
        SizedBox(
          height: 48,
          child: operation == CardReviewOperation.approve
              ? FilledButton(
                  onPressed: widget.submitting
                      ? null
                      : () => widget.onOperation(operation, payload: payload),
                  child: Text(label),
                )
              : OutlinedButton(
                  onPressed: widget.submitting
                      ? null
                      : () => widget.onOperation(operation, payload: payload),
                  child: Text(label),
                ),
        ),
      );
    }

    if (item.lane == CardReviewLane.identity && item.status == 'pending') {
      add('Approve', CardReviewOperation.approve);
      controls.add(
        SizedBox(
          height: 48,
          child: OutlinedButton(
            onPressed: widget.submitting
                ? null
                : () => widget.onOperation(
                    CardReviewOperation.editApprove,
                    payload: _editedIdentityPayload(item),
                  ),
            child: const Text('Edit & approve'),
          ),
        ),
      );
      add('Merge', CardReviewOperation.merge);
      add('Reject', CardReviewOperation.reject);
      add('Retry', CardReviewOperation.retry);
    } else if (item.lane == CardReviewLane.benefit) {
      if ({'staged', 'review_required'}.contains(item.status) &&
          item.stagingId != null &&
          item.benefitProposals.isNotEmpty &&
          item.benefitConflictCodes.isEmpty) {
        controls.add(
          SizedBox(
            height: 48,
            child: FilledButton(
              onPressed: widget.submitting ? null : () => _submitBenefit(item),
              child: const Text('Submit benefit decisions'),
            ),
          ),
        );
      }
      if ({'failed', 'review_required', 'quarantined'}.contains(item.status)) {
        add('Retry', CardReviewOperation.retry);
      }
      if ({
        'queued',
        'failed',
        'review_required',
        'staged',
      }.contains(item.status)) {
        add('Quarantine', CardReviewOperation.quarantine);
      }
      if (item.status == 'quarantined') {
        add('Unquarantine', CardReviewOperation.unquarantine);
      }
    }
    if (controls.isEmpty) {
      return const Text('No actions are available for this state.');
    }
    return Wrap(
      spacing: BrandSpacing.sm,
      runSpacing: BrandSpacing.sm,
      children: controls,
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

enum _BenefitFieldKind { text, number, date, list }

final class _BenefitFieldSpec {
  const _BenefitFieldSpec(
    this.key,
    this.label, [
    this.kind = _BenefitFieldKind.text,
  ]);
  final String key;
  final String label;
  final _BenefitFieldKind kind;
}

const _benefitFieldSpecs = <_BenefitFieldSpec>[
  _BenefitFieldSpec('title', 'Title'),
  _BenefitFieldSpec('description', 'Description'),
  _BenefitFieldSpec('benefit_category', 'Benefit category'),
  _BenefitFieldSpec('benefit_type', 'Benefit type'),
  _BenefitFieldSpec('partners', 'Partners', _BenefitFieldKind.list),
  _BenefitFieldSpec('regions', 'Regions', _BenefitFieldKind.list),
  _BenefitFieldSpec('exclusions', 'Exclusions', _BenefitFieldKind.list),
  _BenefitFieldSpec('source_url', 'Source URL'),
  _BenefitFieldSpec('valid_from', 'Valid from', _BenefitFieldKind.date),
  _BenefitFieldSpec('valid_until', 'Valid until', _BenefitFieldKind.date),
  _BenefitFieldSpec('value_config.unit', 'Value unit'),
  _BenefitFieldSpec('value_config.currency_unit', 'Value currency'),
  _BenefitFieldSpec('value_config.category', 'Value category'),
  _BenefitFieldSpec('value_config.discount_type', 'Discount type'),
  _BenefitFieldSpec('value_config.value', 'Value', _BenefitFieldKind.number),
  _BenefitFieldSpec('value_config.rate', 'Rate', _BenefitFieldKind.number),
  _BenefitFieldSpec('value_config.cap', 'Cap', _BenefitFieldKind.number),
  _BenefitFieldSpec(
    'value_config.threshold',
    'Threshold',
    _BenefitFieldKind.number,
  ),
  _BenefitFieldSpec('value_config.frequency', 'Frequency'),
  _BenefitFieldSpec('value_config.period', 'Period'),
  _BenefitFieldSpec(
    'value_config.restrictions',
    'Restrictions',
    _BenefitFieldKind.list,
  ),
  _BenefitFieldSpec('value_config.usage_period', 'Usage period'),
  _BenefitFieldSpec('value_config.milestone_type', 'Milestone type'),
  _BenefitFieldSpec('value_config.platform', 'Platform'),
  _BenefitFieldSpec(
    'value_config.discount_percent',
    'Discount percent',
    _BenefitFieldKind.number,
  ),
  _BenefitFieldSpec(
    'value_config.discount_amount',
    'Discount amount',
    _BenefitFieldKind.number,
  ),
  _BenefitFieldSpec(
    'value_config.max_discount_per_transaction',
    'Max discount per transaction',
    _BenefitFieldKind.number,
  ),
  _BenefitFieldSpec(
    'value_config.max_usage_per_month',
    'Max usage per month',
    _BenefitFieldKind.number,
  ),
  _BenefitFieldSpec(
    'value_config.max_usage_per_period',
    'Max usage per period',
    _BenefitFieldKind.number,
  ),
  _BenefitFieldSpec(
    'value_config.monthly_cap',
    'Monthly cap',
    _BenefitFieldKind.number,
  ),
  _BenefitFieldSpec(
    'value_config.annual_cap',
    'Annual cap',
    _BenefitFieldKind.number,
  ),
  _BenefitFieldSpec(
    'value_config.threshold_amount',
    'Threshold amount',
    _BenefitFieldKind.number,
  ),
  _BenefitFieldSpec(
    'value_config.reward_value',
    'Reward value',
    _BenefitFieldKind.number,
  ),
  _BenefitFieldSpec(
    'value_config.multiplier',
    'Multiplier',
    _BenefitFieldKind.number,
  ),
  _BenefitFieldSpec(
    'value_config.base_rate',
    'Base rate',
    _BenefitFieldKind.number,
  ),
];

Object? _readPath(Map<String, dynamic> source, String path) {
  final pieces = path.split('.');
  Object? value = source;
  for (final piece in pieces) {
    if (value is! Map) return null;
    value = value[piece];
  }
  return value;
}

String _editableValue(Map<String, dynamic> source, _BenefitFieldSpec spec) {
  final value = _readPath(source, spec.key);
  if (value == null) return '';
  if (value is List) return value.join(', ');
  if (value is Map) return jsonEncode(value);
  return value.toString();
}

void _writePath(Map<String, dynamic> target, String path, Object value) {
  final pieces = path.split('.');
  if (pieces.length == 1) {
    target[path] = value;
    return;
  }
  final parent = Map<String, dynamic>.from(
    target[pieces.first] is Map
        ? target[pieces.first] as Map
        : const <String, dynamic>{},
  );
  parent[pieces.last] = value;
  target[pieces.first] = parent;
}

String _validDate(String value, String label) {
  if (value.length > 100 || DateTime.tryParse(value) == null) {
    throw FormatException('$label must be a valid date.');
  }
  return value;
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
