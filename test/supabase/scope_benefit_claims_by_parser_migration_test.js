import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const migration = new URL(
  '../../supabase/migrations/20260818113000_scope_benefit_claims_by_parser.sql',
  import.meta.url,
);

test('claiming and expired-lease recovery are scoped to one parser generation', async () => {
  const sql = await readFile(migration, 'utf8');

  assert.match(sql, /DROP FUNCTION IF EXISTS public\.claim_card_catalog_enrichment_jobs\(integer, integer, text\)/i);
  assert.match(sql, /_parser_version text/i);
  assert.match(sql, /job\.parser_version\s*=\s*selected_parser/g);
  assert.match(sql, /leased\.parser_version\s*=\s*selected_parser/i);
  assert.match(sql, /REVOKE ALL ON FUNCTION public\.claim_card_catalog_enrichment_jobs\(integer, integer, text, text\)/i);
  assert.match(sql, /GRANT EXECUTE ON FUNCTION public\.claim_card_catalog_enrichment_jobs\(integer, integer, text, text\)\s+TO service_role/i);
});
