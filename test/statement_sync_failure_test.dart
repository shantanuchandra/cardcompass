import 'package:flutter_test/flutter_test.dart';
import 'package:cardcompass/shared/models/statement_sync_failure.dart';

void main() {
  group('buildSyncFailureMessage', () {
    test('returns null when there are no failures', () {
      expect(buildSyncFailureMessage(const []), isNull);
    });

    test('reports a single failure by bank and month/year', () {
      final message = buildSyncFailureMessage([
        StatementSyncFailure(
          bankName: 'ICICI',
          statementDate: DateTime(2026, 3, 15),
          reason: 'Card association failed',
        ),
      ]);

      expect(
        message,
        '1 statement could not be saved: ICICI (Mar 2026). Try syncing again.',
      );
    });

    test('lists up to 3 failures by name', () {
      final message = buildSyncFailureMessage([
        StatementSyncFailure(
          bankName: 'ICICI',
          statementDate: DateTime(2026, 3, 15),
          reason: 'Card association failed',
        ),
        StatementSyncFailure(
          bankName: 'HDFC',
          statementDate: DateTime(2026, 4, 2),
          reason: 'PDF parsing failed',
        ),
      ]);

      expect(
        message,
        '2 statements could not be saved: ICICI (Mar 2026), HDFC (Apr 2026). Try syncing again.',
      );
    });

    test('truncates to first 3 failures and counts the rest', () {
      final message = buildSyncFailureMessage([
        StatementSyncFailure(
          bankName: 'ICICI',
          statementDate: DateTime(2026, 3, 15),
          reason: 'Card association failed',
        ),
        StatementSyncFailure(
          bankName: 'HDFC',
          statementDate: DateTime(2026, 4, 2),
          reason: 'PDF parsing failed',
        ),
        StatementSyncFailure(
          bankName: 'Axis',
          statementDate: DateTime(2026, 5, 1),
          reason: 'DB write failed',
        ),
        StatementSyncFailure(
          bankName: 'SBI',
          statementDate: DateTime(2026, 6, 10),
          reason: 'Gemini parsing failed',
        ),
      ]);

      expect(
        message,
        '4 statements could not be saved: ICICI (Mar 2026), HDFC (Apr 2026), '
        'Axis (May 2026), and 1 more. Try syncing again.',
      );
    });
  });
}
