import 'package:cardcompass/features/debug/widgets/benefit_refresh_pipeline.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'pipeline highlights pending review and preserves rejected branch',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: BenefitRefreshPipeline(stage: BenefitRefreshStage.pendingReview),
      ),
    ));

    expect(
      find.text('Show current active data versus candidate data'),
      findsOneWidget,
    );
    expect(
      find.text('Save rejected staging record; do not modify active benefits'),
      findsOneWidget,
    );
    expect(find.text('Your review'), findsOneWidget);
  });
}
