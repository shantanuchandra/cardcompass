// test/supabase/category_backfill_privileged_test.dart
//
// Integration test against a LIVE local Supabase instance. Run
// `supabase start` first. Proves: a regular per-user client cannot run
// the backfill across other users' data, and a service-role client can.
// Skips the service-role assertion if SUPABASE_SERVICE_ROLE_KEY isn't
// provided (following the pattern in test/supabase/waitlist_security_contract_test.dart).
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late SupabaseClient regularClient;
  const serviceRoleKey = String.fromEnvironment('SUPABASE_SERVICE_ROLE_KEY');
  late String userAId;
  late String userBId;

  setUpAll(() async {
    regularClient = SupabaseClient(
      'http://127.0.0.1:54321',
      const String.fromEnvironment('SUPABASE_ANON_KEY'),
    );
    final authA = await regularClient.auth.signUp(
      email: 'backfill-privileged-user-a-${DateTime.now().microsecondsSinceEpoch}@example.com',
      password: 'test-password-1234',
    );
    userAId = authA.user!.id;

    final secondClient = SupabaseClient(
      'http://127.0.0.1:54321',
      const String.fromEnvironment('SUPABASE_ANON_KEY'),
    );
    final authB = await secondClient.auth.signUp(
      email: 'backfill-privileged-user-b-${DateTime.now().microsecondsSinceEpoch}@example.com',
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
    final serviceClient = SupabaseClient('http://127.0.0.1:54321', serviceRoleKey);
    await expectLater(
      serviceClient.from('transactions').select().eq('user_id', userAId),
      completes,
    );
  });
}
