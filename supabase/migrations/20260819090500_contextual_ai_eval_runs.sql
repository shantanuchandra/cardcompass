create table public.ai_eval_runs (
  id uuid primary key default gen_random_uuid(), dataset_version bigint not null check (dataset_version > 0),
  case_manifest jsonb not null check (jsonb_typeof(case_manifest)='array' and jsonb_array_length(case_manifest) between 1 and 100),
  baseline_config_key text not null check (char_length(baseline_config_key) between 1 and 100),
  candidate_config_key text not null check (char_length(candidate_config_key) between 1 and 100),
  judge_config_key text not null check (char_length(judge_config_key) between 1 and 100),
  status text not null default 'queued' check (status in ('queued','running','completed','completed_with_failures','failed','cancelled')),
  maximum_case_count integer not null check (maximum_case_count between 1 and 100),
  cost_ceiling_usd numeric(12,6) not null check (cost_ceiling_usd > 0), per_case_max_cost_usd numeric(12,6) not null check (per_case_max_cost_usd > 0), latency_ceiling_ms integer not null check (latency_ceiling_ms > 0),
  aggregate_metrics jsonb not null default '{}'::jsonb, token_usage jsonb not null default '{}'::jsonb,
  estimated_cost_usd numeric(12,6) not null default 0 check (estimated_cost_usd >= 0), safe_failure_category text check (safe_failure_category is null or safe_failure_category in ('cost_ceiling_reached','model_unavailable','invalid_model_output','provider_failed','persistence_failed','insufficient_fixture')),
  initiated_by uuid not null references auth.users(id), request_id uuid not null,
  lease_token uuid, lease_expires_at timestamptz, created_at timestamptz not null default now(), started_at timestamptz,
  completed_at timestamptz, updated_at timestamptz not null default now(), unique (initiated_by, request_id)
);

create table public.ai_eval_results (
  id uuid primary key default gen_random_uuid(), run_id uuid not null references public.ai_eval_runs(id) on delete cascade,
  case_id uuid not null references public.ai_eval_cases(id), case_revision integer not null check (case_revision > 0), feature_key text not null,
  baseline_output jsonb not null default '{}'::jsonb, candidate_output jsonb not null default '{}'::jsonb,
  deterministic_assertions jsonb not null default '[]'::jsonb, judge_verdict jsonb not null default '{}'::jsonb,
  regression boolean not null default false, severe_regression boolean not null default false,
  baseline_latency_ms integer not null default 0 check (baseline_latency_ms >= 0), candidate_latency_ms integer not null default 0 check (candidate_latency_ms >= 0),
  baseline_input_tokens integer not null default 0 check (baseline_input_tokens >= 0), baseline_output_tokens integer not null default 0 check (baseline_output_tokens >= 0),
  candidate_input_tokens integer not null default 0 check (candidate_input_tokens >= 0), candidate_output_tokens integer not null default 0 check (candidate_output_tokens >= 0),
  estimated_cost_usd numeric(12,6) not null default 0 check (estimated_cost_usd >= 0),
  execution_status text not null check (execution_status in ('succeeded','failed')),
  safe_failure_category text check (safe_failure_category is null or safe_failure_category in ('model_unavailable','invalid_model_output','provider_failed','persistence_failed','insufficient_fixture')),
  attempt_count integer not null default 1 check (attempt_count > 0),
  claim_token uuid not null, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique (run_id, case_id, case_revision)
);

alter table public.ai_eval_runs enable row level security;
alter table public.ai_eval_results enable row level security;
revoke all on public.ai_eval_runs from public, anon, authenticated, service_role;
revoke all on public.ai_eval_results from public, anon, authenticated, service_role;
grant select on public.ai_eval_runs to service_role;
grant select on public.ai_eval_results to service_role;

create or replace function public.protect_ai_eval_storage() returns trigger
language plpgsql set search_path = '' as $$ declare run_status text; begin
  if tg_table_name='ai_eval_runs' then
    if row(old.case_manifest,old.dataset_version,old.baseline_config_key,old.candidate_config_key,old.judge_config_key,old.maximum_case_count,old.cost_ceiling_usd,old.per_case_max_cost_usd,old.latency_ceiling_ms,old.initiated_by,old.request_id,old.created_at)
       is distinct from row(new.case_manifest,new.dataset_version,new.baseline_config_key,new.candidate_config_key,new.judge_config_key,new.maximum_case_count,new.cost_ceiling_usd,new.per_case_max_cost_usd,new.latency_ceiling_ms,new.initiated_by,new.request_id,new.created_at) then raise exception 'immutable_eval_run'; end if;
    if old.status in ('completed','completed_with_failures','failed','cancelled') and not (old.status in ('completed_with_failures','failed') and new.status='queued' and new.completed_at is null and new.lease_token is null and new.lease_expires_at is null) then raise exception 'immutable_eval_run'; end if;
  else
    select status into run_status from public.ai_eval_runs where id=old.run_id;
    if run_status in ('completed','completed_with_failures','failed','cancelled') then raise exception 'immutable_eval_result'; end if;
    if old.execution_status='succeeded' then raise exception 'immutable_eval_result'; end if;
    if row(old.run_id,old.case_id,old.case_revision,old.feature_key,old.created_at)
       is distinct from row(new.run_id,new.case_id,new.case_revision,new.feature_key,new.created_at) then raise exception 'immutable_eval_result'; end if;
  end if; return new; end $$;
create trigger protect_completed_ai_eval_runs before update on public.ai_eval_runs for each row execute function public.protect_ai_eval_storage();
create trigger protect_completed_ai_eval_results before update on public.ai_eval_results for each row execute function public.protect_ai_eval_storage();

create or replace function public.admin_create_ai_eval_run(_actor_id uuid,_request_id uuid,_dataset_version bigint,_baseline_config_key text,_candidate_config_key text,_judge_config_key text,_maximum_case_count integer,_cost_ceiling_usd numeric,_latency_ceiling_ms integer) returns jsonb
language plpgsql security definer set search_path = '' as $$ declare manifest jsonb; existing public.ai_eval_runs; created public.ai_eval_runs; normalized jsonb; receipt jsonb; _per_case_max_cost_usd numeric; _candidate_feature_key text; begin
  _per_case_max_cost_usd=(case _candidate_config_key when 'gemini-3.6-flash-statement-v1' then 0.01 when 'gemini-3.6-flash-card-data-v1' then 0.02 when 'gemini-3.6-flash-recommendation-v1' then 0.03 else null end)+case when _candidate_config_key='gemini-3.6-flash-recommendation-v1' then 0.01 else 0 end;
  _candidate_feature_key=case _candidate_config_key when 'gemini-3.6-flash-statement-v1' then 'statement_processing' when 'gemini-3.6-flash-card-data-v1' then 'card_data' when 'gemini-3.6-flash-recommendation-v1' then 'recommendation' else null end;
  if _baseline_config_key<>'captured-production-v1' or _judge_config_key<>'gemini-3.6-flash-blind-judge-v1' or _per_case_max_cost_usd is null or _dataset_version<1 or _maximum_case_count not between 1 and 100 or _cost_ceiling_usd<=0 or _per_case_max_cost_usd>_cost_ceiling_usd or _latency_ceiling_ms<=0 then raise exception 'invalid_request'; end if;
  normalized=jsonb_build_object('dataset_version',_dataset_version,'baseline_config_key',_baseline_config_key,'candidate_config_key',_candidate_config_key,'judge_config_key',_judge_config_key,'maximum_case_count',_maximum_case_count,'cost_ceiling_usd',_cost_ceiling_usd,'latency_ceiling_ms',_latency_ceiling_ms,'per_case_max_cost_usd',_per_case_max_cost_usd);
  perform pg_advisory_xact_lock(hashtextextended(_actor_id::text||':'||_request_id::text,0));
  select * into existing from public.ai_eval_runs where initiated_by=_actor_id and request_id=_request_id;
  if found then if existing.dataset_version is distinct from _dataset_version or existing.baseline_config_key is distinct from _baseline_config_key or existing.candidate_config_key is distinct from _candidate_config_key or existing.judge_config_key is distinct from _judge_config_key or existing.maximum_case_count is distinct from _maximum_case_count or existing.cost_ceiling_usd is distinct from _cost_ceiling_usd or existing.per_case_max_cost_usd is distinct from _per_case_max_cost_usd or existing.latency_ceiling_ms is distinct from _latency_ceiling_ms then raise exception 'request_id_collision'; end if; return jsonb_build_object('run_id',existing.id,'status',existing.status,'case_count',jsonb_array_length(existing.case_manifest)); end if;
  with ranked as (select id,source_feedback_id,revision,feature_key,retired_in_dataset_version,row_number() over(partition by source_feedback_id order by revision desc) as rank from public.ai_eval_cases where status in ('approved','retired') and approved_in_dataset_version<=_dataset_version and feature_key=_candidate_feature_key), chosen as (select * from ranked where rank=1 and (retired_in_dataset_version is null or retired_in_dataset_version>_dataset_version) order by source_feedback_id limit _maximum_case_count) select jsonb_agg(jsonb_build_object('case_id',id,'revision',revision,'feature_key',feature_key) order by source_feedback_id) into manifest from chosen;
  if manifest is null or jsonb_array_length(manifest)=0 then raise exception 'invalid_request'; end if;
  insert into public.ai_eval_runs(dataset_version,case_manifest,baseline_config_key,candidate_config_key,judge_config_key,maximum_case_count,cost_ceiling_usd,per_case_max_cost_usd,latency_ceiling_ms,initiated_by,request_id) values(_dataset_version,manifest,_baseline_config_key,_candidate_config_key,_judge_config_key,_maximum_case_count,_cost_ceiling_usd,_per_case_max_cost_usd,_latency_ceiling_ms,_actor_id,_request_id) returning * into created;
  receipt=jsonb_build_object('run_id',created.id,'status',created.status,'case_count',jsonb_array_length(manifest));
  insert into public.admin_audit_log(actor_id,request_id,action,target_type,target_id,outcome,details) values(_actor_id,_request_id,'eval.run.create','ai_eval_run',created.id,'succeeded',jsonb_build_object('request',normalized,'result',receipt)); return receipt; end $$;

create or replace function public.claim_ai_eval_run_batch(_run_id uuid,_batch_limit integer) returns jsonb
language plpgsql security definer set search_path = '' as $$ declare run public.ai_eval_runs; token uuid; cases jsonb; available integer; begin
  if _batch_limit<1 then raise exception 'invalid_request'; end if;
  select * into run from public.ai_eval_runs where id=_run_id and status in ('queued','running') for update skip locked;
  if not found then return null; end if;
  if run.status='running' and run.lease_expires_at>=now() then return null; end if;
  select count(*) into available from jsonb_array_elements(run.case_manifest) m where not exists(select 1 from public.ai_eval_results r where r.run_id=run.id and r.case_id=(m->>'case_id')::uuid and r.case_revision=(m->>'revision')::integer and r.execution_status='succeeded');
  if run.estimated_cost_usd + least(least(_batch_limit, 5),available)*run.per_case_max_cost_usd > run.cost_ceiling_usd then update public.ai_eval_runs set status='completed_with_failures',safe_failure_category='cost_ceiling_reached',completed_at=now(),updated_at=now() where id=run.id; return jsonb_build_object('run_id',run.id,'cases','[]'::jsonb,'safe_failure_category','cost_ceiling_reached'); end if;
  token=gen_random_uuid();
  select coalesce(jsonb_agg(m order by m->>'case_id',m->>'revision'),'[]'::jsonb) into cases from (select m from jsonb_array_elements(run.case_manifest) m where not exists(select 1 from public.ai_eval_results r where r.run_id=run.id and r.case_id=(m->>'case_id')::uuid and r.case_revision=(m->>'revision')::integer and r.execution_status='succeeded') limit least(_batch_limit, 5)) q;
  update public.ai_eval_runs set status='running',lease_token=token,lease_expires_at=now()+interval '5 minutes',started_at=coalesce(started_at,now()),updated_at=now() where id=run.id;
  return jsonb_build_object('run_id',run.id,'lease_token',token,'lease_expires_at',now()+interval '5 minutes','cases',cases,'baseline_config_key',run.baseline_config_key,'candidate_config_key',run.candidate_config_key,'judge_config_key',run.judge_config_key); end $$;

create or replace function public.record_ai_eval_result(_run_id uuid,_lease_token uuid,_case_id uuid,_case_revision integer,_result jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$ declare run public.ai_eval_runs; prior public.ai_eval_results; recorded public.ai_eval_results; manifest_case jsonb; begin
  select * into run from public.ai_eval_runs where id=_run_id for update; if not found or run.status<>'running' or run.lease_token is distinct from _lease_token or run.lease_expires_at<now() then raise exception 'state_conflict'; end if;
  select m into manifest_case from jsonb_array_elements(run.case_manifest) m where (m->>'case_id')::uuid=_case_id and (m->>'revision')::integer=_case_revision; if manifest_case is null or _result->>'feature_key' is distinct from manifest_case->>'feature_key' or _result->>'execution_status' not in ('succeeded','failed') or jsonb_typeof(_result->'baseline_output')<>'object' or jsonb_typeof(_result->'candidate_output')<>'object' or jsonb_typeof(_result->'deterministic_assertions')<>'array' or jsonb_typeof(_result->'judge_verdict')<>'object' then raise exception 'invalid_request'; end if;
  select * into prior from public.ai_eval_results where run_id=_run_id and case_id=_case_id and case_revision=_case_revision for update;
  if found and prior.execution_status='succeeded' then return jsonb_build_object('result_id',prior.id,'execution_status',prior.execution_status); end if;
  if coalesce((_result->>'estimated_cost_usd')::numeric,0)>run.per_case_max_cost_usd or (select coalesce(sum(estimated_cost_usd),0) from public.ai_eval_results where run_id=_run_id) + coalesce((_result->>'estimated_cost_usd')::numeric,0) > run.cost_ceiling_usd then raise exception 'cost_ceiling_reached'; end if;
  insert into public.ai_eval_results(run_id,case_id,case_revision,feature_key,baseline_output,candidate_output,deterministic_assertions,judge_verdict,regression,severe_regression,baseline_latency_ms,candidate_latency_ms,baseline_input_tokens,baseline_output_tokens,candidate_input_tokens,candidate_output_tokens,estimated_cost_usd,execution_status,safe_failure_category,attempt_count,claim_token)
  values(_run_id,_case_id,_case_revision,_result->>'feature_key',_result->'baseline_output',_result->'candidate_output',_result->'deterministic_assertions',_result->'judge_verdict',coalesce((_result->>'regression')::boolean,false),coalesce((_result->>'severe_regression')::boolean,false),coalesce((_result->>'baseline_latency_ms')::integer,0),coalesce((_result->>'candidate_latency_ms')::integer,0),coalesce((_result->>'baseline_input_tokens')::integer,0),coalesce((_result->>'baseline_output_tokens')::integer,0),coalesce((_result->>'candidate_input_tokens')::integer,0),coalesce((_result->>'candidate_output_tokens')::integer,0),coalesce((_result->>'estimated_cost_usd')::numeric,0),_result->>'execution_status',nullif(_result->>'safe_failure_category',''),coalesce(prior.attempt_count,0)+1,_lease_token)
  on conflict(run_id,case_id,case_revision) do update set baseline_output=excluded.baseline_output,candidate_output=excluded.candidate_output,deterministic_assertions=excluded.deterministic_assertions,judge_verdict=excluded.judge_verdict,regression=excluded.regression,severe_regression=excluded.severe_regression,baseline_latency_ms=public.ai_eval_results.baseline_latency_ms+excluded.baseline_latency_ms,candidate_latency_ms=public.ai_eval_results.candidate_latency_ms+excluded.candidate_latency_ms,baseline_input_tokens=public.ai_eval_results.baseline_input_tokens+excluded.baseline_input_tokens,baseline_output_tokens=public.ai_eval_results.baseline_output_tokens+excluded.baseline_output_tokens,candidate_input_tokens=public.ai_eval_results.candidate_input_tokens+excluded.candidate_input_tokens,candidate_output_tokens=public.ai_eval_results.candidate_output_tokens+excluded.candidate_output_tokens,estimated_cost_usd=public.ai_eval_results.estimated_cost_usd+excluded.estimated_cost_usd,execution_status=excluded.execution_status,safe_failure_category=excluded.safe_failure_category,attempt_count=excluded.attempt_count,claim_token=excluded.claim_token,updated_at=now() where public.ai_eval_results.execution_status='failed'
  returning * into recorded; if not found then raise exception 'state_conflict'; end if;
  update public.ai_eval_runs set estimated_cost_usd=(select coalesce(sum(estimated_cost_usd),0) from public.ai_eval_results where run_id=_run_id),updated_at=now() where id=_run_id;
  return jsonb_build_object('result_id',recorded.id,'execution_status',recorded.execution_status); end $$;

create or replace function public.finish_ai_eval_run(_run_id uuid,_lease_token uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$ declare run public.ai_eval_runs; total integer; succeeded integer; failed integer; cost numeric; tokens jsonb; next_status text; begin
  select * into run from public.ai_eval_runs where id=_run_id for update; if not found or run.status<>'running' or run.lease_token is distinct from _lease_token then raise exception 'state_conflict'; end if;
  total=jsonb_array_length(run.case_manifest); select count(*) filter(where execution_status='succeeded'),count(*) filter(where execution_status='failed'),coalesce(sum(estimated_cost_usd),0),jsonb_build_object('baseline_input',coalesce(sum(baseline_input_tokens),0),'baseline_output',coalesce(sum(baseline_output_tokens),0),'candidate_input',coalesce(sum(candidate_input_tokens),0),'candidate_output',coalesce(sum(candidate_output_tokens),0)) into succeeded,failed,cost,tokens from public.ai_eval_results where run_id=_run_id;
  next_status=case when succeeded=total then 'completed' when succeeded+failed>=total then 'completed_with_failures' when succeeded=0 and failed>0 then 'failed' else 'completed_with_failures' end;
  update public.ai_eval_runs set status=next_status,safe_failure_category=case when succeeded=0 and failed>0 and not exists(select 1 from public.ai_eval_results where run_id=_run_id and safe_failure_category is distinct from 'insufficient_fixture') then 'insufficient_fixture' else null end,aggregate_metrics=jsonb_build_object('case_count',total,'succeeded',succeeded,'failed',failed,'missing',total-succeeded-failed,'failure_categories',(select coalesce(jsonb_object_agg(category,count),'{}'::jsonb) from (select safe_failure_category category,count(*) count from public.ai_eval_results where run_id=_run_id and execution_status='failed' and safe_failure_category is not null group by safe_failure_category) failures),'regressions',(select count(*) from public.ai_eval_results where run_id=_run_id and regression),'severe_regressions',(select count(*) from public.ai_eval_results where run_id=_run_id and severe_regression),'average_latency_ms',(select coalesce(avg(baseline_latency_ms+candidate_latency_ms),0) from public.ai_eval_results where run_id=_run_id)),token_usage=tokens,estimated_cost_usd=cost,completed_at=now(),lease_token=null,lease_expires_at=null,updated_at=now() where id=_run_id;
  return jsonb_build_object('run_id',_run_id,'status',next_status); end $$;

create or replace function public.yield_ai_eval_run(_run_id uuid,_lease_token uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$ declare run public.ai_eval_runs; begin
  select * into run from public.ai_eval_runs where id=_run_id for update;
  if not found or run.status<>'running' or run.lease_token is distinct from _lease_token or run.lease_expires_at<now() then raise exception 'state_conflict'; end if;
  update public.ai_eval_runs set lease_token=null,lease_expires_at=null,updated_at=now() where id=_run_id;
  return jsonb_build_object('run_id',_run_id,'status','running'); end $$;

create or replace function public.admin_ai_eval_run_action(_actor_id uuid,_request_id uuid,_run_id uuid,_action text) returns jsonb
language plpgsql security definer set search_path = '' as $$ declare run public.ai_eval_runs; normalized jsonb; prior jsonb; result jsonb; remaining boolean; begin
  if _action not in ('cancel','resume_failed') then raise exception 'invalid_request'; end if; normalized=jsonb_build_object('run_id',_run_id,'action',_action); perform pg_advisory_xact_lock(hashtextextended(_actor_id::text||':'||_request_id::text,0)); select details into prior from public.admin_audit_log where actor_id=_actor_id and request_id=_request_id; if found then if prior->'request' is distinct from normalized then raise exception 'request_id_collision'; end if; return prior->'result'; end if;
  select * into run from public.ai_eval_runs where id=_run_id for update; if not found then raise exception 'not_found'; end if;
  if _action='cancel' then if run.status not in ('cancelled','completed','completed_with_failures','failed') then update public.ai_eval_runs set status='cancelled',completed_at=now(),lease_token=null,lease_expires_at=null,updated_at=now() where id=_run_id; end if;
  else select exists(select 1 from jsonb_array_elements(run.case_manifest) m where not exists(select 1 from public.ai_eval_results r where r.run_id=run.id and r.case_id=(m->>'case_id')::uuid and r.case_revision=(m->>'revision')::integer and r.execution_status='succeeded')) into remaining; if run.status not in ('failed','completed_with_failures') or not remaining then raise exception 'state_conflict'; end if; update public.ai_eval_runs set status='queued',completed_at=null,safe_failure_category=null,lease_token=null,lease_expires_at=null,updated_at=now() where id=_run_id; end if;
  select jsonb_build_object('run_id',id,'status',status) into result from public.ai_eval_runs where id=_run_id; insert into public.admin_audit_log(actor_id,request_id,action,target_type,target_id,outcome,details) values(_actor_id,_request_id,'eval.run.'||_action,'ai_eval_run',_run_id,'succeeded',jsonb_build_object('request',normalized,'result',result)); return result; end $$;

revoke all on function public.admin_create_ai_eval_run(uuid,uuid,bigint,text,text,text,integer,numeric,integer) from public,anon,authenticated;
revoke all on function public.admin_ai_eval_run_action(uuid,uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.claim_ai_eval_run_batch(uuid,integer) from public,anon,authenticated;
revoke all on function public.record_ai_eval_result(uuid,uuid,uuid,integer,jsonb) from public,anon,authenticated;
revoke all on function public.finish_ai_eval_run(uuid,uuid) from public,anon,authenticated;
revoke all on function public.yield_ai_eval_run(uuid,uuid) from public,anon,authenticated;
grant execute on function public.admin_create_ai_eval_run(uuid,uuid,bigint,text,text,text,integer,numeric,integer) to service_role;
grant execute on function public.admin_ai_eval_run_action(uuid,uuid,uuid,text) to service_role;
grant execute on function public.claim_ai_eval_run_batch(uuid,integer) to service_role;
grant execute on function public.record_ai_eval_result(uuid,uuid,uuid,integer,jsonb) to service_role;
grant execute on function public.finish_ai_eval_run(uuid,uuid) to service_role;
grant execute on function public.yield_ai_eval_run(uuid,uuid) to service_role;
