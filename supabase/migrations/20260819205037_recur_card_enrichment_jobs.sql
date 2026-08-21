BEGIN;

SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '120s';

CREATE INDEX IF NOT EXISTS idx_card_catalog_enrichment_jobs_recurrence_v6
  ON public.card_catalog_enrichment_jobs (
    parser_version, run_mode, status, next_run_at, issuer, id
  )
  WHERE parser_version = 'benefits-v6'
    AND status IN ('completed', 'staged', 'quarantined', 'review_required', 'failed');

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

CREATE OR REPLACE FUNCTION public.canonical_card_enrichment_timestamp(
  _value text
) RETURNS timestamptz
LANGUAGE plpgsql
IMMUTABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  parts text[];
  parsed_value timestamptz;
  offset_hour integer;
  offset_minute integer;
BEGIN
  IF _value IS NULL OR length(_value) > 48 THEN RETURN NULL; END IF;
  parts := regexp_match(
    _value,
    '^(\d{4}-\d{2}-\d{2})[ T](\d{2}:\d{2}:\d{2})(?:\.(\d{1,6}))?(Z|([+-])(\d{2})(?::?(\d{2}))?)$'
  );
  IF parts IS NULL THEN RETURN NULL; END IF;
  offset_hour := CASE WHEN upper(parts[4]) = 'Z' THEN 0 ELSE parts[6]::integer END;
  offset_minute := CASE WHEN upper(parts[4]) = 'Z' THEN 0
    ELSE coalesce(parts[7], '0')::integer END;
  IF offset_hour > 14 OR offset_minute > 59
     OR (offset_hour = 14 AND offset_minute <> 0) THEN RETURN NULL; END IF;
  BEGIN
    parsed_value := _value::timestamptz;
  EXCEPTION WHEN OTHERS THEN
    RETURN NULL;
  END;
  RETURN parsed_value;
END;
$$;

-- Pilot evidence can contain Edge ISO strings or PostgreSQL timestamptz text.
-- Normalize both to the same six-microsecond UTC instant and reject invalid or
-- implausible values before they participate in a promotion proof.
CREATE OR REPLACE FUNCTION public.card_enrichment_pilot_timestamp(
  _value text
) RETURNS timestamptz
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  parts text[];
  canonical_value text;
  parsed_value timestamptz;
  offset_hour integer;
  offset_minute integer;
BEGIN
  IF _value IS NULL OR length(_value) > 48 THEN RETURN NULL; END IF;
  parts := regexp_match(
    _value,
    '^(\d{4}-\d{2}-\d{2})[ T](\d{2}:\d{2}:\d{2})(?:\.(\d{1,6}))?(Z|([+-])(\d{2})(?::?(\d{2}))?)$'
  );
  IF parts IS NULL THEN RETURN NULL; END IF;
  offset_hour := CASE WHEN upper(parts[4]) = 'Z' THEN 0 ELSE parts[6]::integer END;
  offset_minute := CASE WHEN upper(parts[4]) = 'Z' THEN 0
    ELSE coalesce(parts[7], '0')::integer END;
  IF offset_hour > 14 OR offset_minute > 59
     OR (offset_hour = 14 AND offset_minute <> 0) THEN RETURN NULL; END IF;
  BEGIN
    parsed_value := _value::timestamptz;
  EXCEPTION WHEN OTHERS THEN
    RETURN NULL;
  END;
  canonical_value := public.canonical_card_benefit_row_timestamp(parsed_value);
  IF canonical_value IS NULL OR parsed_value < '2000-01-01T00:00:00Z'::timestamptz
     OR parsed_value > clock_timestamp() + interval '5 minutes' THEN
    RETURN NULL;
  END IF;
  RETURN parsed_value;
END;
$$;

DO $pilot_timestamp_parity_assertions$
BEGIN
  IF public.canonical_card_benefit_row_timestamp(
       public.card_enrichment_pilot_timestamp('2026-08-20 00:00:00.1234+00')
     ) <> '2026-08-20T00:00:00.123400Z'
     OR public.canonical_card_benefit_row_timestamp(
       public.card_enrichment_pilot_timestamp('2026-08-20T00:00:00.1235Z')
     ) <> '2026-08-20T00:00:00.123500Z'
     OR public.canonical_card_benefit_row_timestamp(
       public.card_enrichment_pilot_timestamp('2026-08-20T05:30:00.123456+05:30')
     ) <> '2026-08-20T00:00:00.123456Z'
     OR public.canonical_card_benefit_row_timestamp(
       public.card_enrichment_pilot_timestamp('2026-08-19T20:00:00.123456-04:00')
     ) <> '2026-08-20T00:00:00.123456Z' THEN
    RAISE EXCEPTION 'pilot timestamp parity assertion failed';
  END IF;
END;
$pilot_timestamp_parity_assertions$;

CREATE OR REPLACE FUNCTION public.next_card_enrichment_observation_at(
  _card_id uuid,
  _completed_at text,
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
  completed_at_value timestamptz;
  cadence_seconds bigint;
  jitter_days integer;
BEGIN
  completed_at_value := public.canonical_card_enrichment_timestamp(_completed_at);
  IF _card_id IS NULL OR completed_at_value IS NULL
     OR completed_at_value > statement_timestamp() + interval '5 minutes'
     OR _is_discontinued IS NULL OR _has_active_cardholder IS NULL THEN
    RAISE EXCEPTION 'invalid_recurrence_policy';
  END IF;
  IF _is_discontinued AND NOT _has_active_cardholder THEN
    RETURN NULL;
  END IF;
  IF normalized_outcome IN ('success', 'not_modified') THEN
    cadence_seconds := extract(epoch FROM interval '30 days')::bigint;
    jitter_days := public.card_enrichment_jitter_days(_card_id, 3);
  ELSIF normalized_outcome IN ('blocked', 'missing', 'failed') THEN
    cadence_seconds := extract(epoch FROM interval '7 days')::bigint;
    jitter_days := public.card_enrichment_jitter_days(_card_id, 1);
  ELSE
    RAISE EXCEPTION 'invalid_recurrence_outcome';
  END IF;
  RETURN to_timestamp(
    extract(epoch FROM completed_at_value) + cadence_seconds +
    (jitter_days::bigint * 86400)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.bounded_card_enrichment_timestamp(
  _value text,
  _now timestamptz
) RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  parsed_value timestamptz;
BEGIN
  IF _value IS NULL OR length(_value) > 64 OR _now IS NULL THEN RETURN NULL; END IF;
  parsed_value := public.canonical_card_enrichment_timestamp(_value);
  IF parsed_value IS NULL THEN RETURN NULL; END IF;
  IF parsed_value < '2000-01-01T00:00:00Z'::timestamptz
     OR parsed_value > _now + interval '5 minutes' THEN
    RETURN NULL;
  END IF;
  RETURN public.canonical_card_benefit_row_timestamp(parsed_value);
END;
$$;

DO $recurrence_timestamp_offset_assertions$
BEGIN
  IF public.bounded_card_enrichment_timestamp(
       '2026-08-20T05:30:00.123456+05:30',
       '2026-08-21T00:00:00Z'::timestamptz
     ) <> '2026-08-20T00:00:00.123456Z'
     OR public.bounded_card_enrichment_timestamp(
       '2026-08-19T20:00:00.123456-04:00',
       '2026-08-21T00:00:00Z'::timestamptz
     ) <> '2026-08-20T00:00:00.123456Z'
     OR public.bounded_card_enrichment_timestamp(
       '2026-08-20 00:00:00.1234+00',
       '2026-08-21T00:00:00Z'::timestamptz
     ) <> '2026-08-20T00:00:00.123400Z'
     OR public.bounded_card_enrichment_timestamp(
       '2026-02-30T00:00:00Z',
       '2026-08-21T00:00:00Z'::timestamptz
     ) IS NOT NULL THEN
    RAISE EXCEPTION 'recurrence timestamp offset assertion failed';
  END IF;
END;
$recurrence_timestamp_offset_assertions$;

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
  attempted_at_value text;
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
  observed_at_value text;
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
    SELECT observation, observation_index::bigint AS source_priority
    FROM jsonb_array_elements(
      CASE WHEN jsonb_typeof(_existing_history) = 'array'
        THEN _existing_history ELSE '[]'::jsonb END
    ) WITH ORDINALITY AS existing(observation, observation_index)
    UNION ALL
    SELECT _current_observation, 0::bigint
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
STABLE
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
    'lease_expired', 'pilot_qualified', 'reviewed_at', 'review_status', 'approved_count',
    'retired_count', 'rejected_count', 'retained_count'
  ] LOOP
    IF _summary ? allowed_key THEN
      allowed_value := _summary->allowed_key;
      allowed_text := allowed_value#>>'{}';
      IF allowed_key = ANY (ARRAY[
        'reused_staging', 'material_proposal', 'successful_no_change',
        'crawl_complete', 'raw_body_stored', 'evidence_passed',
        'idempotency_passed', 'retry_scheduled', 'lease_expired',
        'pilot_qualified'
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
        AND jsonb_typeof(allowed_value) = 'string' THEN
        allowed_text := public.bounded_card_enrichment_timestamp(
          allowed_text, statement_timestamp()
        );
        IF allowed_text IS NOT NULL THEN
          safe_summary := jsonb_set(
            safe_summary, ARRAY[allowed_key], to_jsonb(allowed_text), true
          );
        END IF;
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

CREATE OR REPLACE FUNCTION public.card_enrichment_job_has_pending_staging(
  _staging_id uuid,
  _card_id uuid,
  _parser_version text
) RETURNS boolean
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
  SELECT _staging_id IS NOT NULL AND EXISTS (
    SELECT 1
    FROM public.card_benefits_staging AS staging
    WHERE staging.id = _staging_id
      AND staging.card_id = _card_id
      AND staging.parser_version = _parser_version
      AND staging.request_type = 'official_benefit_enrichment'
      AND staging.status = 'pending'
  );
$$;

CREATE OR REPLACE FUNCTION public.card_enrichment_requeue_action(
  _run_mode text,
  _status text,
  _next_run_at timestamptz,
  _now timestamptz,
  _eligible boolean,
  _has_pending_staging boolean
) RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF _now IS NULL OR _eligible IS NULL OR _has_pending_staging IS NULL
     OR _status NOT IN ('completed', 'staged', 'quarantined', 'review_required', 'failed') THEN
    RETURN 'none';
  END IF;
  IF _run_mode <> 'scheduled' THEN
    RETURN CASE WHEN _next_run_at IS NULL THEN 'none' ELSE 'clear' END;
  END IF;
  IF NOT _eligible THEN
    RETURN CASE WHEN _next_run_at IS NULL THEN 'none' ELSE 'clear' END;
  END IF;
  IF _next_run_at IS NULL OR _next_run_at <= _now THEN
    RETURN 'queue';
  END IF;
  RETURN 'none';
END;
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
     AND NEW.run_mode = 'scheduled'
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
    IF public.card_has_unresolved_catalog_identity(NEW.card_id, NEW.canonical_url) THEN
      NEW.next_run_at := NULL;
      RETURN NEW;
    END IF;
    terminal_disposition := lower(coalesce(
      NEW.result_summary#>>'{source_observation,terminal_disposition}',
      NEW.result_summary#>>'{observation,source_observation,terminal_disposition}',
      NEW.result_summary->>'terminal_disposition',
      ''
    ));
    recurrence_outcome := CASE
      WHEN terminal_disposition = 'not_modified' THEN 'not_modified'
      WHEN terminal_disposition IN ('missing', 'not_found')
        OR NEW.failure_category IN ('http_404', 'http_410', 'missing') THEN 'missing'
      WHEN terminal_disposition IN ('blocked', 'review_required')
        OR NEW.failure_category IN ('http_401', 'http_403', 'http_429', 'robots_disallowed', 'challenge_page')
        THEN 'blocked'
      WHEN NEW.failure_category IS NOT NULL
        OR terminal_disposition IN ('failed', 'timeout', 'unreachable', 'http_5xx')
        THEN 'failed'
      WHEN NEW.status IN ('completed', 'staged') THEN 'success'
      ELSE 'failed'
    END;
    NEW.next_run_at := public.next_card_enrichment_observation_at(
      NEW.card_id,
      to_char(
        statement_timestamp() AT TIME ZONE 'UTC',
        'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
      ),
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
BEFORE INSERT OR UPDATE OF status, next_retry_at, result_summary, failure_category,
  parser_version, run_mode, staging_id, canonical_url, card_id
ON public.card_catalog_enrichment_jobs
FOR EACH ROW EXECUTE FUNCTION public.schedule_terminal_card_enrichment_observation();

CREATE OR REPLACE FUNCTION public.card_enrichment_pilot_job_is_qualified(
  _status text,
  _failure_category text,
  _summary jsonb
) RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  MAX_PILOT_REVIEW_COUNT constant bigint := 999999999;
  approved_count bigint;
  retained_count bigint;
  retired_count bigint;
  rejected_count bigint;
  approved_numeric numeric;
  retained_numeric numeric;
  retired_numeric numeric;
  rejected_numeric numeric;
  review_keys text[] := ARRAY[
    'review_status', 'approved_count', 'retained_count',
    'retired_count', 'rejected_count'
  ];
BEGIN
  IF jsonb_typeof(_summary) <> 'object'
     OR NOT (_summary ? 'unsafe_mutation_count')
     OR jsonb_typeof(_summary->'unsafe_mutation_count') <> 'number'
     OR _summary->'unsafe_mutation_count' IS DISTINCT FROM '0'::jsonb
     OR _summary->'idempotency_passed' IS DISTINCT FROM 'true'::jsonb
     OR NOT (_summary ? 'raw_body_stored')
     OR jsonb_typeof(_summary->'raw_body_stored') <> 'boolean'
     OR _summary->'raw_body_stored' IS DISTINCT FROM 'false'::jsonb
     OR _status NOT IN ('staged', 'completed', 'quarantined') THEN
    RETURN false;
  END IF;
  IF _status = 'quarantined' THEN
    RETURN trim(coalesce(_failure_category, '')) ~ '^[a-z0-9_]{1,64}$';
  END IF;
  IF _summary->'evidence_passed' IS DISTINCT FROM 'true'::jsonb THEN
    RETURN false;
  END IF;
  IF _status = 'staged' THEN RETURN true; END IF;

  IF _summary->'successful_no_change' = 'true'::jsonb
     AND NOT (_summary ?| review_keys) THEN
    RETURN true;
  END IF;
  IF jsonb_typeof(_summary->'review_status') IS DISTINCT FROM 'string'
     OR _summary->>'review_status' IS DISTINCT FROM 'approved'
     OR NOT (_summary ? 'approved_count')
     OR NOT (_summary ? 'retained_count')
     OR NOT (_summary ? 'retired_count')
     OR NOT (_summary ? 'rejected_count')
     OR jsonb_typeof(_summary->'approved_count') IS DISTINCT FROM 'number'
     OR jsonb_typeof(_summary->'retained_count') IS DISTINCT FROM 'number'
     OR jsonb_typeof(_summary->'retired_count') IS DISTINCT FROM 'number'
     OR jsonb_typeof(_summary->'rejected_count') IS DISTINCT FROM 'number' THEN
    RETURN false;
  END IF;
  approved_numeric := (_summary->>'approved_count')::numeric;
  retained_numeric := (_summary->>'retained_count')::numeric;
  retired_numeric := (_summary->>'retired_count')::numeric;
  rejected_numeric := (_summary->>'rejected_count')::numeric;
  IF approved_numeric <> trunc(approved_numeric)
     OR retained_numeric <> trunc(retained_numeric)
     OR retired_numeric <> trunc(retired_numeric)
     OR rejected_numeric <> trunc(rejected_numeric)
     OR approved_numeric NOT BETWEEN 0 AND MAX_PILOT_REVIEW_COUNT
     OR retained_numeric NOT BETWEEN 0 AND MAX_PILOT_REVIEW_COUNT
     OR retired_numeric NOT BETWEEN 0 AND MAX_PILOT_REVIEW_COUNT
     OR rejected_numeric NOT BETWEEN 0 AND MAX_PILOT_REVIEW_COUNT THEN
    RETURN false;
  END IF;
  approved_count := approved_numeric::bigint;
  retained_count := retained_numeric::bigint;
  retired_count := retired_numeric::bigint;
  rejected_count := rejected_numeric::bigint;
  RETURN rejected_count = 0
    AND approved_count + retained_count + retired_count > 0;
END;
$$;

CREATE OR REPLACE FUNCTION public.card_enrichment_enqueue_catalog_eligible(
  _card_id uuid,
  _input_issuer text,
  _input_url text,
  _input_url_hash text,
  _card_bank text,
  _card_url text,
  _card_type text,
  _is_discontinued boolean,
  _has_active_cardholder boolean,
  _has_unresolved_identity boolean
) RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
SECURITY INVOKER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  canonical_catalog_url text;
  canonical_input_url text;
BEGIN
  canonical_catalog_url := regexp_replace(
    split_part(split_part(trim(coalesce(_card_url, '')), '#', 1), '?', 1),
    '/+$', ''
  );
  canonical_input_url := regexp_replace(
    split_part(split_part(trim(coalesce(_input_url, '')), '#', 1), '?', 1),
    '/+$', ''
  );
  RETURN _card_id IS NOT NULL
    AND length(trim(coalesce(_card_bank, ''))) BETWEEN 2 AND 120
    AND lower(trim(coalesce(_input_issuer, ''))) = lower(trim(_card_bank))
    AND lower(trim(coalesce(_card_type, ''))) = 'credit'
    AND trim(coalesce(_input_url, '')) ~ '^https://[^/@?#]+'
    AND canonical_input_url = canonical_catalog_url
    AND lower(coalesce(_input_url_hash, '')) = encode(
      extensions.digest(convert_to(trim(_input_url), 'UTF8'), 'sha256'), 'hex'
    )
    AND (
      _is_discontinued IS DISTINCT FROM true
      OR _has_active_cardholder IS TRUE
    )
    AND _has_unresolved_identity IS FALSE;
END;
$$;

CREATE OR REPLACE FUNCTION public.card_enrichment_enqueue_count_is_valid(
  _requested_count integer,
  _inserted_count integer
) RETURNS boolean
LANGUAGE sql
IMMUTABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
  SELECT _requested_count BETWEEN 1 AND 200
    AND _inserted_count BETWEEN 0 AND _requested_count;
$$;

DO $duplicate_v6_card_parser_preflight$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.card_catalog_enrichment_jobs AS existing_job
    WHERE lower(trim(existing_job.parser_version)) = 'benefits-v6'
    GROUP BY existing_job.card_id, lower(trim(existing_job.parser_version))
    HAVING count(*) > 1
  ) THEN
    RAISE EXCEPTION 'duplicate_v6_card_parser_preflight';
  END IF;
END;
$duplicate_v6_card_parser_preflight$;

-- The preflight deliberately fails rather than rewriting historical jobs.
-- This partial expression index is the final concurrency backstop even when a
-- direct service-role INSERT starts before a competing transaction commits.
CREATE UNIQUE INDEX idx_card_catalog_enrichment_jobs_unique_v6_card_parser
  ON public.card_catalog_enrichment_jobs (
    card_id, (lower(trim(parser_version)))
  )
  WHERE lower(trim(parser_version)) = 'benefits-v6';

CREATE OR REPLACE FUNCTION public.enforce_card_benefit_enrichment_identity()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF lower(trim(NEW.parser_version)) = 'benefits-v6' THEN
    PERFORM pg_advisory_xact_lock(hashtextextended(
      'card_benefit_enrichment_identity:' || NEW.card_id::text ||
        ':benefits-v6',
      0
    ));
    IF EXISTS (
      SELECT 1
      FROM public.card_catalog_enrichment_jobs AS existing_job
      WHERE existing_job.card_id = NEW.card_id
        AND lower(trim(existing_job.parser_version)) = 'benefits-v6'
        AND existing_job.id IS DISTINCT FROM NEW.id
        AND existing_job.job_key IS DISTINCT FROM NEW.job_key
    ) THEN
      RAISE EXCEPTION 'duplicate_v6_card_parser_identity';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS enforce_card_benefit_enrichment_identity
  ON public.card_catalog_enrichment_jobs;
CREATE TRIGGER enforce_card_benefit_enrichment_identity
BEFORE INSERT OR UPDATE OF card_id, parser_version
ON public.card_catalog_enrichment_jobs
FOR EACH ROW EXECUTE FUNCTION public.enforce_card_benefit_enrichment_identity();

CREATE OR REPLACE FUNCTION public.enqueue_card_benefit_enrichment_jobs(
  _jobs jsonb
) RETURNS integer
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  input_count integer;
  invalid_count integer;
  inserted_count integer;
  identity_row record;
  locked_jobs jsonb;
BEGIN
  IF _jobs IS NULL OR jsonb_typeof(_jobs) <> 'array'
     OR jsonb_array_length(_jobs) < 1 OR jsonb_array_length(_jobs) > 200 THEN
    RAISE EXCEPTION 'invalid_enrichment_enqueue';
  END IF;
  WITH input AS (
    SELECT *
    FROM jsonb_to_recordset(_jobs) AS job(
      card_id uuid, issuer text, canonical_url text, final_url_hash text,
      content_hash text, parser_version text, job_key text, run_mode text,
      result_summary jsonb
    )
  )
  SELECT count(*), count(*) FILTER (
    WHERE card_id IS NULL OR length(trim(coalesce(issuer, ''))) < 2
      OR canonical_url IS NULL OR canonical_url !~ '^https://'
      OR final_url_hash IS NULL OR final_url_hash !~ '^[0-9a-f]{64}$'
      OR (content_hash IS NOT NULL AND content_hash !~ '^[0-9a-f]{64}$')
      OR trim(coalesce(parser_version, '')) <> 'benefits-v6'
      OR run_mode IS NULL OR run_mode NOT IN ('pilot', 'scheduled', 'manual')
      OR jsonb_typeof(result_summary) IS DISTINCT FROM 'object'
      OR job_key IS DISTINCT FROM (
        card_id::text || ':' || final_url_hash || ':' || trim(parser_version)
      )
  )
  INTO input_count, invalid_count
  FROM input;
  IF input_count <> jsonb_array_length(_jobs) OR invalid_count <> 0 THEN
    RAISE EXCEPTION 'invalid_enrichment_enqueue';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM jsonb_to_recordset(_jobs) AS duplicate_input(
      card_id uuid, parser_version text
    )
    GROUP BY duplicate_input.card_id, trim(duplicate_input.parser_version)
    HAVING count(*) > 1
  ) THEN
    RAISE EXCEPTION 'duplicate_card_parser_enqueue';
  END IF;

  -- The trigger, this RPC, and pilot initialization share this exact ordered
  -- identity namespace. The RPC then re-reads all mutable authority.
  FOR identity_row IN
    SELECT DISTINCT job.card_id, trim(job.parser_version) AS parser_version
    FROM jsonb_to_recordset(_jobs) AS job(
      card_id uuid, parser_version text
    )
    ORDER BY job.card_id, trim(job.parser_version)
  LOOP
    PERFORM pg_advisory_xact_lock(hashtextextended(
      'card_benefit_enrichment_identity:' || identity_row.card_id::text ||
        ':' || identity_row.parser_version,
      0
    ));
  END LOOP;

  WITH input AS (
    SELECT *
    FROM jsonb_to_recordset(_jobs) AS job(
      card_id uuid, issuer text, canonical_url text, final_url_hash text,
      content_hash text, parser_version text, job_key text, run_mode text,
      result_summary jsonb
    )
  ), locked_enqueue_authority AS MATERIALIZED (
    SELECT input.*, card.bank, card.card_url, card.card_type,
      card.is_discontinued
    FROM input
    JOIN public.card_catalog AS card ON card.id = input.card_id
    ORDER BY card.id
    FOR UPDATE OF card
  )
  SELECT coalesce(
    jsonb_agg(to_jsonb(authority) ORDER BY authority.card_id),
    '[]'::jsonb
  )
  INTO locked_jobs
  FROM locked_enqueue_authority AS authority;

  -- Stabilize existing active-holder evidence before the final eligibility
  -- check. A new holder can only make a previously ineligible card safer.
  PERFORM holder.id
  FROM public.user_cards AS holder
  WHERE holder.catalog_card_id IN (
    SELECT candidate.card_id
    FROM jsonb_to_recordset(locked_jobs) AS candidate(card_id uuid)
  )
    AND holder.is_active = true
  ORDER BY holder.id
  FOR SHARE;

  -- Lock every currently matching unresolved identity review before the final
  -- exclusion check. Review resolution and enqueue therefore cannot cross on
  -- a stale row; a newly inserted review remains a later independent event.
  PERFORM review.id
  FROM public.card_catalog_review_queue AS review
  LEFT JOIN LATERAL jsonb_array_elements(
    CASE WHEN jsonb_typeof(review.existing_candidates) = 'array'
      THEN review.existing_candidates ELSE '[]'::jsonb END
  ) AS review_candidate(value) ON true
  WHERE review.status = 'pending'
    AND EXISTS (
      SELECT 1
      FROM jsonb_to_recordset(locked_jobs) AS candidate(
        card_id uuid, canonical_url text
      )
      WHERE review_candidate.value->>'id' = candidate.card_id::text
        OR review_candidate.value->>'card_id' = candidate.card_id::text
        OR review_candidate.value->>'cardId' = candidate.card_id::text
        OR review.proposed_fields->>'card_id' = candidate.card_id::text
        OR review.proposed_fields->>'cardId' = candidate.card_id::text
        OR review.proposed_fields->>'existing_card_id' = candidate.card_id::text
        OR regexp_replace(split_part(split_part(coalesce(
          review.proposed_fields->>'official_url',
          review.proposed_fields->>'card_url',
          review.proposed_fields->>'source_url',
          review.source_evidence->>'official_url',
          review.source_evidence->>'source_url',
          ''
        ), '#', 1), '?', 1), '/+$', '') =
          regexp_replace(split_part(split_part(candidate.canonical_url, '#', 1), '?', 1), '/+$', '')
    )
  ORDER BY review.id
  FOR SHARE OF review;

  SELECT count(*) FILTER (
    WHERE NOT public.card_enrichment_enqueue_catalog_eligible(
      candidate.card_id,
      candidate.issuer,
      candidate.canonical_url,
      candidate.final_url_hash,
      candidate.bank,
      candidate.card_url,
      candidate.card_type,
      candidate.is_discontinued,
      EXISTS (
        SELECT 1 FROM public.user_cards AS holder
        WHERE holder.catalog_card_id = candidate.card_id
          AND holder.is_active = true
      ),
      public.card_has_unresolved_catalog_identity(
        candidate.card_id, candidate.canonical_url
      )
    )
  )
  INTO invalid_count
  FROM jsonb_to_recordset(locked_jobs) AS candidate(
    card_id uuid, issuer text, canonical_url text, final_url_hash text,
    content_hash text, parser_version text, job_key text, run_mode text,
    result_summary jsonb, bank text, card_url text, card_type text,
    is_discontinued boolean
  );
  IF jsonb_array_length(locked_jobs) <> input_count OR invalid_count <> 0 THEN
    RAISE EXCEPTION 'ineligible_enrichment_enqueue';
  END IF;

  -- A changed job key for an existing v6 card/parser is an identity conflict,
  -- never a partial batch success. Exact repeats remain idempotent.
  IF EXISTS (
    SELECT 1
    FROM jsonb_to_recordset(locked_jobs) AS candidate(
      card_id uuid, parser_version text, job_key text
    )
    JOIN public.card_catalog_enrichment_jobs AS existing_job
      ON existing_job.card_id = candidate.card_id
     AND existing_job.parser_version = candidate.parser_version
    WHERE existing_job.job_key IS DISTINCT FROM candidate.job_key
  ) THEN
    RAISE EXCEPTION 'duplicate_v6_card_parser_identity';
  END IF;

  INSERT INTO public.card_catalog_enrichment_jobs (
    card_id, issuer, canonical_url, final_url_hash, content_hash,
    parser_version, status, run_mode, job_key, result_summary, updated_at
  )
  SELECT candidate.card_id, trim(candidate.issuer),
    trim(candidate.canonical_url), lower(candidate.final_url_hash),
    lower(candidate.content_hash), trim(candidate.parser_version), 'queued',
    candidate.run_mode, candidate.job_key, candidate.result_summary,
    statement_timestamp()
  FROM jsonb_to_recordset(locked_jobs) AS candidate(
    card_id uuid, issuer text, canonical_url text, final_url_hash text,
    content_hash text, parser_version text, job_key text, run_mode text,
    result_summary jsonb
  )
  ORDER BY candidate.card_id, trim(candidate.parser_version)
  ON CONFLICT (job_key) DO NOTHING;
  GET DIAGNOSTICS inserted_count = ROW_COUNT;
  IF NOT public.card_enrichment_enqueue_count_is_valid(
    input_count, inserted_count
  ) THEN
    RAISE EXCEPTION 'invalid_enrichment_enqueue_count';
  END IF;
  RETURN inserted_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.card_enrichment_pilot_cohort_action(
  _pilot_count integer,
  _promoted_count integer,
  _has_duplicate boolean
) RETURNS text
LANGUAGE sql
IMMUTABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
  SELECT CASE
    WHEN _pilot_count IS NULL OR _promoted_count IS NULL
      OR _pilot_count < 0 OR _promoted_count < 0
      OR coalesce(_has_duplicate, true) THEN 'reject'
    WHEN _pilot_count = 0 AND _promoted_count = 0 THEN 'initialize'
    WHEN _pilot_count = 5 AND _promoted_count = 0 THEN 'return_pilot'
    WHEN _pilot_count = 0 AND _promoted_count = 5 THEN 'return_promoted'
    ELSE 'reject'
  END;
$$;

-- Replace the original initializer without changing its signature. Promotion
-- and initialization serialize on one parser-scoped key, so a caller after a
-- successful handoff observes the same five jobs instead of creating 5+5.
CREATE OR REPLACE FUNCTION public.initialize_card_benefit_enrichment_pilot(
  _candidates jsonb,
  _parser_version text
) RETURNS SETOF public.card_catalog_enrichment_jobs
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  selected_parser text := CASE
    WHEN lower(trim(coalesce(_parser_version, ''))) = 'benefits-v6'
      THEN 'benefits-v6'
    ELSE trim(coalesce(_parser_version, ''))
  END;
  pilot_count integer;
  promoted_count integer;
  pilot_card_count integer;
  pilot_profile_count integer;
  pilot_issuer_count integer;
  pilot_profiles text[];
  pilot_issuer_values_valid boolean;
  has_duplicate boolean;
  cohort_action text;
  eligible_count integer;
  distinct_card_count integer;
  distinct_profile_count integer;
  distinct_issuer_count integer;
  inserted_count integer;
  locked_candidates jsonb;
  candidate_identity record;
BEGIN
  IF coalesce(auth.role(), '') <> 'service_role' THEN
    RAISE EXCEPTION 'service_role_required';
  END IF;
  IF _candidates IS NULL OR jsonb_typeof(_candidates) <> 'array'
     OR jsonb_array_length(_candidates) <> 5
     OR length(selected_parser) < 3 THEN
    RAISE EXCEPTION 'invalid_pilot_candidates';
  END IF;
  IF lower(selected_parser) = 'catalog-v1' THEN
    RAISE EXCEPTION 'reserved_parser_version';
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended('card_benefit_enrichment_pilot:' || selected_parser, 0)
  );
  WITH locked_cohort AS MATERIALIZED (
    SELECT job.*
    FROM public.card_catalog_enrichment_jobs AS job
    WHERE job.parser_version = selected_parser
      AND (
        job.run_mode = 'pilot'
        OR (
          job.run_mode = 'scheduled'
          AND job.result_summary->'pilot_qualified' = 'true'::jsonb
        )
      )
    ORDER BY job.id
    FOR UPDATE OF job
  )
  SELECT count(*) FILTER (WHERE locked_cohort.run_mode = 'pilot'),
    count(*) FILTER (WHERE locked_cohort.run_mode = 'scheduled')
  INTO pilot_count, promoted_count
  FROM locked_cohort;
  SELECT EXISTS (
    SELECT 1
    FROM public.card_catalog_enrichment_jobs AS cohort_job
    JOIN public.card_catalog_enrichment_jobs AS other_job
      ON other_job.card_id = cohort_job.card_id
     AND other_job.parser_version = cohort_job.parser_version
     AND other_job.id <> cohort_job.id
    WHERE cohort_job.parser_version = selected_parser
      AND (
        cohort_job.run_mode = 'pilot'
        OR (
          cohort_job.run_mode = 'scheduled'
          AND cohort_job.result_summary->'pilot_qualified' = 'true'::jsonb
        )
      )
  ) INTO has_duplicate;
  cohort_action := public.card_enrichment_pilot_cohort_action(
    pilot_count, promoted_count, has_duplicate
  );

  IF cohort_action = 'return_promoted' THEN
    RETURN QUERY
    SELECT job.*
    FROM public.card_catalog_enrichment_jobs AS job
    JOIN public.card_catalog AS card ON card.id = job.card_id
    WHERE job.parser_version = selected_parser
      AND job.run_mode = 'scheduled'
      AND job.result_summary->'pilot_qualified' = 'true'::jsonb
    ORDER BY job.issuer, card.card_name, job.created_at;
    RETURN;
  ELSIF cohort_action = 'return_pilot' THEN
    RETURN QUERY
    SELECT job.*
    FROM public.card_catalog_enrichment_jobs AS job
    JOIN public.card_catalog AS card ON card.id = job.card_id
    WHERE job.parser_version = selected_parser
      AND job.run_mode = 'pilot'
    ORDER BY job.issuer, card.card_name, job.created_at;
    RETURN;
  ELSIF cohort_action <> 'initialize' THEN
    RAISE EXCEPTION 'pilot_state_incomplete';
  END IF;

  FOR candidate_identity IN
    SELECT DISTINCT candidate.card_id
    FROM jsonb_to_recordset(_candidates)
      AS candidate(card_id uuid, profile text)
    ORDER BY candidate.card_id
  LOOP
    PERFORM pg_advisory_xact_lock(hashtextextended(
      'card_benefit_enrichment_identity:' || candidate_identity.card_id::text ||
        ':' || selected_parser,
      0
    ));
  END LOOP;

  WITH input AS (
    SELECT candidate.card_id, lower(trim(candidate.profile)) AS profile
    FROM jsonb_to_recordset(_candidates)
      AS candidate(card_id uuid, profile text)
  ), locked_candidate_authority AS MATERIALIZED (
    SELECT input.card_id, input.profile, card.bank, card.card_url,
      card.is_discontinued, card.card_type
    FROM input
    JOIN public.card_catalog AS card ON card.id = input.card_id
    ORDER BY card.id
    FOR UPDATE OF card
  )
  SELECT coalesce(
    jsonb_agg(to_jsonb(authority) ORDER BY authority.card_id),
    '[]'::jsonb
  )
  INTO locked_candidates
  FROM locked_candidate_authority AS authority;

  WITH eligible AS (
    SELECT candidate.*
    FROM jsonb_to_recordset(locked_candidates) AS candidate(
      card_id uuid, profile text, bank text, card_url text,
      is_discontinued boolean, card_type text
    )
    WHERE candidate.is_discontinued = false
      AND lower(trim(candidate.card_type)) = 'credit'
      AND candidate.card_url ~ '^https://'
      AND candidate.profile IN (
        'straightforward', 'redirect_or_js', 'terms_linked',
        'known_invalid', 'additional_valid'
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.card_catalog_enrichment_jobs AS existing_job
        WHERE existing_job.card_id = candidate.card_id
          AND existing_job.parser_version = selected_parser
      )
  )
  SELECT count(*), count(DISTINCT card_id), count(DISTINCT profile),
         count(DISTINCT lower(trim(bank)))
  INTO eligible_count, distinct_card_count, distinct_profile_count,
       distinct_issuer_count
  FROM eligible;

  IF eligible_count <> 5 OR distinct_card_count <> 5
     OR distinct_profile_count <> 5 OR distinct_issuer_count < 3 THEN
    RAISE EXCEPTION 'invalid_pilot_candidates';
  END IF;

  INSERT INTO public.card_catalog_enrichment_jobs (
    card_id, issuer, canonical_url, final_url_hash, content_hash,
    parser_version, status, run_mode, job_key, result_summary, updated_at
  )
  SELECT candidate.card_id, candidate.bank, trim(candidate.card_url),
    encode(extensions.digest(convert_to(trim(candidate.card_url), 'UTF8'), 'sha256'), 'hex'),
    NULL, selected_parser, 'queued', 'pilot',
    candidate.card_id::text || ':' ||
      encode(extensions.digest(convert_to(trim(candidate.card_url), 'UTF8'), 'sha256'), 'hex') ||
      ':' || selected_parser,
    jsonb_build_object(
      'pilot_profile', candidate.profile,
      'unsafe_mutation_count', 0,
      'raw_body_stored', false,
      'evidence_passed', false,
      'idempotency_passed', false
    ),
    now()
  FROM jsonb_to_recordset(locked_candidates) AS candidate(
    card_id uuid, profile text, bank text, card_url text,
    is_discontinued boolean, card_type text
  )
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.card_catalog_enrichment_jobs AS existing_job
    WHERE existing_job.card_id = candidate.card_id
      AND existing_job.parser_version = selected_parser
  )
  ON CONFLICT (job_key) DO NOTHING;
  GET DIAGNOSTICS inserted_count = ROW_COUNT;
  IF inserted_count <> 5 THEN
    RAISE EXCEPTION 'pilot_candidate_conflict';
  END IF;

  RETURN QUERY
  SELECT job.*
  FROM public.card_catalog_enrichment_jobs AS job
  JOIN public.card_catalog AS card ON card.id = job.card_id
  WHERE job.parser_version = selected_parser
    AND job.run_mode = 'pilot'
  ORDER BY job.issuer, card.card_name, job.created_at;
END;
$$;

CREATE OR REPLACE FUNCTION public.card_enrichment_pilot_snapshot_rows(
  _rows jsonb
) RETURNS jsonb
LANGUAGE sql
IMMUTABLE
SECURITY INVOKER
SET search_path = public, extensions, pg_temp
AS $$
  SELECT jsonb_build_object(
    'count', jsonb_array_length(_rows),
    'row_hash', encode(extensions.digest(
      convert_to(public.canonical_json_text(_rows), 'UTF8'), 'sha256'
    ), 'hex')
  );
$$;

CREATE OR REPLACE FUNCTION public.card_enrichment_pilot_live_state_snapshot(
  _card_id uuid
) RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public, extensions, pg_temp
AS $$
  -- The Task4 helper is the single serializer for card_catalog,
  -- card_benefit_mapping, and public.benefits and uses
  -- canonical_card_benefit_row_timestamp for UTC microsecond parity.
  SELECT public.card_benefit_review_live_state_snapshot(_card_id);
$$;

CREATE OR REPLACE FUNCTION public.capture_card_enrichment_pilot_publication_snapshot()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, extensions, pg_temp
AS $$
BEGIN
  IF NEW.status = 'approved' AND OLD.status IS DISTINCT FROM 'approved'
     AND NEW.parser_version = 'benefits-v6'
     AND EXISTS (
       SELECT 1 FROM public.card_catalog_enrichment_jobs AS job
       WHERE job.card_id = NEW.card_id
         AND job.parser_version = NEW.parser_version
         AND job.normalized_fields->'pilot_evidence'->>'staging_id' = NEW.id::text
     ) THEN
    NEW.extracted_data := jsonb_set(
      NEW.extracted_data,
      '{published_live_state}',
      public.card_enrichment_pilot_live_state_snapshot(NEW.card_id),
      true
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS capture_card_enrichment_pilot_publication_snapshot
  ON public.card_benefits_staging;
CREATE TRIGGER capture_card_enrichment_pilot_publication_snapshot
BEFORE UPDATE OF status ON public.card_benefits_staging
FOR EACH ROW EXECUTE FUNCTION public.capture_card_enrichment_pilot_publication_snapshot();

-- Promotion never trusts worker/admin booleans alone.  This validator is
-- called only while the exact job, staging, catalog-review, mapping, benefit,
-- and catalog rows are locked by the promotion RPC below.
CREATE OR REPLACE FUNCTION public.card_enrichment_pilot_source_identity_hash(
  _url text
) RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SECURITY INVOKER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  parts text[];
  authority text;
  resource_path text;
  resource_query text;
  canonical_url text;
  query_entry text;
  query_key text;
  query_value text;
  decoded_query_value text;
  query_entries text[];
BEGIN
  IF _url IS NULL OR length(trim(_url)) NOT BETWEEN 9 AND 2048
     OR trim(_url) ~ '[[:cntrl:][:space:]]' THEN
    RETURN NULL;
  END IF;
  parts := regexp_match(
    trim(_url), '^https://([^/?#]+)([^?#]*)(\?[^#]*)?$', 'i'
  );
  IF parts IS NULL OR parts[1] = '' OR parts[1] LIKE '%@%'
     OR parts[1] !~ '^[A-Za-z0-9.-]+(:[0-9]+)?$' THEN
    RETURN NULL;
  END IF;
  authority := lower(regexp_replace(parts[1], ':443$', '', 'i'));
  resource_path := coalesce(parts[2], '');
  resource_query := coalesce(parts[3], '');
  IF resource_query <> '' THEN
    query_entries := string_to_array(substr(resource_query, 2), '&');
    IF cardinality(query_entries) NOT BETWEEN 1 AND 8 THEN RETURN NULL; END IF;
    FOREACH query_entry IN ARRAY query_entries LOOP
      IF query_entry = '' OR position('=' IN query_entry) < 2
         OR length(split_part(query_entry, '=', 1)) > 64
         OR position('%' IN regexp_replace(
              query_entry, '%[0-9A-Fa-f]{2}', '', 'g'
            )) > 0 THEN
        RETURN NULL;
      END IF;
      query_key := lower(split_part(query_entry, '=', 1));
      query_value := substr(query_entry, position('=' IN query_entry) + 1);
      IF length(query_value) > 512 THEN RETURN NULL; END IF;
      IF query_key NOT IN ('document','file','locale','version') THEN
        RETURN NULL;
      END IF;
      decoded_query_value := replace(query_value, '+', ' ');
      decoded_query_value := regexp_replace(decoded_query_value, '%20', ' ', 'gi');
      decoded_query_value := regexp_replace(decoded_query_value, '%2D', '-', 'gi');
      decoded_query_value := regexp_replace(decoded_query_value, '%2E', '.', 'gi');
      decoded_query_value := regexp_replace(decoded_query_value, '%2F', '/', 'gi');
      decoded_query_value := regexp_replace(decoded_query_value, '%5F', '_', 'gi');
      decoded_query_value := regexp_replace(decoded_query_value, '%7E', '~', 'gi');
      IF decoded_query_value ~* '(authorization|bearer|access[_ -]?token|refresh[_ -]?token|lease[_ -]?token|password|secret|credential|customer|account|phone|email|pan|card[_ -]?(number|no\.?))'
         OR decoded_query_value ~* '(@|%40|%(25)+|%3[ad])'
         OR regexp_replace(
              query_value, '%(20|2D|2E|2F|5F|7E)', '', 'gi'
            ) !~ '^[A-Za-z0-9._~+/-]+$'
         OR length(regexp_replace(
              decoded_query_value, '[^0-9]', '', 'g'
            )) >= 10 THEN
        RETURN NULL;
      END IF;
    END LOOP;
  END IF;
  -- WHATWG URL serialization retains the root slash before a functional
  -- query and omits it only for a queryless origin.
  IF resource_query <> '' AND resource_path IN ('', '/') THEN
    resource_path := '/';
  ELSIF resource_query = '' AND resource_path IN ('', '/') THEN
    resource_path := '';
  END IF;
  canonical_url := 'https://' || authority || resource_path || resource_query;
  canonical_url := regexp_replace(canonical_url, '/$', '');
  RETURN encode(extensions.digest(convert_to(canonical_url, 'UTF8'), 'sha256'), 'hex');
END;
$$;

CREATE OR REPLACE FUNCTION public.card_enrichment_pilot_queryless_display_url(
  _url text
) RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SECURITY INVOKER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  parts text[];
  authority text;
  resource_path text;
BEGIN
  IF public.card_enrichment_pilot_source_identity_hash(_url) IS NULL THEN
    RETURN NULL;
  END IF;
  parts := regexp_match(
    trim(_url), '^https://([^/?#]+)([^?#]*)(\?[^#]*)?$', 'i'
  );
  IF parts IS NULL THEN RETURN NULL; END IF;
  authority := lower(regexp_replace(parts[1], ':443$', '', 'i'));
  resource_path := regexp_replace(coalesce(parts[2], ''), '/{2,}', '/', 'g');
  IF resource_path IN ('', '/') THEN
    resource_path := '';
  ELSE
    resource_path := regexp_replace(resource_path, '/$', '');
  END IF;
  RETURN 'https://' || authority || resource_path;
END;
$$;

CREATE OR REPLACE FUNCTION public.card_enrichment_pilot_has_contextual_person(
  _text text,
  _known_identity_phrases jsonb
) RETURNS boolean
LANGUAGE sql
IMMUTABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
  SELECT CASE
    WHEN _text IS NULL OR octet_length(convert_to(_text, 'UTF8')) > 65536
      OR jsonb_typeof(_known_identity_phrases) <> 'array'
      OR jsonb_array_length(_known_identity_phrases) > 9
    THEN true
    ELSE EXISTS (
      SELECT 1
      FROM regexp_matches(
        lower(_text),
        '\m(for|to)[[:space:]]+(([[:alpha:]][^[:space:]]{1,})([[:space:]]+[[:alpha:]][^[:space:]]{1,}){1,3}?)([[:space:]]+(is|gets?|receives?|will)\M|[[:space:]]*[.,;:!?]|$)',
        'g'
      ) AS contextual_person(match)
      WHERE NOT EXISTS (
        SELECT 1
        FROM jsonb_array_elements_text(_known_identity_phrases)
          AS exact_identity_phrase(value)
        WHERE trim(lower(exact_identity_phrase.value)) =
          trim(lower(contextual_person.match[2]))
      )
        AND NOT EXISTS (
          -- POSIX alpha excludes combining vowel signs/viramas. Admit a
          -- bounded Unicode Mark set only after an alphabetic first
          -- character; digits, currency, and arbitrary punctuation remain
          -- outside the name-token grammar.
          SELECT 1
          FROM regexp_split_to_table(
            contextual_person.match[2], ''
          ) AS contextual_character(value)
          WHERE contextual_character.value <> ' '
            AND contextual_character.value !~ '^[[:alpha:]]$'
            AND contextual_character.value NOT IN ('''', '-')
            AND NOT (
              ascii(contextual_character.value) BETWEEN 768 AND 879
              OR ascii(contextual_character.value) BETWEEN 6832 AND 6911
              OR ascii(contextual_character.value) BETWEEN 7616 AND 7679
              OR ascii(contextual_character.value) BETWEEN 8400 AND 8447
              OR ascii(contextual_character.value) BETWEEN 65056 AND 65071
              OR ascii(contextual_character.value) BETWEEN 2304 AND 2307
              OR ascii(contextual_character.value) BETWEEN 2362 AND 2383
              OR ascii(contextual_character.value) BETWEEN 2385 AND 2391
              OR ascii(contextual_character.value) BETWEEN 2402 AND 2403
              OR ascii(contextual_character.value) BETWEEN 2433 AND 2435
              OR ascii(contextual_character.value) BETWEEN 2492 AND 2500
              OR ascii(contextual_character.value) BETWEEN 2503 AND 2504
              OR ascii(contextual_character.value) BETWEEN 2507 AND 2509
              OR ascii(contextual_character.value) = 2519
              OR ascii(contextual_character.value) BETWEEN 2530 AND 2531
              OR ascii(contextual_character.value) = 2558
            )
        )
        AND EXISTS (
          SELECT 1
          FROM regexp_split_to_table(
            trim(lower(contextual_person.match[2])), '[[:space:]]+'
          ) AS contextual_word(value)
          WHERE contextual_word.value NOT IN (
            'applicant','applicants','cardholder','cardholders',
            'customer','customers','member','members','user','users',
            'access','accelerated','annual','airport','bank','benefit','benefits',
            'bonus','cap','cashback','card','conditions','complimentary',
            'credit','cover','dining','discount','domestic','earn','enjoy',
            'exclusive','fee','fees','forex','fuel','get','international',
            'insurance','interest','lounge','mastercard','markup','maximum',
            'milestone','miles','minimum','mitc','most','movie','offer',
            'offers','important','points','program','reward','rewards',
            'rupay','spend','surcharge','terms','threshold','ticket',
            'tickets','travel','unlimited','visa','waiver','welcome','zero',
            'apr','renewal'
          )
        )
    )
  END;
$$;

DO $pilot_resource_identity_assertions$
DECLARE
  ordered text := 'https://issuer.example/terms.pdf?document=mitc.pdf&locale=en&version=2&locale=hi';
  reordered text := 'https://issuer.example/terms.pdf?document=mitc.pdf&locale=hi&version=2&locale=en';
BEGIN
  IF public.card_enrichment_pilot_source_identity_hash(ordered) IS NULL
     OR public.card_enrichment_pilot_source_identity_hash(ordered) =
          public.card_enrichment_pilot_source_identity_hash(reordered)
     OR public.card_enrichment_pilot_source_identity_hash(
          'https://issuer.example/terms.pdf?locale=hi&version=2'
        ) IS NULL
     OR public.card_enrichment_pilot_source_identity_hash(
          'https://issuer.example/terms.pdf?file=most%20important%20terms.pdf'
        ) IS NULL
     OR public.card_enrichment_pilot_source_identity_hash(
          'https://issuer.example/terms.pdf?variant=one'
        ) IS NOT NULL
     OR public.card_enrichment_pilot_source_identity_hash(
          'https://issuer.example/terms.pdf?token=secret'
        ) IS NOT NULL
     OR public.card_enrichment_pilot_source_identity_hash(
          'https://issuer.example/terms.pdf?document=secret'
        ) IS NOT NULL
     OR public.card_enrichment_pilot_source_identity_hash(
          'https://issuer.example/terms.pdf?file=access_token%3Dsecret'
        ) IS NOT NULL
     OR public.card_enrichment_pilot_source_identity_hash(
          'https://issuer.example/terms.pdf?file=%61ccess_token%3Dsecret'
        ) IS NOT NULL
     OR public.card_enrichment_pilot_source_identity_hash(
          'https://issuer.example/terms.pdf?file=access%5Ftoken'
        ) IS NOT NULL
     OR public.card_enrichment_pilot_source_identity_hash(
          'https://issuer.example/terms.pdf?document=customer%20id'
        ) IS NOT NULL
     OR public.card_enrichment_pilot_source_identity_hash(
          'https://issuer.example/terms.pdf?file=%73ecret'
        ) IS NOT NULL
     OR public.card_enrichment_pilot_source_identity_hash(
          'https://issuer.example/terms.pdf?file=%FF'
        ) IS NOT NULL
     OR public.card_enrichment_pilot_source_identity_hash(
          'https://issuer.example/terms.pdf?file=%0A'
        ) IS NOT NULL
     OR public.card_enrichment_pilot_source_identity_hash(
          'https://issuer.example/terms.pdf?utm_source=campaign'
        ) IS NOT NULL
     OR public.card_enrichment_pilot_source_identity_hash(
          'https://issuer.example/?locale=en'
        ) IS DISTINCT FROM
          '2b11cd567b1ddbc93697a59fe4a74f972bf7988553f3d43ca34d039e33aa28a5'
     OR public.card_enrichment_pilot_queryless_display_url(
          'https://issuer.example/?locale=en'
        ) IS DISTINCT FROM 'https://issuer.example'
     OR public.card_enrichment_pilot_queryless_display_url(
          'https://issuer.example/card/?document=mitc.pdf'
        ) IS DISTINCT FROM 'https://issuer.example/card'
     THEN
    RAISE EXCEPTION 'pilot resource identity assertion failed';
  END IF;
END;
$pilot_resource_identity_assertions$;

CREATE OR REPLACE FUNCTION public.card_enrichment_pilot_source_manifest_hash(
  _attempts jsonb
) RETURNS text
LANGUAGE sql
IMMUTABLE
SECURITY INVOKER
SET search_path = public, extensions, pg_temp
AS $$
  SELECT CASE WHEN jsonb_typeof(_attempts) = 'array'
                   AND jsonb_array_length(_attempts) BETWEEN 1 AND 9
    THEN encode(extensions.digest(convert_to(coalesce(string_agg(
      public.canonical_json_text(
        (attempt.value - 'attemptedAt' - 'attemptHistory') ||
        CASE WHEN jsonb_typeof(attempt.value->'attemptHistory') = 'array'
          THEN jsonb_build_object('attemptHistory', coalesce((
            SELECT jsonb_agg(history.value - 'attemptedAt' ORDER BY history.ordinality)
            FROM jsonb_array_elements(attempt.value->'attemptHistory')
              WITH ORDINALITY AS history(value, ordinality)
          ), '[]'::jsonb)) ELSE '{}'::jsonb END
      ), E'\n' ORDER BY public.canonical_json_text(
        (attempt.value - 'attemptedAt' - 'attemptHistory') ||
        CASE WHEN jsonb_typeof(attempt.value->'attemptHistory') = 'array'
          THEN jsonb_build_object('attemptHistory', coalesce((
            SELECT jsonb_agg(history.value - 'attemptedAt' ORDER BY history.ordinality)
            FROM jsonb_array_elements(attempt.value->'attemptHistory')
              WITH ORDINALITY AS history(value, ordinality)
          ), '[]'::jsonb)) ELSE '{}'::jsonb END
      )
    ), ''), 'UTF8'), 'sha256'), 'hex') ELSE NULL END
  FROM jsonb_array_elements(CASE WHEN jsonb_typeof(_attempts) = 'array'
    THEN _attempts ELSE '[]'::jsonb END) AS attempt(value);
$$;

CREATE OR REPLACE FUNCTION public.card_enrichment_pilot_evidence_is_qualified(
  _job public.card_catalog_enrichment_jobs,
  _staging public.card_benefits_staging
) RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  evidence jsonb := _job.normalized_fields->'pilot_evidence';
  verification_envelope jsonb;
  repeat_verification_envelope jsonb;
  replay_input jsonb;
  expected_source_resources jsonb;
  expected_required_source_keys jsonb;
  replay_required_source_keys jsonb;
  actual_required_source_keys jsonb;
  current_live_state jsonb;
  observed_at_value timestamptz;
  decisions jsonb;
  proposals jsonb;
  removals jsonb;
  recomputed_canonical_benefit_hash text;
  approved_count integer;
  retained_count integer;
  retired_count integer;
  rejected_count integer;
BEGIN
  current_live_state := public.card_enrichment_pilot_live_state_snapshot(_job.card_id);
  observed_at_value := public.card_enrichment_pilot_timestamp(evidence->>'observed_at');
  IF NOT (
       (_job.run_mode = 'pilot' AND public.card_enrichment_pilot_job_is_qualified(
          _job.status, _job.failure_category, _job.result_summary
        ))
       OR (_job.run_mode = 'scheduled'
         AND _job.result_summary->'pilot_qualified' = 'true'::jsonb)
     )
     OR jsonb_typeof(evidence) <> 'object'
     OR evidence->>'parser_version' IS DISTINCT FROM _job.parser_version
     OR evidence->>'job_id' IS DISTINCT FROM _job.id::text
     OR evidence->>'card_id' IS DISTINCT FROM _job.card_id::text
     OR evidence->>'run_mode' IS DISTINCT FROM 'pilot'
     OR EXISTS (
       SELECT 1 FROM jsonb_object_keys(evidence) AS key(value)
       WHERE key.value NOT IN (
         'parser_version','job_id','card_id','run_mode','canonical_hash',
         'repeat_canonical_hash','deterministic_replay_passed',
         'source_manifest_hash','source_attempts','expected_required_source_keys',
         'required_source_selection_overflow','verification_envelope',
         'repeat_verification_envelope','replay_input','crawl_complete',
         'suppressed_removal_count','unsafe_mutation_count','raw_body_stored',
         'side_effect_proof_passed','observed_at','live_state_before',
         'live_state_after','conflict_count','catalog_identity_conflict_count',
         'proposal_count','proposal_disposition','canonical_benefit_hash',
         'previous_canonical_benefit_hash','staging_id',
         'staging_content_hash'
       )
     )
     OR evidence->>'catalog_identity_conflict_count' IS DISTINCT FROM '0'
     OR evidence->>'conflict_count' IS DISTINCT FROM '0'
     OR evidence->>'suppressed_removal_count' IS DISTINCT FROM '0'
     OR evidence->>'unsafe_mutation_count' IS DISTINCT FROM '0'
     OR evidence->'crawl_complete' IS DISTINCT FROM 'true'::jsonb
     OR evidence->'raw_body_stored' IS DISTINCT FROM 'false'::jsonb
     OR evidence->'side_effect_proof_passed' IS DISTINCT FROM 'true'::jsonb
     OR evidence->'deterministic_replay_passed' IS DISTINCT FROM 'true'::jsonb
     OR evidence->'required_source_selection_overflow'
          IS DISTINCT FROM 'false'::jsonb
     OR observed_at_value IS NULL
     OR evidence->'live_state_before' IS DISTINCT FROM evidence->'live_state_after'
     OR jsonb_typeof(evidence->'live_state_before') <> 'object'
     OR (SELECT count(*) FROM jsonb_object_keys(evidence->'live_state_before')) <> 3
     OR EXISTS (
       SELECT 1
       FROM jsonb_each(evidence->'live_state_before') AS snapshot(table_name, value)
       WHERE snapshot.table_name NOT IN (
         'card_catalog','benefits','card_benefit_mapping'
       ) OR jsonb_typeof(snapshot.value) <> 'object'
         OR (SELECT count(*) FROM jsonb_object_keys(snapshot.value)) <> 2
         OR jsonb_typeof(snapshot.value->'count') <> 'number'
         OR coalesce(snapshot.value->>'count','') !~ '^[0-9]+$'
         OR (snapshot.value->>'count')::numeric > 512
         OR coalesce(snapshot.value->>'row_hash','') !~ '^[0-9a-f]{64}$'
     )
     OR jsonb_typeof(evidence->'source_attempts') <> 'array'
     OR jsonb_array_length(evidence->'source_attempts') NOT BETWEEN 1 AND 9
     OR (SELECT count(*) FROM jsonb_array_elements(evidence->'source_attempts') AS attempt(value)
         WHERE attempt.value->>'role' = 'primary') <> 1
     OR EXISTS (
       SELECT 1 FROM jsonb_array_elements(evidence->'source_attempts') AS attempt(value)
       WHERE jsonb_typeof(attempt.value) <> 'object'
          OR attempt.value->>'role' NOT IN ('primary','required_supporting','supporting')
          OR attempt.value->>'status' NOT IN ('success','not_modified','failed')
          OR EXISTS (
            SELECT 1 FROM jsonb_object_keys(attempt.value) AS key(value)
            WHERE key.value NOT IN (
              'url','role','status','httpStatus','contentHash',
              'finalResourceIdentityHash','errorCode','attemptedAt',
              'parserCacheReusable','logicalSourceKey','attemptHistory',
              'attemptHistoryOverflow'
            )
          )
          OR (attempt.value->>'status' IN ('success','not_modified') AND (
            coalesce(attempt.value->>'contentHash','') !~ '^[0-9a-f]{64}$'
            OR coalesce(attempt.value->>'logicalSourceKey','') !~ '^[0-9a-f]{64}$'
            OR coalesce(attempt.value->>'finalResourceIdentityHash','') !~ '^[0-9a-f]{64}$'
          ))
          OR (attempt.value->>'status' = 'not_modified'
            AND attempt.value->'parserCacheReusable' IS DISTINCT FROM 'true'::jsonb)
          OR (attempt.value ? 'parserCacheReusable' AND
            jsonb_typeof(attempt.value->'parserCacheReusable') <> 'boolean')
          OR public.card_enrichment_pilot_timestamp(
            attempt.value->>'attemptedAt'
          ) IS NULL
          OR public.card_enrichment_pilot_timestamp(
            attempt.value->>'attemptedAt'
          ) > observed_at_value + interval '5 minutes'
          OR (attempt.value ? 'httpStatus' AND (
            jsonb_typeof(attempt.value->'httpStatus') <> 'number'
            OR coalesce(attempt.value->>'httpStatus','') !~ '^[0-9]+$'
            OR (attempt.value->>'httpStatus')::integer NOT BETWEEN 100 AND 599
          ))
          OR (attempt.value ? 'attemptHistory' AND (
            jsonb_typeof(attempt.value->'attemptHistory') <> 'array'
            OR jsonb_array_length(attempt.value->'attemptHistory') > 6
          ))
          OR (attempt.value->>'role' IN ('primary','required_supporting')
            AND attempt.value->>'status' NOT IN ('success','not_modified'))
          OR (attempt.value ? 'attemptHistoryOverflow' AND
            jsonb_typeof(attempt.value->'attemptHistoryOverflow') <> 'boolean')
          OR attempt.value->'attemptHistoryOverflow' = 'true'::jsonb
          OR EXISTS (
            -- Devanagari and Latin action-subject spans must match one exact
            -- authoritative issuer/product phrase; partial words never do.
            SELECT 1
            FROM jsonb_array_elements(CASE
              WHEN jsonb_typeof(attempt.value->'attemptHistory') = 'array'
              THEN attempt.value->'attemptHistory' ELSE '[]'::jsonb END
            ) AS history(value)
            WHERE jsonb_typeof(history.value) <> 'object'
               OR history.value->>'status' NOT IN ('success','not_modified','failed')
               OR public.card_enrichment_pilot_timestamp(
                 history.value->>'attemptedAt'
               ) IS NULL
               OR public.card_enrichment_pilot_timestamp(
                 history.value->>'attemptedAt'
               ) > observed_at_value + interval '5 minutes'
               OR (history.value ? 'httpStatus' AND (
                 jsonb_typeof(history.value->'httpStatus') <> 'number'
                 OR coalesce(history.value->>'httpStatus','') !~ '^[0-9]+$'
                 OR (history.value->>'httpStatus')::integer NOT BETWEEN 100 AND 599
               ))
               OR EXISTS (
                 SELECT 1 FROM jsonb_object_keys(history.value) AS key(value)
                 WHERE key.value NOT IN (
                   'status','httpStatus','errorCode',
                   'finalResourceIdentityHash','attemptedAt'
                 )
               )
          )
     )
     OR (SELECT attempt.value->>'logicalSourceKey'
         FROM jsonb_array_elements(evidence->'source_attempts') AS attempt(value)
         WHERE attempt.value->>'role' = 'primary') IS DISTINCT FROM
           public.card_enrichment_pilot_source_identity_hash(_job.canonical_url)
     OR EXISTS (
       SELECT attempt.value->>'logicalSourceKey'
       FROM jsonb_array_elements(evidence->'source_attempts') AS attempt(value)
       WHERE attempt.value->>'role' = 'required_supporting'
       GROUP BY attempt.value->>'logicalSourceKey'
       HAVING count(*) <> 1
     )
     OR evidence->>'source_manifest_hash' IS DISTINCT FROM
          public.card_enrichment_pilot_source_manifest_hash(evidence->'source_attempts')
     OR public.card_has_unresolved_catalog_identity(_job.card_id, _job.canonical_url)
  THEN RETURN false; END IF;

  replay_input := evidence->'replay_input';
  IF jsonb_typeof(replay_input) <> 'object'
     OR (SELECT count(*) FROM jsonb_object_keys(replay_input)) <> 3
     OR replay_input->'version' IS DISTINCT FROM '3'::jsonb
     OR jsonb_typeof(replay_input->'context') <> 'object'
     OR (SELECT count(*) FROM jsonb_object_keys(replay_input->'context')) <> 3
     OR replay_input->'context'->>'issuer' IS DISTINCT FROM _job.issuer
     OR length(replay_input->'context'->>'issuer') NOT BETWEEN 1 AND 128
     OR replay_input->'context'->>'primary_source_url' !~
       '^https://[^/@?#]+(?:/[^?#]*)?$'
     OR replay_input->'context'->>'primary_source_url' IS DISTINCT FROM
       public.card_enrichment_pilot_queryless_display_url(_job.canonical_url)
     OR jsonb_typeof(replay_input->'context'->'identity_labels') <> 'array'
     OR jsonb_array_length(replay_input->'context'->'identity_labels')
       NOT BETWEEN 1 AND 8
     OR EXISTS (
       SELECT 1
       FROM jsonb_array_elements(replay_input->'context'->'identity_labels')
         AS label(value)
       WHERE jsonb_typeof(label.value) <> 'string'
          OR length(label.value #>> '{}') NOT BETWEEN 1 AND 128
     )
     OR replay_input->'context'->'identity_labels'->>0 IS DISTINCT FROM (
       SELECT regexp_replace(trim(catalog.card_name), '\s+', ' ', 'g')
       FROM public.card_catalog AS catalog
       WHERE catalog.id = _job.card_id
     )
     OR EXISTS (
       SELECT 1
       FROM jsonb_array_elements_text(
         replay_input->'context'->'identity_labels'
       ) AS label(value)
       WHERE NOT EXISTS (
         SELECT 1 FROM (
           SELECT regexp_replace(trim(catalog.card_name), '\s+', ' ', 'g')
             AS allowed_label
           FROM public.card_catalog AS catalog
           WHERE catalog.id = _job.card_id
           UNION
           SELECT regexp_replace(trim(
             catalog.card_name || ' ' || coalesce(catalog.network, '')
           ), '\s+', ' ', 'g')
           FROM public.card_catalog AS catalog
           WHERE catalog.id = _job.card_id
           UNION
           SELECT regexp_replace(trim(alias.alias), '\s+', ' ', 'g')
           FROM public.card_catalog_aliases AS alias
           WHERE alias.card_id = _job.card_id
         ) AS authoritative
         WHERE authoritative.allowed_label = label.value
       )
     )
     OR jsonb_typeof(replay_input->'documents') <> 'array'
     OR jsonb_array_length(replay_input->'documents') NOT BETWEEN 1 AND 9
     OR octet_length(convert_to(
       public.canonical_json_text(replay_input), 'UTF8'
     )) > 1048576
     OR EXISTS (
       SELECT 1
       FROM jsonb_array_elements(replay_input->'documents') AS document(value)
       WHERE jsonb_typeof(document.value) <> 'object'
          OR (SELECT count(*) FROM jsonb_object_keys(document.value)) <> 13
          OR document.value->>'requested_source_url' !~
            '^https://[^/@?#]+(?:/[^?#]*)?$'
          OR document.value->>'final_source_url' !~
            '^https://[^/@?#]+(?:/[^?#]*)?$'
          OR public.card_enrichment_pilot_source_identity_hash(
               document.value->>'requested_resource_url'
             ) IS NULL
          OR public.card_enrichment_pilot_source_identity_hash(
               document.value->>'final_resource_url'
             ) IS NULL
          OR public.card_enrichment_pilot_queryless_display_url(
               document.value->>'requested_resource_url'
             ) IS DISTINCT FROM document.value->>'requested_source_url'
          OR public.card_enrichment_pilot_queryless_display_url(
               document.value->>'final_resource_url'
             ) IS DISTINCT FROM document.value->>'final_source_url'
          OR coalesce(document.value->>'requested_resource_identity_hash','')
            !~ '^[0-9a-f]{64}$'
          OR coalesce(document.value->>'final_resource_identity_hash','')
            !~ '^[0-9a-f]{64}$'
          OR public.card_enrichment_pilot_source_identity_hash(
               document.value->>'requested_resource_url'
             ) IS DISTINCT FROM
               document.value->>'requested_resource_identity_hash'
          OR public.card_enrichment_pilot_source_identity_hash(
               document.value->>'final_resource_url'
             ) IS DISTINCT FROM document.value->>'final_resource_identity_hash'
          OR coalesce(document.value->>'content_hash','')
            !~ '^[0-9a-f]{64}$'
          OR jsonb_typeof(document.value->'public_text') <> 'string'
          OR octet_length(convert_to(document.value->>'public_text','UTF8'))
            NOT BETWEEN 1 AND 65536
          OR jsonb_typeof(document.value->'fact_count') <> 'number'
          OR coalesce(document.value->>'fact_count','') !~ '^[0-9]+$'
          OR (document.value->>'fact_count')::integer NOT BETWEEN 1 AND 256
          OR (document.value->>'fact_count')::integer IS DISTINCT FROM
            cardinality(string_to_array(document.value->>'public_text', E'\n'))
          OR EXISTS (
            SELECT 1
            FROM unnest(string_to_array(
              document.value->>'public_text', E'\n'
            )) AS fact(value)
            WHERE octet_length(convert_to(fact.value, 'UTF8')) > 4096
          )
          OR document.value->'fact_overflow' IS DISTINCT FROM 'false'::jsonb
          OR document.value->'privacy_normalized' IS DISTINCT FROM 'true'::jsonb
          -- Edge emits NFKD-normalized facts. Fullwidth Unicode and combining
          -- forms, digit-script variants, zero-widths, and confusables must
          -- never survive into a forged database replay envelope. This is the
          -- SQL fail-closed mirror for U+200B/U+200C/U+200D/U+2060/U+FEFF and
          -- fullwidth Unicode U+FF10-U+FF19 input after bounded Edge decoding.
          OR document.value->>'public_text' IS DISTINCT FROM
            normalize(document.value->>'public_text', NFKD)
          -- Residual percent or named HTML entity material is never a
          -- privacy-safe normalized replay fact.
          OR document.value->>'public_text' ~*
            '%(25)*[0-9a-f]{2}|&(?:#x?[0-9a-f]+|[a-z][a-z0-9]{1,31});?'
          OR position(chr(8203) IN document.value->>'public_text') > 0
          OR position(chr(8204) IN document.value->>'public_text') > 0
          OR position(chr(8205) IN document.value->>'public_text') > 0
          OR position(chr(8288) IN document.value->>'public_text') > 0
          OR position(chr(65279) IN document.value->>'public_text') > 0
          OR EXISTS (
            -- Fail closed on every residual Unicode decimal-digit range.
            SELECT 1
            FROM regexp_split_to_table(
              document.value->>'public_text', ''
            ) AS residual_unicode_digit(character)
            CROSS JOIN unnest(ARRAY[
              1632,1776,1984,2406,2534,2662,2790,2918,3046,3174,
              3302,3430,3558,3664,3792,3872,4160,4240,6112,6160,
              6470,6608,6784,6800,6992,7088,7232,7248,42528,43216,
              43264,43472,43504,43600,44016,65296,66720,68912,69734,
              69872,69942,70096,70384,70736,70864,71248,71360,71472,
              71904,72016,72784,73040,73120,73552,92768,92864,93008,
              120782,120792,120802,120812,120822,123200,123632,124144,
              125264
            ]) AS digit_zero(codepoint)
            WHERE ascii(residual_unicode_digit.character)
              BETWEEN digit_zero.codepoint AND digit_zero.codepoint + 9
          )
          OR document.value->>'public_text' ~ '[ΑΒΕΖΗΙΚΜΝΟΡΤΥΧαβεικνορτυχАВЕКМНОРСТХУІаеіјорсху]'
          OR document.value->>'public_text' ~*
            '[a-z0-9._%+\-]+@[a-z0-9.\-]+\.[a-z]{2,}'
          OR document.value->>'public_text' ~
            '(^|[^[:alnum:]+])\+?([0-9][() .-]*){10,}([^[:alnum:]]|$)'
          OR document.value->>'public_text' ~
            '\m[A-Z]{5}[0-9]{4}[A-Z]\M'
          OR document.value->>'public_text' ~
            '\m[Nn]ame[[:space:]]*[:=#-][[:space:]]*[A-Z][a-z]{2,}([[:space:]]+[A-Z][a-z]{2,}){0,3}\M'
          OR document.value->>'public_text' ~*
            '(customer|account|card|payment|pan|phone|mobile)[[:space:]]*((name|number|no\.?|id)[[:space:]]*[:=#-]|[:=#])[[:space:]]*[^,;.[:space:]][^,;.]{1,127}'
          OR EXISTS (
            SELECT 1
            FROM regexp_matches(
              lower(document.value->>'public_text'),
              '^([a-zऀ-ॿ][a-zऀ-ॿ'' -]{2,127})[[:space:]]+((gets?|receives?)\M|will[[:space:]]+(call|contact)\M|is[[:space:]]+the[[:space:]]+(customer|cardholder|member)\M)',
              'gn'
            ) AS personal(match)
            WHERE trim(lower(personal.match[1])) NOT IN (
              'applicant','applicants','cardholder','cardholders',
              'customer','customers','member','members','user','users',
              'cashback','card'
            )
              AND NOT EXISTS (
                SELECT 1 FROM (
                  SELECT replay_input->'context'->>'issuer' AS value
                  UNION ALL
                  SELECT label.value
                  FROM jsonb_array_elements_text(
                    replay_input->'context'->'identity_labels'
                  ) AS label(value)
                ) AS exact_identity_phrase
                WHERE trim(lower(exact_identity_phrase.value)) =
                  trim(lower(personal.match[1]))
              )
          )
          OR public.card_enrichment_pilot_has_contextual_person(
            document.value->>'public_text',
            jsonb_build_array(replay_input->'context'->>'issuer') ||
              replay_input->'context'->'identity_labels'
          )
          OR jsonb_typeof(document.value->'hyperlinks') <> 'array'
          OR jsonb_array_length(document.value->'hyperlinks') > 8
          OR document.value->'hyperlink_overflow' IS DISTINCT FROM 'false'::jsonb
          OR EXISTS (
            SELECT 1
            FROM jsonb_array_elements(document.value->'hyperlinks') AS link(value)
            WHERE jsonb_typeof(link.value) <> 'object'
               OR (SELECT count(*) FROM jsonb_object_keys(link.value)) <> 5
               OR link.value->>'href' !~ '^https://[^/@?#]+(?:/[^?#]*)?$'
               OR public.card_enrichment_pilot_source_identity_hash(
                    link.value->>'resource_url'
                  ) IS NULL
               OR public.card_enrichment_pilot_queryless_display_url(
                    link.value->>'resource_url'
                  ) IS DISTINCT FROM link.value->>'href'
               OR length(coalesce(link.value->>'anchor_text','')) > 96
               OR link.value->>'anchor_text' !~
                 '^(|curated exact source|most important terms( and conditions)?|terms?( and conditions)?|conditions?|mitc|fees?|charges?|benefits?|rewards?|supporting (material|document))$'
               OR coalesce(link.value->>'resource_identity_hash','')
                 !~ '^[0-9a-f]{64}$'
               OR public.card_enrichment_pilot_source_identity_hash(
                    link.value->>'resource_url'
                  ) IS DISTINCT FROM link.value->>'resource_identity_hash'
               OR link.value->>'query_policy' IS DISTINCT FROM 'functional_only'
          )
          OR EXISTS (
            SELECT 1 FROM jsonb_object_keys(document.value) AS key(value)
            WHERE key.value NOT IN (
              'requested_source_url','final_source_url',
              'requested_resource_url','final_resource_url',
              'requested_resource_identity_hash','final_resource_identity_hash',
              'content_hash','public_text','fact_count','fact_overflow',
              'privacy_normalized','hyperlinks','hyperlink_overflow'
            )
          )
     )
     OR EXISTS (
       SELECT 1
       FROM jsonb_array_elements(replay_input->'documents') AS document(value)
       WHERE NOT EXISTS (
         SELECT 1
         FROM jsonb_array_elements(evidence->'source_attempts') AS attempt(value)
         WHERE attempt.value->>'url' = document.value->>'final_source_url'
           AND attempt.value->>'logicalSourceKey' =
                 document.value->>'requested_resource_identity_hash'
           AND attempt.value->>'finalResourceIdentityHash' =
                 document.value->>'final_resource_identity_hash'
           AND attempt.value->>'contentHash' = document.value->>'content_hash'
           AND attempt.value->>'status' IN ('success','not_modified')
       )
     )
     OR EXISTS (
       SELECT 1
       FROM jsonb_array_elements(replay_input->'documents') AS document(value)
       CROSS JOIN LATERAL jsonb_array_elements(document.value->'hyperlinks')
         AS link(value)
       WHERE NOT EXISTS (
         SELECT 1
         FROM jsonb_array_elements(evidence->'source_attempts') AS attempt(value)
         WHERE attempt.value->>'url' = link.value->>'href'
           AND attempt.value->>'logicalSourceKey' =
                 link.value->>'resource_identity_hash'
       ) AND NOT EXISTS (
         SELECT 1
         FROM jsonb_array_elements(replay_input->'documents')
           AS linked_document(value)
         WHERE linked_document.value->>'requested_source_url' =
                 link.value->>'href'
           AND linked_document.value->>'requested_resource_url' =
                 link.value->>'resource_url'
           AND linked_document.value->>'requested_resource_identity_hash' =
                 link.value->>'resource_identity_hash'
       )
     )
  THEN RETURN false; END IF;

  -- Recompute the required-source set from retained classifier inputs. This
  -- deliberately does not read the worker's expected set.
  SELECT coalesce(jsonb_agg(to_jsonb(
    required.source_key
  ) ORDER BY required.source_key), '[]'::jsonb)
  INTO replay_required_source_keys
  FROM (
    SELECT DISTINCT public.card_enrichment_pilot_source_identity_hash(
      link.value->>'resource_url'
    ) AS source_key
    FROM jsonb_array_elements(replay_input->'documents') AS document(value)
    CROSS JOIN LATERAL jsonb_array_elements(document.value->'hyperlinks')
      AS link(value)
    WHERE link.value->>'resource_url' ~*
      '(^|[/?=&_.-])(terms?|conditions?|mitc|fees?|charges?)(?:$|[/?=&_.-])'
       OR link.value->>'anchor_text' ~*
      '\m(most[[:space:]]+important[[:space:]]+terms|terms?|conditions?|mitc|fees?|charges?|curated[[:space:]]+exact[[:space:]]+source)\M'
  ) AS required;
  expected_required_source_keys := evidence->'expected_required_source_keys';
  SELECT coalesce(jsonb_agg(required.source_key ORDER BY required.source_key), '[]'::jsonb)
    INTO actual_required_source_keys
  FROM (
    SELECT DISTINCT attempt.value->>'logicalSourceKey' AS source_key
    FROM jsonb_array_elements(evidence->'source_attempts') AS attempt(value)
    WHERE attempt.value->>'role' = 'required_supporting'
  ) AS required;
  IF jsonb_typeof(expected_required_source_keys) <> 'array'
     OR jsonb_array_length(expected_required_source_keys) > 8
     OR EXISTS (
       SELECT 1 FROM jsonb_array_elements(expected_required_source_keys)
         WITH ORDINALITY AS required(value, ordinality)
       WHERE jsonb_typeof(required.value) <> 'string'
          OR trim(BOTH '"' FROM required.value::text) !~ '^[0-9a-f]{64}$'
          OR (required.ordinality > 1 AND trim(BOTH '"' FROM required.value::text) <= (
            SELECT trim(BOTH '"' FROM prior.value::text)
            FROM jsonb_array_elements(expected_required_source_keys)
              WITH ORDINALITY AS prior(value, ordinality)
            WHERE prior.ordinality = required.ordinality - 1
          ))
     )
     OR expected_required_source_keys IS DISTINCT FROM replay_required_source_keys
     OR replay_required_source_keys IS DISTINCT FROM actual_required_source_keys
  THEN RETURN false; END IF;

  verification_envelope := evidence->'verification_envelope';
  repeat_verification_envelope := evidence->'repeat_verification_envelope';
  SELECT jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'url', attempt.value->'url', 'role', attempt.value->'role',
      'status', attempt.value->'status', 'http_status', attempt.value->'httpStatus',
      'content_hash', attempt.value->'contentHash',
      'logical_source_key', attempt.value->'logicalSourceKey',
      'final_resource_identity_hash', attempt.value->'finalResourceIdentityHash',
      'error_code', attempt.value->'errorCode'
    )) ORDER BY attempt.ordinality)
    INTO expected_source_resources
  FROM jsonb_array_elements(evidence->'source_attempts')
    WITH ORDINALITY AS attempt(value, ordinality);
  IF jsonb_typeof(verification_envelope) <> 'object'
     OR jsonb_typeof(repeat_verification_envelope) <> 'object'
     OR verification_envelope IS DISTINCT FROM repeat_verification_envelope
     OR (SELECT count(*) FROM jsonb_object_keys(verification_envelope)) <> 11
     OR EXISTS (
       SELECT 1 FROM jsonb_object_keys(verification_envelope) AS key(value)
       WHERE key.value NOT IN (
         'parser_version','job_id','card_id','run_mode','source_manifest_hash',
         'source_resources','retained_documents','expected_required_source_keys',
         'required_source_selection_overflow','replay_input_hash',
         'canonical_proposals'
       )
     )
     OR octet_length(convert_to(
          public.canonical_json_text(verification_envelope), 'UTF8'
        )) > 262144
     OR jsonb_typeof(verification_envelope->'retained_documents') <> 'array'
     OR jsonb_array_length(verification_envelope->'retained_documents') > 9
     OR verification_envelope->'source_resources' IS DISTINCT FROM expected_source_resources
     OR verification_envelope->'expected_required_source_keys'
          IS DISTINCT FROM expected_required_source_keys
     OR verification_envelope->'required_source_selection_overflow'
          IS DISTINCT FROM 'false'::jsonb
     OR verification_envelope->>'replay_input_hash' IS DISTINCT FROM encode(
       extensions.digest(
         convert_to(public.canonical_json_text(replay_input), 'UTF8'), 'sha256'
       ), 'hex'
     )
     OR jsonb_array_length(verification_envelope->'retained_documents') <>
        (SELECT count(*) FROM jsonb_array_elements(expected_source_resources) AS resource(value)
         WHERE resource.value->>'status' IN ('success', 'not_modified')
           AND resource.value ? 'content_hash')
     OR EXISTS (
       SELECT 1 FROM jsonb_array_elements(verification_envelope->'retained_documents') AS document(value)
       WHERE jsonb_typeof(document.value) <> 'object'
          OR (SELECT count(*) FROM jsonb_object_keys(document.value)) <> 5
          OR coalesce(document.value->>'requested_resource_identity_hash', '') !~ '^[0-9a-f]{64}$'
          OR coalesce(document.value->>'final_resource_identity_hash', '') !~ '^[0-9a-f]{64}$'
          OR coalesce(document.value->>'content_hash', '') !~ '^[0-9a-f]{64}$'
          OR coalesce(document.value->>'document_text_hash', '') !~ '^[0-9a-f]{64}$'
          OR jsonb_typeof(document.value->'document_bytes') <> 'number'
          OR coalesce(document.value->>'document_bytes', '') !~ '^[0-9]+$'
          OR (document.value->>'document_bytes')::numeric > 1048576
          OR NOT EXISTS (
            SELECT 1 FROM jsonb_array_elements(expected_source_resources) AS resource(value)
            WHERE resource.value->>'logical_source_key' = document.value->>'requested_resource_identity_hash'
              AND resource.value->>'final_resource_identity_hash' = document.value->>'final_resource_identity_hash'
              AND resource.value->>'content_hash' = document.value->>'content_hash'
              AND resource.value->>'status' IN ('success', 'not_modified')
          )
     )
     OR EXISTS (
       SELECT 1
       FROM jsonb_array_elements(verification_envelope->'retained_documents')
         AS document(value)
       GROUP BY public.canonical_json_text(document.value)
       HAVING count(*) <> 1
     )
     OR EXISTS (
       SELECT 1 FROM jsonb_array_elements(expected_source_resources) AS resource(value)
       WHERE resource.value->>'status' IN ('success','not_modified')
         AND resource.value ? 'content_hash'
         AND (SELECT count(*)
              FROM jsonb_array_elements(verification_envelope->'retained_documents')
                AS document(value)
              WHERE document.value->>'requested_resource_identity_hash' =
                      resource.value->>'logical_source_key'
                AND document.value->>'final_resource_identity_hash' =
                      resource.value->>'final_resource_identity_hash'
                    AND document.value->>'content_hash' = resource.value->>'content_hash') <> 1
     )
     OR EXISTS (
       SELECT 1 FROM jsonb_array_elements(replay_input->'documents') AS input(value)
       WHERE (SELECT count(*)
         FROM jsonb_array_elements(verification_envelope->'retained_documents')
           AS retained(value)
         WHERE retained.value->>'requested_resource_identity_hash' =
                 input.value->>'requested_resource_identity_hash'
           AND retained.value->>'final_resource_identity_hash' =
                 input.value->>'final_resource_identity_hash'
           AND retained.value->>'content_hash' = input.value->>'content_hash'
           AND retained.value->>'document_text_hash' = encode(
             extensions.digest(
               convert_to(input.value->>'public_text','UTF8'), 'sha256'
             ), 'hex'
           )
           AND (retained.value->>'document_bytes')::integer =
             octet_length(convert_to(input.value->>'public_text','UTF8'))
       ) <> 1
     )
     OR evidence->>'canonical_hash' IS DISTINCT FROM encode(
          extensions.digest(convert_to(public.canonical_json_text(verification_envelope), 'UTF8'), 'sha256'), 'hex'
        )
     OR evidence->>'repeat_canonical_hash' IS DISTINCT FROM encode(
          extensions.digest(convert_to(public.canonical_json_text(repeat_verification_envelope), 'UTF8'), 'sha256'), 'hex'
        )
     OR evidence->>'canonical_hash' IS DISTINCT FROM evidence->>'repeat_canonical_hash'
     OR verification_envelope->>'job_id' IS DISTINCT FROM _job.id::text
     OR verification_envelope->>'card_id' IS DISTINCT FROM _job.card_id::text
     OR verification_envelope->>'parser_version' IS DISTINCT FROM _job.parser_version
     OR verification_envelope->>'run_mode' IS DISTINCT FROM 'pilot'
     OR verification_envelope->>'source_manifest_hash' IS DISTINCT FROM evidence->>'source_manifest_hash'
  THEN RETURN false; END IF;

  proposals := verification_envelope->'canonical_proposals';
  IF jsonb_typeof(proposals) <> 'array' OR EXISTS (
    SELECT 1 FROM jsonb_array_elements(proposals) AS proposal(value)
    WHERE jsonb_typeof(proposal.value) <> 'object'
       OR coalesce(
         proposal.value->>'conditionHash', proposal.value->>'dedupeKey', ''
       ) = ''
  ) THEN RETURN false; END IF;
  SELECT encode(extensions.digest(convert_to(coalesce(string_agg(
    coalesce(proposal.value->>'conditionHash', proposal.value->>'dedupeKey'),
    E'\n' ORDER BY coalesce(
      proposal.value->>'conditionHash', proposal.value->>'dedupeKey'
    )
  ), ''), 'UTF8'), 'sha256'), 'hex')
  INTO recomputed_canonical_benefit_hash
  FROM jsonb_array_elements(proposals) AS proposal(value);
  IF jsonb_typeof(proposals) <> 'array' OR jsonb_array_length(proposals) > 256
     OR proposals IS DISTINCT FROM repeat_verification_envelope->'canonical_proposals'
     OR (evidence->>'proposal_count')::integer IS DISTINCT FROM jsonb_array_length(proposals)
     OR evidence->>'proposal_disposition' NOT IN (
       'no_change','material','removal_review'
     )
     OR evidence->>'canonical_benefit_hash' IS DISTINCT FROM
       recomputed_canonical_benefit_hash
     OR jsonb_typeof(evidence->'previous_canonical_benefit_hash') IS NULL
     OR jsonb_typeof(evidence->'previous_canonical_benefit_hash')
       NOT IN ('null','string')
     OR (jsonb_typeof(evidence->'previous_canonical_benefit_hash') = 'string'
       AND evidence->>'previous_canonical_benefit_hash' !~ '^[0-9a-f]{64}$')
     OR (_job.run_mode = 'pilot' AND
       (_job.result_summary->>'proposals')::integer IS DISTINCT FROM
         jsonb_array_length(proposals))
  THEN RETURN false; END IF;

  IF evidence->>'proposal_disposition' = 'no_change' THEN
    RETURN evidence->'staging_id' = 'null'::jsonb
      AND evidence->'staging_content_hash' = 'null'::jsonb
      AND (_job.run_mode = 'scheduled' OR _job.staging_id IS NULL)
      AND (
        evidence->>'previous_canonical_benefit_hash' =
          recomputed_canonical_benefit_hash
        OR (
          evidence->'previous_canonical_benefit_hash' = 'null'::jsonb
          AND jsonb_array_length(proposals) = 0
          AND (current_live_state->'benefits'->>'count')::integer = 0
          AND (current_live_state->'card_benefit_mapping'->>'count')::integer = 0
        )
      )
      AND (_job.run_mode = 'scheduled' OR
        current_live_state IS NOT DISTINCT FROM evidence->'live_state_after')
      AND (_job.run_mode = 'scheduled'
        OR _job.result_summary->'successful_no_change' = 'true'::jsonb);
  END IF;
  IF _staging.id IS NULL
     OR _staging.id::text IS DISTINCT FROM evidence->>'staging_id'
     OR (_job.run_mode = 'pilot' AND _job.staging_id IS DISTINCT FROM _staging.id)
     OR _staging.card_id IS DISTINCT FROM _job.card_id
     OR _staging.parser_version IS DISTINCT FROM _job.parser_version
     OR _staging.content_hash IS DISTINCT FROM evidence->>'staging_content_hash'
     OR _staging.status IS DISTINCT FROM 'approved'
     OR _staging.extracted_data->'proposals' IS DISTINCT FROM proposals
     OR _staging.extracted_data->'retained_documents' IS DISTINCT FROM
          verification_envelope->'retained_documents'
     OR jsonb_typeof(_staging.extracted_data->'review_pre_live_state') <> 'object'
     OR _staging.extracted_data->'review_pre_live_state' IS DISTINCT FROM
          evidence->'live_state_after'
     OR jsonb_typeof(_staging.extracted_data->'published_live_state') <> 'object'
     OR (_job.run_mode = 'pilot' AND
       _staging.extracted_data->'published_live_state' IS DISTINCT FROM
         current_live_state)
  THEN RETURN false; END IF;

  decisions := _staging.benefit_decisions;
  removals := coalesce(_staging.extracted_data->'diff'->'possibleRemovals', '[]'::jsonb);
  IF jsonb_typeof(decisions) <> 'array' OR jsonb_array_length(decisions) > 64
     OR jsonb_typeof(removals) <> 'array'
     OR jsonb_array_length(decisions) <>
          jsonb_array_length(proposals) + jsonb_array_length(removals)
     OR EXISTS (
       SELECT 1 FROM jsonb_array_elements(decisions) AS decision(value)
       WHERE decision.value->>'action' NOT IN ('approve','edit','reject','retire','keep_existing')
          OR jsonb_typeof(decision.value->'reviewed_at') <> 'string'
          OR public.card_enrichment_pilot_timestamp(
            decision.value->>'reviewed_at'
          ) IS NULL
          OR public.card_enrichment_pilot_timestamp(
            decision.value->>'reviewed_at'
          ) < observed_at_value - interval '5 minutes'
     )
     OR EXISTS (
       SELECT 1 FROM jsonb_array_elements(decisions) AS decision(value)
       WHERE decision.value->>'action' IN ('approve','edit') AND (
         NOT (decision.value ? 'proposal_index')
         OR NOT (decision.value ? 'benefit_id')
         OR (decision.value->>'proposal_index') !~ '^[0-9]+$'
         OR (decision.value->>'proposal_index')::integer >= jsonb_array_length(proposals)
         OR coalesce(decision.value->>'benefit_id','') !~
           '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
         OR decision.value->>'dedupe_key' IS DISTINCT FROM
           proposals->((decision.value->>'proposal_index')::integer)->>'dedupeKey'
         OR decision.value->>'condition_hash' IS DISTINCT FROM
           proposals->((decision.value->>'proposal_index')::integer)->>'conditionHash'
       )
     )
     OR EXISTS (
       SELECT 1 FROM jsonb_array_elements(decisions) AS decision(value)
       WHERE decision.value->>'action' = 'reject' AND (
         (decision.value ? 'proposal_index') = (decision.value ? 'benefit_id')
         OR ((decision.value ? 'proposal_index') AND (
           (decision.value->>'proposal_index') !~ '^[0-9]+$'
           OR (decision.value->>'proposal_index')::integer >= jsonb_array_length(proposals)
           OR decision.value->>'dedupe_key' IS DISTINCT FROM
             proposals->((decision.value->>'proposal_index')::integer)->>'dedupeKey'
           OR decision.value->>'condition_hash' IS DISTINCT FROM
             proposals->((decision.value->>'proposal_index')::integer)->>'conditionHash'
         ))
         OR ((decision.value ? 'benefit_id') AND (
           coalesce(decision.value->>'benefit_id','') !~
             '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
           OR (SELECT count(*) FROM (
             SELECT 'benefit' AS target
             FROM jsonb_array_elements(removals) AS removal(value)
             WHERE coalesce(
               removal.value->'benefit'->>'liveBenefitId',
               removal.value->'benefit'->>'benefitId',
               removal.value->'benefit'->>'dedupeKey'
             ) = decision.value->>'benefit_id'
             UNION ALL
             SELECT 'proposal:' || (proposal.ordinality - 1)::text
             FROM (
               SELECT item.value->'current' AS current,
                      item.value->'proposed' AS proposed
               FROM jsonb_array_elements(coalesce(
                 _staging.extracted_data->'diff'->'modifications', '[]'::jsonb
               )) AS item(value)
               UNION ALL
               SELECT item.value->'current', item.value->'proposed'
               FROM jsonb_array_elements(coalesce(
                 _staging.extracted_data->'diff'->'unchanged', '[]'::jsonb
               )) AS item(value)
             ) AS pair
             JOIN jsonb_array_elements(proposals) WITH ORDINALITY
               AS proposal(value, ordinality)
               ON public.canonical_json_text(proposal.value) =
                  public.canonical_json_text(pair.proposed)
             WHERE coalesce(
               pair.current->>'liveBenefitId', pair.current->>'benefitId',
               pair.current->>'dedupeKey'
             ) = decision.value->>'benefit_id'
           ) AS exact_target) <> 1
         ))
       )
     )
     OR EXISTS (
       SELECT 1 FROM jsonb_array_elements(decisions) AS decision(value)
       WHERE decision.value->>'action' = 'retire' AND (
         decision.value ? 'proposal_index'
         OR NOT (decision.value ? 'benefit_id')
         OR coalesce(decision.value->>'benefit_id','') !~
           '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
         OR NOT EXISTS (
           SELECT 1 FROM jsonb_array_elements(removals) AS removal(value)
           WHERE coalesce(
             removal.value->'benefit'->>'liveBenefitId',
             removal.value->'benefit'->>'benefitId',
             removal.value->'benefit'->>'dedupeKey'
           ) = decision.value->>'benefit_id'
         )
       )
     )
     OR EXISTS (
       SELECT 1 FROM jsonb_array_elements(decisions) AS decision(value)
       WHERE decision.value->>'action' = 'keep_existing' AND (
         decision.value ? 'proposal_index'
         OR NOT (decision.value ? 'benefit_id')
         OR coalesce(decision.value->>'benefit_id','') !~
           '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
         OR (SELECT count(*) FROM (
           SELECT 'benefit' AS target
           FROM jsonb_array_elements(removals) AS removal(value)
           WHERE coalesce(
             removal.value->'benefit'->>'liveBenefitId',
             removal.value->'benefit'->>'benefitId',
             removal.value->'benefit'->>'dedupeKey'
           ) = decision.value->>'benefit_id'
           UNION ALL
           SELECT 'proposal:' || (proposal.ordinality - 1)::text
           FROM (
             SELECT item.value->'current' AS current,
                    item.value->'proposed' AS proposed
             FROM jsonb_array_elements(coalesce(
               _staging.extracted_data->'diff'->'modifications', '[]'::jsonb
             )) AS item(value)
             UNION ALL
             SELECT item.value->'current', item.value->'proposed'
             FROM jsonb_array_elements(coalesce(
               _staging.extracted_data->'diff'->'unchanged', '[]'::jsonb
             )) AS item(value)
           ) AS pair
           JOIN jsonb_array_elements(proposals) WITH ORDINALITY
             AS proposal(value, ordinality)
             ON public.canonical_json_text(proposal.value) =
                public.canonical_json_text(pair.proposed)
           WHERE coalesce(
             pair.current->>'liveBenefitId', pair.current->>'benefitId',
             pair.current->>'dedupeKey'
           ) = decision.value->>'benefit_id'
         ) AS exact_target) <> 1
       )
     )
     OR EXISTS (
       SELECT identity FROM (
         SELECT CASE
           WHEN decision.value ? 'proposal_index'
             THEN 'proposal:' || decision.value->>'proposal_index'
           WHEN decision.value->>'action' IN ('keep_existing','reject') THEN
             coalesce((
               SELECT 'proposal:' || (proposal.ordinality - 1)::text
               FROM (
                 SELECT item.value->'current' AS current,
                        item.value->'proposed' AS proposed
                 FROM jsonb_array_elements(coalesce(
                   _staging.extracted_data->'diff'->'modifications', '[]'::jsonb
                 )) AS item(value)
                 UNION ALL
                 SELECT item.value->'current', item.value->'proposed'
                 FROM jsonb_array_elements(coalesce(
                   _staging.extracted_data->'diff'->'unchanged', '[]'::jsonb
                 )) AS item(value)
               ) AS pair
               JOIN jsonb_array_elements(proposals) WITH ORDINALITY
                 AS proposal(value, ordinality)
                 ON public.canonical_json_text(proposal.value) =
                    public.canonical_json_text(pair.proposed)
               WHERE coalesce(
                 pair.current->>'liveBenefitId', pair.current->>'benefitId',
                 pair.current->>'dedupeKey'
               ) = decision.value->>'benefit_id'
               LIMIT 1
             ), 'benefit:' || decision.value->>'benefit_id')
           ELSE 'benefit:' || decision.value->>'benefit_id'
         END AS identity
         FROM jsonb_array_elements(decisions) AS decision(value)
       ) reviewed GROUP BY identity HAVING count(*) <> 1
     )
  THEN RETURN false; END IF;

  SELECT count(*) FILTER (WHERE value->>'action' IN ('approve','edit')),
         count(*) FILTER (WHERE value->>'action' = 'keep_existing'),
         count(*) FILTER (WHERE value->>'action' = 'retire'),
         count(*) FILTER (WHERE value->>'action' = 'reject')
    INTO approved_count, retained_count, retired_count, rejected_count
  FROM jsonb_array_elements(decisions);
  RETURN rejected_count = 0
    AND (_job.run_mode = 'scheduled' OR (
      approved_count = (_job.result_summary->>'approved_count')::integer
      AND retained_count = (_job.result_summary->>'retained_count')::integer
      AND retired_count = (_job.result_summary->>'retired_count')::integer
      AND rejected_count = (_job.result_summary->>'rejected_count')::integer
    ));
EXCEPTION WHEN OTHERS THEN
  RETURN false;
END;
$$;

CREATE OR REPLACE FUNCTION public.promote_qualified_card_benefit_enrichment_pilot(
  _parser_version text
) RETURNS SETOF public.card_catalog_enrichment_jobs
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  selected_parser text := lower(trim(coalesce(_parser_version, '')));
  pilot_count integer;
  promoted_count integer;
  all_qualified boolean;
  pilot_card_id uuid;
BEGIN
  IF selected_parser <> 'benefits-v6' THEN
    RAISE EXCEPTION 'invalid_pilot_promotion';
  END IF;
  PERFORM pg_advisory_xact_lock(
    hashtextextended('card_benefit_enrichment_pilot:' || selected_parser, 0)
  );
  FOR pilot_card_id IN
    SELECT job.card_id
    FROM public.card_catalog_enrichment_jobs AS job
    WHERE job.parser_version = selected_parser
      AND (job.run_mode = 'pilot'
        OR job.result_summary->'pilot_qualified' = 'true'::jsonb)
    ORDER BY job.card_id
  LOOP
    PERFORM pg_advisory_xact_lock(hashtextextended(
      'card_benefit_enrichment_review:' || pilot_card_id::text,
      0
    ));
  END LOOP;
  PERFORM 1 FROM public.card_catalog_enrichment_jobs AS job
    WHERE job.parser_version = selected_parser
      AND (job.run_mode = 'pilot'
        OR job.result_summary->'pilot_qualified' = 'true'::jsonb)
    ORDER BY job.id FOR UPDATE OF job;
  PERFORM 1 FROM public.card_benefits_staging AS staging
    JOIN public.card_catalog_enrichment_jobs AS job
      ON nullif(job.normalized_fields->'pilot_evidence'->>'staging_id', '')::uuid = staging.id
    WHERE job.parser_version = selected_parser
      AND (job.run_mode = 'pilot'
        OR job.result_summary->'pilot_qualified' = 'true'::jsonb)
    ORDER BY staging.id FOR UPDATE OF staging;
  -- Block a review/source/live mutation from racing the read/decision boundary.
  LOCK TABLE public.card_catalog_review_queue IN SHARE MODE;
  LOCK TABLE public.card_benefit_mapping IN SHARE MODE;
  LOCK TABLE public.benefits IN SHARE MODE;
  PERFORM 1 FROM public.card_catalog_review_queue AS review
    WHERE review.status = 'pending' ORDER BY review.id FOR SHARE;
  PERFORM 1 FROM public.card_catalog AS card
    JOIN public.card_catalog_enrichment_jobs AS job ON job.card_id = card.id
    WHERE job.parser_version = selected_parser ORDER BY card.id FOR SHARE OF card;
  PERFORM 1 FROM public.card_benefit_mapping AS mapping
    JOIN public.card_catalog_enrichment_jobs AS job ON job.card_id = mapping.card_id
    WHERE job.parser_version = selected_parser ORDER BY mapping.mapping_id FOR SHARE OF mapping;
  PERFORM 1 FROM public.benefits AS benefit
    JOIN public.card_benefit_mapping AS mapping ON mapping.benefit_id = benefit.benefit_id
    JOIN public.card_catalog_enrichment_jobs AS job ON job.card_id = mapping.card_id
    WHERE job.parser_version = selected_parser ORDER BY benefit.benefit_id FOR SHARE OF benefit;
  WITH locked_pilot AS MATERIALIZED (
    SELECT job.*
    FROM public.card_catalog_enrichment_jobs AS job
    WHERE job.parser_version = selected_parser
      AND (
        job.run_mode = 'pilot'
        OR (
          job.run_mode = 'scheduled'
          AND job.result_summary->'pilot_qualified' = 'true'::jsonb
        )
      )
    ORDER BY job.id
    FOR UPDATE OF job
  ), locked_staging AS MATERIALIZED (
    SELECT staging.*
    FROM public.card_benefits_staging AS staging
    JOIN locked_pilot AS pilot
      ON nullif(pilot.normalized_fields->'pilot_evidence'->>'staging_id', '')::uuid = staging.id
    ORDER BY staging.id
    FOR UPDATE OF staging
  )
  SELECT count(*) FILTER (WHERE locked_pilot.run_mode = 'pilot'),
    count(*) FILTER (WHERE locked_pilot.run_mode = 'scheduled'),
    count(DISTINCT locked_pilot.card_id),
    count(DISTINCT locked_pilot.normalized_fields->>'pilot_profile'),
    count(DISTINCT lower(trim(locked_pilot.issuer))),
    array_agg(DISTINCT locked_pilot.normalized_fields->>'pilot_profile'
      ORDER BY locked_pilot.normalized_fields->>'pilot_profile'),
    coalesce(bool_and(length(trim(locked_pilot.issuer)) > 0), false),
    coalesce(bool_and(
    public.card_enrichment_pilot_evidence_is_qualified(
      locked_pilot,
      locked_staging
    )
  ), false)
  INTO pilot_count, promoted_count, pilot_card_count, pilot_profile_count,
    pilot_issuer_count, pilot_profiles, pilot_issuer_values_valid, all_qualified
  FROM locked_pilot
  LEFT JOIN locked_staging ON locked_staging.id =
    nullif(locked_pilot.normalized_fields->'pilot_evidence'->>'staging_id', '')::uuid;
  IF pilot_count + promoted_count <> 5 OR pilot_card_count <> 5
     OR pilot_profile_count <> 5 OR pilot_issuer_count < 3
     OR NOT pilot_issuer_values_valid
     OR pilot_profiles IS DISTINCT FROM ARRAY[
       'additional_valid','known_invalid','redirect_or_js','straightforward',
       'terms_linked'
     ]::text[] THEN
    RAISE EXCEPTION 'pilot_not_qualified';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM public.card_catalog_enrichment_jobs AS pilot_job
    JOIN public.card_catalog_enrichment_jobs AS other_job
      ON other_job.card_id = pilot_job.card_id
     AND other_job.parser_version = pilot_job.parser_version
     AND other_job.id <> pilot_job.id
    WHERE pilot_job.parser_version = selected_parser
      AND (
        pilot_job.run_mode = 'pilot'
        OR pilot_job.result_summary->'pilot_qualified' = 'true'::jsonb
      )
  ) THEN
    RAISE EXCEPTION 'pilot_card_identity_conflict';
  END IF;
  IF promoted_count = 5 THEN
    IF EXISTS (
      SELECT 1
      FROM public.card_catalog_enrichment_jobs AS promoted_job
      WHERE promoted_job.parser_version = selected_parser
        AND promoted_job.run_mode = 'scheduled'
        AND promoted_job.result_summary->'pilot_qualified' = 'true'::jsonb
        AND NOT public.card_enrichment_pilot_evidence_is_qualified(
          promoted_job,
          (SELECT staging FROM public.card_benefits_staging AS staging
             WHERE staging.id = nullif(
               promoted_job.normalized_fields->'pilot_evidence'->>'staging_id',
               ''
             )::uuid)
        )
    ) THEN
      RAISE EXCEPTION 'pilot_not_qualified';
    END IF;
    RETURN QUERY
    SELECT job.*
    FROM public.card_catalog_enrichment_jobs AS job
    WHERE job.parser_version = selected_parser
      AND job.run_mode = 'scheduled'
      AND job.result_summary->'pilot_qualified' = 'true'::jsonb
    ORDER BY job.id;
    RETURN;
  END IF;
  IF pilot_count <> 5 OR promoted_count <> 0 OR NOT all_qualified THEN
    RAISE EXCEPTION 'pilot_not_qualified';
  END IF;

  UPDATE public.card_catalog_enrichment_jobs AS job
  SET run_mode = 'scheduled',
      result_summary = coalesce(job.result_summary, '{}'::jsonb) ||
        jsonb_build_object(
          'pilot_qualified', true,
          'pilot_qualified_at', statement_timestamp()
        ),
      updated_at = statement_timestamp()
  WHERE job.parser_version = selected_parser
    AND job.run_mode = 'pilot';

  IF EXISTS (
    SELECT 1
    FROM public.card_catalog_enrichment_jobs AS promoted_job
    WHERE promoted_job.parser_version = selected_parser
      AND promoted_job.run_mode = 'scheduled'
      AND promoted_job.result_summary->'pilot_qualified' = 'true'::jsonb
      AND NOT public.card_enrichment_pilot_evidence_is_qualified(
        promoted_job,
        (SELECT staging FROM public.card_benefits_staging AS staging
         WHERE staging.id = nullif(
           promoted_job.normalized_fields->'pilot_evidence'->>'staging_id', ''
         )::uuid)
      )
  ) THEN
    RAISE EXCEPTION 'pilot_not_qualified';
  END IF;

  RETURN QUERY
  SELECT job.*
  FROM public.card_catalog_enrichment_jobs AS job
  WHERE job.parser_version = selected_parser
    AND job.run_mode = 'scheduled'
    AND job.result_summary->'pilot_qualified' = 'true'::jsonb
  ORDER BY job.id;
END;
$$;

-- Bring pre-migration v6 terminal rows into the same trigger policy without
-- changing their status, summary, staging link, or audit identity. v5 remains
-- untouched as the rollback lane.
UPDATE public.card_catalog_enrichment_jobs AS legacy_terminal
SET status = legacy_terminal.status
WHERE legacy_terminal.parser_version = 'benefits-v6'
  AND legacy_terminal.status IN ('completed', 'staged', 'quarantined', 'review_required', 'failed')
  AND legacy_terminal.next_retry_at IS NULL
  AND legacy_terminal.next_run_at IS NULL
;

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
  RETURN QUERY
  WITH selected AS (
    SELECT job.id, decision.action
    FROM public.card_catalog_enrichment_jobs AS job
    JOIN public.card_catalog AS card ON card.id = job.card_id
    CROSS JOIN LATERAL (
      SELECT public.card_enrichment_requeue_action(
        job.run_mode,
        job.status,
        job.next_run_at,
        _now,
        (
          (
            coalesce(card.is_discontinued, false) = false
            OR EXISTS (
              SELECT 1 FROM public.user_cards AS user_card
              WHERE user_card.catalog_card_id = job.card_id
                AND user_card.is_active = true
            )
          )
          AND NOT public.card_has_unresolved_catalog_identity(
            job.card_id, job.canonical_url
          )
        ),
        public.card_enrichment_job_has_pending_staging(
          job.staging_id, job.card_id, job.parser_version
        )
      ) AS action
    ) AS decision
    WHERE job.parser_version = selected_parser
      AND job.status IN ('completed', 'staged', 'quarantined', 'review_required', 'failed')
      AND job.status <> 'processing'
      AND job.next_retry_at IS NULL
      AND (job.lease_expires_at IS NULL OR job.lease_expires_at <= _now)
      AND (job.run_mode = 'scheduled' OR decision.action = 'clear')
      AND (job.next_run_at IS NULL OR job.next_run_at <= _now OR decision.action = 'clear')
      AND decision.action <> 'none'
    ORDER BY CASE WHEN decision.action = 'queue' THEN 0 ELSE 1 END,
      job.next_run_at, lower(trim(job.issuer)), job.id
    LIMIT _limit
    FOR UPDATE OF job SKIP LOCKED
  ), updated AS (
    UPDATE public.card_catalog_enrichment_jobs AS job
    SET status = CASE WHEN selected.action = 'queue' THEN 'queued' ELSE job.status END,
      attempt_count = CASE WHEN selected.action = 'queue' THEN 0 ELSE job.attempt_count END,
      next_retry_at = CASE WHEN selected.action = 'queue' THEN NULL ELSE job.next_retry_at END,
      next_run_at = NULL,
      lease_expires_at = CASE WHEN selected.action = 'queue' THEN NULL ELSE job.lease_expires_at END,
      lease_token = CASE WHEN selected.action = 'queue' THEN NULL ELSE job.lease_token END,
      failure_category = CASE WHEN selected.action = 'queue' THEN NULL ELSE job.failure_category END,
      updated_at = _now
    FROM selected
    WHERE job.id = selected.id
    RETURNING job.id, selected.action
  )
  SELECT job.*
  FROM public.card_catalog_enrichment_jobs AS job
  JOIN updated ON updated.id = job.id
  WHERE updated.action = 'queue';
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
  SET status = CASE
        WHEN public.card_enrichment_job_has_pending_staging(
          job.staging_id, job.card_id, job.parser_version
        ) THEN 'staged'
        WHEN job.attempt_count >= 3 THEN 'review_required'
        ELSE 'failed' END,
      -- expired_pending_failure_cadence: retaining a reviewable staging link
      -- must still select the seven-day failure recurrence, never success.
      failure_category = 'worker_resource_limit',
      next_retry_at = CASE
        WHEN public.card_enrichment_job_has_pending_staging(
          job.staging_id, job.card_id, job.parser_version
        ) THEN NULL
        WHEN job.attempt_count >= 3 THEN NULL
        WHEN job.attempt_count = 1 THEN now() + interval '15 minutes'
        ELSE now() + interval '60 minutes' END,
      next_run_at = NULL,
      result_summary = coalesce(job.result_summary, '{}'::jsonb) || jsonb_build_object(
        'lease_expired', true,
        'retry_scheduled', CASE
          WHEN public.card_enrichment_job_has_pending_staging(
            job.staging_id, job.card_id, job.parser_version
          ) THEN false
          ELSE job.attempt_count < 3 END
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

CREATE OR REPLACE FUNCTION public.card_enrichment_effective_terminal_status(
  _requested_status text,
  _has_pending_staging boolean
) RETURNS text
LANGUAGE sql
IMMUTABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
  SELECT CASE
    WHEN _requested_status NOT IN (
      'staged', 'completed', 'quarantined', 'failed', 'review_required'
    ) OR _has_pending_staging IS NULL THEN NULL
    WHEN _has_pending_staging THEN 'staged'
    ELSE _requested_status
  END;
$$;

CREATE OR REPLACE FUNCTION public.card_enrichment_final_staging_state(
  _requested_status text,
  _requested_staging_id uuid,
  _prior_staging_id uuid,
  _locked_staging_id uuid,
  _locked_staging_status text,
  _locked_staging_valid boolean
) RETURNS TABLE (
  effective_status text,
  audit_staging_id uuid,
  has_pending_staging boolean
)
LANGUAGE plpgsql
IMMUTABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  candidate_staging_id uuid := coalesce(
    _requested_staging_id, _prior_staging_id
  );
BEGIN
  audit_staging_id := CASE
    WHEN _locked_staging_valid IS TRUE
      AND _locked_staging_id = candidate_staging_id
      AND _locked_staging_status IN ('pending', 'approved', 'rejected')
    THEN candidate_staging_id
    ELSE NULL
  END;
  has_pending_staging := audit_staging_id IS NOT NULL
    AND _locked_staging_status = 'pending';
  effective_status := CASE
    WHEN has_pending_staging THEN 'staged'
    WHEN _requested_status = 'staged' AND audit_staging_id IS NOT NULL
      THEN 'completed'
    WHEN _requested_status = 'staged' THEN 'review_required'
    ELSE _requested_status
  END;
  RETURN NEXT;
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
  staging_row public.card_benefits_staging%ROWTYPE;
  job_card_id uuid;
  candidate_staging_id uuid;
  current_observation jsonb;
  existing_observation_history jsonb;
  observation_history jsonb;
  safe_summary jsonb;
  has_pending_staging boolean;
  effective_status text;
  resolved_staging_id uuid;
  locked_staging_status text;
  locked_staging_valid boolean := false;
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
  -- Resolve only immutable identity before participating in the exact Task 3/4
  -- review serialization protocol. No queue or staging decision is cached.
  SELECT candidate.card_id INTO job_card_id
  FROM public.card_catalog_enrichment_jobs AS candidate
  WHERE candidate.id = _job_id;
  IF job_card_id IS NULL THEN
    RAISE EXCEPTION 'stale_enrichment_lease';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'card_benefit_enrichment_review:' || job_card_id::text,
    0
  ));

  SELECT candidate.* INTO job_row
  FROM public.card_catalog_enrichment_jobs AS candidate
  WHERE candidate.id = _job_id
    AND candidate.card_id = job_card_id
    AND candidate.status = 'processing'
    AND candidate.lease_token = _lease_token
    AND candidate.lease_expires_at > now()
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'stale_enrichment_lease'; END IF;

  candidate_staging_id := coalesce(_staging_id, job_row.staging_id);
  IF candidate_staging_id IS NOT NULL THEN
    SELECT staging.* INTO staging_row
    FROM public.card_benefits_staging AS staging
    WHERE staging.id = candidate_staging_id
      AND staging.card_id = job_row.card_id
      AND staging.parser_version = job_row.parser_version
      AND staging.request_type = 'official_benefit_enrichment'
    FOR UPDATE;
    IF FOUND THEN
      locked_staging_status := staging_row.status;
      locked_staging_valid := public.is_valid_official_source_evidence(
        staging_row.source_evidence
      );
    END IF;
  END IF;

  SELECT state.effective_status, state.audit_staging_id,
    state.has_pending_staging
  INTO effective_status, resolved_staging_id, has_pending_staging
  FROM public.card_enrichment_final_staging_state(
    _status, _staging_id, job_row.staging_id, staging_row.id,
    locked_staging_status, locked_staging_valid
  ) AS state;

  current_observation := public.sanitize_card_enrichment_observation(
    _result_summary->'observation', statement_timestamp()
  );
  existing_observation_history := CASE
    WHEN jsonb_typeof(job_row.result_summary->'observation') = 'object'
      THEN jsonb_build_array(job_row.result_summary->'observation')
    ELSE '[]'::jsonb
  END || CASE
    WHEN jsonb_typeof(job_row.result_summary->'observations') = 'array'
      THEN job_row.result_summary->'observations'
    ELSE '[]'::jsonb
  END;
  observation_history := public.normalize_card_enrichment_observation_history(
    existing_observation_history,
    _result_summary->'observation',
    statement_timestamp()
  );
  safe_summary := public.sanitize_card_enrichment_result_summary(_result_summary) ||
    jsonb_build_object('observations', observation_history);
  IF current_observation IS NOT NULL THEN
    safe_summary := safe_summary || jsonb_build_object('observation', current_observation);
  END IF;
  IF job_row.result_summary->'pilot_qualified' = 'true'::jsonb THEN
    safe_summary := safe_summary || jsonb_build_object('pilot_qualified', true);
  END IF;

  UPDATE public.card_catalog_enrichment_jobs
  SET status = effective_status,
      lease_expires_at = NULL,
      lease_token = NULL,
      staging_id = resolved_staging_id,
      content_hash = coalesce(_content_hash, job_row.content_hash),
      normalized_fields = coalesce(_normalized_fields, '{}'::jsonb),
      result_summary = safe_summary,
      failure_category = CASE
        WHEN _status = 'staged' AND resolved_staging_id IS NULL
          THEN 'invalid_enrichment_staging'
        ELSE _failure_category
      END,
      next_retry_at = CASE
        WHEN has_pending_staging THEN NULL
        ELSE _next_retry_at
      END,
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
REVOKE ALL ON FUNCTION public.canonical_card_enrichment_timestamp(text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.canonical_card_enrichment_timestamp(text)
  TO service_role;
REVOKE ALL ON FUNCTION public.card_enrichment_pilot_timestamp(text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.card_enrichment_pilot_timestamp(text)
  TO service_role;
REVOKE ALL ON FUNCTION public.next_card_enrichment_observation_at(uuid, text, boolean, boolean, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.next_card_enrichment_observation_at(uuid, text, boolean, boolean, text)
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
REVOKE ALL ON FUNCTION public.card_enrichment_job_has_pending_staging(uuid, uuid, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.card_enrichment_job_has_pending_staging(uuid, uuid, text)
  TO service_role;
REVOKE ALL ON FUNCTION public.card_enrichment_requeue_action(
  text, text, timestamptz, timestamptz, boolean, boolean
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.card_enrichment_requeue_action(
  text, text, timestamptz, timestamptz, boolean, boolean
) TO service_role;
REVOKE ALL ON FUNCTION public.card_enrichment_pilot_job_is_qualified(text, text, jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.card_enrichment_pilot_job_is_qualified(text, text, jsonb)
  TO service_role;
REVOKE ALL ON FUNCTION public.card_enrichment_pilot_evidence_is_qualified(
  public.card_catalog_enrichment_jobs, public.card_benefits_staging
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.card_enrichment_pilot_evidence_is_qualified(
  public.card_catalog_enrichment_jobs, public.card_benefits_staging
) TO service_role;
REVOKE ALL ON FUNCTION public.card_enrichment_pilot_source_manifest_hash(jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.card_enrichment_pilot_source_manifest_hash(jsonb)
  TO service_role;
REVOKE ALL ON FUNCTION public.card_enrichment_pilot_source_identity_hash(text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.card_enrichment_pilot_source_identity_hash(text)
  TO service_role;
REVOKE ALL ON FUNCTION public.card_enrichment_pilot_snapshot_rows(jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.card_enrichment_pilot_snapshot_rows(jsonb)
  TO service_role;
REVOKE ALL ON FUNCTION public.card_enrichment_pilot_live_state_snapshot(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.card_enrichment_pilot_live_state_snapshot(uuid)
  TO service_role;
REVOKE ALL ON FUNCTION public.capture_card_enrichment_pilot_publication_snapshot()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.card_enrichment_enqueue_catalog_eligible(
  uuid, text, text, text, text, text, text, boolean, boolean, boolean
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.card_enrichment_enqueue_catalog_eligible(
  uuid, text, text, text, text, text, text, boolean, boolean, boolean
) TO service_role;
REVOKE ALL ON FUNCTION public.card_enrichment_enqueue_count_is_valid(integer, integer)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.card_enrichment_enqueue_count_is_valid(integer, integer)
  TO service_role;
REVOKE ALL ON FUNCTION public.enforce_card_benefit_enrichment_identity()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.enforce_card_benefit_enrichment_identity()
  TO service_role;
REVOKE ALL ON FUNCTION public.enqueue_card_benefit_enrichment_jobs(jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.enqueue_card_benefit_enrichment_jobs(jsonb)
  TO service_role;
REVOKE ALL ON FUNCTION public.card_enrichment_pilot_cohort_action(integer, integer, boolean)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.card_enrichment_pilot_cohort_action(integer, integer, boolean)
  TO service_role;
REVOKE ALL ON FUNCTION public.initialize_card_benefit_enrichment_pilot(jsonb, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.initialize_card_benefit_enrichment_pilot(jsonb, text)
  TO service_role;
REVOKE ALL ON FUNCTION public.promote_qualified_card_benefit_enrichment_pilot(text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.promote_qualified_card_benefit_enrichment_pilot(text)
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
REVOKE ALL ON FUNCTION public.card_enrichment_effective_terminal_status(text, boolean)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.card_enrichment_effective_terminal_status(text, boolean)
  TO service_role;
REVOKE ALL ON FUNCTION public.card_enrichment_final_staging_state(
  text, uuid, uuid, uuid, text, boolean
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.card_enrichment_final_staging_state(
  text, uuid, uuid, uuid, text, boolean
) TO service_role;
REVOKE ALL ON FUNCTION public.finalize_card_catalog_enrichment_job(
  uuid, uuid, text, uuid, text, jsonb, jsonb, text, timestamptz
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.finalize_card_catalog_enrichment_job(
  uuid, uuid, text, uuid, text, jsonb, jsonb, text, timestamptz
) TO service_role;

DO $recurrence_policy_assertions$
DECLARE
  previous_timezone text := current_setting('TimeZone');
BEGIN
  PERFORM set_config('TimeZone', 'America/New_York', true);
  IF public.card_enrichment_jitter_days('00000000-0000-4000-8000-000000000000', 3) <> 3
     OR public.card_enrichment_jitter_days('11111111-1111-4111-8111-111111111111', 3) <> -2
     OR public.card_enrichment_jitter_days('00000000-0000-4000-8000-000000000000', 1) <> -1
     OR public.next_card_enrichment_observation_at(
       '22222222-2222-4222-8222-222222222222',
       '2024-01-31T12:00:00.000Z', false, false, 'success'
     ) <> '2024-03-01T12:00:00Z'::timestamptz
     OR public.next_card_enrichment_observation_at(
       '00000000-0000-4000-8000-000000000000',
       '2025-12-31T00:00:00.000Z', false, false, 'failed'
     ) <> '2026-01-06T00:00:00Z'::timestamptz
     OR public.next_card_enrichment_observation_at(
       '00000000-0000-4000-8000-000000000000',
       '2026-03-07T07:30:00.000Z', false, false, 'success'
     ) <> '2026-04-09T07:30:00+00:00'::timestamptz
     OR public.next_card_enrichment_observation_at(
       '00000000-0000-4000-8000-000000000000',
       '2025-12-31T00:00:00.000Z', true, false, 'success'
     ) IS NOT NULL
     OR public.canonical_card_enrichment_timestamp(
       '2026-02-30T00:00:00.000Z'
     ) IS NOT NULL
     OR public.canonical_card_enrichment_timestamp(
       '2026-02-20T05:30:00.000+05:30'
     ) IS NOT NULL
     OR public.canonical_card_enrichment_timestamp(
       '2026-02-20 00:00:00.000Z'
     ) IS NOT NULL THEN
    RAISE EXCEPTION 'recurrence policy assertion failed';
  END IF;
  PERFORM set_config('TimeZone', previous_timezone, true);
END;
$recurrence_policy_assertions$;

DO $recurrence_transition_assertions$
BEGIN
  -- The same policy feeds the locked RPC; _limit=1 therefore mutates one row.
  IF public.card_enrichment_requeue_action(
       'pilot', 'completed', '2026-08-19T00:00:00Z',
       '2026-08-20T00:00:00Z', true, false
     ) <> 'clear'
     OR public.card_enrichment_requeue_action(
       'scheduled', 'completed', '2026-08-19T00:00:00Z',
       '2026-08-20T00:00:00Z', true, false
     ) <> 'queue'
     OR public.card_enrichment_requeue_action(
       'scheduled', 'completed', NULL,
       '2026-08-20T00:00:00Z', true, false
     ) <> 'queue'
     OR public.card_enrichment_requeue_action(
       'scheduled', 'staged', '2026-08-19T00:00:00Z',
       '2026-08-20T00:00:00Z', true, true
     ) <> 'queue'
     OR public.card_enrichment_requeue_action(
       'scheduled', 'completed', '2026-08-19T00:00:00Z',
       '2026-08-20T00:00:00Z', false, false
     ) <> 'clear'
     OR public.card_enrichment_requeue_action(
       'scheduled', 'completed', '2026-08-21T00:00:00Z',
       '2026-08-20T00:00:00Z', true, false
     ) <> 'none' THEN
    RAISE EXCEPTION 'recurrence transition assertion failed';
  END IF;
END;
$recurrence_transition_assertions$;

DO $enqueue_authority_assertions$
DECLARE
  atomic_batch boolean;
  zero_insert boolean;
  partial_insert boolean;
  catalog_race boolean;
  canonical_url text := 'https://issuer.example/card';
  canonical_hash text;
BEGIN
  canonical_hash := encode(
    extensions.digest(convert_to(canonical_url, 'UTF8'), 'sha256'), 'hex'
  );
  atomic_batch := public.card_enrichment_enqueue_count_is_valid(2, 2)
    AND NOT public.card_enrichment_enqueue_count_is_valid(2, 3);
  zero_insert := public.card_enrichment_enqueue_count_is_valid(2, 0);
  partial_insert := public.card_enrichment_enqueue_count_is_valid(2, 1);
  catalog_race := public.card_enrichment_enqueue_catalog_eligible(
      '00000000-0000-4000-8000-000000000001', 'Issuer Bank',
      canonical_url, canonical_hash, 'Issuer Bank',
      canonical_url || '?campaign=old#top', ' Credit ', false, false, false
    )
    AND NOT public.card_enrichment_enqueue_catalog_eligible(
      '00000000-0000-4000-8000-000000000001', 'Changed Bank',
      canonical_url, canonical_hash, 'Issuer Bank', canonical_url,
      'credit', false, false, false
    )
    AND NOT public.card_enrichment_enqueue_catalog_eligible(
      '00000000-0000-4000-8000-000000000001', 'Issuer Bank',
      canonical_url, canonical_hash, 'Issuer Bank', canonical_url,
      'credit', true, false, false
    )
    AND NOT public.card_enrichment_enqueue_catalog_eligible(
      '00000000-0000-4000-8000-000000000001', 'Issuer Bank',
      canonical_url, canonical_hash, 'Issuer Bank', canonical_url,
      'credit', false, false, true
    );
  IF NOT atomic_batch OR NOT zero_insert OR NOT partial_insert
     OR NOT catalog_race THEN
    RAISE EXCEPTION 'enqueue authority assertion failed';
  END IF;
END;
$enqueue_authority_assertions$;

DO $finalizer_staging_state_assertions$
DECLARE
  pending_new boolean;
  approved_returned boolean;
  rejected_returned boolean;
  approved_prior_304 boolean;
  obsolete_invalid boolean;
  staging_id uuid := '00000000-0000-4000-8000-000000000010';
BEGIN
  SELECT state.effective_status = 'staged'
      AND state.audit_staging_id = staging_id
      AND state.has_pending_staging
  INTO pending_new
  FROM public.card_enrichment_final_staging_state(
    'staged', staging_id, NULL, staging_id, 'pending', true
  ) AS state;
  SELECT state.effective_status = 'completed'
      AND state.audit_staging_id = staging_id
      AND NOT state.has_pending_staging
  INTO approved_returned
  FROM public.card_enrichment_final_staging_state(
    'staged', staging_id, NULL, staging_id, 'approved', true
  ) AS state;
  SELECT state.effective_status = 'completed'
      AND state.audit_staging_id = staging_id
      AND NOT state.has_pending_staging
  INTO rejected_returned
  FROM public.card_enrichment_final_staging_state(
    'staged', staging_id, NULL, staging_id, 'rejected', true
  ) AS state;
  SELECT state.effective_status = 'completed'
      AND state.audit_staging_id = staging_id
      AND NOT state.has_pending_staging
  INTO approved_prior_304
  FROM public.card_enrichment_final_staging_state(
    'completed', NULL, staging_id, staging_id, 'approved', true
  ) AS state;
  SELECT state.effective_status = 'review_required'
      AND state.audit_staging_id IS NULL
      AND NOT state.has_pending_staging
  INTO obsolete_invalid
  FROM public.card_enrichment_final_staging_state(
    'staged', staging_id, NULL, NULL, NULL, false
  ) AS state;
  IF NOT pending_new OR NOT approved_returned OR NOT rejected_returned
     OR NOT approved_prior_304 OR NOT obsolete_invalid THEN
    RAISE EXCEPTION 'finalizer staging state assertion failed';
  END IF;
END;
$finalizer_staging_state_assertions$;

DO $pilot_qualification_assertions$
DECLARE
  safe_base jsonb := jsonb_build_object(
    'unsafe_mutation_count', 0,
    'idempotency_passed', true,
    'evidence_passed', true,
    'raw_body_stored', false
  );
  successful_no_change jsonb;
  approved_review jsonb;
  fully_rejected jsonb;
  partially_rejected jsonb;
  missing_unsafe jsonb;
  null_unsafe jsonb;
  string_unsafe jsonb;
  negative_unsafe jsonb;
  noninteger_unsafe jsonb;
  missing_raw jsonb;
  null_raw jsonb;
  string_raw jsonb;
  true_raw jsonb;
  missing_review_field jsonb;
  null_review_field jsonb;
  status_casing jsonb;
  one_point_zero_count jsonb;
  ten_digit_count jsonb;
  overflow_count jsonb;
  negative_review_count jsonb;
  fractional_review_count jsonb;
  string_review_count jsonb;
  max_review_count jsonb;
BEGIN
  successful_no_change := safe_base || jsonb_build_object(
    'successful_no_change', true
  );
  approved_review := safe_base || jsonb_build_object(
    'successful_no_change', false,
    'review_status', 'approved',
    'approved_count', 1,
    'retained_count', 0,
    'retired_count', 0,
    'rejected_count', 0
  );
  fully_rejected := safe_base || jsonb_build_object(
    'review_status', 'rejected',
    'approved_count', 0,
    'retained_count', 0,
    'retired_count', 0,
    'rejected_count', 2
  );
  partially_rejected := approved_review || jsonb_build_object(
    'rejected_count', 1
  );
  missing_unsafe := safe_base - 'unsafe_mutation_count';
  null_unsafe := safe_base || jsonb_build_object('unsafe_mutation_count', NULL);
  string_unsafe := safe_base || jsonb_build_object('unsafe_mutation_count', '0');
  negative_unsafe := safe_base || jsonb_build_object('unsafe_mutation_count', -1);
  noninteger_unsafe := safe_base || jsonb_build_object('unsafe_mutation_count', 0.5);
  missing_raw := safe_base - 'raw_body_stored';
  null_raw := safe_base || jsonb_build_object('raw_body_stored', NULL);
  string_raw := safe_base || jsonb_build_object('raw_body_stored', 'false');
  true_raw := safe_base || jsonb_build_object('raw_body_stored', true);
  missing_review_field := approved_review - 'retained_count';
  null_review_field := approved_review || jsonb_build_object(
    'review_status', NULL
  );
  status_casing := approved_review || jsonb_build_object(
    'review_status', 'Approved'
  );
  one_point_zero_count := approved_review || jsonb_build_object(
    'approved_count', 1.0::numeric
  );
  ten_digit_count := approved_review || jsonb_build_object(
    'approved_count', 1000000000
  );
  overflow_count := approved_review || jsonb_build_object(
    'approved_count', 9223372036854775808::numeric
  );
  negative_review_count := approved_review || jsonb_build_object(
    'approved_count', -1
  );
  fractional_review_count := approved_review || jsonb_build_object(
    'approved_count', 0.5
  );
  string_review_count := approved_review || jsonb_build_object(
    'approved_count', '1'
  );
  max_review_count := approved_review || jsonb_build_object(
    'approved_count', 999999999,
    'retained_count', 999999999,
    'retired_count', 999999999
  );
  IF NOT public.card_enrichment_pilot_job_is_qualified(
       'staged', NULL, safe_base
     )
     OR NOT public.card_enrichment_pilot_job_is_qualified(
       'completed', NULL, successful_no_change
     )
     OR NOT public.card_enrichment_pilot_job_is_qualified(
       'completed', NULL, approved_review
     )
     OR public.card_enrichment_pilot_job_is_qualified(
       'completed', NULL, fully_rejected
     )
     OR public.card_enrichment_pilot_job_is_qualified(
       'completed', NULL, partially_rejected
     )
     OR public.card_enrichment_pilot_job_is_qualified(
       'completed', NULL, safe_base
     )
     OR public.card_enrichment_pilot_job_is_qualified(
       'completed', NULL,
       approved_review || jsonb_build_object('approved_count', 'one')
     )
     OR NOT public.card_enrichment_pilot_job_is_qualified(
       'quarantined', 'identity_mismatch', safe_base
     )
     OR public.card_enrichment_pilot_job_is_qualified(
       'quarantined', '', safe_base
     )
     OR public.card_enrichment_pilot_job_is_qualified(
       'staged', NULL, missing_unsafe
     )
     OR public.card_enrichment_pilot_job_is_qualified(
       'staged', NULL, null_unsafe
     )
     OR public.card_enrichment_pilot_job_is_qualified(
       'staged', NULL, string_unsafe
     )
     OR public.card_enrichment_pilot_job_is_qualified(
       'staged', NULL, negative_unsafe
     )
     OR public.card_enrichment_pilot_job_is_qualified(
       'staged', NULL, noninteger_unsafe
     )
     OR public.card_enrichment_pilot_job_is_qualified(
       'staged', NULL, missing_raw
     )
     OR public.card_enrichment_pilot_job_is_qualified(
       'staged', NULL, null_raw
     )
     OR public.card_enrichment_pilot_job_is_qualified(
       'staged', NULL, string_raw
     )
     OR public.card_enrichment_pilot_job_is_qualified(
       'staged', NULL, true_raw
     )
     OR public.card_enrichment_pilot_job_is_qualified(
       'completed', NULL, missing_review_field
     )
     OR public.card_enrichment_pilot_job_is_qualified(
       'completed', NULL, null_review_field
     )
     OR public.card_enrichment_pilot_job_is_qualified(
       'completed', NULL, status_casing
     )
     OR NOT public.card_enrichment_pilot_job_is_qualified(
       'completed', NULL, one_point_zero_count
     )
     OR public.card_enrichment_pilot_job_is_qualified(
       'completed', NULL, ten_digit_count
     )
     OR public.card_enrichment_pilot_job_is_qualified(
       'completed', NULL, overflow_count
     )
     OR public.card_enrichment_pilot_job_is_qualified(
       'completed', NULL, negative_review_count
     )
     OR public.card_enrichment_pilot_job_is_qualified(
       'completed', NULL, fractional_review_count
     )
     OR public.card_enrichment_pilot_job_is_qualified(
       'completed', NULL, string_review_count
     )
     OR NOT public.card_enrichment_pilot_job_is_qualified(
       'completed', NULL, max_review_count
     )
     OR public.card_enrichment_effective_terminal_status(
       'failed', true
     ) <> 'staged'
     OR public.card_enrichment_effective_terminal_status(
       'completed', true
     ) <> 'staged'
     OR public.card_enrichment_effective_terminal_status(
       'completed', false
     ) <> 'completed' THEN
    RAISE EXCEPTION 'pilot qualification assertion failed';
  END IF;
END;
$pilot_qualification_assertions$;

DO $pilot_atomic_evidence_assertions$
DECLARE
  validator_definition text;
  first_attempts jsonb := '[
    {"url":"https://issuer.example/card","role":"primary","status":"success",
     "contentHash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
     "logicalSourceKey":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
     "finalResourceIdentityHash":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
     "attemptedAt":"2026-08-20T00:00:00.000Z"},
    {"url":"https://issuer.example/terms","role":"required_supporting","status":"failed",
     "errorCode":"http_404","attemptedAt":"2026-08-20T00:00:01.000Z"}
  ]'::jsonb;
  reordered_attempts jsonb := '[
    {"url":"https://issuer.example/terms","role":"required_supporting","status":"failed",
     "errorCode":"http_404","attemptedAt":"2026-08-21T00:00:01.000Z"},
    {"url":"https://issuer.example/card","role":"primary","status":"success",
     "contentHash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
     "logicalSourceKey":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
     "finalResourceIdentityHash":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
     "attemptedAt":"2026-08-21T00:00:00.000Z"}
  ]'::jsonb;
BEGIN
  SELECT pg_get_functiondef(
    'public.card_enrichment_pilot_evidence_is_qualified(public.card_catalog_enrichment_jobs,public.card_benefits_staging)'::regprocedure
  ) INTO validator_definition;
  IF validator_definition !~* 'replay_input->''version'' IS DISTINCT FROM ''3''::jsonb'
     OR validator_definition !~* 'replay_input->''context'''
     OR validator_definition !~* 'resource_identity_hash'
     OR validator_definition !~* 'card_catalog_aliases'
     OR validator_definition !~* 'requested_resource_identity_hash'
     OR validator_definition !~* 'logicalSourceKey'
     OR validator_definition !~* 'link.value->>''href'''
     OR validator_definition !~* 'attempt.value->>''url'''
     OR validator_definition ~* 'replay_input->''required_resources''' THEN
    RAISE EXCEPTION 'pilot replay classifier contract drift';
  END IF;
  IF public.card_enrichment_pilot_source_identity_hash(
       'HTTPS://Issuer.Example:443/card/'
     ) IS DISTINCT FROM public.card_enrichment_pilot_source_identity_hash(
       'https://issuer.example/card'
     ) OR public.card_enrichment_pilot_source_identity_hash(
       'https://issuer.example?locale=en'
     ) IS DISTINCT FROM public.card_enrichment_pilot_source_identity_hash(
       'https://issuer.example/?locale=en'
     ) THEN
    RAISE EXCEPTION 'pilot_source_identity_canonicalization_drift';
  END IF;
  IF public.card_enrichment_pilot_source_manifest_hash(first_attempts)
       IS DISTINCT FROM
     public.card_enrichment_pilot_source_manifest_hash(reordered_attempts) THEN
    RAISE EXCEPTION 'pilot_source_manifest_timestamp_or_order_drift';
  END IF;
  IF public.card_enrichment_pilot_snapshot_rows('[]'::jsonb)->>'count' <> '0'
     OR coalesce(public.card_enrichment_pilot_snapshot_rows('[]'::jsonb)->>'row_hash', '')
       !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'pilot_live_snapshot_contract_drift';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname = 'capture_card_enrichment_pilot_publication_snapshot'
      AND tgrelid = 'public.card_benefits_staging'::regclass
      AND NOT tgisinternal
  ) THEN
    RAISE EXCEPTION 'pilot_publication_snapshot_trigger_missing';
  END IF;
END;
$pilot_atomic_evidence_assertions$;

DO $pilot_privacy_assertions$
DECLARE
  known_phrases jsonb := jsonb_build_array(
    'American Express', 'American Express Platinum Card',
    'Issuer Example', 'Issuer Example Card'
  );
  known_fact text := 'American Express Platinum Card gets 10% cashback';
  second_known_fact text := 'Issuer Example Card gets 10% cashback';
  partial_context text := lower('State Bank of India');
  partial_fact text := lower('India gets 10% cashback');
  alice_fact text := lower('ALICE gets 10% cashback');
  rahul_fact text := lower('Rahul Sarma gets 10% cashback');
BEGIN
  IF position(lower('American Express Platinum Card') || ' gets'
       IN lower(known_fact)) = 0
     OR position(lower('Issuer Example Card') || ' gets'
       IN lower(second_known_fact)) = 0
     OR position(partial_context || ' gets' IN partial_fact) > 0
     OR position(lower('American Express Platinum Card') || ' gets'
       IN alice_fact) > 0
     OR position(lower('American Express Platinum Card') || ' gets'
       IN rahul_fact) > 0
     OR public.card_enrichment_pilot_has_contextual_person(
       'Cashback for American Express Platinum Card is 10%', known_phrases
     )
     OR public.card_enrichment_pilot_has_contextual_person(
       'Reward points to Issuer Example Card', known_phrases
     )
     OR NOT public.card_enrichment_pilot_has_contextual_person(
       'Cashback for alice smith is 10%', known_phrases
     )
     OR NOT public.card_enrichment_pilot_has_contextual_person(
       'Reward points to rAhUl shArMa', known_phrases
     )
     OR NOT public.card_enrichment_pilot_has_contextual_person(
       '10% cashback for ALICE SMITH', known_phrases
     )
     OR NOT public.card_enrichment_pilot_has_contextual_person(
       'Cashback for অর্ণব সেন is 10%', known_phrases
     )
     OR public.card_enrichment_pilot_has_contextual_person(
       'Cashback for airport access is 10%', known_phrases
     )
     OR public.card_enrichment_pilot_has_contextual_person(
       'Offer valid for 12 months.', known_phrases
     )
     OR public.card_enrichment_pilot_has_contextual_person(
       'Earn 5 points for ₹150 spent.', known_phrases
     ) THEN
    RAISE EXCEPTION 'pilot privacy assertion failed';
  END IF;
END;
$pilot_privacy_assertions$;

DO $pilot_cohort_assertions$
BEGIN
  -- return_promoted is the only post-handoff state; partial, five_plus_five,
  -- and duplicate cohorts all fail closed before an insert can run.
  IF public.card_enrichment_pilot_cohort_action(0, 5, false)
       <> 'return_promoted'
     OR public.card_enrichment_pilot_cohort_action(5, 0, false)
       <> 'return_pilot'
     OR public.card_enrichment_pilot_cohort_action(0, 0, false)
       <> 'initialize'
     OR public.card_enrichment_pilot_cohort_action(2, 0, false)
       <> 'reject' -- partial
     OR public.card_enrichment_pilot_cohort_action(5, 5, false)
       <> 'reject' -- five_plus_five
     OR public.card_enrichment_pilot_cohort_action(5, 0, true)
       <> 'reject' -- duplicate
     THEN
    RAISE EXCEPTION 'pilot cohort assertion failed';
  END IF;
END;
$pilot_cohort_assertions$;

DO $recurrence_history_assertions$
DECLARE
  history jsonb;
  same_time_history jsonb;
  legacy_history jsonb;
BEGIN
  SELECT public.normalize_card_enrichment_observation_history(
    coalesce(jsonb_agg(jsonb_build_object(
      'observed_at', to_char(
        day_value AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
      ),
      'crawl_complete', true,
      'crawl_reason', 'complete',
      'source_manifest_hash', repeat('a', 64),
      'canonical_benefit_hash', repeat('b', 64),
      'body', 'must-not-survive'
    ) ORDER BY day_value), '[]'::jsonb) || jsonb_build_array(
      jsonb_build_object('observed_at', '2999-01-01T00:00:00.000Z'),
      jsonb_build_object('observed_at', 'malformed')
    ),
    jsonb_build_object(
      'observed_at', '2026-08-26T00:00:00.000Z',
      'crawl_complete', true,
      'crawl_reason', 'duplicate',
      'source_manifest_hash', repeat('a', 64),
      'canonical_benefit_hash', repeat('b', 64)
    ),
    '2026-09-01T00:00:00Z'::timestamptz
  ) INTO history
  FROM generate_series(
    '2026-08-01T00:00:00Z'::timestamptz,
    '2026-08-26T00:00:00Z'::timestamptz,
    interval '1 day'
  ) AS days(day_value);
  same_time_history := public.normalize_card_enrichment_observation_history(
    jsonb_build_array(
      jsonb_build_object(
        'observed_at', '2026-08-20T00:00:00.000Z',
        'crawl_complete', true,
        'crawl_reason', 'first',
        'source_manifest_hash', repeat('a', 64),
        'canonical_benefit_hash', repeat('b', 64)
      ),
      jsonb_build_object(
        'observed_at', '2026-08-20T00:00:00.000Z',
        'crawl_complete', true,
        'crawl_reason', 'distinct',
        'source_manifest_hash', repeat('c', 64),
        'canonical_benefit_hash', repeat('b', 64)
      )
    ),
    jsonb_build_object(
      'observed_at', '2026-08-20T00:00:00.000Z',
      'crawl_complete', true,
      'crawl_reason', 'duplicate',
      'source_manifest_hash', repeat('a', 64),
      'canonical_benefit_hash', repeat('b', 64)
    ),
    '2026-09-01T00:00:00Z'::timestamptz
  );
  legacy_history := public.normalize_card_enrichment_observation_history(
    jsonb_build_array(
      jsonb_build_object(
        'observed_at', '2026-08-18T00:00:00.000Z',
        'crawl_complete', true,
        'crawl_reason', 'legacy-root',
        'source_manifest_hash', repeat('d', 64),
        'canonical_benefit_hash', repeat('e', 64)
      ),
      jsonb_build_object(
        'observed_at', '2026-08-17T00:00:00.000Z',
        'crawl_complete', true,
        'crawl_reason', 'legacy-history',
        'source_manifest_hash', repeat('f', 64),
        'canonical_benefit_hash', repeat('0', 64)
      )
    ),
    NULL,
    '2026-09-01T00:00:00Z'::timestamptz
  );
  IF jsonb_array_length(history) <> 24
     OR history->0->>'observed_at' <> '2026-08-26T00:00:00.000Z'
     OR history->23->>'observed_at' <> '2026-08-03T00:00:00.000Z'
     OR history::text LIKE '%must-not-survive%'
     OR history::text LIKE '%2999-01-01%'
     OR jsonb_array_length(same_time_history) <> 2
     OR legacy_history::text NOT LIKE '%legacy-root%'
     OR legacy_history::text NOT LIKE '%legacy-history%' THEN
    RAISE EXCEPTION 'recurrence history assertion failed';
  END IF;
END;
$recurrence_history_assertions$;

COMMIT;
