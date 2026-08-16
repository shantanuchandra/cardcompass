import 'package:cardcompass/core/services/statement_processing_service.dart';
import 'package:cardcompass/shared/models/user_card.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizes formatted Gemini amounts without aborting persistence', () {
    expect(parsedGeminiNumber(476612), 476612);
    expect(parsedGeminiNumber('₹4,76,612.50'), 476612.50);
    expect(parsedGeminiNumber(''), isNull);
    expect(parsedGeminiNumber('not available'), isNull);
  });

  test('falls back when Gemini emits a non-ISO transaction date', () {
    final fallback = DateTime(2026, 7, 26);

    expect(parsedGeminiDate('2026-07-14', fallback), DateTime(2026, 7, 14));
    expect(parsedGeminiDate('14/07/2026', fallback), DateTime(2026, 7, 14));
    expect(parsedGeminiDate('not available', fallback), fallback);
    expect(parsedGeminiDate(null, fallback), fallback);
  });

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

  test('keeps pending same-bank email available for catalog resolution', () {
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
      hasLength(1),
    );
  });

  test('retries pending emails when no same-bank wallet card exists', () {
    final email = {
      'email_id': 'swiggy-email',
      'bank_detected': 'HDFC Bank',
      'subject': 'Your HDFC Bank - Swiggy Credit Card Statement',
      'metadata': {
        'attachmentFilename': 'statement.pdf',
        'needsCardAssignment': true,
      },
    };
    final unrelatedCards = [
      UserCard(
        id: 'hsbc',
        userId: 'user',
        catalogCardId: 'travelone-catalog',
        bank: 'HSBC',
        cardName: 'TravelOne',
        createdAt: DateTime(2026),
      ),
    ];

    expect(
      statementEmailsReadyForProcessing([email], userCards: unrelatedCards),
      hasLength(1),
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

  test('uniquely matches named statements to same-bank catalog cards', () {
    const cases = <({String subject, String filename, String cardName})>[
      (
        subject: 'ICICI Bank Credit Card Statement',
        filename: '4786XXXXXXXX3001_Retail_AdaniOne_NORM.pdf',
        cardName: 'Adani One',
      ),
      (
        subject: 'ICICI Bank Credit Card Statement',
        filename: '3769XXXXXXXX3003_Retail_Sapphiro_NORM.pdf',
        cardName: 'Sapphiro',
      ),
      (
        subject: 'Amazon Pay ICICI Bank Credit Card Statement',
        filename: '4315XXXXXXXX6006_Retail_Amazon_NORM.pdf',
        cardName: 'Amazon Pay',
      ),
      (
        subject: 'Your HDFC Bank - Tata Neu Infinity Credit Card Statement',
        filename: 'statement.pdf',
        cardName: 'Tata Neu Infinity',
      ),
      (
        subject: 'Your HDFC Bank - Swiggy Credit Card Statement',
        filename: 'statement.pdf',
        cardName: 'Swiggy',
      ),
      (
        subject: 'Your HDFC Bank - Diners Black Credit Card Statement',
        filename: 'statement.pdf',
        cardName: 'Diners Club Black',
      ),
      (
        subject: 'Your Zenith Credit Card Statement is here',
        filename: 'account_Zenith_998_Aug-26.pdf',
        cardName: 'Zenith',
      ),
      (
        subject: 'Statement for White Reserve Credit Card',
        filename: 'statement.pdf',
        cardName: 'White Reserve',
      ),
      (
        subject: 'Your FIRST Power Plus Credit Card Statement',
        filename: 'statement.pdf',
        cardName: 'Power Plus',
      ),
    ];

    for (final item in cases) {
      final match = catalogCardMatchedFromEmailEvidence(
        {
          'subject': item.subject,
          'metadata': {'attachmentFilename': item.filename},
        },
        [
          {'id': 'wanted', 'card_name': item.cardName},
          {'id': 'other', 'card_name': 'Unrelated Platinum'},
        ],
      );
      expect(match?['id'], 'wanted', reason: item.cardName);
    }
  });

  test('does not infer a card from ambiguous or generic catalog evidence', () {
    expect(
      catalogCardMatchedFromEmailEvidence(
        {
          'subject': 'Your PNB Credit Card Statement',
          'metadata': {'attachmentFilename': '2231832797.pdf'},
        },
        [
          {'id': 'pnb', 'card_name': 'Punjab National Bank'},
        ],
      ),
      isNull,
    );
    expect(
      catalogCardMatchedFromEmailEvidence(
        {
          'subject': 'Your Diners Black Credit Card Statement',
          'metadata': {'attachmentFilename': 'statement.pdf'},
        },
        [
          {'id': 'black', 'card_name': 'Diners Club Black'},
          {'id': 'duplicate', 'card_name': 'Diners Black'},
        ],
      ),
      isNull,
    );
  });

  test(
    'catalog evidence prefers White Reserve over the shorter White card',
    () {
      final match = catalogCardMatchedFromEmailEvidence(
        const {
          'bank_detected': 'Kotak Bank',
          'subject': 'Jul-2026 Statement for White Reserve Credit Card X0771',
          'metadata': {'attachmentFilename': '94XXXXXXXXXXX245.pdf'},
        },
        const [
          {'id': 'white', 'bank': 'Kotak Bank', 'card_name': 'White'},
          {
            'id': 'white-reserve',
            'bank': 'Kotak Bank',
            'card_name': 'White Reserve',
          },
        ],
      );

      expect(match?['id'], 'white-reserve');
    },
  );

  test(
    'catalog evidence uses aliases without treating Amex as the product',
    () {
      final match = catalogCardMatchedFromEmailEvidence(
        const {
          'bank_detected': 'Axis Bank',
          'subject': 'Your Axis Bank Amex Privilege Credit Card Statement',
          'metadata': {'attachmentFilename': 'Credit Card Statement.pdf'},
        },
        const [
          {
            'id': 'privilege',
            'bank': 'Axis Bank',
            'card_name': 'Privilege',
            'card_catalog_aliases': [
              {'alias': 'Amex Privilege'},
            ],
          },
        ],
      );

      expect(match?['id'], 'privilege');
    },
  );

  test(
    'creates a wallet card only for one uniquely named catalog entry',
    () async {
      String? createdCatalogId;
      final resolved = await resolveCatalogCardForEmail(
        email: const {
          'subject': 'Your HDFC Bank - Swiggy Credit Card Statement',
          'metadata': {'attachmentFilename': 'statement.pdf'},
        },
        bankName: 'HDFC Bank',
        existingCards: const [],
        loadCatalog: (_) async => const [
          {'id': 'swiggy-catalog', 'card_name': 'Swiggy'},
          {'id': 'regalia-catalog', 'card_name': 'Regalia Gold'},
        ],
        createCard: (catalogId) async {
          createdCatalogId = catalogId;
          return UserCard(
            id: 'created-card',
            userId: 'user',
            catalogCardId: catalogId,
            bank: 'HDFC Bank',
            cardName: 'Swiggy',
            createdAt: DateTime(2026),
          );
        },
      );

      expect(createdCatalogId, 'swiggy-catalog');
      expect(resolved?.id, 'created-card');
    },
  );

  test(
    'reuses an existing wallet card for the matched catalog entry',
    () async {
      final existing = UserCard(
        id: 'amazon-card',
        userId: 'user',
        catalogCardId: 'amazon-catalog',
        bank: 'ICICI Bank',
        cardName: 'Amazon Pay',
        createdAt: DateTime(2026),
      );
      var createCalls = 0;

      final resolved = await resolveCatalogCardForEmail(
        email: const {
          'subject': 'Amazon Pay ICICI Bank Credit Card Statement',
          'metadata': {'attachmentFilename': 'Retail_Amazon_NORM.pdf'},
        },
        bankName: 'ICICI Bank',
        existingCards: [existing],
        loadCatalog: (_) async => const [
          {'id': 'amazon-catalog', 'card_name': 'Amazon Pay'},
          {'id': 'sapphiro-catalog', 'card_name': 'Sapphiro'},
        ],
        createCard: (_) async {
          createCalls++;
          throw StateError('must reuse the wallet card');
        },
      );

      expect(resolved?.id, 'amazon-card');
      expect(createCalls, 0);
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
