import 'dart:typed_data';

import 'package:cardcompass/core/services/enhanced_gmail_service.dart';
import 'package:cardcompass/core/services/gemini_transaction_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StatementParsingResult.fromParsedInfo', () {
    test('uses the PDF statement date over the email received date', () {
      final result = StatementParsingResult.fromParsedInfo(
        emailDate: DateTime(2026, 7, 15),
        statementInfo: {'statement_date': '2026-07-10T00:00:00.000Z'},
        base: _baseResult(),
      );

      expect(result.statementDate, DateTime(2026, 7, 10));
      expect(result.statementDateSource, 'pdf');
    });

    test('records an email fallback when the PDF date is unavailable', () {
      final result = StatementParsingResult.fromParsedInfo(
        emailDate: DateTime(2026, 7, 15),
        statementInfo: {'statement_date': 'not a date'},
        base: _baseResult(),
      );

      expect(result.statementDate, DateTime(2026, 7, 15));
      expect(result.statementDateSource, 'email_fallback');
    });
  });

  test('extracts payments received from a statement fixture', () {
    final parsed = GeminiTransactionParser.fallbackStatementParsingForTesting(
      'Statement Date: 10/07/2026\nPayments Received: ₹1,250.00',
      'Example Bank',
    );

    expect(parsed['payments_received'], 1250.0);
  });
}

StatementParsingResult _baseResult() => StatementParsingResult(
      bankName: 'Example Bank',
      statementDate: DateTime(2026, 7, 15),
      transactions: const [],
      originalPdfData: Uint8List(0),
      emailMessageId: 'email-1',
      processingSuccess: true,
    );
