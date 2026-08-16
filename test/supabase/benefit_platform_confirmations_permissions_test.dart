// test/supabase/benefit_platform_confirmations_permissions_test.dart
//
// Integration test against a LIVE local Supabase instance. Run `supabase
// start` first. This proves the exact SQL grants from Task 8 behave as
// claimed — a fake data source cannot catch a REVOKE/GRANT mistake that
// only manifests against real Postgres role permissions (design spec §12).
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'local_supabase_test_support.dart';

void main() {
  group('local Supabase integration', () {
    late SupabaseClient client;
    late String testUserId;
    const testBenefitId =
        '75c8316b-3fcf-40de-af2c-18838942d5b5'; // real seed row

    setUpAll(() async {
      await Supabase.initialize(
        url: 'http://127.0.0.1:54321',
        publishableKey: localSupabaseAnonKey,
      );
      client = Supabase.instance.client;
      final auth = await client.auth.signUp(
        email: 'movie-deals-permissions-test@example.com',
        password: 'test-password-1234',
      );
      testUserId = auth.user!.id;
    });

    test(
      'authenticated role cannot SELECT the base confirmations table directly',
      () async {
        expect(
          () => client.from('benefit_platform_confirmations').select(),
          throwsA(isA<PostgrestException>()),
        );
      },
    );

    test(
      'authenticated role CAN SELECT the aggregate confirmation_counts view',
      () async {
        final result = await client
            .from('benefit_platform_confirmation_counts')
            .select();
        expect(
          result,
          isA<List>(),
        ); // succeeds, even if empty — no permission error
      },
    );

    test(
      'a duplicate confirmation insert via upsert/ON CONFLICT succeeds silently, never raises 23505',
      () async {
        await client
            .from('benefit_platform_confirmations')
            .upsert(
              {
                'benefit_id': testBenefitId,
                'platform': 'BookMyShow',
                'user_id': testUserId,
              },
              onConflict: 'user_id,benefit_id,platform_key',
              ignoreDuplicates: true,
            );

        // The second identical insert must not throw — this is the exact
        // mechanism Task 11's insertConfirmation() uses.
        await expectLater(
          client
              .from('benefit_platform_confirmations')
              .upsert(
                {
                  'benefit_id': testBenefitId,
                  'platform': 'BookMyShow',
                  'user_id': testUserId,
                },
                onConflict: 'user_id,benefit_id,platform_key',
                ignoreDuplicates: true,
              ),
          completes,
        );

        final counts = await client
            .from('benefit_platform_confirmation_counts')
            .select()
            .eq('benefit_id', testBenefitId)
            .eq('platform_key', 'bookmyshow');
        expect(
          (counts as List).first['confirmation_count'],
          1,
        ); // not 2 — dedup confirmed
      },
    );
  }, skip: localSupabaseSkipReason);
}
