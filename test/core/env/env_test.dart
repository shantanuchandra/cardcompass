import 'package:cardcompass/core/env/env.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release-safe validation rejects a missing Supabase URL', () {
    expect(
      () => Env.validateValues(
        supabaseUrl: '',
        supabaseAnonKey: 'public-key',
        googleClientId: 'google-client',
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('SUPABASE_URL'),
        ),
      ),
    );
  });

  test('release-safe validation accepts a complete public configuration', () {
    expect(
      () => Env.validateValues(
        supabaseUrl: 'https://project.supabase.co',
        supabaseAnonKey: 'public-key',
        googleClientId: 'google-client',
      ),
      returnsNormally,
    );
  });
}
