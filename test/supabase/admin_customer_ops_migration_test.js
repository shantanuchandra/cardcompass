import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import {
  derivePgConnection,
  dropDisposableDatabase,
  ensureRoles,
  psql,
  psqlAsync,
} from './helpers/isolated_postgres.js';

const migrationUrl = new URL(
  '../../supabase/migrations/20260819090300_admin_customer_ops.sql',
  import.meta.url,
);

async function migrationSql() {
  return (await readFile(migrationUrl, 'utf8')).toLowerCase();
}

function functionBody(sql, name) {
  const start = sql.indexOf(`create or replace function public.${name}`);
  assert.notEqual(start, -1, `${name} is required`);
  const end = sql.indexOf('$$;', start);
  assert.notEqual(end, -1, `${name} must have a complete body`);
  return sql.slice(start, end + 3);
}

test('active account state is server-owned and gates every user-data policy', async () => {
  const sql = await migrationSql();
  assert.match(sql, /create or replace function public\.current_user_is_active\(\)/);
  assert.match(functionBody(sql, 'current_user_is_active'), /security definer/);
  assert.match(functionBody(sql, 'current_user_is_active'), /set search_path = ''/);
  assert.match(sql, /revoke insert, update on table public\.users from authenticated/);
  assert.doesNotMatch(sql, /grant (?:insert|update) \([^)]*(?:is_active|is_admin)/);

  for (const [table, owner] of [
    ['users', 'id'],
    ['user_cards', 'user_id'],
    ['transactions', 'user_id'],
    ['statements', 'user_id'],
    ['statement_milestone_cache', 'user_id'],
    ['emails', 'user_id'],
    ['benefit_platform_confirmations', 'user_id'],
  ]) {
    const policySegments = [...sql.matchAll(new RegExp(
      `create policy [^;]*?on public\\.${table}([^;]*?);`, 'g',
    ))].map((match) => match[1]);
    assert.ok(policySegments.length > 0, `${table} needs replacement policies`);
    for (const policy of policySegments) {
      if (table === 'users' && /for insert/.test(policy)) continue;
      assert.match(policy, /public\.current_user_is_active\(\)/, `${table} must check active state`);
      assert.match(policy, new RegExp(`auth\\.uid\\(\\)\\) = ${owner}`), `${table} must remain owner-scoped`);
    }
  }
});

test('customer operation tables are private and expose only narrow role-specific RPCs', async () => {
  const sql = await migrationSql();
  for (const table of ['admin_customer_operation_requests', 'account_deletion_requests']) {
    assert.match(sql, new RegExp(`create table public\\.${table}`));
    assert.match(sql, new RegExp(`alter table public\\.${table} enable row level security`));
    assert.match(sql, new RegExp(`revoke all on public\\.${table} from public, anon, authenticated`));
    assert.doesNotMatch(sql, new RegExp(`grant [^;]+ on public\\.${table} to (?:anon|authenticated)`));
  }
  assert.match(sql, /operation_type text not null check \(operation_type in \('gmail_sync'\)\)/);
  assert.match(sql, /claim_token uuid/);
  assert.match(sql, /claim_expires_at timestamptz/);
  assert.match(sql, /create unique index[\s\S]*?where status in \('queued', 'claimed'\)/);
  assert.doesNotMatch(sql, /account_deletion_requests[\s\S]{0,300}on delete cascade/);
  assert.match(sql, /grant execute on function public\.claim_my_admin_operation_request\(text\) to authenticated/);
  assert.match(sql, /grant execute on function public\.complete_my_admin_operation_request\(uuid, uuid, boolean, text\) to authenticated/);
  assert.match(sql, /grant execute on function public\.renew_my_admin_operation_request\(uuid, uuid\) to authenticated/);
  assert.match(sql, /grant execute on function public\.admin_customer_action\([\s\S]*?timestamptz\s*\) to service_role/);
});

test('user operation RPCs derive and enforce the current active owner', async () => {
  const sql = await migrationSql();
  const claim = functionBody(sql, 'claim_my_admin_operation_request');
  const complete = functionBody(sql, 'complete_my_admin_operation_request');
  const renew = functionBody(sql, 'renew_my_admin_operation_request');
  assert.match(claim, /auth\.uid\(\)/);
  assert.match(claim, /public\.current_user_is_active\(\)/);
  assert.match(claim, /status = 'queued'/);
  assert.match(claim, /status = 'claimed'[\s\S]*claim_expires_at <= now\(\)/);
  assert.match(claim, /for update skip locked/);
  assert.match(claim, /new_claim_token uuid := gen_random_uuid\(\)/);
  assert.match(claim, /claim_token = new_claim_token/);
  assert.match(claim, /claim_expires_at = now\(\) \+ interval '10 minutes'/);
  assert.match(complete, /auth\.uid\(\)/);
  assert.match(complete, /public\.current_user_is_active\(\)/);
  assert.match(complete, /status = 'claimed'/);
  assert.match(complete, /claim_token = _claim_token/);
  assert.match(complete, /claim_token = null[\s\S]*claim_expires_at = null/);
  assert.match(renew, /auth\.uid\(\)/);
  assert.match(renew, /for update/);
  assert.match(renew, /status = 'claimed'/);
  assert.match(renew, /claim_token = _claim_token/);
  assert.match(renew, /claim_expires_at = now\(\) \+ interval '10 minutes'/);
  assert.match(complete, /reauthentication_required[\s\S]*gmail_unavailable[\s\S]*processing_failed/);
});

test('admin customer actions are canonical, serialized, audited, and non-destructive', async () => {
  const sql = await migrationSql();
  const body = functionBody(sql, 'admin_customer_action');
  assert.match(body, /_action not in \('request_gmail_sync', 'disable_account', 'set_deletion_status'\)/);
  assert.match(body, /pg_advisory_xact_lock/);
  assert.match(body, /from public\.admin_audit_log/);
  assert.match(body, /prior_details -> 'request' is distinct from normalized_request/);
  assert.match(body, /raise exception 'request_id_collision'/);
  assert.match(body, /_target_user_id = _actor_id[\s\S]*self_disable_denied/);
  assert.match(body, /for update/);
  assert.match(body, /_observed_updated_at is null[\s\S]*?state_conflict/);
  assert.match(body, /insert into public\.admin_audit_log/);
  assert.doesNotMatch(body, /delete from|auth\.users/);
  assert.match(body, /requested|verified|scheduled|completed|cancelled/);
});

const runPostgresIntegration = process.env.RUN_ADMIN_CUSTOMER_PG_INTEGRATION === 'true';

test('inactive profile immediately blocks an unchanged authenticated database session', {
  skip: runPostgresIntegration
    ? false
    : 'set RUN_ADMIN_CUSTOMER_PG_INTEGRATION=true for isolated local PostgreSQL coverage',
}, async () => {
  const adminUrl = process.env.ADMIN_CUSTOMER_TEST_ADMIN_URL
    ?? 'postgresql:///postgres';
  const databaseName = `admin_customer_test_${process.pid}_${Date.now()}`;
  const adminDatabaseName = decodeURIComponent(new URL(adminUrl).pathname.slice(1)) || 'postgres';
  const adminConnection = derivePgConnection(adminUrl, adminDatabaseName);
  const disposableConnection = derivePgConnection(adminUrl, databaseName);
  let createdRoles = [];
  try {
    createdRoles = ensureRoles(adminConnection, ['anon', 'authenticated', 'service_role']);
    psql(adminConnection, `create database "${databaseName}";`);
    const foundation = await readFile(new URL(
      '../../supabase/migrations/20260819090000_admin_operator_foundation.sql',
      import.meta.url,
    ), 'utf8');
    const customer = await readFile(migrationUrl, 'utf8');
    psql(disposableConnection, `
      create schema auth;
      create table auth.users (id uuid primary key);
      create function auth.uid() returns uuid language sql stable as
        $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
      create table public.users (
        id uuid primary key references auth.users(id), email text, full_name text,
        avatar_url text, phone text, created_at timestamptz default now(),
        updated_at timestamptz default now(), preferences jsonb default '{}',
        given_name text, family_name text, date_of_birth date,
        profile_data jsonb default '{}', is_active boolean not null default true,
        is_admin boolean not null default false
      );
      create table public.user_cards (id uuid primary key default gen_random_uuid(), user_id uuid not null);
      create table public.transactions (id uuid primary key default gen_random_uuid(), user_id uuid not null);
      create table public.statements (id uuid primary key default gen_random_uuid(), user_id uuid not null);
      create table public.statement_milestone_cache (id uuid primary key default gen_random_uuid(), user_id uuid not null);
      create table public.emails (id uuid primary key default gen_random_uuid(), user_id uuid not null);
      create table public.benefit_platform_confirmations (id uuid primary key default gen_random_uuid(), user_id uuid not null);
      alter table public.users enable row level security;
      alter table public.user_cards enable row level security;
      alter table public.transactions enable row level security;
      alter table public.statements enable row level security;
      alter table public.statement_milestone_cache enable row level security;
      alter table public.emails enable row level security;
      alter table public.benefit_platform_confirmations enable row level security;
      grant select, insert, update, delete on all tables in schema public to authenticated;
      ${foundation}
      ${customer}
    `);
    const userId = '10000000-0000-4000-8000-000000000001';
    const newUserId = '10000000-0000-4000-8000-000000000002';
    psql(disposableConnection, `
      insert into auth.users(id) values ('${userId}'), ('${newUserId}');
      insert into public.users(id, email) values ('${userId}', 'local@example.test');
      set role authenticated;
      select set_config('request.jwt.claim.sub', '${newUserId}', false);
      insert into public.users(id, email, full_name)
      values ('${newUserId}', 'new@example.test', 'New User');
      update public.users set full_name = 'Updated User' where id = '${newUserId}';
      reset role;
      do $$ begin
        if not exists (
          select 1 from public.users where id = '${newUserId}'
            and is_active and not is_admin and full_name = 'Updated User'
        ) then raise exception 'legitimate profile write failed'; end if;
      end $$;
      set role authenticated;
      select set_config('request.jwt.claim.sub', '${userId}', false);
      insert into public.user_cards(user_id) values ('${userId}');
      do $$ begin
        begin update public.users set is_active = false where id = '${userId}';
          raise exception 'browser changed is_active';
        exception when insufficient_privilege then null; end;
      end $$;
      reset role;
      update public.users set is_active = false where id = '${userId}';
      set role authenticated;
      select set_config('request.jwt.claim.sub', '${userId}', false);
      do $$ begin
        if exists (select 1 from public.user_cards where user_id = '${userId}') then
          raise exception 'inactive read accepted';
        end if;
        begin insert into public.user_cards(user_id) values ('${userId}');
          raise exception 'inactive insert accepted';
        exception when insufficient_privilege or check_violation then null; end;
      end $$;
      reset role;
    `);
    const actorId = '20000000-0000-4000-8000-000000000001';
    psql(disposableConnection, `
      insert into auth.users(id) values ('${actorId}');
      insert into public.users(id, email, is_admin) values ('${actorId}', 'operator@example.test', true);
      update public.users set is_active = true, updated_at = clock_timestamp()
      where id = '${userId}';
    `);
    const requestId = '30000000-0000-4000-8000-000000000001';
    const recoveryObserved = psql(disposableConnection, `select updated_at from public.users where id = '${userId}';`);
    const recoverySql = `select public.admin_customer_action(
      '${actorId}', '${requestId}', 'request_gmail_sync', '${userId}',
      '{}'::jsonb, null, '${recoveryObserved}'::timestamptz
    );`;
    await Promise.all([
      psqlAsync(disposableConnection, recoverySql),
      psqlAsync(disposableConnection, recoverySql),
    ]);
    assert.ok(psql(disposableConnection, `
      select count(*) from public.admin_audit_log
      where actor_id = '${actorId}' and request_id = '${requestId}';
    `).endsWith('1'));
    assert.ok(psql(disposableConnection, `
      select count(*) from public.admin_customer_operation_requests
      where user_id = '${userId}' and status in ('queued', 'claimed');
    `).endsWith('1'));
    assert.throws(() => psql(disposableConnection, `
      select public.admin_customer_action(
        '${actorId}', '${requestId}', 'request_gmail_sync', '${userId}',
        '{}'::jsonb, null, '${recoveryObserved}'::timestamptz + interval '1 second'
      );
    `), /request_id_collision/);

    const claimSql = `
      set role authenticated;
      select set_config('request.jwt.claim.sub', '${userId}', false);
      select public.claim_my_admin_operation_request('gmail_sync');
      reset role;
    `;
    await Promise.all([
      psqlAsync(disposableConnection, claimSql),
      psqlAsync(disposableConnection, claimSql),
    ]);
    assert.ok(psql(disposableConnection, `
      select count(*) from public.admin_customer_operation_requests
      where user_id = '${userId}' and status = 'claimed';
    `).endsWith('1'));
    const operationId = psql(disposableConnection, `
      select id from public.admin_customer_operation_requests
      where user_id = '${userId}';
    `);
    const firstClaimToken = psql(disposableConnection, `
      select claim_token from public.admin_customer_operation_requests
      where id = '${operationId}';
    `);
    const renewedUntil = psql(disposableConnection, `
      set role authenticated;
      select set_config('request.jwt.claim.sub', '${userId}', false);
      select public.renew_my_admin_operation_request(
        '${operationId}', '${firstClaimToken}'
      ) > now() + interval '9 minutes';
      reset role;
    `);
    assert.ok(renewedUntil.includes('t'));
    psql(disposableConnection, claimSql);
    assert.equal(psql(disposableConnection, `
      select claim_token from public.admin_customer_operation_requests
      where id = '${operationId}';
    `), firstClaimToken, 'an actively renewed claim cannot be reclaimed');
    assert.throws(() => psql(disposableConnection, `
      set role authenticated;
      select set_config('request.jwt.claim.sub', '${newUserId}', false);
      select public.renew_my_admin_operation_request(
        '${operationId}', '${firstClaimToken}'
      );
      reset role;
    `), /state_conflict/);
    assert.throws(() => psql(disposableConnection, `
      set role authenticated;
      select set_config('request.jwt.claim.sub', '${newUserId}', false);
      select public.complete_my_admin_operation_request(
        '${operationId}', '${firstClaimToken}', false, 'gmail_unavailable'
      );
      reset role;
    `), /state_conflict/);
    psql(disposableConnection, `
      update public.admin_customer_operation_requests
      set claim_expires_at = now() - interval '1 second'
      where id = '${operationId}';
    `);
    psql(disposableConnection, claimSql);
    const currentClaimToken = psql(disposableConnection, `
      select claim_token from public.admin_customer_operation_requests
      where id = '${operationId}';
    `);
    assert.notEqual(currentClaimToken, firstClaimToken);
    assert.throws(() => psql(disposableConnection, `
      set role authenticated;
      select set_config('request.jwt.claim.sub', '${userId}', false);
      select public.renew_my_admin_operation_request(
        '${operationId}', '${firstClaimToken}'
      );
      reset role;
    `), /state_conflict/);
    assert.throws(() => psql(disposableConnection, `
      set role authenticated;
      select set_config('request.jwt.claim.sub', '${userId}', false);
      select public.complete_my_admin_operation_request(
        '${operationId}', '${firstClaimToken}', false, 'gmail_unavailable'
      );
      reset role;
    `), /state_conflict/);
    psql(disposableConnection, `
      set role authenticated;
      select set_config('request.jwt.claim.sub', '${userId}', false);
      select public.renew_my_admin_operation_request(
        '${operationId}', '${currentClaimToken}'
      );
      select public.complete_my_admin_operation_request(
        '${operationId}', '${currentClaimToken}', false, 'gmail_unavailable'
      );
      reset role;
    `);
    assert.ok(psql(disposableConnection, `
      select status = 'failed' and safe_failure_category = 'gmail_unavailable'
      from public.admin_customer_operation_requests where id = '${operationId}';
    `).endsWith('t'));

    const observed = psql(disposableConnection, `select updated_at from public.users where id = '${userId}';`);
    assert.throws(() => psql(disposableConnection, `
      select public.admin_customer_action(
        '${actorId}', gen_random_uuid(), 'disable_account', '${userId}',
        '{}'::jsonb, 'contain account', '${new Date(0).toISOString()}'::timestamptz
      );
    `), /state_conflict/);
    psql(disposableConnection, `update public.users set is_active=true where id='${userId}';`);
    const currentObserved = psql(disposableConnection, `select updated_at from public.users where id = '${userId}';`);
    psql(disposableConnection, `
      select public.admin_customer_action(
        '${actorId}', gen_random_uuid(), 'disable_account', '${userId}',
        '{}'::jsonb, 'contain account', '${currentObserved}'::timestamptz
      );
    `);
    assert.ok(psql(disposableConnection, `select not is_active from public.users where id='${userId}';`).endsWith('t'));
    assert.ok(observed.length > 0);
  } finally {
    dropDisposableDatabase(adminConnection, databaseName, createdRoles);
  }
});
