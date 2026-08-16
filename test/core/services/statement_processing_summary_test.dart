import 'package:cardcompass/core/services/statement_processing_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('does not reprocess emails already awaiting card assignment', () {
    final emails = statementEmailsReadyForProcessing([
      {
        'email_id': 'ready',
        'metadata': {'attachmentId': 'attachment-ready'},
      },
      {
        'email_id': 'awaiting-card',
        'metadata': {
          'attachmentId': 'attachment-awaiting',
          'needsCardAssignment': true,
        },
      },
    ]);

    expect(emails.map((email) => email['email_id']), ['ready']);
  });

  test('unexpected failure replaces earlier issues from the same attempt', () {
    final issues = StatementIssueAccumulator();
    final attempt = issues.beginAttempt();
    issues.record(
      const StatementProcessingIssue(
        bankName: 'ICICI Bank',
        cardContext: 'Amazon Pay',
        reason: StatementIssueReason.passwordRequired,
      ),
    );

    issues.replaceAttemptWith(
      attempt,
      const StatementProcessingIssue(
        bankName: 'ICICI Bank',
        cardContext: 'Adani One / Amazon Pay / Sapphiro',
        reason: StatementIssueReason.processingFailed,
      ),
    );

    expect(issues.snapshot, hasLength(1));
    expect(
      issues.snapshot.single.reason,
      StatementIssueReason.processingFailed,
    );
    expect(
      issues.snapshot.single.cardContext,
      'Adani One / Amazon Pay / Sapphiro',
    );
  });

  test('groups statement failures by bank, card context, and reason', () {
    final lines = buildStatementIssueLines([
      const StatementProcessingIssue(
        bankName: 'HDFC Bank',
        cardContext: 'Diners Club Black / Swiggy / Tata Neu Infinity',
        reason: StatementIssueReason.attachmentUnavailable,
      ),
      const StatementProcessingIssue(
        bankName: 'HDFC Bank',
        cardContext: 'Diners Club Black / Swiggy / Tata Neu Infinity',
        reason: StatementIssueReason.attachmentUnavailable,
      ),
      const StatementProcessingIssue(
        bankName: 'ICICI Bank',
        cardContext: 'Adani One / Amazon Pay / Sapphiro',
        reason: StatementIssueReason.cardAssignmentRequired,
      ),
    ]);

    expect(lines, [
      'HDFC Bank · Diners Club Black / Swiggy / Tata Neu Infinity · 2 emails · Attachment unavailable before card matching',
      'ICICI Bank · Adani One / Amazon Pay / Sapphiro · 1 email · Choose the correct card',
    ]);
  });

  test('reports exhausted PDF password attempts as retryable', () {
    final lines = buildStatementIssueLines([
      const StatementProcessingIssue(
        bankName: 'HSBC',
        cardContext: 'TravelOne',
        reason: StatementIssueReason.passwordAttemptsExhausted,
      ),
    ]);

    expect(lines, [
      'HSBC · TravelOne · 1 email · Password still incorrect after 2 attempts',
    ]);
  });
}
