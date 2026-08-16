import 'package:cardcompass/core/services/statement_processing_service.dart';
import 'package:cardcompass/shared/models/user_card.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reprocesses pending ICICI emails with a unique filename last-four', () {
    final cards = [
      UserCard(
        id: 'adani',
        userId: 'user',
        catalogCardId: 'catalog-adani',
        bank: 'ICICI Bank',
        cardName: 'Adani One',
        lastFourDigits: '3001',
        createdAt: DateTime(2026),
      ),
      UserCard(
        id: 'sapphiro',
        userId: 'user',
        catalogCardId: 'catalog-sapphiro',
        bank: 'ICICI Bank',
        cardName: 'Sapphiro',
        lastFourDigits: '3003',
        createdAt: DateTime(2026),
      ),
      UserCard(
        id: 'amazon',
        userId: 'user',
        catalogCardId: 'catalog-amazon',
        bank: 'ICICI Bank',
        cardName: 'Amazon Pay',
        lastFourDigits: '6006',
        createdAt: DateTime(2026),
      ),
    ];
    final emails = statementEmailsReadyForProcessing([
      for (final filename in const [
        '4786XXXXXXXX3001_674596_Retail_AdaniOne_NORM.pdf',
        '3769XXXXXXXX3003_266451_Retail_Sapphiro_NORM.pdf',
        '4315XXXXXXXX6006_241469_Retail_Amazon_NORM.pdf',
      ])
        {
          'email_id': filename,
          'bank_detected': 'ICICI Bank',
          'metadata': {
            'attachmentFilename': filename,
            'needsCardAssignment': true,
          },
        },
    ], userCards: cards);

    expect(emails, hasLength(3));
    expect(
      emails.map((email) => cardMatchedFromEmailFilename(email, cards)?.id),
      ['adani', 'sapphiro', 'amazon'],
    );
  });

  test('keeps genuinely ambiguous pending email out of automatic retries', () {
    final cards = [
      UserCard(
        id: 'one',
        userId: 'user',
        catalogCardId: 'catalog-one',
        bank: 'ICICI Bank',
        lastFourDigits: '3001',
        createdAt: DateTime(2026),
      ),
      UserCard(
        id: 'duplicate',
        userId: 'user',
        catalogCardId: 'catalog-duplicate',
        bank: 'ICICI Bank',
        lastFourDigits: '3001',
        createdAt: DateTime(2026),
      ),
    ];
    final email = {
      'email_id': 'ambiguous',
      'bank_detected': 'ICICI Bank',
      'metadata': {
        'attachmentFilename': '4786XXXXXXXX3001_statement.pdf',
        'needsCardAssignment': true,
      },
    };

    expect(cardMatchedFromEmailFilename(email, cards), isNull);
    expect(
      statementEmailsReadyForProcessing([email], userCards: cards),
      isEmpty,
    );
  });

  test(
    'reprocesses pending HDFC emails with a unique card name in subject',
    () {
      final cards = [
        UserCard(
          id: 'tata-neu',
          userId: 'user',
          catalogCardId: 'catalog-tata-neu',
          bank: 'HDFC Bank',
          cardName: 'Tata Neu Infinity',
          createdAt: DateTime(2026),
        ),
        UserCard(
          id: 'swiggy',
          userId: 'user',
          catalogCardId: 'catalog-swiggy',
          bank: 'HDFC Bank',
          cardName: 'Swiggy',
          createdAt: DateTime(2026),
        ),
        UserCard(
          id: 'diners-black',
          userId: 'user',
          catalogCardId: 'catalog-diners-black',
          bank: 'HDFC Bank',
          cardName: 'Diners Club Black',
          createdAt: DateTime(2026),
        ),
      ];
      final cases = <String, String>{
        'Your HDFC Bank - Tata Neu Infinity HDFC Bank Credit Card Statement':
            'tata-neu',
        'Your HDFC Bank - Swiggy HDFC Bank Credit Card Statement': 'swiggy',
        'Your HDFC Bank - Diners Black Credit Card Statement': 'diners-black',
      };

      for (final entry in cases.entries) {
        final email = {
          'email_id': entry.value,
          'bank_detected': 'HDFC Bank',
          'subject': entry.key,
          'metadata': {
            'attachmentFilename': 'statement.pdf',
            'needsCardAssignment': true,
          },
        };

        expect(
          cardMatchedFromEmailFilename(email, cards)?.id,
          entry.value,
          reason: entry.key,
        );
        expect(
          statementEmailsReadyForProcessing([email], userCards: cards),
          hasLength(1),
        );
      }
    },
  );

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
