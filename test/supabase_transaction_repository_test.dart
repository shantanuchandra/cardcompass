import 'package:flutter_test/flutter_test.dart';
import 'package:cardcompass/core/repositories/supabase_transaction_repository.dart';

void main() {
  group('SupabaseTransactionRepository.transactionUpsertConflictColumns', () {
    test('matches the real DB unique index idx_transactions_dedup', () {
      // supabase/migrations/20260714040000_add_transaction_dedup_constraint.sql
      // creates a unique index on exactly these columns, in this order. If
      // this string ever drifts from that index, addTransaction's upsert
      // will throw instead of silently skipping a genuine duplicate.
      expect(
        SupabaseTransactionRepository.transactionUpsertConflictColumns,
        'user_id,user_card_id,transaction_date,description,amount',
      );
    });
  });
}
