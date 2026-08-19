create sequence public.ai_eval_dataset_version_seq start with 1;

create table public.ai_output_traces (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
  feature_key text not null check (feature_key in ('statement_processing', 'card_data', 'recommendation')),
  request_id uuid not null, safe_input_context jsonb not null default '{}'::jsonb,
  output_snapshot jsonb not null default '{}'::jsonb, authoritative_context jsonb not null default '{}'::jsonb,
  engine_version text, model text, prompt_version text,
  created_at timestamptz not null default now(), expires_at timestamptz not null,
  unique (user_id, request_id), check (expires_at > created_at and expires_at <= created_at + interval '7 days'),
  check (jsonb_typeof(safe_input_context) = 'object' and octet_length(safe_input_context::text) <= 16384),
  check (jsonb_typeof(output_snapshot) = 'object' and octet_length(output_snapshot::text) <= 32768),
  check (jsonb_typeof(authoritative_context) = 'object' and octet_length(authoritative_context::text) <= 32768)
);

create table public.ai_feedback (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
  feature_key text not null check (feature_key in ('statement_processing', 'card_data', 'recommendation')),
  output_ref_type text not null check (output_ref_type in ('transaction','statement','user_card','recommendation_trace')),
  output_ref_id text not null check (char_length(output_ref_id) between 1 and 100),
  feedback_text text not null check (char_length(feedback_text) between 10 and 2000),
  safe_input_context jsonb not null default '{}'::jsonb, output_snapshot jsonb not null default '{}'::jsonb,
  trace_id uuid references public.ai_output_traces(id) on delete set null,
  provider text, model text, prompt_version text, parser_version text, request_id uuid not null,
  triage_status text not null default 'awaiting_triage' check (triage_status in ('awaiting_triage','triaging','triaged','triage_failed')),
  triage_result jsonb not null default '{}'::jsonb, triage_claimed_at timestamptz, triage_attempts integer not null default 0,
  triage_failure_category text check (triage_failure_category is null or triage_failure_category in ('model_unavailable','invalid_model_output','triage_persistence_failed')),
  review_status text not null default 'pending' check (review_status in ('pending','eval_created','data_issue','product_defect','dismissed')),
  reviewed_by uuid references auth.users(id), reviewed_at timestamptz, dismissal_reason text,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique (user_id, request_id),
  check (jsonb_typeof(safe_input_context) = 'object' and octet_length(safe_input_context::text) <= 32768),
  check (jsonb_typeof(output_snapshot) = 'object' and octet_length(output_snapshot::text) <= 32768),
  check (jsonb_typeof(triage_result) = 'object' and octet_length(triage_result::text) <= 16384)
);

create table public.ai_eval_cases (
  id uuid primary key default gen_random_uuid(), source_feedback_id uuid not null references public.ai_feedback(id),
  feature_key text not null check (feature_key in ('statement_processing', 'card_data', 'recommendation')),
  revision integer not null check (revision > 0), supersedes_case_id uuid references public.ai_eval_cases(id),
  input_fixture jsonb not null, captured_output jsonb not null, expected_output jsonb not null,
  operator_feedback text not null check (char_length(operator_feedback) between 2 and 2000),
  scoring_rubric jsonb not null, severe_failure_conditions jsonb not null,
  status text not null default 'draft' check (status in ('draft','approved','retired')),
  approved_in_dataset_version bigint, retired_in_dataset_version bigint,
  source_engine_version text, source_model text, source_prompt_version text, source_parser_version text, source_trace_id uuid,
  created_by uuid not null references auth.users(id), approved_by uuid references auth.users(id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), approved_at timestamptz, retired_at timestamptz,
  unique (source_feedback_id, revision),
  check (jsonb_typeof(input_fixture)='object' and octet_length(input_fixture::text)<=32768),
  check (jsonb_typeof(captured_output)='object' and octet_length(captured_output::text)<=32768),
  check (jsonb_typeof(expected_output)='object' and octet_length(expected_output::text)<=32768),
  check (jsonb_typeof(scoring_rubric)='object' and octet_length(scoring_rubric::text)<=16384),
  check (jsonb_typeof(severe_failure_conditions)='object' and octet_length(severe_failure_conditions::text)<=16384)
);

alter table public.ai_output_traces enable row level security;
alter table public.ai_feedback enable row level security;
alter table public.ai_eval_cases enable row level security;
revoke all on public.ai_output_traces from public, anon, authenticated, service_role;
revoke all on public.ai_feedback from public, anon, authenticated, service_role;
revoke all on public.ai_eval_cases from public, anon, authenticated, service_role;
revoke all on sequence public.ai_eval_dataset_version_seq from public, anon, authenticated;
grant select, insert on public.ai_output_traces to service_role;
grant select, insert, update on public.ai_feedback to service_role;
grant select, insert, update on public.ai_eval_cases to service_role;
grant usage, select on sequence public.ai_eval_dataset_version_seq to service_role;

create or replace function public.create_ai_output_trace(_user_id uuid, _request_id uuid, _feature_key text, _safe_input jsonb, _output jsonb, _authoritative jsonb, _metadata jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$ declare row public.ai_output_traces; begin
  if _feature_key <> 'recommendation' or jsonb_typeof(_safe_input)<>'object' or jsonb_typeof(_output)<>'object' or jsonb_typeof(_authoritative)<>'object'
    or octet_length(_safe_input::text)>16384 or octet_length(_output::text)>32768 or octet_length(_authoritative::text)>32768 then raise exception 'invalid_request'; end if;
  perform pg_advisory_xact_lock(hashtextextended(_user_id::text || ':' || _request_id::text, 0));
  select * into row from public.ai_output_traces where user_id=_user_id and request_id=_request_id;
  if found then
    if row.feature_key is distinct from _feature_key or row.safe_input_context is distinct from _safe_input or row.output_snapshot is distinct from _output or row.authoritative_context is distinct from _authoritative then raise exception 'request_id_collision'; end if;
    return jsonb_build_object('id',row.id,'expires_at',row.expires_at);
  end if;
  insert into public.ai_output_traces(user_id,request_id,feature_key,safe_input_context,output_snapshot,authoritative_context,engine_version,model,prompt_version,expires_at)
  values(_user_id,_request_id,_feature_key,_safe_input,_output,_authoritative,_metadata->>'engine_version',_metadata->>'model',_metadata->>'prompt_version',least(now()+interval '7 days',coalesce((_metadata->>'expires_at')::timestamptz,now()+interval '7 days'))) returning * into row;
  return jsonb_build_object('id',row.id,'expires_at',row.expires_at); end $$;

create or replace function public.submit_ai_feedback(_user_id uuid, _request_id uuid, _feature_key text, _output_ref_type text, _output_ref_id text, _feedback_text text, _safe_input jsonb, _output jsonb, _metadata jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$ declare row public.ai_feedback; begin
  if char_length(btrim(_feedback_text)) not between 10 and 2000 or jsonb_typeof(_safe_input)<>'object' or jsonb_typeof(_output)<>'object' or octet_length(_safe_input::text)>32768 or octet_length(_output::text)>32768 then raise exception 'invalid_request'; end if;
  perform pg_advisory_xact_lock(hashtextextended(_user_id::text || ':' || _request_id::text, 0));
  select * into row from public.ai_feedback where user_id=_user_id and request_id=_request_id;
  if found then
    if row.feature_key is distinct from _feature_key or row.output_ref_type is distinct from _output_ref_type or row.output_ref_id is distinct from _output_ref_id or row.feedback_text is distinct from btrim(_feedback_text) then raise exception 'request_id_collision'; end if;
    return jsonb_build_object('id',row.id,'triage_status',row.triage_status);
  end if;
  insert into public.ai_feedback(user_id,request_id,feature_key,output_ref_type,output_ref_id,feedback_text,safe_input_context,output_snapshot,trace_id,provider,model,prompt_version,parser_version)
  values(_user_id,_request_id,_feature_key,_output_ref_type,_output_ref_id,btrim(_feedback_text),_safe_input,_output,(_metadata->>'trace_id')::uuid,_metadata->>'provider',_metadata->>'model',_metadata->>'prompt_version',_metadata->>'parser_version') returning * into row;
  return jsonb_build_object('id',row.id,'triage_status',row.triage_status); end $$;

create or replace function public.claim_ai_feedback_triage(_feedback_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$ declare row public.ai_feedback; begin
  select * into row from public.ai_feedback where id=_feedback_id and (triage_status in ('awaiting_triage','triage_failed') or (triage_status='triaging' and triage_claimed_at < now()-interval '5 minutes')) for update skip locked;
  if not found then return null; end if;
  update public.ai_feedback set triage_status='triaging',triage_claimed_at=now(),triage_attempts=triage_attempts+1,updated_at=now() where id=row.id;
  return jsonb_build_object('id',row.id,'feature_key',row.feature_key,'feedback_text',row.feedback_text,'safe_input_context',row.safe_input_context,'output_snapshot',row.output_snapshot); end $$;

create or replace function public.complete_ai_feedback_triage(_feedback_id uuid, _succeeded boolean, _result jsonb, _failure_category text) returns void
language plpgsql security definer set search_path = '' as $$ begin
  if _succeeded and (jsonb_typeof(_result)<>'object' or octet_length(_result::text)>16384) then raise exception 'invalid_request'; end if;
  if not _succeeded and _failure_category not in ('model_unavailable','invalid_model_output','triage_persistence_failed') then raise exception 'invalid_request'; end if;
  update public.ai_feedback set triage_status=case when _succeeded then 'triaged' else 'triage_failed' end,triage_result=case when _succeeded then _result else '{}'::jsonb end,triage_failure_category=case when _succeeded then null else _failure_category end,triage_claimed_at=null,updated_at=now() where id=_feedback_id and triage_status='triaging'; end $$;

create or replace function public.admin_review_ai_feedback(_actor_id uuid, _request_id uuid, _feedback_id uuid, _action text, _payload jsonb, _reason text) returns jsonb
language plpgsql security definer set search_path = '' as $$ declare feedback public.ai_feedback; prior_details jsonb; normalized_request jsonb; result jsonb; new_case public.ai_eval_cases; begin
  if _action not in ('create_eval_draft','data_issue','product_defect','dismiss') then raise exception 'invalid_request'; end if;
  perform pg_advisory_xact_lock(hashtextextended(_actor_id::text||':'||_request_id::text,0));
  normalized_request=jsonb_build_object('action',_action,'feedback_id',_feedback_id,'payload',coalesce(_payload,'{}'::jsonb),'reason',coalesce(btrim(_reason),''));
  select details into prior_details from public.admin_audit_log where actor_id=_actor_id and request_id=_request_id;
  if found then if prior_details->'request' is distinct from normalized_request then raise exception 'request_id_collision'; end if; return prior_details->'result'; end if;
  select * into feedback from public.ai_feedback where id=_feedback_id for update; if not found then raise exception 'not_found'; end if;
  if feedback.review_status<>'pending' then raise exception 'state_conflict'; end if;
  if _action='create_eval_draft' then
    if length(btrim(coalesce(_payload->>'operator_feedback',''))) < 2 or jsonb_typeof(_payload->'expected_output')<>'object' or jsonb_typeof(_payload->'scoring_rubric')<>'object' or jsonb_typeof(_payload->'severe_failure_conditions')<>'object' then raise exception 'invalid_request'; end if;
    insert into public.ai_eval_cases(source_feedback_id,feature_key,revision,input_fixture,captured_output,expected_output,operator_feedback,scoring_rubric,severe_failure_conditions,source_engine_version,source_model,source_prompt_version,source_parser_version,source_trace_id,created_by)
    values(feedback.id,feedback.feature_key,1,feedback.safe_input_context,feedback.output_snapshot,_payload->'expected_output',btrim(_payload->>'operator_feedback'),_payload->'scoring_rubric',_payload->'severe_failure_conditions',null,feedback.model,feedback.prompt_version,feedback.parser_version,feedback.trace_id,_actor_id) returning * into new_case;
    update public.ai_feedback set review_status='eval_created',reviewed_by=_actor_id,reviewed_at=now(),updated_at=now() where id=feedback.id;
    result=jsonb_build_object('feedback_id',feedback.id,'review_status','eval_created','case_id',new_case.id,'revision',1);
  else
    if length(btrim(coalesce(_reason,'')))<2 then raise exception 'reason_required'; end if;
    update public.ai_feedback set review_status=case when _action='dismiss' then 'dismissed' else _action end,reviewed_by=_actor_id,reviewed_at=now(),dismissal_reason=btrim(_reason),updated_at=now() where id=feedback.id;
    result=jsonb_build_object('feedback_id',feedback.id,'review_status',case when _action='dismiss' then 'dismissed' else _action end);
  end if;
  insert into public.admin_audit_log(actor_id,request_id,action,target_type,target_id,outcome,reason,details) values(_actor_id,_request_id,'feedback_'||_action,'ai_feedback',_feedback_id,'succeeded',nullif(btrim(coalesce(_reason,'')),''),jsonb_build_object('request',normalized_request,'result',result)); return result; end $$;

create or replace function public.admin_ai_eval_case_action(_actor_id uuid, _request_id uuid, _case_id uuid, _action text, _payload jsonb, _reason text, _observed_updated_at timestamptz) returns jsonb
language plpgsql security definer set search_path = '' as $$ declare current_case public.ai_eval_cases; prior_details jsonb; normalized_request jsonb; result jsonb; version bigint; revised public.ai_eval_cases; begin
  if _action not in ('approve','revise','retire') then raise exception 'invalid_request'; end if;
  perform pg_advisory_xact_lock(hashtextextended(_actor_id::text||':'||_request_id::text,0));
  normalized_request=jsonb_build_object('action',_action,'case_id',_case_id,'payload',coalesce(_payload,'{}'::jsonb),'reason',coalesce(btrim(_reason),''),'observed_updated_at',_observed_updated_at);
  select details into prior_details from public.admin_audit_log where actor_id=_actor_id and request_id=_request_id; if found then if prior_details->'request' is distinct from normalized_request then raise exception 'request_id_collision'; end if; return prior_details->'result'; end if;
  select * into current_case from public.ai_eval_cases where id=_case_id for update; if not found then raise exception 'not_found'; end if;
  if _observed_updated_at is null or current_case.updated_at is distinct from _observed_updated_at then raise exception 'state_conflict'; end if;
  if _action='approve' then if current_case.status<>'draft' then raise exception 'state_conflict'; end if; version=nextval('public.ai_eval_dataset_version_seq'); update public.ai_eval_cases set status='approved',approved_by=_actor_id,approved_at=now(),approved_in_dataset_version=version,updated_at=now() where id=_case_id returning * into current_case; result=jsonb_build_object('case_id',_case_id,'status','approved','dataset_version',version,'updated_at',current_case.updated_at);
  elsif _action='retire' then if current_case.status<>'approved' then raise exception 'state_conflict'; end if; version=nextval('public.ai_eval_dataset_version_seq'); update public.ai_eval_cases set status='retired',retired_at=now(),retired_in_dataset_version=version,updated_at=now() where id=_case_id returning * into current_case; result=jsonb_build_object('case_id',_case_id,'status','retired','dataset_version',version,'updated_at',current_case.updated_at);
  else
    if current_case.status<>'approved' or length(btrim(coalesce(_payload->>'operator_feedback','')))<2 then raise exception 'invalid_request'; end if;
    insert into public.ai_eval_cases(source_feedback_id,feature_key,revision,supersedes_case_id,input_fixture,captured_output,expected_output,operator_feedback,scoring_rubric,severe_failure_conditions,source_engine_version,source_model,source_prompt_version,source_parser_version,source_trace_id,created_by)
    values(current_case.source_feedback_id,current_case.feature_key,current_case.revision+1,current_case.id,current_case.input_fixture,current_case.captured_output,_payload->'expected_output',btrim(_payload->>'operator_feedback'),_payload->'scoring_rubric',_payload->'severe_failure_conditions',current_case.source_engine_version,current_case.source_model,current_case.source_prompt_version,current_case.source_parser_version,current_case.source_trace_id,_actor_id) returning * into revised;
    result=jsonb_build_object('case_id',revised.id,'status','draft','revision',revised.revision,'updated_at',revised.updated_at);
  end if;
  insert into public.admin_audit_log(actor_id,request_id,action,target_type,target_id,outcome,reason,details) values(_actor_id,_request_id,'eval_case_'||_action,'ai_eval_case',_case_id,'succeeded',nullif(btrim(coalesce(_reason,'')),''),jsonb_build_object('request',normalized_request,'result',result)); return result; end $$;

revoke all on function public.create_ai_output_trace(uuid,uuid,text,jsonb,jsonb,jsonb,jsonb) from public, anon, authenticated;
revoke all on function public.submit_ai_feedback(uuid,uuid,text,text,text,text,jsonb,jsonb,jsonb) from public, anon, authenticated;
revoke all on function public.claim_ai_feedback_triage(uuid) from public, anon, authenticated;
revoke all on function public.complete_ai_feedback_triage(uuid,boolean,jsonb,text) from public, anon, authenticated;
revoke all on function public.admin_review_ai_feedback(uuid,uuid,uuid,text,jsonb,text) from public, anon, authenticated;
revoke all on function public.admin_ai_eval_case_action(uuid,uuid,uuid,text,jsonb,text,timestamptz) from public, anon, authenticated;
grant execute on function public.create_ai_output_trace(uuid,uuid,text,jsonb,jsonb,jsonb,jsonb) to service_role;
grant execute on function public.submit_ai_feedback(uuid,uuid,text,text,text,text,jsonb,jsonb,jsonb) to service_role;
grant execute on function public.claim_ai_feedback_triage(uuid) to service_role;
grant execute on function public.complete_ai_feedback_triage(uuid,boolean,jsonb,text) to service_role;
grant execute on function public.admin_review_ai_feedback(uuid,uuid,uuid,text,jsonb,text) to service_role;
grant execute on function public.admin_ai_eval_case_action(uuid,uuid,uuid,text,jsonb,text,timestamptz) to service_role;
