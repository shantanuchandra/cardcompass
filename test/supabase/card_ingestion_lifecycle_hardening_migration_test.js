import test from 'node:test';
import assert from 'node:assert/strict';
import { readdir, readFile } from 'node:fs/promises';

const repoRoot = new URL('../../', import.meta.url);
const migrationsRoot = new URL('supabase/migrations/', repoRoot);

async function lifecycleMigration() {
  const names = (await readdir(migrationsRoot)).filter((name) =>
    name.endsWith('_card_ingestion_lifecycle_hardening.sql')
  );
  assert.equal(
    names.length,
    1,
    'exactly one CLI-generated lifecycle hardening migration is required',
  );
  assert.match(names[0], /^\d{14}_card_ingestion_lifecycle_hardening\.sql$/);
  return readFile(new URL(names[0], migrationsRoot), 'utf8');
}

test('adds only the two lifecycle columns with bounded deployment locks and due indexes', async () => {
  const sql = await lifecycleMigration();

  assert.match(sql, /SET LOCAL lock_timeout\s*=\s*'\d+s'/i);
  assert.match(sql, /SET LOCAL statement_timeout\s*=\s*'\d+s'/i);
  assert.match(
    sql,
    /ALTER TABLE public\.card_catalog_enrichment_jobs[\s\S]*ADD COLUMN IF NOT EXISTS next_run_at timestamptz/i,
  );
  assert.match(
    sql,
    /CREATE INDEX IF NOT EXISTS \w+[\s\S]*ON public\.card_catalog_enrichment_jobs\s*\(\s*parser_version\s*,\s*run_mode\s*,\s*next_run_at\s*,\s*issuer\s*\)[\s\S]*WHERE status IN \(\s*'staged'\s*,\s*'completed'\s*,\s*'review_required'\s*,\s*'quarantined'\s*\)[\s\S]*next_run_at IS NOT NULL/i,
  );
  assert.match(
    sql,
    /ALTER TABLE public\.card_benefit_mapping[\s\S]*ADD COLUMN IF NOT EXISTS retired_at timestamptz/i,
  );
  assert.match(
    sql,
    /CREATE INDEX IF NOT EXISTS \w+[\s\S]*ON public\.card_benefit_mapping\s*\(\s*card_id\s*,\s*display_priority\s*\)[\s\S]*WHERE retired_at IS NULL/i,
  );

  const addedColumns = [...sql.matchAll(/ADD COLUMN IF NOT EXISTS\s+([a-z_]+)/gi)]
    .map((match) => match[1])
    .filter((name) => name === 'next_run_at' || name === 'retired_at');
  assert.deepEqual(addedColumns.sort(), ['next_run_at', 'retired_at']);
  assert.doesNotMatch(sql, /CREATE\s+(?:UNLOGGED\s+)?TABLE\b/i);
  assert.doesNotMatch(sql, /DROP\s+(?:TABLE|SCHEMA|COLUMN)\b/i);
});

test('repairs legacy catalog and JSON values before validating strict shapes', async () => {
  const sql = await lifecycleMigration();

  const discontinuedRepair = sql.search(
    /UPDATE public\.card_catalog[\s\S]*is_discontinued\s*=\s*false[\s\S]*WHERE is_discontinued IS NULL/i,
  );
  const discontinuedNotNull = sql.search(
    /ALTER TABLE public\.card_catalog\s+[\s\S]*ALTER COLUMN is_discontinued SET NOT NULL/i,
  );
  assert.ok(discontinuedRepair >= 0 && discontinuedRepair < discontinuedNotNull);

  assert.match(
    sql,
    /UPDATE public\.benefits[\s\S]*value_config[\s\S]*partners[\s\S]*exclusions[\s\S]*regions/i,
  );
  assert.match(sql, /jsonb_array_elements\([^)]+exclusions[^)]*\)/i);
  assert.match(sql, /jsonb_typeof\([^)]+\)\s*=\s*'string'/i);
  assert.match(sql, /'source_terms'/i);
  assert.match(sql, /existing_additional[\s\S]*\|\|[\s\S]*jsonb_build_object\(\s*'source_terms'/i);

  for (const constraint of [
    'benefits_value_config_object_check',
    'benefits_partners_array_check',
    'benefits_exclusions_object_check',
    'benefits_regions_array_check',
    'card_catalog_enrichment_jobs_result_summary_object_check',
  ]) {
    assert.match(
      sql,
      new RegExp(`ADD CONSTRAINT ${constraint}[\\s\\S]*NOT VALID`, 'i'),
    );
    assert.match(
      sql,
      new RegExp(`VALIDATE CONSTRAINT ${constraint}`, 'i'),
    );
  }

  assert.match(sql, /jsonb_typeof\(value_config\)\s*=\s*'object'/i);
  assert.match(sql, /jsonb_typeof\(partners\)\s*=\s*'array'/i);
  assert.match(sql, /jsonb_typeof\(regions\)\s*=\s*'array'/i);
  assert.match(sql, /jsonb_typeof\(exclusions\)\s*=\s*'object'/i);
  for (const key of [
    'days',
    'mcc_codes',
    'merchants',
    'categories',
    'transaction_types',
  ]) {
    assert.match(
      sql,
      new RegExp(`jsonb_typeof\\(exclusions->'${key}'\\)\\s*=\\s*'array'`, 'i'),
    );
  }
  assert.match(sql, /jsonb_typeof\(exclusions->'additional'\)\s*=\s*'object'/i);
  assert.match(
    sql,
    /jsonb_typeof\(exclusions->'additional'->'source_terms'\)\s*=\s*'array'/i,
  );
  assert.match(sql, /jsonb_typeof\(result_summary\)\s*=\s*'object'/i);
  assert.match(
    sql,
    /CREATE OR REPLACE FUNCTION public\.normalize_benefit_exclusions_shape\(\)[\s\S]*jsonb_typeof\(NEW\.exclusions\)\s*=\s*'array'[\s\S]*'source_terms'/i,
  );
  assert.match(
    sql,
    /CREATE TRIGGER normalize_benefit_exclusions_shape[\s\S]*BEFORE INSERT OR UPDATE OF exclusions[\s\S]*public\.benefits/i,
  );
});

test('classifies legacy staging before enforcing request-specific contracts', async () => {
  const sql = await lifecycleMigration();
  const classification = sql.search(
    /UPDATE public\.card_benefits_staging[\s\S]*SET request_type\s*=\s*CASE/i,
  );
  const officialConstraint = sql.search(
    /ADD CONSTRAINT card_benefits_staging_official_shape_check/i,
  );
  const catalogConstraint = sql.search(
    /ADD CONSTRAINT card_benefits_staging_catalog_entry_shape_check/i,
  );
  assert.ok(classification >= 0);
  assert.ok(classification < officialConstraint);
  assert.ok(classification < catalogConstraint);

  assert.match(
    sql,
    /request_type\s*<>\s*'official_benefit_enrichment'[\s\S]*card_id IS NOT NULL[\s\S]*nullif\(trim\(source_url\)[\s\S]*nullif\(trim\(parser_version\)[\s\S]*nullif\(trim\(source_url_hash\)[\s\S]*nullif\(trim\(content_hash\)[\s\S]*jsonb_typeof\(source_evidence\)\s*=\s*'array'[\s\S]*jsonb_array_length\(source_evidence\)\s*>\s*0/i,
  );
  assert.match(
    sql,
    /request_type\s*<>\s*'catalog_entry'[\s\S]*requested_by IS NOT NULL[\s\S]*jsonb_typeof\(extracted_data\)\s*=\s*'object'/i,
  );
  for (const constraint of [
    'card_benefits_staging_official_shape_check',
    'card_benefits_staging_catalog_entry_shape_check',
  ]) {
    assert.match(
      sql,
      new RegExp(`ADD CONSTRAINT ${constraint}[\\s\\S]*NOT VALID`, 'i'),
    );
    assert.match(
      sql,
      new RegExp(`VALIDATE CONSTRAINT ${constraint}`, 'i'),
    );
  }
});

test('defines an explicit security-invoker active view with UTC lifecycle filters', async () => {
  const sql = await lifecycleMigration();
  const view = sql.match(
    /CREATE OR REPLACE VIEW public\.active_card_benefits[\s\S]*?;/i,
  )?.[0];

  assert.ok(view, 'active_card_benefits view is required');
  assert.match(view, /WITH\s*\(\s*security_invoker\s*=\s*true\s*\)/i);
  assert.doesNotMatch(view, /SELECT\s+(?:\w+\.)?\*/i);
  for (const column of [
    'mapping_id',
    'card_id',
    'benefit_id',
    'display_priority',
    'is_primary',
    'category_codes',
    'title',
    'description',
    'benefit_category',
    'benefit_type',
    'value_config',
    'partners',
    'exclusions',
    'regions',
    'source_url',
    'valid_from',
    'valid_until',
  ]) assert.match(view, new RegExp(`\\b${column}\\b`, 'i'));
  assert.match(view, /mapping\.retired_at IS NULL\s+OR mapping\.retired_at\s*>\s*now\(\)/i);
  assert.match(view, /benefit\.is_active\s*=\s*true/i);
  assert.match(
    view,
    /timezone\(\s*'UTC'\s*,\s*statement_timestamp\(\)\s*\)::date AS utc_date/i,
  );
  assert.match(view, /benefit\.valid_from IS NULL\s+OR benefit\.valid_from\s*<=\s*database_clock\.utc_date/i);
  assert.match(view, /benefit\.valid_until IS NULL\s+OR benefit\.valid_until\s*>=\s*database_clock\.utc_date/i);
});

test('adds authenticated read policies before narrowing client table and RPC grants', async () => {
  const sql = await lifecycleMigration();

  for (const table of [
    'card_catalog',
    'benefit_categories',
    'benefits',
    'card_benefit_mapping',
  ]) {
    assert.match(sql, new RegExp(`ALTER TABLE public\\.${table} ENABLE ROW LEVEL SECURITY`, 'i'));
    assert.match(
      sql,
      new RegExp(`CREATE POLICY[^;]+ON public\\.${table}[^;]+FOR SELECT[^;]+TO authenticated[^;]+USING \\(true\\)`, 'i'),
    );
    assert.match(
      sql,
      new RegExp(`REVOKE INSERT, UPDATE, DELETE ON (?:TABLE )?public\\.${table} FROM (?:PUBLIC, )?anon, authenticated`, 'i'),
    );
  }
  assert.match(sql, /REVOKE ALL ON (?:TABLE )?public\.card_benefits FROM PUBLIC, anon, authenticated/i);
  assert.match(sql, /REVOKE ALL ON (?:TABLE )?public\.active_card_benefits FROM PUBLIC, anon/i);
  assert.match(sql, /GRANT SELECT ON (?:TABLE )?public\.active_card_benefits TO authenticated, service_role/i);

  assert.match(sql, /create_credit_card/i);
  assert.match(sql, /create_or_get_card_catalog/i);
  assert.match(sql, /REVOKE ALL ON FUNCTION[\s\S]*FROM PUBLIC, anon, authenticated/i);

  for (const signature of [
    'initialize_card_benefit_enrichment_pilot\\(jsonb, text\\)',
    'claim_card_catalog_enrichment_jobs\\(integer, integer, text, text\\)',
    'stage_card_benefit_enrichment\\(',
    'finalize_card_catalog_enrichment_job\\(',
    'approve_card_benefit_enrichment\\(uuid, uuid, jsonb\\)',
    'approve_catalog_entry_request\\(uuid, uuid\\)',
    'reject_catalog_entry_request\\(uuid, uuid\\)',
  ]) {
    assert.match(
      sql,
      new RegExp(`GRANT EXECUTE ON FUNCTION public\\.${signature}[\\s\\S]*TO service_role`, 'i'),
    );
  }
  assert.doesNotMatch(sql, /auth\.role\s*\(/i);
});
