import 'package:cardcompass/features/debug/models/benefit_review_candidate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bulk acceptance changes only selected unresolved candidates', () {
    final state = BenefitReviewState.fromExtractedData({
      'cashback_benefits': [
        {'category': 'FUEL', 'description': 'Fuel waiver', 'rate': 1},
        {'category': 'DINING', 'description': 'Dining points', 'rate': 5},
      ],
    });

    final selected = state.setSelected(0, true).acceptSelected();

    expect(selected.items[0].decision, BenefitDecision.accepted);
    expect(selected.items[1].decision, BenefitDecision.unresolved);
  });

  test('staging JSON preserves rejected candidates and their decisions', () {
    final state = BenefitReviewState.fromExtractedData({
      'special_benefits': [
        {'type': 'LOUNGE', 'description': 'Domestic lounge access'},
      ],
    }).setDecision(0, BenefitDecision.rejected);

    expect(state.toStagingJson()['items'][0]['decision'], 'rejected');
  });

  test('discarding rejects every unresolved candidate', () {
    final discarded = BenefitReviewState.fromExtractedData({
      'cashback_benefits': [
        {'category': 'FUEL', 'description': 'Fuel waiver'},
      ],
      'special_benefits': [
        {'type': 'LOUNGE', 'description': 'Lounge access'},
      ],
    }).rejectAll();

    expect(
      discarded.items
          .every((item) => item.decision == BenefitDecision.rejected),
      isTrue,
    );
  });

  test('accepting all resolves every unresolved candidate', () {
    final accepted = BenefitReviewState.fromExtractedData({
      'cashback_benefits': [
        {'category': 'FUEL', 'description': 'Fuel waiver'},
        {'category': 'DINING', 'description': 'Dining reward'},
      ],
    }).acceptAll();

    expect(accepted.unresolvedCount, 0);
    expect(accepted.acceptedCount, 2);
    expect(
      accepted.items.every((item) => item.decision == BenefitDecision.accepted),
      isTrue,
    );
  });

  test('a pending staging record with candidate data can be opened for review',
      () {
    final access = StagingReviewAccess(
      stagingId: 'stage-123',
      status: 'pending',
      candidateData: const {'benefits': []},
    );

    expect(access.canOpen, isTrue);
  });

  test('rejected or incomplete staging records cannot be opened for review',
      () {
    expect(
      const StagingReviewAccess(
        stagingId: 'stage-123',
        status: 'rejected',
        candidateData: {'benefits': []},
      ).canOpen,
      isFalse,
    );
    expect(
      const StagingReviewAccess(
        stagingId: null,
        status: 'pending',
        candidateData: {'benefits': []},
      ).canOpen,
      isFalse,
    );
  });
}
