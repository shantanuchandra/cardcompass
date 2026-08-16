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
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(labelText: 'Reason (required)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final reason = controller.text.trim();
              if (reason.length >= 3) Navigator.pop(context, reason);
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _edit(BenefitEnrichmentReview item) async {
    final candidate =
        item.staging.decisions.firstOrNull?.benefit ??
        item.staging.extractedData.diff.additions.firstOrNull;
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
              BenefitReviewDecision(
                action: 'edit',
                editedBenefit: BenefitProposal(
                  dedupeKey: candidate.dedupeKey,
                  title: title.text.trim(),
                  description: description.text.trim(),
                  category: candidate.category,
                  value: candidate.value,
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
          final message = snapshot.error is AdminAccessDenied
              ? 'Administrator access is required for benefit reviews.'
              : 'Could not load benefit enrichment reviews.';
          return _MessageState(message: message, onRetry: _reload);
        }
        final page = snapshot.data!;
        return RefreshIndicator(
          onRefresh: _reload,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _ProgressSummary(counts: page.counts, history: page.history),
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
                      onApprove: !_mutating && item.canReview
                          ? () => _run(() => widget.repository.approve(item))
                          : null,
                      onEdit: !_mutating && item.canReview
                          ? () => _edit(item)
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

class _ProgressSummary extends StatelessWidget {
  const _ProgressSummary({required this.counts, required this.history});
  final BenefitEnrichmentCounts counts;
  final List<BenefitJobHistory> history;

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
            Text('Job run coverage: $scheduled scheduled · $pilot pilot'),
            Text('Last run: $completed completed · $failed failed'),
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
    this.onRetry,
    this.onQuarantine,
  });

  final BenefitEnrichmentReview item;
  final ValueChanged<Uri> onOpenUrl;
  final VoidCallback? onApprove;
  final VoidCallback? onEdit;
  final VoidCallback? onReject;
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
            if (item.staging.lacksStatementEvidence) ...[
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
            if (diff.modifications.isNotEmpty) ...[
              const Divider(),
              const Text('Current'),
              ...diff.modifications.map(
                (change) => _DiffRow(
                  current: change.current,
                  proposed: change.proposed,
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
              ...diff.possibleRemovals.map(_ProposalEvidence.new),
            ],
            if (diff.conflicts.isNotEmpty) ...[
              const Divider(),
              const Text('Conflicts'),
              ...diff.conflicts.expand(
                (conflict) => [
                  Text(conflict.code ?? 'Unspecified conflict'),
                  ...conflict.current.map(_ProposalEvidence.new),
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
                  child: Text(
                    evidence.sourceExcerpt ??
                        evidence.evidence.values.join(' · '),
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
                  child: const Text('Approve'),
                ),
                OutlinedButton(onPressed: onEdit, child: const Text('Edit')),
                TextButton(onPressed: onReject, child: const Text('Reject')),
                TextButton(onPressed: onRetry, child: const Text('Retry')),
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
        Text(
          '${current.label}${current.value == null ? '' : ' (${current.value})'} → ${proposed.label}${proposed.value == null ? '' : ' (${proposed.value})'}',
        ),
        _ProposalEvidence(proposed),
      ],
    ),
  );
}

class _ProposalEvidence extends StatelessWidget {
  const _ProposalEvidence(this.proposal);
  final BenefitProposal proposal;

  @override
  Widget build(BuildContext context) {
    final details = [
      proposal.description,
      proposal.category,
      proposal.value,
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
          if (details.isNotEmpty) Text(details),
          if (evidence.isNotEmpty) Text('Evidence: $evidence'),
          if (confidence.isNotEmpty) Text('Confidence: $confidence'),
          if (proposal.warnings.isNotEmpty)
            Text('Warnings: ${proposal.warnings.join(', ')}'),
        ],
      ),
    );
  }
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
}
