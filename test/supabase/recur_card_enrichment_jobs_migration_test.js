import test from 'node:test';
import assert from 'node:assert/strict';
import { readdir, readFile } from 'node:fs/promises';

const migrationsRoot = new URL('../../supabase/migrations/', import.meta.url);

async function migrationSql() {
  const names = (await readdir(migrationsRoot)).filter((name) =>
    name.endsWith('_recur_card_enrichment_jobs.sql')
  );
  assert.equal(names.length, 1, 'exactly one CLI-named recurrence migration is required');
  assert.match(names[0], /^\d{14}_recur_card_enrichment_jobs\.sql$/);
  return readFile(new URL(names[0], migrationsRoot), 'utf8');
}

function functionBody(sql, name) {
  const start = sql.search(new RegExp(`CREATE (?:OR REPLACE )?FUNCTION public\\.${name}\\s*\\(`, 'i'));
  assert.notEqual(start, -1, `${name} is required`);
  const end = sql.indexOf('$$;', start);
  assert.notEqual(end, -1, `${name} must have a complete body`);
  return sql.slice(start, end + 3);
}

test('due recurrence reuses only unlocked terminal benefits-v6 jobs in a bounded deterministic batch', async () => {
  const sql = await migrationSql();
  const requeue = functionBody(sql, 'requeue_due_card_catalog_enrichment_jobs');

  assert.match(requeue, /SECURITY INVOKER/i);
  assert.match(requeue, /SET search_path\s*=\s*public, pg_temp/i);
  assert.doesNotMatch(requeue, /auth\.role\(\)|service_role_required/i);
  assert.match(requeue, /selected_parser\s*<>\s*'benefits-v6'/i);
  assert.match(requeue, /_limit\s*<\s*1[\s\S]*_limit\s*>\s*200/i);
  assert.match(requeue, /next_run_at\s*<=\s*_now/i);
  assert.match(requeue, /next_run_at\s+IS\s+NULL/i);
  assert.match(requeue, /next_retry_at IS NULL/i);
  assert.match(requeue, /status IN \('completed', 'staged', 'quarantined', 'review_required', 'failed'\)/i);
  assert.match(requeue, /status\s*<>\s*'processing'/i);
  assert.match(requeue, /lease_expires_at IS NULL\s+OR job\.lease_expires_at\s*<=\s*_now/i);
  assert.match(
    requeue,
    /ORDER BY CASE WHEN decision\.action = 'queue' THEN 0 ELSE 1 END,[\s\S]*job\.next_run_at,[\s\S]*lower\(trim\(job\.issuer\)\), job\.id/i,
  );
  assert.match(requeue, /FOR UPDATE(?: OF job)? SKIP LOCKED/i);
  assert.match(requeue, /job\.run_mode\s*=\s*'scheduled'/i);
  assert.match(requeue, /card_enrichment_job_has_pending_staging/i);
  assert.match(requeue, /card_has_unresolved_catalog_identity\(\s*job\.card_id,\s*job\.canonical_url\s*\)/i);
  assert.match(requeue, /card\.is_discontinued[\s\S]*user_cards[\s\S]*is_active\s*=\s*true/i);
  assert.match(requeue, /status\s*=\s*CASE WHEN selected\.action = 'queue' THEN 'queued'/i);
  assert.match(requeue, /attempt_count\s*=\s*CASE WHEN selected\.action = 'queue' THEN 0/i);
  assert.match(requeue, /next_retry_at\s*=\s*CASE WHEN selected\.action = 'queue' THEN NULL/i);
  assert.match(requeue, /next_run_at\s*=\s*NULL/i);
  assert.match(requeue, /lease_expires_at\s*=\s*CASE WHEN selected\.action = 'queue' THEN NULL/i);
  assert.match(requeue, /lease_token\s*=\s*CASE WHEN selected\.action = 'queue' THEN NULL/i);
  assert.match(requeue, /failure_category\s*=\s*CASE WHEN selected\.action = 'queue' THEN NULL/i);
  assert.doesNotMatch(requeue, /staging_id\s*=|job_key\s*=|canonical_url\s*=|final_url_hash\s*=|result_summary\s*=/i);
  assert.equal(
    (requeue.match(/UPDATE public\.card_catalog_enrichment_jobs/gi) ?? []).length,
    1,
    'all recurrence mutation must share one bounded locked update',
  );
  assert.match(sql, /REVOKE ALL ON FUNCTION public\.requeue_due_card_catalog_enrichment_jobs\(text, integer, timestamptz\)\s+FROM PUBLIC, anon, authenticated/i);
  assert.match(sql, /GRANT EXECUTE ON FUNCTION public\.requeue_due_card_catalog_enrichment_jobs\(text, integer, timestamptz\)\s+TO service_role/i);
});

test('terminal scheduling and TypeScript use the same explicit UTF-8 byte-sum jitter algorithm', async () => {
  const sql = await migrationSql();
  const jitter = functionBody(sql, 'card_enrichment_jitter_days');
  const nextRun = functionBody(sql, 'next_card_enrichment_observation_at');
  const trigger = functionBody(sql, 'schedule_terminal_card_enrichment_observation');

  assert.match(jitter, /convert_to\(lower\(trim\(_card_id::text\)\), 'UTF8'\)/i);
  assert.match(jitter, /get_byte\(identifier_bytes, byte_index\)/i);
  assert.match(jitter, /mod\(byte_total, \(2 \* _radius\) \+ 1\)(?:::integer)? - _radius/i);
  assert.match(nextRun, /'success', 'not_modified'[\s\S]*interval '30 days'[\s\S]*3/i);
  assert.match(nextRun, /'blocked', 'missing', 'failed'[\s\S]*interval '7 days'[\s\S]*1/i);
  assert.match(nextRun, /canonical_card_enrichment_timestamp\(_completed_at\)/i);
  assert.match(nextRun, /extract\(epoch from[\s\S]*86400/i);
  assert.match(nextRun, /_is_discontinued[\s\S]*NOT _has_active_cardholder[\s\S]*RETURN NULL/i);
  assert.match(trigger, /parser_version\s*=\s*'benefits-v6'/i);
  assert.match(trigger, /NEW\.run_mode\s*=\s*'scheduled'/i);
  assert.match(trigger, /NEW\.status IN \('completed', 'staged', 'quarantined', 'review_required', 'failed'\)/i);
  assert.match(trigger, /NEW\.next_retry_at IS NULL/i);
  assert.match(trigger, /next_card_enrichment_observation_at/i);
  assert.match(sql, /CREATE TRIGGER schedule_terminal_card_enrichment_observation[\s\S]*ON public\.card_catalog_enrichment_jobs/i);
  assert.match(sql, /card_enrichment_requeue_action[\s\S]*'pilot'[\s\S]*'clear'[\s\S]*'scheduled'[\s\S]*'queue'/i);
  assert.match(sql, /UPDATE public\.card_catalog_enrichment_jobs AS legacy_terminal[\s\S]*SET status = legacy_terminal\.status[\s\S]*parser_version = 'benefits-v6'[\s\S]*next_run_at IS NULL/i);
  assert.doesNotMatch(sql, /legacy_terminal\.parser_version\s*(?:<>|!=)\s*'catalog-v1'/i);
});

test('finalization preserves staging on 304, separates retry from recurrence, and retains newest 24 sanitized observations', async () => {
  const sql = await migrationSql();
  const finalize = functionBody(sql, 'finalize_card_catalog_enrichment_job');
  const normalize = functionBody(sql, 'normalize_card_enrichment_observation_history');
  const sanitizeSummary = functionBody(sql, 'sanitize_card_enrichment_result_summary');
  const sanitizeAttempt = functionBody(sql, 'sanitize_card_enrichment_source_attempt');
  const sanitizeObservation = functionBody(sql, 'sanitize_card_enrichment_observation');

  assert.match(finalize, /_status\s*=\s*'completed'\s+AND _staging_id IS NOT NULL/i);
  assert.match(finalize, /SELECT job\.\*[\s\S]*FOR UPDATE/i);
  assert.match(finalize, /staging_id\s*=\s*coalesce\(_staging_id, job_row\.staging_id\)/i);
  assert.match(finalize, /content_hash\s*=\s*coalesce\(_content_hash, job_row\.content_hash\)/i);
  assert.match(finalize, /existing_observation_history\s*:=[\s\S]*job_row\.result_summary\s*->\s*'observations'/i);
  assert.match(finalize, /normalize_card_enrichment_observation_history\([\s\S]*existing_observation_history[\s\S]*_result_summary\s*->\s*'observation'/i);
  assert.match(
    finalize,
    /job_row\.result_summary\s*->\s*'observation'[\s\S]*normalize_card_enrichment_observation_history/i,
  );
  assert.match(finalize, /next_retry_at\s*=\s*_next_retry_at/i);
  assert.match(finalize, /next_run_at\s*=\s*NULL/i);
  assert.match(finalize, /sanitize_card_enrichment_result_summary\(_result_summary/i);
  assert.doesNotMatch(finalize, /safe_summary\s*:=\s*\(_result_summary\s*-/i);
  assert.match(normalize, /observed_at/i);
  assert.match(normalize, /source_manifest_hash/i);
  assert.match(normalize, /canonical_benefit_hash/i);
  assert.match(normalize, /ORDER BY[\s\S]*DESC/i);
  assert.match(normalize, /LIMIT 24/i);
  assert.match(normalize, /DISTINCT ON/i);
  assert.match(sanitizeAttempt, /bounded_card_enrichment_timestamp\(\s*_attempt->>'attemptedAt',\s*_now\s*\)/i);
  assert.match(sanitizeAttempt, /bounded_card_enrichment_timestamp\(\s*history->>'attemptedAt',\s*_now\s*\)/i);
  assert.match(sanitizeObservation, /bounded_card_enrichment_timestamp\(\s*_observation->>'observed_at',\s*_now\s*\)/i);
  assert.match(sanitizeSummary, /allowed_key/i);
  assert.match(sanitizeSummary, /jsonb_typeof\(allowed_value\)\s*=\s*'boolean'/i);
  assert.match(sanitizeSummary, /jsonb_typeof\(allowed_value\)\s*=\s*'number'/i);
  assert.match(sanitizeSummary, /source_manifest_hash[\s\S]*\^\[0-9a-f\]\{64\}\$/i);
  assert.doesNotMatch(sanitizeSummary, /'body'|'html'|'raw_page'|'response_body'/i);
  assert.match(sql, /DO \$recurrence_policy_assertions\$[\s\S]*DO \$recurrence_history_assertions\$/i);
  assert.match(sql, /REVOKE ALL ON FUNCTION public\.finalize_card_catalog_enrichment_job[\s\S]*TO service_role/i);
});

test('claiming is one-card with a 300-second lease and admin completion shares the terminal trigger', async () => {
  const sql = await migrationSql();
  const claim = functionBody(sql, 'claim_card_catalog_enrichment_jobs');
  const trigger = functionBody(sql, 'schedule_terminal_card_enrichment_observation');

  assert.match(claim, /maximum_jobs\s*:=\s*1/i);
  assert.match(claim, /lease_seconds\s*:=\s*300/i);
  assert.match(claim, /FOR UPDATE(?: OF job)? SKIP LOCKED/i);
  assert.match(claim, /job\.parser_version\s*=\s*selected_parser/g);
  assert.match(claim, /next_run_at\s*=\s*NULL/i);
  assert.match(claim, /card_enrichment_job_has_pending_staging/i);
  assert.match(
    claim,
    /SET status = CASE[\s\S]*card_enrichment_job_has_pending_staging[\s\S]*THEN 'staged'/i,
  );
  assert.match(
    claim,
    /next_retry_at = CASE[\s\S]*card_enrichment_job_has_pending_staging[\s\S]*THEN NULL/i,
  );
  assert.match(
    claim,
    /'retry_scheduled'[\s\S]*card_enrichment_job_has_pending_staging[\s\S]*THEN false/i,
  );
  assert.match(claim, /card_has_unresolved_catalog_identity\(job\.card_id, job\.canonical_url\)/i);
  assert.match(
    trigger,
    /card_enrichment_job_has_pending_staging[\s\S]*NEW\.next_run_at := NULL[\s\S]*RETURN NEW/i,
  );
  assert.doesNotMatch(claim, /auth\.role\(\)|service_role_required/i);
  assert.match(sql, /BEFORE INSERT OR UPDATE[\s\S]*schedule_terminal_card_enrichment_observation/i);
  assert.doesNotMatch(sql, /CREATE OR REPLACE FUNCTION public\.approve_card_benefit_enrichment/i);
});

test('recurrence transitions and pending review are explicit, bounded, and index-supported', async () => {
  const sql = await migrationSql();
  const action = functionBody(sql, 'card_enrichment_requeue_action');
  const requeue = functionBody(sql, 'requeue_due_card_catalog_enrichment_jobs');

  assert.match(action, /_run_mode\s*<>\s*'scheduled'[\s\S]*RETURN[\s\S]*'clear'/i);
  assert.match(action, /_has_pending_staging[\s\S]*RETURN[\s\S]*'clear'/i);
  assert.match(action, /NOT _eligible[\s\S]*RETURN[\s\S]*'clear'/i);
  assert.match(action, /_next_run_at IS NULL OR _next_run_at <= _now[\s\S]*RETURN 'queue'/i);
  assert.match(requeue, /LIMIT _limit[\s\S]*FOR UPDATE(?: OF job)? SKIP LOCKED/i);
  assert.match(requeue, /status\s*=\s*CASE WHEN selected\.action = 'queue' THEN 'queued' ELSE job\.status END/i);
  assert.match(requeue, /WHERE updated\.action = 'queue'/i);
  assert.match(sql, /CREATE INDEX IF NOT EXISTS idx_card_catalog_enrichment_jobs_recurrence_v6/i);
  assert.match(sql, /DO \$recurrence_transition_assertions\$[\s\S]*_limit=1/i);
});

test('canonical recurrence timestamps and history normalization have apply-time parity assertions', async () => {
  const sql = await migrationSql();
  const canonical = functionBody(sql, 'canonical_card_enrichment_timestamp');
  const normalize = functionBody(sql, 'normalize_card_enrichment_observation_history');

  assert.match(canonical, /YYYY-MM-DD"T"HH24:MI:SS\.MS"Z"/i);
  assert.match(canonical, /RETURN NULL/i);
  assert.match(normalize, /source_manifest_hash[\s\S]*canonical_benefit_hash/i);
  assert.match(sql, /2026-02-30T00:00:00\.000Z[\s\S]*2026-02-20T05:30:00\.000\+05:30/i);
  assert.match(sql, /America\/New_York[\s\S]*2026-04-09T07:30:00\+00:00/i);
  assert.match(sql, /legacy-root[\s\S]*legacy-history/i);
});
