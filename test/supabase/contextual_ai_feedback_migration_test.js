import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import { derivePgConnection, dropDisposableDatabase, ensureRoles, psql, psqlAsync } from './helpers/isolated_postgres.js';

const migrationUrl = new URL('../../supabase/migrations/20260819090400_contextual_ai_feedback.sql', import.meta.url);

test('feedback storage and RPCs are private, bounded, idempotent, and audited', async () => {
  const sql = (await readFile(migrationUrl, 'utf8')).toLowerCase();
  for (const table of ['ai_output_traces', 'ai_feedback', 'ai_eval_cases']) {
    assert.match(sql, new RegExp(`create table public\\.${table}`));
    assert.match(sql, new RegExp(`alter table public\\.${table} enable row level security`));
    assert.match(sql, new RegExp(`revoke all on public\\.${table} from public, anon, authenticated`));
    assert.match(sql, new RegExp(`grant (select, insert|select, insert, update) on public\\.${table} to service_role`));
  }
  assert.match(sql, /expires_at <= created_at \+ interval '7 days'/);
  assert.match(sql, /feature_key in \('statement_processing', 'card_data', 'recommendation'\)/);
  assert.match(sql, /char_length\(feedback_text\) between 10 and 2000/);
  assert.match(sql, /create sequence public\.ai_eval_dataset_version_seq start with 1/);
  assert.match(sql, /unique \(source_feedback_id, revision\)/);
  for (const fn of ['create_ai_output_trace', 'submit_ai_feedback', 'claim_ai_feedback_triage', 'complete_ai_feedback_triage', 'admin_review_ai_feedback', 'admin_ai_eval_case_action']) {
    const start = sql.indexOf(`create or replace function public.${fn}`);
    assert.ok(start >= 0, `${fn} exists`);
    const body = sql.slice(start, sql.indexOf('\ncreate or replace function', start + 1) < 0 ? undefined : sql.indexOf('\ncreate or replace function', start + 1));
    assert.match(body, /security definer/);
    assert.match(body, /set search_path = ''/);
    assert.match(sql, new RegExp(`revoke all on function public\\.${fn}[\\s\\S]*?from public, anon, authenticated`));
    assert.match(sql, new RegExp(`grant execute on function public\\.${fn}[\\s\\S]*?to service_role`));
  }
  assert.match(sql, /pg_advisory_xact_lock/);
  assert.match(sql, /request_id_collision/);
  assert.match(sql, /insert into public\.admin_audit_log/);
  assert.match(sql, /observed_updated_at/);
  assert.match(sql, /for update skip locked/);
  assert.doesNotMatch(sql, /grant .*ai_(output_traces|feedback|eval_cases).*authenticated/);
});

const runPg = process.env.RUN_CONTEXTUAL_FEEDBACK_PG_INTEGRATION === 'true';
test('feedback RPCs compile and preserve replay, claims, human revisions, versions, grants, and rollback', {
  skip: runPg ? false : 'set RUN_CONTEXTUAL_FEEDBACK_PG_INTEGRATION=true for isolated local PostgreSQL coverage',
}, async () => {
  const adminUrl = process.env.CONTEXTUAL_FEEDBACK_TEST_ADMIN_URL ?? 'postgresql://127.0.0.1:5432/postgres';
  const databaseName = `contextual_feedback_test_${process.pid}_${Date.now()}`;
  const adminDatabaseName = decodeURIComponent(new URL(adminUrl).pathname.slice(1)) || 'postgres';
  const admin = derivePgConnection(adminUrl, adminDatabaseName);
  const disposable = derivePgConnection(adminUrl, databaseName);
  let roles = [];
  try {
    roles = ensureRoles(admin, ['anon', 'authenticated', 'service_role']);
    psql(admin, `create database "${databaseName}";`);
    const foundation = await readFile(new URL('../../supabase/migrations/20260819090000_admin_operator_foundation.sql', import.meta.url), 'utf8');
    const migration = await readFile(migrationUrl, 'utf8');
    psql(disposable, `create extension if not exists pgcrypto; create schema auth; create table auth.users(id uuid primary key); ${foundation} ${migration}`);
    psql(disposable, `
      insert into auth.users(id) values ('10000000-0000-4000-8000-000000000001'),('10000000-0000-4000-8000-000000000002');
      do $$ declare first jsonb; replay jsonb; claimed jsonb; reviewed jsonb; approved jsonb; revised jsonb; observed timestamptz; begin
        first := public.submit_ai_feedback('10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','card_data','user_card','30000000-0000-4000-8000-000000000001','This is the wrong matched card','{}','{}','{}');
        replay := public.submit_ai_feedback('10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','card_data','user_card','30000000-0000-4000-8000-000000000001','This is the wrong matched card','{}','{}','{}');
        if first is distinct from replay or (select count(*) from public.ai_feedback)<>1 then raise exception 'replay failed'; end if;
        begin perform public.submit_ai_feedback('10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','card_data','user_card','30000000-0000-4000-8000-000000000001','Changed collision content','{}','{}','{}'); raise exception 'collision accepted'; exception when others then if sqlerrm<>'request_id_collision' then raise; end if; end;
        claimed := public.claim_ai_feedback_triage((first->>'id')::uuid); if claimed->>'feedback_text'<>'This is the wrong matched card' then raise exception 'claim fixture'; end if;
        if public.claim_ai_feedback_triage((first->>'id')::uuid) is not null then raise exception 'double claim'; end if;
        perform public.complete_ai_feedback_triage((first->>'id')::uuid,false,'{}','model_unavailable');
        if public.claim_ai_feedback_triage((first->>'id')::uuid) is null then raise exception 'failed retry not claimable'; end if;
        perform public.complete_ai_feedback_triage((first->>'id')::uuid,true,'{"classification":"model_error"}',null);
        reviewed := public.admin_review_ai_feedback('10000000-0000-4000-8000-000000000002','20000000-0000-4000-8000-000000000002',(first->>'id')::uuid,'create_eval_draft','{"operator_feedback":"Use the current card identity","expected_output":{"card":"correct"},"scoring_rubric":{"exact":true},"severe_failure_conditions":{"wrong_card":true}}','approved fixture');
        begin perform public.admin_review_ai_feedback('10000000-0000-4000-8000-000000000002','20000000-0000-4000-8000-000000000002',(first->>'id')::uuid,'dismiss','{}','changed request'); raise exception 'admin collision accepted'; exception when others then if sqlerrm<>'request_id_collision' then raise; end if; end;
        select updated_at into observed from public.ai_eval_cases where id=(reviewed->>'case_id')::uuid;
        approved := public.admin_ai_eval_case_action('10000000-0000-4000-8000-000000000002','20000000-0000-4000-8000-000000000003',(reviewed->>'case_id')::uuid,'approve','{}','human approval',observed);
        select updated_at into observed from public.ai_eval_cases where id=(reviewed->>'case_id')::uuid;
        revised := public.admin_ai_eval_case_action('10000000-0000-4000-8000-000000000002','20000000-0000-4000-8000-000000000004',(reviewed->>'case_id')::uuid,'revise','{"operator_feedback":"Revised ground truth","expected_output":{"card":"new"},"scoring_rubric":{"exact":true},"severe_failure_conditions":{"wrong_card":true}}','new evidence',observed);
        if approved->>'dataset_version'<>'1' or revised->>'revision'<>'2' or (select status from public.ai_eval_cases where id=(reviewed->>'case_id')::uuid)<>'approved' then raise exception 'version lifecycle'; end if;
      end $$;
      set role authenticated;
      do $$ begin begin perform 1 from public.ai_feedback; raise exception 'browser read accepted'; exception when insufficient_privilege then null; end; end $$;
      reset role;
    `);
    const feedbackId = psql(disposable, `select id from public.ai_feedback limit 1;`);
    psql(disposable, `update public.ai_feedback set review_status='pending', reviewed_by=null, reviewed_at=null where id='${feedbackId}'; create function public.reject_feedback_audit() returns trigger language plpgsql as $$ begin if new.request_id='20000000-0000-4000-8000-000000000005' then raise exception 'forced_audit_failure'; end if; return new; end $$; create trigger reject_feedback_audit before insert on public.admin_audit_log for each row execute function public.reject_feedback_audit();`);
    assert.throws(() => psql(disposable, `select public.admin_review_ai_feedback('10000000-0000-4000-8000-000000000002','20000000-0000-4000-8000-000000000005','${feedbackId}','dismiss','{}','not actionable');`), /forced_audit_failure/);
    assert.equal(psql(disposable, `select review_status from public.ai_feedback where id='${feedbackId}';`), 'pending');
    await Promise.all([
      psqlAsync(disposable, `select public.submit_ai_feedback('10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000006','card_data','user_card','30000000-0000-4000-8000-000000000001','Concurrent feedback request','{}','{}','{}');`),
      psqlAsync(disposable, `select public.submit_ai_feedback('10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000006','card_data','user_card','30000000-0000-4000-8000-000000000001','Concurrent feedback request','{}','{}','{}');`),
    ]);
    assert.equal(psql(disposable, `select count(*) from public.ai_feedback where request_id='20000000-0000-4000-8000-000000000006';`), '1');
  } finally { dropDisposableDatabase(admin, databaseName, roles); }
});
