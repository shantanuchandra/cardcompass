import test from 'node:test';
import assert from 'node:assert/strict';
import { readdir, readFile } from 'node:fs/promises';

const migrationsRoot = new URL('../../supabase/migrations/', import.meta.url);

test('forward migration gives Task7 local variables an explicit PL/pgSQL block label', async () => {
  const names = (await readdir(migrationsRoot)).filter((name) =>
    name.endsWith('_fix_catalog_identity_block_qualification.sql')
  );
  assert.equal(names.length, 1, 'exactly one block-qualification migration is required');
  assert.match(names[0], /^\d{14}_fix_catalog_identity_block_qualification\.sql$/);
  const sql = await readFile(new URL(names[0], migrationsRoot), 'utf8');
  assert.match(sql, /<<publish_card_catalog_identity_block>>/i);
  assert.match(sql, /publish_card_catalog_identity_block\.content_hash/i);
  assert.match(sql, /publish_card_catalog_identity_block\.retrieved_at/i);
  assert.match(sql, /publish_card_catalog_identity_block\.resolved_card_id/i);
  assert.match(sql, /IF fixed_definition IS NOT DISTINCT FROM installed_definition/i);
  assert.match(sql, /EXECUTE fixed_definition/i);
  assert.match(
    sql,
    /has_function_privilege\(\s*'service_role'[\s\S]*has_function_privilege\(\s*'authenticated'/i,
  );
});
