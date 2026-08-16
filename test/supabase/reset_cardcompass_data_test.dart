import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reset migration deletes owned app data but preserves auth user', () {
    final migrations = Directory('supabase/migrations')
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('_reset_cardcompass_data.sql'))
        .toList();

    expect(migrations, hasLength(1));
    final sql = migrations.single.readAsStringSync().toLowerCase();
    for (final table in const [
      'transactions',
      'emails',
      'statement_milestone_cache',
      'statements',
      'user_cards',
      'benefit_platform_confirmations',
      'gemini_proxy_usage',
    ]) {
      expect(sql, contains('delete from public.$table'));
    }
    expect(sql, contains('auth.uid()'));
    expect(sql, contains('security invoker'));
    expect(sql, isNot(contains('delete from auth.users')));
  });

  test('reset uses a locked private definer without exposing private rows', () {
    final sql = Directory('supabase/migrations')
        .listSync()
        .whereType<File>()
        .map((file) => file.readAsStringSync().toLowerCase())
        .join('\n');

    expect(sql, contains('private.reset_my_cardcompass_data'));
    expect(sql, contains('security definer'));
    expect(
      sql,
      contains(
        'revoke all on function private.reset_my_cardcompass_data() from public',
      ),
    );
    expect(
      sql,
      isNot(contains('grant select on public.benefit_platform_confirmations')),
    );
  });
}
