import 'package:flutter/material.dart';

import '../data/admin_catalog_repository.dart';
import '../models/benefit_enrichment_review.dart';

class BenefitEnrichmentReviewPanel extends StatefulWidget {
  const BenefitEnrichmentReviewPanel({
    required this.repository,
    required this.onAuthorizationRequired,
    required this.onOpenUrl,
    super.key,
  });

  final BenefitEnrichmentRepository repository;
  final VoidCallback onAuthorizationRequired;
  final ValueChanged<Uri> onOpenUrl;

  @override
  State<BenefitEnrichmentReviewPanel> createState() =>
      _BenefitEnrichmentReviewPanelState();
}

class _BenefitEnrichmentReviewPanelState
    extends State<BenefitEnrichmentReviewPanel> {
  late Future<BenefitEnrichmentReviewPage> _page = _load();
  String? _actionError;
  var _pageNumber = 1;
  var _mutating = false;

  Future<BenefitEnrichmentReviewPage> _load() =>
      widget.repository.loadReviewPage(page: _pageNumber);

  Future<void> _reload() async {
    setState(() {
      _actionError = null;
      _page = _load();
    });
    await _page;
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _actionError = null;
      _mutating = true;
    });
    try {
      await action();
      if (mounted) {
        await _reload();
      }
    } on AdminAuthorizationRequired {
      if (mounted) {
        widget.onAuthorizationRequired();
      }
    } on AdminAccessDenied {
      if (mounted) {
        setState(
          () => _actionError =
              'Administrator access is required for benefit reviews.',
        );
      }
    } on AdminCatalogRequestFailed catch (error) {
      if (mounted) {
        setState(() => _actionError = error.message);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _actionError = 'Could not update this enrichment. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<String?> _askReason(String title) async {
    var reason = '';
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          autofocus: true,
          minLines: 2,
          maxLines: 5,
          onChanged: (value) => reason = value.trim(),
          decoration: const InputDecoration(labelText: 'Reason (required)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (reason.length >= 3) Navigator.pop(context, reason);
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmApproval() async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Apply these benefit changes?'),
          content: const Text(
            'This updates the existing catalog card with the proposed benefit changes. Check the source evidence and warnings before continuing.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Apply changes'),
            ),
          ],
        ),
      ) ??
      false;

  Future<String?> _confirmRetirement(BenefitPossibleRemoval removal) async {
    var reason = '';
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Retire ${removal.benefit.label}?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This retires only this card-to-benefit mapping. Confirm the issuer evidence and provide an audit reason.',
            ),
            const SizedBox(height: 12),
            TextField(
              autofocus: true,
              minLines: 2,
              maxLines: 5,
              onChanged: (value) => reason = value.trim(),
              decoration: const InputDecoration(
                labelText: 'Retirement reason (required)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (reason.length >= 3) Navigator.pop(context, reason);
            },
            child: const Text('Retire'),
          ),
        ],
      ),
    );
  }

  Future<void> _edit(BenefitEnrichmentReview item) async {
    final decision = item.staging.decisions.firstWhereOrNull(
      (decision) =>
          decision.editedBenefit != null ||
          decision.benefit != null ||
          decision.proposed != null,
    );
    final diff = item.staging.extractedData.diff;
    final candidate =
        decision?.editedBenefit ??
        decision?.proposed ??
        decision?.benefit ??
        diff.additions.firstOrNull ??
        diff.modifications.firstOrNull?.proposed ??
        diff.conflicts.firstOrNull?.proposed.firstOrNull;
    if (candidate == null) {
      setState(
        () => _actionError = 'This enrichment has no proposed benefit to edit.',
      );
      return;
    }
    final title = TextEditingController(text: candidate.title);
    final description = TextEditingController(text: candidate.description);
    final edited = await showDialog<BenefitReviewDecision>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit benefit before approval'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                decoration: const InputDecoration(labelText: 'Benefit title'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: description,
                decoration: const InputDecoration(labelText: 'Description'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              (decision ??
                      BenefitReviewDecision(
                        action: 'edit',
                        liveBenefitId: candidate.liveBenefitId,
                        dedupeKey: candidate.dedupeKey,
                        benefit: candidate,
                        proposed: candidate,
                      ))
                  .withEditedBenefit(
                    candidate.copyWith(
                      title: title.text.trim(),
                      description: description.text.trim(),
                    ),
                  ),
            ),
            child: const Text('Approve edit'),
          ),
        ],
      ),
    );
    title.dispose();
    description.dispose();
    if (edited != null) {
      await _run(() => widget.repository.editApprove(item, [edited]));
    }
  }

  Future<void> _resolveConflicts(BenefitEnrichmentReview item) async {
    final decisions = await showDialog<List<BenefitReviewDecision>>(
      context: context,
      builder: (context) => _ConflictResolutionDialog(
        conflicts: item.staging.extractedData.diff.conflicts,
      ),
    );
    if (decisions != null) {
      await _run(() => widget.repository.editApprove(item, decisions));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<BenefitEnrichmentReviewPage>(
      future: _page,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          if (snapshot.error is AdminAuthorizationRequired) {
            return _AuthorizationRequired(
              onAuthorize: widget.onAuthorizationRequired,
            );
          }
          final message = switch (snapshot.error) {
            AdminAccessDenied() =>
              'Administrator access is required for benefit reviews.',
            FormatException() =>
              'Malformed v6 review data was rejected. Refresh after the ingestion record is repaired.',
            _ => 'Could not load benefit enrichment reviews.',
          };
          return _MessageState(message: message, onRetry: _reload);
        }
        final page = snapshot.data!;
        return RefreshIndicator(
          onRefresh: _reload,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _ProgressSummary(
                counts: page.counts,
                history: page.history,
                movieMappingHealth: page.movieMappingHealth,
              ),
              if (_actionError != null) ...[
                const SizedBox(height: 16),
                MaterialBanner(
                  content: Text(_actionError!),
                  actions: [
                    TextButton(
                      onPressed: () => setState(() => _actionError = null),
                      child: const Text('Dismiss'),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              if (page.items.isEmpty)
                const _MessageState(
                  message: 'No benefit enrichment jobs need review.',
                )
              else
                ...page.items.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _BenefitReviewCard(
                      item: item,
                      onOpenUrl: widget.onOpenUrl,
                      onApprove: !_mutating && item.canBulkApply
                          ? () async {
                              if (await _confirmApproval()) {
                                await _run(
                                  () => widget.repository.approve(item),
                                );
                              }
                            }
                          : null,
                      onEdit: !_mutating && item.canReview
                          ? () => item.hasConflicts
                                ? _resolveConflicts(item)
                                : _edit(item)
                          : null,
                      onReject: !_mutating && item.canReview
                          ? () async {
                              final reason = await _askReason(
                                'Reject benefit enrichment',
                              );
                              if (reason != null) {
                                await _run(
                                  () => widget.repository.reject(item, reason),
                                );
                              }
                            }
                          : null,
                      onRetire: !_mutating && item.canReview
                          ? (removal) async {
                              final reason = await _confirmRetirement(removal);
                              if (reason != null) {
                                await _run(
                                  () => widget.repository.retire(
                                    item,
                                    removal,
                                    reason,
                                  ),
                                );
                              }
                            }
                          : null,
                      onRetry:
                          !_mutating &&
                              (item.status == 'failed' ||
                                  item.status == 'review_required')
                          ? () => _run(() => widget.repository.retry(item))
                          : null,
                      onQuarantine: _mutating
                          ? null
                          : item.isQuarantined
                          ? () =>
                                _run(() => widget.repository.unquarantine(item))
                          : item.canQuarantine
                          ? () async {
                              final reason = await _askReason(
                                'Quarantine enrichment job',
                              );
                              if (reason != null) {
                                await _run(
                                  () => widget.repository.quarantine(
                                    item,
                                    reason,
                                  ),
                                );
                              }
                            }
                          : null,
                    ),
                  ),
                ),
              if (page.page > 1 || page.hasMore)
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: page.page > 1 && !_mutating
                          ? () {
                              setState(() {
                                _pageNumber = page.page - 1;
                                _page = _load();
                              });
                            }
                          : null,
                      child: const Text('Previous page'),
                    ),
                    OutlinedButton(
                      onPressed: page.hasMore && !_mutating
                          ? () {
                              setState(() {
                                _pageNumber = page.page + 1;
                                _page = _load();
                              });
                            }
                          : null,
                      child: const Text('Next page'),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

enum _ConflictAction { approve, edit, reject }

class _ConflictChoice {
  const _ConflictChoice(this.action, this.proposalIndex);

  final _ConflictAction action;
  final int proposalIndex;
}

class _ConflictResolutionDialog extends StatefulWidget {
  const _ConflictResolutionDialog({required this.conflicts});

  final List<BenefitConflict> conflicts;

  @override
  State<_ConflictResolutionDialog> createState() =>
      _ConflictResolutionDialogState();
}

class _ConflictResolutionDialogState extends State<_ConflictResolutionDialog> {
  final _choices = <int, _ConflictChoice>{};
  final _titles = <int, TextEditingController>{};
  final _descriptions = <int, TextEditingController>{};
  final _reasons = <int, TextEditingController>{};
  final _rejectedCurrent = <String>{};
  final _currentReasons = <String, TextEditingController>{};

  @override
  void dispose() {
    for (final controller in [
      ..._titles.values,
      ..._descriptions.values,
      ..._reasons.values,
      ..._currentReasons.values,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  String _label(_ConflictAction action, BenefitProposal proposal) =>
      switch (action) {
        _ConflictAction.approve => 'Approve unchanged — ${proposal.label}',
        _ConflictAction.edit => 'Edit — ${proposal.label}',
        _ConflictAction.reject => 'Reject alternative — ${proposal.label}',
      };

  void _select(int group, String? encoded) {
    if (encoded == null) return;
    final parts = encoded.split(':');
    final action = _ConflictAction.values.byName(parts.first);
    final proposalIndex = int.parse(parts.last);
    final proposal = widget.conflicts[group].proposed[proposalIndex];
    final previous = _choices[group];
    setState(() {
      _choices[group] = _ConflictChoice(action, proposalIndex);
      if (action == _ConflictAction.edit) {
        final title = _titles.putIfAbsent(
          group,
          () => TextEditingController(text: proposal.title),
        );
        final description = _descriptions.putIfAbsent(
          group,
          () => TextEditingController(text: proposal.description),
        );
        if (previous?.action != action ||
            previous?.proposalIndex != proposalIndex) {
          title.text = proposal.title ?? '';
          description.text = proposal.description ?? '';
        }
      }
      if (action == _ConflictAction.reject) {
        final reason = _reasons.putIfAbsent(group, TextEditingController.new);
        if (previous?.action != action ||
            previous?.proposalIndex != proposalIndex) {
          reason.clear();
        }
      }
    });
  }

  bool get _complete {
    for (var group = 0; group < widget.conflicts.length; group += 1) {
      final conflict = widget.conflicts[group];
      if (conflict.proposed.isEmpty) {
        final prefix = '$group:';
        if (_rejectedCurrent.where((key) => key.startsWith(prefix)).length !=
            1) {
          return false;
        }
        continue;
      }
      final choice = _choices[group];
      if (choice == null) return false;
      if (choice.action == _ConflictAction.edit &&
          (_titles[group]?.text.trim().length ?? 0) < 2) {
        return false;
      }
      if (choice.action == _ConflictAction.reject &&
          (_reasons[group]?.text.trim().length ?? 0) < 3) {
        return false;
      }
    }
    for (final key in _rejectedCurrent) {
      if ((_currentReasons[key]?.text.trim().length ?? 0) < 3) return false;
    }
    return true;
  }

  List<BenefitReviewDecision> _decisions() {
    final decisions = <BenefitReviewDecision>[];
    for (var group = 0; group < widget.conflicts.length; group += 1) {
      final choice = _choices[group];
      if (choice == null) continue;
      final proposal = widget.conflicts[group].proposed[choice.proposalIndex];
      decisions.add(switch (choice.action) {
        _ConflictAction.approve => BenefitReviewDecision(
          action: 'approve',
          dedupeKey: proposal.dedupeKey,
          benefit: proposal,
        ),
        _ConflictAction.edit => BenefitReviewDecision(
          action: 'edit',
          dedupeKey: proposal.dedupeKey,
          benefit: proposal,
          proposed: proposal,
          editedBenefit: proposal.copyWith(
            title: _titles[group]!.text.trim(),
            description: _descriptions[group]!.text.trim(),
          ),
        ),
        _ConflictAction.reject => BenefitReviewDecision(
          action: 'reject',
          reason: _reasons[group]!.text.trim(),
          dedupeKey: proposal.dedupeKey,
          benefit: proposal,
        ),
      });
    }
    for (var group = 0; group < widget.conflicts.length; group += 1) {
      for (
        var currentIndex = 0;
        currentIndex < widget.conflicts[group].current.length;
        currentIndex += 1
      ) {
        final key = '$group:$currentIndex';
        if (!_rejectedCurrent.contains(key)) continue;
        final current = widget.conflicts[group].current[currentIndex];
        decisions.add(
          BenefitReviewDecision(
            action: 'reject',
            reason: _currentReasons[key]!.text.trim(),
            liveBenefitId: current.liveBenefitId,
            dedupeKey: current.dedupeKey,
            current: current,
          ),
        );
      }
    }
    return decisions;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Resolve benefit conflicts'),
    content: SizedBox(
      width: 560,
      height: 480,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Choose exactly one outcome for every conflict. Selecting an unchanged proposal publishes its exact staged terms.',
            ),
            const SizedBox(height: 12),
            for (var group = 0; group < widget.conflicts.length; group += 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Conflict ${group + 1}: ${widget.conflicts[group].code ?? 'Unspecified conflict'}',
                    ),
                    if (widget.conflicts[group].proposed.isNotEmpty)
                      DropdownButtonFormField<String>(
                        key: ValueKey('conflict-resolution-$group'),
                        initialValue: _choices[group] == null
                            ? null
                            : '${_choices[group]!.action.name}:${_choices[group]!.proposalIndex}',
                        decoration: const InputDecoration(
                          labelText: 'Required resolution',
                        ),
                        items: [
                          for (
                            var proposalIndex = 0;
                            proposalIndex <
                                widget.conflicts[group].proposed.length;
                            proposalIndex += 1
                          )
                            for (final action in _ConflictAction.values)
                              DropdownMenuItem(
                                value: '${action.name}:$proposalIndex',
                                child: Text(
                                  _label(
                                    action,
                                    widget
                                        .conflicts[group]
                                        .proposed[proposalIndex],
                                  ),
                                ),
                              ),
                        ],
                        onChanged: (value) => _select(group, value),
                      )
                    else
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'Select exactly one current benefit to reject.',
                        ),
                      ),
                    for (
                      var currentIndex = 0;
                      currentIndex < widget.conflicts[group].current.length;
                      currentIndex += 1
                    ) ...[
                      Builder(
                        builder: (context) {
                          final current =
                              widget.conflicts[group].current[currentIndex];
                          final key = '$group:$currentIndex';
                          return CheckboxListTile(
                            key: ValueKey(
                              'conflict-current-reject-$group-$currentIndex',
                            ),
                            contentPadding: EdgeInsets.zero,
                            value: _rejectedCurrent.contains(key),
                            onChanged: current.liveBenefitId == null
                                ? null
                                : (selected) {
                                    setState(() {
                                      if (selected == true) {
                                        if (widget
                                            .conflicts[group]
                                            .proposed
                                            .isEmpty) {
                                          _rejectedCurrent.removeWhere(
                                            (candidate) =>
                                                candidate.startsWith('$group:'),
                                          );
                                        }
                                        _rejectedCurrent.add(key);
                                        _currentReasons.putIfAbsent(
                                          key,
                                          TextEditingController.new,
                                        );
                                      } else {
                                        _rejectedCurrent.remove(key);
                                      }
                                    });
                                  },
                            title: Text(
                              '${widget.conflicts[group].proposed.isEmpty ? 'Reject' : 'Also reject'} current — ${current.label}',
                            ),
                          );
                        },
                      ),
                      if (_rejectedCurrent.contains('$group:$currentIndex'))
                        TextField(
                          key: ValueKey(
                            'conflict-current-reason-$group-$currentIndex',
                          ),
                          controller: _currentReasons['$group:$currentIndex'],
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'Current-target rejection reason',
                          ),
                        ),
                    ],
                    if (_choices[group]?.action == _ConflictAction.edit) ...[
                      const SizedBox(height: 8),
                      TextField(
                        key: ValueKey('conflict-title-$group'),
                        controller: _titles[group],
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Benefit title',
                        ),
                      ),
                      TextField(
                        key: ValueKey('conflict-description-$group'),
                        controller: _descriptions[group],
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Description',
                        ),
                      ),
                    ],
                    if (_choices[group]?.action == _ConflictAction.reject) ...[
                      const SizedBox(height: 8),
                      TextField(
                        key: ValueKey('conflict-reason-$group'),
                        controller: _reasons[group],
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Targeted rejection reason',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _complete
            ? () => Navigator.pop(context, _decisions())
            : null,
        child: const Text('Submit conflict resolutions'),
      ),
    ],
  );
}

class _ProgressSummary extends StatelessWidget {
  const _ProgressSummary({
    required this.counts,
    required this.history,
    required this.movieMappingHealth,
  });
  final BenefitEnrichmentCounts counts;
  final List<BenefitJobHistory> history;
  final MovieBenefitMappingHealth movieMappingHealth;

  @override
  Widget build(BuildContext context) {
    final scheduled = counts.byRunMode['scheduled'] ?? 0;
    final pilot = counts.byRunMode['pilot'] ?? 0;
    final completed = counts.byStatus['completed'] ?? 0;
    final failed = counts.byStatus['failed'] ?? 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Benefit enrichment',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Review evidence-backed changes to benefits on cards already in the catalog.',
            ),
            const SizedBox(height: 12),
            Text('Job run coverage: $scheduled scheduled · $pilot pilot'),
            Text('All jobs by status: $completed completed · $failed failed'),
            Text(
              'Movies mapping health: ${movieMappingHealth.mapped} / ${movieMappingHealth.active} mapped · ${movieMappingHealth.orphaned} orphaned',
            ),
            if (history.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Job history: ${history.map((job) => '${job.runMode} ${job.status}').join(' · ')}',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BenefitReviewCard extends StatelessWidget {
  const _BenefitReviewCard({
    required this.item,
    required this.onOpenUrl,
    this.onApprove,
    this.onEdit,
    this.onReject,
    this.onRetire,
    this.onRetry,
    this.onQuarantine,
  });

  final BenefitEnrichmentReview item;
  final ValueChanged<Uri> onOpenUrl;
  final VoidCallback? onApprove;
  final VoidCallback? onEdit;
  final VoidCallback? onReject;
  final ValueChanged<BenefitPossibleRemoval>? onRetire;
  final VoidCallback? onRetry;
  final VoidCallback? onQuarantine;

  @override
  Widget build(BuildContext context) {
    final source = Uri.tryParse(
      item.canonicalUrl ?? item.staging.sourceUrl ?? '',
    );
    final diff = item.staging.extractedData.diff;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${item.issuer} · ${item.cardName}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'Source/parser: ${item.runMode} · ${item.parserVersion ?? 'unknown'} · ${item.status} · attempt ${item.attemptCount}',
            ),
            if (item.crawlerDiscoveredWithoutStatementSignal ||
                item.staging.lacksStatementEvidence) ...[
              const SizedBox(height: 8),
              const Text(
                'Crawler-discovered card — statement evidence is unavailable.',
              ),
            ],
            if (source != null && source.hasScheme) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => onOpenUrl(source),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open official source'),
              ),
            ],
            if (item.staging.extractedData.retrievedAt != null)
              Text('Retrieved: ${item.staging.extractedData.retrievedAt}'),
            if (item.staging.extractedData.crawl.observedAt != null)
              Text(
                'Crawl observed: ${item.staging.extractedData.crawl.observedAt}',
              ),
            if (item.staging.extractedData.crawl.complete == false) ...[
              const SizedBox(height: 8),
              Text(
                'Incomplete crawl — ${item.staging.extractedData.crawl.readableReason ?? 'required evidence is missing'}',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (item.staging.extractedData.crawl.sourceAttempts.isNotEmpty) ...[
              const Divider(),
              const Text('Source attempts'),
              ...item.staging.extractedData.crawl.sourceAttempts.map(
                (attempt) => Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: SelectableText(
                    '${attempt.readableRole} · ${attempt.readableStatus}'
                    '${attempt.httpStatus == null ? '' : ' · ${attempt.httpStatus}'}'
                    '${attempt.errorCode == null ? '' : ' · ${attempt.errorCode}'}'
                    '${attempt.attemptedAt == null ? '' : ' · ${attempt.attemptedAt}'}\n'
                    '${attempt.url}',
                  ),
                ),
              ),
            ],
            if (diff.modifications.isNotEmpty) ...[
              const Divider(),
              const Text('Current'),
              ...diff.modifications.map(
                (change) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (change.changeType == 'identity_migration')
                      const Text('Identity migration'),
                    _DiffRow(
                      current: change.current,
                      proposed: change.proposed,
                    ),
                  ],
                ),
              ),
            ],
            if (diff.additions.isNotEmpty) ...[
              const Divider(),
              const Text('Proposed'),
              ...diff.additions.map(_ProposalEvidence.new),
            ],
            if (diff.possibleRemovals.isNotEmpty) ...[
              const Divider(),
              const Text('Possible removals (informational)'),
              ...diff.possibleRemovals.map(
                (removal) => _RemovalEvidence(
                  removal: removal,
                  onRetire:
                      removal.retirementEligible &&
                          removal.benefit.liveBenefitId != null
                      ? onRetire
                      : null,
                ),
              ),
            ],
            if (diff.unchanged.isNotEmpty) ...[
              const Divider(),
              const Text('Unchanged'),
              ...diff.unchanged.map(
                (change) => _DiffRow(
                  current: change.current,
                  proposed: change.proposed,
                ),
              ),
            ],
            if (diff.conflicts.isNotEmpty) ...[
              const Divider(),
              const Text('Conflicts'),
              Text(
                'Resolve each conflict with one unchanged selection, edit, or targeted rejection. Global reject remains separate. Bulk apply is disabled.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              ...diff.conflicts.expand(
                (conflict) => [
                  Text('Current: ${conflict.code ?? 'Unspecified conflict'}'),
                  ...conflict.current.map(_ProposalEvidence.new),
                  Text('Proposed: ${conflict.code ?? 'Unspecified conflict'}'),
                  ...conflict.proposed.map(_ProposalEvidence.new),
                ],
              ),
            ],
            if (item.staging.sourceEvidence.isNotEmpty) ...[
              const Divider(),
              const Text('Evidence'),
              ...item.staging.sourceEvidence.map(
                (evidence) => Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        evidence.sourceExcerpt ??
                            evidence.evidence.values.join(' · '),
                      ),
                      if (evidence.dedupeKey != null)
                        SelectableText('Benefit key: ${evidence.dedupeKey}'),
                      if (evidence.offerSubject != null)
                        Text('Condition: ${evidence.offerSubject}'),
                      if (evidence.sourceUrl != null)
                        SelectableText('Source: ${evidence.sourceUrl}'),
                      if (evidence.contentHash != null)
                        SelectableText('Content hash: ${evidence.contentHash}'),
                    ],
                  ),
                ),
              ),
            ],
            if (item.failureCategory != null)
              Text('Failure: ${item.failureCategory}'),
            if (item.nextRetryAt != null)
              Text('Next retry: ${item.nextRetryAt}'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: onApprove,
                  child: const Text('Approve benefit changes'),
                ),
                OutlinedButton(
                  onPressed: onEdit,
                  child: Text(
                    item.hasConflicts
                        ? 'Resolve conflicts'
                        : 'Edit proposed changes',
                  ),
                ),
                TextButton(
                  onPressed: onReject,
                  child: const Text('Reject changes'),
                ),
                TextButton(
                  onPressed: onRetry,
                  child: const Text('Retry processing'),
                ),
                TextButton(
                  onPressed: onQuarantine,
                  child: Text(
                    item.isQuarantined ? 'Unquarantine' : 'Quarantine',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DiffRow extends StatelessWidget {
  const _DiffRow({required this.current, required this.proposed});
  final BenefitProposal current;
  final BenefitProposal proposed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${_proposalSummary(current)} → ${_proposalSummary(proposed)}'),
        _ProposalEvidence(proposed),
      ],
    ),
  );
}

String _proposalSummary(BenefitProposal proposal) {
  final terms = <String>[
    if (proposal.value != null) 'value ${proposal.value}',
    if (proposal.rate != null) 'rate ${proposal.rate}',
    if (proposal.cap != null) 'cap ${proposal.cap}',
    if (proposal.threshold != null) 'threshold ${proposal.threshold}',
    if (proposal.frequency != null) 'frequency ${proposal.frequency}',
    if (proposal.period != null) 'period ${proposal.period}',
  ];
  return [proposal.label, ...terms].join(' · ');
}

class _ProposalEvidence extends StatelessWidget {
  const _ProposalEvidence(this.proposal);
  final BenefitProposal proposal;

  @override
  Widget build(BuildContext context) {
    final details = [
      proposal.description,
      proposal.category,
      if (proposal.value != null) 'value ${proposal.value}',
      if (proposal.rate != null) 'rate ${proposal.rate}',
      if (proposal.cap != null) 'cap ${proposal.cap}',
      if (proposal.threshold != null) 'threshold ${proposal.threshold}',
      proposal.frequency,
      proposal.period,
    ].whereType<String>().where((value) => value.isNotEmpty).join(' · ');
    final evidence = proposal.evidence.values.join(' · ');
    final confidence = proposal.confidence.entries
        .map((entry) => '${entry.key} ${(entry.value * 100).round()}%')
        .join(' · ');
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(proposal.label),
          if (proposal.liveBenefitId != null)
            SelectableText('Live benefit ID: ${proposal.liveBenefitId}'),
          if (proposal.benefitId != null)
            SelectableText('Benefit ID: ${proposal.benefitId}'),
          if (proposal.dedupeKey != null)
            SelectableText('Benefit key: ${proposal.dedupeKey}'),
          if (proposal.conditionHash != null)
            SelectableText('Condition hash: ${proposal.conditionHash}'),
          if (proposal.sourceIdentity != null)
            SelectableText('Source identity: ${proposal.sourceIdentity}'),
          if (details.isNotEmpty) Text(details),
          if (evidence.isNotEmpty) Text('Evidence: $evidence'),
          if (confidence.isNotEmpty) Text('Confidence: $confidence'),
          if (proposal.warnings.isNotEmpty)
            Text(
              'Warnings: ${proposal.warnings.map(_warningLabel).join(' · ')}',
            ),
        ],
      ),
    );
  }
}

class _RemovalEvidence extends StatelessWidget {
  const _RemovalEvidence({required this.removal, this.onRetire});

  final BenefitPossibleRemoval removal;
  final ValueChanged<BenefitPossibleRemoval>? onRetire;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ProposalEvidence(removal.benefit),
        Text(
          'Retirement eligible: ${removal.retirementEligible ? 'Yes' : 'No'}',
        ),
        if (removal.readableRetirementReason != null)
          Text(removal.readableRetirementReason!),
        if (removal.completeAbsenceObservedAt.isNotEmpty)
          Text(
            'Complete absence observed: ${removal.completeAbsenceObservedAt.join(' · ')}',
          ),
        if (onRetire != null)
          TextButton(
            onPressed: () => onRetire!(removal),
            child: const Text('Retire benefit'),
          ),
      ],
    ),
  );
}

String _warningLabel(String warning) {
  const labels = {
    'crawler_discovered':
        'Crawler discovery: verify against a statement or another official source.',
    'crawler_discovered_without_statement_signal':
        'Crawler-only discovery: no independent statement signal.',
    'missing_evidence': 'Missing supporting evidence.',
    'low_confidence': 'Low extraction confidence.',
    'possible_duplicate': 'Possible duplicate benefit.',
  };
  final known = labels[warning];
  if (known != null) return known;
  final words = warning.replaceAll('_', ' ').trim();
  if (words.isEmpty) return warning;
  return '${words[0].toUpperCase()}${words.substring(1)}.';
}

class _AuthorizationRequired extends StatelessWidget {
  const _AuthorizationRequired({required this.onAuthorize});
  final VoidCallback onAuthorize;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Your session needs authorization.'),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: onAuthorize,
            child: const Text('Sign in again'),
          ),
        ],
      ),
    ),
  );
}

class _MessageState extends StatelessWidget {
  const _MessageState({required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    ),
  );
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
  T? firstWhereOrNull(bool Function(T value) test) {
    for (final value in this) {
      if (test(value)) return value;
    }
    return null;
  }
}
