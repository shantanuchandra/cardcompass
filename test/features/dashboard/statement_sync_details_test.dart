import 'package:cardcompass/core/services/statement_processing_service.dart';
import 'package:cardcompass/features/dashboard/providers/gmail_sync_provider.dart';
import 'package:cardcompass/features/dashboard/screens/dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sync summary reports repaired metadata and points to details', () {
    const result = GmailSyncResult(
      foundCount: 10,
      newlyStoredCount: 0,
      repairedCount: 8,
      skippedCount: 2,
      failedCount: 0,
      processedAttempted: 28,
      processedSucceeded: 8,
      processedNeedsCardAssignment: 1,
      processedFailed: 19,
      issues: [
        StatementProcessingIssue(
          bankName: 'HDFC Bank',
          cardContext: '3 possible cards',
          reason: StatementIssueReason.attachmentUnavailable,
        ),
      ],
    );

    expect(
      result.summaryMessage,
      'Found 10 statement emails: 0 new, 8 repaired. Processed 28: 8 succeeded, 1 needs a card assigned, 19 failed. View bank/card details.',
    );
  });

  testWidgets('statement sync details show grouped bank and card context', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StatementSyncDetails(
            issueLines: [
              'HDFC Bank · Diners Club Black / Swiggy / Tata Neu Infinity · 14 emails · Attachment unavailable before card matching',
              'ICICI Bank · Adani One / Amazon Pay / Sapphiro · 13 emails · Attachment unavailable before card matching',
              'ICICI Bank · Adani One / Amazon Pay / Sapphiro · 1 email · Choose the correct card',
            ],
          ),
        ),
      ),
    );

    expect(find.text('Statement issues'), findsOneWidget);
    expect(
      find.textContaining(
        'HDFC Bank · Diners Club Black / Swiggy / Tata Neu Infinity',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('ICICI Bank · Adani One / Amazon Pay / Sapphiro'),
      findsNWidgets(2),
    );
  });
}
