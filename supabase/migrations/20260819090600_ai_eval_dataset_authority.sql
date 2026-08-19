-- A committed lifecycle cursor is the authority for the current eval dataset.
-- It advances transactionally with case approval/retirement and is never
-- inferred from whichever rows happen to remain approved.
create table public.ai_eval_dataset_state (
  singleton boolean primary key default true check (singleton),
  current_version bigint not null default 0 check (current_version >= 0),
  updated_at timestamptz not null default now()
);

insert into public.ai_eval_dataset_state(singleton,current_version)
select true,coalesce(greatest(max(approved_in_dataset_version),max(retired_in_dataset_version)),0)
from public.ai_eval_cases;

alter table public.ai_eval_dataset_state enable row level security;
revoke all on public.ai_eval_dataset_state from public, anon, authenticated, service_role;

create or replace function public.advance_ai_eval_dataset_state() returns trigger
language plpgsql security definer set search_path = '' as $$
declare lifecycle_version bigint;
begin
  lifecycle_version=greatest(coalesce(new.approved_in_dataset_version,0),coalesce(new.retired_in_dataset_version,0));
  if lifecycle_version>0 then
    insert into public.ai_eval_dataset_state(singleton,current_version,updated_at)
    values(true,lifecycle_version,now())
    on conflict(singleton) do update set current_version=greatest(public.ai_eval_dataset_state.current_version,excluded.current_version),updated_at=case when excluded.current_version>public.ai_eval_dataset_state.current_version then now() else public.ai_eval_dataset_state.updated_at end;
  end if;
  return new;
end $$;
create trigger advance_ai_eval_dataset_state after insert or update of approved_in_dataset_version,retired_in_dataset_version on public.ai_eval_cases for each row execute function public.advance_ai_eval_dataset_state();

create or replace function public.current_ai_eval_dataset_version() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('dataset_version',current_version) from public.ai_eval_dataset_state where singleton=true
$$;
revoke all on function public.current_ai_eval_dataset_version() from public, anon, authenticated;
grant execute on function public.current_ai_eval_dataset_version() to service_role;

create or replace function public.admin_create_ai_eval_run(_actor_id uuid,_request_id uuid,_dataset_version bigint,_baseline_config_key text,_candidate_config_key text,_judge_config_key text,_maximum_case_count integer,_cost_ceiling_usd numeric,_latency_ceiling_ms integer) returns jsonb
language plpgsql security definer set search_path = '' as $$ declare manifest jsonb; existing public.ai_eval_runs; created public.ai_eval_runs; normalized jsonb; receipt jsonb; _per_case_max_cost_usd numeric; _candidate_feature_key text; _current_dataset_version bigint; begin
  _per_case_max_cost_usd=(case _candidate_config_key when 'gemini-3.6-flash-statement-v1' then 0.01 when 'gemini-3.6-flash-card-data-v1' then 0.02 when 'gemini-3.6-flash-recommendation-v1' then 0.03 else null end)+case when _candidate_config_key='gemini-3.6-flash-recommendation-v1' then 0.01 else 0 end;
  _candidate_feature_key=case _candidate_config_key when 'gemini-3.6-flash-statement-v1' then 'statement_processing' when 'gemini-3.6-flash-card-data-v1' then 'card_data' when 'gemini-3.6-flash-recommendation-v1' then 'recommendation' else null end;
  if _baseline_config_key<>'captured-production-v1' or _judge_config_key<>'gemini-3.6-flash-blind-judge-v1' or _per_case_max_cost_usd is null or _dataset_version<1 or _maximum_case_count not between 1 and 100 or _cost_ceiling_usd<=0 or _per_case_max_cost_usd>_cost_ceiling_usd or _latency_ceiling_ms<=0 then raise exception 'invalid_request'; end if;
  normalized=jsonb_build_object('dataset_version',_dataset_version,'baseline_config_key',_baseline_config_key,'candidate_config_key',_candidate_config_key,'judge_config_key',_judge_config_key,'maximum_case_count',_maximum_case_count,'cost_ceiling_usd',_cost_ceiling_usd,'latency_ceiling_ms',_latency_ceiling_ms,'per_case_max_cost_usd',_per_case_max_cost_usd);
  perform pg_advisory_xact_lock(hashtextextended(_actor_id::text||':'||_request_id::text,0));
  select * into existing from public.ai_eval_runs where initiated_by=_actor_id and request_id=_request_id;
  if found then if existing.dataset_version is distinct from _dataset_version or existing.baseline_config_key is distinct from _baseline_config_key or existing.candidate_config_key is distinct from _candidate_config_key or existing.judge_config_key is distinct from _judge_config_key or existing.maximum_case_count is distinct from _maximum_case_count or existing.cost_ceiling_usd is distinct from _cost_ceiling_usd or existing.per_case_max_cost_usd is distinct from _per_case_max_cost_usd or existing.latency_ceiling_ms is distinct from _latency_ceiling_ms then raise exception 'request_id_collision'; end if; return jsonb_build_object('run_id',existing.id,'status',existing.status,'case_count',jsonb_array_length(existing.case_manifest)); end if;
  select current_version into _current_dataset_version from public.ai_eval_dataset_state where singleton=true for update;
  if _current_dataset_version is null or _current_dataset_version=0 then raise exception 'invalid_request'; end if;
  if _dataset_version is distinct from _current_dataset_version then raise exception 'state_conflict'; end if;
  with ranked as (select id,source_feedback_id,revision,feature_key,retired_in_dataset_version,row_number() over(partition by source_feedback_id order by revision desc) as rank from public.ai_eval_cases where status in ('approved','retired') and approved_in_dataset_version<=_dataset_version and feature_key=_candidate_feature_key), chosen as (select * from ranked where rank=1 and (retired_in_dataset_version is null or retired_in_dataset_version>_dataset_version) order by source_feedback_id limit _maximum_case_count) select jsonb_agg(jsonb_build_object('case_id',id,'revision',revision,'feature_key',feature_key) order by source_feedback_id) into manifest from chosen;
  if manifest is null or jsonb_array_length(manifest)=0 then raise exception 'invalid_request'; end if;
  insert into public.ai_eval_runs(dataset_version,case_manifest,baseline_config_key,candidate_config_key,judge_config_key,maximum_case_count,cost_ceiling_usd,per_case_max_cost_usd,latency_ceiling_ms,initiated_by,request_id) values(_dataset_version,manifest,_baseline_config_key,_candidate_config_key,_judge_config_key,_maximum_case_count,_cost_ceiling_usd,_per_case_max_cost_usd,_latency_ceiling_ms,_actor_id,_request_id) returning * into created;
  receipt=jsonb_build_object('run_id',created.id,'status',created.status,'case_count',jsonb_array_length(manifest));
  insert into public.admin_audit_log(actor_id,request_id,action,target_type,target_id,outcome,details) values(_actor_id,_request_id,'eval.run.create','ai_eval_run',created.id,'succeeded',jsonb_build_object('request',normalized,'result',receipt)); return receipt; end $$;

revoke all on function public.advance_ai_eval_dataset_state() from public, anon, authenticated;
revoke all on function public.admin_create_ai_eval_run(uuid,uuid,bigint,text,text,text,integer,numeric,integer) from public, anon, authenticated;
grant execute on function public.admin_create_ai_eval_run(uuid,uuid,bigint,text,text,text,integer,numeric,integer) to service_role;
