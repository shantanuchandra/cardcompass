-- Authenticated entry-point inventory. SECURITY INVOKER paths are fenced by
-- the active-owner RLS policies installed by 20260819090300.
-- active-boundary: get_user_transactions
alter function public.get_user_transactions(uuid, integer)
  security invoker set search_path = public;

-- active-boundary: reconcile_imported_statement_payment
alter function public.reconcile_imported_statement_payment(uuid, uuid, uuid, numeric)
  security invoker set search_path = public;

-- active-boundary: apply_statement_payment
alter function public.apply_statement_payment(uuid, uuid, uuid, numeric, boolean)
  security invoker set search_path = public;

-- active-boundary: private.reset_my_cardcompass_data
create or replace function private.reset_my_cardcompass_data()
returns void language plpgsql security definer set search_path = '' as $$
declare current_user_id uuid := auth.uid();
begin
  if current_user_id is null or not public.current_user_is_active() then
    raise exception 'access_denied' using errcode = '42501';
  end if;
  delete from public.transactions where user_id = current_user_id;
  delete from public.emails where user_id = current_user_id;
  delete from public.statement_milestone_cache where user_id = current_user_id;
  delete from public.statements where user_id = current_user_id;
  delete from public.benefit_platform_confirmations where user_id = current_user_id;
  delete from public.gemini_proxy_usage where user_id = current_user_id;
  delete from public.user_cards where user_id = current_user_id;
  update public.users set preferences = '{}'::jsonb, updated_at = now()
    where id = current_user_id;
end;
$$;

-- These three definitions already contain the active check; the annotations
-- make the audited inventory explicit and future additions fail the contract.
-- active-boundary: claim_my_admin_operation_request
-- active-boundary: renew_my_admin_operation_request
-- active-boundary: complete_my_admin_operation_request

create or replace function public.current_user_access_profile_state()
returns text language sql stable security definer set search_path = '' as $$
  select case
    when not exists (select 1 from public.users where id = (select auth.uid())) then 'missing'
    when exists (select 1 from public.users where id = (select auth.uid()) and is_active) then 'active'
    else 'inactive'
  end;
$$;
revoke all on function public.current_user_access_profile_state() from public, anon;
grant execute on function public.current_user_access_profile_state() to authenticated;
alter table public.admin_audit_log drop constraint if exists admin_audit_log_outcome_check;
alter table public.admin_audit_log add constraint admin_audit_log_outcome_check
  check (outcome in ('succeeded', 'failed', 'database_contained'));
