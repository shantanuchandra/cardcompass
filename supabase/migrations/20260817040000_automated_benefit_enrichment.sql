BEGIN;

-- Discovery jobs from issuer crawling are service-owned. Existing statement
-- jobs retain their user-scoped deduplication rule.
ALTER TABLE public.card_discovery_jobs
  ALTER COLUMN user_id DROP NOT NULL;

ALTER TABLE public.card_discovery_jobs
  ADD COLUMN discovery_source text NOT NULL DEFAULT 'statement'
  CHECK (discovery_source IN ('statement', 'issuer_crawl'));

ALTER TABLE public.card_discovery_jobs
  DROP CONSTRAINT IF EXISTS card_discovery_jobs_user_id_dedupe_key_key;

CREATE UNIQUE INDEX IF NOT EXISTS idx_card_discovery_jobs_user_dedupe_key
  ON public.card_discovery_jobs (user_id, dedupe_key)
  WHERE user_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_card_discovery_jobs_service_dedupe_key
  ON public.card_discovery_jobs (discovery_source, dedupe_key)
  WHERE user_id IS NULL;

-- Queue rows can now be created before content is fetched. The deterministic
-- key prevents duplicate work for the same card, canonical URL, and parser.
ALTER TABLE public.card_catalog_enrichment_jobs
  ADD COLUMN parser_version text NOT NULL DEFAULT 'benefits-v1',
  ADD COLUMN lease_expires_at timestamptz,
  ADD COLUMN lease_token uuid,
  ADD COLUMN staging_id uuid REFERENCES public.card_benefits_staging(id),
  ADD COLUMN run_mode text NOT NULL DEFAULT 'scheduled'
    CHECK (run_mode IN ('pilot', 'scheduled', 'manual')),
  ADD COLUMN job_key text,
  ADD COLUMN result_summary jsonb NOT NULL DEFAULT '{}'::jsonb;

ALTER TABLE public.card_catalog_enrichment_jobs
  ALTER COLUMN content_hash DROP NOT NULL;

ALTER TABLE public.card_catalog_enrichment_jobs
  DROP CONSTRAINT IF EXISTS card_catalog_enrichment_jobs_status_check;

-- PostgreSQL truncates generated constraint names, so locate the legacy
-- three-column uniqueness constraint by definition instead of guessing it.
DO $$
DECLARE
  constraint_name text;
BEGIN
  FOR constraint_name IN
    SELECT constraint_row.conname
    FROM pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = 'public.card_catalog_enrichment_jobs'::regclass
      AND constraint_row.contype = 'u'
      AND pg_get_constraintdef(constraint_row.oid) =
        'UNIQUE (card_id, final_url_hash, content_hash)'
  LOOP
    EXECUTE format(
      'ALTER TABLE public.card_catalog_enrichment_jobs DROP CONSTRAINT %I',
      constraint_name
    );
  END LOOP;
END;
$$;

ALTER TABLE public.card_catalog_enrichment_jobs
  ADD CONSTRAINT card_catalog_enrichment_jobs_status_check CHECK (
    status IN ('queued', 'processing', 'completed', 'review_required', 'failed', 'staged', 'quarantined')
  );

WITH ranked AS (
  SELECT
    id,
    card_id::text || ':' || final_url_hash || ':' || parser_version AS canonical_key,
    row_number() OVER (
      PARTITION BY card_id, final_url_hash, parser_version
      ORDER BY created_at DESC, id DESC
    ) AS row_rank
  FROM public.card_catalog_enrichment_jobs
)
UPDATE public.card_catalog_enrichment_jobs AS job
SET job_key = CASE
  WHEN ranked.row_rank = 1 THEN ranked.canonical_key
  ELSE 'legacy:' || job.id::text
END
FROM ranked
WHERE ranked.id = job.id;

ALTER TABLE public.card_catalog_enrichment_jobs
  ADD CONSTRAINT card_catalog_enrichment_jobs_job_key_key UNIQUE (job_key);

CREATE OR REPLACE FUNCTION public.set_card_catalog_enrichment_job_key()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
BEGIN
  NEW.job_key := NEW.card_id::text || ':' || NEW.final_url_hash || ':' || NEW.parser_version;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS set_card_catalog_enrichment_job_key
  ON public.card_catalog_enrichment_jobs;
CREATE TRIGGER set_card_catalog_enrichment_job_key
BEFORE INSERT OR UPDATE OF card_id, final_url_hash, parser_version, job_key
ON public.card_catalog_enrichment_jobs
FOR EACH ROW EXECUTE FUNCTION public.set_card_catalog_enrichment_job_key();

-- Official enrichment staging has a first-class deterministic identity. The
-- legacy extracted_data shape is retained for the review UI and approvals.
ALTER TABLE public.card_benefits_staging
  ADD COLUMN request_type text,
  ADD COLUMN parser_version text,
  ADD COLUMN source_url_hash text,
  ADD COLUMN content_hash text;

UPDATE public.card_benefits_staging
SET request_type = extracted_data->>'request_type',
    parser_version = extracted_data->>'parser_version',
    source_url_hash = CASE
      WHEN source_url ~ '^https://' THEN
        encode(extensions.digest(convert_to(trim(source_url), 'UTF8'), 'sha256'), 'hex')
      ELSE NULL
    END,
    content_hash = extracted_data->>'content_hash'
WHERE extracted_data->>'request_type' = 'official_benefit_enrichment';

-- Preserve the newest historical duplicate without making migration apply
-- fail. New official rows always carry all identity fields through the RPC.
WITH duplicate_staging AS (
  SELECT id,
    row_number() OVER (
      PARTITION BY card_id, source_url_hash, parser_version, content_hash
      ORDER BY created_at DESC, id DESC
    ) AS row_rank
  FROM public.card_benefits_staging
  WHERE request_type = 'official_benefit_enrichment'
    AND source_url_hash IS NOT NULL
    AND parser_version IS NOT NULL
    AND content_hash IS NOT NULL
)
UPDATE public.card_benefits_staging AS staging
SET source_url_hash = NULL
FROM duplicate_staging
WHERE staging.id = duplicate_staging.id
  AND duplicate_staging.row_rank > 1;

CREATE UNIQUE INDEX IF NOT EXISTS card_benefits_staging_official_identity
  ON public.card_benefits_staging (
    card_id, source_url_hash, parser_version, content_hash
  )
  WHERE request_type = 'official_benefit_enrichment';

CREATE OR REPLACE FUNCTION public.initialize_card_benefit_enrichment_pilot(
  _candidates jsonb,
  _parser_version text
) RETURNS SETOF public.card_catalog_enrichment_jobs
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  existing_pilot_count integer;
  eligible_count integer;
  distinct_card_count integer;
  distinct_profile_count integer;
  distinct_issuer_count integer;
  inserted_count integer;
BEGIN
  IF coalesce(auth.role(), '') <> 'service_role' THEN
    RAISE EXCEPTION 'service_role_required';
  END IF;
  IF _candidates IS NULL OR jsonb_typeof(_candidates) <> 'array'
     OR jsonb_array_length(_candidates) <> 5
     OR _parser_version IS NULL OR length(trim(_parser_version)) < 3 THEN
    RAISE EXCEPTION 'invalid_pilot_candidates';
  END IF;
  IF lower(trim(_parser_version)) = 'catalog-v1' THEN
    RAISE EXCEPTION 'reserved_parser_version';
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended('card_benefit_enrichment_pilot', 0)
  );

  SELECT count(*) INTO existing_pilot_count
  FROM public.card_catalog_enrichment_jobs
  WHERE run_mode = 'pilot';

  IF existing_pilot_count = 5 THEN
    RETURN QUERY
    SELECT job.*
    FROM public.card_catalog_enrichment_jobs AS job
    JOIN public.card_catalog AS card ON card.id = job.card_id
    WHERE job.run_mode = 'pilot'
    ORDER BY job.issuer, card.card_name, job.created_at;
    RETURN;
  ELSIF existing_pilot_count <> 0 THEN
    RAISE EXCEPTION 'pilot_state_incomplete';
  END IF;

  WITH input AS (
    SELECT candidate.card_id, lower(trim(candidate.profile)) AS profile
    FROM jsonb_to_recordset(_candidates)
      AS candidate(card_id uuid, profile text)
  ), eligible AS (
    SELECT input.card_id, input.profile, card.bank, card.card_url
    FROM input
    JOIN public.card_catalog AS card ON card.id = input.card_id
    WHERE card.is_discontinued = false
      AND lower(trim(card.card_type)) = 'credit'
      AND card.card_url ~ '^https://'
      AND input.profile IN (
        'straightforward', 'redirect_or_js', 'terms_linked',
        'known_invalid', 'additional_valid'
      )
  )
  SELECT count(*), count(DISTINCT card_id), count(DISTINCT profile),
         count(DISTINCT lower(trim(bank)))
  INTO eligible_count, distinct_card_count, distinct_profile_count,
       distinct_issuer_count
  FROM eligible;

  IF eligible_count <> 5 OR distinct_card_count <> 5
     OR distinct_profile_count <> 5
     OR distinct_issuer_count < 3 THEN
    RAISE EXCEPTION 'invalid_pilot_candidates';
  END IF;

  INSERT INTO public.card_catalog_enrichment_jobs (
    card_id, issuer, canonical_url, final_url_hash, content_hash,
    parser_version, status, run_mode, job_key, result_summary, updated_at
  )
  SELECT
    card.id,
    card.bank,
    trim(card.card_url),
    encode(extensions.digest(convert_to(trim(card.card_url), 'UTF8'), 'sha256'), 'hex'),
    NULL,
    trim(_parser_version),
    'queued',
    'pilot',
    card.id::text || ':' ||
      encode(extensions.digest(convert_to(trim(card.card_url), 'UTF8'), 'sha256'), 'hex') ||
      ':' || trim(_parser_version),
    jsonb_build_object(
      'pilot_profile', lower(trim(input.profile)),
      'unsafe_mutation_count', 0,
      'raw_body_stored', false,
      'evidence_passed', false,
      'idempotency_passed', false
    ),
    now()
  FROM jsonb_to_recordset(_candidates)
    AS input(card_id uuid, profile text)
  JOIN public.card_catalog AS card ON card.id = input.card_id
  ON CONFLICT (job_key) DO NOTHING;

  GET DIAGNOSTICS inserted_count = ROW_COUNT;
  IF inserted_count <> 5 THEN
    RAISE EXCEPTION 'pilot_candidate_conflict';
  END IF;

  SELECT count(*) INTO existing_pilot_count
  FROM public.card_catalog_enrichment_jobs
  WHERE run_mode = 'pilot';
  IF existing_pilot_count <> 5 THEN
    RAISE EXCEPTION 'pilot_initialization_failed';
  END IF;

  RETURN QUERY
  SELECT job.*
  FROM public.card_catalog_enrichment_jobs AS job
  JOIN public.card_catalog AS card ON card.id = job.card_id
  WHERE job.run_mode = 'pilot'
  ORDER BY job.issuer, card.card_name, job.created_at;
END;
$$;

REVOKE ALL ON FUNCTION public.initialize_card_benefit_enrichment_pilot(jsonb, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.initialize_card_benefit_enrichment_pilot(jsonb, text)
  TO service_role;

CREATE OR REPLACE FUNCTION public.claim_card_catalog_enrichment_jobs(
  _max_jobs integer,
  _lease_seconds integer,
  _run_mode text
) RETURNS SETOF public.card_catalog_enrichment_jobs
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  selected_issuer text;
  maximum_jobs integer;
  lease_seconds integer;
BEGIN
  IF coalesce(auth.role(), '') <> 'service_role' THEN
    RAISE EXCEPTION 'service_role_required';
  END IF;
  IF _max_jobs IS NULL OR _lease_seconds IS NULL OR _run_mode IS NULL
     OR _run_mode NOT IN ('pilot', 'scheduled', 'manual') THEN
    RAISE EXCEPTION 'invalid_enrichment_claim';
  END IF;

  maximum_jobs := LEAST(GREATEST(_max_jobs, 1), 5);
  lease_seconds := LEAST(GREATEST(_lease_seconds, 60), 3600);

  -- A transaction-scoped global lock serializes issuer selection and keeps the
  -- post-lock eligibility query authoritative for concurrent callers.
  PERFORM pg_advisory_xact_lock(
    hashtextextended('card_catalog_enrichment_claim', 0)
  );

  UPDATE public.card_catalog_enrichment_jobs AS job
  SET status = 'queued',
      lease_expires_at = NULL,
      lease_token = NULL,
      updated_at = now()
  WHERE job.status = 'processing'
    AND lower(trim(job.parser_version)) <> 'catalog-v1'
    AND (job.lease_expires_at IS NULL OR job.lease_expires_at <= now());

  SELECT lower(trim(job.issuer))
  INTO selected_issuer
  FROM public.card_catalog_enrichment_jobs AS job
  JOIN public.card_catalog AS card ON card.id = job.card_id
  WHERE job.status IN ('queued', 'failed')
    AND (job.next_retry_at IS NULL OR job.next_retry_at <= now())
    AND job.run_mode = _run_mode
    AND lower(trim(job.parser_version)) <> 'catalog-v1'
    AND NOT EXISTS (
      SELECT 1
      FROM public.card_catalog_enrichment_jobs AS leased
      WHERE lower(trim(leased.issuer)) = lower(trim(job.issuer))
        AND leased.status = 'processing'
        AND leased.lease_expires_at > now()
    )
  ORDER BY lower(trim(job.issuer)), card.card_name, job.created_at
  LIMIT 1;

  IF selected_issuer IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH candidates AS (
    SELECT job.id
    FROM public.card_catalog_enrichment_jobs AS job
    JOIN public.card_catalog AS card ON card.id = job.card_id
    WHERE lower(trim(job.issuer)) = selected_issuer
      AND job.status IN ('queued', 'failed')
      AND (job.next_retry_at IS NULL OR job.next_retry_at <= now())
      AND job.run_mode = _run_mode
      AND lower(trim(job.parser_version)) <> 'catalog-v1'
    ORDER BY card.card_name, job.created_at
    LIMIT maximum_jobs
    FOR UPDATE SKIP LOCKED
  )
  UPDATE public.card_catalog_enrichment_jobs AS job
  SET status = 'processing',
      attempt_count = job.attempt_count + 1,
      lease_expires_at = now() + make_interval(secs => lease_seconds),
      lease_token = gen_random_uuid(),
      updated_at = now()
  FROM candidates
  WHERE job.id = candidates.id
  RETURNING job.*;
END;
$$;

REVOKE ALL ON FUNCTION public.claim_card_catalog_enrichment_jobs(integer, integer, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_card_catalog_enrichment_jobs(integer, integer, text)
  TO service_role;

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
  IF FOUND THEN
    RETURN QUERY SELECT resolved_staging_id, true;
    RETURN;
  END IF;

  INSERT INTO public.card_benefits_staging (
    card_id, source_url, request_type, parser_version, source_url_hash,
    content_hash, extracted_data, status, validation_version,
    calculated_confidence, validation_reasons, validation_warnings,
    source_evidence, validated_at
  ) VALUES (
    job.card_id, trim(_source_url), 'official_benefit_enrichment',
    _parser_version, _source_url_hash, _content_hash, _extracted_data,
    'pending', _parser_version, _calculated_confidence,
    coalesce(_validation_reasons, '[]'::jsonb),
    coalesce(_validation_warnings, '[]'::jsonb), _source_evidence,
    coalesce(_validated_at, now())
  ) ON CONFLICT (card_id, source_url_hash, parser_version, content_hash)
      WHERE request_type = 'official_benefit_enrichment'
      DO NOTHING
  RETURNING id INTO resolved_staging_id;

  IF resolved_staging_id IS NULL THEN
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
    IF NOT FOUND THEN
      RAISE EXCEPTION 'unsafe_staging_identity';
    END IF;
    RETURN QUERY SELECT resolved_staging_id, true;
    RETURN;
  END IF;

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
  IF coalesce(auth.role(), '') <> 'service_role' THEN
    RAISE EXCEPTION 'service_role_required';
  END IF;
  IF _job_id IS NULL OR _lease_token IS NULL
     OR _status NOT IN ('staged', 'quarantined', 'failed', 'review_required')
     OR jsonb_typeof(coalesce(_normalized_fields, '{}'::jsonb)) <> 'object'
     OR jsonb_typeof(coalesce(_result_summary, '{}'::jsonb)) <> 'object'
     OR (_status = 'staged' AND _staging_id IS NULL)
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
     AND jsonb_typeof(staging.source_evidence) = 'array'
     AND jsonb_array_length(staging.source_evidence) > 0
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

CREATE OR REPLACE FUNCTION public.approve_card_benefit_enrichment(
  _staging_id uuid,
  _reviewed_by uuid,
  _decisions jsonb
) RETURNS TABLE (staging_id uuid, resulting_status text)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  staging_row public.card_benefits_staging%ROWTYPE;
  decision jsonb;
  proposal jsonb;
  decision_action text;
  proposed_dedupe_key text;
  proposed_category text;
  canonical_category text;
  resolved_benefit_id uuid;
  approved_count integer := 0;
  retained_count integer := 0;
  final_status text;
BEGIN
  IF coalesce(auth.role(), '') <> 'service_role' THEN
    RAISE EXCEPTION 'service_role_required';
  END IF;
  IF _staging_id IS NULL OR _reviewed_by IS NULL
     OR _decisions IS NULL OR jsonb_typeof(_decisions) <> 'array' THEN
    RAISE EXCEPTION 'invalid_benefit_approval';
  END IF;

  SELECT staging.*
  INTO staging_row
  FROM public.card_benefits_staging AS staging
  WHERE staging.id = _staging_id
    AND staging.status = 'pending'
    AND staging.extracted_data->>'request_type' = 'official_benefit_enrichment'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'invalid_or_non_pending_benefit_staging';
  END IF;

  FOR decision IN SELECT value FROM jsonb_array_elements(_decisions) AS item(value)
  LOOP
    decision_action := lower(trim(decision->>'action'));
    IF jsonb_typeof(decision) <> 'object'
       OR decision_action IS NULL
       OR decision_action NOT IN ('approve', 'edit', 'reject', 'keep_existing') THEN
      RAISE EXCEPTION 'invalid_benefit_decision';
    END IF;

    IF decision_action = 'keep_existing' THEN
      retained_count := retained_count + 1;
      CONTINUE;
    END IF;
    IF decision_action = 'reject' THEN
      CONTINUE;
    END IF;

    IF coalesce(decision->>'change_type', decision->>'changeType', '')
       IN ('removal', 'possible_removal') THEN
      RAISE EXCEPTION 'proposed removals cannot be approved';
    END IF;

    proposal := CASE
      WHEN decision_action = 'edit' THEN coalesce(
        decision->'edited_benefit', decision->'editedBenefit', decision->'benefit', decision
      )
      ELSE coalesce(decision->'benefit', decision->'proposed', decision)
    END;
    proposed_dedupe_key := coalesce(
      proposal->>'dedupe_key', proposal->>'dedupeKey',
      decision->>'dedupe_key', decision->>'dedupeKey'
    );
    proposed_category := trim(coalesce(
      proposal->>'benefit_category', proposal->>'category', ''
    ));

    IF proposed_dedupe_key IS NULL OR length(trim(proposed_dedupe_key)) < 3
       OR length(trim(coalesce(proposal->>'title', ''))) < 2
       OR length(proposed_category) < 2 THEN
      RAISE EXCEPTION 'approved benefit is missing identity fields';
    END IF;

    SELECT category.category_code
    INTO canonical_category
    FROM public.benefit_categories AS category
    WHERE lower(category.category_code) = lower(proposed_category)
       OR lower(category.name) = lower(proposed_category)
    ORDER BY
      CASE WHEN lower(category.category_code) = lower(proposed_category) THEN 0 ELSE 1 END,
      category.category_code
    LIMIT 1;

    IF canonical_category IS NULL THEN
      RAISE EXCEPTION 'approved benefit has an unknown category';
    END IF;

    INSERT INTO public.benefits (
      title, description, benefit_category, benefit_type, value_config,
      partners, exclusions, regions, source_url, dedupe_key,
      valid_from, valid_until, is_active
    ) VALUES (
      trim(proposal->>'title'),
      nullif(trim(proposal->>'description'), ''),
      canonical_category,
      nullif(trim(coalesce(proposal->>'benefit_type', proposal->>'valueType')), ''),
      coalesce(proposal->'value_config', proposal->'valueConfig', '{}'::jsonb),
      coalesce(proposal->'partners', '[]'::jsonb),
      coalesce(proposal->'exclusions', '{}'::jsonb),
      coalesce(proposal->'regions', '[]'::jsonb),
      nullif(trim(coalesce(proposal->>'source_url', proposal->>'sourceUrl')), ''),
      trim(proposed_dedupe_key),
      nullif(coalesce(proposal->>'valid_from', proposal->>'effectiveFrom'), '')::date,
      nullif(coalesce(proposal->>'valid_until', proposal->>'effectiveTo'), '')::date,
      true
    ) ON CONFLICT (dedupe_key) DO UPDATE
    SET title = EXCLUDED.title,
        description = EXCLUDED.description,
        benefit_category = EXCLUDED.benefit_category,
        benefit_type = EXCLUDED.benefit_type,
        value_config = EXCLUDED.value_config,
        partners = EXCLUDED.partners,
        exclusions = EXCLUDED.exclusions,
        regions = EXCLUDED.regions,
        source_url = EXCLUDED.source_url,
        valid_from = EXCLUDED.valid_from,
        valid_until = EXCLUDED.valid_until,
        is_active = true,
        updated_at = now()
    RETURNING benefit_id INTO resolved_benefit_id;

    INSERT INTO public.card_benefit_mapping (
      card_id, benefit_id, display_priority, is_primary, category_codes
    ) VALUES (
      staging_row.card_id,
      resolved_benefit_id,
      coalesce((decision->>'display_priority')::integer, 1),
      coalesce((decision->>'is_primary')::boolean, true),
      ARRAY[canonical_category]
    ) ON CONFLICT (card_id, benefit_id) DO UPDATE
    SET display_priority = EXCLUDED.display_priority,
        is_primary = EXCLUDED.is_primary,
        category_codes = EXCLUDED.category_codes;

    approved_count := approved_count + 1;
  END LOOP;

  final_status := CASE
    WHEN approved_count > 0 OR retained_count > 0 THEN 'approved'
    ELSE 'rejected'
  END;

  UPDATE public.card_benefits_staging
  SET benefit_decisions = _decisions,
      status = final_status,
      reviewed_by = _reviewed_by,
      reviewed_at = now(),
      updated_at = now()
  WHERE id = staging_row.id;

  RETURN QUERY SELECT staging_row.id, final_status;
END;
$$;

REVOKE ALL ON FUNCTION public.approve_card_benefit_enrichment(uuid, uuid, jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.approve_card_benefit_enrichment(uuid, uuid, jsonb)
  TO service_role;

COMMIT;
