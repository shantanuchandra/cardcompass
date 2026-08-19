import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
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
  assert.match(body, /normalized_request/);
  assert.match(body, /prior_details -> 'request' is distinct from normalized_request/);
  assert.doesNotMatch(body, /md5|digest/);
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

const runPostgresIntegration = process.env.RUN_ADMIN_CARD_DATA_PG_INTEGRATION === 'true';
const psqlArgs = ['-X', '-A', '-t', '--set', 'ON_ERROR_STOP=1', '--file', '-'];

function derivePgConnection(databaseUrl, databaseName) {
  const parsed = new URL(databaseUrl);
  assert.ok(
    ['postgres:', 'postgresql:'].includes(parsed.protocol),
    'integration database URL must use PostgreSQL',
  );
  assert.ok(
    parsed.hostname === '' || ['localhost', '127.0.0.1', '[::1]'].includes(parsed.hostname),
    'integration tests refuse non-loopback PostgreSQL servers',
  );
  assert.match(databaseName, /^[a-zA-Z0-9_]+$/, 'database name must be identifier-safe');

  const env = { ...process.env, PGDATABASE: databaseName };
  if (parsed.hostname) env.PGHOST = parsed.hostname;
  if (parsed.port) env.PGPORT = parsed.port;
  if (parsed.username) env.PGUSER = decodeURIComponent(parsed.username);
  if (parsed.password) env.PGPASSWORD = decodeURIComponent(parsed.password);
  if (parsed.searchParams.has('sslmode')) env.PGSSLMODE = parsed.searchParams.get('sslmode');
  if (parsed.searchParams.has('options')) env.PGOPTIONS = parsed.searchParams.get('options');

  return { env, secrets: [databaseUrl, env.PGPASSWORD].filter(Boolean) };
}

function redactSecrets(value, secrets) {
  return secrets.reduce(
    (redacted, secret) => redacted.replaceAll(secret, '[REDACTED]'),
    String(value ?? ''),
  );
}

function psql(connection, sql) {
  const result = spawnSync(
    'psql',
    psqlArgs,
    { input: sql, encoding: 'utf8', env: connection.env },
  );
  if (result.status !== 0) {
    throw new Error(
      `PostgreSQL integration command failed:\n${redactSecrets(result.stderr, connection.secrets)}`,
    );
  }
  return result.stdout.trim();
}

function psqlAsync(connection, sql) {
  return new Promise((resolve, reject) => {
    const child = spawn(
      'psql',
      psqlArgs,
      { stdio: ['pipe', 'pipe', 'pipe'], env: connection.env },
    );
    let stderr = '';
    child.stderr.setEncoding('utf8');
    child.stderr.on('data', (chunk) => { stderr += chunk; });
    child.on('error', reject);
    child.on('close', (code) => {
      if (code === 0) resolve();
      else reject(new Error(
        `PostgreSQL integration command failed:\n${redactSecrets(stderr, connection.secrets)}`,
      ));
    });
    child.stdin.end(sql);
  });
}

test('PostgreSQL connection derivation keeps credentials out of process arguments', () => {
  const connection = derivePgConnection(
    'postgresql://operator:s3cr%40t@127.0.0.1:5544/admin?sslmode=require&options=-c%20statement_timeout%3D5000',
    'disposable_test',
  );
  assert.equal(connection.env.PGHOST, '127.0.0.1');
  assert.equal(connection.env.PGPORT, '5544');
  assert.equal(connection.env.PGUSER, 'operator');
  assert.equal(connection.env.PGPASSWORD, 's3cr@t');
  assert.equal(connection.env.PGDATABASE, 'disposable_test');
  assert.equal(connection.env.PGSSLMODE, 'require');
  assert.equal(connection.env.PGOPTIONS, '-c statement_timeout=5000');
  assert.ok(psqlArgs.every((argument) => !argument.includes('s3cr')));
  assert.equal(redactSecrets('failure s3cr@t', connection.secrets), 'failure [REDACTED]');
});

test('RPC compiles and preserves transactional mutation invariants in PostgreSQL', {
  skip: runPostgresIntegration ? false : 'set RUN_ADMIN_CARD_DATA_PG_INTEGRATION=true for isolated local PostgreSQL coverage',
}, async () => {
  const adminUrl = process.env.ADMIN_CARD_DATA_TEST_ADMIN_URL ?? 'postgresql:///postgres';
  const databaseName = `admin_card_data_test_${process.pid}_${Date.now()}`;
  assert.match(databaseName, /^admin_card_data_test_\d+_\d+$/);
  const adminDatabaseName = decodeURIComponent(new URL(adminUrl).pathname.slice(1)) || 'postgres';
  const adminConnection = derivePgConnection(adminUrl, adminDatabaseName);
  const disposableConnection = derivePgConnection(adminUrl, databaseName);
  const requiredRoles = ['anon', 'authenticated', 'service_role'];
  const createdRoles = [];

  try {
    for (const role of requiredRoles) {
      const exists = psql(
        adminConnection,
        `select exists (select 1 from pg_roles where rolname = '${role}');`,
      );
      if (!exists.endsWith('t')) {
        psql(adminConnection, `create role ${role} nologin;`);
        createdRoles.push(role);
      }
    }
    psql(adminConnection, `create database "${databaseName}";`);

    const migration = await readFile(migrationUrl, 'utf8');
    const setup = `
      create schema auth;
      create table auth.users (id uuid primary key);
      create table public.admin_audit_log (
        id uuid primary key default gen_random_uuid(),
        actor_id uuid not null references auth.users(id),
        action text not null,
        target_type text not null,
        target_id text,
        reason text,
        request_id uuid not null,
        outcome text not null,
        details jsonb not null default '{}'::jsonb,
        created_at timestamptz not null default now(),
        unique (actor_id, request_id)
      );
      create table public.card_catalog_review_queue (
        id uuid primary key,
        status text not null,
        updated_at timestamptz not null
      );
      create table public.card_catalog_enrichment_jobs (
        id uuid primary key,
        card_id uuid not null,
        parser_version text not null,
        status text not null,
        staging_id uuid,
        failure_category text,
        next_retry_at timestamptz,
        lease_token uuid,
        lease_expires_at timestamptz,
        result_summary jsonb not null default '{}'::jsonb,
        updated_at timestamptz not null
      );
      create table public.card_benefits_staging (
        id uuid primary key,
        card_id uuid not null,
        status text not null
      );
      create function public.review_card_catalog_discovery(
        _review_item_id uuid, _actor_id uuid, _action text,
        _proposed_fields jsonb, _merge_card_id uuid, _reason text
      ) returns table (card_id uuid, job_id uuid, resulting_status text)
      language plpgsql as $$
      begin
        update public.card_catalog_review_queue
        set status = case when _action = 'reject' then 'rejected' else 'approved' end,
            updated_at = now()
        where id = _review_item_id;
        return query select null::uuid, _review_item_id,
          case when _action = 'reject' then 'rejected' else 'approved' end;
      end;
      $$;
      create function public.approve_card_benefit_enrichment(
        _staging_id uuid, _reviewed_by uuid, _decisions jsonb
      ) returns table (staging_id uuid, resulting_status text)
      language plpgsql as $$
      begin
        update public.card_benefits_staging set status = 'approved' where id = _staging_id;
        return query select _staging_id, 'approved'::text;
      end;
      $$;
      ${migration}
    `;
    psql(disposableConnection, setup);

    const assertions = `
      begin;
      insert into auth.users(id) values ('10000000-0000-4000-8000-000000000001');
      insert into public.card_catalog_review_queue(id, status, updated_at) values
        ('20000000-0000-4000-8000-000000000001', 'pending', '2026-08-19T09:00:00Z'),
        ('20000000-0000-4000-8000-000000000002', 'pending', '2026-08-19T09:00:00Z'),
        ('20000000-0000-4000-8000-000000000003', 'pending', '2026-08-19T09:00:00Z');
      insert into public.card_benefits_staging(id, card_id, status) values
        ('30000000-0000-4000-8000-000000000001', '40000000-0000-4000-8000-000000000002', 'pending');
      insert into public.card_catalog_enrichment_jobs(
        id, card_id, parser_version, status, staging_id, updated_at
      ) values (
        '50000000-0000-4000-8000-000000000001',
        '40000000-0000-4000-8000-000000000001',
        'benefits-v1', 'staged',
        '30000000-0000-4000-8000-000000000001',
        '2026-08-19T09:00:00Z'
      );

      do $$
      declare first_result jsonb; replay_result jsonb;
      begin
        first_result := public.admin_card_data_action(
          '10000000-0000-4000-8000-000000000001',
          '60000000-0000-4000-8000-000000000001',
          'identity', 'reject',
          '20000000-0000-4000-8000-000000000001',
          null, '{}'::jsonb, 'not a product', '2026-08-19T09:00:00Z'
        );
        replay_result := public.admin_card_data_action(
          '10000000-0000-4000-8000-000000000001',
          '60000000-0000-4000-8000-000000000001',
          'identity', 'reject',
          '20000000-0000-4000-8000-000000000001',
          null, '{}'::jsonb, 'not a product', '2026-08-19T09:00:00Z'
        );
        if first_result is distinct from replay_result then
          raise exception 'exact replay result changed';
        end if;
        if (select count(*) from public.admin_audit_log
            where request_id = '60000000-0000-4000-8000-000000000001') <> 1 then
          raise exception 'exact replay duplicated audit';
        end if;

        begin
          perform public.admin_card_data_action(
            '10000000-0000-4000-8000-000000000001',
            '60000000-0000-4000-8000-000000000001',
            'identity', 'reject',
            '20000000-0000-4000-8000-000000000001',
            null, '{}'::jsonb, 'changed reason', '2026-08-19T09:00:00Z'
          );
          raise exception 'changed request was accepted';
        exception when others then
          if sqlerrm <> 'request_id_collision' then raise; end if;
        end;

        begin
          perform public.admin_card_data_action(
            '10000000-0000-4000-8000-000000000001', gen_random_uuid(),
            'identity', 'approve',
            '20000000-0000-4000-8000-000000000002',
            null, '{}'::jsonb, null, '2026-08-19T08:59:00Z'
          );
          raise exception 'stale state was accepted';
        exception when others then
          if sqlerrm <> 'state_conflict' then raise; end if;
        end;

        begin
          perform public.admin_card_data_action(
            '10000000-0000-4000-8000-000000000001', gen_random_uuid(),
            'benefit', 'approve',
            '50000000-0000-4000-8000-000000000001',
            '30000000-0000-4000-8000-000000000001',
            '{"decisions":[{"action":"approve"}]}'::jsonb,
            null, '2026-08-19T09:00:00Z'
          );
          raise exception 'cross-card staging was accepted';
        exception when others then
          if sqlerrm <> 'state_conflict' then raise; end if;
        end;

        begin
          perform public.admin_card_data_action(
            '10000000-0000-4000-8000-000000000099', gen_random_uuid(),
            'identity', 'approve',
            '20000000-0000-4000-8000-000000000003',
            null, '{}'::jsonb, null, '2026-08-19T09:00:00Z'
          );
          raise exception 'audit foreign-key failure did not occur';
        exception when foreign_key_violation then null;
        end;
        if (select status from public.card_catalog_review_queue
            where id = '20000000-0000-4000-8000-000000000003') <> 'pending' then
          raise exception 'mutation survived audit failure';
        end if;
      end;
      $$;
      rollback;
    `;
    psql(disposableConnection, assertions);

    psql(disposableConnection, `
      insert into auth.users(id) values ('10000000-0000-4000-8000-000000000010');
      insert into public.card_catalog_review_queue(id, status, updated_at) values
        ('20000000-0000-4000-8000-000000000010', 'pending', '2026-08-19T09:00:00Z');
    `);
    const concurrentCall = `
      select public.admin_card_data_action(
        '10000000-0000-4000-8000-000000000010',
        '60000000-0000-4000-8000-000000000010',
        'identity', 'reject',
        '20000000-0000-4000-8000-000000000010',
        null, '{}'::jsonb, 'concurrent replay', '2026-08-19T09:00:00Z'
      );
    `;
    await Promise.all([
      psqlAsync(disposableConnection, concurrentCall),
      psqlAsync(disposableConnection, concurrentCall),
    ]);
    const concurrentAuditCount = psql(disposableConnection, `
      select count(*) from public.admin_audit_log
      where request_id = '60000000-0000-4000-8000-000000000010';
    `);
    assert.ok(concurrentAuditCount.endsWith('1'), 'concurrent replay must write one audit row');
  } finally {
    assert.match(databaseName, /^admin_card_data_test_\d+_\d+$/);
    try {
      psql(adminConnection, `drop database if exists "${databaseName}" with (force);`);
    } finally {
      for (const role of createdRoles.reverse()) {
        psql(adminConnection, `drop role if exists ${role};`);
      }
    }
  }
});
