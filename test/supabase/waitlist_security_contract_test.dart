// Integration contract for the public waitlist boundary. Run this against a
// local Supabase instance after `supabase db reset`; it deliberately exercises
// the anon role rather than inspecting SQL text so a mistaken grant or RLS
// policy cannot slip through review.
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'local_supabase_test_support.dart';

void main() {
  group('local Supabase integration', () {
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
      client = SupabaseClient('http://127.0.0.1:54321', localSupabaseAnonKey);
      if (serviceRoleKey.isNotEmpty) {
        serviceClient = SupabaseClient(
          'http://127.0.0.1:54321',
          serviceRoleKey,
        );
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
        expect(row['status'], 'accepted');
        expect(
          row['enrichment_token'],
          isA<String>().having((token) => token.length, 'length', 64),
        );
        expect(row.containsKey('id'), isFalse);
        expect(row.containsKey('email'), isFalse);
      },
    );

    test(
      'new and duplicate joins have the same public response shape',
      () async {
        final first = await client.rpc(
          'join_waitlist',
          params: {'p_email': email, 'p_privacy_consent': true},
        );

        final duplicate = await client.rpc(
          'join_waitlist',
          params: {'p_email': email, 'p_privacy_consent': true},
        );
        final firstRow = (first as List).single as Map<String, dynamic>;
        final row = (duplicate as List).single as Map<String, dynamic>;

        expect(firstRow['status'], 'accepted');
        expect(row['status'], firstRow['status']);
        expect(
          firstRow['enrichment_token'],
          isA<String>().having((token) => token.length, 'length', 64),
        );
        expect(
          row['enrichment_token'],
          isA<String>().having((token) => token.length, 'length', 64),
        );
        expect(row['enrichment_token'], isNot(firstRow['enrichment_token']));
        expect(row.containsKey('id'), isFalse);
        expect(row.containsKey('email'), isFalse);

        final decoyEnrichment = await client.rpc(
          'enrich_waitlist',
          params: {
            'p_enrichment_token': row['enrichment_token'],
            'p_card_count': '3-6',
            'p_monthly_spend_band': '50k-1l',
            'p_primary_goal': 'maximize_rewards',
          },
        );
        expect(decoyEnrichment, true);
      },
    );

    test(
      'enrichment validates malformed tokens and qualification values',
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
            'p_enrichment_token': 'not-a-token',
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
        expect(replayed, true);
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
      'a duplicate decoy token reports success without mutating the existing lead',
      () async {
        final first = await client.rpc(
          'join_waitlist',
          params: {'p_email': email, 'p_privacy_consent': true},
        );
        final firstToken =
            ((first as List).single as Map<String, dynamic>)['enrichment_token']
                as String;
        await client.rpc(
          'enrich_waitlist',
          params: {
            'p_enrichment_token': firstToken,
            'p_card_count': '1-2',
            'p_monthly_spend_band': '50k-1l',
            'p_primary_goal': 'maximize_rewards',
          },
        );

        final duplicate = await client.rpc(
          'join_waitlist',
          params: {'p_email': email, 'p_privacy_consent': true},
        );
        final decoyToken =
            ((duplicate as List).single
                    as Map<String, dynamic>)['enrichment_token']
                as String;
        final decoyResult = await client.rpc(
          'enrich_waitlist',
          params: {
            'p_enrichment_token': decoyToken,
            'p_card_count': '3-6',
            'p_monthly_spend_band': '1l-plus',
            'p_primary_goal': 'track_benefits',
          },
        );
        expect(decoyResult, true);

        final row = await serviceClient
            .from('operator_waitlist_ranked')
            .select('card_count,monthly_spend_band,primary_goal')
            .eq('email', email)
            .single();
        expect(row['card_count'], '1-2');
        expect(row['monthly_spend_band'], '50k-1l');
        expect(row['primary_goal'], 'maximize_rewards');
      },
      skip: serviceRoleKey.isEmpty
          ? 'Run with --dart-define=SUPABASE_SERVICE_ROLE_KEY=<local service-role key>.'
          : false,
    );

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
              ((join as List).single
                      as Map<String, dynamic>)['enrichment_token']
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

    test(
      'public marketing choice remains requested and unverified',
      () async {
        final join = await client.rpc(
          'join_waitlist',
          params: {
            'p_email': email,
            'p_privacy_consent': true,
            'p_website': '',
          },
        );
        final token =
            ((join as List).single as Map<String, dynamic>)['enrichment_token']
                as String;
        await client.rpc(
          'enrich_waitlist',
          params: {
            'p_enrichment_token': token,
            'p_card_count': '3-6',
            'p_monthly_spend_band': '50k-1l',
            'p_primary_goal': 'maximize_rewards',
            'p_marketing_consent': true,
          },
        );
        final row = await serviceClient
            .from('operator_waitlist_ranked')
            .select('marketing_consent_requested_at,marketing_consent_at')
            .eq('email', email)
            .single();
        expect(row['marketing_consent_requested_at'], isNotNull);
        expect(row['marketing_consent_at'], isNull);
      },
      skip: serviceRoleKey.isEmpty
          ? 'Run with --dart-define=SUPABASE_SERVICE_ROLE_KEY=<local service-role key>.'
          : false,
    );

    test(
      'honeypot keeps the success shape without creating a lead',
      () async {
        final result = await client.rpc(
          'join_waitlist',
          params: {
            'p_email': email,
            'p_privacy_consent': true,
            'p_website': 'https://bot.example',
          },
        );
        expect((result as List).single['status'], 'accepted');
        final rows = await serviceClient
            .from('operator_waitlist_ranked')
            .select('id')
            .eq('email', email);
        expect(rows, isEmpty);
      },
      skip: serviceRoleKey.isEmpty
          ? 'Run with --dart-define=SUPABASE_SERVICE_ROLE_KEY=<local service-role key>.'
          : false,
    );
  }, skip: localSupabaseSkipReason);
}
