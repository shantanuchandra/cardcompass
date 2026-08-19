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
  assert.match(sql, /least\(_batch_limit, 5\)/);
  assert.doesNotMatch(sql, /_maximum_projected_cost_per_case/);
  assert.match(sql, /per_case_max_cost_usd > 0/);
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
      values ('50000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001','card_data',1,'{}','{}','{}','expected','{}','{}','approved',1,'10000000-0000-4000-8000-000000000001');
      insert into public.ai_eval_cases(id,source_feedback_id,feature_key,revision,supersedes_case_id,input_fixture,captured_output,expected_output,operator_feedback,scoring_rubric,severe_failure_conditions,status,approved_in_dataset_version,retired_in_dataset_version,retired_at,created_by)
      values ('50000000-0000-4000-8000-000000000002','30000000-0000-4000-8000-000000000001','card_data',2,'50000000-0000-4000-8000-000000000001','{}','{}','{}','revised','{}','{}','retired',2,3,now(),'10000000-0000-4000-8000-000000000001');`);
    const create = `select public.admin_create_ai_eval_run('10000000-0000-4000-8000-000000000001','60000000-0000-4000-8000-000000000001',1,'captured-production-v1','gemini-3.6-flash-card-data-v1','gemini-3.6-flash-blind-judge-v1',100,1.0,25000);`;
    await Promise.all([psqlAsync(disposable, create), psqlAsync(disposable, create)]);
    assert.equal(psql(disposable, `select count(*) from public.ai_eval_runs;`), '1');
    const runId = psql(disposable, `select id from public.ai_eval_runs;`);
    assert.equal(psql(disposable, `select case_manifest->0->>'revision' from public.ai_eval_runs where id='${runId}';`), '1');
    const claim = JSON.parse(psql(disposable, `select public.claim_ai_eval_run_batch('${runId}',99);`));
    assert.equal(claim.cases.length, 1);
    assert.throws(() => psql(disposable, `select public.claim_ai_eval_run_batch('${runId}',0);`), /invalid_request/);
    assert.throws(() => psql(disposable, `select public.record_ai_eval_result('${runId}','00000000-0000-0000-0000-000000000000','50000000-0000-4000-8000-000000000001',1,'{}');`), /state_conflict/);
    assert.throws(() => psql(disposable, `select public.record_ai_eval_result('${runId}','${claim.lease_token}','50000000-0000-4000-8000-000000000001',2,'{}');`), /invalid_request/);
    psql(disposable, `select public.record_ai_eval_result('${runId}','${claim.lease_token}','50000000-0000-4000-8000-000000000001',1,'{"feature_key":"card_data","baseline_output":{},"candidate_output":{},"deterministic_assertions":[],"judge_verdict":{},"regression":false,"severe_regression":false,"baseline_latency_ms":1,"candidate_latency_ms":2,"baseline_input_tokens":1,"baseline_output_tokens":1,"candidate_input_tokens":1,"candidate_output_tokens":1,"estimated_cost_usd":0.01,"execution_status":"succeeded","safe_failure_category":null}');`);
    psql(disposable, `select public.finish_ai_eval_run('${runId}','${claim.lease_token}');`);
    assert.equal(psql(disposable, `select status from public.ai_eval_runs;`), 'completed');
    assert.throws(() => psql(disposable, `update public.ai_eval_results set regression=true;`), /immutable_eval_result/);
    assert.throws(() => psql(disposable, `set role service_role; insert into public.ai_eval_results(run_id,case_id,case_revision,feature_key,execution_status,claim_token) values('${runId}','50000000-0000-4000-8000-000000000001',1,'card_data','failed',gen_random_uuid());`), /permission denied/);
    assert.throws(() => psql(disposable, `set role service_role; update public.ai_eval_runs set status='queued' where id='${runId}';`), /permission denied/);
    assert.throws(() => psql(disposable, `set role service_role; delete from public.ai_eval_results;`), /permission denied/);
    psql(disposable, `
      insert into public.ai_feedback(id,user_id,feature_key,output_ref_type,output_ref_id,feedback_text,request_id)
      select md5('feedback'||i)::uuid,'10000000-0000-4000-8000-000000000001','card_data','user_card',i::text,'Useful generated feedback',md5('request'||i)::uuid from generate_series(1,6) i;
      insert into public.ai_eval_cases(id,source_feedback_id,feature_key,revision,input_fixture,captured_output,expected_output,operator_feedback,scoring_rubric,severe_failure_conditions,status,approved_in_dataset_version,created_by)
      select md5('case'||i)::uuid,md5('feedback'||i)::uuid,'card_data',1,'{}','{}','{}','expected','{}','{}','approved',1,'10000000-0000-4000-8000-000000000001' from generate_series(1,6) i;
      insert into public.ai_feedback(id,user_id,feature_key,output_ref_type,output_ref_id,feedback_text,request_id) values('30000000-0000-4000-8000-000000000099','10000000-0000-4000-8000-000000000001','recommendation','recommendation_trace','mixed','Mixed feature feedback','40000000-0000-4000-8000-000000000099');
      insert into public.ai_eval_cases(id,source_feedback_id,feature_key,revision,input_fixture,captured_output,expected_output,operator_feedback,scoring_rubric,severe_failure_conditions,status,approved_in_dataset_version,created_by) values('50000000-0000-4000-8000-000000000099','30000000-0000-4000-8000-000000000099','recommendation',1,'{}','{}','{}','expected','{}','{}','approved',1,'10000000-0000-4000-8000-000000000001');`);
    const versionTwo = JSON.parse(psql(disposable, `select public.admin_create_ai_eval_run('10000000-0000-4000-8000-000000000001','60000000-0000-4000-8000-000000000002',2,'captured-production-v1','gemini-3.6-flash-card-data-v1','gemini-3.6-flash-blind-judge-v1',100,1.0,25000);`));
    assert.equal(psql(disposable, `select count(*) from jsonb_array_elements((select case_manifest from public.ai_eval_runs where id='${versionTwo.run_id}')) m where m->>'case_id'='50000000-0000-4000-8000-000000000002';`), '1');
    assert.equal(psql(disposable, `select count(*) from jsonb_array_elements((select case_manifest from public.ai_eval_runs where id='${versionTwo.run_id}')) m where m->>'case_id'='50000000-0000-4000-8000-000000000001';`), '0');
    assert.equal(psql(disposable, `select count(*) from jsonb_array_elements((select case_manifest from public.ai_eval_runs where id='${versionTwo.run_id}')) m where m->>'feature_key'<>'card_data';`), '0');
    const versionThree = JSON.parse(psql(disposable, `select public.admin_create_ai_eval_run('10000000-0000-4000-8000-000000000001','60000000-0000-4000-8000-000000000099',3,'captured-production-v1','gemini-3.6-flash-card-data-v1','gemini-3.6-flash-blind-judge-v1',100,1.0,25000);`));
    assert.equal(psql(disposable, `select count(*) from jsonb_array_elements((select case_manifest from public.ai_eval_runs where id='${versionThree.run_id}')) m where m->>'case_id' in ('50000000-0000-4000-8000-000000000001','50000000-0000-4000-8000-000000000002');`), '0');
    assert.throws(() => psql(disposable, `select public.admin_create_ai_eval_run('10000000-0000-4000-8000-000000000001',gen_random_uuid(),2,'captured-production-v1','gemini-3.6-flash-statement-v1','gemini-3.6-flash-blind-judge-v1',100,1.0,25000);`), /invalid_request/);
    const five = JSON.parse(psql(disposable, `select public.claim_ai_eval_run_batch('${versionTwo.run_id}',99);`));
    assert.equal(five.cases.length, 5);
    const retryCase = five.cases[0];
    const resultPayload = (status, cost) => JSON.stringify({ feature_key: retryCase.feature_key, baseline_output: {}, candidate_output: {}, deterministic_assertions: [], judge_verdict: {}, regression: false, severe_regression: false, baseline_latency_ms: 1, candidate_latency_ms: 2, baseline_input_tokens: 1, baseline_output_tokens: 1, candidate_input_tokens: 1, candidate_output_tokens: 1, estimated_cost_usd: cost, execution_status: status, safe_failure_category: status === 'failed' ? 'provider_failed' : null });
    assert.throws(() => psql(disposable, `select public.record_ai_eval_result('${versionTwo.run_id}','${five.lease_token}','${retryCase.case_id}',${retryCase.revision},'${resultPayload('succeeded', 1.01)}');`), /cost_ceiling_reached/);
    psql(disposable, `select public.record_ai_eval_result('${versionTwo.run_id}','${five.lease_token}','${retryCase.case_id}',${retryCase.revision},'${resultPayload('failed', 0.01)}');`);
    psql(disposable, `select public.record_ai_eval_result('${versionTwo.run_id}','${five.lease_token}','${retryCase.case_id}',${retryCase.revision},'${resultPayload('succeeded', 0.01)}');`);
    assert.equal(psql(disposable, `select execution_status||':'||attempt_count||':'||estimated_cost_usd from public.ai_eval_results where run_id='${versionTwo.run_id}' and case_id='${retryCase.case_id}';`), 'succeeded:2:0.020000');
    assert.throws(() => psql(disposable, `select public.admin_create_ai_eval_run('10000000-0000-4000-8000-000000000001',gen_random_uuid(),2,'captured-production-v1','unknown','gemini-3.6-flash-blind-judge-v1',100,1.0,25000);`), /invalid_request/);
    const cancelRequest = '60000000-0000-4000-8000-000000000003';
    psql(disposable, `select public.admin_ai_eval_run_action('10000000-0000-4000-8000-000000000001','${cancelRequest}','${versionTwo.run_id}','cancel'); select public.admin_ai_eval_run_action('10000000-0000-4000-8000-000000000001','${cancelRequest}','${versionTwo.run_id}','cancel');`);
    assert.equal(psql(disposable, `select count(*) from public.admin_audit_log where request_id='${cancelRequest}';`), '1');
    assert.equal(psql(disposable, `select count(*) from public.ai_eval_results where run_id='${versionTwo.run_id}' and execution_status='succeeded';`), '1');
    const resumable = JSON.parse(psql(disposable, `select public.admin_create_ai_eval_run('10000000-0000-4000-8000-000000000001','60000000-0000-4000-8000-000000000004',2,'captured-production-v1','gemini-3.6-flash-card-data-v1','gemini-3.6-flash-blind-judge-v1',100,0.03,25000);`));
    const one = JSON.parse(psql(disposable, `select public.claim_ai_eval_run_batch('${resumable.run_id}',1);`));
    const successCase = one.cases[0];
    const successPayload = JSON.stringify({ feature_key: successCase.feature_key, baseline_output: {}, candidate_output: {}, deterministic_assertions: [], judge_verdict: {}, regression: false, severe_regression: false, estimated_cost_usd: 0.01, execution_status: 'succeeded', safe_failure_category: null });
    psql(disposable, `select public.record_ai_eval_result('${resumable.run_id}','${one.lease_token}','${successCase.case_id}',${successCase.revision},'${successPayload}'); update public.ai_eval_runs set lease_expires_at=now()-interval '1 second' where id='${resumable.run_id}';`);
    const stopped = JSON.parse(psql(disposable, `select public.claim_ai_eval_run_batch('${resumable.run_id}',2);`));
    assert.equal(stopped.safe_failure_category, 'cost_ceiling_reached');
    const resumeRequest = '60000000-0000-4000-8000-000000000005';
    psql(disposable, `create function public.reject_eval_audit() returns trigger language plpgsql as $$ begin if new.request_id='${resumeRequest}' then raise exception 'forced_audit_failure'; end if; return new; end $$; create trigger reject_eval_audit before insert on public.admin_audit_log for each row execute function public.reject_eval_audit();`);
    assert.throws(() => psql(disposable, `select public.admin_ai_eval_run_action('10000000-0000-4000-8000-000000000001','${resumeRequest}','${resumable.run_id}','resume_failed');`), /forced_audit_failure/);
    assert.equal(psql(disposable, `select status from public.ai_eval_runs where id='${resumable.run_id}';`), 'completed_with_failures');
    psql(disposable, `drop trigger reject_eval_audit on public.admin_audit_log; drop function public.reject_eval_audit();`);
    psql(disposable, `select public.admin_ai_eval_run_action('10000000-0000-4000-8000-000000000001','${resumeRequest}','${resumable.run_id}','resume_failed');`);
    assert.equal(psql(disposable, `select status from public.ai_eval_runs where id='${resumable.run_id}';`), 'queued');
    assert.equal(psql(disposable, `select count(*) from public.ai_eval_results where run_id='${resumable.run_id}' and execution_status='succeeded';`), '1');
  } finally { dropDisposableDatabase(admin, databaseName, createdRoles); }
});
