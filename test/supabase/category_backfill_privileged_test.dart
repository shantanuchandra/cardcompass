// test/supabase/category_backfill_privileged_test.dart
//
// Integration test against a LIVE local Supabase instance. Run
// `supabase start` first. Proves: a regular per-user client cannot run
// the backfill across other users' data, and a service-role client can.
// Skips the service-role assertion if SUPABASE_SERVICE_ROLE_KEY isn't
// provided (following the pattern in test/supabase/waitlist_security_contract_test.dart).
//
// User A gets one seeded transaction (card_catalog -> user_cards ->
// transactions, matching the pattern in
// test/supabase/get_uncategorized_transactions_test.dart and
// test/supabase/transactions_category_check_test.dart) so the
// service-role assertion below can check actual returned content,
// not just that the call didn't throw.
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'local_supabase_test_support.dart';

void main() {
  group('local Supabase integration', () {
    late SupabaseClient regularClient;
    const serviceRoleKey = String.fromEnvironment('SUPABASE_SERVICE_ROLE_KEY');
    late String userAId;
    late String userBId;

    setUpAll(() async {
      regularClient = SupabaseClient(
        localSupabaseUrl,
        localSupabaseAnonKey,
      );
      final authA = await regularClient.auth.signUp(
        email:
            'backfill-privileged-user-a-${DateTime.now().microsecondsSinceEpoch}@example.com',
        password: 'test-password-1234',
      );
      userAId = authA.user!.id;

      final catalog = await regularClient
          .from('card_catalog')
          .select('id')
          .limit(1)
          .single();
      final card = await regularClient
          .from('user_cards')
          .insert({'user_id': userAId, 'catalog_card_id': catalog['id']})
          .select('id')
          .single();
      final userACardId = card['id'] as String;

      await regularClient.from('transactions').insert({
        'user_id': userAId,
        'user_card_id': userACardId,
        'amount': 100,
        'description': 'backfill privileged-path fixture transaction',
        'transaction_date': DateTime.now().toIso8601String(),
        'category': 'other',
      });

      final secondClient = SupabaseClient(
        localSupabaseUrl,
        localSupabaseAnonKey,
      );
      final authB = await secondClient.auth.signUp(
        email:
            'backfill-privileged-user-b-${DateTime.now().microsecondsSinceEpoch}@example.com',
        password: 'test-password-1234',
      );
      userBId = authB.user!.id;
    });

    test('a regular authenticated client cannot read another user\'s '
        'transactions — proving the backfill cannot run as a normal user '
        'session across all users', () async {
      final result = await regularClient
          .from('transactions')
          .select()
          .eq('user_id', userBId);
      expect(result, isEmpty);
    });

    test('a service-role client CAN read across all users — the privileged '
        'path the backfill must actually use in production', () async {
      if (serviceRoleKey.isEmpty) {
        return; // documented skip, no service-role key available
      }
      final serviceClient = SupabaseClient(
        localSupabaseUrl,
        serviceRoleKey,
      );
      final result = await serviceClient
          .from('transactions')
          .select()
          .eq('user_id', userAId);
      // Not just "didn't throw" — actually contains the fixture row seeded
      // in setUpAll, proving the service-role client genuinely sees user
      // A's data rather than e.g. an empty result that would also satisfy
      // a bare `completes` check.
      expect(result, isNotEmpty);
      expect(
        result.map((row) => row['description']),
        contains('backfill privileged-path fixture transaction'),
      );
    });
  }, skip: localSupabaseSkipReason);
}
