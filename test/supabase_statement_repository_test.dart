import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cardcompass/core/repositories/supabase_statement_repository.dart';

void main() {
  group('statement payment reconciliation migration', () {
    test('uses one ownership-checked RPC transaction with source idempotency',
        () {
      final migration = File(
        'supabase/migrations/20260716090200_reconcile_imported_statement_payments.sql',
      ).readAsStringSync();

      expect(migration, contains('reconcile_imported_statement_payment'));
      expect(migration, contains('FOR UPDATE'));
      expect(migration, contains("'{payment_reconciliation_state}'"));
      expect(migration, contains("'\"applied\"'::jsonb"));
      expect(migration, contains("unmatched_payment_credit'"));
      expect(migration, contains("ORDER BY due_date ASC"));
      expect(migration, contains('p_user_card_id'));
      expect(migration, contains('auth.uid()'));
    });
  });

  group('SupabaseStatementRepository.statementUpsertConflictColumns', () {
    test('matches the real DB unique constraint (user_card_id, statement_date)',
        () {
      // The `statements` table's unique constraint is `statements_user_card_statement_date_key`
      // on (user_card_id, statement_date) — see
      // supabase/migrations/20260714020000_enforce_user_card_ownership.sql:44-49,
      // which replaced the old (card_id, statement_date) constraint. If this
      // string ever drifts from that constraint again, every statement upsert
      // silently fails (caught and logged, not surfaced) and no `statements`
      // row gets written — exactly the bug this test guards against.
      expect(
        SupabaseStatementRepository.statementUpsertConflictColumns,
        'user_card_id,statement_date',
      );
    });
  });

  group('SupabaseStatementRepository.createStatement', () {
    test('persists ingestion metadata in the statement upsert row', () async {
      Map<String, dynamic>? persistedStatement;
      final repository = SupabaseStatementRepository(
        resolveCatalogCardId: (_) async => 'catalog-card-1',
        upsertStatement: (statement, {required onConflict}) async {
          persistedStatement = statement;
          expect(
            onConflict,
            SupabaseStatementRepository.statementUpsertConflictColumns,
          );
          return {
            ...statement,
            'id': 'statement-1',
            'file_path': 'test-statement.pdf',
          };
        },
      );

      await repository.createStatement(
        userId: 'user-1',
        userCardId: 'user-card-1',
        statementData: {
          'statement_date': '2026-07-10T00:00:00.000Z',
          'metadata': {
            'statement_date_source': 'pdf',
            'payments_received': 1250.0,
            'payment_reconciliation_status': 'unreconciled',
          },
        },
      );

      expect(persistedStatement?['metadata'], {
        'statement_date_source': 'pdf',
        'payments_received': 1250.0,
        'payment_reconciliation_status': 'unreconciled',
      });
    });

    test(
        'throws instead of silently using userCardId as card_id when the '
        'catalog_card_id lookup fails', () async {
      // A userCardId that doesn't resolve to any user_cards row (fabricated,
      // orphaned, or otherwise) must fail loudly. Previously this was caught
      // and swallowed, leaving `catalogCardId = userCardId` — a user_cards.id
      // silently written into statements.card_id, which actually references
      // card_catalog(id). That corrupts the row instead of surfacing the
      // real problem.
      final repository = SupabaseStatementRepository(
        resolveCatalogCardId: (userCardId) async {
          throw Exception('simulated: no user_cards row for $userCardId');
        },
      );

      expect(
        () => repository.createStatement(
          userId: 'user-1',
          userCardId: 'nonexistent-user-card-id',
          statementData: const {},
        ),
        throwsException,
      );
    });
  });
}
