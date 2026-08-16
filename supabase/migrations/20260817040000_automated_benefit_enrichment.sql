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

  UPDATE public.card_catalog_enrichment_jobs
  SET status = 'queued',
      lease_expires_at = NULL,
      updated_at = now()
  WHERE status = 'processing'
    AND (lease_expires_at IS NULL OR lease_expires_at <= now());

  SELECT job.issuer
  INTO selected_issuer
  FROM public.card_catalog_enrichment_jobs AS job
  JOIN public.card_catalog AS card ON card.id = job.card_id
  WHERE job.status IN ('queued', 'failed')
    AND (job.next_retry_at IS NULL OR job.next_retry_at <= now())
    AND job.run_mode = _run_mode
    AND NOT EXISTS (
      SELECT 1
      FROM public.card_catalog_enrichment_jobs AS leased
      WHERE leased.issuer = job.issuer
        AND leased.status = 'processing'
        AND leased.lease_expires_at > now()
    )
  ORDER BY job.issuer, card.card_name, job.created_at
  LIMIT 1;

  IF selected_issuer IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH candidates AS (
    SELECT job.id
    FROM public.card_catalog_enrichment_jobs AS job
    JOIN public.card_catalog AS card ON card.id = job.card_id
    WHERE job.issuer = selected_issuer
      AND job.status IN ('queued', 'failed')
      AND (job.next_retry_at IS NULL OR job.next_retry_at <= now())
      AND job.run_mode = _run_mode
    ORDER BY card.card_name, job.created_at
    LIMIT maximum_jobs
    FOR UPDATE SKIP LOCKED
  )
  UPDATE public.card_catalog_enrichment_jobs AS job
  SET status = 'processing',
      attempt_count = job.attempt_count + 1,
      lease_expires_at = now() + make_interval(secs => lease_seconds),
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
