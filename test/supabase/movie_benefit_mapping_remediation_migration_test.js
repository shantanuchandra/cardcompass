import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const migration = new URL(
  '../../supabase/migrations/20260818090000_movie_benefit_mapping_remediation.sql',
  import.meta.url,
);
const healthFixMigration = new URL(
  '../../supabase/migrations/20260818100000_fix_movie_benefit_mapping_health.sql',
  import.meta.url,
);

async function migrationSql() {
  return readFile(migration, 'utf8');
}

test('exposes movie mapping health only to the service role', async () => {
  const sql = await migrationSql();

  assert.match(sql, /CREATE OR REPLACE FUNCTION public\.get_movie_benefit_mapping_health\(\)/i);
  assert.match(sql, /RETURNS TABLE\s*\(\s*metric text,\s*value bigint/i);
  assert.match(sql, /auth\.role\(\)\s*<>\s*'service_role'/i);
  assert.match(sql, /active_movie_benefits/i);
  assert.match(sql, /mapped_active_movie_benefits/i);
  assert.match(sql, /orphaned_active_movie_benefits/i);
  assert.match(sql, /REVOKE ALL ON FUNCTION public\.get_movie_benefit_mapping_health\(\)\s+FROM PUBLIC, anon, authenticated/i);
  assert.match(sql, /GRANT EXECUTE ON FUNCTION public\.get_movie_benefit_mapping_health\(\)\s+TO service_role/i);
});

test('backfills only the source-verified IDFC Classic movie benefit', async () => {
  const sql = await migrationSql();

  assert.match(sql, /INSERT INTO public\.card_benefit_mapping/i);
  assert.match(sql, /c\.bank\s*=\s*'IDFC FIRST Bank'/i);
  assert.match(sql, /c\.card_name\s*=\s*'Classic'/i);
  assert.match(sql, /b\.title\s*=\s*'25% Off on Movie Tickets'/i);
  assert.match(sql, /c\.card_url\s*=\s*b\.source_url/i);
  assert.match(sql, /ON CONFLICT \(card_id, benefit_id\) DO NOTHING/i);
  assert.doesNotMatch(sql, /INSERT[\s\S]*SBI Card ELITE/i);
});

test('removes one exact HDFC semantic duplicate mapping without deleting benefit evidence', async () => {
  const sql = await migrationSql();

  assert.match(sql, /DELETE FROM public\.card_benefit_mapping AS mapping/i);
  assert.match(sql, /c\.bank\s*=\s*'HDFC Bank'/i);
  assert.match(sql, /c\.card_name\s*=\s*'Diners Club Black'/i);
  assert.match(sql, /b\.title\s*=\s*'Monthly Milestone Benefits'/i);
  assert.doesNotMatch(sql, /DELETE FROM public\.benefits/i);
});

test('normalizes only exact known catalog labels', async () => {
  const sql = await migrationSql();

  assert.match(sql, /SET card_name\s*=\s*'FIRST Private Credit Card'/i);
  assert.match(sql, /card_name\s*=\s*'Firstprivatecreditcard'/i);
  assert.match(sql, /SET card_name\s*=\s*'IndianOil'/i);
  assert.match(sql, /bank\s*=\s*'Axis Bank'[\s\S]*card_name\s*=\s*'Indianoil'/i);
  assert.match(sql, /SET bank\s*=\s*'IDFC FIRST Bank'/i);
  assert.match(sql, /bank\s*=\s*'IDFC First Bank'/i);
});

test('follow-up health RPC mirrors the repository schema and widened predicate', async () => {
  const sql = await readFile(healthFixMigration, 'utf8');

  assert.match(sql, /benefit\.benefit_category\s*=\s*'entertainment'/i);
  assert.match(sql, /benefit\.value_config\s*->>\s*'category'\s+ILIKE\s+'%movie%'/i);
  assert.match(sql, /benefit\.value_config\s*->>\s*'discount_type'\s+ILIKE\s+'%movie%'/i);
  for (const keyword of ['movie', 'cinema', 'bookmyshow', 'pvr', 'inox', 'cinepolis']) {
    assert.match(sql, new RegExp(`benefit\\.title ILIKE '%${keyword}%'`, 'i'));
    assert.match(sql, new RegExp(`benefit\\.description ILIKE '%${keyword}%'`, 'i'));
  }
  assert.doesNotMatch(sql, /benefit\.(?:category|subcategory)\b/i);
});
