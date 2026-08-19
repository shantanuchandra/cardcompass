create table public.admin_runtime_controls (
  control_key text primary key
    check (control_key in ('benefit_enrichment_scheduled')),
  is_paused boolean not null default false,
  reason text check (reason is null or length(reason) between 2 and 500),
  updated_by uuid references auth.users(id) on delete restrict,
  updated_at timestamptz not null default now()
);

insert into public.admin_runtime_controls (control_key, is_paused)
values ('benefit_enrichment_scheduled', false)
on conflict (control_key) do nothing;

alter table public.admin_runtime_controls enable row level security;
revoke all on public.admin_runtime_controls from public, anon, authenticated;
revoke all on public.admin_runtime_controls from service_role;
grant select on public.admin_runtime_controls to service_role;

create or replace function public.admin_set_runtime_control(
  _actor_id uuid,
  _request_id uuid,
  _control_key text,
  _is_paused boolean,
  _reason text,
  _observed_updated_at timestamptz
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  normalized_reason text;
  normalized_request jsonb;
  prior_action text;
  prior_target_type text;
  prior_target_id text;
  prior_details jsonb;
  current_updated_at timestamptz;
  next_updated_at timestamptz;
  result jsonb;
begin
  normalized_reason := pg_catalog.btrim(coalesce(_reason, ''));
  if _control_key <> 'benefit_enrichment_scheduled'
     or _actor_id is null or _request_id is null or _is_paused is null
     or length(pg_catalog.btrim(coalesce(_reason, ''))) not between 2 and 500 then
    raise exception 'invalid_request';
  end if;

  normalized_request := pg_catalog.jsonb_build_object(
    'control_key', _control_key,
    'is_paused', _is_paused,
    'reason', normalized_reason,
    'observed_updated_at', _observed_updated_at
  );

  -- Serialize the first use of an idempotency key before reading its receipt.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    _actor_id::text || ':' || _request_id::text,
    0
  ));

  select audit.action, audit.target_type, audit.target_id, audit.details
    into prior_action, prior_target_type, prior_target_id, prior_details
  from public.admin_audit_log as audit
  where audit.actor_id = _actor_id and audit.request_id = _request_id;
  if found then
    if prior_action is distinct from
         case when _is_paused then 'system.control.pause' else 'system.control.resume' end
       or prior_target_type is distinct from 'runtime_control'
       or prior_target_id is distinct from _control_key
       or prior_details -> 'request' is distinct from normalized_request then
      raise exception 'request_id_collision';
    end if;
    return coalesce(prior_details -> 'result', '{}'::jsonb);
  end if;

  select control.updated_at into current_updated_at
  from public.admin_runtime_controls as control
  where control.control_key = _control_key
  for update;
  if not found then raise exception 'not_found'; end if;
  if _observed_updated_at is null
     or current_updated_at is distinct from _observed_updated_at then
    raise exception 'state_conflict';
  end if;

  next_updated_at := pg_catalog.clock_timestamp();
  if next_updated_at <= current_updated_at then
    next_updated_at := current_updated_at + interval '1 microsecond';
  end if;

  update public.admin_runtime_controls
  set is_paused = _is_paused,
      reason = normalized_reason,
      updated_by = _actor_id,
      updated_at = next_updated_at
  where control_key = _control_key;

  result := pg_catalog.jsonb_build_object(
    'control_key', _control_key,
    'is_paused', _is_paused,
    'reason', normalized_reason,
    'updated_at', next_updated_at
  );

  insert into public.admin_audit_log (
    actor_id, action, target_type, target_id, reason,
    request_id, outcome, details
  ) values (
    _actor_id,
    case when _is_paused then 'system.control.pause' else 'system.control.resume' end,
    'runtime_control', _control_key, normalized_reason,
    _request_id, 'succeeded',
    pg_catalog.jsonb_build_object(
      'request', normalized_request,
      'result', result
    )
  );

  return result;
end;
$$;

revoke all on function public.admin_set_runtime_control(
  uuid, uuid, text, boolean, text, timestamptz
) from public, anon, authenticated;
grant execute on function public.admin_set_runtime_control(
  uuid, uuid, text, boolean, text, timestamptz
) to service_role;
