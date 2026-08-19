BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

-- This serializer is deliberately structural only. Commercial normalization is
-- owned by the shared TypeScript benefit contract and arrives in a bounded,
-- server-created canonical_envelope.
CREATE OR REPLACE FUNCTION public.canonical_json_text(_value jsonb)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  result text;
BEGIN
  CASE jsonb_typeof(_value)
    WHEN 'object' THEN
      SELECT '{' || coalesce(string_agg(
        to_jsonb(item.key)::text || ':' || public.canonical_json_text(item.value),
        ',' ORDER BY item.key
      ), '') || '}'
      INTO result
      FROM jsonb_each(_value) AS item(key, value);
      RETURN result;
    WHEN 'array' THEN
      SELECT '[' || coalesce(string_agg(
        public.canonical_json_text(item.value),
        ',' ORDER BY item.ordinality
      ), '') || ']'
      INTO result
      FROM jsonb_array_elements(_value) WITH ORDINALITY AS item(value, ordinality);
      RETURN result;
    ELSE
      RETURN _value::text;
  END CASE;
END;
$$;

CREATE OR REPLACE FUNCTION public.canonical_benefit_condition_hash(
  _condition jsonb
) RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SECURITY INVOKER
SET search_path = public, extensions, pg_temp
AS $$
BEGIN
  IF _condition IS NULL OR jsonb_typeof(_condition) <> 'object' THEN
    RAISE EXCEPTION 'invalid_canonical_condition';
  END IF;
  RETURN encode(
    extensions.digest(
      convert_to('[' || public.canonical_json_text(_condition) || ']', 'UTF8'),
      'sha256'
    ),
    'hex'
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.card_scoped_benefit_key(
  _card_id uuid,
  _condition jsonb
) RETURNS text
LANGUAGE sql
IMMUTABLE
SECURITY INVOKER
SET search_path = public, extensions, pg_temp
AS $$
  SELECT 'card-benefit-v2:' || lower(_card_id::text) || ':' ||
    public.canonical_benefit_condition_hash(_condition);
$$;

CREATE OR REPLACE FUNCTION public.validate_benefit_publication_envelope(
  _envelope jsonb,
  _card_id uuid,
  _staged_proposal jsonb
) RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  condition_value jsonb;
  benefit_value jsonb;
  expected_staged_hash text;
  expected_condition_hash text;
  expected_key text;
  category_code text;
  valid_from_value date;
  valid_until_value date;
  array_key text;
BEGIN
  IF _envelope IS NULL OR jsonb_typeof(_envelope) <> 'object'
     OR _envelope->>'version' <> 'benefit-publication-v2'
     OR _staged_proposal IS NULL OR jsonb_typeof(_staged_proposal) <> 'object'
     OR jsonb_typeof(_envelope->'staged_proposal_binding') <> 'object'
     OR _envelope->'staged_proposal_binding' IS DISTINCT FROM _staged_proposal THEN
    RAISE EXCEPTION 'invalid_canonical_envelope';
  END IF;
  condition_value := _envelope->'condition';
  benefit_value := _envelope->'benefit';
  IF jsonb_typeof(condition_value) <> 'object'
     OR jsonb_typeof(benefit_value) <> 'object'
     OR jsonb_typeof(condition_value->'value_config') <> 'object'
     OR jsonb_typeof(condition_value->'exclusions') <> 'object'
     OR jsonb_typeof(benefit_value->'value_config') <> 'object'
     OR jsonb_typeof(benefit_value->'exclusions') <> 'object' THEN
    RAISE EXCEPTION 'invalid_canonical_envelope_shape';
  END IF;
  FOREACH array_key IN ARRAY ARRAY['partners', 'regions', 'restrictions']
  LOOP
    IF jsonb_typeof(condition_value->array_key) <> 'array'
       OR jsonb_array_length(condition_value->array_key) > 64
       OR EXISTS (
         SELECT 1 FROM jsonb_array_elements(condition_value->array_key) AS item(value)
         WHERE jsonb_typeof(item.value) <> 'string'
           OR length(item.value #>> '{}') > 500
       ) THEN
      RAISE EXCEPTION 'invalid_canonical_envelope_shape';
    END IF;
  END LOOP;
  FOREACH array_key IN ARRAY ARRAY[
    'categories', 'days', 'mcc_codes', 'merchants', 'transaction_types'
  ]
  LOOP
    IF jsonb_typeof(condition_value->'exclusions'->array_key) <> 'array'
       OR jsonb_array_length(condition_value->'exclusions'->array_key) > 64
       OR EXISTS (
         SELECT 1
         FROM jsonb_array_elements(condition_value->'exclusions'->array_key) AS item(value)
         WHERE jsonb_typeof(item.value) <> 'string'
           OR length(item.value #>> '{}') > 500
       ) THEN
      RAISE EXCEPTION 'invalid_canonical_exclusions';
    END IF;
  END LOOP;
  IF jsonb_typeof(condition_value->'exclusions'->'additional') <> 'object'
     OR jsonb_typeof(condition_value->'exclusions'->'additional'->'source_terms') <> 'array'
     OR jsonb_array_length(condition_value->'exclusions'->'additional'->'source_terms') > 64
     OR EXISTS (
       SELECT 1
       FROM jsonb_array_elements(
         condition_value->'exclusions'->'additional'->'source_terms'
       ) AS item(value)
       WHERE jsonb_typeof(item.value) <> 'string'
         OR length(item.value #>> '{}') > 500
     )
     OR octet_length(public.canonical_json_text(condition_value)) > 32768
     OR octet_length(public.canonical_json_text(benefit_value)) > 65536 THEN
    RAISE EXCEPTION 'invalid_canonical_exclusions';
  END IF;

  expected_staged_hash := encode(
    extensions.digest(
      convert_to(
        public.canonical_json_text(_envelope->'staged_proposal_binding'),
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );
  expected_condition_hash := public.canonical_benefit_condition_hash(condition_value);
  expected_key := public.card_scoped_benefit_key(_card_id, condition_value);
  IF lower(coalesce(_envelope->>'staged_proposal_hash', '')) <> expected_staged_hash
     OR lower(coalesce(_envelope->>'condition_hash', '')) <> expected_condition_hash
     OR coalesce(_envelope->>'dedupe_key', '') <> expected_key THEN
    RAISE EXCEPTION 'canonical_envelope_identity_mismatch';
  END IF;

  SELECT category.category_code INTO category_code
  FROM public.benefit_categories AS category
  WHERE category.is_active = true
    AND (
      lower(category.category_code) = lower(condition_value->>'category')
      OR lower(category.name) = lower(condition_value->>'category')
    )
  ORDER BY CASE
    WHEN lower(category.category_code) = lower(condition_value->>'category') THEN 0
    ELSE 1 END,
    category.category_code
  LIMIT 1;
  IF category_code IS NULL
     OR lower(benefit_value->>'benefit_category') <> lower(condition_value->>'category')
     OR lower(coalesce(benefit_value->>'benefit_type', '')) IS DISTINCT FROM
        lower(coalesce(condition_value->>'benefit_type', ''))
     OR benefit_value->'partners' IS DISTINCT FROM condition_value->'partners'
     OR benefit_value->'regions' IS DISTINCT FROM condition_value->'regions'
     OR benefit_value->'exclusions' IS DISTINCT FROM condition_value->'exclusions'
     OR benefit_value->'value_config'->'restrictions' IS DISTINCT FROM condition_value->'restrictions'
     OR benefit_value->'value_config'->'exclusions' IS DISTINCT FROM condition_value->'exclusions'
     OR benefit_value->'value_config'->'offer_subject' IS DISTINCT FROM condition_value->'semantic_key'
     OR (benefit_value->'value_config' - 'offer_subject' - 'restrictions' - 'exclusions')
        IS DISTINCT FROM condition_value->'value_config' THEN
    RAISE EXCEPTION 'canonical_envelope_terms_mismatch';
  END IF;
  IF length(trim(coalesce(benefit_value->>'title', ''))) NOT BETWEEN 2 AND 500 THEN
    RAISE EXCEPTION 'invalid_benefit_title';
  END IF;
  IF length(coalesce(benefit_value->>'description', '')) > 8000
     OR length(coalesce(benefit_value->>'benefit_category', '')) NOT BETWEEN 1 AND 200
     OR length(coalesce(benefit_value->>'benefit_type', '')) NOT BETWEEN 1 AND 200 THEN
    RAISE EXCEPTION 'invalid_canonical_envelope_shape';
  END IF;
  BEGIN
    IF benefit_value->>'valid_from' IS NOT NULL THEN
      IF benefit_value->>'valid_from' !~ '^\d{4}-\d{2}-\d{2}$' THEN
        RAISE EXCEPTION 'invalid_benefit_date';
      END IF;
      valid_from_value := (benefit_value->>'valid_from')::date;
    END IF;
    IF benefit_value->>'valid_until' IS NOT NULL THEN
      IF benefit_value->>'valid_until' !~ '^\d{4}-\d{2}-\d{2}$' THEN
        RAISE EXCEPTION 'invalid_benefit_date';
      END IF;
      valid_until_value := (benefit_value->>'valid_until')::date;
    END IF;
  EXCEPTION WHEN datetime_field_overflow OR invalid_datetime_format THEN
    RAISE EXCEPTION 'invalid_benefit_date';
  END;
  IF valid_from_value IS DISTINCT FROM nullif(condition_value->>'valid_from', '')::date
     OR valid_until_value IS DISTINCT FROM nullif(condition_value->>'valid_until', '')::date
     OR (valid_from_value IS NOT NULL AND valid_until_value IS NOT NULL
       AND valid_from_value > valid_until_value) THEN
    RAISE EXCEPTION 'invalid_benefit_date_range';
  END IF;
  RETURN _envelope || jsonb_build_object('database_category_code', category_code);
END;
$$;

CREATE OR REPLACE FUNCTION public.validate_locked_retirement_evidence(
  _extracted_data jsonb,
  _live_benefit_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  observation_value jsonb;
  candidate jsonb;
  benefit_value jsonb;
  observed_at_value timestamptz;
  explicit_end_date date;
  computed_reason text;
  timestamp_count integer;
  earliest_timestamp timestamptz;
  latest_timestamp timestamptz;
BEGIN
  IF _extracted_data IS NULL OR jsonb_typeof(_extracted_data) <> 'object' THEN
    RAISE EXCEPTION 'retirement_not_eligible';
  END IF;
  observation_value := _extracted_data->'crawl_observation';
  IF jsonb_typeof(observation_value) <> 'object'
     OR coalesce((observation_value->>'crawl_complete')::boolean, false) <> true
     OR jsonb_typeof(observation_value->'absent_benefit_ids') <> 'array'
     OR jsonb_typeof(observation_value->'absent_legacy_benefit_ids') <> 'array'
     OR jsonb_array_length(observation_value->'absent_benefit_ids') > 256
     OR jsonb_array_length(observation_value->'absent_legacy_benefit_ids') > 256
     OR EXISTS (
       SELECT 1 FROM jsonb_array_elements(
         (observation_value->'absent_benefit_ids') ||
         (observation_value->'absent_legacy_benefit_ids')
       ) AS absent(value)
       WHERE jsonb_typeof(absent.value) <> 'string'
     ) THEN
    RAISE EXCEPTION 'retirement_not_eligible';
  END IF;
  SELECT removal.value INTO candidate
  FROM jsonb_array_elements(coalesce(
    _extracted_data->'diff'->'possibleRemovals', '[]'::jsonb
  )) AS removal(value)
  WHERE removal.value->'benefit'->>'liveBenefitId' = _live_benefit_id::text
  LIMIT 1;
  benefit_value := candidate->'benefit';
  IF candidate IS NULL OR jsonb_typeof(benefit_value) <> 'object'
     OR jsonb_typeof(candidate->'completeAbsenceObservedAt') <> 'array'
     OR jsonb_array_length(candidate->'completeAbsenceObservedAt') NOT BETWEEN 1 AND 24
     OR NOT EXISTS (
       SELECT 1
       FROM jsonb_array_elements_text(
         (observation_value->'absent_benefit_ids') ||
         (observation_value->'absent_legacy_benefit_ids')
       ) AS absent(identifier)
       WHERE absent.identifier IN (
         coalesce(benefit_value->>'benefitId', ''),
         coalesce(benefit_value->>'dedupeKey', '')
       )
     ) THEN
    RAISE EXCEPTION 'retirement_not_eligible';
  END IF;
  BEGIN
    observed_at_value := (observation_value->>'observed_at')::timestamptz;
  EXCEPTION WHEN datetime_field_overflow OR invalid_datetime_format THEN
    RAISE EXCEPTION 'retirement_not_eligible';
  END;
  IF observed_at_value IS NULL THEN RAISE EXCEPTION 'retirement_not_eligible'; END IF;
  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(candidate->'completeAbsenceObservedAt') AS item(value)
    WHERE jsonb_typeof(item.value) <> 'string'
      OR item.value #>> '{}' !~ '^\d{4}-\d{2}-\d{2}T.*Z$'
  ) THEN RAISE EXCEPTION 'retirement_not_eligible'; END IF;
  BEGIN
    IF NOT EXISTS (
      SELECT 1
      FROM jsonb_array_elements_text(
        candidate->'completeAbsenceObservedAt'
      ) AS item(observed)
      WHERE item.observed::timestamptz = observed_at_value
    ) THEN RAISE EXCEPTION 'retirement_not_eligible'; END IF;
  EXCEPTION WHEN datetime_field_overflow OR invalid_datetime_format THEN
    RAISE EXCEPTION 'retirement_not_eligible';
  END;

  IF nullif(benefit_value->>'effectiveTo', '') IS NOT NULL THEN
    BEGIN
      explicit_end_date := (benefit_value->>'effectiveTo')::date;
    EXCEPTION WHEN datetime_field_overflow OR invalid_datetime_format THEN
      RAISE EXCEPTION 'retirement_not_eligible';
    END;
  END IF;
  IF explicit_end_date IS NOT NULL
     AND explicit_end_date < (observed_at_value AT TIME ZONE 'UTC')::date THEN
    computed_reason := 'explicit_past_end_date';
  ELSE
    SELECT count(DISTINCT observed), min(observed), max(observed)
    INTO timestamp_count, earliest_timestamp, latest_timestamp
    FROM (
      SELECT (item.value #>> '{}')::timestamptz AS observed
      FROM jsonb_array_elements(candidate->'completeAbsenceObservedAt') AS item(value)
    ) AS history;
    IF timestamp_count < 2
       OR latest_timestamp > observed_at_value
       OR latest_timestamp - earliest_timestamp < interval '7 days' THEN
      RAISE EXCEPTION 'retirement_not_eligible';
    END IF;
    computed_reason := 'two_complete_observations';
  END IF;
  IF coalesce((candidate->>'retirementEligible')::boolean, false) <> true
     OR candidate->>'retirementReason' <> computed_reason THEN
    RAISE EXCEPTION 'retirement_not_eligible';
  END IF;
  RETURN candidate || jsonb_build_object('verified_retirement_reason', computed_reason);
END;
$$;

CREATE OR REPLACE FUNCTION public.approve_card_benefit_enrichment(
  _staging_id uuid,
  _reviewed_by uuid,
  _decisions jsonb
) RETURNS TABLE (staging_id uuid, resulting_status text)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  staging_row public.card_benefits_staging%ROWTYPE;
  staged_proposal jsonb;
  canonical_envelope jsonb;
  canonical_benefit jsonb;
  decision jsonb;
  decision_action text;
  decision_identity text;
  decision_proposal_index integer;
  seen_decision_identities text[] := ARRAY[]::text[];
  existing_benefit_id uuid;
  staged_existing_benefit_id uuid;
  resolved_benefit_id uuid;
  retirement_candidate jsonb;
  retirement_at timestamptz;
  affected_rows integer;
  linked_job_count integer;
  approved_count integer := 0;
  retained_count integer := 0;
  retired_count integer := 0;
  rejected_count integer := 0;
  final_status text;
  review_payload_hash text;
  audit_decisions jsonb := '[]'::jsonb;
  audit_decision jsonb;
BEGIN
  IF _staging_id IS NULL OR _reviewed_by IS NULL OR _decisions IS NULL
     OR jsonb_typeof(_decisions) <> 'array' OR jsonb_array_length(_decisions) = 0 THEN
    RAISE EXCEPTION 'invalid_benefit_approval';
  END IF;
  review_payload_hash := encode(
    extensions.digest(
      convert_to(public.canonical_json_text(_decisions), 'UTF8'), 'sha256'
    ),
    'hex'
  );
  SELECT staging.* INTO staging_row
  FROM public.card_benefits_staging AS staging
  WHERE staging.id = _staging_id
    AND staging.request_type = 'official_benefit_enrichment'
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'invalid_benefit_staging'; END IF;

  IF staging_row.status <> 'pending' THEN
    IF EXISTS (
      SELECT 1 FROM jsonb_array_elements(
        CASE WHEN jsonb_typeof(staging_row.benefit_decisions) = 'array'
          THEN staging_row.benefit_decisions ELSE '[]'::jsonb END
      ) AS prior(value)
      WHERE prior.value->>'review_payload_hash' = review_payload_hash
    ) THEN
      RETURN QUERY SELECT staging_row.id, staging_row.status;
      RETURN;
    END IF;
    IF staging_row.benefit_decisions @>
      '[{"reason":"superseded_by_newer_crawl"}]'::jsonb THEN
      RAISE EXCEPTION 'superseded_staging';
    END IF;
    RAISE EXCEPTION 'already_reviewed';
  END IF;
  IF staging_row.card_id IS NULL
     OR staging_row.parser_version NOT IN ('benefits-v5', 'benefits-v6')
     OR NOT public.is_valid_official_source_evidence(staging_row.source_evidence)
     OR jsonb_typeof(staging_row.extracted_data) <> 'object'
     OR staging_row.extracted_data->>'request_type' <> 'official_benefit_enrichment'
     OR staging_row.extracted_data->>'parser_version' <> staging_row.parser_version
     OR jsonb_typeof(staging_row.extracted_data->'proposals') <> 'array'
     OR EXISTS (
       SELECT 1 FROM jsonb_array_elements(staging_row.extracted_data->'proposals') AS proposal(value)
       WHERE jsonb_typeof(proposal.value) <> 'object'
     ) THEN
    RAISE EXCEPTION 'invalid_staged_authority';
  END IF;

  -- Validate every identity and duplicate before the first live mutation.
  FOR decision IN SELECT item.value FROM jsonb_array_elements(_decisions) AS item(value)
  LOOP
    IF jsonb_typeof(decision) <> 'object' THEN RAISE EXCEPTION 'invalid_benefit_decision'; END IF;
    decision_action := lower(trim(coalesce(decision->>'action', '')));
    IF decision_action NOT IN ('approve', 'edit', 'reject', 'keep_existing', 'retire') THEN
      RAISE EXCEPTION 'invalid_benefit_decision';
    END IF;
    IF decision_action IN ('approve', 'edit') THEN
      IF (decision->>'proposal_index') !~ '^[0-9]+$' THEN
        RAISE EXCEPTION 'unknown_benefit_proposal';
      END IF;
      decision_proposal_index := (decision->>'proposal_index')::integer;
      staged_proposal := staging_row.extracted_data->'proposals'->decision_proposal_index;
      IF staged_proposal IS NULL THEN RAISE EXCEPTION 'unknown_benefit_proposal'; END IF;
      canonical_envelope := public.validate_benefit_publication_envelope(
        decision->'canonical_envelope', staging_row.card_id, staged_proposal
      );
      decision_identity := 'proposal:' || decision_proposal_index::text;
    ELSIF decision_action IN ('retire', 'keep_existing') THEN
      BEGIN
        existing_benefit_id := nullif(coalesce(
          decision->>'benefit_id', decision->>'current_benefit_id'
        ), '')::uuid;
      EXCEPTION WHEN invalid_text_representation THEN
        RAISE EXCEPTION 'invalid_existing_benefit_id';
      END;
      IF existing_benefit_id IS NULL THEN RAISE EXCEPTION 'invalid_existing_benefit_id'; END IF;
      IF decision_action = 'retire' THEN
        PERFORM public.validate_locked_retirement_evidence(
          staging_row.extracted_data, existing_benefit_id
        );
      ELSIF NOT EXISTS (
        SELECT 1 FROM (
          SELECT item.value->'current' AS benefit
          FROM jsonb_array_elements(coalesce(staging_row.extracted_data->'diff'->'modifications', '[]'::jsonb)) AS item(value)
          UNION ALL
          SELECT item.value->'current'
          FROM jsonb_array_elements(coalesce(staging_row.extracted_data->'diff'->'unchanged', '[]'::jsonb)) AS item(value)
          UNION ALL
          SELECT item.value->'benefit'
          FROM jsonb_array_elements(coalesce(staging_row.extracted_data->'diff'->'possibleRemovals', '[]'::jsonb)) AS item(value)
        ) AS current_benefits
        WHERE current_benefits.benefit->>'liveBenefitId' = existing_benefit_id::text
      ) THEN RAISE EXCEPTION 'existing_mapping_not_found';
      END IF;
      decision_identity := 'live:' || existing_benefit_id::text;
    ELSIF decision_action = 'reject' THEN
      IF (decision->>'proposal_index') ~ '^[0-9]+$' THEN
        decision_proposal_index := (decision->>'proposal_index')::integer;
        staged_proposal := staging_row.extracted_data->'proposals'->decision_proposal_index;
        IF staged_proposal IS NULL THEN RAISE EXCEPTION 'unknown_benefit_proposal'; END IF;
        decision_identity := 'proposal:' || decision_proposal_index::text;
      ELSIF nullif(coalesce(
        decision->>'benefit_id', decision->>'current_benefit_id'
      ), '') IS NOT NULL THEN
        BEGIN
          existing_benefit_id := coalesce(
            decision->>'benefit_id', decision->>'current_benefit_id'
          )::uuid;
        EXCEPTION WHEN invalid_text_representation THEN
          RAISE EXCEPTION 'invalid_existing_benefit_id';
        END;
        IF NOT EXISTS (
          SELECT 1 FROM (
            SELECT item.value->'current' AS benefit
            FROM jsonb_array_elements(coalesce(staging_row.extracted_data->'diff'->'modifications', '[]'::jsonb)) AS item(value)
            UNION ALL
            SELECT item.value->'current'
            FROM jsonb_array_elements(coalesce(staging_row.extracted_data->'diff'->'unchanged', '[]'::jsonb)) AS item(value)
            UNION ALL
            SELECT item.value->'benefit'
            FROM jsonb_array_elements(coalesce(staging_row.extracted_data->'diff'->'possibleRemovals', '[]'::jsonb)) AS item(value)
          ) AS current_benefits
          WHERE current_benefits.benefit->>'liveBenefitId' = existing_benefit_id::text
        ) THEN RAISE EXCEPTION 'existing_mapping_not_found';
        END IF;
        decision_identity := 'live:' || existing_benefit_id::text;
      ELSE
        decision_identity := 'reject:all';
      END IF;
    END IF;
    IF decision_identity = ANY(seen_decision_identities) THEN
      RAISE EXCEPTION 'duplicate_benefit_decision';
    END IF;
    seen_decision_identities := array_append(seen_decision_identities, decision_identity);
  END LOOP;

  FOR decision IN SELECT item.value FROM jsonb_array_elements(_decisions) AS item(value)
  LOOP
    decision_action := lower(trim(decision->>'action'));
    IF decision_action IN ('approve', 'edit') THEN
      decision_proposal_index := (decision->>'proposal_index')::integer;
      staged_proposal := staging_row.extracted_data->'proposals'->decision_proposal_index;
      canonical_envelope := public.validate_benefit_publication_envelope(
        decision->'canonical_envelope', staging_row.card_id, staged_proposal
      );
      canonical_benefit := canonical_envelope->'benefit';
      INSERT INTO public.benefits (
        title, description, benefit_category, benefit_type, value_config,
        partners, exclusions, regions, source_url, dedupe_key,
        valid_from, valid_until, is_active
      ) VALUES (
        canonical_benefit->>'title', canonical_benefit->>'description',
        canonical_envelope->>'database_category_code',
        canonical_benefit->>'benefit_type', canonical_benefit->'value_config',
        canonical_benefit->'partners', canonical_benefit->'exclusions',
        canonical_benefit->'regions',
        CASE WHEN staging_row.source_url ~ '^https://[A-Za-z0-9.-]+(:[0-9]+)?(/[^@?#]*)?$'
          THEN staging_row.source_url ELSE NULL END,
        canonical_envelope->>'dedupe_key',
        nullif(canonical_benefit->>'valid_from', '')::date,
        nullif(canonical_benefit->>'valid_until', '')::date,
        true
      ) ON CONFLICT (dedupe_key) DO NOTHING
      RETURNING benefit_id INTO resolved_benefit_id;
      IF resolved_benefit_id IS NULL THEN
        SELECT benefit.benefit_id INTO resolved_benefit_id
        FROM public.benefits AS benefit
        WHERE benefit.dedupe_key = canonical_envelope->>'dedupe_key'
          AND benefit.title = canonical_benefit->>'title'
          AND benefit.description IS NOT DISTINCT FROM canonical_benefit->>'description'
          AND benefit.benefit_category = canonical_envelope->>'database_category_code'
          AND benefit.benefit_type IS NOT DISTINCT FROM canonical_benefit->>'benefit_type'
          AND benefit.value_config = canonical_benefit->'value_config'
          AND benefit.partners = canonical_benefit->'partners'
          AND benefit.exclusions = canonical_benefit->'exclusions'
          AND benefit.regions = canonical_benefit->'regions'
          AND benefit.valid_from IS NOT DISTINCT FROM nullif(canonical_benefit->>'valid_from', '')::date
          AND benefit.valid_until IS NOT DISTINCT FROM nullif(canonical_benefit->>'valid_until', '')::date;
        IF resolved_benefit_id IS NULL THEN RAISE EXCEPTION 'canonical_benefit_collision'; END IF;
      END IF;

      SELECT nullif(modification.value->'current'->>'liveBenefitId', '')::uuid
      INTO staged_existing_benefit_id
      FROM jsonb_array_elements(coalesce(
        staging_row.extracted_data->'diff'->'modifications', '[]'::jsonb
      )) AS modification(value)
      WHERE public.canonical_json_text(modification.value->'proposed') =
        public.canonical_json_text(staged_proposal)
      LIMIT 1;
      IF staging_row.parser_version = 'benefits-v5'
         AND staged_existing_benefit_id IS NOT NULL
         AND lower(coalesce(decision->>'change_type', '')) <> 'identity_migration' THEN
        RAISE EXCEPTION 'identity_migration_must_be_explicit';
      END IF;
      INSERT INTO public.card_benefit_mapping (
        card_id, benefit_id, display_priority, is_primary, category_codes, retired_at
      ) VALUES (
        staging_row.card_id, resolved_benefit_id,
        coalesce((decision->>'display_priority')::integer, 1),
        coalesce((decision->>'is_primary')::boolean, true),
        ARRAY[canonical_envelope->>'database_category_code'], NULL
      ) ON CONFLICT (card_id, benefit_id) DO UPDATE
      SET display_priority = EXCLUDED.display_priority,
          is_primary = EXCLUDED.is_primary,
          category_codes = EXCLUDED.category_codes,
          retired_at = NULL;
      IF staged_existing_benefit_id IS NOT NULL
         AND staged_existing_benefit_id <> resolved_benefit_id THEN
        retirement_at := CASE
          WHEN nullif(canonical_benefit->>'valid_from', '')::date >
            (statement_timestamp() AT TIME ZONE 'UTC')::date
          THEN nullif(canonical_benefit->>'valid_from', '')::date::timestamp
            AT TIME ZONE 'UTC'
          ELSE statement_timestamp() END;
        UPDATE public.card_benefit_mapping
        SET retired_at = retirement_at
        WHERE card_id = staging_row.card_id
          AND benefit_id = staged_existing_benefit_id;
        GET DIAGNOSTICS affected_rows = ROW_COUNT;
        IF affected_rows <> 1 THEN RAISE EXCEPTION 'existing_mapping_not_found'; END IF;
      END IF;
      approved_count := approved_count + 1;
      audit_decision := jsonb_build_object(
        'action', decision_action,
        'proposal_index', decision_proposal_index,
        'change_type', decision->>'change_type',
        'benefit_id', resolved_benefit_id,
        'dedupe_key', canonical_envelope->>'dedupe_key',
        'condition_hash', canonical_envelope->>'condition_hash'
      );
    ELSIF decision_action = 'retire' THEN
      existing_benefit_id := (decision->>'benefit_id')::uuid;
      retirement_candidate := public.validate_locked_retirement_evidence(
        staging_row.extracted_data, existing_benefit_id
      );
      UPDATE public.card_benefit_mapping
      SET retired_at = statement_timestamp()
      WHERE card_id = staging_row.card_id
        AND benefit_id = existing_benefit_id;
      GET DIAGNOSTICS affected_rows = ROW_COUNT;
      IF affected_rows <> 1 THEN RAISE EXCEPTION 'existing_mapping_not_found'; END IF;
      retired_count := retired_count + 1;
      audit_decision := jsonb_build_object(
        'action', decision_action,
        'benefit_id', existing_benefit_id,
        'retirement_reason', retirement_candidate->>'verified_retirement_reason'
      );
    ELSIF decision_action = 'keep_existing' THEN
      retained_count := retained_count + 1;
      audit_decision := jsonb_build_object(
        'action', decision_action,
        'benefit_id', (decision->>'benefit_id')::uuid
      );
    ELSE
      rejected_count := rejected_count + 1;
      audit_decision := jsonb_build_object(
        'action', decision_action,
        'reason', nullif(trim(decision->>'reason'), '')
      );
    END IF;
    audit_decision := jsonb_strip_nulls(audit_decision || jsonb_build_object(
      'reviewed_by', _reviewed_by,
      'reviewed_at', statement_timestamp(),
      'review_payload_hash', review_payload_hash,
      'parser_version', staging_row.parser_version,
      'source_evidence', staging_row.source_evidence
    ));
    audit_decisions := audit_decisions || jsonb_build_array(audit_decision);
  END LOOP;

  final_status := CASE
    WHEN approved_count + retained_count + retired_count > 0 THEN 'approved'
    ELSE 'rejected' END;
  UPDATE public.card_benefits_staging
  SET benefit_decisions = CASE
        WHEN jsonb_typeof(benefit_decisions) = 'array' THEN benefit_decisions
        ELSE jsonb_build_array(jsonb_build_object(
          'action', 'legacy_malformed_decisions', 'value', benefit_decisions
        ))
      END || audit_decisions,
      status = final_status,
      reviewed_by = _reviewed_by,
      reviewed_at = statement_timestamp(),
      updated_at = statement_timestamp()
  WHERE id = staging_row.id;

  -- Staging reuse is intentional: complete all matching same-card/parser staged
  -- jobs together, but never touch another card, parser, or status.
  UPDATE public.card_catalog_enrichment_jobs AS job
  SET status = 'completed',
      next_run_at = statement_timestamp() + interval '30 days',
      lease_token = NULL,
      lease_expires_at = NULL,
      next_retry_at = NULL,
      updated_at = statement_timestamp(),
      result_summary = coalesce(result_summary, '{}'::jsonb) || jsonb_build_object(
        'reviewed_at', statement_timestamp(),
        'review_status', final_status,
        'approved_count', approved_count,
        'retired_count', retired_count,
        'rejected_count', rejected_count,
        'retained_count', retained_count
      )
  WHERE job.staging_id = staging_row.id
    AND job.card_id = staging_row.card_id
    AND job.parser_version = staging_row.parser_version
    AND job.status = 'staged';
  GET DIAGNOSTICS linked_job_count = ROW_COUNT;
  IF linked_job_count < 1 THEN RAISE EXCEPTION 'linked_staged_job_not_found'; END IF;

  RETURN QUERY SELECT staging_row.id, final_status;
END;
$$;

DO $retirement_v2_assertions$
DECLARE
  live_id uuid := '11111111-1111-4111-8111-111111111111'::uuid;
  exact_eligible jsonb := '{
    "crawl_observation": {
      "crawl_complete": true,
      "observed_at": "2026-08-19T00:00:00.000Z",
      "absent_benefit_ids": ["card-benefit-v2:card-a:cashback"],
      "absent_legacy_benefit_ids": []
    },
    "diff": {"possibleRemovals": [{
      "benefit": {
        "liveBenefitId": "11111111-1111-4111-8111-111111111111",
        "benefitId": "card-benefit-v2:card-a:cashback",
        "dedupeKey": "legacy:cashback"
      },
      "retirementEligible": true,
      "retirementReason": "two_complete_observations",
      "completeAbsenceObservedAt": [
        "2026-08-12T00:00:00.000Z", "2026-08-19T00:00:00.000Z"
      ]
    }]}
  }'::jsonb;
  invalid_fixture jsonb;
  explicit_past_end_date_assertion jsonb;
  assertion_failed boolean;
BEGIN
  PERFORM public.validate_locked_retirement_evidence(exact_eligible, live_id);
  explicit_past_end_date_assertion := jsonb_set(
    jsonb_set(
      jsonb_set(
        exact_eligible,
        '{diff,possibleRemovals,0,benefit,effectiveTo}',
        '"2026-08-18"'::jsonb
      ),
      '{diff,possibleRemovals,0,retirementReason}',
      '"explicit_past_end_date"'::jsonb
    ),
    '{diff,possibleRemovals,0,completeAbsenceObservedAt}',
    '["2026-08-19T00:00:00.000Z"]'::jsonb
  );
  PERFORM public.validate_locked_retirement_evidence(
    explicit_past_end_date_assertion, live_id
  );
  FOR invalid_fixture IN SELECT value FROM jsonb_array_elements(jsonb_build_array(
    jsonb_set(exact_eligible, '{crawl_observation,crawl_complete}', 'false'::jsonb),
    jsonb_set(exact_eligible, '{crawl_observation,absent_benefit_ids}', '["absent_mismatch"]'::jsonb),
    jsonb_set(exact_eligible, '{diff,possibleRemovals,0,completeAbsenceObservedAt}', '["2026-08-19T00:00:00.000Z"]'::jsonb),
    jsonb_set(exact_eligible, '{diff,possibleRemovals,0,completeAbsenceObservedAt}', '["2026-08-13T00:00:00.000Z","2026-08-19T00:00:00.000Z"]'::jsonb),
    jsonb_set(exact_eligible, '{diff,possibleRemovals,0,completeAbsenceObservedAt}', '["2026-08-11T00:00:00.000Z","2026-08-18T00:00:00.000Z"]'::jsonb),
    jsonb_set(exact_eligible, '{diff,possibleRemovals,0,retirementReason}', '"eligibility_reason_mismatch"'::jsonb)
  )) LOOP
    assertion_failed := false;
    BEGIN
      PERFORM public.validate_locked_retirement_evidence(invalid_fixture, live_id);
      assertion_failed := true;
    EXCEPTION WHEN raise_exception THEN
      NULL;
    END;
    IF assertion_failed THEN
      RAISE EXCEPTION 'retirement assertion failed: incomplete, absent_mismatch, one_observation, less_than_seven_days, current_observation_missing, or eligibility_reason_mismatch';
    END IF;
  END LOOP;
END;
$retirement_v2_assertions$;

DO $publication_envelope_v2_assertions$
DECLARE
  card_a uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid;
  card_b uuid := 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'::uuid;
  staged_proposal jsonb := '{"category":"rewards","title":"Five reward points"}'::jsonb;
  condition_value jsonb := '{
    "benefit_type":"reward_points",
    "category":"points",
    "exclusions":{
      "additional":{"source_terms":[]},
      "categories":[],"days":[],"mcc_codes":[],"merchants":[],
      "transaction_types":[]
    },
    "partners":[],"regions":["in"],"restrictions":["retail spends"],
    "semantic_key":"rewards:reward_points:general",
    "value_config":{"rate":5}
  }'::jsonb;
  benefit_value jsonb;
  envelope_value jsonb;
  validated_value jsonb;
  staged_hash text;
  condition_hash text;
  card_a_key text;
  card_b_key text;
  cross_card_rejected boolean := false;
BEGIN
  staged_hash := encode(
    extensions.digest(
      convert_to(public.canonical_json_text(staged_proposal), 'UTF8'), 'sha256'
    ), 'hex'
  );
  condition_hash := public.canonical_benefit_condition_hash(condition_value);
  card_a_key := public.card_scoped_benefit_key(card_a, condition_value);
  card_b_key := public.card_scoped_benefit_key(card_b, condition_value);
  benefit_value := jsonb_build_object(
    'title', 'Five reward points',
    'description', NULL,
    'benefit_category', 'points',
    'benefit_type', 'reward_points',
    'value_config', (condition_value->'value_config') || jsonb_build_object(
      'offer_subject', 'rewards:reward_points:general',
      'restrictions', condition_value->'restrictions',
      'exclusions', condition_value->'exclusions'
    ),
    'partners', condition_value->'partners',
    'exclusions', condition_value->'exclusions',
    'regions', condition_value->'regions',
    'valid_from', NULL,
    'valid_until', NULL
  );
  envelope_value := jsonb_build_object(
    'version', 'benefit-publication-v2',
    'staged_proposal_binding', staged_proposal,
    'staged_proposal_hash', staged_hash,
    'condition', condition_value,
    'condition_hash', condition_hash,
    'dedupe_key', card_a_key,
    'benefit', benefit_value
  );
  validated_value := public.validate_benefit_publication_envelope(
    envelope_value, card_a, staged_proposal
  );
  BEGIN
    PERFORM public.validate_benefit_publication_envelope(
      envelope_value, card_b, staged_proposal
    );
  EXCEPTION WHEN raise_exception THEN
    cross_card_rejected := true;
  END;
  IF validated_value->>'dedupe_key' <> card_a_key
     OR validated_value->>'condition_hash' <> condition_hash
     OR validated_value->>'database_category_code' <> 'POINTS'
     OR card_a_key = card_b_key
     OR NOT cross_card_rejected THEN
    RAISE EXCEPTION 'canonical envelope assertion failed';
  END IF;
END;
$publication_envelope_v2_assertions$;

REVOKE ALL ON FUNCTION public.canonical_json_text(jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.canonical_benefit_condition_hash(jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.card_scoped_benefit_key(uuid, jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.validate_benefit_publication_envelope(jsonb, uuid, jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.validate_locked_retirement_evidence(jsonb, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.approve_card_benefit_enrichment(uuid, uuid, jsonb) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.canonical_json_text(jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.canonical_benefit_condition_hash(jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.card_scoped_benefit_key(uuid, jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.validate_benefit_publication_envelope(jsonb, uuid, jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.validate_locked_retirement_evidence(jsonb, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.approve_card_benefit_enrichment(uuid, uuid, jsonb) TO service_role;

DO $review_v2_acl_assertions$
DECLARE
  approval_oid regprocedure :=
    'public.approve_card_benefit_enrichment(uuid,uuid,jsonb)'::regprocedure;
  envelope_oid regprocedure :=
    'public.validate_benefit_publication_envelope(jsonb,uuid,jsonb)'::regprocedure;
  protected_oid regprocedure;
  approval_definition text;
  envelope_definition text;
BEGIN
  FOREACH protected_oid IN ARRAY ARRAY[
    'public.canonical_json_text(jsonb)'::regprocedure,
    'public.canonical_benefit_condition_hash(jsonb)'::regprocedure,
    'public.card_scoped_benefit_key(uuid,jsonb)'::regprocedure,
    'public.validate_benefit_publication_envelope(jsonb,uuid,jsonb)'::regprocedure,
    'public.validate_locked_retirement_evidence(jsonb,uuid)'::regprocedure,
    'public.approve_card_benefit_enrichment(uuid,uuid,jsonb)'::regprocedure
  ] LOOP
    IF NOT has_function_privilege('service_role', protected_oid, 'EXECUTE')
       OR has_function_privilege('anon', protected_oid, 'EXECUTE')
       OR has_function_privilege('authenticated', protected_oid, 'EXECUTE') THEN
      RAISE EXCEPTION 'v2 publication grant assertion failed: %', protected_oid;
    END IF;
  END LOOP;
  SELECT pg_get_functiondef(approval_oid) INTO approval_definition;
  SELECT pg_get_functiondef(envelope_oid) INTO envelope_definition;
  IF approval_definition ~* 'auth\.role\s*\('
     OR approval_definition !~* 'FOR UPDATE'
     OR approval_definition !~* 'validate_benefit_publication_envelope\([\s\S]*staging_row\.card_id'
     OR approval_definition !~* 'ON CONFLICT \(dedupe_key\) DO NOTHING'
     OR approval_definition ~* 'UPDATE public\.benefits'
     OR envelope_definition !~* 'card_scoped_benefit_key\(_card_id' THEN
    RAISE EXCEPTION 'v2 approval invariant assertion failed';
  END IF;
END;
$review_v2_acl_assertions$;

COMMIT;
