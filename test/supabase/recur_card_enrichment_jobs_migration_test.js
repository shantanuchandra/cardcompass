import test from 'node:test';
import assert from 'node:assert/strict';
import { readdir, readFile } from 'node:fs/promises';

const migrationsRoot = new URL('../../supabase/migrations/', import.meta.url);
const stagingMigration = new URL(
  '../../supabase/migrations/20260819122252_supersede_stale_benefit_staging.sql',
  import.meta.url,
);
const reviewMigration = new URL(
  '../../supabase/migrations/20260819163046_review_card_benefit_enrichment_v2.sql',
  import.meta.url,
);

async function migrationSql() {
  const names = (await readdir(migrationsRoot)).filter((name) => name.endsWith('_recur_card_enrichment_jobs.sql'));
  assert.equal(
    names.length,
    1,
    'exactly one CLI-named recurrence migration is required',
  );
  assert.match(names[0], /^\d{14}_recur_card_enrichment_jobs\.sql$/);
  return readFile(new URL(names[0], migrationsRoot), 'utf8');
}

function functionBody(sql, name) {
  const start = sql.search(
    new RegExp(`CREATE (?:OR REPLACE )?FUNCTION public\\.${name}\\s*\\(`, 'i'),
  );
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
  assert.match(
    requeue,
    /status IN \('completed', 'staged', 'quarantined', 'review_required', 'failed'\)/i,
  );
  assert.match(requeue, /status\s*<>\s*'processing'/i);
  assert.match(
    requeue,
    /lease_expires_at IS NULL\s+OR job\.lease_expires_at\s*<=\s*_now/i,
  );
  assert.match(
    requeue,
    /ORDER BY CASE WHEN decision\.action = 'queue' THEN 0 ELSE 1 END,[\s\S]*job\.next_run_at,[\s\S]*lower\(trim\(job\.issuer\)\), job\.id/i,
  );
  assert.match(requeue, /FOR UPDATE(?: OF job)? SKIP LOCKED/i);
  assert.match(requeue, /job\.run_mode\s*=\s*'scheduled'/i);
  assert.match(requeue, /card_enrichment_job_has_pending_staging/i);
  assert.match(
    requeue,
    /card_has_unresolved_catalog_identity\(\s*job\.card_id,\s*job\.canonical_url\s*\)/i,
  );
  assert.match(
    requeue,
    /card\.is_discontinued[\s\S]*user_cards[\s\S]*is_active\s*=\s*true/i,
  );
  assert.match(
    requeue,
    /status\s*=\s*CASE WHEN selected\.action = 'queue' THEN 'queued'/i,
  );
  assert.match(
    requeue,
    /attempt_count\s*=\s*CASE WHEN selected\.action = 'queue' THEN 0/i,
  );
  assert.match(
    requeue,
    /next_retry_at\s*=\s*CASE WHEN selected\.action = 'queue' THEN NULL/i,
  );
  assert.match(requeue, /next_run_at\s*=\s*NULL/i);
  assert.match(
    requeue,
    /lease_expires_at\s*=\s*CASE WHEN selected\.action = 'queue' THEN NULL/i,
  );
  assert.match(
    requeue,
    /lease_token\s*=\s*CASE WHEN selected\.action = 'queue' THEN NULL/i,
  );
  assert.match(
    requeue,
    /failure_category\s*=\s*CASE WHEN selected\.action = 'queue' THEN NULL/i,
  );
  assert.doesNotMatch(
    requeue,
    /staging_id\s*=|job_key\s*=|canonical_url\s*=|final_url_hash\s*=|result_summary\s*=/i,
  );
  assert.equal(
    (requeue.match(/UPDATE public\.card_catalog_enrichment_jobs/gi) ?? [])
      .length,
    1,
    'all recurrence mutation must share one bounded locked update',
  );
  assert.match(
    sql,
    /REVOKE ALL ON FUNCTION public\.requeue_due_card_catalog_enrichment_jobs\(text, integer, timestamptz\)\s+FROM PUBLIC, anon, authenticated/i,
  );
  assert.match(
    sql,
    /GRANT EXECUTE ON FUNCTION public\.requeue_due_card_catalog_enrichment_jobs\(text, integer, timestamptz\)\s+TO service_role/i,
  );
});

test('terminal scheduling and TypeScript use the same explicit UTF-8 byte-sum jitter algorithm', async () => {
  const sql = await migrationSql();
  const jitter = functionBody(sql, 'card_enrichment_jitter_days');
  const nextRun = functionBody(sql, 'next_card_enrichment_observation_at');
  const trigger = functionBody(
    sql,
    'schedule_terminal_card_enrichment_observation',
  );

  assert.match(
    jitter,
    /convert_to\(lower\(trim\(_card_id::text\)\), 'UTF8'\)/i,
  );
  assert.match(jitter, /get_byte\(identifier_bytes, byte_index\)/i);
  assert.match(
    jitter,
    /mod\(byte_total, \(2 \* _radius\) \+ 1\)(?:::integer)? - _radius/i,
  );
  assert.match(
    nextRun,
    /'success', 'not_modified'[\s\S]*interval '30 days'[\s\S]*3/i,
  );
  assert.match(
    nextRun,
    /'blocked', 'missing', 'failed'[\s\S]*interval '7 days'[\s\S]*1/i,
  );
  assert.match(
    nextRun,
    /canonical_card_enrichment_timestamp\(_completed_at\)/i,
  );
  assert.match(nextRun, /extract\(epoch from[\s\S]*86400/i);
  assert.match(
    nextRun,
    /_is_discontinued[\s\S]*NOT _has_active_cardholder[\s\S]*RETURN NULL/i,
  );
  assert.match(trigger, /parser_version\s*=\s*'benefits-v6'/i);
  assert.match(trigger, /NEW\.run_mode\s*=\s*'scheduled'/i);
  assert.match(
    trigger,
    /NEW\.status IN \('completed', 'staged', 'quarantined', 'review_required', 'failed'\)/i,
  );
  assert.match(trigger, /NEW\.next_retry_at IS NULL/i);
  assert.match(trigger, /next_card_enrichment_observation_at/i);
  assert.match(
    sql,
    /CREATE TRIGGER schedule_terminal_card_enrichment_observation[\s\S]*ON public\.card_catalog_enrichment_jobs/i,
  );
  assert.match(
    sql,
    /card_enrichment_requeue_action[\s\S]*'pilot'[\s\S]*'clear'[\s\S]*'scheduled'[\s\S]*'queue'/i,
  );
  assert.match(
    sql,
    /UPDATE public\.card_catalog_enrichment_jobs AS legacy_terminal[\s\S]*SET status = legacy_terminal\.status[\s\S]*parser_version = 'benefits-v6'[\s\S]*next_run_at IS NULL/i,
  );
  assert.doesNotMatch(
    sql,
    /legacy_terminal\.parser_version\s*(?:<>|!=)\s*'catalog-v1'/i,
  );
});

test('finalization preserves staging on 304, separates retry from recurrence, and retains newest 24 sanitized observations', async () => {
  const sql = await migrationSql();
  const finalize = functionBody(sql, 'finalize_card_catalog_enrichment_job');
  const normalize = functionBody(
    sql,
    'normalize_card_enrichment_observation_history',
  );
  const sanitizeSummary = functionBody(
    sql,
    'sanitize_card_enrichment_result_summary',
  );
  const sanitizeAttempt = functionBody(
    sql,
    'sanitize_card_enrichment_source_attempt',
  );
  const sanitizeObservation = functionBody(
    sql,
    'sanitize_card_enrichment_observation',
  );

  assert.match(
    finalize,
    /_status\s*=\s*'completed'\s+AND _staging_id IS NOT NULL/i,
  );
  const unlockedIdentity = finalize.indexOf(
    'SELECT candidate.card_id INTO job_card_id',
  );
  const reviewLock = finalize.indexOf('card_benefit_enrichment_review:');
  const lockedJob = finalize.indexOf('SELECT candidate.* INTO job_row');
  const lockedStaging = finalize.indexOf('SELECT staging.* INTO staging_row');
  assert.ok(
    unlockedIdentity > 0 && reviewLock > unlockedIdentity,
    'finalizer must resolve identity before review serialization',
  );
  assert.ok(
    lockedJob > reviewLock && lockedStaging > lockedJob,
    'finalizer must take the shared advisory lock before canonical row locks',
  );
  assert.match(finalize, /candidate\.card_id\s*=\s*job_card_id/i);
  assert.match(
    finalize,
    /staging\.card_id\s*=\s*job_row\.card_id[\s\S]*staging\.parser_version\s*=\s*job_row\.parser_version[\s\S]*FOR UPDATE/i,
  );
  assert.doesNotMatch(finalize, /card_enrichment_job_has_pending_staging/i);
  assert.match(finalize, /card_enrichment_final_staging_state\(/i);
  assert.match(finalize, /staging_id\s*=\s*resolved_staging_id/i);
  assert.match(
    finalize,
    /content_hash\s*=\s*coalesce\(_content_hash, job_row\.content_hash\)/i,
  );
  assert.match(
    finalize,
    /existing_observation_history\s*:=[\s\S]*job_row\.result_summary\s*->\s*'observations'/i,
  );
  assert.match(
    finalize,
    /normalize_card_enrichment_observation_history\([\s\S]*existing_observation_history[\s\S]*_result_summary\s*->\s*'observation'/i,
  );
  assert.match(
    finalize,
    /job_row\.result_summary\s*->\s*'observation'[\s\S]*normalize_card_enrichment_observation_history/i,
  );
  assert.match(finalize, /ELSE _next_retry_at/i);
  assert.match(finalize, /next_run_at\s*=\s*NULL/i);
  assert.match(
    finalize,
    /card_enrichment_final_staging_state\([\s\S]*locked_staging_status[\s\S]*locked_staging_valid/i,
  );
  assert.match(
    finalize,
    /next_retry_at\s*=\s*CASE[\s\S]*has_pending_staging[\s\S]*THEN NULL/i,
  );
  assert.match(
    finalize,
    /sanitize_card_enrichment_result_summary\(_result_summary/i,
  );
  assert.doesNotMatch(finalize, /safe_summary\s*:=\s*\(_result_summary\s*-/i);
  assert.match(normalize, /observed_at/i);
  assert.match(normalize, /source_manifest_hash/i);
  assert.match(normalize, /canonical_benefit_hash/i);
  assert.match(normalize, /ORDER BY[\s\S]*DESC/i);
  assert.match(normalize, /LIMIT 24/i);
  assert.match(normalize, /DISTINCT ON/i);
  assert.match(
    sanitizeAttempt,
    /bounded_card_enrichment_timestamp\(\s*_attempt->>'attemptedAt',\s*_now\s*\)/i,
  );
  assert.match(
    sanitizeAttempt,
    /bounded_card_enrichment_timestamp\(\s*history->>'attemptedAt',\s*_now\s*\)/i,
  );
  assert.match(
    sanitizeObservation,
    /bounded_card_enrichment_timestamp\(\s*_observation->>'observed_at',\s*_now\s*\)/i,
  );
  assert.match(sanitizeSummary, /allowed_key/i);
  assert.match(
    sanitizeSummary,
    /jsonb_typeof\(allowed_value\)\s*=\s*'boolean'/i,
  );
  assert.match(
    sanitizeSummary,
    /jsonb_typeof\(allowed_value\)\s*=\s*'number'/i,
  );
  assert.match(
    sanitizeSummary,
    /source_manifest_hash[\s\S]*\^\[0-9a-f\]\{64\}\$/i,
  );
  assert.doesNotMatch(
    sanitizeSummary,
    /'body'|'html'|'raw_page'|'response_body'/i,
  );
  assert.match(
    sql,
    /DO \$recurrence_policy_assertions\$[\s\S]*DO \$recurrence_history_assertions\$/i,
  );
  assert.match(
    sql,
    /DO \$finalizer_staging_state_assertions\$[\s\S]*pending_new[\s\S]*approved_returned[\s\S]*rejected_returned[\s\S]*approved_prior_304[\s\S]*obsolete_invalid/i,
  );
  assert.match(
    sql,
    /REVOKE ALL ON FUNCTION public\.finalize_card_catalog_enrichment_job[\s\S]*TO service_role/i,
  );
});

test('claiming is one-card with a 300-second lease and admin completion shares the terminal trigger', async () => {
  const sql = await migrationSql();
  const claim = functionBody(sql, 'claim_card_catalog_enrichment_jobs');
  const trigger = functionBody(
    sql,
    'schedule_terminal_card_enrichment_observation',
  );

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
    /expired_pending_failure_cadence[\s\S]*failure_category\s*=\s*'worker_resource_limit'/i,
  );
  assert.doesNotMatch(
    claim,
    /failure_category\s*=\s*CASE[\s\S]*THEN job\.failure_category/i,
  );
  assert.match(
    claim,
    /'retry_scheduled'[\s\S]*card_enrichment_job_has_pending_staging[\s\S]*THEN false/i,
  );
  assert.match(
    claim,
    /card_has_unresolved_catalog_identity\(job\.card_id, job\.canonical_url\)/i,
  );
  assert.doesNotMatch(
    claim,
    /AND NOT public\.card_enrichment_job_has_pending_staging/i,
  );
  assert.doesNotMatch(trigger, /card_enrichment_job_has_pending_staging/i);
  assert.doesNotMatch(claim, /auth\.role\(\)|service_role_required/i);
  assert.match(
    sql,
    /BEFORE INSERT OR UPDATE[\s\S]*schedule_terminal_card_enrichment_observation/i,
  );
  assert.doesNotMatch(
    sql,
    /CREATE OR REPLACE FUNCTION public\.approve_card_benefit_enrichment/i,
  );
});

test('recurrence transitions and pending review are explicit, bounded, and index-supported', async () => {
  const sql = await migrationSql();
  const action = functionBody(sql, 'card_enrichment_requeue_action');
  const requeue = functionBody(sql, 'requeue_due_card_catalog_enrichment_jobs');

  assert.match(
    action,
    /_run_mode\s*<>\s*'scheduled'[\s\S]*RETURN[\s\S]*'clear'/i,
  );
  assert.doesNotMatch(
    action,
    /IF _has_pending_staging[\s\S]*RETURN[\s\S]*'clear'/i,
  );
  assert.match(action, /NOT _eligible[\s\S]*RETURN[\s\S]*'clear'/i);
  assert.match(
    action,
    /_next_run_at IS NULL OR _next_run_at <= _now[\s\S]*RETURN 'queue'/i,
  );
  assert.match(
    requeue,
    /LIMIT _limit[\s\S]*FOR UPDATE(?: OF job)? SKIP LOCKED/i,
  );
  assert.match(
    requeue,
    /status\s*=\s*CASE WHEN selected\.action = 'queue' THEN 'queued' ELSE job\.status END/i,
  );
  assert.match(requeue, /WHERE updated\.action = 'queue'/i);
  assert.match(
    sql,
    /CREATE INDEX IF NOT EXISTS idx_card_catalog_enrichment_jobs_recurrence_v6/i,
  );
  assert.match(sql, /DO \$recurrence_transition_assertions\$[\s\S]*_limit=1/i);
  assert.match(
    sql,
    /'scheduled', 'staged', '2026-08-19T00:00:00Z'[\s\S]*true\s*\)[\s\S]*<> 'queue'/i,
  );
});

test('pending review recurs through ordered supersession while obsolete approval rolls back', async () => {
  const sql = await migrationSql();
  const finalize = functionBody(sql, 'finalize_card_catalog_enrichment_job');
  const effective = functionBody(
    sql,
    'card_enrichment_effective_terminal_status',
  );
  const stageSql = await readFile(stagingMigration, 'utf8');
  const reviewSql = await readFile(reviewMigration, 'utf8');
  const stage = functionBody(stageSql, 'stage_card_benefit_enrichment');
  const approve = functionBody(reviewSql, 'approve_card_benefit_enrichment');

  assert.match(effective, /_has_pending_staging[\s\S]*THEN 'staged'/i);
  const sharedReviewLock = /hashtextextended\(\s*'card_benefit_enrichment_review:'\s*\|\|\s*\w+::text,\s*0\s*\)/i;
  assert.match(finalize, sharedReviewLock);
  assert.match(stage, sharedReviewLock);
  assert.match(approve, sharedReviewLock);
  assert.match(finalize, /locked_staging_status[\s\S]*resolved_staging_id/i);
  assert.match(finalize, /existing_observation_history[\s\S]*observations/i);
  assert.match(stage, /superseded_by_newer_crawl/i);
  assert.match(stage, /SET staging_id = resolved_staging_id/i);
  assert.match(
    approve,
    /WHERE job\.staging_id = staging_row\.id[\s\S]*job\.status = 'staged'[\s\S]*linked_job_count < 1[\s\S]*RAISE EXCEPTION 'linked_staged_job_not_found'/i,
  );
  assert.doesNotMatch(
    sql,
    /CREATE OR REPLACE FUNCTION public\.approve_card_benefit_enrichment/i,
  );
});

test('v6 enqueue revalidates authoritative catalog eligibility and enforces future identity uniqueness', async () => {
  const sql = await migrationSql();
  const enqueue = functionBody(sql, 'enqueue_card_benefit_enrichment_jobs');
  const eligible = functionBody(
    sql,
    'card_enrichment_enqueue_catalog_eligible',
  );
  const identityTrigger = functionBody(
    sql,
    'enforce_card_benefit_enrichment_identity',
  );

  assert.match(enqueue, /locked_enqueue_authority[\s\S]*FOR UPDATE OF card/i);
  assert.match(
    eligible,
    /lower\(trim\(coalesce\(_card_type,[\s\S]*\)\)\)\s*=\s*'credit'/i,
  );
  assert.match(
    eligible,
    /_is_discontinued IS DISTINCT FROM true[\s\S]*_has_active_cardholder IS TRUE/i,
  );
  assert.match(
    eligible,
    /_input_issuer[\s\S]*_card_bank[\s\S]*_input_url[\s\S]*canonical_catalog_url/i,
  );
  assert.match(
    eligible,
    /_input_url_hash[\s\S]*extensions\.digest[\s\S]*_input_url/i,
  );
  assert.match(enqueue, /user_cards[\s\S]*is_active\s*=\s*true/i);
  assert.match(
    enqueue,
    /card_catalog_review_queue AS review[\s\S]*review\.status = 'pending'[\s\S]*FOR SHARE OF review[\s\S]*card_has_unresolved_catalog_identity/i,
  );
  assert.match(
    enqueue,
    /card_has_unresolved_catalog_identity\(\s*candidate\.card_id,\s*candidate\.canonical_url\s*\)/i,
  );
  assert.match(enqueue, /RETURN inserted_count/i);
  assert.match(
    identityTrigger,
    /card_benefit_enrichment_identity:[\s\S]*NEW\.card_id[\s\S]*benefits-v6/i,
  );
  assert.match(identityTrigger, /NEW\.card_id::text\s*\|\|\s*':benefits-v6'/i);
  assert.match(
    identityTrigger,
    /existing_job\.job_key IS DISTINCT FROM NEW\.job_key[\s\S]*duplicate_v6_card_parser_identity/i,
  );
  assert.match(
    sql,
    /duplicate_v6_card_parser_preflight[\s\S]*GROUP BY[\s\S]*card_id, lower\(trim\(existing_job\.parser_version\)\)[\s\S]*HAVING count\(\*\) > 1/i,
  );
  assert.match(
    sql,
    /CREATE UNIQUE INDEX idx_card_catalog_enrichment_jobs_unique_v6_card_parser[\s\S]*card_id,[\s\S]*lower\(trim\(parser_version\)\)[\s\S]*WHERE lower\(trim\(parser_version\)\) = 'benefits-v6'/i,
  );
  assert.match(
    sql,
    /CREATE TRIGGER enforce_card_benefit_enrichment_identity[\s\S]*BEFORE INSERT OR UPDATE OF card_id, parser_version/i,
  );
  assert.match(
    sql,
    /REVOKE ALL ON FUNCTION public\.enforce_card_benefit_enrichment_identity\(\)[\s\S]*FROM PUBLIC, anon, authenticated/i,
  );
  assert.match(
    sql,
    /DO \$enqueue_authority_assertions\$[\s\S]*atomic_batch[\s\S]*zero_insert[\s\S]*partial_insert[\s\S]*catalog_race/i,
  );
});

test('pilot qualification atomically promotes the existing exact five identities once', async () => {
  const sql = await migrationSql();
  const qualify = functionBody(sql, 'card_enrichment_pilot_job_is_qualified');
  const promote = functionBody(
    sql,
    'promote_qualified_card_benefit_enrichment_pilot',
  );
  const validateEnvelope = functionBody(
    sql,
    'card_enrichment_pilot_evidence_is_qualified',
  );
  const sourceIdentity = functionBody(
    sql,
    'card_enrichment_pilot_source_identity_hash',
  );
  const sourceManifest = functionBody(
    sql,
    'card_enrichment_pilot_source_manifest_hash',
  );
  const liveSnapshot = functionBody(
    sql,
    'card_enrichment_pilot_live_state_snapshot',
  );
  const capturePublished = functionBody(
    sql,
    'capture_card_enrichment_pilot_publication_snapshot',
  );
  const initialize = functionBody(
    sql,
    'initialize_card_benefit_enrichment_pilot',
  );
  const cohortAction = functionBody(sql, 'card_enrichment_pilot_cohort_action');
  const enqueue = functionBody(sql, 'enqueue_card_benefit_enrichment_jobs');

  assert.match(qualify, /successful_no_change/i);
  assert.match(qualify, /review_status/i);
  assert.match(qualify, /approved_count/i);
  assert.match(qualify, /rejected_count/i);
  assert.match(qualify, /status = 'quarantined'[\s\S]*failure_category/i);
  assert.match(qualify, /_summary \? 'unsafe_mutation_count'/i);
  assert.match(
    qualify,
    /jsonb_typeof\(_summary->'unsafe_mutation_count'\)\s*<>\s*'number'/i,
  );
  assert.match(qualify, /_summary \? 'raw_body_stored'/i);
  assert.match(
    qualify,
    /jsonb_typeof\(_summary->'raw_body_stored'\)\s*<>\s*'boolean'/i,
  );
  assert.match(qualify, /failure_category[\s\S]*\^\[a-z0-9_\][^$]*\$/i);
  assert.match(promote, /selected_parser\s*<>\s*'benefits-v6'/i);
  assert.match(promote, /FOR UPDATE(?: OF job)?/i);
  assert.match(promote, /card_benefits_staging[\s\S]*FOR UPDATE/i);
  assert.match(
    promote,
    /card_catalog_review_queue[\s\S]*status\s*=\s*'pending'[\s\S]*FOR SHARE/i,
  );
  assert.match(promote, /card_benefit_mapping[\s\S]*FOR SHARE/i);
  assert.match(promote, /public\.benefits[\s\S]*FOR SHARE/i);
  assert.match(
    promote,
    /LOCK TABLE public\.card_catalog_review_queue IN SHARE MODE/i,
  );
  assert.match(
    promote,
    /LOCK TABLE public\.card_benefit_mapping IN SHARE MODE/i,
  );
  assert.match(promote, /card_benefit_enrichment_review:[\s\S]*pilot_card_id/i);
  assert.match(promote, /normalized_fields->'pilot_evidence'->>'staging_id'/i);
  assert.match(promote, /count\(\*\)[\s\S]*<> 5/i);
  assert.match(
    promote,
    /bool_and\([\s\S]*card_enrichment_pilot_evidence_is_qualified/i,
  );
  assert.match(validateEnvelope, /verification_envelope/i);
  assert.match(validateEnvelope, /repeat_verification_envelope/i);
  assert.match(validateEnvelope, /canonical_json_text/i);
  assert.match(validateEnvelope, /extensions\.digest/i);
  assert.match(validateEnvelope, /benefit_decisions/i);
  assert.match(validateEnvelope, /catalog_identity_conflict_count/i);
  assert.match(
    validateEnvelope,
    /source_manifest_hash[\s\S]*card_enrichment_pilot_source_manifest_hash/i,
  );
  assert.match(
    validateEnvelope,
    /logicalSourceKey[\s\S]*card_enrichment_pilot_source_identity_hash\(_job\.canonical_url\)/i,
  );
  assert.doesNotMatch(
    validateEnvelope,
    /role' = 'primary'\)[\s\S]{0,120}url'[\s\S]*_job\.canonical_url/i,
  );
  assert.match(
    validateEnvelope,
    /required_source_selection_overflow[\s\S]*IS DISTINCT FROM 'false'::jsonb/i,
  );
  assert.match(
    validateEnvelope,
    /expected_required_source_keys[\s\S]*required_supporting/i,
  );
  assert.match(validateEnvelope, /replay_input[\s\S]*replay_input_hash/i);
  assert.match(validateEnvelope, /replay_input->'context'[\s\S]*issuer/i);
  assert.match(
    validateEnvelope,
    /replay_input->'context'[\s\S]*identity_labels/i,
  );
  assert.match(
    validateEnvelope,
    /replay_input->'context'[\s\S]*primary_source_url/i,
  );
  assert.match(
    validateEnvelope,
    /hyperlinks[\s\S]*anchor_text[\s\S]*resource_identity_hash/i,
  );
  assert.doesNotMatch(
    validateEnvelope,
    /replay_input->'required_resources'/i,
    'classifier output must not be copied into retained replay input',
  );
  assert.match(
    validateEnvelope,
    /role' IN \('primary','required_supporting'\)[\s\S]*status' NOT IN \('success','not_modified'\)/i,
  );
  assert.match(
    validateEnvelope,
    /attemptHistoryOverflow[\s\S]*= 'true'::jsonb/i,
  );
  assert.match(
    validateEnvelope,
    /retained_documents[\s\S]*document_text_hash/i,
  );
  assert.match(
    validateEnvelope,
    /verification_envelope\s+IS DISTINCT FROM repeat_verification_envelope/i,
  );
  assert.match(
    validateEnvelope,
    /current_live_state[\s\S]*published_live_state/i,
  );
  assert.match(
    validateEnvelope,
    /action' IN \('approve','edit'\)[\s\S]*proposal_index[\s\S]*benefit_id[\s\S]*dedupe_key[\s\S]*condition_hash/i,
  );
  assert.match(
    validateEnvelope,
    /review_pre_live_state[\s\S]*live_state_after/i,
  );
  assert.match(
    validateEnvelope,
    /count\(\*\) FILTER \(WHERE value->>'action' IN \('approve','edit'\)\)/i,
  );
  assert.match(sourceManifest, /attemptedAt/i);
  assert.match(sourceManifest, /attemptHistory/i);
  assert.match(
    sourceManifest,
    /string_agg[\s\S]*ORDER BY public\.canonical_json_text/i,
  );
  assert.match(sourceIdentity, /regexp_match[\s\S]*extensions\.digest/i);
  assert.match(
    liveSnapshot,
    /card_catalog[\s\S]*card_benefit_mapping[\s\S]*public\.benefits/i,
  );
  assert.match(liveSnapshot, /canonical_card_benefit_row_timestamp/i);
  assert.match(capturePublished, /OLD\.status IS DISTINCT FROM 'approved'/i);
  assert.match(capturePublished, /pilot_evidence'[\s\S]*staging_id/i);
  assert.match(
    sql,
    /CREATE TRIGGER capture_card_enrichment_pilot_publication_snapshot[\s\S]*BEFORE UPDATE OF status ON public\.card_benefits_staging/i,
  );
  assert.match(promote, /SET run_mode = 'scheduled'/i);
  assert.match(promote, /'pilot_qualified', true/i);
  assert.match(
    promote,
    /other_job\.card_id = pilot_job\.card_id[\s\S]*other_job\.parser_version = pilot_job\.parser_version[\s\S]*other_job\.id <> pilot_job\.id/i,
  );
  assert.match(promote, /job\.run_mode = 'pilot'[\s\S]*pilot_qualified/i);
  assert.match(
    promote,
    /IF promoted_count = 5 THEN[\s\S]*RETURN QUERY[\s\S]*RETURN;/i,
  );
  assert.match(
    promote,
    /promoted_count = 5[\s\S]*NOT public\.card_enrichment_pilot_evidence_is_qualified[\s\S]*RAISE EXCEPTION 'pilot_not_qualified'/i,
  );
  assert.doesNotMatch(
    promote,
    /promoted_count = 5[\s\S]{0,800}status = 'completed'/i,
    'idempotent promotion must validate immutable original proof after later scheduled status changes',
  );
  assert.match(promote, /count\(DISTINCT[\s\S]*pilot_profile[\s\S]*\<\> 5/i);
  for (
    const profile of [
      'straightforward',
      'redirect_or_js',
      'terms_linked',
      'known_invalid',
      'additional_valid',
    ]
  ) {
    assert.match(promote, new RegExp(profile, 'i'));
  }
  assert.match(
    promote,
    /count\(DISTINCT lower\(trim\([\s\S]*issuer[\s\S]*\)\)[\s\S]*< 3/i,
  );
  assert.match(
    promote,
    /pilot_count <> 5 OR promoted_count <> 0 OR NOT all_qualified/i,
  );
  assert.doesNotMatch(
    promote,
    /INSERT INTO public\.card_catalog_enrichment_jobs/i,
  );
  const sharedPilotLock = /hashtextextended\('card_benefit_enrichment_pilot:'\s*\|\|\s*selected_parser,\s*0\)/i;
  assert.match(promote, sharedPilotLock);
  assert.match(initialize, sharedPilotLock);
  const sharedIdentityLock = /card_benefit_enrichment_identity:[\s\S]*card_id[\s\S]*parser_version/i;
  assert.match(initialize, sharedIdentityLock);
  assert.match(enqueue, sharedIdentityLock);
  assert.match(
    initialize,
    /locked_candidate_authority[\s\S]*FOR UPDATE OF card/i,
  );
  assert.match(
    initialize,
    /jsonb_to_recordset\(locked_candidates\)[\s\S]*is_discontinued[\s\S]*card_type[\s\S]*card_url/i,
  );
  assert.match(
    initialize,
    /INSERT INTO public\.card_catalog_enrichment_jobs[\s\S]*FROM jsonb_to_recordset\(locked_candidates\)/i,
  );
  const candidateInsert = initialize.slice(
    initialize.indexOf('INSERT INTO public.card_catalog_enrichment_jobs'),
    initialize.indexOf('GET DIAGNOSTICS inserted_count'),
  );
  assert.doesNotMatch(
    candidateInsert,
    /JOIN public\.card_catalog/i,
    'insert must not weakly reread catalog after candidate validation',
  );
  assert.match(
    candidateInsert,
    /NOT EXISTS[\s\S]*existing_job\.card_id = candidate\.card_id[\s\S]*existing_job\.parser_version = selected_parser/i,
  );
  assert.match(
    enqueue,
    /ORDER BY[\s\S]*card_id[\s\S]*parser_version[\s\S]*pg_advisory_xact_lock/i,
  );
  assert.match(
    enqueue,
    /existing_job\.job_key IS DISTINCT FROM candidate\.job_key[\s\S]*duplicate_v6_card_parser_identity/i,
  );
  assert.match(
    enqueue,
    /GROUP BY duplicate_input\.card_id,[\s\S]*HAVING count\(\*\) > 1[\s\S]*duplicate_card_parser_enqueue/i,
  );
  assert.match(initialize, /card_enrichment_pilot_cohort_action\(/i);
  assert.match(
    initialize,
    /'return_promoted'[\s\S]*pilot_qualified[\s\S]*RETURN;/i,
  );
  assert.match(
    initialize,
    /'return_pilot'[\s\S]*run_mode\s*=\s*'pilot'[\s\S]*RETURN;/i,
  );
  assert.match(
    initialize,
    /pilot_card_identity_conflict|pilot_state_incomplete/i,
  );
  assert.match(
    cohortAction,
    /_pilot_count = 0 AND _promoted_count = 5[\s\S]*'return_promoted'/i,
  );
  assert.match(
    cohortAction,
    /_pilot_count = 5 AND _promoted_count = 0[\s\S]*'return_pilot'/i,
  );
  assert.match(
    cohortAction,
    /_pilot_count = 0 AND _promoted_count = 0[\s\S]*'initialize'/i,
  );
  assert.match(cohortAction, /_has_duplicate[\s\S]*'reject'/i);
  assert.doesNotMatch(
    initialize,
    /pilot_count\s*=\s*5[\s\S]*promoted_count\s*=\s*5[\s\S]*INSERT INTO/i,
  );
  assert.match(
    sql,
    /REVOKE ALL ON FUNCTION public\.promote_qualified_card_benefit_enrichment_pilot\(text\)[\s\S]*TO service_role/i,
  );
  assert.match(
    sql,
    /REVOKE ALL ON FUNCTION public\.initialize_card_benefit_enrichment_pilot\(jsonb, text\)[\s\S]*TO service_role/i,
  );
  assert.match(
    sql,
    /REVOKE ALL ON FUNCTION public\.enqueue_card_benefit_enrichment_jobs\(jsonb\)[\s\S]*TO service_role/i,
  );
  assert.match(
    sql,
    /DO \$pilot_qualification_assertions\$[\s\S]*fully_rejected[\s\S]*partially_rejected[\s\S]*successful_no_change/i,
  );
  assert.match(
    sql,
    /DO \$pilot_atomic_evidence_assertions\$[\s\S]*pilot_source_manifest_timestamp_or_order_drift[\s\S]*pilot_publication_snapshot_trigger_missing/i,
  );
  assert.match(
    sql,
    /DO \$pilot_cohort_assertions\$[\s\S]*return_promoted[\s\S]*partial[\s\S]*five_plus_five[\s\S]*duplicate/i,
  );
  assert.match(
    sql,
    /missing_unsafe[\s\S]*null_unsafe[\s\S]*string_unsafe[\s\S]*negative_unsafe[\s\S]*noninteger_unsafe[\s\S]*missing_raw[\s\S]*null_raw[\s\S]*string_raw[\s\S]*true_raw/i,
  );
  assert.match(qualify, /review_status'[\s\S]*IS DISTINCT FROM 'approved'/i);
  assert.match(qualify, /MAX_PILOT_REVIEW_COUNT/i);
  assert.match(qualify, /::numeric[\s\S]*trunc\(/i);
  assert.match(qualify, /::bigint/i);
  assert.match(
    sql,
    /missing_review_field[\s\S]*null_review_field[\s\S]*status_casing[\s\S]*one_point_zero_count[\s\S]*ten_digit_count[\s\S]*overflow_count[\s\S]*negative_review_count[\s\S]*fractional_review_count[\s\S]*string_review_count[\s\S]*max_review_count/i,
  );
});

test('canonical recurrence timestamps and history normalization have apply-time parity assertions', async () => {
  const sql = await migrationSql();
  const canonical = functionBody(sql, 'canonical_card_enrichment_timestamp');
  const normalize = functionBody(
    sql,
    'normalize_card_enrichment_observation_history',
  );
  const bounded = functionBody(sql, 'bounded_card_enrichment_timestamp');

  assert.match(
    canonical,
    /regexp_match[\s\S]*offset_hour[\s\S]*offset_minute/i,
  );
  assert.match(bounded, /canonical_card_benefit_row_timestamp/i);
  assert.match(canonical, /RETURN NULL/i);
  assert.match(normalize, /source_manifest_hash[\s\S]*canonical_benefit_hash/i);
  assert.match(
    sql,
    /2026-02-30T00:00:00\.000Z[\s\S]*2026-02-20T05:30:00\.000\+05:30/i,
  );
  assert.match(sql, /America\/New_York[\s\S]*2026-04-09T07:30:00\+00:00/i);
  assert.match(sql, /legacy-root[\s\S]*legacy-history/i);
});

test('pilot SQL validates real timestamptz text, attempt history, and HTTP status bounds', async () => {
  const sql = await migrationSql();
  const validateEnvelope = functionBody(
    sql,
    'card_enrichment_pilot_evidence_is_qualified',
  );
  const pilotTimestamp = functionBody(sql, 'card_enrichment_pilot_timestamp');
  const liveTimestamp = functionBody(
    sql,
    'card_enrichment_pilot_live_state_snapshot',
  );
  assert.match(
    pilotTimestamp,
    /(?:T|\\s)[\s\S]*(?:Z|\[\+\-\][\s\S]*\\d\{2\}[\s\S]*\\d\{2\})/i,
  );
  assert.match(pilotTimestamp, /2000-01-01[\s\S]*clock_timestamp/i);
  assert.match(liveTimestamp, /canonical_card_benefit_row_timestamp/i);
  assert.match(
    validateEnvelope,
    /observed_at[\s\S]*card_enrichment_pilot_timestamp/i,
  );
  assert.match(
    validateEnvelope,
    /attemptedAt[\s\S]*card_enrichment_pilot_timestamp/i,
  );
  assert.match(
    validateEnvelope,
    /attemptHistory[\s\S]*jsonb_array_length[\s\S]*> 6/i,
  );
  assert.match(validateEnvelope, /httpStatus[\s\S]*100[\s\S]*599/i);
  assert.match(
    sql,
    /2026-08-20 00:00:00\.1234\+00[\s\S]*2026-08-20T00:00:00\.123400Z/i,
  );
  assert.match(sql, /\.123500Z/i);
  assert.match(
    sql,
    /2026-08-20T05:30:00\.123456\+05:30[\s\S]*2026-08-20T00:00:00\.123456Z/i,
  );
  assert.match(
    sql,
    /2026-08-19T20:00:00\.123456-04:00[\s\S]*2026-08-20T00:00:00\.123456Z/i,
  );
});

test('pilot SQL rejects labeled and unlabeled person data in retained replay text', async () => {
  const migration = await migrationSql();
  assert.match(
    migration,
    /customer\|account\|card\|payment\|pan\|phone\|mobile/,
    'replay validator does not reject labeled customer/payment values',
  );
  assert.match(
    migration,
    /gets\?[\s\S]{0,160}receives\?[\s\S]{0,160}will/,
    'replay validator does not reject person-like spans in benefit prose',
  );
  assert.match(migration, /\{10,\}/, 'long numeric IDs above 19 digits are accepted');
  assert.match(
    migration,
    /regexp_matches[\s\S]*cardholder[\s\S]*customer/i,
    'lowercase unknown person-like subjects are not separated from public cardholder terms',
  );
  assert.match(
    migration,
    /regexp_matches\([\s\S]*lower\(document\.value->>'public_text'\)[\s\S]*gets\?/i,
    'mixed-case and uppercase unknown person subjects bypass replay privacy validation',
  );
  assert.match(
    migration,
    /anchor_text'\s*!~[\s\S]*most[\s\S]*important[\s\S]*terms/i,
    'replay anchors accept arbitrary prose instead of the required-source vocabulary',
  );
});

test('pilot SQL binds replay URLs, opaque identities, and catalog labels to authoritative rows', async () => {
  const sql = await migrationSql();
  const validator = functionBody(
    sql,
    'card_enrichment_pilot_evidence_is_qualified',
  );
  assert.match(
    validator,
    /link\.value->>'href'[\s\S]*attempt\.value->>'url'/i,
    'replay hyperlink href is not bound to the exact source attempt',
  );
  assert.match(
    validator,
    /requested_resource_identity_hash[\s\S]*logicalSourceKey/i,
    'retained document identity is not bound to its source attempt',
  );
  assert.match(
    validator,
    /attempt\.value->>'url'\s*=\s*document\.value->>'final_source_url'/i,
    'redirected documents are not bound through their observed final URL',
  );
  assert.match(
    validator,
    /linked_document[\s\S]*requested_source_url[\s\S]*resource_identity_hash/i,
    'a requested replay link cannot resolve through its redirected document',
  );
  assert.match(
    validator,
    /identity_labels[\s\S]*card_catalog_aliases/i,
    'replay card labels are not checked against authoritative catalog identity',
  );
});

test('pilot SQL recomputes v3 functional resource hashes and rejects every overflow bit', async () => {
  const sql = await migrationSql();
  const validator = functionBody(
    sql,
    'card_enrichment_pilot_evidence_is_qualified',
  );
  const resourceHash = functionBody(
    sql,
    'card_enrichment_pilot_source_identity_hash',
  );
  assert.match(validator, /replay_input->'version' IS DISTINCT FROM '3'::jsonb/i);
  for (const field of [
    'requested_resource_url',
    'final_resource_url',
    'fact_count',
    'fact_overflow',
    'privacy_normalized',
    'resource_url',
    'query_policy',
  ]) {
    assert.match(validator, new RegExp(field, 'i'), `${field} is not SQL-authoritative`);
  }
  assert.match(
    validator,
    /card_enrichment_pilot_source_identity_hash\(\s*document\.value->>'requested_resource_url'\s*\)[\s\S]*requested_resource_identity_hash/i,
    'SQL trusts a supplied requested-resource digest',
  );
  assert.match(
    validator,
    /card_enrichment_pilot_source_identity_hash\(\s*link\.value->>'resource_url'\s*\)[\s\S]*resource_identity_hash/i,
    'SQL trusts a supplied hyperlink digest',
  );
  assert.match(
    validator,
    /fact_overflow'\s+IS DISTINCT FROM 'false'::jsonb[\s\S]*hyperlink_overflow'\s+IS DISTINCT FROM 'false'::jsonb/i,
    'SQL qualification does not reject every replay overflow dimension',
  );
  assert.match(
    resourceHash,
    /query_key NOT IN \('document','file','locale','version'\)/i,
  );
  assert.doesNotMatch(
    resourceHash,
    /['"](?:variant|filename|language|lang)['"]/i,
  );
  assert.match(resourceHash, /string_to_array\([\s\S]*'&'[\s\S]*FOREACH/i);
  assert.ok(
    resourceHash.includes('query_value') &&
      resourceHash.includes('decoded_query_value') &&
      resourceHash.includes('access[_ -]?token') &&
      /regexp_replace\(\s*query_value/i.test(resourceHash) &&
      resourceHash.includes("'[^0-9]', '', 'g'"),
    'SQL functional resource policy does not reject sensitive values',
  );
  assert.match(
    resourceHash,
    /length\(query_value\)\s*>\s*512/i,
    'SQL does not enforce the exact raw functional-query byte bound',
  );
  assert.match(
    sql,
    /pilot_resource_identity_assertions[\s\S]*access%5Ftoken[\s\S]*customer%20id[\s\S]*%73ecret[\s\S]*%FF[\s\S]*%0A/i,
    'migration lacks apply-time encoded sensitive/control URL probes',
  );
  assert.match(
    resourceHash,
    /resource_query <> ''[\s\S]*resource_path IN \('',\s*'\/'\)[\s\S]*resource_path := '\/'/i,
    'SQL root-resource canonicalization can drift from the Edge URL serializer',
  );
  assert.match(
    sql,
    /pilot_resource_identity_assertions[\s\S]*document=mitc\.pdf&locale=en&version=2&locale=hi[\s\S]*locale=hi&version=2/i,
    'migration lacks apply-time query ordering/duplicate/hash parity assertions',
  );
  assert.match(
    sql,
    /https:\/\/issuer\.example\/\?locale=en[\s\S]*2b11cd567b1ddbc93697a59fe4a74f972bf7988553f3d43ca34d039e33aa28a5/i,
    'migration lacks a cross-runtime known root functional-resource hash',
  );
});

test('pilot SQL mirrors normalized privacy and exact catalog-context allowlisting', async () => {
  const sql = await migrationSql();
  const validator = functionBody(
    sql,
    'card_enrichment_pilot_evidence_is_qualified',
  );
  assert.match(validator, /normalize\([\s\S]*NFKD/i);
  assert.ok(
    validator.includes("%(25)*[0-9a-f]{2}") &&
      validator.includes("#x?[0-9a-f]+"),
    'SQL does not fail closed on recursively encoded percent/HTML payloads',
  );
  assert.match(
    validator,
    /named[_ -]?html|&\[a-z\]\[a-z0-9\]/i,
    'SQL does not fail closed on unrecognized named HTML entities',
  );
  assert.match(
    validator,
    /residual[_ -]?unicode[_ -]?digit|1e950/i,
    'SQL does not reject residual Unicode decimal-digit scripts',
  );
  assert.match(validator, /200b|200c|200d|2060|feff/i);
  assert.match(validator, /fullwidth|ff10|ff19|unicode/i);
  assert.match(
    validator,
    /identity_labels[\s\S]*exact_identity_phrase[\s\S]*personal\.match\[1\]/i,
    'known issuer/card labels are not exact-phrase allowlisted in the person-span check',
  );
  assert.doesNotMatch(
    validator,
    /position\(lower\(personal\.match\[1\]\)\s+IN\s+lower\(/i,
    'an arbitrary issuer/card word substring is still allowlisted',
  );
  assert.match(
    validator,
    /[Іі]/,
    'Ukrainian-I confusables are not rejected at the SQL boundary',
  );
  assert.match(
    validator,
    /\\p\{Script=Devanagari\}|Devanagari/i,
    'SQL does not fail closed on unknown Devanagari person spans',
  );
  assert.match(
    sql,
    /pilot_privacy_assertions[\s\S]*American Express[\s\S]*State Bank of India[\s\S]*India gets[\s\S]*ALICE[\s\S]*Rahul/i,
    'migration lacks apply-time exact-product, partial-label, and unknown-person privacy probes',
  );
});

test('recurrence sanitizers canonicalize every valid offset timestamp to UTC microseconds', async () => {
  const sql = await migrationSql();
  const canonical = functionBody(sql, 'canonical_card_enrichment_timestamp');
  const bounded = functionBody(sql, 'bounded_card_enrichment_timestamp');
  const summary = functionBody(
    sql,
    'sanitize_card_enrichment_result_summary',
  );
  assert.match(canonical, /[+-][\s\S]*offset_hour[\s\S]*offset_minute/i);
  assert.match(
    bounded,
    /canonical_card_benefit_row_timestamp\(parsed_value\)/i,
    'bounded recurrence timestamps return session/input text instead of canonical UTC',
  );
  assert.match(
    summary,
    /reviewed_at[\s\S]*bounded_card_enrichment_timestamp/i,
    'reviewed_at is only prefix-checked instead of parsed and canonicalized',
  );
  assert.match(
    sql,
    /2026-08-20T05:30:00\.123456\+05:30[\s\S]*2026-08-20T00:00:00\.123456Z/i,
  );
});
