BEGIN;

CREATE OR REPLACE FUNCTION public.stage_card_benefit_enrichment(
  _job_id uuid,
  _lease_token uuid,
  _source_url text,
  _source_url_hash text,
  _parser_version text,
  _content_hash text,
  _extracted_data jsonb,
  _calculated_confidence numeric,
  _validation_reasons jsonb,
  _validation_warnings jsonb,
  _source_evidence jsonb,
  _validated_at timestamptz
) RETURNS TABLE (staging_id uuid, reused boolean)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  job public.card_catalog_enrichment_jobs%ROWTYPE;
  resolved_staging_id uuid;
  reused_staging boolean := false;
  newest_pending_id uuid;
  newest_pending_validated_at timestamptz;
BEGIN
  IF _job_id IS NULL OR _lease_token IS NULL OR _source_url !~ '^https://'
     OR _source_url_hash !~ '^[0-9a-f]{64}$'
     OR encode(extensions.digest(convert_to(trim(_source_url), 'UTF8'), 'sha256'), 'hex')
        <> _source_url_hash
     OR _content_hash !~ '^[0-9a-f]{64}$'
     OR _parser_version IS NULL
     OR jsonb_typeof(_extracted_data) <> 'object'
     OR _extracted_data->>'request_type' <> 'official_benefit_enrichment'
     OR _extracted_data->>'parser_version' <> _parser_version
     OR _extracted_data->>'content_hash' <> _content_hash
     OR _validated_at IS NULL
     -- Keep the database guard aligned with MAX_EVIDENCE_CLOCK_SKEW_MS.
     OR _validated_at > statement_timestamp() + interval '5 minutes'
     OR NOT public.is_valid_official_source_evidence(_source_evidence) THEN
    RAISE EXCEPTION 'invalid_benefit_staging';
  END IF;

  SELECT candidate.* INTO job
  FROM public.card_catalog_enrichment_jobs AS candidate
  WHERE candidate.id = _job_id
    AND candidate.status = 'processing'
    AND candidate.lease_token = _lease_token
    AND candidate.lease_expires_at > now()
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'stale_enrichment_lease';
  END IF;
  IF job.parser_version <> _parser_version THEN
    RAISE EXCEPTION 'parser_version_mismatch';
  END IF;

  IF _parser_version = 'benefits-v6' THEN
    -- Serialize observations for one card even when separate queue jobs race.
    PERFORM pg_advisory_xact_lock(hashtextextended(
      'stage_card_benefit_enrichment:' || job.card_id::text,
      0
    ));

    -- Acquire row locks in UUID order so concurrent reviewers/stagers cannot
    -- invert their lock order.
    PERFORM locked.id
    FROM (
      SELECT staging.id
      FROM public.card_benefits_staging AS staging
      WHERE staging.card_id = job.card_id
        AND staging.parser_version = _parser_version
        AND staging.request_type = 'official_benefit_enrichment'
        AND staging.status = 'pending'
      ORDER BY staging.id
      FOR UPDATE
    ) AS locked;

    -- A corrupt future row must not indefinitely win newest-observation order.
    UPDATE public.card_benefits_staging AS staging
    SET benefit_decisions = (
          CASE
            WHEN jsonb_typeof(staging.benefit_decisions) = 'array'
              THEN staging.benefit_decisions
            WHEN staging.benefit_decisions IS NULL
              OR staging.benefit_decisions = 'null'::jsonb
              THEN '[]'::jsonb
            ELSE jsonb_build_array(jsonb_build_object(
              'action', 'preserve_legacy',
              'reason', 'legacy_malformed_benefit_decisions',
              'legacy_value', staging.benefit_decisions
            ))
          END
        ) || jsonb_build_array(jsonb_build_object(
          'action', 'reject',
          'reason', 'invalid_future_observation_timestamp',
          'rejected_at', timezone('UTC', statement_timestamp())
        )),
        status = 'rejected',
        updated_at = statement_timestamp()
    WHERE staging.card_id = job.card_id
      AND staging.parser_version = _parser_version
      AND staging.request_type = 'official_benefit_enrichment'
      AND staging.status = 'pending'
      AND staging.validated_at > statement_timestamp() + interval '5 minutes';

    SELECT staging.id, staging.validated_at
    INTO newest_pending_id, newest_pending_validated_at
    FROM public.card_benefits_staging AS staging
    WHERE staging.card_id = job.card_id
      AND staging.parser_version = _parser_version
      AND staging.request_type = 'official_benefit_enrichment'
      AND staging.status = 'pending'
    ORDER BY staging.validated_at DESC NULLS FIRST, staging.id DESC
    LIMIT 1;

    -- Unknown legacy time or an equal/newer pending observation wins. The
    -- incoming job still records its crawl summary through finalization but
    -- cannot create a competing pending review row.
    IF newest_pending_id IS NOT NULL AND (
      newest_pending_validated_at IS NULL
      OR _validated_at <= newest_pending_validated_at
    ) THEN
      UPDATE public.card_catalog_enrichment_jobs
      SET staging_id = newest_pending_id,
          updated_at = now()
      WHERE id = _job_id;
      RETURN QUERY SELECT newest_pending_id, true;
      RETURN;
    END IF;
  END IF;

  SELECT staging.id INTO resolved_staging_id
  FROM public.card_benefits_staging AS staging
  WHERE staging.card_id = job.card_id
    AND staging.source_url_hash = _source_url_hash
    AND staging.parser_version = _parser_version
    AND staging.content_hash = _content_hash
    AND staging.request_type = 'official_benefit_enrichment'
    AND staging.status IN ('pending', 'approved')
    AND public.is_valid_official_source_evidence(staging.source_evidence)
  ORDER BY CASE WHEN staging.status = 'pending' THEN 0 ELSE 1 END,
           staging.validated_at DESC NULLS LAST,
           staging.id DESC
  LIMIT 1
  FOR UPDATE;
  reused_staging := FOUND;
  IF NOT reused_staging THEN
    resolved_staging_id := gen_random_uuid();
  END IF;

  IF _parser_version = 'benefits-v6' THEN
    UPDATE public.card_benefits_staging AS staging
    SET benefit_decisions = (
          CASE
            WHEN jsonb_typeof(staging.benefit_decisions) = 'array'
              THEN staging.benefit_decisions
            WHEN staging.benefit_decisions IS NULL
              OR staging.benefit_decisions = 'null'::jsonb
              THEN '[]'::jsonb
            ELSE jsonb_build_array(jsonb_build_object(
              'action', 'preserve_legacy',
              'reason', 'legacy_malformed_benefit_decisions',
              'legacy_value', staging.benefit_decisions
            ))
          END
        ) || jsonb_build_array(jsonb_build_object(
          'action', 'reject',
          'reason', 'superseded_by_newer_crawl',
          'superseded_at', timezone('UTC', statement_timestamp()),
          'superseded_by_job_id', _job_id,
          'superseded_by_staging_id', resolved_staging_id
        )),
        status = 'rejected',
        updated_at = now()
    WHERE staging.card_id = job.card_id
      AND staging.parser_version = _parser_version
      AND staging.request_type = 'official_benefit_enrichment'
      AND staging.status = 'pending'
      AND staging.validated_at IS NOT NULL
      AND staging.validated_at < _validated_at
      AND staging.id <> resolved_staging_id;
  END IF;

  IF reused_staging THEN
    UPDATE public.card_catalog_enrichment_jobs
    SET staging_id = resolved_staging_id,
        updated_at = now()
    WHERE id = _job_id;
    RETURN QUERY SELECT resolved_staging_id, true;
    RETURN;
  END IF;

  INSERT INTO public.card_benefits_staging (
    id, card_id, source_url, request_type, parser_version, source_url_hash,
    content_hash, extracted_data, status, validation_version,
    calculated_confidence, validation_reasons, validation_warnings,
    source_evidence, validated_at
  ) VALUES (
    resolved_staging_id, job.card_id, trim(_source_url),
    'official_benefit_enrichment', _parser_version, _source_url_hash,
    _content_hash, _extracted_data, 'pending', _parser_version,
    _calculated_confidence, coalesce(_validation_reasons, '[]'::jsonb),
    coalesce(_validation_warnings, '[]'::jsonb), _source_evidence,
    _validated_at
  ) ON CONFLICT (card_id, source_url_hash, parser_version, content_hash)
      WHERE request_type = 'official_benefit_enrichment'
      DO NOTHING;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'unsafe_staging_identity';
  END IF;

  UPDATE public.card_catalog_enrichment_jobs
  SET staging_id = resolved_staging_id,
      updated_at = now()
  WHERE id = _job_id;

  RETURN QUERY SELECT resolved_staging_id, false;
END;
$$;

REVOKE ALL ON FUNCTION public.stage_card_benefit_enrichment(
  uuid, uuid, text, text, text, text, jsonb, numeric, jsonb, jsonb, jsonb, timestamptz
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.stage_card_benefit_enrichment(
  uuid, uuid, text, text, text, text, jsonb, numeric, jsonb, jsonb, jsonb, timestamptz
) TO service_role;

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

  IF _status = 'staged' AND NOT EXISTS (
    SELECT 1
    FROM public.card_catalog_enrichment_jobs AS job
    JOIN public.card_benefits_staging AS staging
      ON staging.id = _staging_id
     AND staging.card_id = job.card_id
     AND staging.request_type = 'official_benefit_enrichment'
     AND staging.status IN ('pending', 'approved')
     AND public.is_valid_official_source_evidence(staging.source_evidence)
    WHERE job.id = _job_id
      AND job.status = 'processing'
      AND job.lease_token = _lease_token
      AND job.lease_expires_at > now()
  ) THEN
    RAISE EXCEPTION 'invalid_enrichment_staging_ownership';
  END IF;

  UPDATE public.card_catalog_enrichment_jobs
  SET status = _status,
      lease_expires_at = NULL,
      lease_token = NULL,
      staging_id = _staging_id,
      content_hash = _content_hash,
      normalized_fields = coalesce(_normalized_fields, '{}'::jsonb),
      result_summary = coalesce(_result_summary, '{}'::jsonb),
      failure_category = _failure_category,
      next_retry_at = _next_retry_at,
      updated_at = now()
  WHERE id = _job_id
    AND status = 'processing'
    AND lease_token = _lease_token
    AND lease_expires_at > now();
  GET DIAGNOSTICS affected_rows = ROW_COUNT;
  IF affected_rows <> 1 THEN
    RAISE EXCEPTION 'stale_enrichment_lease';
  END IF;
  RETURN _job_id;
END;
$$;

REVOKE ALL ON FUNCTION public.finalize_card_catalog_enrichment_job(
  uuid, uuid, text, uuid, text, jsonb, jsonb, text, timestamptz
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.finalize_card_catalog_enrichment_job(
  uuid, uuid, text, uuid, text, jsonb, jsonb, text, timestamptz
) TO service_role;

COMMIT;
