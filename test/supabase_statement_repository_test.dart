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
      expect(migration, contains('AND id <> p_source_statement_id'));
      expect(migration, contains('p_user_card_id'));
      expect(migration, contains('auth.uid()'));
    });

    test('records the unmatched remainder on the source after excluding it',
        () {
      final migration = File(
        'supabase/migrations/20260716090200_reconcile_imported_statement_payments.sql',
      ).readAsStringSync();

      final sourceExclusion =
          migration.indexOf('AND id <> p_source_statement_id');
      final remainderUpdate = migration.indexOf("'{unmatched_payment_credit}'");
      expect(sourceExclusion, greaterThanOrEqualTo(0));
      expect(remainderUpdate, greaterThan(sourceExclusion));
    });

    test('marks a manually paid statement with its remaining balance and time',
        () {
      final migration = File(
        'supabase/migrations/20260716090200_reconcile_imported_statement_payments.sql',
      ).readAsStringSync();

      expect(
        migration,
        contains(
            'WHEN p_mark_paid THEN v_statement.total_amount - v_statement.paid_amount'),
      );
      expect(migration, contains('paid_at = CASE'));
      expect(migration,
          contains('WHEN paid_amount + v_payment >= total_amount THEN NOW()'));
    });

    test('database trigger keeps reconciliation-owned fields during an upsert',
        () {
      final migration = File(
        'supabase/migrations/20260716090300_protect_reconciled_statement_fields.sql',
      ).readAsStringSync();

      expect(migration, contains('CREATE OR REPLACE FUNCTION'));
      expect(migration, contains('protect_reconciled_statement_fields'));
      expect(migration, contains('BEFORE UPDATE ON public.statements'));
      expect(migration, contains("NEW.payment_status := OLD.payment_status"));
      expect(migration, contains("NEW.paid_amount := OLD.paid_amount"));
      expect(migration, contains("NEW.paid_at := OLD.paid_at"));
      expect(migration, contains("'{payment_reconciliation_state}'"));
      expect(migration, contains("'{unmatched_payment_credit}'"));
      expect(
          migration,
          contains(
              "current_setting('cardcompass.reconciliation_write', true)"));
    });

    test('payment RPCs opt into the trigger trusted-writer contract', () {
      final migration = File(
        'supabase/migrations/20260716090300_protect_reconciled_statement_fields.sql',
      ).readAsStringSync();

      expect(migration, contains('reconcile_imported_statement_payment'));
      expect(migration, contains('apply_statement_payment'));
      expect(
          migration,
          contains(
              "set_config('cardcompass.reconciliation_write', 'on', true)"));
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
