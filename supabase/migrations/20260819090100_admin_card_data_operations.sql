create or replace function public.admin_card_data_action(
  _actor_id uuid,
  _request_id uuid,
  _lane text,
  _operation text,
  _target_id uuid,
  _staging_id uuid default null,
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
  normalized_request jsonb;
  result jsonb;
  review public.card_catalog_review_queue%rowtype;
  job public.card_catalog_enrichment_jobs%rowtype;
  staging public.card_benefits_staging%rowtype;
begin
  if _actor_id is null or _request_id is null or _target_id is null
     or _lane is null or _operation is null
     or jsonb_typeof(coalesce(_payload, '{}'::jsonb)) <> 'object' then
    raise exception 'invalid_request';
  end if;
  if _lane not in ('identity', 'benefit') then
    raise exception 'invalid_request';
  end if;
  if _operation not in (
    'approve', 'edit_approve', 'merge', 'reject',
    'retry', 'quarantine', 'unquarantine'
  ) then
    raise exception 'invalid_request';
  end if;
  if _lane = 'identity'
     and _operation not in ('approve', 'edit_approve', 'merge', 'reject', 'retry') then
    raise exception 'invalid_request';
  end if;
  if _lane = 'benefit'
     and _operation not in (
       'approve', 'edit_approve', 'reject', 'retry', 'quarantine', 'unquarantine'
     ) then
    raise exception 'invalid_request';
  end if;
  if _operation in ('reject', 'quarantine')
     and length(pg_catalog.btrim(coalesce(_reason, ''))) < 2 then
    raise exception 'reason_required';
  end if;
  if length(coalesce(_reason, '')) > 1000 then
    raise exception 'invalid_request';
  end if;

  normalized_request := pg_catalog.jsonb_build_object(
    'lane', _lane,
    'operation', _operation,
    'target_id', _target_id,
    'staging_id', _staging_id,
    'payload', coalesce(_payload, '{}'::jsonb),
    'reason', nullif(pg_catalog.btrim(_reason), ''),
    'observed_updated_at', _observed_updated_at
  );

  -- Serialize a request key before looking up its receipt. Without this lock,
  -- two first-time callers could both mutate before the unique audit insert.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    _actor_id::text || ':' || _request_id::text,
    0
  ));

  select audit.action, audit.target_type, audit.target_id, audit.details
    into prior_action, prior_target_type, prior_target_id, prior_details
  from public.admin_audit_log as audit
  where audit.actor_id = _actor_id and audit.request_id = _request_id;
  if found then
    if prior_action is distinct from 'card_data.' || _lane || '.' || _operation
       or prior_target_type is distinct from _lane || '_review'
       or prior_target_id is distinct from _target_id::text
       or prior_details -> 'request' is distinct from normalized_request then
      raise exception 'request_id_collision';
    end if;
    return coalesce(prior_details -> 'result', '{}'::jsonb);
  end if;

  if _lane = 'identity' then
    select candidate.* into review
    from public.card_catalog_review_queue as candidate
    where candidate.id = _target_id
    for update;
    if not found then
      raise exception 'not_found';
    end if;
    if review.status <> 'pending' then
      raise exception 'state_conflict';
    end if;
    if _observed_updated_at is not null
       and review.updated_at is distinct from _observed_updated_at then
      raise exception 'state_conflict';
    end if;

    select to_jsonb(resolution) into result
    from public.review_card_catalog_discovery(
      _target_id,
      _actor_id,
      _operation,
      nullif(_payload -> 'proposed_fields', 'null'::jsonb),
      nullif(_payload ->> 'merge_card_id', '')::uuid,
      _reason
    ) as resolution;
  else
    select candidate.* into job
    from public.card_catalog_enrichment_jobs as candidate
    where candidate.id = _target_id
    for update;
    if not found or lower(pg_catalog.btrim(job.parser_version)) = 'catalog-v1' then
      raise exception 'not_found';
    end if;
    if _observed_updated_at is not null
       and job.updated_at is distinct from _observed_updated_at then
      raise exception 'state_conflict';
    end if;

    if _operation in ('approve', 'edit_approve', 'reject') then
      if _staging_id is null or jsonb_typeof(_payload -> 'decisions') <> 'array'
         or job.status not in ('staged', 'review_required')
         or job.staging_id is distinct from _staging_id then
        raise exception 'state_conflict';
      end if;

      select candidate.* into staging
      from public.card_benefits_staging as candidate
      where candidate.id = _staging_id
      for update;
      if not found or staging.card_id is distinct from job.card_id
         or staging.status <> 'pending' then
        raise exception 'state_conflict';
      end if;

      select to_jsonb(resolution) into result
      from public.approve_card_benefit_enrichment(
        _staging_id, _actor_id, _payload -> 'decisions'
      ) as resolution;

      update public.card_catalog_enrichment_jobs
      set status = 'completed', failure_category = null,
          next_retry_at = null, updated_at = now()
      where id = _target_id;
    elsif _operation = 'retry' then
      update public.card_catalog_enrichment_jobs
      set status = 'queued', failure_category = null, next_retry_at = now(),
          lease_token = null, lease_expires_at = null, updated_at = now()
      where id = _target_id
        and status in ('failed', 'review_required', 'quarantined')
        and lower(pg_catalog.btrim(parser_version)) <> 'catalog-v1';
      if not found then raise exception 'state_conflict'; end if;
      result := pg_catalog.jsonb_build_object(
        'job_id', _target_id, 'resulting_status', 'queued'
      );
    elsif _operation = 'quarantine' then
      update public.card_catalog_enrichment_jobs
      set status = 'quarantined', failure_category = 'manual_quarantine',
          next_retry_at = null, lease_token = null, lease_expires_at = null,
          result_summary = coalesce(result_summary, '{}'::jsonb) ||
            pg_catalog.jsonb_build_object(
              'quarantine_reason', left(pg_catalog.btrim(_reason), 500)
            ),
          updated_at = now()
      where id = _target_id
        and status in ('queued', 'failed', 'review_required', 'staged')
        and lower(pg_catalog.btrim(parser_version)) <> 'catalog-v1';
      if not found then raise exception 'state_conflict'; end if;
      result := pg_catalog.jsonb_build_object(
        'job_id', _target_id, 'resulting_status', 'quarantined'
      );
    else
      update public.card_catalog_enrichment_jobs
      set status = 'queued', failure_category = null, next_retry_at = now(),
          lease_token = null, lease_expires_at = null, updated_at = now()
      where id = _target_id and status = 'quarantined'
        and lower(pg_catalog.btrim(parser_version)) <> 'catalog-v1';
      if not found then raise exception 'state_conflict'; end if;
      result := pg_catalog.jsonb_build_object(
        'job_id', _target_id, 'resulting_status', 'queued'
      );
    end if;
  end if;

  if result is null then
    raise exception 'state_conflict';
  end if;

  insert into public.admin_audit_log (
    actor_id, action, target_type, target_id, reason,
    request_id, outcome, details
  ) values (
    _actor_id, 'card_data.' || _lane || '.' || _operation,
    _lane || '_review', _target_id::text,
    nullif(pg_catalog.btrim(_reason), ''), _request_id, 'succeeded',
    pg_catalog.jsonb_build_object(
      'request', normalized_request,
      'result', result
    )
  );

  return result;
end;
$$;

revoke all on function public.admin_card_data_action(
  uuid, uuid, text, text, uuid, uuid, jsonb, text, timestamptz
) from public, anon, authenticated;
grant execute on function public.admin_card_data_action(
  uuid, uuid, text, text, uuid, uuid, jsonb, text, timestamptz
) to service_role;
