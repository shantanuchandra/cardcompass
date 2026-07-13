import 'package:cardcompass/features/debug/models/benefit_review_candidate.dart';
import 'package:flutter/material.dart';

class BenefitCandidateReview extends StatelessWidget {
  const BenefitCandidateReview({
    super.key,
    required this.state,
    required this.onChanged,
  });

  final BenefitReviewState state;
  final ValueChanged<BenefitReviewState> onChanged;

  @override
  Widget build(BuildContext context) {
    final selectedUnresolved = state.items
        .where((item) =>
            item.selected && item.decision == BenefitDecision.unresolved)
        .length;
    return Semantics(
      label: 'Candidate benefit decisions',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('CANDIDATE BENEFITS (${state.items.length})',
              style: const TextStyle(
                  color: Color(0xFF00F5FF), fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: state.items.length,
              itemBuilder: (context, index) => _buildItem(context, index),
            ),
          ),
          const Divider(color: Color(0xFF334155)),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              OutlinedButton(
                onPressed: selectedUnresolved == 0
                    ? null
                    : () => onChanged(state.rejectSelected()),
                child: const Text('Reject selected'),
              ),
              FilledButton(
                onPressed: selectedUnresolved == 0
                    ? null
                    : () => onChanged(state.acceptSelected()),
                child: const Text('Accept selected'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildItem(BuildContext context, int index) {
    final item = state.items[index];
    final resolved = item.decision != BenefitDecision.unresolved;
    final color = switch (item.decision) {
      BenefitDecision.unresolved => const Color(0xFF334155),
      BenefitDecision.accepted => const Color(0xFF2DD4BF),
      BenefitDecision.rejected => const Color(0xFFFB7185),
    };
    return Card(
      color: const Color(0xFF0B1729),
      shape: RoundedRectangleBorder(
          side: BorderSide(color: color),
          borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Checkbox(
              value: item.selected,
              onChanged: resolved
                  ? null
                  : (value) =>
                      onChanged(state.setSelected(index, value ?? false)),
            ),
            Expanded(
                child: Text(item.kind,
                    style: const TextStyle(
                        color: Color(0xFF00F5FF),
                        fontWeight: FontWeight.bold))),
            Text(item.decision.name.toUpperCase(),
                style: TextStyle(color: color, fontSize: 10)),
          ]),
          Text(item.description,
              style: const TextStyle(color: Color(0xFFE2E8F0))),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            OutlinedButton(
              onPressed: resolved
                  ? null
                  : () => onChanged(
                      state.setDecision(index, BenefitDecision.rejected)),
              child: const Text('Reject'),
            ),
            FilledButton(
              onPressed: resolved
                  ? null
                  : () => onChanged(
                      state.setDecision(index, BenefitDecision.accepted)),
              child: const Text('Accept'),
            ),
          ]),
        ]),
      ),
    );
  }
}
