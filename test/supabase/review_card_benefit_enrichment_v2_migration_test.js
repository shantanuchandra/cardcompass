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
  const sql = await migrationSql();
  const approval = functionBody(sql, 'approve_card_benefit_enrichment');
  const proposals = functionBody(sql, 'validate_locked_benefit_proposals');
  assert.match(approval, /FROM public\.card_benefits_staging[\s\S]*FOR UPDATE/i);
  assert.match(approval, /parser_version NOT IN \('benefits-v5', 'benefits-v6'\)/i);
  assert.match(approval, /decision_proposal_index\s*:=\s*\(decision->>'proposal_index'\)::integer[\s\S]*staging_row\.extracted_data->'proposals'->decision_proposal_index/i);
  assert.match(approval, /validate_benefit_publication_envelope\([\s\S]*staging_row\.card_id[\s\S]*staged_proposal/i);
  assert.match(approval, /decision_proposal_index[\s\S]*seen_decision_identities[\s\S]*duplicate_benefit_decision/i);
  assert.match(approval, /superseded_by_newer_crawl|superseded_staging/i);
  assert.match(approval, /validate_locked_benefit_proposals\(\s*staging_row\.extracted_data->'proposals',\s*staging_row\.parser_version\s*\)/i);
  assert.match(proposals, /octet_length[\s\S]*MAX_STAGED_PROPOSALS_BYTES/i);
  assert.match(proposals, /canonical_json_shape_is_bounded[\s\S]*MAX_CANONICAL_KEY_CHARS/i);
  assert.match(proposals, /jsonb_object_keys[\s\S]*unknown_staged_proposal_key/i);
  assert.match(proposals, /canonical_json_numbers_are_safe/i);
  assert.match(proposals, /GROUP BY[\s\S]*(?:dedupeKey|dedupe_key)[\s\S]*HAVING count\(\*\)\s*>\s*1/i);
  assert.match(sql, /locked_proposal_v2_assertions[\s\S]*oversized_unselected[\s\S]*unknown_unselected[\s\S]*duplicate_unselected[\s\S]*deep_unselected[\s\S]*wide_unselected[\s\S]*valid_multi/i);
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
  assert.match(approval, /SET retired_at\s*=\s*coalesce\(retired_at, statement_timestamp\(\)\)/i);
  assert.match(approval, /staged_change_type[\s\S]*identity_migration[\s\S]*existing_mapping_not_found/i);
  assert.match(approval, /audit_decision[\s\S]*identity_migration/i);
});

test('legacy replacement identity is derived from locked diff and never from client change type', async () => {
  const approval = functionBody(await migrationSql(), 'approve_card_benefit_enrichment');
  assert.match(approval, /SELECT modification\.value->>'changeType'[\s\S]*INTO staged_change_type/i);
  assert.match(approval, /modification\.value->'current'->>'liveBenefitId'/i);
  assert.match(approval, /modification\.value->'proposed'[\s\S]*staged_proposal/i);
  assert.match(approval, /decision->>'change_type'[\s\S]*client_publication_authority_rejected/i);
  assert.match(approval, /staged_change_type\s*=\s*'identity_migration'[\s\S]*identity_migration_must_be_explicit/i);
  assert.ok(
    approval.indexOf('staged_change_type') < approval.indexOf('INSERT INTO public.benefits'),
    'identity migration must bind before mutation',
  );
});

test('retirement, audit append, replay, and linked-job completion fail closed', async () => {
  const sql = await migrationSql();
  const approval = functionBody(sql, 'approve_card_benefit_enrichment');
  const retirement = functionBody(sql, 'validate_locked_retirement_evidence');
  assert.match(approval, /decision_action NOT IN \('approve', 'edit', 'reject', 'keep_existing', 'retire'\)/i);
  assert.match(retirement, /retirementEligible[\s\S]*retirementReason[\s\S]*retirement_not_eligible/i);
  assert.match(approval, /benefit_decisions\s*=\s*CASE[\s\S]*\|\|\s*audit_decisions/i);
  assert.match(approval, /source_evidence/i);
  assert.match(approval, /jsonb_array_length\(staging_row\.source_evidence\)\s*>\s*MAX_SOURCE_EVIDENCE_ITEMS[\s\S]*octet_length[\s\S]*MAX_SOURCE_EVIDENCE_BYTES/i);
  assert.match(approval, /audit_source_evidence[\s\S]*evidence_attached[\s\S]*source_evidence/i);
  assert.match(approval, /jsonb_array_length\(_decisions\)\s*>\s*MAX_DECISIONS[\s\S]*octet_length[\s\S]*MAX_REVIEW_BYTES/i);
  assert.match(approval, /length\(coalesce\(decision->>'reason'[\s\S]*>\s*MAX_CANONICAL_STRING_CHARS/i);
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
  assert.match(envelope, /jsonb_object_keys\(_envelope\)[\s\S]*unknown_canonical_envelope_key/i);
  assert.match(envelope, /jsonb_object_keys\(condition_value\)[\s\S]*unknown_canonical_condition_key/i);
  assert.match(envelope, /jsonb_object_keys\(condition_value->'value_config'\)[\s\S]*unknown_canonical_value_config_key/i);
  assert.match(envelope, /0\.000001|1e-6/i);
  assert.match(envelope, /1000000000000000000000|1e21/i);
  assert.match(envelope, /9007199254740991/i);
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
  assert.match(sql, /unknown_key_assertion[\s\S]*unsafe_numeric_assertion/i);
  assert.match(sql, /category_alias_identity_migration[\s\S]*legacy_condition_hash[\s\S]*legacy_dedupe_key/i);
});

test('linked completion is card/parser/status scoped and asserts a first-review target', async () => {
  const approval = functionBody(await migrationSql(), 'approve_card_benefit_enrichment');
  assert.match(approval, /job\.staging_id\s*=\s*staging_row\.id/i);
  assert.match(approval, /job\.card_id\s*=\s*staging_row\.card_id/i);
  assert.match(approval, /job\.parser_version\s*=\s*staging_row\.parser_version/i);
  assert.match(approval, /job\.status\s*=\s*'staged'/i);
  assert.match(approval, /GET DIAGNOSTICS linked_job_count = ROW_COUNT[\s\S]*linked_job_count < 1/i);
});

test('Edge and SQL publication limits have one exact named boundary contract', async () => {
  const sql = await migrationSql();
  const limitsSource = await readFile(
    new URL('supabase/functions/_shared/benefit_publication_limits.ts', repoRoot),
    'utf8',
  );
  const expected = {
    MAX_DECISIONS: 64,
    MAX_CANONICAL_ARRAY_ITEMS: 64,
    MAX_CANONICAL_STRING_CHARS: 500,
    MAX_CONDITION_BYTES: 32768,
    MAX_BENEFIT_BYTES: 65536,
    MAX_ENVELOPE_BYTES: 131072,
    MAX_REVIEW_BYTES: 262144,
    MAX_SOURCE_EVIDENCE_ITEMS: 32,
    MAX_SOURCE_EVIDENCE_BYTES: 32768,
    MAX_CANONICAL_DEPTH: 8,
    MAX_CANONICAL_KEYS: 256,
    MAX_CANONICAL_KEY_CHARS: 500,
    MAX_STAGED_PROPOSALS: 64,
    MAX_STAGED_PROPOSALS_BYTES: 131072,
    MAX_STAGED_STRING_CHARS: 8000,
  };
  for (const [name, value] of Object.entries(expected)) {
    assert.match(limitsSource, new RegExp(`${name}:\\s*${value}\\b`));
    const declarations = [
      ...sql.matchAll(
        new RegExp(`${name}\\s+constant\\s+integer\\s*:=\\s*(\\d+)\\b`, 'gi'),
      ),
    ];
    assert.ok(declarations.length > 0, `${name} SQL declaration is required`);
    assert.deepEqual(
      declarations.map((match) => Number(match[1])),
      declarations.map(() => value),
      `${name} SQL declarations drifted from the Edge limit`,
    );
  }
});

test('Task 2 active view owns the exact UTC lifecycle boundary used by Task 4 reads', async () => {
  const lifecycle = await readFile(
    new URL('supabase/migrations/20260819112813_card_ingestion_lifecycle_hardening.sql', repoRoot),
    'utf8',
  );
  const view = lifecycle.match(
    /CREATE OR REPLACE VIEW public\.active_card_benefits[\s\S]*?;/i,
  )?.[0];
  assert.ok(view, 'Task 2 active lifecycle view is required');
  assert.match(view, /timezone\(\s*'UTC'\s*,\s*statement_timestamp\(\)\s*\)::date AS utc_date/i);
  assert.match(view, /mapping\.retired_at IS NULL\s+OR mapping\.retired_at\s*>\s*now\(\)/i);
  assert.match(view, /benefit\.valid_from IS NULL\s+OR benefit\.valid_from\s*<=\s*database_clock\.utc_date/i);
  assert.match(view, /benefit\.valid_until IS NULL\s+OR benefit\.valid_until\s*>=\s*database_clock\.utc_date/i);
});
