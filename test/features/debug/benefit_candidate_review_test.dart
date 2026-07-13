import 'package:cardcompass/features/debug/models/benefit_review_candidate.dart';
import 'package:cardcompass/features/debug/widgets/benefit_candidate_review.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('accept selected leaves unselected candidate unresolved',
      (tester) async {
    var state = BenefitReviewState.fromExtractedData({
      'cashback_benefits': [
        {'category': 'FUEL', 'description': 'Fuel waiver'},
        {'category': 'DINING', 'description': 'Dining reward'},
      ],
    }).setSelected(0, true);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BenefitCandidateReview(
          state: state,
          onChanged: (next) => state = next,
        ),
      ),
    ));

    await tester.tap(find.text('Accept selected'));

    expect(state.items[0].decision, BenefitDecision.accepted);
    expect(state.items[1].decision, BenefitDecision.unresolved);
  });
}
