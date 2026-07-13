import 'package:cardcompass/features/debug/models/benefit_review_candidate.dart';
import 'package:flutter/material.dart';

class BenefitCandidateReview extends StatelessWidget {
  const BenefitCandidateReview({
    super.key,
    required this.state,
    required this.onChanged,
  });

  static const _cyan = Color(0xFF00F5FF);
  static const _surface = Color(0xFF0B1729);
  static const _border = Color(0xFF334155);
  static const _accepted = Color(0xFF2DD4BF);
  static const _rejected = Color(0xFFFB7185);
  static const _text = Color(0xFFE2E8F0);

  final BenefitReviewState state;
  final ValueChanged<BenefitReviewState> onChanged;

  @override
  Widget build(BuildContext context) {
    final selectedUnresolved = state.items
        .where((item) =>
            item.selected && item.decision == BenefitDecision.unresolved)
        .length;
    final progress = state.items.isEmpty
        ? 0.0
        : (state.items.length - state.unresolvedCount) / state.items.length;

    return Semantics(
      label: 'Candidate benefit decisions',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DecisionSummary(
            state: state,
            progress: progress,
            onRejectAll: state.unresolvedCount == 0
                ? null
                : () => onChanged(state.rejectAll()),
            onAcceptAll: state.unresolvedCount == 0
                ? null
                : () => onChanged(state.acceptAll()),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 8),
              itemCount: state.items.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) => _buildItem(context, index),
            ),
          ),
          const Divider(color: _border, height: 20),
          _SelectedActionBar(
            selectedUnresolved: selectedUnresolved,
            onReject: selectedUnresolved == 0
                ? null
                : () => onChanged(state.rejectSelected()),
            onAccept: selectedUnresolved == 0
                ? null
                : () => onChanged(state.acceptSelected()),
          ),
        ],
      ),
    );
  }

  Widget _buildItem(BuildContext context, int index) {
    final item = state.items[index];
    final resolved = item.decision != BenefitDecision.unresolved;
    final status = _statusFor(item.decision);
    final actionLabel = item.kind.toLowerCase();
    final sourceCoverageGap = item.source['source_coverage_gap'] == true;
    final repairPass = item.source['repair_pass'] == true;
    final evidenceExcerpt = item.source['evidence_excerpt']?.toString();

    return Card(
      margin: EdgeInsets.zero,
      color: _surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: status.color),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  label: 'Select $actionLabel for selected actions',
                  checked: item.selected,
                  enabled: !resolved,
                  child: Checkbox(
                    value: item.selected,
                    onChanged: resolved
                        ? null
                        : (value) =>
                            onChanged(state.setSelected(index, value ?? false)),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(status.icon, size: 18, color: status.color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.kind,
                    style: const TextStyle(
                      color: _cyan,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                _StatusChip(status: status),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              item.description,
              style: const TextStyle(color: _text, height: 1.35),
            ),
            if (sourceCoverageGap || repairPass) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF172554),
                  border: Border.all(color: _cyan.withValues(alpha: 0.45)),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      repairPass
                          ? 'SECOND-PASS REPAIR — REVIEW REQUIRED'
                          : 'SOURCE COVERAGE GAP',
                      style: TextStyle(
                        color: _cyan,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (evidenceExcerpt != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'VERBATIM: $evidenceExcerpt',
                        style: const TextStyle(
                          color: Color(0xFFCBD5E1),
                          fontSize: 11,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final buttons = [
                  Expanded(
                    child: Tooltip(
                      message: 'Reject this benefit candidate',
                      child: OutlinedButton.icon(
                        onPressed: resolved
                            ? null
                            : () => onChanged(state.setDecision(
                                  index,
                                  BenefitDecision.rejected,
                                )),
                        icon: const Icon(Icons.close, size: 18),
                        label: const Text('Reject'),
                        style: _rejectButtonStyle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Tooltip(
                      message: 'Accept this benefit candidate',
                      child: FilledButton.icon(
                        onPressed: resolved
                            ? null
                            : () => onChanged(state.setDecision(
                                  index,
                                  BenefitDecision.accepted,
                                )),
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Accept'),
                        style: _acceptButtonStyle,
                      ),
                    ),
                  ),
                ];
                if (constraints.maxWidth >= 280) {
                  return Row(children: buttons);
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    buttons[0],
                    const SizedBox(height: 8),
                    buttons[2],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  static _DecisionStatus _statusFor(BenefitDecision decision) =>
      switch (decision) {
        BenefitDecision.unresolved => const _DecisionStatus(
            label: 'TO REVIEW',
            color: _border,
            icon: Icons.pending_outlined,
          ),
        BenefitDecision.accepted => const _DecisionStatus(
            label: 'ACCEPTED',
            color: _accepted,
            icon: Icons.check_circle_outline,
          ),
        BenefitDecision.rejected => const _DecisionStatus(
            label: 'REJECTED',
            color: _rejected,
            icon: Icons.cancel_outlined,
          ),
      };

  static final _rejectButtonStyle = OutlinedButton.styleFrom(
    foregroundColor: _rejected,
    side: const BorderSide(color: _rejected),
    minimumSize: const Size.fromHeight(44),
  );

  static final _acceptButtonStyle = FilledButton.styleFrom(
    backgroundColor: _cyan,
    foregroundColor: const Color(0xFF07111F),
    minimumSize: const Size.fromHeight(44),
  );
}

class _DecisionSummary extends StatelessWidget {
  const _DecisionSummary({
    required this.state,
    required this.progress,
    required this.onRejectAll,
    required this.onAcceptAll,
  });

  final BenefitReviewState state;
  final double progress;
  final VoidCallback? onRejectAll;
  final VoidCallback? onAcceptAll;

  @override
  Widget build(BuildContext context) {
    final unresolved = state.unresolvedCount;
    return Semantics(
      liveRegion: true,
      label:
          '${state.items.length} candidate benefits. $unresolved still need review.',
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF0E1D34),
          border: Border.all(color: const Color(0xFF334155)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'CANDIDATE BENEFITS',
                    style: TextStyle(
                      color: Color(0xFF00F5FF),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  '${state.items.length} TOTAL',
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '$unresolved to review · ${state.acceptedCount} accepted · ${state.rejectedCount} rejected',
              style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 12),
            ),
            const SizedBox(height: 8),
            Semantics(
              label:
                  '${(progress * 100).round()} percent of candidate benefits reviewed',
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: const Color(0xFF1E293B),
                color: const Color(0xFF2DD4BF),
              ),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final actions = [
                  Expanded(
                    child: Tooltip(
                      message: 'Mark all unresolved candidates as rejected',
                      child: OutlinedButton.icon(
                        onPressed: onRejectAll,
                        icon: const Icon(Icons.close, size: 18),
                        label: Text('Reject all ($unresolved)'),
                        style: BenefitCandidateReview._rejectButtonStyle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Tooltip(
                      message: 'Mark all unresolved candidates as accepted',
                      child: FilledButton.icon(
                        onPressed: onAcceptAll,
                        icon: const Icon(Icons.done_all, size: 18),
                        label: Text('Accept all ($unresolved)'),
                        style: BenefitCandidateReview._acceptButtonStyle,
                      ),
                    ),
                  ),
                ];
                if (constraints.maxWidth >= 330) return Row(children: actions);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    actions[0],
                    const SizedBox(height: 8),
                    actions[2],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectedActionBar extends StatelessWidget {
  const _SelectedActionBar({
    required this.selectedUnresolved,
    required this.onReject,
    required this.onAccept,
  });

  final int selectedUnresolved;
  final VoidCallback? onReject;
  final VoidCallback? onAccept;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final buttons = [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onReject,
              icon: const Icon(Icons.close, size: 18),
              label: const Text('Reject selected'),
              style: BenefitCandidateReview._rejectButtonStyle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton.icon(
              onPressed: onAccept,
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Accept selected'),
              style: BenefitCandidateReview._acceptButtonStyle,
            ),
          ),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              selectedUnresolved == 0
                  ? 'Select candidates to decide in bulk'
                  : '$selectedUnresolved selected for bulk decision',
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
            ),
            const SizedBox(height: 8),
            if (constraints.maxWidth >= 330)
              Row(children: buttons)
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  buttons[0],
                  const SizedBox(height: 8),
                  buttons[2],
                ],
              ),
          ],
        );
      },
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final _DecisionStatus status;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Decision status: ${status.label.toLowerCase()}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          border: Border.all(color: status.color),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          status.label,
          style: TextStyle(
            color: status.color,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class _DecisionStatus {
  const _DecisionStatus({
    required this.label,
    required this.color,
    required this.icon,
  });

  final String label;
  final Color color;
  final IconData icon;
}
