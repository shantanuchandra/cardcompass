import 'package:flutter/material.dart';

enum BenefitRefreshStage {
  selectedCard,
  loadedOfficialUrl,
  scrapedSource,
  validatedIdentity,
  extracted,
  groundedAccepted,
  groundedRejected,
  pendingReview,
  revalidating,
  approved,
  approvalRejected,
  discarded,
}

class BenefitRefreshPipeline extends StatelessWidget {
  const BenefitRefreshPipeline({super.key, required this.stage});

  final BenefitRefreshStage stage;

  @override
  Widget build(BuildContext context) {
    final pendingReview = stage == BenefitRefreshStage.pendingReview;
    final steps = <_PipelineStep>[
      const _PipelineStep(
          'Select only the requested card', _StepState.complete),
      const _PipelineStep(
          'Load official URL from card_catalog', _StepState.complete),
      const _PipelineStep('Scrape the bank product page', _StepState.complete),
      const _PipelineStep(
          'Validate page identity: bank and card', _StepState.complete),
      const _PipelineStep(
        'Gemini extracts fees, rewards, cashback and special benefits',
        _StepState.complete,
      ),
      const _PipelineStep(
        'Ground every extracted claim against scraped evidence',
        _StepState.complete,
      ),
      _PipelineStep(
        'Show current active data versus candidate data',
        pendingReview ? _StepState.active : _StepState.complete,
      ),
      _PipelineStep(
        'Your review',
        pendingReview ? _StepState.active : _StepState.future,
      ),
      const _PipelineStep(
        'Revalidate using stored source evidence',
        _StepState.future,
      ),
      const _PipelineStep(
        'Replace selected card benefits only',
        _StepState.future,
      ),
      const _PipelineStep('Mark staging record approved', _StepState.future),
    ];

    return Semantics(
      label: 'Benefit refresh pipeline',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF071225),
          border: Border.all(color: const Color(0xFF334155)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: ListView(
            children: [
              Text('PIPELINE TRACE',
                  style: _labelStyle(const Color(0xFF00F5FF))),
              const SizedBox(height: 12),
              for (final step in steps) _buildStep(step),
              const SizedBox(height: 8),
              const _BranchStep(
                label: 'Invalid',
                detail: 'Stop; record failure',
                color: Color(0xFFFB7185),
              ),
              const _BranchStep(
                label: 'Rejected',
                detail:
                    'Save rejected staging record; do not modify active benefits',
                color: Color(0xFFFB7185),
              ),
              const _BranchStep(
                label: 'Accepted',
                detail: 'Save pending record in card_benefits_staging',
                color: Color(0xFF2DD4BF),
              ),
              const _BranchStep(
                label: 'Discard',
                detail: 'Candidate rejected; active data unchanged',
                color: Color(0xFFFB7185),
              ),
              const _BranchStep(
                label: 'Fail',
                detail: 'Mark staging record rejected; active data unchanged',
                color: Color(0xFFFB7185),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep(_PipelineStep step) {
    final color = switch (step.state) {
      _StepState.complete => const Color(0xFF2DD4BF),
      _StepState.active => const Color(0xFF00F5FF),
      _StepState.future => const Color(0xFF64748B),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 12,
            height: 12,
            margin: const EdgeInsets.only(top: 3),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
              child: Text(step.label,
                  style: TextStyle(color: color, fontSize: 12))),
        ],
      ),
    );
  }

  TextStyle _labelStyle(Color color) => TextStyle(
        color: color,
        fontWeight: FontWeight.bold,
        fontSize: 11,
        letterSpacing: 1,
      );
}

enum _StepState { complete, active, future }

class _PipelineStep {
  const _PipelineStep(this.label, this.state);
  final String label;
  final _StepState state;
}

class _BranchStep extends StatelessWidget {
  const _BranchStep(
      {required this.label, required this.detail, required this.color});
  final String label;
  final String detail;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 22, bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.bold, fontSize: 11)),
            Text(detail,
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
          ],
        ),
      );
}
