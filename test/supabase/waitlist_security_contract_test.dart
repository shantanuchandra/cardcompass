// Integration contract for the public waitlist boundary. Run this against a
// local Supabase instance after `supabase db reset`; it deliberately exercises
// the anon role rather than inspecting SQL text so a mistaken grant or RLS
// policy cannot slip through review.
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late SupabaseClient client;
  late SupabaseClient serviceClient;
  late String email;
  const serviceRoleKey = String.fromEnvironment('SUPABASE_SERVICE_ROLE_KEY');
  final permissionDenied = isA<PostgrestException>().having(
    (error) => error.code,
    'Postgres permission code',
    '42501',
  );

  setUpAll(() async {
    client = SupabaseClient(
      'http://127.0.0.1:54321',
      const String.fromEnvironment('SUPABASE_ANON_KEY'),
    );
    if (serviceRoleKey.isNotEmpty) {
      serviceClient = SupabaseClient('http://127.0.0.1:54321', serviceRoleKey);
    }
  });

  setUp(() {
    email =
        'waitlist-contract-${DateTime.now().microsecondsSinceEpoch}@example.com';
  });

  test('anon cannot read or write the waitlist table directly', () async {
    await expectLater(
      client.from('waitlist').select(),
      throwsA(permissionDenied),
    );
    await expectLater(
      client.from('waitlist').insert({'email': email}),
      throwsA(permissionDenied),
    );
    await expectLater(
      client
          .from('waitlist')
          .update({'name': 'Unauthorised'})
          .eq('email', email),
      throwsA(permissionDenied),
    );
  });

  test(
    'join returns a one-time enrichment token without exposing the row',
    () async {
      final result = await client.rpc(
        'join_waitlist',
        params: {
          'p_email': email,
          'p_source': 'landing-hero',
          'p_utm_source': 'newsletter',
          'p_utm_medium': 'email',
          'p_utm_campaign': 'founding-100',
          'p_referrer_path': '/',
          'p_landing_variant': 'receipt-a',
          'p_privacy_consent': true,
        },
      );

      expect(result, isA<List>());
      final row = (result as List).single as Map<String, dynamic>;
      expect(row['status'], 'joined');
      expect(
        row['enrichment_token'],
        isA<String>().having((token) => token.length, 'length', 64),
      );
      expect(row.containsKey('id'), isFalse);
      expect(row.containsKey('email'), isFalse);
    },
  );

  test(
    'a duplicate join neither discloses a row nor issues another token',
    () async {
      await client.rpc(
        'join_waitlist',
        params: {'p_email': email, 'p_privacy_consent': true},
      );

      final duplicate = await client.rpc(
        'join_waitlist',
        params: {'p_email': email, 'p_privacy_consent': true},
      );
      final row = (duplicate as List).single as Map<String, dynamic>;

      expect(row['status'], 'already_joined');
      expect(row['enrichment_token'], isNull);
      expect(row.containsKey('id'), isFalse);
      expect(row.containsKey('email'), isFalse);
    },
  );

  test(
    'enrichment requires the issued token and validates qualification values',
    () async {
      final join = await client.rpc(
        'join_waitlist',
        params: {'p_email': email, 'p_privacy_consent': true},
      );
      final token =
          ((join as List).single as Map<String, dynamic>)['enrichment_token']
              as String;

      final rejected = await client.rpc(
        'enrich_waitlist',
        params: {
          'p_enrichment_token': '0' * 64,
          'p_name': 'Aarav',
          'p_card_count': '3-6',
          'p_monthly_spend_band': '50k-1l',
          'p_primary_goal': 'maximize_rewards',
          'p_problem_detail': 'I want to stop missing category rewards.',
          'p_top_cards': ['HDFC Regalia Gold', 'SBI Cashback'],
          'p_marketing_consent': true,
        },
      );
      expect(rejected, false);

      await expectLater(
        client.rpc(
          'enrich_waitlist',
          params: {
            'p_enrichment_token': token,
            'p_card_count': '3-5',
            'p_monthly_spend_band': '50k-1l',
            'p_primary_goal': 'maximize_rewards',
          },
        ),
        throwsA(isA<PostgrestException>()),
      );

      await expectLater(
        client.rpc(
          'enrich_waitlist',
          params: {
            'p_enrichment_token': token,
            'p_card_count': '3-6',
            'p_monthly_spend_band': '50k-1l',
            'p_primary_goal': 'maximize_rewards',
            'p_top_cards': ['Card One', 'Card Two', 'Card Three'],
          },
        ),
        throwsA(isA<PostgrestException>()),
      );

      final enriched = await client.rpc(
        'enrich_waitlist',
        params: {
          'p_enrichment_token': token,
          'p_name': 'Aarav',
          'p_card_count': '3-6',
          'p_monthly_spend_band': '50k-1l',
          'p_primary_goal': 'maximize_rewards',
          'p_problem_detail': 'I want to stop missing category rewards.',
          'p_top_cards': ['HDFC Regalia Gold', 'SBI Cashback'],
          'p_marketing_consent': true,
        },
      );
      expect(enriched, true);

      final replayed = await client.rpc(
        'enrich_waitlist',
        params: {
          'p_enrichment_token': token,
          'p_card_count': '3-6',
          'p_monthly_spend_band': '50k-1l',
          'p_primary_goal': 'maximize_rewards',
        },
      );
      expect(replayed, false);
    },
  );

  test('enrichment rejects an incomplete qualification profile', () async {
    final join = await client.rpc(
      'join_waitlist',
      params: {'p_email': email, 'p_privacy_consent': true},
    );
    final token =
        ((join as List).single as Map<String, dynamic>)['enrichment_token']
            as String;

    await expectLater(
      client.rpc(
        'enrich_waitlist',
        params: {
          'p_enrichment_token': token,
          'p_card_count': '3-6',
          'p_monthly_spend_band': '50k-1l',
        },
      ),
      throwsA(isA<PostgrestException>()),
    );
  });

  test('anon cannot query the ranked operator view', () async {
    await expectLater(
      client.from('operator_waitlist_ranked').select(),
      throwsA(permissionDenied),
    );
  });

  test(
    'the operator view ranks a fully qualified 3-6-card lead above a 1-2-card lead',
    () async {
      final base = DateTime.now().microsecondsSinceEpoch;
      final highPriorityEmail = 'waitlist-ranked-$base-a@example.com';
      final lowerPriorityEmail = 'waitlist-ranked-$base-b@example.com';

      Future<void> joinAndEnrich(
        String candidateEmail,
        String cardCount,
      ) async {
        final join = await client.rpc(
          'join_waitlist',
          params: {'p_email': candidateEmail, 'p_privacy_consent': true},
        );
        final token =
            ((join as List).single as Map<String, dynamic>)['enrichment_token']
                as String;
        final enriched = await client.rpc(
          'enrich_waitlist',
          params: {
            'p_enrichment_token': token,
            'p_card_count': cardCount,
            'p_monthly_spend_band': '50k-1l',
            'p_primary_goal': 'maximize_rewards',
          },
        );
        expect(enriched, true);
      }

      await joinAndEnrich(highPriorityEmail, '3-6');
      await joinAndEnrich(lowerPriorityEmail, '1-2');

      final highPriorityRow = await serviceClient
          .from('operator_waitlist_ranked')
          .select('email,rank_score')
          .eq('email', highPriorityEmail)
          .single();
      final lowerPriorityRow = await serviceClient
          .from('operator_waitlist_ranked')
          .select('email,rank_score')
          .eq('email', lowerPriorityEmail)
          .single();

      expect(
        highPriorityRow['rank_score'],
        greaterThan(lowerPriorityRow['rank_score']),
      );
    },
    skip: serviceRoleKey.isEmpty
        ? 'Run with --dart-define=SUPABASE_SERVICE_ROLE_KEY=<local service-role key>.'
        : false,
  );
}
