import test from 'node:test';
import assert from 'node:assert/strict';
import { readdir, readFile } from 'node:fs/promises';

const migrationsRoot = new URL('../../supabase/migrations/', import.meta.url);

test('forward migration binds the latest lifecycle query to the locked card row', async () => {
  const names = (await readdir(migrationsRoot)).filter((name) =>
    name.endsWith('_fix_catalog_identity_lifecycle_reference.sql')
  );
  assert.equal(names.length, 1, 'exactly one lifecycle-reference forward migration is required');
  assert.match(names[0], /^\d{14}_fix_catalog_identity_lifecycle_reference\.sql$/);
  const sql = await readFile(new URL(names[0], migrationsRoot), 'utf8');
  assert.match(
    sql,
    /pg_get_functiondef\(\s*'public\.publish_card_catalog_identity\(uuid,uuid,uuid,text,jsonb,uuid,text,text\)'::regprocedure/i,
  );
  assert.match(
    sql,
    /latest_job\.evidence->>''card_id'' = card_row\.id::text/i,
  );
  assert.match(sql, /IF fixed_definition IS NOT DISTINCT FROM installed_definition/i);
  assert.match(sql, /EXECUTE fixed_definition/i);
  assert.match(
    sql,
    /has_function_privilege\(\s*'service_role'[\s\S]*has_function_privilege\(\s*'authenticated'/i,
  );
});
