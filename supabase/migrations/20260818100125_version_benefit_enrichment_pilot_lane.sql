-- Keep the safety pilot idempotent within one parser generation while
-- retaining prior-generation pilot evidence for audit and rollback.
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
  WHERE run_mode = 'pilot'
    AND parser_version = trim(_parser_version);

  IF existing_pilot_count = 5 THEN
    RETURN QUERY
    SELECT job.*
    FROM public.card_catalog_enrichment_jobs AS job
    JOIN public.card_catalog AS card ON card.id = job.card_id
    WHERE job.run_mode = 'pilot'
      AND job.parser_version = trim(_parser_version)
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
     OR distinct_profile_count <> 5 OR distinct_issuer_count < 3 THEN
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
  WHERE run_mode = 'pilot'
    AND parser_version = trim(_parser_version);
  IF existing_pilot_count <> 5 THEN
    RAISE EXCEPTION 'pilot_initialization_failed';
  END IF;

  RETURN QUERY
  SELECT job.*
  FROM public.card_catalog_enrichment_jobs AS job
  JOIN public.card_catalog AS card ON card.id = job.card_id
  WHERE job.run_mode = 'pilot'
    AND job.parser_version = trim(_parser_version)
  ORDER BY job.issuer, card.card_name, job.created_at;
END;
$$;

REVOKE ALL ON FUNCTION public.initialize_card_benefit_enrichment_pilot(jsonb, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.initialize_card_benefit_enrichment_pilot(jsonb, text)
  TO service_role;
