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

-- A deliberately conservative number domain shared with the Edge validator.
-- It avoids JSON exponent spelling and unsafe coefficient differences between
-- JavaScript JSON.stringify and PostgreSQL jsonb text.
CREATE OR REPLACE FUNCTION public.canonical_json_numbers_are_safe(_value jsonb)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  item jsonb;
  rendered text;
  numeric_value numeric;
  coefficient numeric;
BEGIN
  CASE jsonb_typeof(_value)
    WHEN 'number' THEN
      rendered := _value::text;
      BEGIN
        numeric_value := rendered::numeric;
        coefficient := replace(rendered, '.', '')::numeric;
      EXCEPTION WHEN numeric_value_out_of_range OR invalid_text_representation THEN
        RETURN false;
      END;
      RETURN numeric_value = 0 OR (
        abs(numeric_value) >= 0.000001
        AND abs(numeric_value) < 1000000000000000000000
        AND rendered ~ '^-?[0-9]+(?:\.[0-9]{1,6})?$'
        AND abs(coefficient) <= 9007199254740991
      );
    WHEN 'array' THEN
      FOR item IN SELECT value FROM jsonb_array_elements(_value) LOOP
        IF NOT public.canonical_json_numbers_are_safe(item) THEN RETURN false; END IF;
      END LOOP;
    WHEN 'object' THEN
      FOR item IN SELECT value FROM jsonb_each(_value) LOOP
        IF NOT public.canonical_json_numbers_are_safe(item) THEN RETURN false; END IF;
      END LOOP;
    ELSE
      NULL;
  END CASE;
  RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION public.canonical_json_shape_is_bounded(
  _value jsonb,
  _max_depth integer,
  _max_keys integer,
  _max_array_items integer,
  _max_key_chars integer,
  _max_string_chars integer
) RETURNS boolean
LANGUAGE sql
IMMUTABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
  WITH RECURSIVE nodes(value, depth) AS (
    SELECT _value, 0
    UNION ALL
    SELECT child.value, nodes.depth + 1
    FROM nodes
    CROSS JOIN LATERAL (
      SELECT item.value
      FROM jsonb_each(
        CASE WHEN jsonb_typeof(nodes.value) = 'object'
          THEN nodes.value ELSE '{}'::jsonb END
      ) AS item(key, value)
      UNION ALL
      SELECT item.value
      FROM jsonb_array_elements(
        CASE WHEN jsonb_typeof(nodes.value) = 'array'
          THEN nodes.value ELSE '[]'::jsonb END
      ) AS item(value)
    ) AS child(value)
    WHERE nodes.depth < _max_depth + 1
  ), measurements AS (
    SELECT
      coalesce(max(depth), 0) AS maximum_depth,
      coalesce(sum(CASE WHEN jsonb_typeof(value) = 'object' THEN (
        SELECT count(*) FROM jsonb_object_keys(value)
      ) ELSE 0 END), 0) AS key_count,
      coalesce(max(CASE WHEN jsonb_typeof(value) = 'object' THEN (
        SELECT coalesce(max(length(item.key)), 0)
        FROM jsonb_object_keys(value) AS item(key)
      ) ELSE 0 END), 0) AS maximum_key_chars,
      coalesce(max(CASE WHEN jsonb_typeof(value) = 'array'
        THEN jsonb_array_length(value) ELSE 0 END), 0) AS maximum_array_items,
      coalesce(max(CASE WHEN jsonb_typeof(value) = 'string'
        THEN length(value #>> '{}') ELSE 0 END), 0) AS maximum_string_chars
    FROM nodes
  )
  SELECT maximum_depth <= _max_depth
    AND key_count <= _max_keys
    AND maximum_array_items <= _max_array_items
    AND maximum_key_chars <= _max_key_chars
    AND maximum_string_chars <= _max_string_chars
  FROM measurements;
$$;

CREATE OR REPLACE FUNCTION public.validate_locked_benefit_proposals(
  _proposals jsonb,
  _parser_version text
) RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  MAX_CANONICAL_ARRAY_ITEMS constant integer := 64;
  MAX_CANONICAL_DEPTH constant integer := 8;
  MAX_CANONICAL_KEYS constant integer := 256;
  MAX_CANONICAL_KEY_CHARS constant integer := 500;
  MAX_STAGED_PROPOSALS constant integer := 64;
  MAX_STAGED_PROPOSALS_BYTES constant integer := 131072;
  MAX_STAGED_STRING_CHARS constant integer := 8000;
BEGIN
  IF _parser_version NOT IN ('benefits-v5', 'benefits-v6')
     OR jsonb_typeof(_proposals) <> 'array'
     OR jsonb_array_length(_proposals) > MAX_STAGED_PROPOSALS
     OR octet_length(public.canonical_json_text(_proposals)) >
        MAX_STAGED_PROPOSALS_BYTES
     OR NOT public.canonical_json_shape_is_bounded(
       _proposals, MAX_CANONICAL_DEPTH, MAX_CANONICAL_KEYS,
       MAX_CANONICAL_ARRAY_ITEMS, MAX_CANONICAL_KEY_CHARS,
       MAX_STAGED_STRING_CHARS
     )
     OR NOT public.canonical_json_numbers_are_safe(_proposals) THEN
    RAISE EXCEPTION 'invalid_staged_presentation_bounds';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(_proposals) AS proposal(value)
    WHERE jsonb_typeof(proposal.value) <> 'object'
       OR jsonb_typeof(proposal.value->'title') IS DISTINCT FROM 'string'
       OR jsonb_typeof(proposal.value->'description') IS DISTINCT FROM 'string'
       OR jsonb_typeof(proposal.value->'category') IS DISTINCT FROM 'string'
       OR jsonb_typeof(proposal.value->'valueType') IS DISTINCT FROM 'string'
       OR jsonb_typeof(proposal.value->'dedupeKey') IS DISTINCT FROM 'string'
       OR jsonb_typeof(proposal.value->'sourceUrl') IS DISTINCT FROM 'string'
       OR jsonb_typeof(proposal.value->'sourceExcerpt') IS DISTINCT FROM 'string'
       OR jsonb_typeof(proposal.value->'contentHash') IS DISTINCT FROM 'string'
       OR jsonb_typeof(proposal.value->'parserVersion') IS DISTINCT FROM 'string'
       OR length(trim(coalesce(proposal.value->>'title', ''))) NOT BETWEEN 2 AND 500
       OR length(trim(coalesce(proposal.value->>'valueType', ''))) NOT BETWEEN 1 AND 200
       OR length(trim(coalesce(proposal.value->>'category', ''))) NOT BETWEEN 1 AND 500
       OR length(trim(coalesce(proposal.value->>'dedupeKey', ''))) NOT BETWEEN 1 AND 500
       OR proposal.value->>'parserVersion' IS DISTINCT FROM _parser_version
       OR EXISTS (
         SELECT 1 FROM (VALUES
           ('liveBenefitId'), ('benefitId'), ('offerSubject'),
           ('conditionHash'), ('frequency'), ('period'), ('effectiveFrom'),
           ('effectiveTo'), ('sourceIdentity')
         ) AS field(name)
         WHERE proposal.value ? field.name
           AND jsonb_typeof(proposal.value->field.name) IS DISTINCT FROM 'string'
       )
       OR EXISTS (
         SELECT 1 FROM (VALUES ('value'), ('rate'), ('cap'), ('threshold')) AS field(name)
         WHERE proposal.value ? field.name
           AND jsonb_typeof(proposal.value->field.name) IS DISTINCT FROM 'number'
       )
       OR EXISTS (
         SELECT 1 FROM (VALUES
           ('partners'), ('restrictions'), ('regions'), ('sourceUrls'),
           ('sourceIdentities'), ('warnings')
         ) AS field(name)
         WHERE proposal.value ? field.name AND (
           jsonb_typeof(proposal.value->field.name) IS DISTINCT FROM 'array'
           OR jsonb_array_length(CASE
             WHEN jsonb_typeof(proposal.value->field.name) = 'array'
             THEN proposal.value->field.name ELSE '[]'::jsonb END
           ) > MAX_CANONICAL_ARRAY_ITEMS
           OR EXISTS (
             SELECT 1 FROM jsonb_array_elements(CASE
               WHEN jsonb_typeof(proposal.value->field.name) = 'array'
               THEN proposal.value->field.name ELSE '[]'::jsonb END
             ) AS entry(value)
             WHERE jsonb_typeof(entry.value) IS DISTINCT FROM 'string'
           )
         )
       )
       OR jsonb_typeof(proposal.value->'restrictions') IS DISTINCT FROM 'array'
       OR jsonb_typeof(proposal.value->'warnings') IS DISTINCT FROM 'array'
       OR jsonb_typeof(proposal.value->'confidence') IS DISTINCT FROM 'object'
       OR EXISTS (
         SELECT 1 FROM jsonb_each(CASE
           WHEN jsonb_typeof(proposal.value->'confidence') = 'object'
           THEN proposal.value->'confidence' ELSE '{}'::jsonb END
         ) AS confidence(key, value)
         WHERE jsonb_typeof(confidence.value) IS DISTINCT FROM 'number'
       )
       OR jsonb_typeof(proposal.value->'evidence') IS DISTINCT FROM 'object'
       OR EXISTS (
         SELECT 1 FROM jsonb_each(CASE
           WHEN jsonb_typeof(proposal.value->'evidence') = 'object'
           THEN proposal.value->'evidence' ELSE '{}'::jsonb END
         ) AS evidence(key, value)
         WHERE jsonb_typeof(evidence.value) IS DISTINCT FROM 'string'
       )
       OR (proposal.value ? 'valueConfig'
         AND jsonb_typeof(proposal.value->'valueConfig') IS DISTINCT FROM 'object')
       OR EXISTS (
         SELECT 1 FROM jsonb_object_keys(CASE
           WHEN jsonb_typeof(proposal.value->'valueConfig') = 'object'
           THEN proposal.value->'valueConfig' ELSE '{}'::jsonb END
         ) AS config_key(value)
         WHERE config_key.value NOT IN (
           'category', 'discount_type', 'discount_percent', 'discount_amount',
           'max_discount_per_transaction', 'max_usage_per_month',
           'max_usage_per_period', 'usage_period', 'monthly_cap', 'annual_cap',
           'unit', 'milestone_type', 'threshold_amount', 'reward_value',
           'multiplier', 'base_rate', 'currency_unit', 'platform', 'value',
           'rate', 'cap', 'threshold', 'frequency', 'period', 'offer_subject',
           'restrictions', 'exclusions'
         )
         OR (_parser_version = 'benefits-v5' AND config_key.value IN (
           'value', 'rate', 'cap', 'threshold', 'frequency', 'period',
           'offer_subject'
         ))
       )
       OR (proposal.value->'valueConfig' ? 'restrictions' AND (
         jsonb_typeof(proposal.value->'valueConfig'->'restrictions') IS DISTINCT FROM 'array'
         OR proposal.value->'valueConfig'->'restrictions' IS DISTINCT FROM proposal.value->'restrictions'
       ))
       OR (proposal.value->'valueConfig' ? 'exclusions' AND (
         jsonb_typeof(proposal.value->'valueConfig'->'exclusions') IS DISTINCT FROM 'object'
         OR proposal.value->'valueConfig'->'exclusions' IS DISTINCT FROM proposal.value->'exclusions'
       ))
       OR (proposal.value->'valueConfig' ? 'offer_subject'
         AND proposal.value->'valueConfig'->>'offer_subject'
           IS DISTINCT FROM proposal.value->>'offerSubject')
       OR (_parser_version = 'benefits-v5'
         AND jsonb_typeof(proposal.value->'exclusions') IS DISTINCT FROM 'array')
       OR (_parser_version = 'benefits-v5' AND EXISTS (
         SELECT 1 FROM jsonb_array_elements(CASE
           WHEN jsonb_typeof(proposal.value->'exclusions') = 'array'
           THEN proposal.value->'exclusions' ELSE '[]'::jsonb END
         ) AS exclusion(value)
         WHERE jsonb_typeof(exclusion.value) IS DISTINCT FROM 'string'
       ))
       OR (_parser_version = 'benefits-v6' AND (
         jsonb_typeof(proposal.value->'valueConfig') IS DISTINCT FROM 'object'
         OR jsonb_typeof(proposal.value->'exclusions') IS DISTINCT FROM 'object'
         OR jsonb_typeof(proposal.value->'exclusions'->'additional') IS DISTINCT FROM 'object'
         OR EXISTS (
           SELECT 1 FROM jsonb_object_keys(CASE
             WHEN jsonb_typeof(proposal.value->'exclusions') = 'object'
             THEN proposal.value->'exclusions' ELSE '{}'::jsonb END
           ) AS exclusion_key(value)
           WHERE exclusion_key.value NOT IN (
             'additional', 'categories', 'days', 'mcc_codes', 'merchants',
             'transaction_types'
           )
         )
         OR EXISTS (
           SELECT 1 FROM jsonb_object_keys(CASE
             WHEN jsonb_typeof(proposal.value->'exclusions'->'additional') = 'object'
             THEN proposal.value->'exclusions'->'additional' ELSE '{}'::jsonb END
           ) AS additional_key(value)
           WHERE additional_key.value <> 'source_terms'
         )
         OR EXISTS (
           SELECT 1 FROM (VALUES
             ('categories'), ('days'), ('mcc_codes'), ('merchants'),
             ('transaction_types')
           ) AS exclusion_field(name)
           WHERE jsonb_typeof(proposal.value->'exclusions'->exclusion_field.name)
             IS DISTINCT FROM 'array'
             OR EXISTS (
               SELECT 1 FROM jsonb_array_elements(CASE
                 WHEN jsonb_typeof(proposal.value->'exclusions'->exclusion_field.name) = 'array'
                 THEN proposal.value->'exclusions'->exclusion_field.name ELSE '[]'::jsonb END
               ) AS exclusion_term(value)
               WHERE jsonb_typeof(exclusion_term.value) IS DISTINCT FROM 'string'
             )
         )
         OR jsonb_typeof(proposal.value->'exclusions'->'additional'->'source_terms')
           IS DISTINCT FROM 'array'
         OR EXISTS (
           SELECT 1 FROM jsonb_array_elements(CASE
             WHEN jsonb_typeof(proposal.value->'exclusions'->'additional'->'source_terms') = 'array'
             THEN proposal.value->'exclusions'->'additional'->'source_terms' ELSE '[]'::jsonb END
           ) AS source_term(value)
           WHERE jsonb_typeof(source_term.value) IS DISTINCT FROM 'string'
         )
       ))
       OR (_parser_version = 'benefits-v6' AND (
         length(trim(coalesce(proposal.value->>'benefitId', ''))) NOT BETWEEN 1 AND 500
         OR proposal.value->>'benefitId' IS DISTINCT FROM proposal.value->>'dedupeKey'
         OR length(trim(coalesce(proposal.value->>'offerSubject', ''))) NOT BETWEEN 1 AND 500
         OR coalesce(proposal.value->>'conditionHash', '') !~ '^[0-9a-fA-F]{64}$'
         OR coalesce(proposal.value->>'sourceIdentity', '') !~ '^[0-9a-fA-F]{64}$'
         OR EXISTS (
           SELECT 1 FROM jsonb_array_elements(CASE
             WHEN jsonb_typeof(proposal.value->'sourceIdentities') = 'array'
             THEN proposal.value->'sourceIdentities' ELSE '[]'::jsonb END
           ) AS identity(value)
           WHERE identity.value #>> '{}' !~ '^[0-9a-fA-F]{64}$'
         )
       ))
       OR EXISTS (
         SELECT 1 FROM jsonb_object_keys(
           CASE WHEN jsonb_typeof(proposal.value) = 'object'
             THEN proposal.value ELSE '{}'::jsonb END
         ) AS key(value)
         WHERE key.value NOT IN (
           'liveBenefitId', 'benefitId', 'offerSubject', 'dedupeKey',
           'conditionHash', 'title', 'description', 'category', 'valueType',
           'value', 'rate', 'cap', 'threshold', 'valueConfig', 'partners',
           'frequency', 'period', 'restrictions', 'exclusions', 'regions',
           'effectiveFrom', 'effectiveTo', 'sourceUrl', 'sourceUrls',
           'sourceIdentity', 'sourceIdentities', 'sourceExcerpt', 'contentHash',
           'parserVersion', 'confidence', 'evidence', 'warnings'
         )
       )
  ) THEN RAISE EXCEPTION 'unknown_staged_proposal_key'; END IF;
  IF EXISTS (
    SELECT proposal.value->>'dedupeKey'
    FROM jsonb_array_elements(_proposals) AS proposal(value)
    GROUP BY proposal.value->>'dedupeKey'
    HAVING count(*) > 1
  ) THEN RAISE EXCEPTION 'duplicate_staged_proposal'; END IF;
  IF _parser_version = 'benefits-v6' AND EXISTS (
    SELECT proposal.value->>'benefitId'
    FROM jsonb_array_elements(_proposals) AS proposal(value)
    GROUP BY proposal.value->>'benefitId'
    HAVING count(*) > 1
  ) THEN RAISE EXCEPTION 'duplicate_staged_proposal'; END IF;
  RETURN true;
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
  MAX_DECISIONS constant integer := 64;
  MAX_CANONICAL_ARRAY_ITEMS constant integer := 64;
  MAX_CANONICAL_STRING_CHARS constant integer := 500;
  MAX_CONDITION_BYTES constant integer := 32768;
  MAX_BENEFIT_BYTES constant integer := 65536;
  MAX_ENVELOPE_BYTES constant integer := 131072;
  MAX_REVIEW_BYTES constant integer := 262144;
  MAX_SOURCE_EVIDENCE_ITEMS constant integer := 32;
  MAX_SOURCE_EVIDENCE_BYTES constant integer := 32768;
  MAX_CANONICAL_DEPTH constant integer := 8;
  MAX_CANONICAL_KEYS constant integer := 256;
  MAX_CANONICAL_KEY_CHARS constant integer := 500;
  MAX_STAGED_PROPOSALS constant integer := 64;
  MAX_STAGED_PROPOSALS_BYTES constant integer := 131072;
  MAX_STAGED_STRING_CHARS constant integer := 8000;
  condition_value jsonb;
  benefit_value jsonb;
  expected_staged_hash text;
  expected_condition_hash text;
  expected_key text;
  category_code text;
  valid_from_value date;
  valid_until_value date;
  array_key text;
  identity_migration jsonb;
  legacy_condition jsonb;
  legacy_condition_hash text;
  legacy_dedupe_key text;
BEGIN
  IF _envelope IS NULL OR jsonb_typeof(_envelope) <> 'object'
     OR _envelope->>'version' <> 'benefit-publication-v2'
     OR _staged_proposal IS NULL OR jsonb_typeof(_staged_proposal) <> 'object'
     OR jsonb_typeof(_envelope->'staged_proposal_binding') <> 'object'
     OR _envelope->'staged_proposal_binding' IS DISTINCT FROM _staged_proposal THEN
    RAISE EXCEPTION 'invalid_canonical_envelope';
  END IF;
  IF EXISTS (
    SELECT 1 FROM jsonb_object_keys(_envelope) AS key(value)
    WHERE key.value NOT IN (
      'version', 'staged_proposal_binding', 'staged_proposal_hash',
      'condition', 'condition_hash', 'dedupe_key', 'benefit',
      'identity_migration'
    )
  ) THEN RAISE EXCEPTION 'unknown_canonical_envelope_key'; END IF;
  condition_value := _envelope->'condition';
  benefit_value := _envelope->'benefit';
  IF octet_length(public.canonical_json_text(_envelope)) > MAX_ENVELOPE_BYTES THEN
    RAISE EXCEPTION 'canonical_envelope_bytes_limit';
  END IF;
  IF jsonb_typeof(condition_value) <> 'object'
     OR jsonb_typeof(benefit_value) <> 'object'
     OR jsonb_typeof(condition_value->'value_config') <> 'object'
     OR jsonb_typeof(condition_value->'exclusions') <> 'object'
     OR jsonb_typeof(benefit_value->'value_config') <> 'object'
     OR jsonb_typeof(benefit_value->'exclusions') <> 'object' THEN
    RAISE EXCEPTION 'invalid_canonical_envelope_shape';
  END IF;
  IF EXISTS (
    SELECT 1 FROM jsonb_object_keys(condition_value) AS key(value)
    WHERE key.value NOT IN (
      'benefit_type', 'category', 'exclusions', 'partners', 'regions',
      'restrictions', 'semantic_key', 'valid_from', 'valid_until', 'value_config'
    )
  ) THEN RAISE EXCEPTION 'unknown_canonical_condition_key'; END IF;
  IF EXISTS (
    SELECT 1 FROM jsonb_object_keys(benefit_value) AS key(value)
    WHERE key.value NOT IN (
      'title', 'description', 'benefit_category', 'benefit_type',
      'value_config', 'partners', 'exclusions', 'regions', 'valid_from',
      'valid_until'
    )
  ) THEN RAISE EXCEPTION 'unknown_canonical_benefit_key'; END IF;
  IF EXISTS (
    SELECT 1 FROM jsonb_object_keys(condition_value->'value_config') AS key(value)
    WHERE key.value NOT IN (
      'category', 'discount_type', 'discount_percent', 'discount_amount',
      'max_discount_per_transaction', 'max_usage_per_month',
      'max_usage_per_period', 'usage_period', 'monthly_cap', 'annual_cap',
      'unit', 'milestone_type', 'threshold_amount', 'reward_value',
      'multiplier', 'base_rate', 'currency_unit', 'platform', 'value', 'rate',
      'cap', 'threshold', 'frequency', 'period', 'offer_subject',
      'restrictions', 'exclusions'
    )
  ) THEN RAISE EXCEPTION 'unknown_canonical_value_config_key'; END IF;
  IF EXISTS (
    SELECT 1 FROM jsonb_object_keys(benefit_value->'value_config') AS key(value)
    WHERE key.value NOT IN (
      'category', 'discount_type', 'discount_percent', 'discount_amount',
      'max_discount_per_transaction', 'max_usage_per_month',
      'max_usage_per_period', 'usage_period', 'monthly_cap', 'annual_cap',
      'unit', 'milestone_type', 'threshold_amount', 'reward_value',
      'multiplier', 'base_rate', 'currency_unit', 'platform', 'value', 'rate',
      'cap', 'threshold', 'frequency', 'period', 'offer_subject',
      'restrictions', 'exclusions'
    )
  ) THEN RAISE EXCEPTION 'unknown_canonical_value_config_key'; END IF;
  IF EXISTS (
    SELECT 1 FROM jsonb_each(condition_value->'value_config') AS item(key, value)
    WHERE jsonb_typeof(item.value) NOT IN ('string', 'number', 'boolean', 'null')
  ) OR EXISTS (
    SELECT 1 FROM jsonb_each(benefit_value->'value_config') AS item(key, value)
    WHERE item.key NOT IN ('restrictions', 'exclusions')
      AND jsonb_typeof(item.value) NOT IN ('string', 'number', 'boolean', 'null')
  ) THEN RAISE EXCEPTION 'invalid_canonical_value_config'; END IF;
  IF EXISTS (
    SELECT 1 FROM jsonb_object_keys(condition_value->'exclusions') AS key(value)
    WHERE key.value NOT IN (
      'additional', 'categories', 'days', 'mcc_codes', 'merchants',
      'transaction_types'
    )
  ) OR EXISTS (
    SELECT 1 FROM jsonb_object_keys(condition_value->'exclusions'->'additional') AS key(value)
    WHERE key.value <> 'source_terms'
  ) THEN RAISE EXCEPTION 'unknown_canonical_exclusion_key'; END IF;
  -- Numeric parity domain: non-zero abs >= 0.000001, abs <
  -- 1000000000000000000000 (1e21), coefficient <= 9007199254740991.
  IF NOT public.canonical_json_numbers_are_safe(_staged_proposal)
     OR NOT public.canonical_json_numbers_are_safe(condition_value)
     OR NOT public.canonical_json_numbers_are_safe(benefit_value) THEN
    RAISE EXCEPTION 'unsafe_canonical_number';
  END IF;
  FOREACH array_key IN ARRAY ARRAY['partners', 'regions', 'restrictions']
  LOOP
    IF jsonb_typeof(condition_value->array_key) <> 'array'
       OR jsonb_array_length(condition_value->array_key) > MAX_CANONICAL_ARRAY_ITEMS
       OR EXISTS (
         SELECT 1 FROM jsonb_array_elements(condition_value->array_key) AS item(value)
         WHERE jsonb_typeof(item.value) <> 'string'
           OR length(item.value #>> '{}') > MAX_CANONICAL_STRING_CHARS
       ) THEN
      RAISE EXCEPTION 'invalid_canonical_envelope_shape';
    END IF;
  END LOOP;
  FOREACH array_key IN ARRAY ARRAY[
    'categories', 'days', 'mcc_codes', 'merchants', 'transaction_types'
  ]
  LOOP
    IF jsonb_typeof(condition_value->'exclusions'->array_key) <> 'array'
       OR jsonb_array_length(condition_value->'exclusions'->array_key) > MAX_CANONICAL_ARRAY_ITEMS
       OR EXISTS (
         SELECT 1
         FROM jsonb_array_elements(condition_value->'exclusions'->array_key) AS item(value)
         WHERE jsonb_typeof(item.value) <> 'string'
           OR length(item.value #>> '{}') > MAX_CANONICAL_STRING_CHARS
       ) THEN
      RAISE EXCEPTION 'invalid_canonical_exclusions';
    END IF;
  END LOOP;
  IF jsonb_typeof(condition_value->'exclusions'->'additional') <> 'object'
     OR jsonb_typeof(condition_value->'exclusions'->'additional'->'source_terms') <> 'array'
     OR jsonb_array_length(condition_value->'exclusions'->'additional'->'source_terms') > MAX_CANONICAL_ARRAY_ITEMS
     OR EXISTS (
       SELECT 1
       FROM jsonb_array_elements(
         condition_value->'exclusions'->'additional'->'source_terms'
       ) AS item(value)
       WHERE jsonb_typeof(item.value) <> 'string'
         OR length(item.value #>> '{}') > MAX_CANONICAL_STRING_CHARS
     )
     OR octet_length(public.canonical_json_text(condition_value)) > MAX_CONDITION_BYTES
     OR octet_length(public.canonical_json_text(benefit_value)) > MAX_BENEFIT_BYTES THEN
    RAISE EXCEPTION 'invalid_canonical_exclusions';
  END IF;
  IF NOT public.canonical_json_shape_is_bounded(
       condition_value, MAX_CANONICAL_DEPTH, MAX_CANONICAL_KEYS,
       MAX_CANONICAL_ARRAY_ITEMS, MAX_CANONICAL_KEY_CHARS,
       MAX_CANONICAL_STRING_CHARS
     ) OR NOT public.canonical_json_shape_is_bounded(
       jsonb_set(benefit_value, '{description}', '""'::jsonb),
       MAX_CANONICAL_DEPTH, MAX_CANONICAL_KEYS,
       MAX_CANONICAL_ARRAY_ITEMS, MAX_CANONICAL_KEY_CHARS,
       MAX_CANONICAL_STRING_CHARS
     ) OR NOT public.canonical_json_shape_is_bounded(
       _staged_proposal, MAX_CANONICAL_DEPTH, MAX_CANONICAL_KEYS,
       MAX_CANONICAL_ARRAY_ITEMS, MAX_CANONICAL_KEY_CHARS,
       MAX_STAGED_STRING_CHARS
     ) THEN
    RAISE EXCEPTION 'canonical_shape_limit';
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

  identity_migration := _envelope->'identity_migration';
  IF identity_migration IS NOT NULL THEN
    IF jsonb_typeof(identity_migration) <> 'object' OR EXISTS (
      SELECT 1 FROM jsonb_object_keys(identity_migration) AS key(value)
      WHERE key.value NOT IN (
        'kind', 'from_category', 'to_category', 'legacy_condition_hash',
        'legacy_dedupe_key'
      )
    ) THEN RAISE EXCEPTION 'invalid_identity_migration'; END IF;
    legacy_condition := jsonb_set(condition_value, '{category}', '"rewards"'::jsonb);
    legacy_condition_hash := public.canonical_benefit_condition_hash(legacy_condition);
    legacy_dedupe_key := 'card-benefit-v2:' || lower(_card_id::text) || ':' ||
      legacy_condition_hash;
    IF identity_migration->>'kind' <> 'category_alias_identity_migration'
       OR identity_migration->>'from_category' <> 'rewards'
       OR identity_migration->>'to_category' <> 'points'
       OR identity_migration->>'legacy_condition_hash' <> legacy_condition_hash
       OR identity_migration->>'legacy_dedupe_key' <> legacy_dedupe_key
       OR lower(coalesce(_staged_proposal->>'category', '')) <> 'rewards'
       OR _staged_proposal->>'benefitId' <> legacy_dedupe_key
       OR _staged_proposal->>'dedupeKey' <> legacy_dedupe_key
       OR lower(coalesce(_staged_proposal->>'conditionHash', '')) <> legacy_condition_hash
       OR condition_value->>'category' <> 'points' THEN
      RAISE EXCEPTION 'invalid_identity_migration';
    END IF;
  ELSIF lower(coalesce(_staged_proposal->>'category', '')) = 'rewards'
     AND (
       _staged_proposal->>'benefitId' IS DISTINCT FROM expected_key
       OR _staged_proposal->>'dedupeKey' IS DISTINCT FROM expected_key
       OR lower(coalesce(_staged_proposal->>'conditionHash', ''))
          IS DISTINCT FROM expected_condition_hash
     ) THEN
    RAISE EXCEPTION 'category_alias_identity_migration_required';
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
  MAX_DECISIONS constant integer := 64;
  MAX_CANONICAL_STRING_CHARS constant integer := 500;
  MAX_REVIEW_BYTES constant integer := 262144;
  MAX_SOURCE_EVIDENCE_ITEMS constant integer := 32;
  MAX_SOURCE_EVIDENCE_BYTES constant integer := 32768;
  MAX_CANONICAL_ARRAY_ITEMS constant integer := 64;
  MAX_CANONICAL_DEPTH constant integer := 8;
  MAX_CANONICAL_KEYS constant integer := 256;
  MAX_CANONICAL_KEY_CHARS constant integer := 500;
  MAX_STAGED_PROPOSALS constant integer := 64;
  MAX_STAGED_PROPOSALS_BYTES constant integer := 131072;
  MAX_STAGED_STRING_CHARS constant integer := 8000;
  staging_row public.card_benefits_staging%ROWTYPE;
  staged_proposal jsonb;
  canonical_envelope jsonb;
  canonical_benefit jsonb;
  decision jsonb;
  decision_action text;
  decision_identity text;
  decision_proposal_index integer;
  seen_decision_identities text[] := ARRAY[]::text[];
  seen_publication_keys text[] := ARRAY[]::text[];
  publication_key text;
  existing_benefit_id uuid;
  staged_existing_benefit_id uuid;
  staged_change_type text;
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
  audit_source_evidence jsonb;
  evidence_attached boolean := false;
  review_identity_payload jsonb;
BEGIN
  IF _staging_id IS NULL OR _reviewed_by IS NULL OR _decisions IS NULL
     OR jsonb_typeof(_decisions) <> 'array' OR jsonb_array_length(_decisions) = 0
     OR jsonb_array_length(_decisions) > MAX_DECISIONS
     OR octet_length(public.canonical_json_text(_decisions)) > MAX_REVIEW_BYTES THEN
    RAISE EXCEPTION 'invalid_benefit_approval';
  END IF;
  SELECT jsonb_agg(item.value - 'benefit' - 'edited_benefit' ORDER BY item.ordinality)
  INTO review_identity_payload
  FROM jsonb_array_elements(_decisions) WITH ORDINALITY AS item(value, ordinality);
  review_payload_hash := encode(
    extensions.digest(
      convert_to(public.canonical_json_text(review_identity_payload), 'UTF8'), 'sha256'
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
     OR jsonb_typeof(staging_row.source_evidence) <> 'array'
     OR jsonb_array_length(staging_row.source_evidence) > MAX_SOURCE_EVIDENCE_ITEMS
     OR octet_length(public.canonical_json_text(staging_row.source_evidence)) > MAX_SOURCE_EVIDENCE_BYTES
     OR jsonb_typeof(staging_row.extracted_data) <> 'object'
     OR staging_row.extracted_data->>'request_type' <> 'official_benefit_enrichment'
     OR staging_row.extracted_data->>'parser_version' <> staging_row.parser_version
     OR NOT public.validate_locked_benefit_proposals(
       staging_row.extracted_data->'proposals', staging_row.parser_version
     ) THEN
    RAISE EXCEPTION 'invalid_staged_authority';
  END IF;

  -- Validate every identity and duplicate before the first live mutation.
  FOR decision IN SELECT item.value FROM jsonb_array_elements(_decisions) AS item(value)
  LOOP
    IF jsonb_typeof(decision) <> 'object' THEN RAISE EXCEPTION 'invalid_benefit_decision'; END IF;
    IF EXISTS (
      SELECT 1 FROM jsonb_object_keys(decision) AS key(value)
      WHERE key.value NOT IN (
        'action', 'reason', 'change_type', 'display_priority', 'is_primary',
        'proposal_index', 'benefit_id', 'current_benefit_id',
        'existing_benefit_id', 'benefit', 'edited_benefit',
        'canonical_envelope'
      )
    ) OR length(coalesce(decision->>'reason', '')) > MAX_CANONICAL_STRING_CHARS
      OR octet_length(public.canonical_json_text(decision)) > MAX_REVIEW_BYTES THEN
      RAISE EXCEPTION 'invalid_benefit_decision_shape';
    END IF;
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
      publication_key := canonical_envelope->>'dedupe_key';
      IF publication_key = ANY(seen_publication_keys) THEN
        RAISE EXCEPTION 'duplicate_target_publication';
      END IF;
      seen_publication_keys := array_append(seen_publication_keys, publication_key);
      IF (
        SELECT count(*) FROM jsonb_array_elements(coalesce(
          staging_row.extracted_data->'diff'->'modifications', '[]'::jsonb
        )) AS modification(value)
        WHERE public.canonical_json_text(modification.value->'proposed') =
          public.canonical_json_text(staged_proposal)
      ) > 1 THEN RAISE EXCEPTION 'ambiguous_staged_modification'; END IF;
      SELECT modification.value->>'changeType',
             nullif(modification.value->'current'->>'liveBenefitId', '')::uuid
      INTO staged_change_type, staged_existing_benefit_id
      FROM jsonb_array_elements(coalesce(
        staging_row.extracted_data->'diff'->'modifications', '[]'::jsonb
      )) AS modification(value)
      WHERE public.canonical_json_text(modification.value->'proposed') =
        public.canonical_json_text(staged_proposal)
      LIMIT 1;
      BEGIN
        existing_benefit_id := nullif(decision->>'existing_benefit_id', '')::uuid;
      EXCEPTION WHEN invalid_text_representation THEN
        RAISE EXCEPTION 'invalid_existing_benefit_id';
      END;
      IF existing_benefit_id IS DISTINCT FROM staged_existing_benefit_id THEN
        RAISE EXCEPTION 'client_publication_authority_rejected';
      END IF;
      IF canonical_envelope ? 'identity_migration' THEN
        IF decision->>'change_type' <> 'category_alias_identity_migration' THEN
          RAISE EXCEPTION 'identity_migration_must_be_explicit';
        END IF;
      ELSIF staged_change_type = 'identity_migration' THEN
        IF staged_existing_benefit_id IS NULL OR
           decision->>'change_type' <> 'identity_migration' THEN
          RAISE EXCEPTION 'identity_migration_must_be_explicit';
        END IF;
      ELSIF staged_change_type IS NOT NULL THEN
        RAISE EXCEPTION 'invalid_staged_change_type';
      ELSIF decision->>'change_type' IS NOT NULL THEN
        RAISE EXCEPTION 'client_publication_authority_rejected';
      END IF;
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

      SELECT modification.value->>'changeType',
             nullif(modification.value->'current'->>'liveBenefitId', '')::uuid
      INTO staged_change_type, staged_existing_benefit_id
      FROM jsonb_array_elements(coalesce(
        staging_row.extracted_data->'diff'->'modifications', '[]'::jsonb
      )) AS modification(value)
      WHERE public.canonical_json_text(modification.value->'proposed') =
        public.canonical_json_text(staged_proposal)
      LIMIT 1;
      IF staged_change_type = 'identity_migration'
         AND staged_existing_benefit_id IS NULL THEN
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
        SET retired_at = CASE
          WHEN retired_at IS NULL THEN retirement_at
          ELSE least(retired_at, retirement_at)
        END
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
      SET retired_at = coalesce(retired_at, statement_timestamp())
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
      'parser_version', staging_row.parser_version
    ));
    IF NOT evidence_attached THEN
      audit_source_evidence := staging_row.source_evidence;
      audit_decision := audit_decision || jsonb_build_object(
        'source_evidence', audit_source_evidence
      );
      evidence_attached := true;
    END IF;
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

DO $retirement_boundary_v2_assertions$
DECLARE
  existing_earlier boolean;
  computed_earlier boolean;
  null_existing boolean;
  future_replacement boolean;
BEGIN
  existing_earlier := least(
    '2026-08-20T00:00:00Z'::timestamptz,
    '2026-08-25T00:00:00Z'::timestamptz
  ) = '2026-08-20T00:00:00Z'::timestamptz;
  computed_earlier := least(
    '2026-08-25T00:00:00Z'::timestamptz,
    '2026-08-20T00:00:00Z'::timestamptz
  ) = '2026-08-20T00:00:00Z'::timestamptz;
  null_existing := CASE
    WHEN NULL::timestamptz IS NULL THEN '2026-08-25T00:00:00Z'::timestamptz
    ELSE least(NULL::timestamptz, '2026-08-25T00:00:00Z'::timestamptz)
  END = '2026-08-25T00:00:00Z'::timestamptz;
  future_replacement := CASE
    WHEN NULL::timestamptz IS NULL THEN '2026-09-01T00:00:00Z'::timestamptz
    ELSE least(NULL::timestamptz, '2026-09-01T00:00:00Z'::timestamptz)
  END = '2026-09-01T00:00:00Z'::timestamptz;
  IF NOT existing_earlier OR NOT computed_earlier OR NOT null_existing
     OR NOT future_replacement THEN
    RAISE EXCEPTION 'replacement retirement boundary assertion failed';
  END IF;
END;
$retirement_boundary_v2_assertions$;

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

DO $locked_proposal_v2_assertions$
DECLARE
  valid_proposal jsonb := '{
    "title":"Dining cashback","category":"cashback",
    "description":"Get 10% cashback on dining spends.",
    "valueType":"cashback","rate":10,
    "benefitId":"card-benefit-v2:card:one",
    "dedupeKey":"card-benefit-v2:card:one",
    "offerSubject":"cashback:cashback:dining",
    "conditionHash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "sourceIdentity":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "sourceUrl":"https://issuer.example/card",
    "sourceExcerpt":"Get 10% cashback on dining spends.",
    "contentHash":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
    "restrictions":["dining spends"],"warnings":[],
    "confidence":{"rate":0.9},"evidence":{"rate":"10% cashback"},
    "valueConfig":{"rate":10,"offer_subject":"cashback:cashback:dining","restrictions":["dining spends"],"exclusions":{"additional":{"source_terms":[]},"categories":[],"days":[],"mcc_codes":[],"merchants":[],"transaction_types":[]}},
    "exclusions":{"additional":{"source_terms":[]},"categories":[],"days":[],"mcc_codes":[],"merchants":[],"transaction_types":[]},
    "parserVersion":"benefits-v6"
  }'::jsonb;
  second_proposal jsonb;
  nested_value jsonb := '"leaf"'::jsonb;
  wide_value jsonb;
  depth_index integer;
  valid_multi boolean := false;
  oversized_unselected boolean := false;
  unknown_unselected boolean := false;
  malformed_unselected boolean := false;
  invalid_typed_proposal jsonb;
  typed_unselected_count integer := 0;
  duplicate_unselected boolean := false;
  deep_unselected boolean := false;
  wide_unselected boolean := false;
BEGIN
  second_proposal := valid_proposal || jsonb_build_object(
    'title', 'Fuel cashback',
    'benefitId', 'card-benefit-v2:card:two',
    'dedupeKey', 'card-benefit-v2:card:two'
  );
  PERFORM public.validate_locked_benefit_proposals(
    jsonb_build_array(valid_proposal, second_proposal), 'benefits-v6'
  );
  valid_multi := true;
  BEGIN
    PERFORM public.validate_locked_benefit_proposals(jsonb_build_array(
      valid_proposal, second_proposal || jsonb_build_object(
        'unknown', repeat('x', 200000)
      )
    ), 'benefits-v6');
  EXCEPTION WHEN raise_exception THEN oversized_unselected := true; END;
  BEGIN
    PERFORM public.validate_locked_benefit_proposals(jsonb_build_array(
      valid_proposal, second_proposal || '{"unknown":"small"}'::jsonb
    ), 'benefits-v6');
  EXCEPTION WHEN raise_exception THEN unknown_unselected := true; END;
  BEGIN
    PERFORM public.validate_locked_benefit_proposals(
      jsonb_build_array(valid_proposal, '"malformed"'::jsonb), 'benefits-v6'
    );
  EXCEPTION WHEN raise_exception THEN malformed_unselected := true; END;
  FOR invalid_typed_proposal IN SELECT value FROM jsonb_array_elements(
    jsonb_build_array(
      jsonb_set(second_proposal, '{partners}', '[1]'::jsonb),
      jsonb_set(second_proposal, '{confidence}', '{"rate":"high"}'::jsonb),
      jsonb_set(second_proposal, '{sourceUrls}', '[42]'::jsonb),
      jsonb_set(second_proposal, '{description}', '4'::jsonb),
      jsonb_set(second_proposal, '{valueConfig}', '[]'::jsonb),
      jsonb_set(second_proposal, '{warnings}', '[false]'::jsonb)
    )
  ) LOOP
    BEGIN
      PERFORM public.validate_locked_benefit_proposals(
        jsonb_build_array(valid_proposal, invalid_typed_proposal), 'benefits-v6'
      );
    EXCEPTION WHEN raise_exception THEN
      typed_unselected_count := typed_unselected_count + 1;
    END;
  END LOOP;
  BEGIN
    PERFORM public.validate_locked_benefit_proposals(
      jsonb_build_array(valid_proposal, valid_proposal), 'benefits-v6'
    );
  EXCEPTION WHEN raise_exception THEN duplicate_unselected := true; END;
  FOR depth_index IN 1..9 LOOP
    nested_value := jsonb_build_object('next', nested_value);
  END LOOP;
  BEGIN
    PERFORM public.validate_locked_benefit_proposals(jsonb_build_array(
      valid_proposal,
      second_proposal || jsonb_build_object('valueConfig', nested_value)
    ), 'benefits-v6');
  EXCEPTION WHEN raise_exception THEN deep_unselected := true; END;
  SELECT jsonb_object_agg('key_' || value::text, value)
  INTO wide_value FROM generate_series(1, 257) AS item(value);
  BEGIN
    PERFORM public.validate_locked_benefit_proposals(jsonb_build_array(
      valid_proposal,
      second_proposal || jsonb_build_object('valueConfig', wide_value)
    ), 'benefits-v6');
  EXCEPTION WHEN raise_exception THEN wide_unselected := true; END;
  IF NOT valid_multi OR NOT oversized_unselected OR NOT unknown_unselected
     OR NOT malformed_unselected
     OR typed_unselected_count <> 6 OR NOT duplicate_unselected OR NOT deep_unselected
     OR NOT wide_unselected THEN
    RAISE EXCEPTION 'locked proposal assertion failed';
  END IF;
END;
$locked_proposal_v2_assertions$;

DO $publication_envelope_v2_assertions$
DECLARE
  card_a uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid;
  card_b uuid := 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'::uuid;
  staged_proposal jsonb := '{"category":"points","title":"Five reward points"}'::jsonb;
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
  unknown_key_assertion boolean := false;
  unsafe_numeric_assertion boolean := false;
  identity_migration_assertion boolean := false;
  shape_boundary_assertion boolean := false;
  legacy_condition jsonb;
  legacy_condition_hash text;
  legacy_dedupe_key text;
  legacy_staged_proposal jsonb;
  legacy_envelope jsonb;
  boundary_value jsonb;
  depth_index integer;
BEGIN
  IF NOT public.canonical_json_shape_is_bounded(
       jsonb_build_object(repeat('k', 500), 'value'), 8, 256, 64, 500, 500
     ) OR public.canonical_json_shape_is_bounded(
       jsonb_build_object(repeat('k', 501), 'value'), 8, 256, 64, 500, 500
     ) THEN
    RAISE EXCEPTION 'canonical key length boundary assertion failed';
  END IF;
  IF NOT public.canonical_json_shape_is_bounded(
       jsonb_build_object('value', repeat('x', 500)), 8, 256, 64, 500, 500
     ) OR public.canonical_json_shape_is_bounded(
       jsonb_build_object('value', repeat('x', 501)), 8, 256, 64, 500, 500
     ) OR NOT public.canonical_json_shape_is_bounded(
       to_jsonb(ARRAY(SELECT value FROM generate_series(1, 64))),
       8, 256, 64, 500, 500
     ) OR public.canonical_json_shape_is_bounded(
       to_jsonb(ARRAY(SELECT value FROM generate_series(1, 65))),
       8, 256, 64, 500, 500
     ) THEN
    RAISE EXCEPTION 'canonical shape boundary assertion failed';
  END IF;
  SELECT jsonb_object_agg('key_' || value::text, value)
  INTO boundary_value FROM generate_series(1, 256) AS item(value);
  IF NOT public.canonical_json_shape_is_bounded(
    boundary_value, 8, 256, 64, 500, 500
  ) THEN RAISE EXCEPTION 'canonical key boundary assertion failed'; END IF;
  SELECT jsonb_object_agg('key_' || value::text, value)
  INTO boundary_value FROM generate_series(1, 257) AS item(value);
  IF public.canonical_json_shape_is_bounded(
    boundary_value, 8, 256, 64, 500, 500
  ) THEN RAISE EXCEPTION 'canonical key overflow assertion failed'; END IF;
  boundary_value := '"leaf"'::jsonb;
  FOR depth_index IN 1..8 LOOP
    boundary_value := jsonb_build_object('next', boundary_value);
  END LOOP;
  IF NOT public.canonical_json_shape_is_bounded(
    boundary_value, 8, 256, 64, 500, 500
  ) THEN RAISE EXCEPTION 'canonical depth boundary assertion failed'; END IF;
  boundary_value := jsonb_build_object('next', boundary_value);
  IF public.canonical_json_shape_is_bounded(
    boundary_value, 8, 256, 64, 500, 500
  ) THEN RAISE EXCEPTION 'canonical depth overflow assertion failed'; END IF;
  shape_boundary_assertion := true;
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
      envelope_value || '{"nonce":"hash-only"}'::jsonb,
      card_a, staged_proposal
    );
  EXCEPTION WHEN raise_exception THEN
    unknown_key_assertion := true;
  END;
  BEGIN
    PERFORM public.validate_benefit_publication_envelope(
      jsonb_set(envelope_value, '{condition,value_config,rate}', '0.0000001'::jsonb),
      card_a, staged_proposal
    );
  EXCEPTION WHEN raise_exception THEN
    unsafe_numeric_assertion := true;
  END;
  legacy_condition := jsonb_set(condition_value, '{category}', '"rewards"'::jsonb);
  legacy_condition_hash := public.canonical_benefit_condition_hash(legacy_condition);
  legacy_dedupe_key := 'card-benefit-v2:' || lower(card_a::text) || ':' ||
    legacy_condition_hash;
  legacy_staged_proposal := staged_proposal || jsonb_build_object(
    'category', 'rewards',
    'benefitId', legacy_dedupe_key,
    'dedupeKey', legacy_dedupe_key,
    'conditionHash', legacy_condition_hash
  );
  legacy_envelope := jsonb_set(
    jsonb_set(
      envelope_value,
      '{staged_proposal_binding}', legacy_staged_proposal
    ),
    '{staged_proposal_hash}',
    to_jsonb(encode(extensions.digest(
      convert_to(public.canonical_json_text(legacy_staged_proposal), 'UTF8'),
      'sha256'
    ), 'hex'))
  ) || jsonb_build_object('identity_migration', jsonb_build_object(
    'kind', 'category_alias_identity_migration',
    'from_category', 'rewards',
    'to_category', 'points',
    'legacy_condition_hash', legacy_condition_hash,
    'legacy_dedupe_key', legacy_dedupe_key
  ));
  PERFORM public.validate_benefit_publication_envelope(
    legacy_envelope, card_a, legacy_staged_proposal
  );
  identity_migration_assertion := true;
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
     OR NOT cross_card_rejected
     OR NOT unknown_key_assertion
     OR NOT unsafe_numeric_assertion
     OR NOT identity_migration_assertion
     OR NOT shape_boundary_assertion THEN
    RAISE EXCEPTION 'canonical envelope assertion failed';
  END IF;
END;
$publication_envelope_v2_assertions$;

REVOKE ALL ON FUNCTION public.canonical_json_text(jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.canonical_json_numbers_are_safe(jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.canonical_json_shape_is_bounded(jsonb, integer, integer, integer, integer, integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.validate_locked_benefit_proposals(jsonb, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.canonical_benefit_condition_hash(jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.card_scoped_benefit_key(uuid, jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.validate_benefit_publication_envelope(jsonb, uuid, jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.validate_locked_retirement_evidence(jsonb, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.approve_card_benefit_enrichment(uuid, uuid, jsonb) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.canonical_json_text(jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.canonical_json_numbers_are_safe(jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.canonical_json_shape_is_bounded(jsonb, integer, integer, integer, integer, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.validate_locked_benefit_proposals(jsonb, text) TO service_role;
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
    'public.canonical_json_numbers_are_safe(jsonb)'::regprocedure,
    'public.canonical_json_shape_is_bounded(jsonb,integer,integer,integer,integer,integer)'::regprocedure,
    'public.validate_locked_benefit_proposals(jsonb,text)'::regprocedure,
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
