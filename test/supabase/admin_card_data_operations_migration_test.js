import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const migrationUrl = new URL(
  '../../supabase/migrations/20260819090100_admin_card_data_operations.sql',
  import.meta.url,
);

async function migrationSql() {
  return (await readFile(migrationUrl, 'utf8')).toLowerCase();
}

function functionBody(sql) {
  const start = sql.indexOf('create or replace function public.admin_card_data_action');
  assert.notEqual(start, -1, 'admin_card_data_action RPC is required');
  const end = sql.indexOf('$$;', start);
  assert.notEqual(end, -1, 'admin_card_data_action must have a complete body');
  return sql.slice(start, end + 3);
}

test('card data actions are allowlisted, atomic, idempotent and service-only', async () => {
  const sql = await migrationSql();
  const body = functionBody(sql);

  assert.match(body, /security definer/);
  assert.match(body, /set search_path = ''/);
  assert.match(body, /_lane not in \('identity', 'benefit'\)/);
  assert.match(body, /_operation not in \([\s\S]*?'approve'[\s\S]*?'unquarantine'[\s\S]*?\)/);
  assert.match(body, /pg_advisory_xact_lock/);
  assert.match(body, /from public\.admin_audit_log/);
  assert.match(body, /request_fingerprint/);
  assert.match(body, /raise exception 'request_id_collision'/);
  assert.match(body, /insert into public\.admin_audit_log/);
  assert.match(body, /for update/);
  assert.match(
    sql,
    /revoke all on function public\.admin_card_data_action\([\s\S]*?timestamptz[\s\S]*?\) from public, anon, authenticated/,
  );
  assert.match(
    sql,
    /grant execute on function public\.admin_card_data_action\([\s\S]*?timestamptz[\s\S]*?\) to service_role/,
  );
});

test('lane-operation combinations and reason requirements are explicit', async () => {
  const body = functionBody(await migrationSql());

  assert.match(body, /_lane = 'identity'[\s\S]*?_operation not in \('approve', 'edit_approve', 'merge', 'reject', 'retry'\)/);
  assert.match(body, /_lane = 'benefit'[\s\S]*?_operation not in \([\s\S]*?'approve'[\s\S]*?'unquarantine'[\s\S]*?\)/);
  assert.match(body, /_operation in \('reject', 'quarantine'\)[\s\S]*?reason_required/);
  assert.match(body, /review\.status <> 'pending'[\s\S]*?state_conflict/);
  assert.match(body, /job\.parser_version\)\) = 'catalog-v1'[\s\S]*?not_found/);
});

test('benefit approvals bind the locked job to its staging row', async () => {
  const body = functionBody(await migrationSql());

  assert.match(body, /job\.staging_id is distinct from _staging_id/);
  assert.match(body, /staging\.card_id is distinct from job\.card_id/);
  assert.match(body, /public\.approve_card_benefit_enrichment/);
  assert.match(body, /update public\.card_catalog_enrichment_jobs[\s\S]*?status = 'completed'/);
});
