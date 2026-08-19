import 'dart:async';

import 'package:cardcompass/features/admin2/feedback/feedback_detail.dart';
import 'package:cardcompass/features/admin2/feedback/feedback_models.dart';
import 'package:cardcompass/features/admin2/data/admin_operator_repository.dart';
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
    expect(find.byKey(const Key('operator-output')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('operator-output')))
          .controller!
          .text,
      isEmpty,
    );
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
      await tester.ensureVisible(
        find.byKey(const Key('ground-truth-confirmed')),
      );
      await tester.tap(find.byKey(const Key('ground-truth-confirmed')));
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

  testWidgets('one in-flight mutation disables every mutation control', (
    tester,
  ) async {
    final completion = Completer<AdminFeedbackReceipt>();
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: FeedbackDetailView(
          detail: detail,
          onAction: (_) {
            calls++;
            return completion.future;
          },
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('operator-behavior')),
      'Human expected behavior',
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
    await tester.ensureVisible(find.byKey(const Key('ground-truth-confirmed')));
    await tester.tap(find.byKey(const Key('ground-truth-confirmed')));
    await tester.ensureVisible(find.text('Create eval draft'));
    await tester.tap(find.text('Create eval draft'));
    await tester.pump();
    expect(calls, 1);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Create eval draft'),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Data issue'),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Product defect'),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Dismiss'))
          .onPressed,
      isNull,
    );
    completion.complete(
      AdminFeedbackReceipt(
        status: 'draft',
        caseId: 'case',
        updatedAt: DateTime.utc(2026),
        datasetVersion: null,
      ),
    );
    await tester.pumpAndSettle();
    expect(calls, 1);
  });
  testWidgets('retry identity survives a parent rebuild after response loss', (
    tester,
  ) async {
    final retryIds = <String>[];
    var attempts = 0;
    final failed = AdminFeedbackDetail(
      id: detail.id,
      feature: detail.feature,
      feedbackText: detail.feedbackText,
      capturedOutput: detail.capturedOutput,
      safeContext: detail.safeContext,
      triageStatus: 'triage_failed',
      reviewStatus: 'pending',
      advisoryDiagnosis: '',
      advisorySeverity: 'normal',
      advisoryExpectedOutput: const {},
      model: null,
      promptVersion: null,
      createdAt: detail.createdAt,
    );
    Widget build() => MaterialApp(
      home: FeedbackDetailView(
        detail: failed,
        onAction: (_) async => throw const AdminRequestFailed('request_failed'),
        onRetryTriage: (mutation) async {
          retryIds.add(mutation.requestId);
          if (++attempts == 1) throw const AdminRequestFailed('request_failed');
          return const AdminFeedbackReceipt(
            status: 'awaiting_triage',
            caseId: null,
            updatedAt: null,
            datasetVersion: null,
          );
        },
      ),
    );
    await tester.pumpWidget(build());
    await tester.ensureVisible(find.text('Retry triage'));
    await tester.tap(find.text('Retry triage'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(build());
    await tester.ensureVisible(find.text('Retry triage'));
    await tester.tap(find.text('Retry triage'));
    await tester.pumpAndSettle();
    expect(retryIds, hasLength(2));
    expect(retryIds.first, retryIds.last);
  });

  testWidgets('detail renders every eval revision and marks the current one', (
    tester,
  ) async {
    AdminEvalCase caseAt(int revision, String status) => AdminEvalCase(
      id: '20000000-0000-4000-8000-00000000000$revision',
      status: status,
      revision: revision,
      updatedAt: DateTime.utc(2026, 8, 19, revision),
      inputFixture: {'revision': revision},
      capturedOutput: {'captured': revision},
      expectedOutput: {'expected': revision},
      operatorFeedback: 'Human revision $revision',
      scoringRubric: const {'exact': true},
      severeConditions: const {'wrong': true},
      approvedDatasetVersion: revision,
      retiredDatasetVersion: status == 'retired' ? revision + 1 : null,
      approvedAt: DateTime.utc(2026, 8, 19, revision),
      retiredAt: status == 'retired' ? DateTime.utc(2026, 8, 20) : null,
    );
    final versioned = AdminFeedbackDetail(
      id: detail.id,
      feature: detail.feature,
      feedbackText: detail.feedbackText,
      capturedOutput: detail.capturedOutput,
      safeContext: detail.safeContext,
      triageStatus: detail.triageStatus,
      reviewStatus: 'eval_created',
      advisoryDiagnosis: '',
      advisorySeverity: 'normal',
      advisoryExpectedOutput: const {},
      model: null,
      promptVersion: null,
      createdAt: detail.createdAt,
      evalCases: [
        caseAt(3, 'draft'),
        caseAt(2, 'approved'),
        caseAt(1, 'retired'),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: FeedbackDetailView(
          detail: versioned,
          onAction: (_) async => const AdminFeedbackReceipt(
            status: 'ok',
            caseId: null,
            updatedAt: null,
            datasetVersion: null,
          ),
        ),
      ),
    );
    expect(
      find.text('Eval revision 3 · current actionable revision'),
      findsOneWidget,
    );
    expect(find.text('Eval revision 2'), findsOneWidget);
    expect(find.text('Eval revision 1'), findsOneWidget);
    expect(find.textContaining('Retired:'), findsWidgets);
  });
}
