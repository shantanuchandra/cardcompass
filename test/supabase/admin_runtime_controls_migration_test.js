import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import {
  derivePgConnection,
  dropDisposableDatabase,
  ensureRoles,
  psql,
  psqlAsync,
  psqlArgs,
} from './helpers/isolated_postgres.js';

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

test('shared PostgreSQL harness neutralizes inherited libpq selectors and argv secrets', () => {
  const connection = derivePgConnection(
    'postgresql://operator:s3cr%40t@127.0.0.1:5544/admin?sslmode=require',
    'runtime_test',
    {
      PATH: process.env.PATH,
      PGHOST: 'attacker.example', PGHOSTADDR: '203.0.113.5', PGPORT: '1',
      PGDATABASE: 'production', PGUSER: 'wrong', PGPASSWORD: 'wrong',
      PGSERVICE: 'production', PGSERVICEFILE: '/tmp/hostile', PGOPTIONS: '-c search_path=hostile',
    },
  );
  assert.equal(connection.env.PGHOST, '127.0.0.1');
  assert.equal(connection.env.PGPORT, '5544');
  assert.equal(connection.env.PGDATABASE, 'runtime_test');
  assert.equal(connection.env.PGUSER, 'operator');
  assert.equal(connection.env.PGPASSWORD, 's3cr@t');
  assert.equal(connection.env.PGSERVICE, undefined);
  assert.equal(connection.env.PGHOSTADDR, undefined);
  assert.equal(connection.env.PGOPTIONS, undefined);
  assert.equal(connection.env.HOME, undefined);
  assert.ok(psqlArgs.every((argument) => !argument.includes('s3cr')));
  const socket = derivePgConnection('postgresql:///postgres', 'runtime_socket', {});
  assert.equal(socket.env.PGHOST, '/tmp');
  assert.equal(socket.env.PGPORT, '5432');
});

test('shared PostgreSQL harness cleans partial role ownership before rethrowing', () => {
  const commands = [];
  const existing = new Set();
  const runPsql = (_connection, sql) => {
    commands.push(sql);
    if (sql.startsWith('select exists')) return 'f';
    if (sql === 'create role anon nologin;') {
      existing.add('anon');
      return '';
    }
    if (sql === 'create role authenticated nologin;') {
      throw new Error('simulated role creation failure');
    }
    if (sql === 'drop role if exists anon;') {
      existing.delete('anon');
      return '';
    }
    throw new Error(`unexpected command: ${sql}`);
  };
  assert.throws(
    () => ensureRoles({}, ['anon', 'authenticated', 'service_role'], runPsql),
    /simulated role creation failure/,
  );
  assert.deepEqual([...existing], []);
  assert.deepEqual(commands.slice(-2), [
    'create role authenticated nologin;',
    'drop role if exists anon;',
  ]);
});

const runPostgresIntegration = process.env.RUN_ADMIN_RUNTIME_CONTROL_PG_INTEGRATION === 'true';

test('runtime control RPC preserves replay, concurrency, rollback, and grants in PostgreSQL', {
  skip: runPostgresIntegration ? false : 'set RUN_ADMIN_RUNTIME_CONTROL_PG_INTEGRATION=true for isolated local PostgreSQL coverage',
}, async () => {
  const adminUrl = process.env.ADMIN_RUNTIME_CONTROL_TEST_ADMIN_URL
    ?? 'postgresql://127.0.0.1:5432/postgres';
  const databaseName = `admin_runtime_test_${process.pid}_${Date.now()}`;
  assert.match(databaseName, /^admin_runtime_test_\d+_\d+$/);
  const adminDatabaseName = decodeURIComponent(new URL(adminUrl).pathname.slice(1)) || 'postgres';
  const adminConnection = derivePgConnection(adminUrl, adminDatabaseName);
  const disposableConnection = derivePgConnection(adminUrl, databaseName);
  let createdRoles = [];
  try {
    createdRoles = ensureRoles(adminConnection, ['anon', 'authenticated', 'service_role']);
    psql(adminConnection, `create database "${databaseName}";`);
    const foundation = await readFile(new URL('../../supabase/migrations/20260819090000_admin_operator_foundation.sql', import.meta.url), 'utf8');
    const runtime = await readFile(migrationUrl, 'utf8');
    psql(disposableConnection, `create schema auth; create table auth.users (id uuid primary key); ${foundation} ${runtime}`);
    psql(disposableConnection, `
      insert into auth.users(id) values ('10000000-0000-4000-8000-000000000001');
      do $$
      declare observed timestamptz; first_result jsonb; replay_result jsonb; second_result jsonb;
      begin
        select updated_at into observed from public.admin_runtime_controls where control_key = 'benefit_enrichment_scheduled';
        first_result := public.admin_set_runtime_control(
          '10000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001',
          'benefit_enrichment_scheduled', true, 'provider outage', observed);
        replay_result := public.admin_set_runtime_control(
          '10000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001',
          'benefit_enrichment_scheduled', true, 'provider outage', observed);
        if first_result is distinct from replay_result then raise exception 'replay changed'; end if;
        if (select count(*) from public.admin_audit_log where request_id = '20000000-0000-4000-8000-000000000001') <> 1 then raise exception 'replay duplicated audit'; end if;
        if (first_result->>'updated_at')::timestamptz <= observed then raise exception 'timestamp not monotonic'; end if;
        begin
          perform public.admin_set_runtime_control(
            '10000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001',
            'benefit_enrichment_scheduled', true, 'changed reason', observed);
          raise exception 'collision accepted';
        exception when others then if sqlerrm <> 'request_id_collision' then raise; end if; end;
        begin
          perform public.admin_set_runtime_control(
            '10000000-0000-4000-8000-000000000001', gen_random_uuid(),
            'benefit_enrichment_scheduled', false, 'missing version', null);
          raise exception 'missing version accepted';
        exception when others then if sqlerrm <> 'state_conflict' then raise; end if; end;
        begin
          perform public.admin_set_runtime_control(
            '10000000-0000-4000-8000-000000000001', gen_random_uuid(),
            'benefit_enrichment_scheduled', false, 'stale version', observed);
          raise exception 'stale version accepted';
        exception when others then if sqlerrm <> 'state_conflict' then raise; end if; end;
      end $$;
      set role authenticated;
      do $$ begin
        begin perform 1 from public.admin_runtime_controls; raise exception 'browser read accepted';
        exception when insufficient_privilege then null; end;
      end $$;
      reset role;
    `);

    const observed = psql(disposableConnection, `select updated_at from public.admin_runtime_controls where control_key='benefit_enrichment_scheduled';`);
    const concurrentSql = `select public.admin_set_runtime_control(
      '10000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000002',
      'benefit_enrichment_scheduled', false, 'outage recovered', '${observed}'::timestamptz);`;
    await Promise.all([psqlAsync(disposableConnection, concurrentSql), psqlAsync(disposableConnection, concurrentSql)]);
    assert.ok(psql(disposableConnection, `select count(*) from public.admin_audit_log where request_id='20000000-0000-4000-8000-000000000002';`).endsWith('1'));

    const beforeRollback = psql(disposableConnection, `select is_paused||':'||updated_at::text from public.admin_runtime_controls;`);
    psql(disposableConnection, `create function public.reject_runtime_audit() returns trigger language plpgsql as $$ begin if new.request_id='20000000-0000-4000-8000-000000000003' then raise exception 'forced_audit_failure'; end if; return new; end $$; create trigger reject_runtime_audit before insert on public.admin_audit_log for each row execute function public.reject_runtime_audit();`);
    const rollbackObserved = psql(disposableConnection, `select updated_at from public.admin_runtime_controls;`);
    assert.throws(() => psql(disposableConnection, `select public.admin_set_runtime_control('10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000003','benefit_enrichment_scheduled',true,'force rollback','${rollbackObserved}'::timestamptz);`), /forced_audit_failure/);
    assert.equal(psql(disposableConnection, `select is_paused||':'||updated_at::text from public.admin_runtime_controls;`), beforeRollback);
  } finally {
    dropDisposableDatabase(adminConnection, databaseName, createdRoles);
  }
});
