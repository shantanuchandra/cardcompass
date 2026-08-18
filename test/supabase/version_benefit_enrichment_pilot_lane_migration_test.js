import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const migration = new URL(
  '../../supabase/migrations/20260818100125_version_benefit_enrichment_pilot_lane.sql',
  import.meta.url,
);

test('versions pilot initialization by parser without rewriting prior pilot evidence', async () => {
  const sql = await readFile(migration, 'utf8');

  assert.match(sql, /CREATE OR REPLACE FUNCTION public\.initialize_card_benefit_enrichment_pilot/i);
  assert.match(sql, /SECURITY INVOKER/i);
  assert.match(sql, /coalesce\(auth\.role\(\),\s*''\)\s*<>\s*'service_role'/i);
  assert.match(sql, /WHERE run_mode\s*=\s*'pilot'\s+AND parser_version\s*=\s*trim\(_parser_version\)/i);
  assert.match(sql, /WHERE job\.run_mode\s*=\s*'pilot'\s+AND job\.parser_version\s*=\s*trim\(_parser_version\)/i);
  assert.match(sql, /ON CONFLICT \(job_key\) DO NOTHING/i);
  assert.doesNotMatch(sql, /DELETE FROM public\.card_catalog_enrichment_jobs/i);
  assert.doesNotMatch(sql, /UPDATE public\.card_catalog_enrichment_jobs/i);
  assert.match(sql, /REVOKE ALL ON FUNCTION public\.initialize_card_benefit_enrichment_pilot\(jsonb, text\)\s+FROM PUBLIC, anon, authenticated/i);
  assert.match(sql, /GRANT EXECUTE ON FUNCTION public\.initialize_card_benefit_enrichment_pilot\(jsonb, text\)\s+TO service_role/i);
});
