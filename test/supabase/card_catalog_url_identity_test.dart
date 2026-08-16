import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('migration protects canonical URL identity and enrichment jobs', () {
    final migration = File(
      'supabase/migrations/20260816175215_card_catalog_url_identity.sql',
    );
    expect(migration.existsSync(), isTrue);

    final sql = migration.readAsStringSync().toLowerCase();
    expect(sql, contains('canonical_submitted_url text'));
    expect(sql, contains('canonical_final_url text'));
    expect(sql, contains('submitted_url_hash text'));
    expect(sql, contains('final_url_hash text'));
    expect(sql, contains('create unique index'));
    expect(sql, contains('resolve_card_catalog_identity'));
    expect(sql, contains('pg_advisory_xact_lock'));
    expect(sql, contains('card_catalog_enrichment_jobs'));
    expect(sql, contains('enable row level security'));
    expect(sql, contains('revoke all on function'));
    expect(sql, contains('grant execute on function'));
    expect(sql, contains('to service_role'));
  });

  test('catalog resolver cannot be executed by application roles', () {
    final sql = File(
      'supabase/migrations/20260816175215_card_catalog_url_identity.sql',
    ).readAsStringSync().toLowerCase();

    expect(
      RegExp(
        r'revoke all on function public\.resolve_card_catalog_identity\([\s\S]*?\)'
        r' from public, anon, authenticated;',
      ).hasMatch(sql),
      isTrue,
    );
    expect(
      RegExp(
        r'grant execute on function public\.resolve_card_catalog_identity\([\s\S]*?\)'
        r' to service_role;',
      ).hasMatch(sql),
      isTrue,
    );
    expect(sql, isNot(contains('to anon')));
    expect(sql, isNot(contains('to authenticated')));
  });
}
