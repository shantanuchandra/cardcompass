import test from 'node:test';
import assert from 'node:assert/strict';
import { readdir, readFile } from 'node:fs/promises';

const migrationsRoot = new URL('../../supabase/migrations/', import.meta.url);

test('forward migration preserves plus as a strong catalog product token', async () => {
  const names = (await readdir(migrationsRoot)).filter((name) =>
    name.endsWith('_preserve_catalog_plus_identity.sql')
  );
  assert.equal(names.length, 1, 'exactly one plus-identity migration is required');
  const sql = await readFile(new URL(names[0], migrationsRoot), 'utf8');

  assert.match(
    sql,
    /CREATE OR REPLACE FUNCTION public\.normalize_card_catalog_product\(_value text\)/i,
  );
  assert.match(
    sql,
    /CREATE OR REPLACE FUNCTION public\.normalize_card_catalog_family\(_value text\)/i,
  );
  assert.match(sql, /\[\+⁺\][\s\S]*' plus '/i);
  assert.match(sql, /'Zenith\+'\)[\s\S]*<> 'zenithplus'/i);
  assert.match(sql, /'Zenith Credit Card'\)[\s\S]*<> 'zenith'/i);
  assert.match(sql, /SET LOCAL lock_timeout = '5s'/i);
  assert.match(sql, /SET LOCAL statement_timeout = '30s'/i);
});
