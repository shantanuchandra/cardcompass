create table public.admin_audit_log (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid not null references auth.users(id) on delete restrict,
  action text not null check (length(action) between 1 and 100),
  target_type text not null check (length(target_type) between 1 and 100),
  target_id text,
  reason text check (reason is null or length(reason) between 1 and 1000),
  request_id uuid not null,
  outcome text not null check (outcome in ('succeeded', 'failed')),
  details jsonb not null default '{}'::jsonb check (jsonb_typeof(details) = 'object'),
  created_at timestamptz not null default now(),
  unique (actor_id, request_id)
);

create index admin_audit_log_created_at_idx
  on public.admin_audit_log (created_at desc);

alter table public.admin_audit_log enable row level security;
revoke all on public.admin_audit_log from public, anon, authenticated;
revoke all on public.admin_audit_log from service_role;
grant select, insert on public.admin_audit_log to service_role;

create or replace function public.find_admin_request(
  _actor_id uuid,
  _request_id uuid
) returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'action', log.action,
    'outcome', log.outcome,
    'result', coalesce(log.details -> 'result', '{}'::jsonb)
  )
  from public.admin_audit_log as log
  where log.actor_id = _actor_id and log.request_id = _request_id;
$$;

create or replace function public.record_admin_read(
  _actor_id uuid,
  _action text,
  _target_type text,
  _target_id text,
  _request_id uuid,
  _details jsonb default '{}'::jsonb
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  inserted_id uuid;
begin
  insert into public.admin_audit_log (
    actor_id, action, target_type, target_id, request_id, outcome, details
  ) values (
    _actor_id, _action, _target_type, _target_id, _request_id,
    'succeeded', coalesce(_details, '{}'::jsonb)
  )
  returning id into inserted_id;
  return inserted_id;
end;
$$;

revoke all on function public.find_admin_request(uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.record_admin_read(uuid, text, text, text, uuid, jsonb)
  from public, anon, authenticated;
grant execute on function public.find_admin_request(uuid, uuid) to service_role;
grant execute on function public.record_admin_read(uuid, text, text, text, uuid, jsonb)
  to service_role;
