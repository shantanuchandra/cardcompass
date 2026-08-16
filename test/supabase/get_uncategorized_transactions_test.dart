// test/supabase/get_uncategorized_transactions_test.dart
//
// Integration test against a LIVE local Supabase instance. Run
// `supabase start` (or `supabase db reset` to apply migrations fresh)
// before running this file. Exists specifically to verify the
// getUncategorizedTransactions() PostgREST filter string actually
// behaves as intended — this combination of is.null/eq/not.in inside one
// .or() clause has no precedent elsewhere in this codebase to pattern-
// match against with confidence (see
// TransactionsRepository._buildUncategorizedOrExpression).
//
// The test email is randomized per run (unlike some sibling files in
// this directory — see README.md's "Known gap" section) specifically to
// avoid the documented "email already registered" setUpAll failure when
// re-running against a persistent local instance.
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cardcompass/core/repositories/transactions_repository.dart';

import 'local_supabase_test_support.dart';

void main() {
  group('local Supabase integration', () {
    late SupabaseClient client;
    late TransactionsRepository repo;
    late String testUserId;
    late String testUserCardId;

    setUpAll(() async {
      await Supabase.initialize(
        url: localSupabaseUrl,
        publishableKey: localSupabaseAnonKey,
      );
      client = Supabase.instance.client;
      repo = TransactionsRepository(client);

      final runId = DateTime.now().microsecondsSinceEpoch;
      final auth = await client.auth.signUp(
        email: 'uncategorized-filter-test-$runId@example.com',
        password: 'test-password-1234',
      );
      testUserId = auth.user!.id;

      final catalog = await client
          .from('card_catalog')
          .select('id')
          .limit(1)
          .single();
      final card = await client
          .from('user_cards')
          .insert({'user_id': testUserId, 'catalog_card_id': catalog['id']})
          .select('id')
          .single();
      testUserCardId = card['id'] as String;

      final now = DateTime.now().toIso8601String();
      await client.from('transactions').insert([
        {
          'user_id': testUserId,
          'user_card_id': testUserCardId,
          'amount': 1,
          'description': 'null category case',
          'transaction_date': now,
          'category': null,
        },
        {
          'user_id': testUserId,
          'user_card_id': testUserCardId,
          'amount': 1,
          'description': 'other category case',
          'transaction_date': now,
          'category': 'other',
        },
        {
          'user_id': testUserId,
          'user_card_id': testUserCardId,
          'amount': 1,
          'description': 'legacy invalid category case',
          'transaction_date': now,
          'category': 'dining',
        },
        {
          'user_id': testUserId,
          'user_card_id': testUserCardId,
          'amount': 1,
          'description': 'already-correct category, must NOT be selected',
          'transaction_date': now,
          'category': 'food',
        },
      ]);
    });

    test('selects NULL, other, and legacy-invalid categories, but not an '
        'already-correct one', () async {
      final result = await repo.getUncategorizedTransactions(testUserId);
      final descriptions = result.map((t) => t.description).toSet();

      expect(descriptions, contains('null category case'));
      expect(descriptions, contains('other category case'));
      expect(descriptions, contains('legacy invalid category case'));
      expect(
        descriptions,
        isNot(contains('already-correct category, must NOT be selected')),
      );
    });
  }, skip: localSupabaseSkipReason);
}
