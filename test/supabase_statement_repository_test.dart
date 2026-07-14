import 'package:flutter_test/flutter_test.dart';
import 'package:cardcompass/core/repositories/supabase_statement_repository.dart';

void main() {
  group('SupabaseStatementRepository.statementUpsertConflictColumns', () {
    test('matches the real DB unique constraint (user_card_id, statement_date)', () {
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
}
