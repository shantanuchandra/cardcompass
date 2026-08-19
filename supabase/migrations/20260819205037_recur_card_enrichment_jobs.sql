BEGIN;

SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '120s';

-- This byte-sum is intentionally simple. TypeScript uses TextEncoder over the
-- same trimmed lowercase identifier, so jitter is stable across runtimes.
CREATE OR REPLACE FUNCTION public.card_enrichment_jitter_days(
  _card_id uuid,
  _radius integer
) RETURNS integer
LANGUAGE plpgsql
IMMUTABLE
STRICT
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  identifier_bytes bytea;
  byte_index integer;
  byte_total bigint := 0;
BEGIN
  IF _radius < 0 OR _radius > 31 THEN
    RAISE EXCEPTION 'invalid_recurrence_radius';
  END IF;
  identifier_bytes := convert_to(lower(trim(_card_id::text)), 'UTF8');
  IF length(identifier_bytes) > 0 THEN
    FOR byte_index IN 0..length(identifier_bytes) - 1 LOOP
      byte_total := byte_total + get_byte(identifier_bytes, byte_index);
    END LOOP;
  END IF;
  RETURN mod(byte_total, (2 * _radius) + 1)::integer - _radius;
END;
$$;

CREATE OR REPLACE FUNCTION public.next_card_enrichment_observation_at(
  _card_id uuid,
  _completed_at timestamptz,
  _is_discontinued boolean,
  _has_active_cardholder boolean,
  _outcome text
) RETURNS timestamptz
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  normalized_outcome text := lower(trim(coalesce(_outcome, '')));
BEGIN
  IF _card_id IS NULL OR _completed_at IS NULL
     OR _completed_at > statement_timestamp() + interval '5 minutes'
     OR _is_discontinued IS NULL OR _has_active_cardholder IS NULL THEN
    RAISE EXCEPTION 'invalid_recurrence_policy';
  END IF;
  IF _is_discontinued AND NOT _has_active_cardholder THEN
    RETURN NULL;
  END IF;
  IF normalized_outcome IN ('success', 'not_modified') THEN
    RETURN _completed_at + interval '30 days' + make_interval(
      days => public.card_enrichment_jitter_days(_card_id, 3)
    );
  ELSIF normalized_outcome IN ('blocked', 'missing', 'failed') THEN
    RETURN _completed_at + interval '7 days' + make_interval(
      days => public.card_enrichment_jitter_days(_card_id, 1)
    );
  END IF;
  RAISE EXCEPTION 'invalid_recurrence_outcome';
END;
$$;

CREATE OR REPLACE FUNCTION public.bounded_card_enrichment_timestamp(
  _value text,
  _now timestamptz
) RETURNS timestamptz
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  parsed_value timestamptz;
BEGIN
  IF _value IS NULL OR length(_value) > 64 OR _now IS NULL THEN RETURN NULL; END IF;
  BEGIN
    parsed_value := _value::timestamptz;
  EXCEPTION WHEN OTHERS THEN
    RETURN NULL;
  END;
  IF parsed_value < '2000-01-01T00:00:00Z'::timestamptz
     OR parsed_value > _now + interval '5 minutes' THEN
    RETURN NULL;
  END IF;
  RETURN parsed_value;
END;
$$;

CREATE OR REPLACE FUNCTION public.sanitize_card_enrichment_source_attempt(
  _attempt jsonb,
  _now timestamptz
) RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  attempted_at_value timestamptz;
  safe_url text;
  safe_history jsonb;
BEGIN
  IF jsonb_typeof(_attempt) <> 'object' OR _now IS NULL THEN RETURN NULL; END IF;
  attempted_at_value := public.bounded_card_enrichment_timestamp(
    _attempt->>'attemptedAt', _now
  );
  IF attempted_at_value IS NULL THEN RETURN NULL; END IF;
  safe_url := CASE
    WHEN _attempt->>'url' = 'invalid-source' THEN 'invalid-source'
    WHEN _attempt->>'url' ~ '^https://[^/@?#]+(?:/[^?#]*)?$'
      THEN left(_attempt->>'url', 2048)
    ELSE 'invalid-source'
  END;
  SELECT coalesce(jsonb_agg(history_value ORDER BY history_index), '[]'::jsonb)
  INTO safe_history
  FROM (
    SELECT history_index, jsonb_strip_nulls(jsonb_build_object(
      'status', CASE WHEN history->>'status' IN ('success', 'not_modified', 'failed')
        THEN history->>'status' END,
      'httpStatus', CASE WHEN history->>'httpStatus' ~ '^[1-5][0-9]{2}$'
        THEN (history->>'httpStatus')::integer END,
      'errorCode', CASE WHEN history->>'errorCode' ~ '^[a-z0-9_]{1,64}$'
        THEN history->>'errorCode' END,
      'finalResourceIdentityHash', CASE
        WHEN history->>'finalResourceIdentityHash' ~ '^[0-9a-f]{64}$'
        THEN history->>'finalResourceIdentityHash' END,
      'attemptedAt', public.bounded_card_enrichment_timestamp(
        history->>'attemptedAt', _now
      )
    )) AS history_value
    FROM jsonb_array_elements(
      CASE WHEN jsonb_typeof(_attempt->'attemptHistory') = 'array'
        THEN _attempt->'attemptHistory' ELSE '[]'::jsonb END
    ) WITH ORDINALITY AS entries(history, history_index)
    WHERE jsonb_typeof(history) = 'object'
    ORDER BY history_index
    LIMIT 6
  ) AS bounded_history;
  RETURN jsonb_strip_nulls(jsonb_build_object(
    'url', safe_url,
    'role', CASE WHEN _attempt->>'role' IN ('primary', 'required_supporting', 'supporting')
      THEN _attempt->>'role' END,
    'status', CASE WHEN _attempt->>'status' IN ('success', 'not_modified', 'failed')
      THEN _attempt->>'status' END,
    'httpStatus', CASE WHEN _attempt->>'httpStatus' ~ '^[1-5][0-9]{2}$'
      THEN (_attempt->>'httpStatus')::integer END,
    'contentHash', CASE WHEN _attempt->>'contentHash' ~ '^[0-9a-f]{64}$'
      THEN _attempt->>'contentHash' END,
    'finalResourceIdentityHash', CASE
      WHEN _attempt->>'finalResourceIdentityHash' ~ '^[0-9a-f]{64}$'
      THEN _attempt->>'finalResourceIdentityHash' END,
    'errorCode', CASE WHEN _attempt->>'errorCode' ~ '^[a-z0-9_]{1,64}$'
      THEN _attempt->>'errorCode' END,
    'attemptedAt', attempted_at_value,
    'parserCacheReusable', CASE WHEN jsonb_typeof(_attempt->'parserCacheReusable') = 'boolean'
      THEN _attempt->'parserCacheReusable' END,
    'logicalSourceKey', CASE WHEN _attempt->>'logicalSourceKey' ~ '^[0-9a-f]{64}$'
      THEN _attempt->>'logicalSourceKey' END,
    'attemptHistory', safe_history,
    'attemptHistoryOverflow', CASE WHEN jsonb_typeof(_attempt->'attemptHistoryOverflow') = 'boolean'
      THEN _attempt->'attemptHistoryOverflow' END
  ));
END;
$$;

CREATE OR REPLACE FUNCTION public.sanitize_card_enrichment_observation(
  _observation jsonb,
  _now timestamptz
) RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  observed_at_value timestamptz;
  safe_attempts jsonb;
  safe_absent_ids jsonb;
  safe_absent_legacy_ids jsonb;
  safe_source_observation jsonb;
BEGIN
  IF jsonb_typeof(_observation) <> 'object' OR _now IS NULL THEN RETURN NULL; END IF;
  observed_at_value := public.bounded_card_enrichment_timestamp(
    _observation->>'observed_at', _now
  );
  IF observed_at_value IS NULL THEN RETURN NULL; END IF;
  SELECT coalesce(jsonb_agg(value ORDER BY value), '[]'::jsonb)
  INTO safe_absent_ids
  FROM (
    SELECT DISTINCT left(jsonb_array_elements_text(
      CASE WHEN jsonb_typeof(_observation->'absent_benefit_ids') = 'array'
        THEN _observation->'absent_benefit_ids' ELSE '[]'::jsonb END
    ), 256) AS value
    LIMIT 256
  ) AS values;
  SELECT coalesce(jsonb_agg(value ORDER BY value), '[]'::jsonb)
  INTO safe_absent_legacy_ids
  FROM (
    SELECT DISTINCT left(jsonb_array_elements_text(
      CASE WHEN jsonb_typeof(_observation->'absent_legacy_benefit_ids') = 'array'
        THEN _observation->'absent_legacy_benefit_ids' ELSE '[]'::jsonb END
    ), 256) AS value
    LIMIT 256
  ) AS values;
  SELECT coalesce(jsonb_agg(safe_attempt ORDER BY attempt_index), '[]'::jsonb)
  INTO safe_attempts
  FROM (
    SELECT attempt_index,
      public.sanitize_card_enrichment_source_attempt(attempt, _now) AS safe_attempt
    FROM jsonb_array_elements(
      CASE WHEN jsonb_typeof(_observation->'source_attempts') = 'array'
        THEN _observation->'source_attempts' ELSE '[]'::jsonb END
    ) WITH ORDINALITY AS entries(attempt, attempt_index)
    ORDER BY attempt_index
    LIMIT 9
  ) AS attempts
  WHERE safe_attempt IS NOT NULL;
  safe_source_observation := CASE
    WHEN jsonb_typeof(_observation->'source_observation') = 'object' THEN
      jsonb_strip_nulls(jsonb_build_object(
        'parser_version', left(_observation#>>'{source_observation,parser_version}', 64),
        'terminal_disposition', left(_observation#>>'{source_observation,terminal_disposition}', 64),
        'review_reason', left(_observation#>>'{source_observation,review_reason}', 64),
        'crawl_complete', CASE
          WHEN jsonb_typeof(_observation#>'{source_observation,crawl_complete}') = 'boolean'
          THEN _observation#>'{source_observation,crawl_complete}' END,
        'http_status', CASE
          WHEN _observation#>>'{source_observation,http_status}' ~ '^[1-5][0-9]{2}$'
          THEN (_observation#>>'{source_observation,http_status}')::integer END,
        'submitted_url', CASE
          WHEN _observation#>>'{source_observation,submitted_url}' ~ '^https://[^/@?#]+(?:/[^?#]*)?$'
          THEN left(_observation#>>'{source_observation,submitted_url}', 2048) END,
        'final_url', CASE
          WHEN _observation#>>'{source_observation,final_url}' ~ '^https://[^/@?#]+(?:/[^?#]*)?$'
          THEN left(_observation#>>'{source_observation,final_url}', 2048) END,
        'canonical_url', CASE
          WHEN _observation#>>'{source_observation,canonical_url}' ~ '^https://[^/@?#]+(?:/[^?#]*)?$'
          THEN left(_observation#>>'{source_observation,canonical_url}', 2048) END,
        'retrieved_at', public.bounded_card_enrichment_timestamp(
          _observation#>>'{source_observation,retrieved_at}', _now
        ),
        'not_modified', CASE
          WHEN jsonb_typeof(_observation#>'{source_observation,not_modified}') = 'boolean'
          THEN _observation#>'{source_observation,not_modified}' END,
        'etag', left(_observation#>>'{source_observation,etag}', 512),
        'last_modified', left(_observation#>>'{source_observation,last_modified}', 512),
        'content_hash', CASE
          WHEN _observation#>>'{source_observation,content_hash}' ~ '^[0-9a-f]{64}$'
          THEN _observation#>>'{source_observation,content_hash}' END,
        'submitted_identity_hash', CASE
          WHEN _observation#>>'{source_observation,submitted_identity_hash}' ~ '^[0-9a-f]{64}$'
          THEN _observation#>>'{source_observation,submitted_identity_hash}' END,
        'final_resource_url', CASE
          WHEN _observation#>>'{source_observation,final_resource_url}' ~ '^https://[^/@?#]+(?:/[^?#]*)?$'
          THEN left(_observation#>>'{source_observation,final_resource_url}', 2048) END,
        'final_resource_identity_hash', CASE
          WHEN _observation#>>'{source_observation,final_resource_identity_hash}' ~ '^[0-9a-f]{64}$'
          THEN _observation#>>'{source_observation,final_resource_identity_hash}' END,
        'card_identity_validated', CASE
          WHEN jsonb_typeof(_observation#>'{source_observation,card_identity_validated}') = 'boolean'
          THEN _observation#>'{source_observation,card_identity_validated}' END
      ))
    ELSE NULL
  END;
  RETURN jsonb_strip_nulls(jsonb_build_object(
    'observed_at', observed_at_value,
    'crawl_complete', CASE WHEN jsonb_typeof(_observation->'crawl_complete') = 'boolean'
      THEN _observation->'crawl_complete' ELSE 'false'::jsonb END,
    'crawl_reason', left(coalesce(_observation->>'crawl_reason', 'invalid_observation'), 64),
    'source_manifest_hash', CASE WHEN _observation->>'source_manifest_hash' ~ '^[0-9a-f]{64}$'
      THEN _observation->>'source_manifest_hash' END,
    'canonical_benefit_hash', CASE WHEN _observation->>'canonical_benefit_hash' ~ '^[0-9a-f]{64}$'
      THEN _observation->>'canonical_benefit_hash' END,
    'absent_benefit_ids', safe_absent_ids,
    'absent_legacy_benefit_ids', safe_absent_legacy_ids,
    'source_attempts', safe_attempts,
    'source_observation', safe_source_observation
  ));
END;
$$;

CREATE OR REPLACE FUNCTION public.normalize_card_enrichment_observation_history(
  _existing_history jsonb,
  _current_observation jsonb,
  _now timestamptz
) RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
  WITH raw_observations AS (
    SELECT observation, 1 AS source_priority
    FROM jsonb_array_elements(
      CASE WHEN jsonb_typeof(_existing_history) = 'array'
        THEN _existing_history ELSE '[]'::jsonb END
    ) AS existing(observation)
    UNION ALL
    SELECT _current_observation, 0
  ), sanitized AS (
    SELECT public.sanitize_card_enrichment_observation(observation, _now) AS observation,
      source_priority
    FROM raw_observations
  ), deduplicated AS (
    SELECT DISTINCT ON (
      observation->>'observed_at',
      coalesce(observation->>'source_manifest_hash', ''),
      coalesce(observation->>'canonical_benefit_hash', '')
    ) observation
    FROM sanitized
    WHERE observation IS NOT NULL
    ORDER BY observation->>'observed_at',
      coalesce(observation->>'source_manifest_hash', ''),
      coalesce(observation->>'canonical_benefit_hash', ''),
      source_priority
  ), newest AS (
    SELECT observation
    FROM deduplicated
    ORDER BY (observation->>'observed_at')::timestamptz DESC,
      observation->>'source_manifest_hash', observation->>'canonical_benefit_hash'
    LIMIT 24
  )
  SELECT coalesce(jsonb_agg(observation ORDER BY
    (observation->>'observed_at')::timestamptz DESC,
    observation->>'source_manifest_hash', observation->>'canonical_benefit_hash'
  ), '[]'::jsonb)
  FROM newest;
$$;

CREATE OR REPLACE FUNCTION public.sanitize_card_enrichment_result_summary(
  _summary jsonb
) RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  safe_summary jsonb := '{}'::jsonb;
  allowed_key text;
  allowed_value jsonb;
  allowed_text text;
BEGIN
  IF jsonb_typeof(_summary) <> 'object' THEN RETURN safe_summary; END IF;
  FOREACH allowed_key IN ARRAY ARRAY[
    'run_id', 'source_documents', 'proposals', 'additions', 'modifications',
    'possible_removals', 'retirement_eligible_removals',
    'suppressed_removal_count', 'conflicts', 'reused_staging',
    'material_proposal', 'proposal_disposition', 'successful_no_change',
    'source_manifest_hash', 'canonical_benefit_hash', 'crawl_complete',
    'unsafe_mutation_count', 'raw_body_stored', 'evidence_passed',
    'idempotency_passed', 'quarantine_reason', 'retry_scheduled',
    'lease_expired', 'reviewed_at', 'review_status', 'approved_count',
    'retired_count', 'rejected_count', 'retained_count'
  ] LOOP
    IF _summary ? allowed_key THEN
      allowed_value := _summary->allowed_key;
      allowed_text := allowed_value#>>'{}';
      IF allowed_key = ANY (ARRAY[
        'reused_staging', 'material_proposal', 'successful_no_change',
        'crawl_complete', 'raw_body_stored', 'evidence_passed',
        'idempotency_passed', 'retry_scheduled', 'lease_expired'
      ]) AND jsonb_typeof(allowed_value) = 'boolean' THEN
        safe_summary := jsonb_set(safe_summary, ARRAY[allowed_key], allowed_value, true);
      ELSIF allowed_key = ANY (ARRAY[
        'source_documents', 'proposals', 'additions', 'modifications',
        'possible_removals', 'retirement_eligible_removals',
        'suppressed_removal_count', 'conflicts', 'unsafe_mutation_count',
        'approved_count', 'retired_count', 'rejected_count', 'retained_count'
      ]) AND jsonb_typeof(allowed_value) = 'number'
        AND allowed_text ~ '^[0-9]{1,9}$' THEN
        safe_summary := jsonb_set(safe_summary, ARRAY[allowed_key], allowed_value, true);
      ELSIF allowed_key IN ('source_manifest_hash', 'canonical_benefit_hash')
        AND jsonb_typeof(allowed_value) = 'string'
        AND allowed_text ~ '^[0-9a-f]{64}$' THEN
        safe_summary := jsonb_set(safe_summary, ARRAY[allowed_key], allowed_value, true);
      ELSIF allowed_key = 'run_id'
        AND jsonb_typeof(allowed_value) = 'string'
        AND allowed_text ~ '^[0-9a-f-]{1,64}$' THEN
        safe_summary := jsonb_set(safe_summary, ARRAY[allowed_key], allowed_value, true);
      ELSIF allowed_key = 'proposal_disposition'
        AND allowed_text IN ('material', 'removal_review', 'no_change', 'incomplete') THEN
        safe_summary := jsonb_set(safe_summary, ARRAY[allowed_key], allowed_value, true);
      ELSIF allowed_key = 'quarantine_reason'
        AND jsonb_typeof(allowed_value) = 'string'
        AND allowed_text ~ '^[a-z0-9_]{1,64}$' THEN
        safe_summary := jsonb_set(safe_summary, ARRAY[allowed_key], allowed_value, true);
      ELSIF allowed_key = 'review_status'
        AND allowed_text IN ('approved', 'rejected') THEN
        safe_summary := jsonb_set(safe_summary, ARRAY[allowed_key], allowed_value, true);
      ELSIF allowed_key = 'reviewed_at'
        AND jsonb_typeof(allowed_value) = 'string'
        AND length(allowed_text) <= 40
        AND allowed_text ~ '^\d{4}-\d{2}-\d{2}T' THEN
        safe_summary := jsonb_set(safe_summary, ARRAY[allowed_key], allowed_value, true);
      END IF;
    END IF;
  END LOOP;
  RETURN safe_summary;
END;
$$;

CREATE OR REPLACE FUNCTION public.card_has_unresolved_catalog_identity(
  _card_id uuid,
  _canonical_url text
) RETURNS boolean
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.card_catalog_review_queue AS review
    LEFT JOIN LATERAL jsonb_array_elements(
      CASE WHEN jsonb_typeof(review.existing_candidates) = 'array'
        THEN review.existing_candidates ELSE '[]'::jsonb END
    ) AS candidate(value) ON true
    WHERE review.status = 'pending'
      AND (
        candidate.value->>'id' = _card_id::text
        OR candidate.value->>'card_id' = _card_id::text
        OR candidate.value->>'cardId' = _card_id::text
        OR review.proposed_fields->>'card_id' = _card_id::text
        OR review.proposed_fields->>'cardId' = _card_id::text
        OR review.proposed_fields->>'existing_card_id' = _card_id::text
        OR regexp_replace(split_part(split_part(coalesce(
          review.proposed_fields->>'official_url',
          review.proposed_fields->>'card_url',
          review.proposed_fields->>'source_url',
          review.source_evidence->>'official_url',
          review.source_evidence->>'source_url',
          ''
        ), '#', 1), '?', 1), '/+$', '') =
          regexp_replace(split_part(split_part(coalesce(_canonical_url, ''), '#', 1), '?', 1), '/+$', '')
      )
  );
$$;

CREATE OR REPLACE FUNCTION public.schedule_terminal_card_enrichment_observation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  card_is_discontinued boolean;
  active_cardholder boolean;
  terminal_disposition text;
  recurrence_outcome text;
BEGIN
  IF NEW.parser_version = 'benefits-v6'
     AND NEW.status IN ('completed', 'staged', 'quarantined', 'review_required', 'failed')
     AND NEW.next_retry_at IS NULL THEN
    SELECT coalesce(card.is_discontinued, false), EXISTS (
      SELECT 1 FROM public.user_cards AS user_card
      WHERE user_card.catalog_card_id = NEW.card_id
        AND user_card.is_active = true
    )
    INTO card_is_discontinued, active_cardholder
    FROM public.card_catalog AS card
    WHERE card.id = NEW.card_id;
    terminal_disposition := lower(coalesce(
      NEW.result_summary#>>'{source_observation,terminal_disposition}',
      NEW.result_summary#>>'{observation,source_observation,terminal_disposition}',
      NEW.result_summary->>'terminal_disposition',
      ''
    ));
    recurrence_outcome := CASE
      WHEN terminal_disposition = 'not_modified' THEN 'not_modified'
      WHEN NEW.status IN ('completed', 'staged') THEN 'success'
      WHEN terminal_disposition IN ('missing', 'not_found')
        OR NEW.failure_category IN ('http_404', 'http_410', 'missing') THEN 'missing'
      WHEN terminal_disposition IN ('blocked', 'review_required')
        OR NEW.failure_category IN ('http_401', 'http_403', 'http_429', 'robots_disallowed', 'challenge_page')
        THEN 'blocked'
      ELSE 'failed'
    END;
    NEW.next_run_at := public.next_card_enrichment_observation_at(
      NEW.card_id,
      statement_timestamp(),
      card_is_discontinued,
      active_cardholder,
      recurrence_outcome
    );
  ELSIF NEW.parser_version = 'benefits-v6' THEN
    NEW.next_run_at := NULL;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS schedule_terminal_card_enrichment_observation
  ON public.card_catalog_enrichment_jobs;
CREATE TRIGGER schedule_terminal_card_enrichment_observation
BEFORE INSERT OR UPDATE OF status, next_retry_at, result_summary, failure_category, parser_version
ON public.card_catalog_enrichment_jobs
FOR EACH ROW EXECUTE FUNCTION public.schedule_terminal_card_enrichment_observation();

-- Bring pre-migration v6 terminal rows into the same trigger policy without
-- changing their status, summary, staging link, or audit identity. v5 remains
-- untouched as the rollback lane.
UPDATE public.card_catalog_enrichment_jobs AS legacy_terminal
SET status = legacy_terminal.status
WHERE legacy_terminal.parser_version = 'benefits-v6'
  AND legacy_terminal.status IN ('completed', 'staged', 'quarantined', 'review_required', 'failed')
  AND legacy_terminal.next_retry_at IS NULL
  AND legacy_terminal.next_run_at IS NULL
  AND NOT public.card_has_unresolved_catalog_identity(
    legacy_terminal.card_id, legacy_terminal.canonical_url
  );

CREATE OR REPLACE FUNCTION public.requeue_due_card_catalog_enrichment_jobs(
  _parser_version text,
  _limit integer,
  _now timestamptz
) RETURNS SETOF public.card_catalog_enrichment_jobs
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  selected_parser text := lower(trim(coalesce(_parser_version, '')));
BEGIN
  IF selected_parser <> 'benefits-v6' OR _now IS NULL
     OR _now > statement_timestamp() + interval '5 minutes'
     OR _limit IS NULL OR _limit < 1 OR _limit > 200 THEN
    RAISE EXCEPTION 'invalid_enrichment_requeue';
  END IF;
  UPDATE public.card_catalog_enrichment_jobs AS job
  SET next_run_at = NULL,
      updated_at = _now
  FROM public.card_catalog AS card
  WHERE job.card_id = card.id
    AND job.parser_version = selected_parser
    AND job.status IN ('completed', 'staged', 'quarantined', 'review_required', 'failed')
    AND job.next_run_at <= _now
    AND coalesce(card.is_discontinued, false) = true
    AND NOT EXISTS (
      SELECT 1 FROM public.user_cards AS user_card
      WHERE user_card.catalog_card_id = job.card_id
        AND user_card.is_active = true
    );
  RETURN QUERY
  WITH due_jobs AS (
    SELECT job.id
    FROM public.card_catalog_enrichment_jobs AS job
    JOIN public.card_catalog AS card ON card.id = job.card_id
    WHERE job.parser_version = selected_parser
      AND job.status IN ('completed', 'staged', 'quarantined', 'review_required', 'failed')
      AND job.status <> 'processing'
      AND job.next_run_at <= _now
      AND job.next_retry_at IS NULL
      AND (job.lease_expires_at IS NULL OR job.lease_expires_at <= _now)
      AND (
        coalesce(card.is_discontinued, false) = false
        OR EXISTS (
          SELECT 1 FROM public.user_cards AS user_card
          WHERE user_card.catalog_card_id = job.card_id
            AND user_card.is_active = true
        )
      )
      AND NOT public.card_has_unresolved_catalog_identity(job.card_id, job.canonical_url)
    ORDER BY job.next_run_at, lower(trim(job.issuer)), job.id
    LIMIT _limit
    FOR UPDATE OF job SKIP LOCKED
  )
  UPDATE public.card_catalog_enrichment_jobs AS job
  SET status = 'queued',
      attempt_count = 0,
      next_retry_at = NULL,
      next_run_at = NULL,
      lease_expires_at = NULL,
      lease_token = NULL,
      failure_category = NULL,
      updated_at = _now
  FROM due_jobs
  WHERE job.id = due_jobs.id
  RETURNING job.*;
END;
$$;

CREATE OR REPLACE FUNCTION public.claim_card_catalog_enrichment_jobs(
  _max_jobs integer,
  _lease_seconds integer,
  _run_mode text,
  _parser_version text
) RETURNS SETOF public.card_catalog_enrichment_jobs
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  selected_issuer text;
  maximum_jobs integer;
  lease_seconds integer;
  selected_parser text;
BEGIN
  selected_parser := trim(coalesce(_parser_version, ''));
  IF _max_jobs IS NULL OR _max_jobs < 1 OR _lease_seconds IS NULL
     OR _run_mode IS NULL OR _run_mode NOT IN ('pilot', 'scheduled', 'manual')
     OR length(selected_parser) < 3 OR lower(selected_parser) = 'catalog-v1' THEN
    RAISE EXCEPTION 'invalid_enrichment_claim';
  END IF;
  maximum_jobs := 1;
  lease_seconds := 300;
  PERFORM pg_advisory_xact_lock(
    hashtextextended('card_catalog_enrichment_claim:' || selected_parser, 0)
  );
  UPDATE public.card_catalog_enrichment_jobs AS job
  SET status = CASE WHEN job.attempt_count >= 3 THEN 'review_required' ELSE 'failed' END,
      failure_category = 'worker_resource_limit',
      next_retry_at = CASE
        WHEN job.attempt_count >= 3 THEN NULL
        WHEN job.attempt_count = 1 THEN now() + interval '15 minutes'
        ELSE now() + interval '60 minutes' END,
      next_run_at = NULL,
      result_summary = coalesce(job.result_summary, '{}'::jsonb) || jsonb_build_object(
        'lease_expired', true, 'retry_scheduled', job.attempt_count < 3
      ),
      lease_expires_at = NULL,
      lease_token = NULL,
      updated_at = now()
  WHERE job.status = 'processing'
    AND job.parser_version = selected_parser
    AND (job.lease_expires_at IS NULL OR job.lease_expires_at <= now());

  SELECT lower(trim(job.issuer)) INTO selected_issuer
  FROM public.card_catalog_enrichment_jobs AS job
  JOIN public.card_catalog AS card ON card.id = job.card_id
  WHERE job.status IN ('queued', 'failed')
    AND job.next_run_at IS NULL
    AND (job.next_retry_at IS NULL OR job.next_retry_at <= now())
    AND job.run_mode = _run_mode
    AND job.parser_version = selected_parser
    AND (
      coalesce(card.is_discontinued, false) = false
      OR EXISTS (
        SELECT 1 FROM public.user_cards AS user_card
        WHERE user_card.catalog_card_id = job.card_id
          AND user_card.is_active = true
      )
    )
    AND NOT public.card_has_unresolved_catalog_identity(job.card_id, job.canonical_url)
    AND NOT EXISTS (
      SELECT 1 FROM public.card_catalog_enrichment_jobs AS leased
      WHERE lower(trim(leased.issuer)) = lower(trim(job.issuer))
        AND leased.status = 'processing'
        AND leased.parser_version = selected_parser
        AND leased.lease_expires_at > now()
    )
  ORDER BY lower(trim(job.issuer)), card.card_name, job.created_at, job.id
  LIMIT 1;
  IF selected_issuer IS NULL THEN RETURN; END IF;

  RETURN QUERY
  WITH candidates AS (
    SELECT job.id
    FROM public.card_catalog_enrichment_jobs AS job
    JOIN public.card_catalog AS card ON card.id = job.card_id
    WHERE lower(trim(job.issuer)) = selected_issuer
      AND job.status IN ('queued', 'failed')
      AND job.next_run_at IS NULL
      AND (job.next_retry_at IS NULL OR job.next_retry_at <= now())
      AND job.run_mode = _run_mode
      AND job.parser_version = selected_parser
      AND (
        coalesce(card.is_discontinued, false) = false
        OR EXISTS (
          SELECT 1 FROM public.user_cards AS user_card
          WHERE user_card.catalog_card_id = job.card_id
            AND user_card.is_active = true
        )
      )
      AND NOT public.card_has_unresolved_catalog_identity(job.card_id, job.canonical_url)
    ORDER BY card.card_name, job.created_at, job.id
    LIMIT maximum_jobs
    FOR UPDATE OF job SKIP LOCKED
  )
  UPDATE public.card_catalog_enrichment_jobs AS job
  SET status = 'processing',
      attempt_count = job.attempt_count + 1,
      next_run_at = NULL,
      lease_expires_at = now() + make_interval(secs => lease_seconds),
      lease_token = gen_random_uuid(),
      updated_at = now()
  FROM candidates
  WHERE job.id = candidates.id
  RETURNING job.*;
END;
$$;

CREATE OR REPLACE FUNCTION public.finalize_card_catalog_enrichment_job(
  _job_id uuid,
  _lease_token uuid,
  _status text,
  _staging_id uuid,
  _content_hash text,
  _normalized_fields jsonb,
  _result_summary jsonb,
  _failure_category text,
  _next_retry_at timestamptz
) RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  affected_rows integer;
  job_row public.card_catalog_enrichment_jobs%ROWTYPE;
  current_observation jsonb;
  observation_history jsonb;
  safe_summary jsonb;
BEGIN
  IF _job_id IS NULL OR _lease_token IS NULL
     OR _status NOT IN ('staged', 'completed', 'quarantined', 'failed', 'review_required')
     OR jsonb_typeof(coalesce(_normalized_fields, '{}'::jsonb)) <> 'object'
     OR jsonb_typeof(coalesce(_result_summary, '{}'::jsonb)) <> 'object'
     OR (_status = 'staged' AND _staging_id IS NULL)
     OR (_status = 'completed' AND _staging_id IS NOT NULL)
     OR (_status = 'failed' AND _next_retry_at IS NULL)
     OR (_status <> 'failed' AND _next_retry_at IS NOT NULL) THEN
    RAISE EXCEPTION 'invalid_enrichment_finalization';
  END IF;
  SELECT job.* INTO job_row
  FROM public.card_catalog_enrichment_jobs AS job
  WHERE job.id = _job_id
    AND job.status = 'processing'
    AND job.lease_token = _lease_token
    AND job.lease_expires_at > now()
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'stale_enrichment_lease'; END IF;

  IF _status = 'staged' AND NOT EXISTS (
    SELECT 1 FROM public.card_benefits_staging AS staging
    WHERE staging.id = _staging_id
      AND staging.card_id = job_row.card_id
      AND staging.request_type = 'official_benefit_enrichment'
      AND staging.status IN ('pending', 'approved')
      AND public.is_valid_official_source_evidence(staging.source_evidence)
  ) THEN
    RAISE EXCEPTION 'invalid_enrichment_staging_ownership';
  END IF;

  current_observation := public.sanitize_card_enrichment_observation(
    _result_summary->'observation', statement_timestamp()
  );
  observation_history := public.normalize_card_enrichment_observation_history(
    job_row.result_summary->'observations',
    _result_summary->'observation',
    statement_timestamp()
  );
  safe_summary := public.sanitize_card_enrichment_result_summary(_result_summary) ||
    jsonb_build_object('observations', observation_history);
  IF current_observation IS NOT NULL THEN
    safe_summary := safe_summary || jsonb_build_object('observation', current_observation);
  END IF;

  UPDATE public.card_catalog_enrichment_jobs
  SET status = _status,
      lease_expires_at = NULL,
      lease_token = NULL,
      staging_id = coalesce(_staging_id, job_row.staging_id),
      content_hash = coalesce(_content_hash, job_row.content_hash),
      normalized_fields = coalesce(_normalized_fields, '{}'::jsonb),
      result_summary = safe_summary,
      failure_category = _failure_category,
      next_retry_at = _next_retry_at,
      next_run_at = NULL,
      updated_at = now()
  WHERE id = _job_id
    AND status = 'processing'
    AND lease_token = _lease_token;
  GET DIAGNOSTICS affected_rows = ROW_COUNT;
  IF affected_rows <> 1 THEN RAISE EXCEPTION 'stale_enrichment_lease'; END IF;
  RETURN _job_id;
END;
$$;

REVOKE ALL ON FUNCTION public.card_enrichment_jitter_days(uuid, integer)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.card_enrichment_jitter_days(uuid, integer)
  TO service_role;
REVOKE ALL ON FUNCTION public.next_card_enrichment_observation_at(uuid, timestamptz, boolean, boolean, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.next_card_enrichment_observation_at(uuid, timestamptz, boolean, boolean, text)
  TO service_role;
REVOKE ALL ON FUNCTION public.sanitize_card_enrichment_source_attempt(jsonb, timestamptz)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.sanitize_card_enrichment_source_attempt(jsonb, timestamptz)
  TO service_role;
REVOKE ALL ON FUNCTION public.bounded_card_enrichment_timestamp(text, timestamptz)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.bounded_card_enrichment_timestamp(text, timestamptz)
  TO service_role;
REVOKE ALL ON FUNCTION public.sanitize_card_enrichment_observation(jsonb, timestamptz)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.sanitize_card_enrichment_observation(jsonb, timestamptz)
  TO service_role;
REVOKE ALL ON FUNCTION public.normalize_card_enrichment_observation_history(jsonb, jsonb, timestamptz)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.normalize_card_enrichment_observation_history(jsonb, jsonb, timestamptz)
  TO service_role;
REVOKE ALL ON FUNCTION public.sanitize_card_enrichment_result_summary(jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.sanitize_card_enrichment_result_summary(jsonb)
  TO service_role;
REVOKE ALL ON FUNCTION public.card_has_unresolved_catalog_identity(uuid, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.card_has_unresolved_catalog_identity(uuid, text)
  TO service_role;
REVOKE ALL ON FUNCTION public.schedule_terminal_card_enrichment_observation()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.requeue_due_card_catalog_enrichment_jobs(text, integer, timestamptz)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.requeue_due_card_catalog_enrichment_jobs(text, integer, timestamptz)
  TO service_role;
REVOKE ALL ON FUNCTION public.claim_card_catalog_enrichment_jobs(integer, integer, text, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_card_catalog_enrichment_jobs(integer, integer, text, text)
  TO service_role;
REVOKE ALL ON FUNCTION public.finalize_card_catalog_enrichment_job(
  uuid, uuid, text, uuid, text, jsonb, jsonb, text, timestamptz
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.finalize_card_catalog_enrichment_job(
  uuid, uuid, text, uuid, text, jsonb, jsonb, text, timestamptz
) TO service_role;

DO $recurrence_policy_assertions$
BEGIN
  IF public.card_enrichment_jitter_days('00000000-0000-4000-8000-000000000000', 3) <> 3
     OR public.card_enrichment_jitter_days('11111111-1111-4111-8111-111111111111', 3) <> -2
     OR public.card_enrichment_jitter_days('00000000-0000-4000-8000-000000000000', 1) <> -1
     OR public.next_card_enrichment_observation_at(
       '22222222-2222-4222-8222-222222222222',
       '2024-01-31T12:00:00Z', false, false, 'success'
     ) <> '2024-03-01T12:00:00Z'::timestamptz
     OR public.next_card_enrichment_observation_at(
       '00000000-0000-4000-8000-000000000000',
       '2025-12-31T00:00:00Z', false, false, 'failed'
     ) <> '2026-01-06T00:00:00Z'::timestamptz
     OR public.next_card_enrichment_observation_at(
       '00000000-0000-4000-8000-000000000000',
       '2025-12-31T00:00:00Z', true, false, 'success'
     ) IS NOT NULL THEN
    RAISE EXCEPTION 'recurrence policy assertion failed';
  END IF;
END;
$recurrence_policy_assertions$;

DO $recurrence_history_assertions$
DECLARE
  history jsonb;
BEGIN
  SELECT public.normalize_card_enrichment_observation_history(
    coalesce(jsonb_agg(jsonb_build_object(
      'observed_at', to_char(day_value, 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
      'crawl_complete', true,
      'crawl_reason', 'complete',
      'source_manifest_hash', repeat('a', 64),
      'canonical_benefit_hash', repeat('b', 64),
      'body', 'must-not-survive'
    ) ORDER BY day_value), '[]'::jsonb) || jsonb_build_array(
      jsonb_build_object('observed_at', '2999-01-01T00:00:00Z'),
      jsonb_build_object('observed_at', 'malformed')
    ),
    jsonb_build_object(
      'observed_at', '2026-08-26T00:00:00Z',
      'crawl_complete', true,
      'crawl_reason', 'duplicate',
      'source_manifest_hash', repeat('a', 64),
      'canonical_benefit_hash', repeat('b', 64)
    ),
    '2026-09-01T00:00:00Z'
  ) INTO history
  FROM generate_series(
    '2026-08-01T00:00:00Z'::timestamptz,
    '2026-08-26T00:00:00Z'::timestamptz,
    interval '1 day'
  ) AS days(day_value);
  IF jsonb_array_length(history) <> 24
     OR history->0->>'observed_at' <> '2026-08-26T00:00:00+00:00'
     OR history->23->>'observed_at' <> '2026-08-03T00:00:00+00:00'
     OR history::text LIKE '%must-not-survive%'
     OR history::text LIKE '%2999-01-01%' THEN
    RAISE EXCEPTION 'recurrence history assertion failed';
  END IF;
END;
$recurrence_history_assertions$;

COMMIT;
