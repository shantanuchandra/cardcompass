BEGIN;

-- Fail rather than waiting indefinitely on production traffic or an
-- unexpectedly expensive legacy repair.
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '120s';
SET LOCAL TIME ZONE 'UTC';

ALTER TABLE public.card_catalog_enrichment_jobs
  ADD COLUMN IF NOT EXISTS next_run_at timestamptz;

ALTER TABLE public.card_benefit_mapping
  ADD COLUMN IF NOT EXISTS retired_at timestamptz;

CREATE INDEX IF NOT EXISTS idx_card_catalog_enrichment_jobs_due_v6
  ON public.card_catalog_enrichment_jobs (
    parser_version, run_mode, next_run_at, issuer
  )
  WHERE status IN ('staged', 'completed', 'review_required', 'quarantined')
    AND next_run_at IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_card_benefit_mapping_active_card_priority
  ON public.card_benefit_mapping (card_id, display_priority)
  WHERE retired_at IS NULL;

UPDATE public.card_catalog
SET is_discontinued = false
WHERE is_discontinued IS NULL;

ALTER TABLE public.card_catalog
  ALTER COLUMN is_discontinued SET DEFAULT false,
  ALTER COLUMN is_discontinued SET NOT NULL;

-- Normalize historical JSON without assigning an unknown exclusion to a
-- structured exclusion category. Unclassified strings remain auditably
-- available in additional.source_terms. Existing object-valued additional
-- metadata is retained.
CREATE OR REPLACE FUNCTION public.normalize_benefit_exclusions_value(
  _exclusions jsonb
) RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
SECURITY INVOKER
SET search_path = pg_catalog
AS $$
DECLARE
  root_type text := jsonb_typeof(_exclusions);
  base_exclusions jsonb := CASE
    WHEN jsonb_typeof(_exclusions) = 'object' THEN _exclusions
    ELSE '{}'::jsonb
  END;
  existing_additional jsonb := CASE
    WHEN jsonb_typeof(_exclusions->'additional') = 'object'
      THEN _exclusions->'additional'
    ELSE '{}'::jsonb
  END;
  normalized_additional jsonb;
  source_terms jsonb := '[]'::jsonb;
  legacy_values jsonb := '[]'::jsonb;
  source_terms_was_present boolean := false;
  legacy_values_was_present boolean := false;
  key_name text;
  malformed_value jsonb;
  element record;
BEGIN
  IF existing_additional ? 'legacy_values' THEN
    legacy_values_was_present := true;
    IF jsonb_typeof(existing_additional->'legacy_values') = 'array' THEN
      legacy_values := existing_additional->'legacy_values';
    ELSE
      legacy_values := legacy_values || jsonb_build_array(jsonb_build_object(
        'path', '$.additional.legacy_values',
        'value', existing_additional->'legacy_values'
      ));
    END IF;
  END IF;

  IF existing_additional ? 'source_terms' THEN
    source_terms_was_present := true;
    malformed_value := existing_additional->'source_terms';
    IF jsonb_typeof(malformed_value) = 'array' THEN
      FOR element IN
        SELECT item.value, item.ordinality
        FROM jsonb_array_elements(malformed_value)
          WITH ORDINALITY AS item(value, ordinality)
        ORDER BY item.ordinality
      LOOP
        IF jsonb_typeof(element.value) = 'string' THEN
          source_terms := source_terms || jsonb_build_array(element.value);
        ELSE
          legacy_values := legacy_values || jsonb_build_array(jsonb_build_object(
            'path', format(
              '$.additional.source_terms[%s]',
              element.ordinality - 1
            ),
            'value', element.value
          ));
        END IF;
      END LOOP;
    ELSE
      IF jsonb_typeof(malformed_value) = 'string' THEN
        source_terms := source_terms || jsonb_build_array(malformed_value);
      END IF;
      legacy_values := legacy_values || jsonb_build_array(jsonb_build_object(
        'path', '$.additional.source_terms',
        'value', malformed_value
      ));
    END IF;
  END IF;

  IF root_type = 'array' THEN
    FOR element IN
      SELECT item.value, item.ordinality
      FROM jsonb_array_elements(_exclusions)
        WITH ORDINALITY AS item(value, ordinality)
      ORDER BY item.ordinality
    LOOP
      IF jsonb_typeof(element.value) = 'string' THEN
        source_terms := source_terms || jsonb_build_array(element.value);
      ELSIF jsonb_typeof(element.value) <> 'string' THEN
        legacy_values := legacy_values || jsonb_build_array(jsonb_build_object(
          'path', format('$[%s]', element.ordinality - 1),
          'value', element.value
        ));
      END IF;
    END LOOP;
  ELSIF root_type = 'string' THEN
    source_terms := source_terms || jsonb_build_array(_exclusions);
  ELSIF root_type IN ('null', 'number', 'boolean') THEN
    legacy_values := legacy_values || jsonb_build_array(jsonb_build_object(
      'path', '$',
      'value', _exclusions
    ));
  END IF;

  IF base_exclusions ? 'additional'
     AND jsonb_typeof(_exclusions->'additional') <> 'object' THEN
    malformed_value := _exclusions->'additional';
    IF jsonb_typeof(malformed_value) = 'string' THEN
      source_terms := source_terms || jsonb_build_array(malformed_value);
    END IF;
    legacy_values := legacy_values || jsonb_build_array(jsonb_build_object(
      'path', '$.additional',
      'value', malformed_value
    ));
  END IF;

  FOREACH key_name IN ARRAY ARRAY[
    'days', 'mcc_codes', 'merchants', 'categories', 'transaction_types'
  ]
  LOOP
    IF base_exclusions ? key_name
       AND jsonb_typeof(_exclusions->key_name) <> 'array' THEN
      malformed_value := _exclusions->key_name;
      IF jsonb_typeof(malformed_value) = 'string' THEN
        source_terms := source_terms || jsonb_build_array(malformed_value);
      END IF;
      legacy_values := legacy_values || jsonb_build_array(jsonb_build_object(
        'path', format('$.%s', key_name),
        'value', malformed_value
      ));
    END IF;
  END LOOP;

  normalized_additional := existing_additional
    || CASE
      WHEN source_terms_was_present OR jsonb_array_length(source_terms) > 0
        THEN jsonb_build_object('source_terms', source_terms)
      ELSE '{}'::jsonb
    END
    || CASE
      WHEN legacy_values_was_present OR jsonb_array_length(legacy_values) > 0
        THEN jsonb_build_object('legacy_values', legacy_values)
      ELSE '{}'::jsonb
    END;

  RETURN base_exclusions || jsonb_build_object(
    'days', CASE
      WHEN jsonb_typeof(_exclusions->'days') = 'array'
        THEN _exclusions->'days'
      ELSE '[]'::jsonb
    END,
    'mcc_codes', CASE
      WHEN jsonb_typeof(_exclusions->'mcc_codes') = 'array'
        THEN _exclusions->'mcc_codes'
      ELSE '[]'::jsonb
    END,
    'merchants', CASE
      WHEN jsonb_typeof(_exclusions->'merchants') = 'array'
        THEN _exclusions->'merchants'
      ELSE '[]'::jsonb
    END,
    'categories', CASE
      WHEN jsonb_typeof(_exclusions->'categories') = 'array'
        THEN _exclusions->'categories'
      ELSE '[]'::jsonb
    END,
    'transaction_types', CASE
      WHEN jsonb_typeof(_exclusions->'transaction_types') = 'array'
        THEN _exclusions->'transaction_types'
      ELSE '[]'::jsonb
    END,
    'additional', normalized_additional
  );
END;
$$;

REVOKE ALL ON FUNCTION public.normalize_benefit_exclusions_value(jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.normalize_benefit_exclusions_value(jsonb)
  TO service_role;

WITH normalized AS (
  SELECT
    benefit.benefit_id,
    CASE
      WHEN jsonb_typeof(benefit.value_config) = 'object'
        THEN benefit.value_config
      WHEN benefit.value_config IS NULL
        THEN '{}'::jsonb
      ELSE jsonb_build_object('legacy_value', benefit.value_config)
    END AS value_config,
    CASE
      WHEN jsonb_typeof(benefit.partners) = 'array'
        THEN benefit.partners
      WHEN benefit.partners IS NULL
        THEN '[]'::jsonb
      ELSE jsonb_build_array(benefit.partners)
    END AS partners,
    public.normalize_benefit_exclusions_value(benefit.exclusions) AS exclusions,
    CASE
      WHEN jsonb_typeof(benefit.regions) = 'array'
        THEN benefit.regions
      WHEN benefit.regions IS NULL
        THEN '[]'::jsonb
      ELSE jsonb_build_array(benefit.regions)
    END AS regions
  FROM public.benefits AS benefit
)
UPDATE public.benefits AS benefit
SET value_config = normalized.value_config,
    partners = normalized.partners,
    exclusions = normalized.exclusions,
    regions = normalized.regions
FROM normalized
WHERE normalized.benefit_id = benefit.benefit_id
  AND (
    normalized.value_config IS DISTINCT FROM benefit.value_config
    OR normalized.partners IS DISTINCT FROM benefit.partners
    OR normalized.exclusions IS DISTINCT FROM benefit.exclusions
    OR normalized.regions IS DISTINCT FROM benefit.regions
  );

-- Keep the benefits-v5 rollback lane write-compatible while the live column
-- contract is object-shaped. The legacy RPC supplies a flat string array;
-- normalize it without assigning those strings to narrower categories.
CREATE OR REPLACE FUNCTION public.normalize_benefit_exclusions_shape()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
BEGIN
  NEW.exclusions := public.normalize_benefit_exclusions_value(NEW.exclusions);
  RETURN NEW;
END;
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_trigger
    WHERE tgrelid = 'public.benefits'::regclass
      AND tgname = 'normalize_benefit_exclusions_shape'
      AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER normalize_benefit_exclusions_shape
    BEFORE INSERT OR UPDATE OF exclusions ON public.benefits
    FOR EACH ROW
    EXECUTE FUNCTION public.normalize_benefit_exclusions_shape();
  END IF;
END;
$$;

UPDATE public.card_catalog_enrichment_jobs
SET result_summary = CASE
  WHEN result_summary IS NULL THEN '{}'::jsonb
  ELSE jsonb_build_object('legacy_value', result_summary)
END
WHERE result_summary IS NULL
   OR jsonb_typeof(result_summary) <> 'object';

-- Keep malformed historical staging rows for audit, but keep them outside the
-- current request contracts. New rows using either live request type must
-- carry every field needed for deterministic ownership and review.
UPDATE public.card_benefits_staging
SET request_type = CASE
  WHEN coalesce(nullif(trim(request_type), ''), extracted_data->>'request_type')
       = 'official_benefit_enrichment'
    AND card_id IS NOT NULL
    AND nullif(trim(source_url), '') IS NOT NULL
    AND nullif(trim(parser_version), '') IS NOT NULL
    AND nullif(trim(source_url_hash), '') IS NOT NULL
    AND nullif(trim(content_hash), '') IS NOT NULL
    AND jsonb_typeof(extracted_data) = 'object'
    AND source_evidence IS NOT NULL
    AND CASE
      WHEN jsonb_typeof(source_evidence) = 'array'
        THEN jsonb_array_length(source_evidence) > 0
      ELSE false
    END
    THEN 'official_benefit_enrichment'
  WHEN coalesce(nullif(trim(request_type), ''), extracted_data->>'request_type')
       = 'catalog_entry'
    AND requested_by IS NOT NULL
    AND jsonb_typeof(extracted_data) = 'object'
    THEN 'catalog_entry'
  ELSE 'legacy'
END
WHERE nullif(trim(request_type), '') IS NULL
   OR request_type IN ('official_benefit_enrichment', 'catalog_entry');

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.benefits'::regclass
      AND conname = 'benefits_value_config_object_check'
  ) THEN
    ALTER TABLE public.benefits
      ADD CONSTRAINT benefits_value_config_object_check
      CHECK (
        value_config IS NOT NULL
        AND jsonb_typeof(value_config) = 'object'
      ) NOT VALID;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.benefits'::regclass
      AND conname = 'benefits_partners_array_check'
  ) THEN
    ALTER TABLE public.benefits
      ADD CONSTRAINT benefits_partners_array_check
      CHECK (
        partners IS NOT NULL
        AND jsonb_typeof(partners) = 'array'
      ) NOT VALID;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.benefits'::regclass
      AND conname = 'benefits_exclusions_object_check'
  ) THEN
    ALTER TABLE public.benefits
      ADD CONSTRAINT benefits_exclusions_object_check CHECK (
        exclusions IS NOT NULL
        AND jsonb_typeof(exclusions) = 'object'
        AND coalesce(jsonb_typeof(exclusions->'days') = 'array', false)
        AND coalesce(jsonb_typeof(exclusions->'mcc_codes') = 'array', false)
        AND coalesce(jsonb_typeof(exclusions->'merchants') = 'array', false)
        AND coalesce(jsonb_typeof(exclusions->'categories') = 'array', false)
        AND coalesce(jsonb_typeof(exclusions->'transaction_types') = 'array', false)
        AND coalesce(jsonb_typeof(exclusions->'additional') = 'object', false)
        AND (
          NOT ((exclusions->'additional') ? 'source_terms')
          OR coalesce(
            jsonb_typeof(exclusions->'additional'->'source_terms') = 'array',
            false
          )
        )
      ) NOT VALID;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.benefits'::regclass
      AND conname = 'benefits_regions_array_check'
  ) THEN
    ALTER TABLE public.benefits
      ADD CONSTRAINT benefits_regions_array_check
      CHECK (
        regions IS NOT NULL
        AND jsonb_typeof(regions) = 'array'
      ) NOT VALID;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.card_catalog_enrichment_jobs'::regclass
      AND conname = 'card_catalog_enrichment_jobs_result_summary_object_check'
  ) THEN
    ALTER TABLE public.card_catalog_enrichment_jobs
      ADD CONSTRAINT card_catalog_enrichment_jobs_result_summary_object_check
      CHECK (jsonb_typeof(result_summary) = 'object') NOT VALID;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.card_benefits_staging'::regclass
      AND conname = 'card_benefits_staging_official_shape_check'
  ) THEN
    ALTER TABLE public.card_benefits_staging
      ADD CONSTRAINT card_benefits_staging_official_shape_check CHECK (
        request_type <> 'official_benefit_enrichment'
        OR (
          card_id IS NOT NULL
          AND nullif(trim(source_url), '') IS NOT NULL
          AND nullif(trim(parser_version), '') IS NOT NULL
          AND nullif(trim(source_url_hash), '') IS NOT NULL
          AND nullif(trim(content_hash), '') IS NOT NULL
          AND jsonb_typeof(extracted_data) = 'object'
          AND source_evidence IS NOT NULL
          AND CASE
            WHEN jsonb_typeof(source_evidence) = 'array'
              THEN jsonb_array_length(source_evidence) > 0
            ELSE false
          END
        )
      ) NOT VALID;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.card_benefits_staging'::regclass
      AND conname = 'card_benefits_staging_catalog_entry_shape_check'
  ) THEN
    ALTER TABLE public.card_benefits_staging
      ADD CONSTRAINT card_benefits_staging_catalog_entry_shape_check CHECK (
        request_type <> 'catalog_entry'
        OR (
          requested_by IS NOT NULL
          AND jsonb_typeof(extracted_data) = 'object'
        )
      ) NOT VALID;
  END IF;
END;
$$;

ALTER TABLE public.benefits
  VALIDATE CONSTRAINT benefits_value_config_object_check;
ALTER TABLE public.benefits
  VALIDATE CONSTRAINT benefits_partners_array_check;
ALTER TABLE public.benefits
  VALIDATE CONSTRAINT benefits_exclusions_object_check;
ALTER TABLE public.benefits
  VALIDATE CONSTRAINT benefits_regions_array_check;
ALTER TABLE public.card_catalog_enrichment_jobs
  VALIDATE CONSTRAINT card_catalog_enrichment_jobs_result_summary_object_check;
ALTER TABLE public.card_benefits_staging
  VALIDATE CONSTRAINT card_benefits_staging_official_shape_check;
ALTER TABLE public.card_benefits_staging
  VALIDATE CONSTRAINT card_benefits_staging_catalog_entry_shape_check;

ALTER TABLE public.card_catalog ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.benefit_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.benefits ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.card_benefit_mapping ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'card_catalog'
      AND policyname = 'authenticated_read_card_catalog'
  ) THEN
    CREATE POLICY authenticated_read_card_catalog
      ON public.card_catalog FOR SELECT TO authenticated USING (true);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'benefit_categories'
      AND policyname = 'authenticated_read_benefit_categories'
  ) THEN
    CREATE POLICY authenticated_read_benefit_categories
      ON public.benefit_categories FOR SELECT TO authenticated USING (true);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'benefits'
      AND policyname = 'authenticated_read_benefits'
  ) THEN
    CREATE POLICY authenticated_read_benefits
      ON public.benefits FOR SELECT TO authenticated USING (true);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'card_benefit_mapping'
      AND policyname = 'authenticated_read_card_benefit_mapping'
  ) THEN
    CREATE POLICY authenticated_read_card_benefit_mapping
      ON public.card_benefit_mapping FOR SELECT TO authenticated USING (true);
  END IF;
END;
$$;

GRANT SELECT ON TABLE public.card_catalog TO authenticated;
GRANT SELECT ON TABLE public.benefit_categories TO authenticated;
GRANT SELECT ON TABLE public.benefits TO authenticated;
GRANT SELECT ON TABLE public.card_benefit_mapping TO authenticated;

REVOKE INSERT, UPDATE, DELETE ON TABLE public.card_catalog FROM PUBLIC, anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON TABLE public.benefit_categories FROM PUBLIC, anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON TABLE public.benefits FROM PUBLIC, anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON TABLE public.card_benefit_mapping FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.card_benefits FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE VIEW public.active_card_benefits
WITH (security_invoker = true) AS
SELECT
  mapping.mapping_id,
  mapping.card_id,
  mapping.benefit_id,
  mapping.display_priority,
  mapping.is_primary,
  mapping.category_codes,
  mapping.retired_at,
  mapping.created_at AS mapping_created_at,
  benefit.title,
  benefit.description,
  benefit.benefit_category,
  benefit.benefit_type,
  benefit.value_config,
  benefit.partners,
  benefit.exclusions,
  benefit.regions,
  benefit.source_url,
  benefit.valid_from,
  benefit.valid_until,
  benefit.is_active,
  benefit.dedupe_key,
  benefit.created_at AS benefit_created_at,
  benefit.updated_at AS benefit_updated_at
FROM public.card_benefit_mapping AS mapping
JOIN public.benefits AS benefit
  ON benefit.benefit_id = mapping.benefit_id
CROSS JOIN LATERAL (
  SELECT timezone('UTC', statement_timestamp())::date AS utc_date
) AS database_clock
WHERE (mapping.retired_at IS NULL OR mapping.retired_at > now())
  AND benefit.is_active = true
  AND (
    benefit.valid_from IS NULL
    OR benefit.valid_from <= database_clock.utc_date
  )
  AND (
    benefit.valid_until IS NULL
    OR benefit.valid_until >= database_clock.utc_date
  );

REVOKE ALL ON TABLE public.active_card_benefits FROM PUBLIC, anon;
GRANT SELECT ON TABLE public.active_card_benefits TO authenticated, service_role;

-- Revoke all legacy catalog-write overloads if they still exist on an older
-- deployment. Function identity arguments are catalog-derived, not composed
-- from external input.
DO $$
DECLARE
  legacy_function record;
BEGIN
  FOR legacy_function IN
    SELECT function_row.oid::regprocedure AS identity
    FROM pg_proc AS function_row
    JOIN pg_namespace AS namespace
      ON namespace.oid = function_row.pronamespace
    WHERE namespace.nspname = 'public'
      AND function_row.proname IN (
        'create_credit_card',
        'create_or_get_card_catalog'
      )
  LOOP
    EXECUTE format(
      'REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated',
      legacy_function.identity
    );
  END LOOP;
END;
$$;

-- Access is authorized by PostgreSQL EXECUTE grants. Keep every ingestion
-- write/claim/finalize/review function explicit and service-role-only.
REVOKE ALL ON FUNCTION public.create_or_get_card_catalog(
  text, text, text, text, numeric, numeric, numeric
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_or_get_card_catalog(
  text, text, text, text, numeric, numeric, numeric
) TO service_role;

REVOKE ALL ON FUNCTION public.resolve_card_catalog_identity(
  text, text, text, text, text, text
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_card_catalog_identity(
  text, text, text, text, text, text
) TO service_role;

REVOKE ALL ON FUNCTION public.initialize_card_benefit_enrichment_pilot(jsonb, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.initialize_card_benefit_enrichment_pilot(jsonb, text)
  TO service_role;

REVOKE ALL ON FUNCTION public.claim_card_catalog_enrichment_jobs(integer, integer, text, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_card_catalog_enrichment_jobs(integer, integer, text, text)
  TO service_role;

REVOKE ALL ON FUNCTION public.stage_card_benefit_enrichment(
  uuid, uuid, text, text, text, text, jsonb, numeric, jsonb, jsonb, jsonb, timestamptz
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.stage_card_benefit_enrichment(
  uuid, uuid, text, text, text, text, jsonb, numeric, jsonb, jsonb, jsonb, timestamptz
) TO service_role;

REVOKE ALL ON FUNCTION public.finalize_card_catalog_enrichment_job(
  uuid, uuid, text, uuid, text, jsonb, jsonb, text, timestamptz
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.finalize_card_catalog_enrichment_job(
  uuid, uuid, text, uuid, text, jsonb, jsonb, text, timestamptz
) TO service_role;

REVOKE ALL ON FUNCTION public.approve_card_benefit_enrichment(uuid, uuid, jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.approve_card_benefit_enrichment(uuid, uuid, jsonb)
  TO service_role;

REVOKE ALL ON FUNCTION public.list_pending_catalog_entry_requests()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.list_pending_catalog_entry_requests()
  TO service_role;

REVOKE ALL ON FUNCTION public.approve_catalog_entry_request(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.approve_catalog_entry_request(uuid, uuid)
  TO service_role;

REVOKE ALL ON FUNCTION public.reject_catalog_entry_request(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reject_catalog_entry_request(uuid, uuid)
  TO service_role;

REVOKE ALL ON FUNCTION public.review_card_catalog_discovery(uuid, uuid, text, jsonb, uuid, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.review_card_catalog_discovery(uuid, uuid, text, jsonb, uuid, text)
  TO service_role;

REVOKE ALL ON FUNCTION public.submit_card_catalog_request(uuid, text, text, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.submit_card_catalog_request(uuid, text, text, text)
  TO service_role;

COMMIT;
