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
});

test('locked staging card and exact proposal set govern canonical publication', async () => {
  const approval = functionBody(await migrationSql(), 'approve_card_benefit_enrichment');
  assert.match(approval, /FROM public\.card_benefits_staging[\s\S]*FOR UPDATE/i);
  assert.match(approval, /parser_version NOT IN \('benefits-v5', 'benefits-v6'\)/i);
  assert.match(approval, /jsonb_typeof\(staging_row\.extracted_data->'proposals'\)\s*<>\s*'array'/i);
  assert.match(approval, /jsonb_array_length\(staging_row\.extracted_data->'proposals'\)/i);
  assert.match(approval, /public\.canonical_card_benefit_terms\(staged_proposal/i);
  assert.match(approval, /public\.card_scoped_benefit_key\(staging_row\.card_id, canonical_terms\)/i);
  assert.match(approval, /staged_condition_hash[\s\S]*canonical_condition_hash[\s\S]*staged_identity_mismatch/i);
  assert.match(approval, /decision_proposal_index[\s\S]*duplicate_benefit_decision/i);
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
  const mappingUpdates = [...approval.matchAll(/UPDATE public\.card_benefit_mapping[\s\S]*?;/gi)];
  assert.ok(mappingUpdates.length >= 2, 'replacement and retirement mapping updates are required');
  for (const [statement] of mappingUpdates) {
    assert.match(statement, /card_id\s*=\s*staging_row\.card_id/i);
    assert.match(statement, /benefit_id\s*=\s*existing_benefit_id/i);
  }
  assert.match(approval, /canonical_valid_from[\s\S]*AT TIME ZONE 'UTC'[\s\S]*retired_at/i);
});

test('retirement, audit append, replay, and linked-job completion fail closed', async () => {
  const approval = functionBody(await migrationSql(), 'approve_card_benefit_enrichment');
  assert.match(approval, /decision_action NOT IN \('approve', 'edit', 'reject', 'keep_existing', 'retire'\)/i);
  assert.match(approval, /retirementEligible[\s\S]*retirementReason[\s\S]*retirement_not_eligible/i);
  assert.match(approval, /benefit_decisions\s*=\s*CASE[\s\S]*\|\|\s*audit_decisions/i);
  assert.match(approval, /source_evidence/i);
  assert.match(approval, /review_payload_hash[\s\S]*already_reviewed/i);
  assert.match(approval, /UPDATE public\.card_catalog_enrichment_jobs[\s\S]*status\s*=\s*'completed'[\s\S]*next_run_at\s*=\s*statement_timestamp\(\)\s*\+\s*interval '30 days'/i);
  assert.match(approval, /staging_id\s*=\s*staging_row\.id/i);
});

test('canonical helpers validate commercial shapes, dates, arrays, and stable SHA-256 identity', async () => {
  const sql = await migrationSql();
  const terms = functionBody(sql, 'canonical_card_benefit_terms');
  const key = functionBody(sql, 'card_scoped_benefit_key');
  assert.match(terms, /benefit_categories[\s\S]*is_active\s*=\s*true/i);
  assert.match(terms, /invalid_benefit_value_config|jsonb_typeof\(raw_value_config\)\s*<>\s*'object'/i);
  assert.match(terms, /canonical_benefit_exclusions/i);
  assert.match(functionBody(sql, 'canonical_benefit_exclusions'), /invalid_benefit_exclusions/i);
  assert.match(terms, /invalid_benefit_number/i);
  assert.match(terms, /invalid_benefit_date_range/i);
  assert.match(terms, /value_config[\s\S]*restrictions[\s\S]*exclusions/i);
  assert.match(key, /card-benefit-v2:/i);
  assert.match(key, /canonical_benefit_condition_hash/i);
  assert.match(functionBody(sql, 'canonical_benefit_condition_hash'), /extensions\.digest[\s\S]*sha256/i);
});
