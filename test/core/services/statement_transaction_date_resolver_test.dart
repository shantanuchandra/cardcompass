import 'package:cardcompass/core/services/statement_transaction_date_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final statementDate = DateTime(2026, 8, 15);

  test('keeps a parsed transaction date inside the statement window', () {
    final result = resolveStatementTransactionDate(
      parsedValue: '2026-08-11',
      statementDate: statementDate,
      pdfText: '',
      description: 'CRED_FASTAG BANGALORE',
    );

    expect(result.date, DateTime(2026, 8, 11));
    expect(result.source, TransactionDateSource.parser);
  });

  test(
    'recovers a split AU date from source text instead of saving a future date',
    () {
      const pdfText = '''
Statement for your credit card ending with 4311 (16 Jul - 15 Aug 2026)
Your Transactions
11 CRED_FASTAG BANGALORE IN
Aug 26 Dr
₹489.85
''';

      final result = resolveStatementTransactionDate(
        parsedValue: '2026-08-26',
        statementDate: statementDate,
        pdfText: pdfText,
        description: 'CRED_FASTAG BANGALORE',
      );

      expect(result.date, DateTime(2026, 8, 11));
      expect(result.source, TransactionDateSource.pdfContext);
    },
  );

  test(
    'rejects a future parser date when source text cannot prove a correction',
    () {
      final result = resolveStatementTransactionDate(
        parsedValue: '2026-08-26',
        statementDate: statementDate,
        pdfText: 'unrelated statement text',
        description: 'CRED_FASTAG BANGALORE',
      );

      expect(result.date, isNull);
      expect(result.source, TransactionDateSource.rejectedFuture);
    },
  );

  test(
    'uses the statement date only when the parser did not provide a date',
    () {
      final result = resolveStatementTransactionDate(
        parsedValue: null,
        statementDate: statementDate,
        pdfText: '',
        description: 'Unknown transaction',
      );

      expect(result.date, statementDate);
      expect(result.source, TransactionDateSource.statementFallback);
    },
  );
}
