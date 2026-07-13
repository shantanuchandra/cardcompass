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
}
