import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const repoRoot = new URL('../../', import.meta.url);
const migration = new URL(
  'supabase/migrations/20260817040000_automated_benefit_enrichment.sql',
  repoRoot,
);
const ownershipRepairMigration = new URL(
  'supabase/migrations/20260817071435_repair_legacy_catalog_enrichment_ownership.sql',
  repoRoot,
);

async function migrationSql() {
  return readFile(migration, 'utf8');
}

function functionBody(sql, name) {
  const start = sql.search(new RegExp(`CREATE OR REPLACE FUNCTION public\\.${name}\\s*\\(`, 'i'));
  assert.notEqual(start, -1, `${name} RPC is required`);
  const end = sql.indexOf('$$;', start);
  assert.notEqual(end, -1, `${name} RPC must have a complete function body`);
  return sql.slice(start, end + 3);
}

test('migration preserves user discovery uniqueness while allowing issuer-crawl jobs', async () => {
  const sql = await migrationSql();

  assert.match(sql, /ALTER TABLE public\.card_discovery_jobs\s+ALTER COLUMN user_id DROP NOT NULL/i);
  assert.match(sql, /ADD COLUMN discovery_source text NOT NULL DEFAULT 'statement'\s+CHECK \(discovery_source IN \('statement', 'issuer_crawl'\)\)/i);
  assert.match(sql, /CREATE UNIQUE INDEX IF NOT EXISTS idx_card_discovery_jobs_user_dedupe_key\s+ON public\.card_discovery_jobs\s*\(user_id, dedupe_key\)\s+WHERE user_id IS NOT NULL/i);
  assert.match(sql, /CREATE UNIQUE INDEX IF NOT EXISTS idx_card_discovery_jobs_service_dedupe_key\s+ON public\.card_discovery_jobs\s*\(discovery_source, dedupe_key\)\s+WHERE user_id IS NULL/i);
});

test('migration adds leaseable enrichment queue metadata without losing compatible rows', async () => {
  const sql = await migrationSql();
  const queueIdentity = functionBody(sql, 'set_card_catalog_enrichment_job_key');

  for (const column of [
    /parser_version text NOT NULL DEFAULT 'benefits-v1'/i,
    /lease_expires_at timestamptz/i,
    /lease_token uuid/i,
    /staging_id uuid REFERENCES public\.card_benefits_staging\(id\)/i,
    /run_mode text NOT NULL DEFAULT 'scheduled'\s+CHECK \(run_mode IN \('pilot', 'scheduled', 'manual'\)\)/i,
    /job_key text/i,
    /result_summary jsonb NOT NULL DEFAULT '\{\}'::jsonb/i,
  ]) {
    assert.match(sql, column);
  }
  assert.match(sql, /status IN \('queued', 'processing', 'completed', 'review_required', 'failed', 'staged', 'quarantined'\)/i);
  assert.match(sql, /ALTER COLUMN content_hash DROP NOT NULL/i);
  assert.match(sql, /UPDATE public\.card_catalog_enrichment_jobs[\s\S]*SET job_key[\s\S]*legacy:/i);
  assert.doesNotMatch(sql, /ALTER COLUMN job_key SET NOT NULL/i);
  assert.match(sql, /ADD CONSTRAINT card_catalog_enrichment_jobs_job_key_key\s+UNIQUE \(job_key\)/i);
  assert.match(sql, /CREATE TRIGGER set_card_catalog_enrichment_job_key[\s\S]*set_card_catalog_enrichment_job_key\(\)/i);
  assert.match(queueIdentity, /NEW\.job_key\s*:=\s*NEW\.card_id::text[\s\S]*NEW\.final_url_hash[\s\S]*NEW\.parser_version/i);
  assert.doesNotMatch(queueIdentity, /IF\s+NEW\.job_key/i);
});

test('claim RPC leases no more than five jobs from one issuer with service-only access', async () => {
  const sql = await migrationSql();
  const claim = functionBody(sql, 'claim_card_catalog_enrichment_jobs');

  assert.match(claim, /claim_card_catalog_enrichment_jobs\s*\(\s*_max_jobs integer\s*,\s*_lease_seconds integer\s*,\s*_run_mode text/i);
  assert.match(claim, /SECURITY INVOKER/i);
  assert.match(claim, /auth\.role\(\).*service_role/i);
  assert.match(claim, /(?:job\.)?lease_expires_at IS NULL\s+OR (?:job\.)?lease_expires_at\s*<=\s*now\(\)/i);
  assert.match(claim, /lease_token\s*=\s*NULL/i);
  assert.match(claim, /lease_token\s*=\s*gen_random_uuid\(\)/i);
  assert.match(claim, /_run_mode IS NULL\s+OR _run_mode NOT IN \('pilot', 'scheduled', 'manual'\)/i);
  assert.match(claim, /pg_advisory_xact_lock\s*\(\s*hashtextextended\s*\(\s*'card_catalog_enrichment_claim'/i);
  assert.match(claim, /pg_advisory_xact_lock[\s\S]*SELECT lower\(trim\(job\.issuer\)\)[\s\S]*INTO selected_issuer/i);
  assert.match(claim, /SELECT[\s\S]*issuer[\s\S]*INTO selected_issuer/i);
  assert.match(claim, /SELECT lower\(trim\(job\.issuer\)\)[\s\S]*INTO selected_issuer/i);
  assert.match(claim, /lower\(trim\(leased\.issuer\)\)\s*=\s*lower\(trim\(job\.issuer\)\)/i);
  assert.match(claim, /lower\(trim\(job\.issuer\)\)\s*=\s*selected_issuer/i);
  assert.equal(
    [...claim.matchAll(/lower\(trim\(job\.parser_version\)\)\s*<>\s*'catalog-v1'/gi)].length,
    3,
    'lease recovery, issuer selection, and row claim must reserve catalog-v1 in every run mode',
  );
  assert.match(claim, /FOR UPDATE SKIP LOCKED/i);
  assert.match(claim, /LEAST\s*\(\s*GREATEST\s*\([^)]*\)\s*,\s*5\s*\)/i);
  assert.match(sql, /REVOKE ALL ON FUNCTION public\.claim_card_catalog_enrichment_jobs\(integer, integer, text\)\s+FROM PUBLIC, anon, authenticated/i);
  assert.match(sql, /GRANT EXECUTE ON FUNCTION public\.claim_card_catalog_enrichment_jobs\(integer, integer, text\)\s+TO service_role/i);
});

test('migration atomically initializes exactly five validated pilot jobs', async () => {
  const sql = await migrationSql();
  const pilot = functionBody(sql, 'initialize_card_benefit_enrichment_pilot');

  assert.match(pilot, /jsonb_array_length\(_candidates\)\s*<>\s*5/i);
  assert.match(pilot, /count\(DISTINCT profile\)[\s\S]*distinct_profile_count\s*<>\s*5/i);
  assert.match(pilot, /count\(DISTINCT lower\(trim\(bank\)\)\)[\s\S]*<\s*3/i);
  assert.match(pilot, /is_discontinued\s*=\s*false/i);
  assert.match(pilot, /lower\(trim\(card\.card_type\)\)\s*=\s*'credit'/i);
  assert.match(pilot, /lower\(trim\(_parser_version\)\)\s*=\s*'catalog-v1'[\s\S]*reserved_parser_version/i);
  assert.match(pilot, /INSERT INTO public\.card_catalog_enrichment_jobs[\s\S]*'pilot'/i);
  assert.match(pilot, /ON CONFLICT \(job_key\) DO NOTHING/i);
  assert.match(pilot, /GET DIAGNOSTICS[\s\S]*ROW_COUNT/i);
  assert.match(pilot, /inserted_count\s*<>\s*5[\s\S]*pilot_candidate_conflict/i);
  assert.doesNotMatch(pilot, /ON CONFLICT \(job_key\) DO UPDATE/i);
  assert.doesNotMatch(pilot, /SET\s+run_mode\s*=\s*'pilot'/i);
  assert.match(pilot, /pilot_state_incomplete/i);
  assert.match(sql, /GRANT EXECUTE ON FUNCTION public\.initialize_card_benefit_enrichment_pilot\(jsonb, text\)\s+TO service_role/i);
});

test('migration fences staging and finalization with a database-issued lease token', async () => {
  const sql = await migrationSql();
  const stage = functionBody(sql, 'stage_card_benefit_enrichment');
  const finalize = functionBody(sql, 'finalize_card_catalog_enrichment_job');

  for (const column of [
    /request_type text/i,
    /parser_version text/i,
    /source_url_hash text/i,
    /content_hash text/i,
  ]) assert.match(sql, column);
  assert.match(sql, /CREATE UNIQUE INDEX[\s\S]*card_benefits_staging_official_identity[\s\S]*card_id\s*,\s*source_url_hash\s*,\s*parser_version\s*,\s*content_hash[\s\S]*request_type\s*=\s*'official_benefit_enrichment'/i);
  assert.match(stage, /candidate\.id\s*=\s*_job_id[\s\S]*candidate\.status\s*=\s*'processing'[\s\S]*candidate\.lease_token\s*=\s*_lease_token/i);
  assert.match(stage, /FOR UPDATE/i);
  assert.match(stage, /extensions\.digest[\s\S]*_source_url_hash/i);
  assert.match(stage, /ON CONFLICT \(card_id, source_url_hash, parser_version, content_hash\)[\s\S]*request_type\s*=\s*'official_benefit_enrichment'/i);
  assert.match(stage, /status IN \('pending', 'approved'\)/i);
  assert.match(stage, /source_evidence IS NOT NULL/i);
  assert.match(stage, /jsonb_array_length\(_source_evidence\)\s*>\s*0/i);
  assert.match(finalize, /_status\s*=\s*'staged'[\s\S]*card_benefits_staging/i);
  assert.match(finalize, /WHERE id\s*=\s*_job_id[\s\S]*status\s*=\s*'processing'[\s\S]*lease_token\s*=\s*_lease_token/i);
  assert.match(finalize, /GET DIAGNOSTICS[\s\S]*ROW_COUNT/i);
  assert.match(finalize, /affected_rows\s*<>\s*1/i);
  assert.match(sql, /GRANT EXECUTE ON FUNCTION public\.stage_card_benefit_enrichment/i);
  assert.match(sql, /GRANT EXECUTE ON FUNCTION public\.finalize_card_catalog_enrichment_job/i);
});

test('approval RPC applies only reviewed additions or edits and retains existing data', async () => {
  const sql = await migrationSql();
  const approval = functionBody(sql, 'approve_card_benefit_enrichment');

  assert.match(approval, /approve_card_benefit_enrichment\s*\(\s*_staging_id uuid\s*,\s*_reviewed_by uuid\s*,\s*_decisions jsonb/i);
  assert.match(approval, /SECURITY INVOKER/i);
  assert.match(approval, /auth\.role\(\).*service_role/i);
  assert.match(approval, /'approve', 'edit', 'reject', 'keep_existing'/i);
  assert.match(approval, /jsonb_typeof\(decision\)\s*<>\s*'object'\s+OR decision_action IS NULL\s+OR decision_action NOT IN/i);
  assert.match(approval, /INSERT INTO public\.benefits[\s\S]*ON CONFLICT \(dedupe_key\) DO UPDATE/i);
  assert.match(approval, /SELECT category\.category_code[\s\S]*FROM public\.benefit_categories AS category[\s\S]*lower\(category\.category_code\)/i);
  assert.match(approval, /category_codes\s*\)[\s\S]*ARRAY\[canonical_category\]/i);
  assert.match(approval, /INSERT INTO public\.card_benefit_mapping[\s\S]*ON CONFLICT \(card_id, benefit_id\) DO UPDATE/i);
  assert.match(approval, /possible_removal|removal/i);
  assert.match(approval, /benefit_decisions\s*=\s*_decisions/i);
  assert.match(approval, /reviewed_by\s*=\s*_reviewed_by/i);
  assert.match(approval, /reviewed_at\s*=\s*now\(\)/i);
  assert.doesNotMatch(approval, /DELETE\s+FROM\s+public\.benefits/i);
  assert.match(sql, /REVOKE ALL ON FUNCTION public\.approve_card_benefit_enrichment\(uuid, uuid, jsonb\)\s+FROM PUBLIC, anon, authenticated/i);
  assert.match(sql, /GRANT EXECUTE ON FUNCTION public\.approve_card_benefit_enrichment\(uuid, uuid, jsonb\)\s+TO service_role/i);
});

test('forward migration conservatively repairs only identifiable legacy catalog jobs', async () => {
  const sql = await readFile(ownershipRepairMigration, 'utf8');

  assert.match(sql, /UPDATE public\.card_catalog_enrichment_jobs AS legacy/i);
  assert.match(sql, /SET parser_version\s*=\s*'catalog-v1'[\s\S]*run_mode\s*=\s*'manual'/i);
  assert.match(sql, /legacy\.parser_version\s*=\s*'benefits-v1'/i);
  assert.match(sql, /legacy\.run_mode\s*=\s*'scheduled'/i);
  assert.match(sql, /legacy\.content_hash IS NOT NULL/i);
  assert.match(sql, /legacy\.staging_id IS NULL/i);
  assert.match(sql, /legacy\.result_summary\s*=\s*'\{\}'::jsonb/i);
  assert.match(sql, /legacy\.status IN \('completed', 'review_required', 'failed'\)/i);
  assert.match(sql, /row_number\(\) OVER \([\s\S]*PARTITION BY legacy\.card_id, legacy\.final_url_hash/i);
  assert.match(sql, /repairable\.identity_rank\s*=\s*1/i);
  assert.match(sql, /NOT EXISTS[\s\S]*parser_version\s*=\s*'catalog-v1'/i);
  assert.doesNotMatch(sql, /WHERE\s+parser_version\s*=\s*'benefits-v1'\s*;/i);
});
