import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import assert from 'node:assert/strict';

const migrationPath = path.join(
  process.cwd(),
  'supabase/migrations/20260821150000_fix_card_catalog_network_case_normalization.sql',
);

test('forward migration normalizes network case before stripping characters', () => {
  const sql = fs.readFileSync(migrationPath, 'utf8');
  assert.match(
    sql,
    /CREATE OR REPLACE FUNCTION public\.normalize_card_catalog_network\(_value text\)/i,
  );
  assert.match(
    sql,
    /regexp_replace\(lower\(trim\(coalesce\(_value, ''\)\)\), '\[\^a-z0-9\]\+', '', 'g'\)/i,
  );
  assert.doesNotMatch(
    sql,
    /lower\(regexp_replace\(trim\(coalesce\(_value, ''\)\), '\[\^a-z0-9\]\+'/i,
  );
  assert.match(sql, /normalize_card_catalog_network\('Visa'\).*'visa'/is);
  assert.match(sql, /normalize_card_catalog_network\('MASTERCARD'\).*'mastercard'/is);
  assert.match(
    sql,
    /card_catalog_effective_network\(\s*'Visa'.*'Task11 Visa Infinite Credit Card'/is,
  );
  assert.match(
    sql,
    /REVOKE ALL ON FUNCTION public\.normalize_card_catalog_network\(text\)\s+FROM PUBLIC, anon, authenticated/i,
  );
  assert.match(
    sql,
    /GRANT EXECUTE ON FUNCTION public\.normalize_card_catalog_network\(text\)\s+TO service_role/i,
  );
});
