import 'package:cardcompass/features/admin2/feedback/feedback_detail.dart';
import 'package:cardcompass/features/admin2/feedback/feedback_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final detail = AdminFeedbackDetail(
    id: '20000000-0000-4000-8000-000000000001',
    feature: 'card_data',
    feedbackText: 'The benefit amount is wrong.',
    capturedOutput: const {'amount': 100},
    safeContext: const {'card': 'Gold'},
    triageStatus: 'triaged',
    reviewStatus: 'pending',
    advisoryDiagnosis: 'Likely extraction mismatch',
    advisorySeverity: 'high',
    advisoryExpectedOutput: const {'amount': 200},
    model: 'gemini',
    promptVersion: 'triage-v1',
    createdAt: DateTime.utc(2026, 8, 19),
  );

  testWidgets('detail distinguishes user advisory and operator ground truth', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FeedbackDetailView(
          detail: detail,
          onAction: (_) async => AdminFeedbackReceipt(
            status: 'draft',
            caseId: 'case',
            updatedAt: DateTime.utc(2026),
            datasetVersion: null,
          ),
        ),
      ),
    );
    expect(find.text('User feedback'), findsOneWidget);
    expect(find.text('LLM proposal · advisory'), findsOneWidget);
    expect(find.text('Operator ground truth'), findsOneWidget);
    expect(find.textContaining('Likely extraction mismatch'), findsOneWidget);
  });

  testWidgets(
    'draft requires human fields and approval uses second typed confirmation',
    (tester) async {
      final actions = <AdminFeedbackAction>[];
      await tester.pumpWidget(
        MaterialApp(
          home: FeedbackDetailView(
            detail: detail,
            onAction: (a) async {
              actions.add(a);
              return AdminFeedbackReceipt(
                status: 'draft',
                caseId: 'case',
                updatedAt: DateTime.utc(2026),
                datasetVersion: null,
              );
            },
          ),
        ),
      );
      await tester.ensureVisible(find.text('Create eval draft'));
      await tester.tap(find.text('Create eval draft'));
      await tester.pump();
      expect(
        find.text('Complete all operator ground-truth fields.'),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const Key('operator-behavior')),
        'Use the issuer benefit amount',
      );
      await tester.enterText(
        find.byKey(const Key('operator-output')),
        '{"amount":200}',
      );
      await tester.enterText(
        find.byKey(const Key('operator-rubric')),
        '{"exact":true}',
      );
      await tester.enterText(
        find.byKey(const Key('operator-severe')),
        '{"wrong_amount":true}',
      );
      await tester.ensureVisible(find.text('Create eval draft'));
      await tester.tap(find.text('Create eval draft'));
      await tester.pumpAndSettle();
      expect(actions.single.kind, AdminFeedbackActionKind.createDraft);
      expect(find.text('Approve eval case'), findsOneWidget);
      await tester.ensureVisible(find.text('Approve eval case'));
      await tester.tap(find.text('Approve eval case'));
      await tester.pumpAndSettle();
      expect(
        find.text('Type APPROVE to add this case to the dataset.'),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const Key('approval-confirmation')),
        'APPROVE',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
      await tester.pumpAndSettle();
      expect(actions.last.kind, AdminFeedbackActionKind.approve);
    },
  );
}
