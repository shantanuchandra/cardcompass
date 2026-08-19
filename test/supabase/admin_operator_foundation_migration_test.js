import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const migrationUrl = new URL(
  '../../supabase/migrations/20260819090000_admin_operator_foundation.sql',
  import.meta.url,
);

test('admin audit storage is append-only and browser-inaccessible', async () => {
  const sql = (await readFile(migrationUrl, 'utf8')).toLowerCase();
  assert.match(sql, /create table public\.admin_audit_log/);
  assert.match(sql, /unique \(actor_id, request_id\)/);
  assert.match(sql, /alter table public\.admin_audit_log enable row level security/);
  assert.match(sql, /revoke all on public\.admin_audit_log from public, anon, authenticated/);
  assert.match(sql, /revoke all on public\.admin_audit_log from service_role/);
  assert.match(sql, /grant select, insert on public\.admin_audit_log to service_role/);
  assert.match(sql, /outcome text not null check \(outcome in \('succeeded', 'failed', 'database_contained'\)\)/);
  assert.match(sql, /create or replace function public\.record_admin_read/);
  assert.match(sql, /security definer/);
  assert.match(sql, /set search_path = ''/);
  assert.match(sql, /revoke all on function public\.record_admin_read/);
});

test('admin request lookup is hardened for service-only execution', async () => {
  const sql = (await readFile(migrationUrl, 'utf8')).toLowerCase();
  const functionStart = sql.indexOf('create or replace function public.find_admin_request');
  const nextFunction = sql.indexOf('create or replace function public.record_admin_read');
  const definition = sql.slice(functionStart, nextFunction);

  assert.ok(functionStart >= 0);
  assert.ok(nextFunction > functionStart);
  assert.match(definition, /security definer/);
  assert.match(definition, /set search_path = ''/);
  assert.match(
    sql,
    /revoke all on function public\.find_admin_request\(uuid, uuid\)\s+from public, anon, authenticated/,
  );
  assert.match(
    sql,
    /grant execute on function public\.find_admin_request\(uuid, uuid\) to service_role/,
  );
});
