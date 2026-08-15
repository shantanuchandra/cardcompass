import 'package:cardcompass/core/repositories/transactions_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseMerchantCategoryRow', () {
    test('extracts category from a valid row', () {
      expect(parseMerchantCategoryRow({'category': 'grocery'}), 'grocery');
    });

    test('returns null for an empty result', () {
      expect(parseMerchantCategoryRow(null), isNull);
    });

    test('returns null when category field is missing', () {
      expect(
        parseMerchantCategoryRow({'merchant_name_normalized': 'CARREFOUR'}),
        isNull,
      );
    });
  });

  group('getUncategorizedTransactions query construction', () {
    // getUncategorizedTransactions() is a thin wrapper around a real
    // Supabase call: eq('user_id', ...).or(<assembled filter string>).
    // The one piece of logic inside it that isn't "make a network call" —
    // assembling the .or(...) filter string from validCategories — lives
    // in TransactionsRepository._buildUncategorizedOrExpression(), a
    // private static helper (matching the precedent set by
    // SupabaseMovieDealsDataSource._buildWidenedOrExpression() in
    // movie_deals_repository.dart, which is also private with no
    // dedicated unit test for the same reason).
    //
    // Dart privacy is per-library: this test file is a different library
    // from transactions_repository.dart (it imports the package, it
    // isn't a `part of`), so the private helper isn't reachable here
    // without either exposing it publicly — which would widen the API
    // surface purely for testability, for a helper no other caller
    // needs — or duplicating its string-building logic into this test,
    // which would test a copy of the logic rather than the logic itself.
    // Neither is a real test, so this group is deliberately left without
    // one.
    //
    // The actual behavioral guarantee — that the assembled filter string
    // selects NULL / 'other' / legacy-invalid categories and excludes
    // already-valid ones — is covered by the live-Supabase integration
    // test in test/supabase/get_uncategorized_transactions_test.dart,
    // which is what actually exercises this against real PostgREST.
  });
}
