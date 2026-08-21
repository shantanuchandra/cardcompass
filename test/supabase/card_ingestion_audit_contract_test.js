import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const repoRoot = new URL('../../', import.meta.url);
const audit = new URL('scripts/audit-card-ingestion.sql', repoRoot);

async function auditSql() {
  return readFile(audit, 'utf8');
}

function executableSql(sql) {
  return sql
    .replace(/--[^\n]*/g, '')
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .trim();
}

test('card ingestion audit is read-only and retains every release-ticket check', async () => {
  const sql = await auditSql();
  const executable = executableSql(sql);

  assert.match(executable, /^(?:WITH\b|SELECT\b)/i);
  assert.doesNotMatch(executable, /\b(?:insert|update|delete|alter|drop|truncate|create|grant|revoke|call|do|copy)\b/i);

  for (const checkName of [
    'catalog_counts_by_discontinued',
    'benefit_exclusions_jsonb_type',
    'benefits_mapped_to_multiple_cards',
    'orphan_card_benefit_mappings',
    'duplicate_card_benefit_mappings',
    'pending_staging_age_and_count',
    'enrichment_jobs_by_status_parser_and_mode',
    'duplicate_normalized_catalog_identity',
    'submitted_final_url_key_conflicts',
    'missing_url_provenance',
    'active_user_cards_on_discontinued_catalog',
    'table_rls_state',
    'table_policies',
    'relation_grants',
    'function_grants',
  ]) {
    assert.match(sql, new RegExp(`'${checkName}'[\\s\\S]{0,80}AS\\s+check_name`, 'i'));
  }

  assert.match(sql, /jsonb_typeof\s*\(\s*benefit\.exclusions\s*\)/i);
  assert.match(sql, /pg_class/i);
  assert.match(sql, /pg_namespace/i);
  assert.match(sql, /relkind\s+IN\s*\(\s*'r'\s*,\s*'p'\s*\)/i);
  assert.doesNotMatch(sql, /WITH\s+audited_relations\s+AS/i,
    'access metadata must derive current public tables instead of a partial allowlist');
  assert.doesNotMatch(sql, /relname\s+IN\s*\(/i,
    'catalog-derived access metadata must not exclude identity, discovery, or review tables');
  assert.match(sql, /pg_policies/i);
  assert.match(sql, /information_schema\.role_table_grants/i);
  assert.match(sql, /information_schema\.routine_privileges/i);
  assert.doesNotMatch(sql, /\buser_id\b/i, 'audit output must not expose customer identifiers');
});
