-- A rollout gate is meaningful only when the worker claims the same parser
-- generation whose pilot was evaluated. Remove the unscoped signature so no
-- caller can accidentally mix queued parser generations.
DROP FUNCTION IF EXISTS public.claim_card_catalog_enrichment_jobs(integer, integer, text);

CREATE FUNCTION public.claim_card_catalog_enrichment_jobs(
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
  IF coalesce(auth.role(), '') <> 'service_role' THEN
    RAISE EXCEPTION 'service_role_required';
  END IF;
  selected_parser := trim(coalesce(_parser_version, ''));
  IF _max_jobs IS NULL OR _lease_seconds IS NULL OR _run_mode IS NULL
     OR _run_mode NOT IN ('pilot', 'scheduled', 'manual')
     OR length(selected_parser) < 3
     OR lower(selected_parser) = 'catalog-v1' THEN
    RAISE EXCEPTION 'invalid_enrichment_claim';
  END IF;

  maximum_jobs := LEAST(GREATEST(_max_jobs, 1), 5);
  lease_seconds := LEAST(GREATEST(_lease_seconds, 60), 3600);

  PERFORM pg_advisory_xact_lock(
    hashtextextended('card_catalog_enrichment_claim:' || selected_parser, 0)
  );

  UPDATE public.card_catalog_enrichment_jobs AS job
  SET status = CASE
        WHEN job.attempt_count >= 3 THEN 'review_required'
        ELSE 'failed'
      END,
      failure_category = 'worker_resource_limit',
      next_retry_at = CASE
        WHEN job.attempt_count >= 3 THEN NULL
        WHEN job.attempt_count = 1 THEN now() + interval '15 minutes'
        ELSE now() + interval '60 minutes'
      END,
      result_summary = coalesce(job.result_summary, '{}'::jsonb) || jsonb_build_object(
        'lease_expired', true,
        'retry_scheduled', job.attempt_count < 3
      ),
      lease_expires_at = NULL,
      lease_token = NULL,
      updated_at = now()
  WHERE job.status = 'processing'
    AND job.parser_version = selected_parser
    AND (job.lease_expires_at IS NULL OR job.lease_expires_at <= now());

  SELECT lower(trim(job.issuer))
  INTO selected_issuer
  FROM public.card_catalog_enrichment_jobs AS job
  JOIN public.card_catalog AS card ON card.id = job.card_id
  WHERE job.status IN ('queued', 'failed')
    AND (job.next_retry_at IS NULL OR job.next_retry_at <= now())
    AND job.run_mode = _run_mode
    AND job.parser_version = selected_parser
    AND NOT EXISTS (
      SELECT 1
      FROM public.card_catalog_enrichment_jobs AS leased
      WHERE lower(trim(leased.issuer)) = lower(trim(job.issuer))
        AND leased.status = 'processing'
        AND leased.parser_version = selected_parser
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
      AND job.parser_version = selected_parser
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

REVOKE ALL ON FUNCTION public.claim_card_catalog_enrichment_jobs(integer, integer, text, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_card_catalog_enrichment_jobs(integer, integer, text, text)
  TO service_role;
