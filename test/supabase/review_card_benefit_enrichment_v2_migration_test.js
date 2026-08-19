import test from 'node:test';
import assert from 'node:assert/strict';
import { readdir, readFile } from 'node:fs/promises';

const repoRoot = new URL('../../', import.meta.url);
const migrationsRoot = new URL('supabase/migrations/', repoRoot);

async function migrationSql() {
  const names = (await readdir(migrationsRoot)).filter((name) =>
    name.endsWith('_review_card_benefit_enrichment_v2.sql')
  );
  assert.equal(names.length, 1, 'one CLI-generated v2 review migration is required');
  assert.match(names[0], /^\d{14}_review_card_benefit_enrichment_v2\.sql$/);
  return readFile(new URL(names[0], migrationsRoot), 'utf8');
}

function functionBody(sql, name) {
  const start = sql.search(new RegExp(`CREATE OR REPLACE FUNCTION public\\.${name}\\s*\\(`, 'i'));
  assert.notEqual(start, -1, `${name} is required`);
  const end = sql.indexOf('$$;', start);
  assert.notEqual(end, -1, `${name} must have a complete body`);
  return sql.slice(start, end + 3);
}

test('v2 approval keeps the existing schema and a service-role-only invoker boundary', async () => {
  const sql = await migrationSql();
  const approval = functionBody(sql, 'approve_card_benefit_enrichment');
  assert.match(approval, /SECURITY INVOKER/i);
  assert.match(approval, /SET search_path\s*=\s*public, extensions, pg_temp/i);
  assert.doesNotMatch(approval, /auth\.role\s*\(/i);
  assert.match(sql, /REVOKE ALL ON FUNCTION public\.approve_card_benefit_enrichment\(uuid, uuid, jsonb\)\s+FROM PUBLIC, anon, authenticated/i);
  assert.match(sql, /GRANT EXECUTE ON FUNCTION public\.approve_card_benefit_enrichment\(uuid, uuid, jsonb\)\s+TO service_role/i);
  assert.doesNotMatch(sql, /\b(?:CREATE\s+(?:UNLOGGED\s+)?TABLE|ADD\s+COLUMN|DROP\s+(?:TABLE|COLUMN))\b/i);
  assert.match(sql, /review_v2_acl_assertions[\s\S]*envelope_definition[\s\S]*card_scoped_benefit_key\\?\(_card_id/i);
  assert.match(sql, /FOREACH protected_oid IN ARRAY[\s\S]*canonical_json_text\(jsonb\)[\s\S]*validate_locked_retirement_evidence\(jsonb,uuid\)[\s\S]*has_function_privilege\('authenticated', protected_oid, 'EXECUTE'\)/i);
});

test('locked staging card and exact proposal set govern canonical publication', async () => {
  const approval = functionBody(await migrationSql(), 'approve_card_benefit_enrichment');
  assert.match(approval, /FROM public\.card_benefits_staging[\s\S]*FOR UPDATE/i);
  assert.match(approval, /parser_version NOT IN \('benefits-v5', 'benefits-v6'\)/i);
  assert.match(approval, /jsonb_typeof\(staging_row\.extracted_data->'proposals'\)\s*<>\s*'array'/i);
  assert.match(approval, /decision_proposal_index\s*:=\s*\(decision->>'proposal_index'\)::integer[\s\S]*staging_row\.extracted_data->'proposals'->decision_proposal_index/i);
  assert.match(approval, /validate_benefit_publication_envelope\([\s\S]*staging_row\.card_id[\s\S]*staged_proposal/i);
  assert.match(approval, /decision_proposal_index[\s\S]*seen_decision_identities[\s\S]*duplicate_benefit_decision/i);
  assert.match(approval, /superseded_by_newer_crawl|superseded_staging/i);
});

test('publication inserts immutable canonical rows and scopes every lifecycle mutation to one mapping', async () => {
  const approval = functionBody(await migrationSql(), 'approve_card_benefit_enrichment');
  assert.match(approval, /INSERT INTO public\.benefits/i);
  assert.match(approval, /ON CONFLICT \(dedupe_key\) DO NOTHING/i);
  assert.doesNotMatch(approval, /ON CONFLICT \(dedupe_key\) DO UPDATE/i);
  assert.doesNotMatch(approval, /UPDATE public\.benefits/i);
  assert.doesNotMatch(approval, /benefits[\s\S]*is_active\s*=/i);
  assert.match(approval, /INSERT INTO public\.card_benefit_mapping[\s\S]*ON CONFLICT \(card_id, benefit_id\) DO UPDATE[\s\S]*retired_at\s*=\s*NULL/i);
  assert.match(approval, /benefit\.title\s*=\s*canonical_benefit->>'title'[\s\S]*benefit\.description\s+IS NOT DISTINCT FROM/i);
  const mappingUpdates = [...approval.matchAll(/UPDATE public\.card_benefit_mapping[\s\S]*?;/gi)];
  assert.ok(mappingUpdates.length >= 2, 'replacement and retirement mapping updates are required');
  for (const [statement] of mappingUpdates) {
    assert.match(statement, /card_id\s*=\s*staging_row\.card_id/i);
    assert.match(statement, /benefit_id\s*=\s*(?:staged_)?existing_benefit_id/i);
  }
  assert.match(approval, /canonical_benefit->>'valid_from'[\s\S]*AT TIME ZONE 'UTC'[\s\S]*retired_at/i);
});

test('retirement, audit append, replay, and linked-job completion fail closed', async () => {
  const sql = await migrationSql();
  const approval = functionBody(sql, 'approve_card_benefit_enrichment');
  const retirement = functionBody(sql, 'validate_locked_retirement_evidence');
  assert.match(approval, /decision_action NOT IN \('approve', 'edit', 'reject', 'keep_existing', 'retire'\)/i);
  assert.match(retirement, /retirementEligible[\s\S]*retirementReason[\s\S]*retirement_not_eligible/i);
  assert.match(approval, /benefit_decisions\s*=\s*CASE[\s\S]*\|\|\s*audit_decisions/i);
  assert.match(approval, /source_evidence/i);
  assert.match(approval, /review_payload_hash[\s\S]*already_reviewed/i);
  assert.match(approval, /UPDATE public\.card_catalog_enrichment_jobs[\s\S]*status\s*=\s*'completed'[\s\S]*next_run_at\s*=\s*statement_timestamp\(\)\s*\+\s*interval '30 days'/i);
  assert.match(approval, /staging_id\s*=\s*staging_row\.id/i);
});

test('canonical helpers validate commercial shapes, dates, arrays, and stable SHA-256 identity', async () => {
  const sql = await migrationSql();
  const envelope = functionBody(sql, 'validate_benefit_publication_envelope');
  const key = functionBody(sql, 'card_scoped_benefit_key');
  assert.match(envelope, /benefit_categories[\s\S]*is_active\s*=\s*true/i);
  assert.match(envelope, /invalid_canonical_envelope_shape/i);
  assert.match(envelope, /invalid_canonical_exclusions/i);
  assert.match(envelope, /invalid_benefit_date_range/i);
  assert.match(envelope, /description[\s\S]*8_000|description[\s\S]*8000/i);
  assert.match(envelope, /offer_subject[\s\S]*semantic_key/i);
  assert.match(envelope, /value_config[\s\S]*restrictions[\s\S]*exclusions/i);
  assert.match(key, /card-benefit-v2:/i);
  assert.match(key, /canonical_benefit_condition_hash/i);
  assert.match(functionBody(sql, 'canonical_benefit_condition_hash'), /extensions\.digest[\s\S]*sha256/i);
});

test('SQL verifies the Edge canonical envelope instead of maintaining a second normalizer', async () => {
  const sql = await migrationSql();
  const approval = functionBody(sql, 'approve_card_benefit_enrichment');
  const envelope = functionBody(sql, 'validate_benefit_publication_envelope');
  assert.doesNotMatch(sql, /FUNCTION public\.canonical_benefit_json/i);
  assert.doesNotMatch(sql, /FUNCTION public\.canonical_card_benefit_terms/i);
  assert.match(approval, /canonical_envelope/i);
  assert.match(envelope, /canonical_json_text\(_envelope->'staged_proposal_binding'\)/i);
  assert.match(envelope, /_envelope->'staged_proposal_binding'\s+IS DISTINCT FROM\s+_staged_proposal/i);
  assert.match(envelope, /_envelope->>'staged_proposal_hash'[\s\S]*expected_staged_hash/i);
  assert.match(envelope, /condition_value[\s\S]*canonical_benefit_condition_hash/i);
  assert.match(envelope, /card_scoped_benefit_key\(_card_id/i);
  assert.match(approval, /validate_benefit_publication_envelope\([\s\S]*staging_row\.card_id/i);
});

test('locked retirement proof and all-action duplicate identities are enforced before mutation', async () => {
  const sql = await migrationSql();
  const approval = functionBody(sql, 'approve_card_benefit_enrichment');
  const retirement = functionBody(sql, 'validate_locked_retirement_evidence');
  assert.match(retirement, /crawl_complete[\s\S]*absent_benefit_ids[\s\S]*completeAbsenceObservedAt/i);
  assert.match(retirement, /interval '7 days'|604800/i);
  assert.match(retirement, /explicit_past_end_date/i);
  assert.match(approval, /decision_identity[\s\S]*seen_decision_identities[\s\S]*duplicate_benefit_decision/i);
  assert.match(approval, /decision_action = 'reject'[\s\S]*staging_row\.extracted_data->'proposals'->decision_proposal_index[\s\S]*unknown_benefit_proposal/i);
  assert.ok(approval.indexOf('duplicate_benefit_decision') < approval.indexOf('INSERT INTO public.benefits'));
  assert.match(sql, /retirement_v2_assertions/i);
  for (const fixture of ['incomplete', 'absent_mismatch', 'one_observation', 'less_than_seven_days', 'exact_eligible']) {
    assert.match(sql, new RegExp(fixture, 'i'));
  }
  assert.match(sql, /explicit_past_end_date_assertion/i);
  assert.match(sql, /eligibility_reason_mismatch/i);
  assert.match(sql, /publication_envelope_v2_assertions[\s\S]*card_a_key[\s\S]*card_b_key[\s\S]*canonical envelope assertion failed/i);
});

test('linked completion is card/parser/status scoped and asserts a first-review target', async () => {
  const approval = functionBody(await migrationSql(), 'approve_card_benefit_enrichment');
  assert.match(approval, /job\.staging_id\s*=\s*staging_row\.id/i);
  assert.match(approval, /job\.card_id\s*=\s*staging_row\.card_id/i);
  assert.match(approval, /job\.parser_version\s*=\s*staging_row\.parser_version/i);
  assert.match(approval, /job\.status\s*=\s*'staged'/i);
  assert.match(approval, /GET DIAGNOSTICS linked_job_count = ROW_COUNT[\s\S]*linked_job_count < 1/i);
});
