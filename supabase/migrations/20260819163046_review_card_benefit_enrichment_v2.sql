BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

CREATE OR REPLACE FUNCTION public.canonical_benefit_json(_value jsonb)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  result jsonb;
BEGIN
  CASE jsonb_typeof(_value)
    WHEN 'object' THEN
      SELECT coalesce(jsonb_object_agg(item.normalized_key, item.value), '{}'::jsonb)
      INTO result
      FROM (
        SELECT DISTINCT ON (normalized_key)
          lower(trim(regexp_replace(regexp_replace(entry.key, '([a-z])([A-Z])', '\1_\2', 'g'), '[\s-]+', '_', 'g'))) AS normalized_key,
          public.canonical_benefit_json(entry.value) AS value
        FROM jsonb_each(_value) AS entry
        ORDER BY normalized_key,
          CASE WHEN entry.key = lower(entry.key) AND entry.key !~ '[ -]' THEN 0 ELSE 1 END,
          entry.key
      ) AS item;
      RETURN result;
    WHEN 'array' THEN
      SELECT coalesce(jsonb_agg(public.canonical_benefit_json(item.value) ORDER BY item.ordinality), '[]'::jsonb)
      INTO result
      FROM jsonb_array_elements(_value) WITH ORDINALITY AS item(value, ordinality);
      RETURN result;
    WHEN 'string' THEN
      RETURN to_jsonb(lower(trim(regexp_replace(_value #>> '{}', '\s+', ' ', 'g'))));
    ELSE
      RETURN _value;
  END CASE;
END;
$$;

CREATE OR REPLACE FUNCTION public.canonical_benefit_text_array(
  _value jsonb,
  _field text
) RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  result jsonb;
BEGIN
  IF _value IS NULL OR _value = 'null'::jsonb THEN
    RETURN '[]'::jsonb;
  END IF;
  IF jsonb_typeof(_value) = 'string' THEN
    _value := jsonb_build_array(_value);
  ELSIF jsonb_typeof(_value) <> 'array' THEN
    RAISE EXCEPTION 'invalid_benefit_%', _field;
  END IF;
  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(_value) AS item(value)
    WHERE jsonb_typeof(item.value) <> 'string'
  ) THEN
    RAISE EXCEPTION 'invalid_benefit_%', _field;
  END IF;
  SELECT coalesce(jsonb_agg(value ORDER BY value), '[]'::jsonb)
  INTO result
  FROM (
    SELECT DISTINCT lower(trim(regexp_replace(item.value #>> '{}', '\s+', ' ', 'g'))) AS value
    FROM jsonb_array_elements(_value) AS item(value)
    WHERE length(trim(item.value #>> '{}')) > 0
  ) AS normalized;
  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.canonical_benefit_exclusions(_value jsonb)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  source_terms jsonb := '[]'::jsonb;
BEGIN
  IF _value IS NULL OR _value = 'null'::jsonb THEN
    _value := '{}'::jsonb;
  END IF;
  IF jsonb_typeof(_value) IN ('array', 'string') THEN
    source_terms := public.canonical_benefit_text_array(_value, 'exclusions');
    _value := '{}'::jsonb;
  ELSIF jsonb_typeof(_value) <> 'object' THEN
    RAISE EXCEPTION 'invalid_benefit_exclusions';
  ELSE
    IF _value ? 'additional' AND jsonb_typeof(_value->'additional') <> 'object' THEN
      RAISE EXCEPTION 'invalid_benefit_exclusions';
    END IF;
    source_terms := public.canonical_benefit_text_array(
      coalesce(_value->'source_terms', _value->'additional'->'source_terms'),
      'exclusions'
    );
  END IF;
  RETURN jsonb_build_object(
    'additional', jsonb_build_object('source_terms', source_terms),
    'categories', public.canonical_benefit_text_array(_value->'categories', 'exclusions'),
    'days', public.canonical_benefit_text_array(_value->'days', 'exclusions'),
    'mcc_codes', public.canonical_benefit_text_array(coalesce(_value->'mcc_codes', _value->'mccCodes'), 'exclusions'),
    'merchants', public.canonical_benefit_text_array(_value->'merchants', 'exclusions'),
    'transaction_types', public.canonical_benefit_text_array(coalesce(_value->'transaction_types', _value->'transactionTypes'), 'exclusions')
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.canonical_card_benefit_terms(_proposal jsonb)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  category_code text;
  benefit_type text;
  semantic_key text;
  title_value text;
  description_value text;
  raw_value_config jsonb;
  value_config jsonb;
  exclusions_value jsonb;
  restrictions_value jsonb;
  partners_value jsonb;
  regions_value jsonb;
  date_from date;
  date_until date;
  numeric_field text;
  numeric_json jsonb;
BEGIN
  IF _proposal IS NULL OR jsonb_typeof(_proposal) <> 'object' THEN
    RAISE EXCEPTION 'invalid_benefit_proposal';
  END IF;
  title_value := trim(coalesce(_proposal->>'title', ''));
  description_value := nullif(trim(coalesce(_proposal->>'description', '')), '');
  IF length(title_value) < 2 OR length(title_value) > 500 THEN
    RAISE EXCEPTION 'invalid_benefit_title';
  END IF;

  SELECT category.category_code INTO category_code
  FROM public.benefit_categories AS category
  WHERE category.is_active = true
    AND (
      lower(category.category_code) = lower(trim(coalesce(_proposal->>'category', _proposal->>'benefit_category', '')))
      OR lower(category.name) = lower(trim(coalesce(_proposal->>'category', _proposal->>'benefit_category', '')))
    )
  ORDER BY CASE WHEN lower(category.category_code) = lower(trim(coalesce(_proposal->>'category', _proposal->>'benefit_category', ''))) THEN 0 ELSE 1 END,
    category.category_code
  LIMIT 1;
  IF category_code IS NULL THEN
    RAISE EXCEPTION 'inactive_or_unknown_benefit_category';
  END IF;

  benefit_type := nullif(lower(trim(coalesce(_proposal->>'valueType', _proposal->>'benefit_type', ''))), '');
  semantic_key := nullif(lower(trim(coalesce(_proposal->>'offerSubject', _proposal->>'offer_subject', ''))), '');
  IF semantic_key IS NULL THEN
    semantic_key := lower(category_code || ':' || coalesce(benefit_type, 'benefit'));
  END IF;

  raw_value_config := coalesce(_proposal->'valueConfig', _proposal->'value_config', '{}'::jsonb);
  IF jsonb_typeof(raw_value_config) <> 'object' THEN
    RAISE EXCEPTION 'invalid_benefit_value_config';
  END IF;
  value_config := public.canonical_benefit_json(raw_value_config - 'offer_subject' - 'restrictions' - 'exclusions');
  FOREACH numeric_field IN ARRAY ARRAY['value', 'rate', 'cap', 'threshold']
  LOOP
    IF _proposal ? numeric_field AND _proposal->numeric_field <> 'null'::jsonb THEN
      numeric_json := _proposal->numeric_field;
      IF jsonb_typeof(numeric_json) <> 'number' THEN
        RAISE EXCEPTION 'invalid_benefit_number';
      END IF;
      value_config := value_config || jsonb_build_object(numeric_field, numeric_json);
    END IF;
  END LOOP;
  FOREACH numeric_field IN ARRAY ARRAY['frequency', 'period']
  LOOP
    IF _proposal ? numeric_field AND _proposal->>numeric_field IS NOT NULL THEN
      IF jsonb_typeof(_proposal->numeric_field) <> 'string' THEN
        RAISE EXCEPTION 'invalid_benefit_value_config';
      END IF;
      value_config := value_config || jsonb_build_object(
        numeric_field,
        lower(trim(regexp_replace(_proposal->>numeric_field, '\s+', ' ', 'g')))
      );
    END IF;
  END LOOP;
  value_config := public.canonical_benefit_json(value_config);

  exclusions_value := public.canonical_benefit_exclusions(
    coalesce(_proposal->'exclusions', raw_value_config->'exclusions')
  );
  restrictions_value := public.canonical_benefit_text_array(
    coalesce(_proposal->'restrictions', raw_value_config->'restrictions'),
    'restrictions'
  );
  partners_value := public.canonical_benefit_text_array(_proposal->'partners', 'partners');
  regions_value := public.canonical_benefit_text_array(_proposal->'regions', 'regions');

  BEGIN
    IF nullif(coalesce(_proposal->>'effectiveFrom', _proposal->>'valid_from'), '') IS NOT NULL THEN
      IF coalesce(_proposal->>'effectiveFrom', _proposal->>'valid_from') !~ '^\d{4}-\d{2}-\d{2}$' THEN
        RAISE EXCEPTION 'invalid_benefit_date';
      END IF;
      date_from := coalesce(_proposal->>'effectiveFrom', _proposal->>'valid_from')::date;
    END IF;
    IF nullif(coalesce(_proposal->>'effectiveTo', _proposal->>'valid_until'), '') IS NOT NULL THEN
      IF coalesce(_proposal->>'effectiveTo', _proposal->>'valid_until') !~ '^\d{4}-\d{2}-\d{2}$' THEN
        RAISE EXCEPTION 'invalid_benefit_date';
      END IF;
      date_until := coalesce(_proposal->>'effectiveTo', _proposal->>'valid_until')::date;
    END IF;
  EXCEPTION WHEN datetime_field_overflow OR invalid_datetime_format THEN
    RAISE EXCEPTION 'invalid_benefit_date';
  END;
  IF date_from IS NOT NULL AND date_until IS NOT NULL AND date_from > date_until THEN
    RAISE EXCEPTION 'invalid_benefit_date_range';
  END IF;

  RETURN jsonb_strip_nulls(jsonb_build_object(
    'title', title_value,
    'description', description_value,
    'category', lower(category_code),
    'benefit_type', benefit_type,
    'semantic_key', semantic_key,
    'value_config', value_config,
    'exclusions', exclusions_value,
    'restrictions', restrictions_value,
    'partners', partners_value,
    'regions', regions_value,
    'valid_from', date_from,
    'valid_until', date_until
  ));
END;
$$;

CREATE OR REPLACE FUNCTION public.canonical_benefit_condition(_terms jsonb)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
  SELECT jsonb_strip_nulls(jsonb_build_object(
    'benefit_type', _terms->'benefit_type',
    'category', _terms->'category',
    'exclusions', _terms->'exclusions',
    'partners', _terms->'partners',
    'regions', _terms->'regions',
    'restrictions', _terms->'restrictions',
    'semantic_key', _terms->'semantic_key',
    'valid_from', _terms->'valid_from',
    'valid_until', _terms->'valid_until',
    'value_config', _terms->'value_config'
  ));
$$;

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
      SELECT '{' || coalesce(string_agg(to_jsonb(item.key)::text || ':' || public.canonical_json_text(item.value), ',' ORDER BY item.key), '') || '}'
      INTO result FROM jsonb_each(_value) AS item(key, value);
      RETURN result;
    WHEN 'array' THEN
      SELECT '[' || coalesce(string_agg(public.canonical_json_text(item.value), ',' ORDER BY item.ordinality), '') || ']'
      INTO result FROM jsonb_array_elements(_value) WITH ORDINALITY AS item(value, ordinality);
      RETURN result;
    ELSE
      RETURN _value::text;
  END CASE;
END;
$$;

CREATE OR REPLACE FUNCTION public.canonical_benefit_condition_hash(_terms jsonb)
RETURNS text
LANGUAGE sql
IMMUTABLE
SECURITY INVOKER
SET search_path = public, extensions, pg_temp
AS $$
  SELECT encode(
    extensions.digest(
      convert_to('[' || public.canonical_json_text(public.canonical_benefit_condition(_terms)) || ']', 'UTF8'),
      'sha256'
    ),
    'hex'
  );
$$;

CREATE OR REPLACE FUNCTION public.card_scoped_benefit_key(
  _card_id uuid,
  _terms jsonb
) RETURNS text
LANGUAGE sql
IMMUTABLE
SECURITY INVOKER
SET search_path = public, extensions, pg_temp
AS $$
  SELECT 'card-benefit-v2:' || lower(_card_id::text) || ':' ||
    public.canonical_benefit_condition_hash(_terms);
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
  staged_terms jsonb;
  canonical_proposals jsonb := '[]'::jsonb;
  canonical_terms jsonb;
  canonical_condition_hash text;
  canonical_key text;
  staged_condition_hash text;
  staged_key text;
  submitted_key text;
  proposal_index integer;
  proposal_count integer;
  decision jsonb;
  decision_action text;
  decision_proposal_index integer;
  submitted_proposal jsonb;
  edit_overlay jsonb;
  existing_benefit_id uuid;
  staged_existing_benefit_id uuid;
  resolved_benefit_id uuid;
  canonical_valid_from date;
  retirement_at timestamptz;
  affected_rows integer;
  approved_count integer := 0;
  retained_count integer := 0;
  retired_count integer := 0;
  rejected_count integer := 0;
  final_status text;
  review_payload_hash text;
  audit_decisions jsonb := '[]'::jsonb;
  audit_decision jsonb;
  seen_proposal_indexes integer[] := ARRAY[]::integer[];
  retirement_candidate jsonb;
BEGIN
  IF _staging_id IS NULL OR _reviewed_by IS NULL OR _decisions IS NULL
     OR jsonb_typeof(_decisions) <> 'array' OR jsonb_array_length(_decisions) = 0 THEN
    RAISE EXCEPTION 'invalid_benefit_approval';
  END IF;
  review_payload_hash := encode(
    extensions.digest(convert_to(public.canonical_json_text(_decisions), 'UTF8'), 'sha256'),
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
    IF staging_row.benefit_decisions @> '[{"reason":"superseded_by_newer_crawl"}]'::jsonb THEN
      RAISE EXCEPTION 'superseded_staging';
    END IF;
    RAISE EXCEPTION 'already_reviewed';
  END IF;

  IF staging_row.parser_version NOT IN ('benefits-v5', 'benefits-v6') THEN
    RAISE EXCEPTION 'unsupported_benefit_parser_version';
  END IF;
  IF staging_row.card_id IS NULL
     OR NOT public.is_valid_official_source_evidence(staging_row.source_evidence) THEN
    RAISE EXCEPTION 'invalid_staged_authority';
  END IF;
  IF staging_row.extracted_data IS NULL OR jsonb_typeof(staging_row.extracted_data) <> 'object'
     OR staging_row.extracted_data->>'request_type' <> 'official_benefit_enrichment'
     OR staging_row.extracted_data->>'parser_version' <> staging_row.parser_version
     OR jsonb_typeof(staging_row.extracted_data->'proposals') <> 'array' THEN
    RAISE EXCEPTION 'invalid_staged_proposal_set';
  END IF;
  proposal_count := jsonb_array_length(staging_row.extracted_data->'proposals');
  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(staging_row.extracted_data->'proposals') AS proposal(value)
    WHERE jsonb_typeof(proposal.value) <> 'object'
  ) THEN RAISE EXCEPTION 'invalid_staged_proposal_set'; END IF;

  FOR staged_proposal, proposal_index IN
    SELECT proposal.value, (proposal.ordinality - 1)::integer
    FROM jsonb_array_elements(staging_row.extracted_data->'proposals')
      WITH ORDINALITY AS proposal(value, ordinality)
  LOOP
    canonical_terms := public.canonical_card_benefit_terms(staged_proposal);
    canonical_condition_hash := public.canonical_benefit_condition_hash(canonical_terms);
    canonical_key := public.card_scoped_benefit_key(staging_row.card_id, canonical_terms);
    staged_condition_hash := lower(coalesce(staged_proposal->>'conditionHash', staged_proposal->>'condition_hash', ''));
    staged_key := coalesce(staged_proposal->>'benefitId', staged_proposal->>'dedupeKey', staged_proposal->>'dedupe_key');
    IF staging_row.parser_version = 'benefits-v6' AND (
      staged_condition_hash <> canonical_condition_hash
      OR staged_key <> canonical_key
      OR coalesce(staged_proposal->>'dedupeKey', staged_proposal->>'dedupe_key') <> canonical_key
    ) THEN RAISE EXCEPTION 'staged_identity_mismatch'; END IF;
    canonical_proposals := canonical_proposals || jsonb_build_array(jsonb_build_object(
      'proposal_index', proposal_index,
      'staged_key', staged_key,
      'terms', canonical_terms,
      'condition_hash', canonical_condition_hash,
      'canonical_key', canonical_key
    ));
  END LOOP;
  IF (SELECT count(DISTINCT item.value->>'canonical_key') FROM jsonb_array_elements(canonical_proposals) AS item(value)) <> proposal_count THEN
    RAISE EXCEPTION 'duplicate_staged_proposal';
  END IF;

  FOR decision IN SELECT item.value FROM jsonb_array_elements(_decisions) AS item(value)
  LOOP
    IF jsonb_typeof(decision) <> 'object' THEN RAISE EXCEPTION 'invalid_benefit_decision'; END IF;
    decision_action := lower(trim(coalesce(decision->>'action', '')));
    IF decision_action NOT IN ('approve', 'edit', 'reject', 'keep_existing', 'retire') THEN
      RAISE EXCEPTION 'invalid_benefit_decision';
    END IF;
    decision_proposal_index := CASE WHEN (decision->>'proposal_index') ~ '^[0-9]+$'
      THEN (decision->>'proposal_index')::integer ELSE NULL END;

    IF decision_action IN ('approve', 'edit') THEN
      submitted_proposal := CASE WHEN decision_action = 'edit'
        THEN coalesce(decision->'edited_benefit', decision->'editedBenefit', decision->'benefit')
        ELSE coalesce(decision->'benefit', decision->'proposed') END;
      IF jsonb_typeof(submitted_proposal) <> 'object' THEN RAISE EXCEPTION 'invalid_benefit_decision'; END IF;
      IF decision_proposal_index IS NULL AND staging_row.parser_version = 'benefits-v5' THEN
        SELECT (proposal.ordinality - 1)::integer INTO decision_proposal_index
        FROM jsonb_array_elements(staging_row.extracted_data->'proposals') WITH ORDINALITY AS proposal(value, ordinality)
        WHERE coalesce(proposal.value->>'dedupeKey', proposal.value->>'dedupe_key') =
          coalesce(submitted_proposal->>'dedupeKey', submitted_proposal->>'dedupe_key')
        LIMIT 1;
      END IF;
      IF decision_proposal_index IS NULL OR decision_proposal_index < 0 OR decision_proposal_index >= proposal_count THEN
        RAISE EXCEPTION 'unknown_benefit_proposal';
      END IF;
      IF decision_proposal_index = ANY(seen_proposal_indexes) THEN RAISE EXCEPTION 'duplicate_benefit_decision'; END IF;
      seen_proposal_indexes := array_append(seen_proposal_indexes, decision_proposal_index);
      SELECT item.value->'terms' INTO staged_terms
      FROM jsonb_array_elements(canonical_proposals) AS item(value)
      WHERE (item.value->>'proposal_index')::integer = decision_proposal_index;
      SELECT item.value->>'staged_key' INTO staged_key
      FROM jsonb_array_elements(canonical_proposals) AS item(value)
      WHERE (item.value->>'proposal_index')::integer = decision_proposal_index;
      submitted_key := coalesce(
        submitted_proposal->>'benefitId', submitted_proposal->>'dedupeKey',
        submitted_proposal->>'dedupe_key'
      );
      IF submitted_key IS NULL OR submitted_key <> staged_key THEN
        RAISE EXCEPTION 'benefit_decision_identity_mismatch';
      END IF;
      FOREACH staged_key IN ARRAY ARRAY[
        'benefitId', 'dedupeKey', 'conditionHash', 'offerSubject',
        'restrictions', 'exclusions', 'partners', 'regions', 'sourceIdentity',
        'sourceIdentities', 'valueConfig'
      ] LOOP
        IF submitted_proposal ? staged_key
           AND submitted_proposal->staged_key IS DISTINCT FROM
             staging_row.extracted_data->'proposals'->decision_proposal_index->staged_key THEN
          RAISE EXCEPTION 'benefit_decision_identity_mismatch';
        END IF;
      END LOOP;
      SELECT item.value->>'staged_key' INTO staged_key
      FROM jsonb_array_elements(canonical_proposals) AS item(value)
      WHERE (item.value->>'proposal_index')::integer = decision_proposal_index;

      IF decision_action = 'edit' THEN
        edit_overlay := '{}'::jsonb;
        FOREACH staged_key IN ARRAY ARRAY[
          'title', 'description', 'category', 'valueType', 'value', 'rate', 'cap',
          'threshold', 'frequency', 'period', 'effectiveFrom', 'effectiveTo'
        ] LOOP
          IF submitted_proposal ? staged_key THEN
            edit_overlay := edit_overlay || jsonb_build_object(staged_key, submitted_proposal->staged_key);
          END IF;
        END LOOP;
        staged_proposal := (staging_row.extracted_data->'proposals'->decision_proposal_index) || edit_overlay;
        canonical_terms := public.canonical_card_benefit_terms(staged_proposal);
      ELSE
        canonical_terms := staged_terms;
      END IF;
      canonical_condition_hash := public.canonical_benefit_condition_hash(canonical_terms);
      canonical_key := public.card_scoped_benefit_key(staging_row.card_id, canonical_terms);
      canonical_valid_from := nullif(canonical_terms->>'valid_from', '')::date;

      INSERT INTO public.benefits (
        title, description, benefit_category, benefit_type, value_config,
        partners, exclusions, regions, source_url, dedupe_key,
        valid_from, valid_until, is_active
      ) VALUES (
        canonical_terms->>'title', canonical_terms->>'description', canonical_terms->>'category',
        canonical_terms->>'benefit_type',
        (canonical_terms->'value_config') || jsonb_build_object(
          'offer_subject', canonical_terms->>'semantic_key',
          'restrictions', canonical_terms->'restrictions',
          'exclusions', canonical_terms->'exclusions'
        ),
        canonical_terms->'partners', canonical_terms->'exclusions', canonical_terms->'regions',
        CASE WHEN staging_row.source_url ~ '^https://[A-Za-z0-9.-]+(:[0-9]+)?(/[^@?#]*)?$'
          THEN staging_row.source_url ELSE NULL END,
        canonical_key, canonical_valid_from,
        nullif(canonical_terms->>'valid_until', '')::date, true
      ) ON CONFLICT (dedupe_key) DO NOTHING
      RETURNING benefit_id INTO resolved_benefit_id;
      IF resolved_benefit_id IS NULL THEN
        SELECT benefit.benefit_id INTO resolved_benefit_id
        FROM public.benefits AS benefit
        WHERE benefit.dedupe_key = canonical_key
          AND benefit.benefit_category = canonical_terms->>'category'
          AND benefit.value_config = (canonical_terms->'value_config') || jsonb_build_object(
            'offer_subject', canonical_terms->>'semantic_key',
            'restrictions', canonical_terms->'restrictions',
            'exclusions', canonical_terms->'exclusions'
          );
        IF resolved_benefit_id IS NULL THEN RAISE EXCEPTION 'canonical_benefit_collision'; END IF;
      END IF;

      INSERT INTO public.card_benefit_mapping (
        card_id, benefit_id, display_priority, is_primary, category_codes, retired_at
      ) VALUES (
        staging_row.card_id, resolved_benefit_id,
        coalesce((decision->>'display_priority')::integer, 1),
        coalesce((decision->>'is_primary')::boolean, true),
        ARRAY[canonical_terms->>'category'], NULL
      ) ON CONFLICT (card_id, benefit_id) DO UPDATE
      SET display_priority = EXCLUDED.display_priority,
          is_primary = EXCLUDED.is_primary,
          category_codes = EXCLUDED.category_codes,
          retired_at = NULL;

      BEGIN
        existing_benefit_id := nullif(coalesce(
          decision->>'existing_benefit_id', decision->>'current_benefit_id',
          decision->'current'->>'liveBenefitId', submitted_proposal->>'liveBenefitId'
        ), '')::uuid;
      EXCEPTION WHEN invalid_text_representation THEN
        RAISE EXCEPTION 'invalid_existing_benefit_id';
      END;
      BEGIN
        SELECT nullif(modification.value->'current'->>'liveBenefitId', '')::uuid
        INTO staged_existing_benefit_id
        FROM jsonb_array_elements(coalesce(staging_row.extracted_data->'diff'->'modifications', '[]'::jsonb)) AS modification(value)
        WHERE coalesce(
          modification.value->'proposed'->>'benefitId',
          modification.value->'proposed'->>'dedupeKey',
          modification.value->'proposed'->>'dedupe_key'
        ) IN (staged_key, canonical_key)
        LIMIT 1;
      EXCEPTION WHEN invalid_text_representation THEN
        RAISE EXCEPTION 'invalid_staged_existing_benefit_id';
      END;
      IF existing_benefit_id IS DISTINCT FROM staged_existing_benefit_id
         AND existing_benefit_id IS NOT NULL THEN
        RAISE EXCEPTION 'existing_benefit_identity_mismatch';
      END IF;
      existing_benefit_id := staged_existing_benefit_id;
      IF staging_row.parser_version = 'benefits-v5'
         AND existing_benefit_id IS NOT NULL
         AND lower(coalesce(decision->>'change_type', decision->>'changeType', '')) <> 'identity_migration' THEN
        RAISE EXCEPTION 'identity_migration_must_be_explicit';
      END IF;
      IF existing_benefit_id IS NOT NULL AND existing_benefit_id <> resolved_benefit_id THEN
        retirement_at := CASE WHEN canonical_valid_from IS NOT NULL
            AND canonical_valid_from > (statement_timestamp() AT TIME ZONE 'UTC')::date
          THEN canonical_valid_from::timestamp AT TIME ZONE 'UTC' ELSE statement_timestamp() END;
        UPDATE public.card_benefit_mapping
        SET retired_at = retirement_at
        WHERE card_id = staging_row.card_id
          AND benefit_id = existing_benefit_id;
        GET DIAGNOSTICS affected_rows = ROW_COUNT;
        IF affected_rows <> 1 THEN RAISE EXCEPTION 'existing_mapping_not_found'; END IF;
      END IF;
      approved_count := approved_count + 1;
      audit_decision := jsonb_build_object(
        'action', decision_action, 'proposal_index', decision_proposal_index,
        'change_type', coalesce(decision->>'change_type', decision->>'changeType'),
        'benefit_id', resolved_benefit_id, 'dedupe_key', canonical_key,
        'condition_hash', canonical_condition_hash
      );
    ELSIF decision_action = 'retire' THEN
      BEGIN
        existing_benefit_id := nullif(coalesce(
          decision->>'benefit_id', decision->>'current_benefit_id',
          decision->'benefit'->>'liveBenefitId'
        ), '')::uuid;
      EXCEPTION WHEN invalid_text_representation THEN
        RAISE EXCEPTION 'invalid_existing_benefit_id';
      END;
      SELECT removal.value INTO retirement_candidate
      FROM jsonb_array_elements(coalesce(staging_row.extracted_data->'diff'->'possibleRemovals', '[]'::jsonb)) AS removal(value)
      WHERE coalesce(removal.value->'benefit'->>'liveBenefitId', removal.value->>'benefit_id') = existing_benefit_id::text
      LIMIT 1;
      IF retirement_candidate IS NULL
         OR coalesce((coalesce(retirement_candidate->>'retirementEligible', retirement_candidate->>'retirement_eligible'))::boolean, false) <> true
         OR length(trim(coalesce(retirement_candidate->>'retirementReason', retirement_candidate->>'retirement_reason', ''))) < 3 THEN
        RAISE EXCEPTION 'retirement_not_eligible';
      END IF;
      UPDATE public.card_benefit_mapping
      SET retired_at = statement_timestamp()
      WHERE card_id = staging_row.card_id
        AND benefit_id = existing_benefit_id;
      GET DIAGNOSTICS affected_rows = ROW_COUNT;
      IF affected_rows <> 1 THEN RAISE EXCEPTION 'existing_mapping_not_found'; END IF;
      retired_count := retired_count + 1;
      audit_decision := jsonb_build_object(
        'action', decision_action, 'benefit_id', existing_benefit_id,
        'retirement_reason', coalesce(retirement_candidate->>'retirementReason', retirement_candidate->>'retirement_reason')
      );
    ELSIF decision_action = 'keep_existing' THEN
      BEGIN
        existing_benefit_id := nullif(coalesce(
          decision->>'benefit_id', decision->>'current_benefit_id',
          decision->'benefit'->>'liveBenefitId'
        ), '')::uuid;
      EXCEPTION WHEN invalid_text_representation THEN
        RAISE EXCEPTION 'invalid_existing_benefit_id';
      END;
      IF existing_benefit_id IS NULL OR NOT EXISTS (
        SELECT 1
        FROM (
          SELECT candidate.value->'current' AS benefit
          FROM jsonb_array_elements(coalesce(staging_row.extracted_data->'diff'->'modifications', '[]'::jsonb)) AS candidate(value)
          UNION ALL
          SELECT candidate.value->'current'
          FROM jsonb_array_elements(coalesce(staging_row.extracted_data->'diff'->'unchanged', '[]'::jsonb)) AS candidate(value)
          UNION ALL
          SELECT candidate.value->'benefit'
          FROM jsonb_array_elements(coalesce(staging_row.extracted_data->'diff'->'possibleRemovals', '[]'::jsonb)) AS candidate(value)
        ) AS staged_current
        WHERE staged_current.benefit->>'liveBenefitId' = existing_benefit_id::text
      ) THEN RAISE EXCEPTION 'existing_mapping_not_found'; END IF;
      retained_count := retained_count + 1;
      audit_decision := jsonb_build_object('action', decision_action, 'benefit_id', existing_benefit_id);
    ELSE
      rejected_count := rejected_count + 1;
      audit_decision := jsonb_build_object('action', decision_action, 'reason', nullif(trim(decision->>'reason'), ''));
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

  final_status := CASE WHEN approved_count + retained_count + retired_count > 0 THEN 'approved' ELSE 'rejected' END;
  UPDATE public.card_benefits_staging
  SET benefit_decisions = CASE
        WHEN jsonb_typeof(benefit_decisions) = 'array' THEN benefit_decisions
        ELSE jsonb_build_array(jsonb_build_object('action', 'legacy_malformed_decisions', 'value', benefit_decisions))
      END || audit_decisions,
      status = final_status,
      reviewed_by = _reviewed_by,
      reviewed_at = statement_timestamp(),
      updated_at = statement_timestamp()
  WHERE id = staging_row.id;

  UPDATE public.card_catalog_enrichment_jobs AS job
  SET status = 'completed',
      next_run_at = statement_timestamp() + interval '30 days',
      lease_token = NULL,
      lease_expires_at = NULL,
      next_retry_at = NULL,
      updated_at = statement_timestamp(),
      result_summary = coalesce(result_summary, '{}'::jsonb) || jsonb_build_object(
        'reviewed_at', statement_timestamp(), 'review_status', final_status,
        'approved_count', approved_count, 'retired_count', retired_count,
        'rejected_count', rejected_count, 'retained_count', retained_count
      )
  WHERE job.staging_id = staging_row.id;

  RETURN QUERY SELECT staging_row.id, final_status;
END;
$$;

DO $review_v2_assertions$
DECLARE
  function_security boolean;
  function_config text[];
BEGIN
  SELECT prosecdef, proconfig INTO function_security, function_config
  FROM pg_proc WHERE oid = 'public.approve_card_benefit_enrichment(uuid,uuid,jsonb)'::regprocedure;
  IF function_security OR NOT (function_config @> ARRAY['search_path=public, extensions, pg_temp']) THEN
    RAISE EXCEPTION 'v2 approval security assertion failed';
  END IF;
END;
$review_v2_assertions$;

REVOKE ALL ON FUNCTION public.canonical_benefit_json(jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.canonical_benefit_text_array(jsonb, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.canonical_benefit_exclusions(jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.canonical_card_benefit_terms(jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.canonical_benefit_condition(jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.canonical_json_text(jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.canonical_benefit_condition_hash(jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.card_scoped_benefit_key(uuid, jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.approve_card_benefit_enrichment(uuid, uuid, jsonb) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.canonical_benefit_json(jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.canonical_benefit_text_array(jsonb, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.canonical_benefit_exclusions(jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.canonical_card_benefit_terms(jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.canonical_benefit_condition(jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.canonical_json_text(jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.canonical_benefit_condition_hash(jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.card_scoped_benefit_key(uuid, jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.approve_card_benefit_enrichment(uuid, uuid, jsonb) TO service_role;

DO $review_v2_acl_assertions$
DECLARE
  approval_oid regprocedure := 'public.approve_card_benefit_enrichment(uuid,uuid,jsonb)'::regprocedure;
  approval_definition text;
BEGIN
  IF NOT has_function_privilege('service_role', approval_oid, 'EXECUTE')
     OR has_function_privilege('anon', approval_oid, 'EXECUTE')
     OR has_function_privilege('authenticated', approval_oid, 'EXECUTE') THEN
    RAISE EXCEPTION 'v2 approval grant assertion failed';
  END IF;
  SELECT pg_get_functiondef(approval_oid) INTO approval_definition;
  IF approval_definition ~* 'auth\.role\s*\('
     OR approval_definition !~* 'FOR UPDATE'
     OR approval_definition !~* 'card_scoped_benefit_key\(staging_row\.card_id'
     OR approval_definition !~* 'ON CONFLICT \(dedupe_key\) DO NOTHING'
     OR approval_definition ~* 'UPDATE public\.benefits' THEN
    RAISE EXCEPTION 'v2 approval invariant assertion failed';
  END IF;
END;
$review_v2_acl_assertions$;

COMMIT;
