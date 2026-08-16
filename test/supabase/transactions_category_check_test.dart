// test/supabase/transactions_category_check_test.dart
//
// Integration test against a LIVE local Supabase instance. Run
// `supabase db reset` first to apply migrations fresh.
//
// Schema verified against the current transactions table (initial
// schema + 20260714020000_enforce_user_card_ownership.sql +
// 20260817000000_transaction_mcc_enrichment.sql) before writing this:
// no new NOT NULL column without a default was added by the MCC
// enrichment migration, so the insert shapes below need no additional
// fields beyond what's given. This matches the sibling
// get_uncategorized_transactions_test.dart's insert shape, which already
// exercises this same setup against the live schema.
//
// The test email is randomized per run (unlike some sibling files in
// this directory — see README.md's "Known gap" section) specifically to
// avoid the documented "email already registered" setUpAll failure when
// re-running against a persistent local instance.
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'local_supabase_test_support.dart';

void main() {
  group('local Supabase integration', () {
    late SupabaseClient client;
    late String testUserId;
    late String testUserCardId;

    setUpAll(() async {
      await Supabase.initialize(
        url: localSupabaseUrl,
        publishableKey: localSupabaseAnonKey,
      );
      client = Supabase.instance.client;
      final auth = await client.auth.signUp(
        email:
            'category-check-test-${DateTime.now().microsecondsSinceEpoch}@example.com',
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
    });

    test('a valid category value is accepted', () async {
      await expectLater(
        client.from('transactions').insert({
          'user_id': testUserId,
          'user_card_id': testUserCardId,
          'amount': 100,
          'description': 'Test valid category',
          'transaction_date': DateTime.now().toIso8601String(),
          'category': 'food',
        }),
        completes,
      );
    });

    test('NULL category is accepted (defense-in-depth)', () async {
      await expectLater(
        client.from('transactions').insert({
          'user_id': testUserId,
          'user_card_id': testUserCardId,
          'amount': 100,
          'description': 'Test null category',
          'transaction_date': DateTime.now().toIso8601String(),
          'category': null,
        }),
        completes,
      );
    });

    test('an invalid category value is rejected', () async {
      expect(
        () => client.from('transactions').insert({
          'user_id': testUserId,
          'user_card_id': testUserCardId,
          'amount': 100,
          'description': 'Test invalid category',
          'transaction_date': DateTime.now().toIso8601String(),
          'category': 'not_a_real_category',
        }),
        throwsA(isA<PostgrestException>()),
      );
    });

    test('a legacy pre-fix category value is also rejected (proves NOT '
        'VALID enforces on new writes immediately)', () async {
      expect(
        () => client.from('transactions').insert({
          'user_id': testUserId,
          'user_card_id': testUserCardId,
          'amount': 100,
          'description': 'Test legacy category',
          'transaction_date': DateTime.now().toIso8601String(),
          'category': 'dining',
        }),
        throwsA(isA<PostgrestException>()),
      );
    });
  }, skip: localSupabaseSkipReason);
}
