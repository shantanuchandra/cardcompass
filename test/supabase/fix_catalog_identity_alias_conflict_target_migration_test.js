import test from 'node:test';
import assert from 'node:assert/strict';
import { readdir, readFile } from 'node:fs/promises';

const migrationsRoot = new URL('../../supabase/migrations/', import.meta.url);

test('forward migration uses the alias constraint instead of ambiguous output-column names', async () => {
  const names = (await readdir(migrationsRoot)).filter((name) =>
    name.endsWith('_fix_catalog_identity_alias_conflict_target.sql')
  );
  assert.equal(names.length, 1, 'exactly one alias-conflict forward migration is required');
  const sql = await readFile(new URL(names[0], migrationsRoot), 'utf8');
  assert.match(names[0], /^\d{14}_fix_catalog_identity_alias_conflict_target\.sql$/);
  assert.match(
    sql,
    /ON CONFLICT ON CONSTRAINT card_catalog_aliases_card_id_normalized_alias_key DO NOTHING/i,
  );
  assert.match(sql, /IF fixed_definition IS NOT DISTINCT FROM installed_definition/i);
  assert.match(sql, /EXECUTE fixed_definition/i);
  assert.match(
    sql,
    /has_function_privilege\(\s*'service_role'[\s\S]*has_function_privilege\(\s*'authenticated'/i,
  );
});
