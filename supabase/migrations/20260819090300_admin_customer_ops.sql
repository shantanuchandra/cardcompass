create or replace function public.current_user_is_active()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.users
    where id = (select auth.uid()) and is_active = true
  );
$$;

revoke all on function public.current_user_is_active() from public, anon;
grant execute on function public.current_user_is_active() to authenticated;

revoke insert, update on table public.users from authenticated;
grant insert (id, email, full_name, avatar_url, phone, created_at, updated_at,
  preferences, given_name, family_name, date_of_birth, profile_data)
  on table public.users to authenticated;
grant update (id, email, full_name, avatar_url, phone, created_at, updated_at, preferences,
  given_name, family_name, date_of_birth, profile_data)
  on table public.users to authenticated;

drop policy if exists users_own_data_policy on public.users;
drop policy if exists users_select_own_active on public.users;
drop policy if exists users_insert_own on public.users;
drop policy if exists users_update_own_active on public.users;
drop policy if exists users_delete_own_active on public.users;
create policy users_select_own_active on public.users for select to authenticated
  using ((select auth.uid()) = id and public.current_user_is_active());
create policy users_insert_own on public.users for insert to authenticated
  with check ((select auth.uid()) = id);
create policy users_update_own_active on public.users for update to authenticated
  using ((select auth.uid()) = id and public.current_user_is_active())
  with check ((select auth.uid()) = id and public.current_user_is_active());
create policy users_delete_own_active on public.users for delete to authenticated
  using ((select auth.uid()) = id and public.current_user_is_active());

drop policy if exists user_cards_policy on public.user_cards;
create policy user_cards_active_owner on public.user_cards for all to authenticated
  using ((select auth.uid()) = user_id and public.current_user_is_active())
  with check ((select auth.uid()) = user_id and public.current_user_is_active());

drop policy if exists transactions_policy on public.transactions;
create policy transactions_active_owner on public.transactions for all to authenticated
  using ((select auth.uid()) = user_id and public.current_user_is_active())
  with check ((select auth.uid()) = user_id and public.current_user_is_active());

drop policy if exists statements_policy on public.statements;
create policy statements_active_owner on public.statements for all to authenticated
  using ((select auth.uid()) = user_id and public.current_user_is_active())
  with check ((select auth.uid()) = user_id and public.current_user_is_active());

drop policy if exists statement_milestone_user_policy on public.statement_milestone_cache;
create policy statement_milestone_active_owner on public.statement_milestone_cache for all to authenticated
  using ((select auth.uid()) = user_id and public.current_user_is_active())
  with check ((select auth.uid()) = user_id and public.current_user_is_active());

drop policy if exists emails_policy on public.emails;
create policy emails_active_owner on public.emails for all to authenticated
  using ((select auth.uid()) = user_id and public.current_user_is_active())
  with check ((select auth.uid()) = user_id and public.current_user_is_active());

drop policy if exists "authenticated insert own confirmation" on public.benefit_platform_confirmations;
create policy benefit_confirmations_active_owner
  on public.benefit_platform_confirmations for insert to authenticated
  with check ((select auth.uid()) = user_id and public.current_user_is_active());

create table public.admin_customer_operation_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete restrict,
  operation_type text not null check (operation_type in ('gmail_sync')),
  status text not null default 'queued' check (status in ('queued', 'claimed', 'completed', 'failed')),
  requested_by uuid not null references auth.users(id) on delete restrict,
  request_id uuid not null,
  safe_failure_category text check (safe_failure_category is null or safe_failure_category in (
    'reauthentication_required', 'gmail_unavailable', 'processing_failed'
  )),
  claimed_at timestamptz,
  claim_expires_at timestamptz,
  claim_token uuid,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (requested_by, request_id)
);

create unique index admin_customer_one_unfinished_gmail_sync
  on public.admin_customer_operation_requests (user_id, operation_type)
  where status in ('queued', 'claimed');

create table public.account_deletion_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete restrict,
  status text not null check (status in ('requested', 'verified', 'scheduled', 'completed', 'cancelled')),
  operator_note text not null check (length(operator_note) between 2 and 1000),
  updated_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.admin_auth_ban_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete restrict,
  originating_actor_id uuid not null references auth.users(id) on delete restrict,
  originating_request_id uuid not null,
  status text not null default 'pending'
    check (status in ('pending', 'processing', 'completed', 'failed')),
  attempt_count integer not null default 0 check (attempt_count >= 0),
  safe_failure_category text check (
    safe_failure_category is null or safe_failure_category = 'auth_provider_unavailable'
  ),
  claimed_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (originating_actor_id, originating_request_id)
);

alter table public.admin_customer_operation_requests enable row level security;
alter table public.account_deletion_requests enable row level security;
alter table public.admin_auth_ban_requests enable row level security;
revoke all on public.admin_customer_operation_requests from public, anon, authenticated;
revoke all on public.account_deletion_requests from public, anon, authenticated;
revoke all on public.admin_customer_operation_requests from service_role;
revoke all on public.account_deletion_requests from service_role;
revoke all on public.admin_auth_ban_requests from public, anon, authenticated;
revoke all on public.admin_auth_ban_requests from service_role;
grant select on public.admin_customer_operation_requests to service_role;
grant select on public.account_deletion_requests to service_role;
grant select on public.admin_auth_ban_requests to service_role;

create or replace function public.claim_my_admin_operation_request(
  _operation_type text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  claimed public.admin_customer_operation_requests%rowtype;
  new_claim_token uuid := gen_random_uuid();
begin
  if current_user_id is null or _operation_type <> 'gmail_sync'
     or not public.current_user_is_active() then
    raise exception 'access_denied';
  end if;
  select request.* into claimed
  from public.admin_customer_operation_requests as request
  where request.user_id = current_user_id
    and request.operation_type = _operation_type
    and (
      request.status = 'queued'
      or (request.status = 'claimed' and request.claim_expires_at <= now())
    )
  order by request.created_at, request.id
  for update skip locked
  limit 1;
  if not found then return null; end if;
  update public.admin_customer_operation_requests
  set status = 'claimed', claimed_at = now(),
      claim_expires_at = now() + interval '10 minutes',
      claim_token = new_claim_token, updated_at = now()
  where id = claimed.id
  returning * into claimed;
  return pg_catalog.jsonb_build_object(
    'id', claimed.id,
    'operation_type', claimed.operation_type,
    'claim_token', claimed.claim_token
  );
end;
$$;

-- Remove the pre-lease development signature if this migration is replayed
-- against a local database that saw an earlier draft.
drop function if exists public.complete_my_admin_operation_request(
  uuid, boolean, text
);

create or replace function public.renew_my_admin_operation_request(
  _request_id uuid,
  _claim_token uuid
) returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  claimed public.admin_customer_operation_requests%rowtype;
  renewed_until timestamptz;
begin
  if current_user_id is null or not public.current_user_is_active()
     or _request_id is null or _claim_token is null then
    raise exception 'access_denied';
  end if;
  select request.* into claimed
  from public.admin_customer_operation_requests as request
  where request.id = _request_id and request.user_id = current_user_id
    and request.operation_type = 'gmail_sync'
    and request.status = 'claimed' and request.claim_token = _claim_token
  for update;
  if not found then raise exception 'state_conflict'; end if;
  update public.admin_customer_operation_requests
  set claim_expires_at = now() + interval '10 minutes', updated_at = now()
  where id = claimed.id and status = 'claimed' and claim_token = _claim_token
  returning claim_expires_at into renewed_until;
  return renewed_until;
end;
$$;

create or replace function public.complete_my_admin_operation_request(
  _request_id uuid,
  _claim_token uuid,
  _succeeded boolean,
  _safe_failure_category text default null
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare current_user_id uuid := (select auth.uid());
begin
  if current_user_id is null or not public.current_user_is_active()
     or _request_id is null or _claim_token is null or _succeeded is null then
    raise exception 'access_denied';
  end if;
  if (_succeeded and _safe_failure_category is not null)
     or (not _succeeded and coalesce(_safe_failure_category, '') not in (
       'reauthentication_required', 'gmail_unavailable', 'processing_failed'
     )) then
    raise exception 'invalid_request';
  end if;
  update public.admin_customer_operation_requests
  set status = case when _succeeded then 'completed' else 'failed' end,
      safe_failure_category = _safe_failure_category,
      completed_at = now(), claim_token = null, claim_expires_at = null,
      updated_at = now()
  where id = _request_id and user_id = current_user_id and status = 'claimed'
    and claim_token = _claim_token;
  if not found then raise exception 'state_conflict'; end if;
end;
$$;

create or replace function public.admin_customer_action(
  _actor_id uuid,
  _request_id uuid,
  _action text,
  _target_user_id uuid,
  _payload jsonb default '{}'::jsonb,
  _reason text default null,
  _observed_updated_at timestamptz default null
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  prior_action text;
  prior_target_type text;
  prior_target_id text;
  prior_details jsonb;
  normalized_reason text := nullif(pg_catalog.btrim(_reason), '');
  normalized_request jsonb;
  result jsonb;
  profile public.users%rowtype;
  operation_request public.admin_customer_operation_requests%rowtype;
  deletion public.account_deletion_requests%rowtype;
  deletion_status text;
begin
  if _actor_id is null or _request_id is null or _target_user_id is null
     or _action not in ('request_gmail_sync', 'disable_account', 'set_deletion_status')
     or pg_catalog.jsonb_typeof(coalesce(_payload, '{}'::jsonb)) <> 'object'
     or length(coalesce(_reason, '')) > 1000 then
    raise exception 'invalid_request';
  end if;
  if _action in ('disable_account', 'set_deletion_status')
     and length(coalesce(normalized_reason, '')) < 2 then
    raise exception 'reason_required';
  end if;
  if _action = 'disable_account' and _target_user_id = _actor_id then
    raise exception 'self_disable_denied';
  end if;
  if _action <> 'set_deletion_status' and _payload <> '{}'::jsonb then
    raise exception 'invalid_request';
  end if;
  if _action = 'request_gmail_sync' and normalized_reason is not null then
    raise exception 'invalid_request';
  end if;
  deletion_status := _payload ->> 'status';
  if _action = 'set_deletion_status'
     and ((select count(*) from pg_catalog.jsonb_object_keys(_payload)) <> 1
       or deletion_status not in ('requested', 'verified', 'scheduled', 'completed', 'cancelled')) then
    raise exception 'invalid_request';
  end if;

  normalized_request := pg_catalog.jsonb_build_object(
    'action', _action,
    'target_user_id', _target_user_id,
    'payload', coalesce(_payload, '{}'::jsonb),
    'reason', normalized_reason,
    'observed_updated_at', _observed_updated_at
  );
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    _actor_id::text || ':' || _request_id::text, 0
  ));
  select audit.action, audit.target_type, audit.target_id, audit.details
    into prior_action, prior_target_type, prior_target_id, prior_details
  from public.admin_audit_log as audit
  where audit.actor_id = _actor_id and audit.request_id = _request_id;
  if found then
    if prior_action is distinct from 'customer.' || _action
       or prior_target_type is distinct from 'user'
       or prior_target_id is distinct from _target_user_id::text
       or prior_details -> 'request' is distinct from normalized_request then
      raise exception 'request_id_collision';
    end if;
    return coalesce(prior_details -> 'result', '{}'::jsonb);
  end if;

  select candidate.* into profile
  from public.users as candidate
  where candidate.id = _target_user_id
  for update;
  if not found then raise exception 'not_found'; end if;
  if _action <> 'set_deletion_status'
     and (_observed_updated_at is null
       or profile.updated_at is distinct from _observed_updated_at) then
    raise exception 'state_conflict';
  end if;

  if _action = 'request_gmail_sync' then
    if not profile.is_active then raise exception 'state_conflict'; end if;
    select request.* into operation_request
    from public.admin_customer_operation_requests as request
    where request.user_id = _target_user_id
      and request.operation_type = 'gmail_sync'
      and request.status in ('queued', 'claimed')
    for update;
    if found then
      result := pg_catalog.jsonb_build_object(
        'request_id', operation_request.id,
        'status', operation_request.status
      );
    else
      insert into public.admin_customer_operation_requests (
        user_id, operation_type, requested_by, request_id
      ) values (_target_user_id, 'gmail_sync', _actor_id, _request_id)
      returning pg_catalog.jsonb_build_object(
        'request_id', id, 'status', status
      ) into result;
    end if;
  elsif _action = 'disable_account' then
    update public.users set is_active = false, updated_at = now()
    where id = _target_user_id and is_active = true;
    if not found and profile.is_active = false then
      result := pg_catalog.jsonb_build_object('user_id', _target_user_id, 'is_active', false);
    elsif not found then
      raise exception 'state_conflict';
    else
      result := pg_catalog.jsonb_build_object('user_id', _target_user_id, 'is_active', false);
    end if;
    insert into public.admin_auth_ban_requests (
      user_id, originating_actor_id, originating_request_id, status
    ) values (_target_user_id, _actor_id, _request_id, 'pending')
    on conflict (user_id) do update set
      status = case when admin_auth_ban_requests.status in ('completed', 'processing')
        then admin_auth_ban_requests.status else 'pending' end,
      originating_actor_id = case when admin_auth_ban_requests.status in ('completed', 'processing')
        then admin_auth_ban_requests.originating_actor_id else excluded.originating_actor_id end,
      originating_request_id = case when admin_auth_ban_requests.status in ('completed', 'processing')
        then admin_auth_ban_requests.originating_request_id else excluded.originating_request_id end,
      safe_failure_category = case when admin_auth_ban_requests.status in ('completed', 'processing')
        then admin_auth_ban_requests.safe_failure_category else null end,
      updated_at = now();
    result := result || pg_catalog.jsonb_build_object(
      'containment', 'database_contained',
      'auth_ban_status', (select status from public.admin_auth_ban_requests where user_id = _target_user_id)
    );
  else
    select request.* into deletion
    from public.account_deletion_requests as request
    where request.user_id = _target_user_id
    for update;
    if found and (_observed_updated_at is null
       or deletion.updated_at is distinct from _observed_updated_at) then
      raise exception 'state_conflict';
    end if;
    if not found and (_observed_updated_at is null
       or profile.updated_at is distinct from _observed_updated_at) then
      raise exception 'state_conflict';
    end if;
    insert into public.account_deletion_requests (
      user_id, status, operator_note, updated_by
    ) values (
      _target_user_id, deletion_status, normalized_reason, _actor_id
    ) on conflict (user_id) do update
      set status = excluded.status, operator_note = excluded.operator_note,
          updated_by = excluded.updated_by, updated_at = now()
    returning pg_catalog.jsonb_build_object(
      'user_id', user_id, 'status', status, 'updated_at', updated_at
    ) into result;
  end if;

  insert into public.admin_audit_log (
    actor_id, action, target_type, target_id, reason,
    request_id, outcome, details
  ) values (
    _actor_id, 'customer.' || _action, 'user', _target_user_id::text,
    normalized_reason, _request_id,
    case when _action = 'disable_account' then 'database_contained' else 'succeeded' end,
    pg_catalog.jsonb_build_object('request', normalized_request, 'result', result)
  );
  return result;
end;
$$;

create or replace function public.claim_admin_auth_ban(_target_user_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare request public.admin_auth_ban_requests%rowtype;
begin
  select candidate.* into request from public.admin_auth_ban_requests candidate
  where candidate.user_id = _target_user_id and (
    candidate.status in ('pending', 'failed') or
    (candidate.status = 'processing' and candidate.claimed_at < now() - interval '2 minutes')
  ) for update;
  if not found then
    select candidate.* into request from public.admin_auth_ban_requests candidate
      where candidate.user_id = _target_user_id;
    if found and request.status = 'completed' then
      return pg_catalog.jsonb_build_object('id', request.id, 'user_id', request.user_id, 'status', request.status, 'claimed', false);
    elsif found and request.status = 'processing' then
      return pg_catalog.jsonb_build_object('id', request.id, 'user_id', request.user_id, 'status', request.status, 'claimed', false);
    end if;
    raise exception 'state_conflict';
  end if;
  update public.admin_auth_ban_requests set status = 'processing',
    attempt_count = attempt_count + 1, claimed_at = now(), updated_at = now()
  where id = request.id returning * into request;
  return pg_catalog.jsonb_build_object('id', request.id, 'user_id', request.user_id, 'status', request.status, 'claimed', true);
end;
$$;

create or replace function public.complete_admin_auth_ban(
  _ban_id uuid, _succeeded boolean, _safe_failure_category text default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare request public.admin_auth_ban_requests%rowtype;
begin
  if _succeeded is null or (_succeeded and _safe_failure_category is not null)
     or (not _succeeded and _safe_failure_category <> 'auth_provider_unavailable') then
    raise exception 'invalid_request';
  end if;
  update public.admin_auth_ban_requests set
    status = case when _succeeded then 'completed' else 'failed' end,
    safe_failure_category = _safe_failure_category,
    completed_at = case when _succeeded then now() else null end,
    updated_at = now()
  where id = _ban_id and status = 'processing' returning * into request;
  if not found then raise exception 'state_conflict'; end if;
  insert into public.admin_audit_log (
    actor_id, action, target_type, target_id, request_id, outcome, details
  ) values (
    request.originating_actor_id,
    case when _succeeded then 'customer.auth_ban_completed' else 'customer.auth_ban_failed' end,
    'user', request.user_id::text, gen_random_uuid(),
    case when _succeeded then 'succeeded' else 'failed' end,
    pg_catalog.jsonb_build_object(
      'originating_request_id', request.originating_request_id,
      'safe_failure_category', request.safe_failure_category,
      'result', pg_catalog.jsonb_build_object('user_id', request.user_id, 'auth_ban_status', request.status)
    )
  );
  return pg_catalog.jsonb_build_object('user_id', request.user_id, 'auth_ban_status', request.status);
end;
$$;

revoke all on function public.claim_my_admin_operation_request(text)
  from public, anon, service_role;
revoke all on function public.complete_my_admin_operation_request(uuid, uuid, boolean, text)
  from public, anon, service_role;
revoke all on function public.renew_my_admin_operation_request(uuid, uuid)
  from public, anon, service_role;
revoke all on function public.admin_customer_action(
  uuid, uuid, text, uuid, jsonb, text, timestamptz
) from public, anon, authenticated;
grant execute on function public.claim_my_admin_operation_request(text) to authenticated;
grant execute on function public.complete_my_admin_operation_request(uuid, uuid, boolean, text) to authenticated;
grant execute on function public.renew_my_admin_operation_request(uuid, uuid) to authenticated;
grant execute on function public.admin_customer_action(
  uuid, uuid, text, uuid, jsonb, text, timestamptz
) to service_role;
revoke all on function public.claim_admin_auth_ban(uuid) from public, anon, authenticated;
revoke all on function public.complete_admin_auth_ban(uuid, boolean, text) from public, anon, authenticated;
grant execute on function public.claim_admin_auth_ban(uuid) to service_role;
grant execute on function public.complete_admin_auth_ban(uuid, boolean, text) to service_role;
