ALTER TABLE public.card_catalog_provenance
  ADD COLUMN IF NOT EXISTS canonical_submitted_url text,
  ADD COLUMN IF NOT EXISTS canonical_final_url text,
  ADD COLUMN IF NOT EXISTS submitted_url_hash text,
  ADD COLUMN IF NOT EXISTS final_url_hash text;

UPDATE public.card_catalog_provenance
SET canonical_submitted_url = source_url,
    canonical_final_url = source_url
WHERE source_url ~ '^https://'
  AND canonical_submitted_url IS NULL
  AND canonical_final_url IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_card_catalog_provenance_submitted_url_hash
  ON public.card_catalog_provenance(submitted_url_hash)
  WHERE submitted_url_hash IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_card_catalog_provenance_final_url_hash
  ON public.card_catalog_provenance(final_url_hash)
  WHERE final_url_hash IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.card_catalog_enrichment_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  card_id uuid NOT NULL REFERENCES public.card_catalog(id) ON DELETE CASCADE,
  issuer text NOT NULL CHECK (length(trim(issuer)) BETWEEN 2 AND 120),
  canonical_url text NOT NULL CHECK (canonical_url ~ '^https://'),
  final_url_hash text NOT NULL CHECK (length(final_url_hash) = 64),
  content_hash text NOT NULL CHECK (length(content_hash) = 64),
  status text NOT NULL DEFAULT 'queued' CHECK (
    status IN ('queued', 'processing', 'completed', 'review_required', 'failed')
  ),
  attempt_count integer NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
  next_retry_at timestamptz,
  normalized_fields jsonb NOT NULL DEFAULT '{}'::jsonb
    CHECK (jsonb_typeof(normalized_fields) = 'object'),
  validation_warnings jsonb NOT NULL DEFAULT '[]'::jsonb
    CHECK (jsonb_typeof(validation_warnings) = 'array'),
  failure_category text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(card_id, final_url_hash, content_hash)
);

CREATE INDEX IF NOT EXISTS idx_card_catalog_enrichment_jobs_pending
  ON public.card_catalog_enrichment_jobs(status, next_retry_at)
  WHERE status IN ('queued', 'failed');

ALTER TABLE public.card_catalog_enrichment_jobs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.card_catalog_enrichment_jobs FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.card_catalog_enrichment_jobs TO service_role;

CREATE OR REPLACE FUNCTION public.resolve_card_catalog_identity(
  _issuer text,
  _card_name text,
  _network text,
  _source_url text,
  _submitted_url_hash text,
  _final_url_hash text
) RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  normalized_issuer text;
  normalized_name text;
  resolved_id uuid;
  candidate_count integer;
BEGIN
  normalized_issuer := lower(trim(_issuer));
  normalized_name := lower(regexp_replace(_card_name, '[^a-zA-Z0-9]+', '', 'g'));

  IF length(normalized_issuer) < 2 OR length(normalized_name) < 2 THEN
    RAISE EXCEPTION 'invalid_catalog_identity';
  END IF;
  IF _source_url IS NULL OR _source_url !~ '^https://' THEN
    RAISE EXCEPTION 'invalid_source_url';
  END IF;
  IF _submitted_url_hash !~ '^[0-9a-f]{64}$'
     OR _final_url_hash !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'invalid_url_hash';
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended(normalized_issuer || ':' || normalized_name, 0)
  );

  SELECT provenance.card_id
  INTO resolved_id
  FROM public.card_catalog_provenance AS provenance
  WHERE provenance.submitted_url_hash IN (_submitted_url_hash, _final_url_hash)
     OR provenance.final_url_hash IN (_submitted_url_hash, _final_url_hash)
  ORDER BY provenance.created_at
  LIMIT 1;

  IF resolved_id IS NOT NULL THEN
    RETURN resolved_id;
  END IF;

  WITH candidates AS (
    SELECT catalog.id
    FROM public.card_catalog AS catalog
    WHERE lower(trim(catalog.bank)) = normalized_issuer
      AND catalog.is_discontinued = false
      AND lower(regexp_replace(catalog.card_name, '[^a-zA-Z0-9]+', '', 'g')) = normalized_name
    UNION
    SELECT catalog.id
    FROM public.card_catalog AS catalog
    JOIN public.card_catalog_aliases AS alias ON alias.card_id = catalog.id
    WHERE lower(trim(catalog.bank)) = normalized_issuer
      AND catalog.is_discontinued = false
      AND lower(regexp_replace(alias.alias, '[^a-zA-Z0-9]+', '', 'g')) = normalized_name
  )
  SELECT count(*), min(id)
  INTO candidate_count, resolved_id
  FROM candidates;

  IF candidate_count > 1 THEN
    RAISE EXCEPTION 'ambiguous_catalog_identity';
  END IF;

  IF resolved_id IS NULL THEN
    INSERT INTO public.card_catalog(
      bank, card_name, network, card_type, card_url
    ) VALUES (
      trim(_issuer), trim(_card_name), nullif(trim(_network), ''), 'credit', _source_url
    )
    RETURNING id INTO resolved_id;
  ELSE
    UPDATE public.card_catalog
    SET network = COALESCE(network, nullif(trim(_network), '')),
        card_url = COALESCE(card_url, _source_url),
        updated_at = now()
    WHERE id = resolved_id;
  END IF;

  RETURN resolved_id;
END;
$$;

REVOKE ALL ON FUNCTION public.resolve_card_catalog_identity(
  text, text, text, text, text, text
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_card_catalog_identity(
  text, text, text, text, text, text
) TO service_role;
