import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import { derivePgConnection, dropDisposableDatabase, ensureRoles, psql, psqlAsync } from './helpers/isolated_postgres.js';

const migrationUrl = new URL('../../supabase/migrations/20260819090500_contextual_ai_eval_runs.sql', import.meta.url);
const feedbackUrl = new URL('../../supabase/migrations/20260819090400_contextual_ai_feedback.sql', import.meta.url);
const foundationUrl = new URL('../../supabase/migrations/20260819090000_admin_operator_foundation.sql', import.meta.url);

test('eval run schema exposes bounded service-only lifecycle contracts', async () => {
  const sql = (await readFile(migrationUrl, 'utf8')).toLowerCase();
  for (const table of ['ai_eval_runs', 'ai_eval_results']) {
    assert.match(sql, new RegExp(`create table public\\.${table}`));
    assert.match(sql, new RegExp(`alter table public\\.${table} enable row level security`));
    assert.match(sql, new RegExp(`revoke all on public\\.${table} from public, anon, authenticated, service_role`));
  }
  assert.match(sql, /maximum_case_count between 1 and 100/);
  assert.match(sql, /cost_ceiling_usd > 0/);
  assert.match(sql, /unique \(run_id, case_id, case_revision\)/);
  assert.match(sql, /for update skip locked/);
  assert.match(sql, /least\(greatest\(_batch_limit, 1\), 5\)/);
  for (const rpc of ['admin_create_ai_eval_run', 'admin_ai_eval_run_action', 'claim_ai_eval_run_batch', 'record_ai_eval_result', 'finish_ai_eval_run']) {
    assert.match(sql, new RegExp(`function public\\.${rpc}`));
    assert.match(sql, new RegExp(`grant execute on function public\\.${rpc}[^;]+ to service_role`));
  }
  assert.match(sql, /create trigger protect_completed_ai_eval/);
});

test('eval lifecycle is idempotent, fenced, bounded, resumable and immutable in PostgreSQL', { skip: !process.env.CONTEXTUAL_EVAL_TEST_ADMIN_URL }, async () => {
  const adminUrl = process.env.CONTEXTUAL_EVAL_TEST_ADMIN_URL;
  const databaseName = `cardcompass_eval_${process.pid}_${Date.now()}`;
  const admin = derivePgConnection(adminUrl, decodeURIComponent(new URL(adminUrl).pathname.slice(1)) || 'postgres', process.env);
  const disposable = derivePgConnection(adminUrl, databaseName, process.env);
  const createdRoles = ensureRoles(admin, ['anon', 'authenticated', 'service_role']);
  try {
    psql(admin, `create database "${databaseName}";`);
    const [foundation, feedback, migration] = await Promise.all([readFile(foundationUrl, 'utf8'), readFile(feedbackUrl, 'utf8'), readFile(migrationUrl, 'utf8')]);
    psql(disposable, `create extension if not exists pgcrypto; create schema auth; create table auth.users(id uuid primary key); ${foundation} ${feedback} ${migration}`);
    psql(disposable, `
      insert into auth.users values ('10000000-0000-4000-8000-000000000001');
      insert into public.ai_feedback(id,user_id,feature_key,output_ref_type,output_ref_id,feedback_text,request_id) values
        ('30000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','card_data','user_card','x','Useful feedback','40000000-0000-4000-8000-000000000001');
      insert into public.ai_eval_cases(id,source_feedback_id,feature_key,revision,input_fixture,captured_output,expected_output,operator_feedback,scoring_rubric,severe_failure_conditions,status,approved_in_dataset_version,created_by)
      values ('50000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001','card_data',1,'{}','{}','{}','expected','{}','{}','approved',1,'10000000-0000-4000-8000-000000000001');`);
    const create = `select public.admin_create_ai_eval_run('10000000-0000-4000-8000-000000000001','60000000-0000-4000-8000-000000000001',1,'captured-production-v1','candidate-v1','judge-v1',100,1.0,25000);`;
    await Promise.all([psqlAsync(disposable, create), psqlAsync(disposable, create)]);
    assert.equal(psql(disposable, `select count(*) from public.ai_eval_runs;`), '1');
    const runId = psql(disposable, `select id from public.ai_eval_runs;`);
    const claim = JSON.parse(psql(disposable, `select public.claim_ai_eval_run_batch('${runId}',5,0.10);`));
    assert.equal(claim.cases.length, 1);
    assert.throws(() => psql(disposable, `select public.record_ai_eval_result('${runId}','00000000-0000-0000-0000-000000000000','50000000-0000-4000-8000-000000000001',1,'{}');`), /state_conflict/);
    psql(disposable, `select public.record_ai_eval_result('${runId}','${claim.lease_token}','50000000-0000-4000-8000-000000000001',1,'{"feature_key":"card_data","baseline_output":{},"candidate_output":{},"deterministic_assertions":[],"judge_verdict":{},"regression":false,"severe_regression":false,"baseline_latency_ms":1,"candidate_latency_ms":2,"baseline_input_tokens":1,"baseline_output_tokens":1,"candidate_input_tokens":1,"candidate_output_tokens":1,"estimated_cost_usd":0.01,"execution_status":"succeeded","safe_failure_category":null}');`);
    psql(disposable, `select public.finish_ai_eval_run('${runId}','${claim.lease_token}');`);
    assert.equal(psql(disposable, `select status from public.ai_eval_runs;`), 'completed');
    assert.throws(() => psql(disposable, `update public.ai_eval_results set regression=true;`), /immutable_eval_result/);
  } finally { dropDisposableDatabase(admin, databaseName, createdRoles); }
});
