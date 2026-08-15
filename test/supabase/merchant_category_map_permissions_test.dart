// test/supabase/merchant_category_map_permissions_test.dart
//
// Integration test against a LIVE local Supabase instance. Run
// `supabase start` (or `supabase db reset` to apply migrations fresh)
// before running this file.
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late SupabaseClient client;

  setUpAll(() async {
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
    );
    client = Supabase.instance.client;
    await client.auth.signUp(
      email: 'merchant-category-map-test@example.com',
      password: 'test-password-1234',
    );
  });

  test('authenticated role can SELECT merchant_category_map', () async {
    final result = await client.from('merchant_category_map').select().limit(1);
    expect(result, isA<List>());
  });

  test('seed data is present and correctly categorized', () async {
    final result = await client
        .from('merchant_category_map')
        .select()
        .eq('merchant_name_normalized', 'CARREFOUR')
        .single();
    expect(result['category'], 'grocery');
  });

  test('the category CHECK constraint rejects an invalid value', () async {
    expect(
      () => client.from('merchant_category_map').insert({
        'merchant_name_normalized': 'TEST_INVALID_ROW',
        'category': 'not_a_real_category',
      }),
      throwsA(isA<PostgrestException>()),
    );
  });

  test('authenticated role cannot INSERT (no write grant exists)', () async {
    expect(
      () => client.from('merchant_category_map').insert({
        'merchant_name_normalized': 'TEST_SHOULD_FAIL',
        'category': 'shopping',
      }),
      throwsA(isA<PostgrestException>()),
    );
  });
}
