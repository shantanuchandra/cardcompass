import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const migrationUrl = new URL(
  '../../supabase/migrations/20260819090200_admin_runtime_controls.sql',
  import.meta.url,
);

async function migrationSql() {
  return (await readFile(migrationUrl, 'utf8')).toLowerCase();
}

test('runtime controls are one-key, audited, serialized, and service-only', async () => {
  const sql = await migrationSql();
  assert.match(sql, /create table public\.admin_runtime_controls/);
  assert.match(sql, /check \(control_key in \('benefit_enrichment_scheduled'\)\)/);
  assert.match(sql, /insert into public\.admin_runtime_controls/);
  assert.match(sql, /create or replace function public\.admin_set_runtime_control/);
  assert.match(sql, /security definer/);
  assert.match(sql, /set search_path = ''/);
  assert.match(sql, /pg_advisory_xact_lock/);
  assert.match(sql, /for update/);
  assert.match(sql, /normalized_request/);
  assert.match(sql, /prior_details -> 'request' is distinct from normalized_request/);
  assert.match(sql, /raise exception 'request_id_collision'/);
  assert.match(sql, /insert into public\.admin_audit_log/);
  assert.match(sql, /revoke all on public\.admin_runtime_controls from public, anon, authenticated/);
  assert.match(sql, /revoke all on public\.admin_runtime_controls from service_role/);
  assert.match(sql, /grant select on public\.admin_runtime_controls to service_role/);
  assert.match(sql, /grant execute on function public\.admin_set_runtime_control[\s\S]*to service_role/);
});

test('runtime-control mutation bounds its input and returned receipt', async () => {
  const sql = await migrationSql();
  assert.match(sql, /length\(pg_catalog\.btrim\(coalesce\(_reason, ''\)\)\) not between 2 and 500/);
  assert.match(sql, /_observed_updated_at is null/);
  assert.match(sql, /current_updated_at is distinct from _observed_updated_at/);
  assert.match(sql, /'control_key', _control_key/);
  assert.match(sql, /'is_paused', _is_paused/);
  assert.match(sql, /'reason', normalized_reason/);
  assert.doesNotMatch(sql, /details\s*->\s*'result'\s*@>/);
});
