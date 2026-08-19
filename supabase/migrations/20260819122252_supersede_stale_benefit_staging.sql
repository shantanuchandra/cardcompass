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
BEGIN
  IF coalesce(auth.role(), '') <> 'service_role' THEN
    RAISE EXCEPTION 'service_role_required';
  END IF;
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
     OR _source_evidence IS NULL
     OR jsonb_typeof(_source_evidence) <> 'array'
     OR NOT (jsonb_array_length(_source_evidence) > 0) THEN
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

  SELECT staging.id INTO resolved_staging_id
  FROM public.card_benefits_staging AS staging
  WHERE staging.card_id = job.card_id
    AND staging.source_url_hash = _source_url_hash
    AND staging.parser_version = _parser_version
    AND staging.content_hash = _content_hash
    AND staging.request_type = 'official_benefit_enrichment'
    AND staging.status IN ('pending', 'approved')
    AND staging.source_evidence IS NOT NULL
    AND jsonb_typeof(staging.source_evidence) = 'array'
    AND jsonb_array_length(staging.source_evidence) > 0
  FOR UPDATE;
  reused_staging := FOUND;
  IF NOT reused_staging THEN
    resolved_staging_id := gen_random_uuid();
  END IF;

  IF _parser_version = 'benefits-v6' THEN
    -- Lock every older pending observation before changing its review state.
    -- This remains in the same transaction as the replacement insert/link.
    PERFORM 1
    FROM public.card_benefits_staging AS staging
    WHERE staging.card_id = job.card_id
      AND staging.parser_version = _parser_version
      AND staging.request_type = 'official_benefit_enrichment'
      AND staging.status = 'pending'
      AND staging.id <> resolved_staging_id
    FOR UPDATE;

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
    coalesce(_validated_at, now())
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

COMMIT;
