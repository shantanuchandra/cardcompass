--
-- PostgreSQL database dump
--

\restrict ll6MZjhMAf84oGBGwhgVVbhp3f6Qh7gXe94XBtiklgle4FobDVKmYRVqzNkfBKg

-- Dumped from database version 17.6
-- Dumped by pg_dump version 17.10 (Homebrew)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA public;


--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- Name: add_transaction(uuid, uuid, numeric, text, timestamp with time zone, text, text, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_transaction(_user_id uuid, _user_card_id uuid, _amount numeric, _description text, _transaction_date timestamp with time zone, _category text, _type text, _currency text DEFAULT 'INR'::text, _merchant_name text DEFAULT NULL::text, _location text DEFAULT NULL::text) RETURNS uuid
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
DECLARE
    transaction_id UUID;
BEGIN
    -- Validate required parameters
    IF _user_id IS NULL OR _user_card_id IS NULL OR _amount IS NULL THEN
        RAISE EXCEPTION 'Required parameters cannot be null: user_id, user_card_id, amount';
    END IF;

    -- Verify this card belongs to the user for security
    IF NOT EXISTS (SELECT 1 FROM user_cards WHERE id = _user_card_id AND user_id = _user_id) THEN
        RAISE EXCEPTION 'Card does not belong to user';
    END IF;

    INSERT INTO transactions (
        user_id, user_card_id, amount, description,
        transaction_date, category, transaction_type,
        currency, merchant_name, location
    ) VALUES (
        _user_id, _user_card_id, _amount, _description,
        _transaction_date, _category, _type,
        _currency, _merchant_name, _location
    ) RETURNING id INTO transaction_id;

    RETURN transaction_id;
END;
$$;


--
-- Name: adopt_reviewed_card_enrichment_source(uuid, text, text, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.adopt_reviewed_card_enrichment_source(_card_id uuid, _issuer text, _canonical_url text, _final_url_hash text, _content_hash text, _parser_version text) RETURNS TABLE(enqueued_count integer, existing_v6_job_count integer, adopted_count integer)
    LANGUAGE plpgsql
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $_$
DECLARE
  existing_job public.card_catalog_enrichment_jobs%ROWTYPE;
  requested_job_key text;
BEGIN
  IF _parser_version <> 'benefits-v6' OR _card_id IS NULL
     OR _final_url_hash !~ '^[0-9a-f]{64}$'
     OR _content_hash !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'invalid_reviewed_enrichment_source';
  END IF;
  IF public.canonical_card_resource_url(_canonical_url) IS DISTINCT FROM _canonical_url
     OR lower(_final_url_hash) <> encode(
       extensions.digest(convert_to(_canonical_url, 'UTF8'), 'sha256'), 'hex'
     )
     OR NOT public.card_catalog_source_matches_issuer(_issuer, _canonical_url) THEN
    RAISE EXCEPTION 'invalid_reviewed_enrichment_source';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'card_benefit_enrichment_identity:' || _card_id::text || ':benefits-v6', 0
  ));
  requested_job_key := _card_id::text || ':' || lower(_final_url_hash) || ':benefits-v6';

  SELECT job.* INTO existing_job
  FROM public.card_catalog_enrichment_jobs AS job
  WHERE job.card_id = _card_id AND lower(trim(job.parser_version)) = 'benefits-v6'
  FOR UPDATE;

  IF FOUND THEN
    existing_v6_job_count := 1;
    enqueued_count := 0;
    adopted_count := 0;
    IF existing_job.job_key = requested_job_key
       AND existing_job.canonical_url = _canonical_url
       AND existing_job.content_hash = lower(_content_hash) THEN
      RETURN NEXT;
      RETURN;
    END IF;
    IF existing_job.status NOT IN (
         'completed', 'staged', 'quarantined', 'review_required', 'failed'
       )
       OR (existing_job.status = 'failed' AND existing_job.next_retry_at IS NOT NULL)
       OR existing_job.lease_token IS NOT NULL
       OR (existing_job.lease_expires_at IS NOT NULL AND existing_job.lease_expires_at > statement_timestamp()) THEN
      RAISE EXCEPTION 'reviewed_enrichment_source_busy' USING ERRCODE = '40001';
    END IF;
    UPDATE public.card_catalog_enrichment_jobs AS job
    SET canonical_url = _canonical_url,
        final_url_hash = lower(_final_url_hash),
        content_hash = lower(_content_hash),
        job_key = requested_job_key,
        updated_at = statement_timestamp()
    WHERE job.id = existing_job.id;
    -- Deliberately preserve status, attempts, next_run_at, staging_id and the
    -- complete historical result_summary/observation evidence.
    adopted_count := 1;
    RETURN NEXT;
    RETURN;
  END IF;

  enqueued_count := public.enqueue_card_benefit_enrichment_jobs(jsonb_build_array(
    jsonb_build_object(
      'card_id', _card_id,
      'issuer', trim(_issuer),
      'canonical_url', _canonical_url,
      'final_url_hash', lower(_final_url_hash),
      'content_hash', lower(_content_hash),
      'parser_version', 'benefits-v6',
      'job_key', requested_job_key,
      'run_mode', 'scheduled',
      'result_summary', jsonb_build_object(
        'publication_source_adopted', true,
        'unsafe_mutation_count', 0,
        'raw_body_stored', false,
        'evidence_passed', false,
        'idempotency_passed', true
      )
    )
  ));
  IF enqueued_count = 0 THEN
    SELECT count(*) INTO existing_v6_job_count
    FROM public.card_catalog_enrichment_jobs AS job
    WHERE job.card_id = _card_id
      AND lower(trim(job.parser_version)) = 'benefits-v6'
      AND job.job_key = requested_job_key;
  ELSE
    existing_v6_job_count := 0;
  END IF;
  adopted_count := 0;
  RETURN NEXT;
END;
$_$;


--
-- Name: append_catalog_observation_history(jsonb, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.append_catalog_observation_history(_history jsonb, _entry jsonb) RETURNS jsonb
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
  WITH entries AS (
    SELECT value
    FROM jsonb_array_elements(
      CASE WHEN jsonb_typeof(_history) = 'array' THEN _history ELSE '[]'::jsonb END
      || jsonb_build_array(_entry)
    )
    WHERE jsonb_typeof(value) = 'object'
  ), ranked AS (
    SELECT DISTINCT ON (coalesce(
      value->>'semantic_hash', value->>'source_observation_semantic_hash',
      value->>'source_observation_hash', value::text
    )) value,
      CASE
        WHEN coalesce(value->>'observed_at', value->>'retrieved_at', '')
          ~ '^20[0-9]{2}-[0-9]{2}-[0-9]{2}T'
        THEN coalesce(value->>'observed_at', value->>'retrieved_at')::timestamptz
        ELSE '-infinity'::timestamptz
      END AS observed_at,
      coalesce(
        value->>'semantic_hash', value->>'source_observation_semantic_hash',
        value->>'source_observation_hash', value::text
      ) AS semantic_key
    FROM entries
    ORDER BY coalesce(
      value->>'semantic_hash', value->>'source_observation_semantic_hash',
      value->>'source_observation_hash', value::text
    ), observed_at DESC
  ), newest AS (
    SELECT value, observed_at, semantic_key FROM ranked
    ORDER BY observed_at DESC, semantic_key
    LIMIT 24
  )
  SELECT coalesce(jsonb_agg(value ORDER BY observed_at DESC, semantic_key), '[]'::jsonb)
  FROM newest;
$$;


--
-- Name: apply_statement_payment(uuid, uuid, uuid, numeric, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.apply_statement_payment(p_statement_id uuid, p_user_id uuid, p_user_card_id uuid, p_payment_amount numeric, p_mark_paid boolean DEFAULT false) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_statement public.statements%ROWTYPE;
  v_payment numeric(12,2);
BEGIN
  IF auth.uid() IS NULL OR auth.uid() <> p_user_id THEN
    RAISE EXCEPTION 'statement payment requires the owning user';
  END IF;
  PERFORM set_config('cardcompass.reconciliation_write', 'on', true);

  SELECT * INTO v_statement FROM public.statements
  WHERE id = p_statement_id AND user_id = p_user_id AND user_card_id = p_user_card_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'statement is not owned by the supplied user and card';
  END IF;
  v_payment := CASE WHEN p_mark_paid THEN v_statement.total_amount - v_statement.paid_amount ELSE p_payment_amount END;
  IF v_payment <= 0 OR v_payment > v_statement.total_amount - v_statement.paid_amount THEN
    RAISE EXCEPTION 'payment amount must be positive and no greater than the remaining balance';
  END IF;
  UPDATE public.statements
  SET paid_amount = paid_amount + v_payment,
      payment_status = CASE WHEN paid_amount + v_payment >= total_amount THEN 'paid' ELSE 'partial' END,
      -- Preserve the time of the first recorded allocation, including partials.
      paid_at = COALESCE(paid_at, NOW())
  WHERE id = p_statement_id AND user_id = p_user_id AND user_card_id = p_user_card_id;
  RETURN jsonb_build_object('payment_amount', v_payment);
END;
$$;


--
-- Name: approve_card_benefit_enrichment(uuid, uuid, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.approve_card_benefit_enrichment(_staging_id uuid, _reviewed_by uuid, _decisions jsonb) RETURNS TABLE(staging_id uuid, resulting_status text)
    LANGUAGE plpgsql
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $_$
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
  staging_card_id uuid;
  staging_parser_version text;
  locked_card_type text;
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
  -- Task 3 uses this exact card-scoped key before it locks either the queue job
  -- or staging. Do the same here, then revalidate under the staging row lock.
  SELECT staging.card_id, staging.parser_version
  INTO staging_card_id, staging_parser_version
  FROM public.card_benefits_staging AS staging
  WHERE staging.id = _staging_id
    AND staging.request_type = 'official_benefit_enrichment';
  IF staging_card_id IS NULL THEN
    RAISE EXCEPTION 'invalid_benefit_staging';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'card_benefit_enrichment_review:' || staging_card_id::text,
    0
  ));
  -- Task 7 publishes mutable card identity under this exact lock. This
  -- serialization belongs only to v6: the rollback v5 lane historically
  -- approves retained staging even when later catalog/card_type authority is
  -- absent. For v6 the order remains review advisory -> benefit identity
  -- advisory -> card row -> staging row.
  IF staging_parser_version = 'benefits-v6' THEN
    PERFORM pg_advisory_xact_lock(hashtextextended(
      'card_benefit_enrichment_identity:' || staging_card_id::text || ':benefits-v6',
      0
    ));
    SELECT catalog.card_type INTO locked_card_type
    FROM public.card_catalog AS catalog
    WHERE catalog.id = staging_card_id
      AND lower(trim(coalesce(catalog.card_type, ''))) = 'credit'
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'card_target_not_found'; END IF;
  END IF;
  SELECT staging.* INTO staging_row
  FROM public.card_benefits_staging AS staging
  WHERE staging.id = _staging_id
    AND staging.card_id = staging_card_id
    AND staging.parser_version = staging_parser_version
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

  -- v6 pilot qualification must prove that no unrelated live mutation landed
  -- between extraction and this locked review transaction. Seal the exact
  -- pre-publication state while the shared card advisory lock is held. v5 is
  -- deliberately unchanged for rollback.
  IF staging_row.parser_version = 'benefits-v6' THEN
    staging_row.extracted_data := jsonb_set(
      staging_row.extracted_data,
      '{review_pre_live_state}',
      public.card_benefit_review_live_state_snapshot(staging_row.card_id),
      true
    );
    UPDATE public.card_benefits_staging
    SET extracted_data = staging_row.extracted_data,
        updated_at = statement_timestamp()
    WHERE id = staging_row.id;
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
          UNION ALL
          SELECT conflict_current.value
          FROM jsonb_array_elements(coalesce(staging_row.extracted_data->'diff'->'conflicts', '[]'::jsonb)) AS item(value)
          CROSS JOIN LATERAL jsonb_array_elements(coalesce(item.value->'current', '[]'::jsonb)) AS conflict_current(value)
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
            UNION ALL
            SELECT conflict_current.value
            FROM jsonb_array_elements(coalesce(staging_row.extracted_data->'diff'->'conflicts', '[]'::jsonb)) AS item(value)
            CROSS JOIN LATERAL jsonb_array_elements(coalesce(item.value->'current', '[]'::jsonb)) AS conflict_current(value)
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
    decision_proposal_index := NULL;
    existing_benefit_id := NULL;
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
      IF (decision->>'proposal_index') ~ '^[0-9]+$' THEN
        decision_proposal_index := (decision->>'proposal_index')::integer;
        staged_proposal := staging_row.extracted_data->'proposals'->decision_proposal_index;
      ELSIF nullif(coalesce(
        decision->>'benefit_id', decision->>'current_benefit_id'
      ), '') IS NOT NULL THEN
        existing_benefit_id := coalesce(
          decision->>'benefit_id', decision->>'current_benefit_id'
        )::uuid;
      END IF;
      IF decision_proposal_index IS NOT NULL THEN
        audit_decision := jsonb_build_object(
          'action', decision_action,
          'proposal_index', decision_proposal_index,
          'dedupe_key', staged_proposal->>'dedupeKey',
          'condition_hash', staged_proposal->>'conditionHash',
          'reason', nullif(trim(decision->>'reason'), '')
        );
      ELSIF existing_benefit_id IS NOT NULL THEN
        audit_decision := jsonb_build_object(
          'action', decision_action,
          'benefit_id', existing_benefit_id,
          'reason', nullif(trim(decision->>'reason'), '')
        );
      ELSE
        audit_decision := jsonb_build_object(
          'action', decision_action,
          'reason', nullif(trim(decision->>'reason'), '')
        );
      END IF;
    END IF;
    audit_decision := jsonb_strip_nulls(audit_decision || jsonb_build_object(
      'reviewed_by', _reviewed_by,
      'reviewed_at', public.canonical_card_benefit_row_timestamp(statement_timestamp()),
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
        'reviewed_at', public.canonical_card_benefit_row_timestamp(statement_timestamp()),
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
$_$;


--
-- Name: approve_catalog_entry_request(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.approve_catalog_entry_request(_staging_id uuid, _reviewed_by uuid) RETURNS TABLE(card_id uuid, bank_name text, card_name text, source_url text)
    LANGUAGE plpgsql
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
DECLARE
  staging_row public.card_benefits_staging%ROWTYPE;
  discovery_id uuid;
  review_id uuid;
  published record;
  fields jsonb;
BEGIN
  IF _staging_id IS NULL OR _reviewed_by IS NULL THEN
    RAISE EXCEPTION 'invalid_catalog_entry_review';
  END IF;
  SELECT staging.* INTO staging_row FROM public.card_benefits_staging AS staging
  WHERE staging.id = _staging_id AND staging.status = 'pending'
    AND staging.card_id IS NULL
    AND staging.extracted_data->>'request_type' = 'catalog_entry'
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'invalid_catalog_entry_review'; END IF;
  fields := jsonb_build_object(
    'issuer', trim(staging_row.extracted_data->>'bank_name'),
    'cardName', trim(staging_row.extracted_data->>'card_name'),
    'official_url', staging_row.source_url,
    'submitted_url', staging_row.source_url,
    'final_url', staging_row.source_url,
    'content_hash', encode(extensions.digest(convert_to(staging_row.source_url, 'UTF8'), 'sha256'), 'hex'),
    'retrieved_at', statement_timestamp(),
    'source_type', 'secondary',
    'source_observation', jsonb_build_object('kind', 'manual_catalog_request')
  );
  SELECT job.id INTO discovery_id FROM public.card_discovery_jobs AS job
  WHERE job.user_id = staging_row.requested_by
    AND job.dedupe_key = 'catalog-entry:' || _staging_id::text;
  IF discovery_id IS NULL THEN
    INSERT INTO public.card_discovery_jobs(
      user_id, discovery_source, issuer, proposed_product, evidence,
      dedupe_key, status, updated_at
    ) VALUES (
      staging_row.requested_by, 'statement', fields->>'issuer', fields->>'cardName',
      jsonb_build_object('manual_catalog_request', true),
      'catalog-entry:' || _staging_id::text, 'review_required', statement_timestamp()
    ) RETURNING id INTO discovery_id;
  END IF;
  SELECT review.id INTO review_id FROM public.card_catalog_review_queue AS review
  WHERE review.discovery_job_id = discovery_id;
  IF review_id IS NULL THEN
    INSERT INTO public.card_catalog_review_queue(
      discovery_job_id, proposed_fields, source_evidence, existing_candidates,
      validation_warnings, confidence, status, updated_at
    ) VALUES (
      discovery_id, fields, fields->'source_observation', '[]'::jsonb,
      '[]'::jsonb, 1, 'pending', statement_timestamp()
    ) RETURNING id INTO review_id;
    UPDATE public.card_discovery_jobs SET review_item_id = review_id
    WHERE id = discovery_id;
  END IF;
  SELECT * INTO published FROM public.publish_card_catalog_identity(
    discovery_id, review_id, _reviewed_by, 'approve', '{}'::jsonb,
    NULL, 'approved manual catalog request', 'benefits-v6'
  );
  UPDATE public.card_benefits_staging SET status = 'approved',
    card_id = published.card_id, reviewed_at = statement_timestamp(),
    reviewed_by = _reviewed_by, updated_at = statement_timestamp()
  WHERE id = _staging_id;
  RETURN QUERY SELECT published.card_id, fields->>'issuer', fields->>'cardName', staging_row.source_url;
END;
$$;


--
-- Name: bounded_card_enrichment_timestamp(text, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.bounded_card_enrichment_timestamp(_value text, _now timestamp with time zone) RETURNS text
    LANGUAGE plpgsql STABLE
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  parsed_value timestamptz;
BEGIN
  IF _value IS NULL OR length(_value) > 64 OR _now IS NULL THEN RETURN NULL; END IF;
  parsed_value := public.canonical_card_enrichment_timestamp(_value);
  IF parsed_value IS NULL THEN RETURN NULL; END IF;
  IF parsed_value < '2000-01-01T00:00:00Z'::timestamptz
     OR parsed_value > _now + interval '5 minutes' THEN
    RETURN NULL;
  END IF;
  RETURN public.canonical_card_benefit_row_timestamp(parsed_value);
END;
$$;


--
-- Name: canonical_benefit_condition_hash(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.canonical_benefit_condition_hash(_condition jsonb) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO 'public', 'extensions', 'pg_temp'
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


--
-- Name: canonical_card_benefit_row_timestamp(timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.canonical_card_benefit_row_timestamp(_value timestamp with time zone) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'public', 'pg_temp'
    AS $$
  SELECT CASE WHEN _value IS NULL THEN NULL ELSE
    to_char(
      _value AT TIME ZONE 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
    )
  END;
$$;


--
-- Name: canonical_card_enrichment_timestamp(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.canonical_card_enrichment_timestamp(_value text) RETURNS timestamp with time zone
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO 'public', 'pg_temp'
    AS $_$
DECLARE
  parts text[];
  parsed_value timestamptz;
  offset_hour integer;
  offset_minute integer;
BEGIN
  IF _value IS NULL OR length(_value) > 48 THEN RETURN NULL; END IF;
  parts := regexp_match(
    _value,
    '^(\d{4}-\d{2}-\d{2})[ T](\d{2}:\d{2}:\d{2})(?:\.(\d{1,6}))?(Z|([+-])(\d{2})(?::?(\d{2}))?)$'
  );
  IF parts IS NULL THEN RETURN NULL; END IF;
  offset_hour := CASE WHEN upper(parts[4]) = 'Z' THEN 0 ELSE parts[6]::integer END;
  offset_minute := CASE WHEN upper(parts[4]) = 'Z' THEN 0
    ELSE coalesce(parts[7], '0')::integer END;
  IF offset_hour > 14 OR offset_minute > 59
     OR (offset_hour = 14 AND offset_minute <> 0) THEN RETURN NULL; END IF;
  BEGIN
    parsed_value := _value::timestamptz;
  EXCEPTION WHEN OTHERS THEN
    RETURN NULL;
  END;
  RETURN parsed_value;
END;
$_$;


--
-- Name: canonical_card_resource_url(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.canonical_card_resource_url(_url text) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $_$
DECLARE
  exact_url text := trim(coalesce(_url, ''));
  without_fragment text;
  base_url text;
  authority text;
  normalized_path text;
  raw_query text;
  retained_query text;
  query_part record;
  query_key text;
  query_value text;
  query_count integer := 0;
BEGIN
  IF length(exact_url) < 10 OR length(exact_url) > 2048
     OR exact_url !~ '^https://[^/@?#]+'
     OR exact_url ~ '^https://[^/?#]*@' THEN
    RAISE EXCEPTION 'invalid_source_url';
  END IF;
  without_fragment := split_part(exact_url, '#', 1);
  base_url := split_part(without_fragment, '?', 1);
  authority := substring(base_url FROM '^https://([^/]+)');
  IF authority IS NULL OR authority = ''
     OR authority !~ '^[A-Za-z0-9.-]+(?::[0-9]+)?$' THEN
    RAISE EXCEPTION 'invalid_source_url';
  END IF;
  normalized_path := substring(base_url FROM length('https://' || authority) + 1);
  normalized_path := public.normalize_card_resource_path(normalized_path);
  base_url := 'https://' || lower(regexp_replace(authority, ':[0-9]+$', '')) || normalized_path;
  raw_query := CASE WHEN position('?' IN without_fragment) > 0
    THEN substring(without_fragment FROM position('?' IN without_fragment) + 1)
    ELSE '' END;
  -- An explicit empty query separator is not the same resource spelling as a
  -- URL with no query. Fail closed so Edge and SQL cannot bind different keys.
  IF raw_query = '' AND position('?' IN without_fragment) > 0 THEN
    RAISE EXCEPTION 'unapproved_query';
  ELSIF raw_query = '' THEN
    RETURN base_url;
  END IF;

  retained_query := '';
  FOR query_part IN
    SELECT part, ordinality
    FROM regexp_split_to_table(raw_query, '&') WITH ORDINALITY AS item(part, ordinality)
    ORDER BY ordinality
  LOOP
    query_count := query_count + 1;
    IF query_part.part = '' OR query_part.part ~ '%(?![0-9A-Fa-f]{2})' THEN
      RAISE EXCEPTION 'unapproved_query';
    END IF;
    query_key := lower(public.decode_card_resource_component(
      split_part(query_part.part, '=', 1)
    ));
    query_value := public.decode_card_resource_component(
      CASE WHEN position('=' IN query_part.part) > 0
        THEN substring(query_part.part FROM position('=' IN query_part.part) + 1)
        ELSE '' END
    );
    IF query_count > 8 OR length(query_key) > 64 OR length(query_value) > 512 THEN
      RAISE EXCEPTION 'unapproved_query';
    END IF;
    IF query_key ~ '^utm_' OR query_key IN ('gclid', 'fbclid') THEN
      CONTINUE;
    END IF;
    IF query_key NOT IN (
      'document', 'doc', 'file', 'filename', 'lang', 'language',
      'locale', 'version', 'variant'
    ) OR query_key ~ '(token|session|secret|password|passwd|credential|auth|signature|sig|key|code|state|nonce)' THEN
      RAISE EXCEPTION 'unapproved_query';
    END IF;
    retained_query := retained_query || CASE WHEN retained_query = '' THEN '' ELSE '&' END || query_part.part;
  END LOOP;
  RETURN base_url || CASE WHEN retained_query = '' THEN '' ELSE '?' || retained_query END;
END;
$_$;


--
-- Name: canonical_json_numbers_are_safe(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.canonical_json_numbers_are_safe(_value jsonb) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO 'public', 'pg_temp'
    AS $_$
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
$_$;


--
-- Name: canonical_json_shape_is_bounded(jsonb, integer, integer, integer, integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.canonical_json_shape_is_bounded(_value jsonb, _max_depth integer, _max_keys integer, _max_array_items integer, _max_key_chars integer, _max_string_chars integer) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: canonical_json_text(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.canonical_json_text(_value jsonb) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: canonical_locked_benefit_condition(jsonb, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.canonical_locked_benefit_condition(_proposal jsonb, _parser_version text) RETURNS jsonb
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO 'public', 'pg_temp'
    AS $_$
DECLARE
  -- Exact SQL mirror of benefit_contract.ts numericValue(): currency markers
  -- are removed globally only for the numeric parse candidate; prose falls
  -- back to its original normalized text when the remaining value is not numeric.
  CURRENCY_MARKER_PATTERN constant text :=
    '(₹|rs\.?|inr)[[:space:]]*';
  normalized_config jsonb := '{}'::jsonb;
  normalized_exclusions jsonb;
  normalized_partners jsonb;
  normalized_regions jsonb;
  normalized_restrictions jsonb;
  source_terms jsonb;
  category_value text;
  config_item record;
  exclusion_key text;
  normalized_text text;
  numeric_match text[];
  numeric_value numeric;
  scalar_key text;
  scalar_value jsonb;
  normalized_terms jsonb;
BEGIN
  IF jsonb_typeof(_proposal) <> 'object'
     OR _parser_version NOT IN ('benefits-v5', 'benefits-v6') THEN
    RAISE EXCEPTION 'invalid_staged_benefit_shape';
  END IF;

  FOR config_item IN SELECT item.key, item.value FROM jsonb_each(
    coalesce(_proposal->'valueConfig', '{}'::jsonb) -
      'offer_subject' - 'restrictions' - 'exclusions'
  ) AS item(key, value) ORDER BY item.key LOOP
    CASE jsonb_typeof(config_item.value)
      WHEN 'null' THEN CONTINUE;
      WHEN 'string' THEN
        normalized_text := btrim(regexp_replace(
          lower(normalize(config_item.value #>> '{}', NFKC)),
          '[[:space:]]+', ' ', 'g'
        ));
        normalized_text := regexp_replace(
          normalized_text, CURRENCY_MARKER_PATTERN, '', 'g'
        );
        numeric_match := regexp_match(
          normalized_text,
          '^([+-]?[0-9][0-9,]*(\.[0-9]+)?)[[:space:]]*(lakh|lac|lacs|crore|crores)?$'
        );
        IF numeric_match IS NULL THEN
          scalar_value := to_jsonb(btrim(regexp_replace(
            lower(normalize(config_item.value #>> '{}', NFKC)),
            '[[:space:]]+', ' ', 'g'
          )));
        ELSE
          numeric_value := replace(numeric_match[1], ',', '')::numeric * CASE
            WHEN numeric_match[3] IN ('crore', 'crores') THEN 10000000
            WHEN numeric_match[3] IS NOT NULL THEN 100000
            ELSE 1
          END;
          scalar_value := to_jsonb(numeric_value);
        END IF;
      ELSE scalar_value := config_item.value;
    END CASE;
    normalized_config := jsonb_set(
      normalized_config, ARRAY[config_item.key], scalar_value, true
    );
  END LOOP;

  FOREACH scalar_key IN ARRAY ARRAY[
    'value', 'rate', 'cap', 'threshold', 'frequency', 'period'
  ] LOOP
    IF _proposal ? scalar_key THEN
      IF jsonb_typeof(_proposal->scalar_key) = 'string' THEN
        normalized_text := btrim(regexp_replace(
          lower(normalize(_proposal->>scalar_key, NFKC)),
          '[[:space:]]+', ' ', 'g'
        ));
        normalized_text := regexp_replace(
          normalized_text, CURRENCY_MARKER_PATTERN, '', 'g'
        );
        numeric_match := regexp_match(
          normalized_text,
          '^([+-]?[0-9][0-9,]*(\.[0-9]+)?)[[:space:]]*(lakh|lac|lacs|crore|crores)?$'
        );
        IF numeric_match IS NULL THEN
          scalar_value := to_jsonb(btrim(regexp_replace(
            lower(normalize(_proposal->>scalar_key, NFKC)),
            '[[:space:]]+', ' ', 'g'
          )));
        ELSE
          numeric_value := replace(numeric_match[1], ',', '')::numeric * CASE
            WHEN numeric_match[3] IN ('crore', 'crores') THEN 10000000
            WHEN numeric_match[3] IS NOT NULL THEN 100000
            ELSE 1
          END;
          scalar_value := to_jsonb(numeric_value);
        END IF;
      ELSE
        scalar_value := _proposal->scalar_key;
      END IF;
      normalized_config := jsonb_set(
        normalized_config,
        ARRAY[scalar_key],
        scalar_value,
        true
      );
    END IF;
  END LOOP;

  SELECT coalesce(jsonb_agg(term.value ORDER BY term.value), '[]'::jsonb)
  INTO normalized_partners
  FROM (
    SELECT DISTINCT btrim(regexp_replace(
      lower(normalize(item.value #>> '{}', NFKC)), '[[:space:]]+', ' ', 'g'
    )) AS value
    FROM jsonb_array_elements(coalesce(_proposal->'partners', '[]'::jsonb))
      AS item(value)
    WHERE btrim(regexp_replace(
      lower(normalize(item.value #>> '{}', NFKC)), '[[:space:]]+', ' ', 'g'
    )) <> ''
  ) AS term;
  SELECT coalesce(jsonb_agg(term.value ORDER BY term.value), '[]'::jsonb)
  INTO normalized_regions
  FROM (
    SELECT DISTINCT btrim(regexp_replace(
      lower(normalize(item.value #>> '{}', NFKC)), '[[:space:]]+', ' ', 'g'
    )) AS value
    FROM jsonb_array_elements(coalesce(_proposal->'regions', '[]'::jsonb))
      AS item(value)
    WHERE btrim(regexp_replace(
      lower(normalize(item.value #>> '{}', NFKC)), '[[:space:]]+', ' ', 'g'
    )) <> ''
  ) AS term;
  SELECT coalesce(jsonb_agg(term.value ORDER BY term.value), '[]'::jsonb)
  INTO normalized_restrictions
  FROM (
    SELECT DISTINCT btrim(regexp_replace(
      lower(normalize(item.value #>> '{}', NFKC)), '[[:space:]]+', ' ', 'g'
    )) AS value
    FROM jsonb_array_elements(coalesce(_proposal->'restrictions', '[]'::jsonb))
      AS item(value)
    WHERE btrim(regexp_replace(
      lower(normalize(item.value #>> '{}', NFKC)), '[[:space:]]+', ' ', 'g'
    )) <> ''
  ) AS term;

  source_terms := CASE WHEN _parser_version = 'benefits-v6'
    THEN coalesce(
      _proposal->'exclusions'->'additional'->'source_terms', '[]'::jsonb
    )
    ELSE coalesce(_proposal->'exclusions', '[]'::jsonb)
  END;
  SELECT coalesce(jsonb_agg(term.value ORDER BY term.value), '[]'::jsonb)
  INTO normalized_terms
  FROM (
    SELECT DISTINCT btrim(regexp_replace(
      lower(normalize(item.value #>> '{}', NFKC)), '[[:space:]]+', ' ', 'g'
    )) AS value
    FROM jsonb_array_elements(source_terms) AS item(value)
    WHERE btrim(regexp_replace(
      lower(normalize(item.value #>> '{}', NFKC)), '[[:space:]]+', ' ', 'g'
    )) <> ''
  ) AS term;
  normalized_exclusions := jsonb_build_object(
    'additional', jsonb_build_object('source_terms', normalized_terms)
  );
  FOREACH exclusion_key IN ARRAY ARRAY[
    'categories', 'days', 'mcc_codes', 'merchants', 'transaction_types'
  ] LOOP
    SELECT coalesce(jsonb_agg(term.value ORDER BY term.value), '[]'::jsonb)
    INTO normalized_terms
    FROM (
      SELECT DISTINCT btrim(regexp_replace(
        lower(normalize(item.value #>> '{}', NFKC)),
        '[[:space:]]+', ' ', 'g'
      )) AS value
      FROM jsonb_array_elements(CASE WHEN _parser_version = 'benefits-v6'
        THEN coalesce(_proposal->'exclusions'->exclusion_key, '[]'::jsonb)
        ELSE '[]'::jsonb END
      ) AS item(value)
      WHERE btrim(regexp_replace(
        lower(normalize(item.value #>> '{}', NFKC)),
        '[[:space:]]+', ' ', 'g'
      )) <> ''
    ) AS term;
    normalized_exclusions := normalized_exclusions ||
      jsonb_build_object(exclusion_key, normalized_terms);
  END LOOP;

  category_value := btrim(regexp_replace(
    lower(normalize(_proposal->>'category', NFKC)), '[[:space:]]+', ' ', 'g'
  ));
  category_value := CASE
    WHEN category_value IN ('reward', 'rewards', 'point', 'points', 'reward points')
      THEN 'points'
    WHEN category_value IN ('lounge', 'airport lounge access') THEN 'travel'
    WHEN category_value = 'cashback rewards' THEN 'cashback'
    ELSE category_value
  END;

  RETURN jsonb_strip_nulls(jsonb_build_object(
    'benefit_type', nullif(btrim(regexp_replace(
      lower(normalize(_proposal->>'valueType', NFKC)), '[[:space:]]+', ' ', 'g'
    )), ''),
    'category', nullif(category_value, ''),
    'exclusions', normalized_exclusions,
    'partners', normalized_partners,
    'regions', normalized_regions,
    'restrictions', normalized_restrictions,
    'semantic_key', CASE WHEN _parser_version = 'benefits-v6' THEN nullif(
      btrim(regexp_replace(
        lower(normalize(_proposal->>'offerSubject', NFKC)),
        '[[:space:]]+', ' ', 'g'
      )), ''
    ) ELSE NULL END,
    'valid_from', nullif(btrim(regexp_replace(
      lower(normalize(coalesce(_proposal->>'effectiveFrom', ''), NFKC)),
      '[[:space:]]+', ' ', 'g'
    )), ''),
    'valid_until', nullif(btrim(regexp_replace(
      lower(normalize(coalesce(_proposal->>'effectiveTo', ''), NFKC)),
      '[[:space:]]+', ' ', 'g'
    )), ''),
    'value_config', normalized_config
  ));
END;
$_$;


--
-- Name: capture_card_enrichment_pilot_publication_snapshot(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.capture_card_enrichment_pilot_publication_snapshot() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
BEGIN
  IF NEW.status = 'approved' AND OLD.status IS DISTINCT FROM 'approved'
     AND NEW.parser_version = 'benefits-v6'
     AND EXISTS (
       SELECT 1 FROM public.card_catalog_enrichment_jobs AS job
       WHERE job.card_id = NEW.card_id
         AND job.parser_version = NEW.parser_version
         AND job.normalized_fields->'pilot_evidence'->>'staging_id' = NEW.id::text
     ) THEN
    NEW.extracted_data := jsonb_set(
      NEW.extracted_data,
      '{published_live_state}',
      public.card_enrichment_pilot_live_state_snapshot(NEW.card_id),
      true
    );
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: card_benefit_review_live_state_snapshot(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.card_benefit_review_live_state_snapshot(_card_id uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
DECLARE
  catalog_rows jsonb;
  mapping_rows jsonb;
  benefit_rows jsonb;
BEGIN
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id', card.id, 'card_name', card.card_name, 'bank', card.bank,
    'network', card.network, 'card_type', card.card_type,
    'annual_fee', card.annual_fee, 'joining_fee', card.joining_fee,
    'apr', card.apr, 'card_url', card.card_url,
    'is_discontinued', card.is_discontinued,
    'created_at', public.canonical_card_benefit_row_timestamp(card.created_at),
    'updated_at', public.canonical_card_benefit_row_timestamp(card.updated_at)
  ) ORDER BY card.id), '[]'::jsonb) INTO catalog_rows
  FROM public.card_catalog AS card WHERE card.id = _card_id;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'mapping_id', mapping.mapping_id, 'card_id', mapping.card_id,
    'benefit_id', mapping.benefit_id,
    'display_priority', mapping.display_priority,
    'is_primary', mapping.is_primary, 'category_codes', mapping.category_codes,
    'retired_at', public.canonical_card_benefit_row_timestamp(mapping.retired_at),
    'created_at', public.canonical_card_benefit_row_timestamp(mapping.created_at)
  ) ORDER BY mapping.mapping_id), '[]'::jsonb) INTO mapping_rows
  FROM public.card_benefit_mapping AS mapping WHERE mapping.card_id = _card_id;

  SELECT coalesce(jsonb_agg(benefit.row_value ORDER BY benefit.benefit_id), '[]'::jsonb)
    INTO benefit_rows
  FROM (
    SELECT DISTINCT ON (stored.benefit_id) stored.benefit_id,
      jsonb_build_object(
        'benefit_id', stored.benefit_id, 'dedupe_key', stored.dedupe_key,
        'title', stored.title, 'description', stored.description,
        'benefit_category', stored.benefit_category,
        'benefit_type', stored.benefit_type, 'value_config', stored.value_config,
        'partners', stored.partners, 'exclusions', stored.exclusions,
        'regions', stored.regions, 'source_url', stored.source_url,
        'valid_from', stored.valid_from, 'valid_until', stored.valid_until,
        'is_active', stored.is_active,
        'created_at', public.canonical_card_benefit_row_timestamp(stored.created_at),
        'updated_at', public.canonical_card_benefit_row_timestamp(stored.updated_at)
      ) AS row_value
    FROM public.benefits AS stored
    JOIN public.card_benefit_mapping AS mapping
      ON mapping.benefit_id = stored.benefit_id
    WHERE mapping.card_id = _card_id
    ORDER BY stored.benefit_id
  ) AS benefit;

  RETURN jsonb_build_object(
    'card_catalog', public.card_benefit_review_snapshot_rows(catalog_rows),
    'benefits', public.card_benefit_review_snapshot_rows(benefit_rows),
    'card_benefit_mapping', public.card_benefit_review_snapshot_rows(mapping_rows)
  );
END;
$$;


--
-- Name: card_benefit_review_snapshot_rows(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.card_benefit_review_snapshot_rows(_rows jsonb) RETURNS jsonb
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
  SELECT jsonb_build_object(
    'count', jsonb_array_length(_rows),
    'row_hash', encode(extensions.digest(
      convert_to(public.canonical_json_text(_rows), 'UTF8'), 'sha256'
    ), 'hex')
  );
$$;


--
-- Name: card_catalog_baseline_matches(jsonb, uuid, text, text, numeric, numeric, numeric, text, boolean, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.card_catalog_baseline_matches(_baseline jsonb, _card_id uuid, _card_name text, _network text, _annual_fee numeric, _joining_fee numeric, _apr numeric, _card_url text, _is_discontinued boolean, _updated_at timestamp with time zone) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
BEGIN
  RETURN jsonb_typeof(_baseline) = 'object'
    AND _baseline->>'card_id' = _card_id::text
    AND _baseline->'card_name' IS NOT DISTINCT FROM
      coalesce(to_jsonb(_card_name), 'null'::jsonb)
    AND _baseline->'network' IS NOT DISTINCT FROM
      coalesce(to_jsonb(_network), 'null'::jsonb)
    AND _baseline->'annual_fee' IS NOT DISTINCT FROM
      coalesce(to_jsonb(_annual_fee), 'null'::jsonb)
    AND _baseline->'joining_fee' IS NOT DISTINCT FROM
      coalesce(to_jsonb(_joining_fee), 'null'::jsonb)
    AND _baseline->'apr' IS NOT DISTINCT FROM
      coalesce(to_jsonb(_apr), 'null'::jsonb)
    AND _baseline->'card_url' IS NOT DISTINCT FROM
      coalesce(to_jsonb(_card_url), 'null'::jsonb)
    AND _baseline->'is_discontinued' IS NOT DISTINCT FROM
      coalesce(to_jsonb(_is_discontinued), 'null'::jsonb)
    AND (
      (_updated_at IS NULL AND _baseline->'updated_at' = 'null'::jsonb)
      OR (
        _updated_at IS NOT NULL
        AND nullif(_baseline->>'updated_at', '')::timestamptz = _updated_at
      )
    );
EXCEPTION WHEN invalid_text_representation OR datetime_field_overflow THEN
  RETURN false;
END;
$$;


--
-- Name: card_catalog_effective_network(text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.card_catalog_effective_network(_network text, _card_name text, _issuer text) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
DECLARE
  column_network text := public.normalize_card_catalog_network(_network);
  name_network text := CASE
    WHEN lower(coalesce(_card_name, '')) ~ '\m(american[[:space:]]+express|amex)\M'
      THEN 'americanexpress'
    WHEN lower(coalesce(_card_name, '')) ~ '\mmaster[[:space:]]*card\M'
      THEN 'mastercard'
    WHEN lower(coalesce(_card_name, '')) ~ '\mrupay\M' THEN 'rupay'
    WHEN lower(coalesce(_card_name, '')) ~ '\mvisa\M' THEN 'visa'
    ELSE NULL END;
  issuer_network text := CASE
    WHEN lower(trim(coalesce(_issuer, ''))) = 'american express'
      THEN 'americanexpress'
    ELSE NULL END;
BEGIN
  IF column_network IS NOT NULL AND name_network IS NOT NULL
     AND column_network <> name_network THEN
    RAISE EXCEPTION 'stored_network_conflict';
  END IF;
  IF coalesce(column_network, name_network) IS NOT NULL
     AND issuer_network IS NOT NULL
     AND coalesce(column_network, name_network) <> issuer_network THEN
    RAISE EXCEPTION 'stored_network_conflict';
  END IF;
  RETURN coalesce(column_network, name_network, issuer_network);
END;
$$;


--
-- Name: card_catalog_json_contains_sensitive_url(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.card_catalog_json_contains_sensitive_url(_value jsonb) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
DECLARE
  item record;
  scalar text;
  decoded_scalar text;
  next_scalar text;
  decode_pass integer;
  ascii_code integer;
BEGIN
  IF _value IS NULL THEN RETURN false; END IF;
  IF jsonb_typeof(_value) = 'object' THEN
    FOR item IN SELECT key, value FROM jsonb_each(_value) LOOP
      IF public.card_catalog_json_contains_sensitive_url(to_jsonb(item.key))
         OR public.card_catalog_json_contains_sensitive_url(item.value) THEN
        RETURN true;
      END IF;
    END LOOP;
    RETURN false;
  ELSIF jsonb_typeof(_value) = 'array' THEN
    FOR item IN SELECT value FROM jsonb_array_elements(_value) LOOP
      IF public.card_catalog_json_contains_sensitive_url(item.value) THEN
        RETURN true;
      END IF;
    END LOOP;
    RETURN false;
  ELSIF jsonb_typeof(_value) <> 'string' THEN
    RETURN false;
  END IF;
  scalar := lower(_value #>> '{}');
  decoded_scalar := scalar;
  FOR decode_pass IN 1..8 LOOP
    next_scalar := decoded_scalar;
    FOR ascii_code IN 32..126 LOOP
      next_scalar := replace(
        next_scalar,
        '%' || lpad(to_hex(ascii_code), 2, '0'),
        chr(ascii_code)
      );
    END LOOP;
    next_scalar := replace(next_scalar, '&amp;', '&');
    EXIT WHEN next_scalar = decoded_scalar;
    decoded_scalar := next_scalar;
  END LOOP;
  RETURN decoded_scalar ~ 'https?://[^/[:space:]<>"'']+@'
    OR decoded_scalar ~ '[?&](token|session|secret|password|passwd|credential|auth|signature|sig|key|code|state|nonce)='
    OR decoded_scalar ~ 'https?://[^[:space:]<>"'']+#[^[:space:]<>"'']*'
    OR decoded_scalar ~ '%3f[^[:space:]]*(token|session|secret|password|credential|auth|signature|nonce)%3d'
    OR decoded_scalar ~ '%40[^[:space:]]*(%2f|/|%3f|\?)';
END;
$$;


--
-- Name: card_catalog_json_envelope_valid(jsonb, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.card_catalog_json_envelope_valid(_value jsonb, _depth integer DEFAULT 0) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
DECLARE
  item record;
  object_count integer;
BEGIN
  IF _value IS NULL OR _depth > 6 THEN RETURN false; END IF;
  IF jsonb_typeof(_value) = 'object' THEN
    SELECT count(*) INTO object_count FROM jsonb_object_keys(_value);
    IF object_count > 32 THEN RETURN false; END IF;
    FOR item IN SELECT key, value FROM jsonb_each(_value) LOOP
      IF octet_length(item.key) > 64
         OR NOT public.card_catalog_json_envelope_valid(item.value, _depth + 1) THEN
        RETURN false;
      END IF;
    END LOOP;
    RETURN true;
  ELSIF jsonb_typeof(_value) = 'array' THEN
    IF jsonb_array_length(_value) > 32 THEN RETURN false; END IF;
    FOR item IN SELECT value FROM jsonb_array_elements(_value) LOOP
      IF NOT public.card_catalog_json_envelope_valid(item.value, _depth + 1) THEN
        RETURN false;
      END IF;
    END LOOP;
    RETURN true;
  ELSIF jsonb_typeof(_value) = 'string' THEN
    RETURN octet_length(_value #>> '{}') <= 2048;
  END IF;
  RETURN jsonb_typeof(_value) IN ('number', 'boolean', 'null');
END;
$$;


--
-- Name: card_catalog_source_matches_issuer(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.card_catalog_source_matches_issuer(_issuer text, _url text) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
DECLARE
  normalized_issuer text := lower(trim(coalesce(_issuer, '')));
  canonical_url text;
  hostname text;
  approved_domains text[];
BEGIN
  canonical_url := public.canonical_card_resource_url(_url);
  hostname := lower(substring(canonical_url FROM '^https://([^/:?#]+)'));
  approved_domains := CASE normalized_issuer
    WHEN 'axis bank' THEN ARRAY['axis.bank.in', 'axisbank.com']
    WHEN 'hdfc bank' THEN ARRAY['hdfcbank.com', 'hdfc.bank.in']
    WHEN 'icici bank' THEN ARRAY['icicibank.com', 'icici.bank.in']
    WHEN 'kotak bank' THEN ARRAY['kotak.com', 'kotak.bank.in']
    WHEN 'indusind bank' THEN ARRAY['indusind.com', 'indusind.bank.in']
    WHEN 'hsbc' THEN ARRAY['hsbc.co.in']
    WHEN 'sbi card' THEN ARRAY['sbicard.com']
    WHEN 'idfc first bank' THEN ARRAY['idfcfirstbank.com', 'idfcfirst.bank.in']
    WHEN 'yes bank' THEN ARRAY['yesbank.in', 'yes.bank.in']
    WHEN 'au small finance bank' THEN ARRAY['aubank.in', 'au.bank.in']
    WHEN 'rbl bank' THEN ARRAY['rbl.bank', 'rblbank.com']
    WHEN 'bank of baroda' THEN ARRAY['bobfinancial.com']
    WHEN 'punjab national bank' THEN ARRAY['pnbcard.in', 'pnbindia.in']
    WHEN 'standard chartered' THEN ARRAY['sc.com']
    WHEN 'american express' THEN ARRAY['americanexpress.com']
    ELSE ARRAY[]::text[] END;
  RETURN EXISTS (
    SELECT 1 FROM unnest(approved_domains) AS approved(domain)
    WHERE hostname = approved.domain OR hostname LIKE '%.' || approved.domain
  );
END;
$$;


--
-- Name: card_enrichment_effective_terminal_status(text, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.card_enrichment_effective_terminal_status(_requested_status text, _has_pending_staging boolean) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'public', 'pg_temp'
    AS $$
  SELECT CASE
    WHEN _requested_status NOT IN (
      'staged', 'completed', 'quarantined', 'failed', 'review_required'
    ) OR _has_pending_staging IS NULL THEN NULL
    WHEN _has_pending_staging THEN 'staged'
    ELSE _requested_status
  END;
$$;


--
-- Name: card_enrichment_enqueue_catalog_eligible(uuid, text, text, text, text, text, text, boolean, boolean, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.card_enrichment_enqueue_catalog_eligible(_card_id uuid, _input_issuer text, _input_url text, _input_url_hash text, _card_bank text, _card_url text, _card_type text, _is_discontinued boolean, _has_active_cardholder boolean, _has_unresolved_identity boolean) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
DECLARE
  canonical_catalog_url text;
  canonical_input_url text;
BEGIN
  canonical_catalog_url := public.canonical_card_resource_url(_card_url);
  canonical_input_url := public.canonical_card_resource_url(_input_url);
  RETURN _card_id IS NOT NULL
    AND length(trim(coalesce(_card_bank, ''))) BETWEEN 2 AND 120
    AND lower(trim(coalesce(_input_issuer, ''))) = lower(trim(_card_bank))
    AND lower(trim(coalesce(_card_type, ''))) = 'credit'
    AND canonical_input_url = canonical_catalog_url
    AND lower(coalesce(_input_url_hash, '')) = encode(
      extensions.digest(convert_to(canonical_input_url, 'UTF8'), 'sha256'), 'hex'
    )
    AND (
      _is_discontinued IS DISTINCT FROM true
      OR _has_active_cardholder IS TRUE
    )
    AND _has_unresolved_identity IS FALSE;
EXCEPTION WHEN OTHERS THEN
  RETURN false;
END;
$$;


--
-- Name: card_enrichment_enqueue_count_is_valid(integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.card_enrichment_enqueue_count_is_valid(_requested_count integer, _inserted_count integer) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'public', 'pg_temp'
    AS $$
  SELECT _requested_count BETWEEN 1 AND 200
    AND _inserted_count BETWEEN 0 AND _requested_count;
$$;


--
-- Name: card_enrichment_final_staging_state(text, uuid, uuid, uuid, text, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.card_enrichment_final_staging_state(_requested_status text, _requested_staging_id uuid, _prior_staging_id uuid, _locked_staging_id uuid, _locked_staging_status text, _locked_staging_valid boolean) RETURNS TABLE(effective_status text, audit_staging_id uuid, has_pending_staging boolean)
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  candidate_staging_id uuid := coalesce(
    _requested_staging_id, _prior_staging_id
  );
BEGIN
  audit_staging_id := CASE
    WHEN _locked_staging_valid IS TRUE
      AND _locked_staging_id = candidate_staging_id
      AND _locked_staging_status IN ('pending', 'approved', 'rejected')
    THEN candidate_staging_id
    ELSE NULL
  END;
  has_pending_staging := audit_staging_id IS NOT NULL
    AND _locked_staging_status = 'pending';
  effective_status := CASE
    WHEN has_pending_staging THEN 'staged'
    WHEN _requested_status = 'staged' AND audit_staging_id IS NOT NULL
      THEN 'completed'
    WHEN _requested_status = 'staged' THEN 'review_required'
    ELSE _requested_status
  END;
  RETURN NEXT;
END;
$$;


--
-- Name: card_enrichment_jitter_days(uuid, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.card_enrichment_jitter_days(_card_id uuid, _radius integer) RETURNS integer
    LANGUAGE plpgsql IMMUTABLE STRICT
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  identifier_bytes bytea;
  byte_index integer;
  byte_total bigint := 0;
BEGIN
  IF _radius < 0 OR _radius > 31 THEN
    RAISE EXCEPTION 'invalid_recurrence_radius';
  END IF;
  identifier_bytes := convert_to(lower(trim(_card_id::text)), 'UTF8');
  IF length(identifier_bytes) > 0 THEN
    FOR byte_index IN 0..length(identifier_bytes) - 1 LOOP
      byte_total := byte_total + get_byte(identifier_bytes, byte_index);
    END LOOP;
  END IF;
  RETURN mod(byte_total, (2 * _radius) + 1)::integer - _radius;
END;
$$;


--
-- Name: card_enrichment_job_has_pending_staging(uuid, uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.card_enrichment_job_has_pending_staging(_staging_id uuid, _card_id uuid, _parser_version text) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'public', 'pg_temp'
    AS $$
  SELECT _staging_id IS NOT NULL AND EXISTS (
    SELECT 1
    FROM public.card_benefits_staging AS staging
    WHERE staging.id = _staging_id
      AND staging.card_id = _card_id
      AND staging.parser_version = _parser_version
      AND staging.request_type = 'official_benefit_enrichment'
      AND staging.status = 'pending'
  );
$$;


--
-- Name: card_enrichment_pilot_cohort_action(integer, integer, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.card_enrichment_pilot_cohort_action(_pilot_count integer, _promoted_count integer, _has_duplicate boolean) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'public', 'pg_temp'
    AS $$
  SELECT CASE
    WHEN _pilot_count IS NULL OR _promoted_count IS NULL
      OR _pilot_count < 0 OR _promoted_count < 0
      OR coalesce(_has_duplicate, true) THEN 'reject'
    WHEN _pilot_count = 0 AND _promoted_count = 0 THEN 'initialize'
    WHEN _pilot_count = 5 AND _promoted_count = 0 THEN 'return_pilot'
    WHEN _pilot_count = 0 AND _promoted_count = 5 THEN 'return_promoted'
    ELSE 'reject'
  END;
$$;


--
-- Name: is_valid_official_source_evidence(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_valid_official_source_evidence(_source_evidence jsonb) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'pg_catalog'
    AS $$
  SELECT CASE
    WHEN _source_evidence IS NULL THEN false
    WHEN jsonb_typeof(_source_evidence) = 'array'
      THEN jsonb_array_length(_source_evidence) > 0
    ELSE false
  END
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: card_benefits_staging; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.card_benefits_staging (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    card_id uuid,
    source_url text,
    extracted_data jsonb NOT NULL,
    status text DEFAULT 'pending'::text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    validation_version text,
    calculated_confidence numeric(5,4),
    validation_reasons jsonb DEFAULT '[]'::jsonb NOT NULL,
    validation_warnings jsonb DEFAULT '[]'::jsonb NOT NULL,
    source_evidence jsonb,
    validated_at timestamp with time zone,
    rejected_at timestamp with time zone,
    benefit_decisions jsonb DEFAULT '[]'::jsonb NOT NULL,
    reviewed_at timestamp with time zone,
    reviewed_by uuid,
    requested_by uuid,
    request_type text,
    parser_version text,
    source_url_hash text,
    content_hash text,
    CONSTRAINT card_benefits_staging_catalog_entry_shape_check CHECK (((request_type <> 'catalog_entry'::text) OR ((requested_by IS NOT NULL) AND (jsonb_typeof(extracted_data) = 'object'::text)))),
    CONSTRAINT card_benefits_staging_confidence_check CHECK (((calculated_confidence IS NULL) OR ((calculated_confidence >= (0)::numeric) AND (calculated_confidence <= (1)::numeric)))),
    CONSTRAINT card_benefits_staging_official_shape_check CHECK (((request_type <> 'official_benefit_enrichment'::text) OR ((card_id IS NOT NULL) AND (NULLIF(TRIM(BOTH FROM source_url), ''::text) IS NOT NULL) AND (NULLIF(TRIM(BOTH FROM parser_version), ''::text) IS NOT NULL) AND (NULLIF(TRIM(BOTH FROM source_url_hash), ''::text) IS NOT NULL) AND (NULLIF(TRIM(BOTH FROM content_hash), ''::text) IS NOT NULL) AND (jsonb_typeof(extracted_data) = 'object'::text) AND public.is_valid_official_source_evidence(source_evidence)))),
    CONSTRAINT card_benefits_staging_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text])))
);


--
-- Name: card_catalog_enrichment_jobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.card_catalog_enrichment_jobs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    card_id uuid NOT NULL,
    discovery_job_id uuid,
    issuer text NOT NULL,
    canonical_url text NOT NULL,
    final_url_hash text NOT NULL,
    content_hash text,
    status text DEFAULT 'queued'::text NOT NULL,
    attempt_count integer DEFAULT 0 NOT NULL,
    next_retry_at timestamp with time zone,
    normalized_fields jsonb DEFAULT '{}'::jsonb NOT NULL,
    validation_warnings jsonb DEFAULT '[]'::jsonb NOT NULL,
    failure_category text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    parser_version text DEFAULT 'benefits-v1'::text NOT NULL,
    lease_expires_at timestamp with time zone,
    lease_token uuid,
    staging_id uuid,
    run_mode text DEFAULT 'scheduled'::text NOT NULL,
    job_key text,
    result_summary jsonb DEFAULT '{}'::jsonb NOT NULL,
    next_run_at timestamp with time zone,
    CONSTRAINT card_catalog_enrichment_jobs_attempt_count_check CHECK ((attempt_count >= 0)),
    CONSTRAINT card_catalog_enrichment_jobs_canonical_url_check CHECK ((canonical_url ~ '^https://'::text)),
    CONSTRAINT card_catalog_enrichment_jobs_content_hash_check CHECK ((length(content_hash) = 64)),
    CONSTRAINT card_catalog_enrichment_jobs_final_url_hash_check CHECK ((length(final_url_hash) = 64)),
    CONSTRAINT card_catalog_enrichment_jobs_issuer_check CHECK (((length(TRIM(BOTH FROM issuer)) >= 2) AND (length(TRIM(BOTH FROM issuer)) <= 120))),
    CONSTRAINT card_catalog_enrichment_jobs_normalized_fields_check CHECK ((jsonb_typeof(normalized_fields) = 'object'::text)),
    CONSTRAINT card_catalog_enrichment_jobs_result_summary_object_check CHECK ((jsonb_typeof(result_summary) = 'object'::text)),
    CONSTRAINT card_catalog_enrichment_jobs_run_mode_check CHECK ((run_mode = ANY (ARRAY['pilot'::text, 'scheduled'::text, 'manual'::text]))),
    CONSTRAINT card_catalog_enrichment_jobs_status_check CHECK ((status = ANY (ARRAY['queued'::text, 'processing'::text, 'completed'::text, 'review_required'::text, 'failed'::text, 'staged'::text, 'quarantined'::text]))),
    CONSTRAINT card_catalog_enrichment_jobs_validation_warnings_check CHECK ((jsonb_typeof(validation_warnings) = 'array'::text))
);


--
-- Name: card_enrichment_pilot_evidence_is_qualified(public.card_catalog_enrichment_jobs, public.card_benefits_staging); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.card_enrichment_pilot_evidence_is_qualified(_job public.card_catalog_enrichment_jobs, _staging public.card_benefits_staging) RETURNS boolean
    LANGUAGE plpgsql STABLE
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $_$
DECLARE
  evidence jsonb := _job.normalized_fields->'pilot_evidence';
  verification_envelope jsonb;
  repeat_verification_envelope jsonb;
  replay_input jsonb;
  expected_source_resources jsonb;
  expected_required_source_keys jsonb;
  replay_required_source_keys jsonb;
  actual_required_source_keys jsonb;
  current_live_state jsonb;
  observed_at_value timestamptz;
  decisions jsonb;
  proposals jsonb;
  removals jsonb;
  recomputed_canonical_benefit_hash text;
  approved_count integer;
  retained_count integer;
  retired_count integer;
  rejected_count integer;
BEGIN
  current_live_state := public.card_enrichment_pilot_live_state_snapshot(_job.card_id);
  observed_at_value := public.card_enrichment_pilot_timestamp(evidence->>'observed_at');
  IF NOT (
       (_job.run_mode = 'pilot' AND public.card_enrichment_pilot_job_is_qualified(
          _job.status, _job.failure_category, _job.result_summary
        ))
       OR (_job.run_mode = 'scheduled'
         AND _job.result_summary->'pilot_qualified' = 'true'::jsonb)
     )
     OR jsonb_typeof(evidence) <> 'object'
     OR evidence->>'parser_version' IS DISTINCT FROM _job.parser_version
     OR evidence->>'job_id' IS DISTINCT FROM _job.id::text
     OR evidence->>'card_id' IS DISTINCT FROM _job.card_id::text
     OR evidence->>'run_mode' IS DISTINCT FROM 'pilot'
     OR EXISTS (
       SELECT 1 FROM jsonb_object_keys(evidence) AS key(value)
       WHERE key.value NOT IN (
         'parser_version','job_id','card_id','run_mode','canonical_hash',
         'repeat_canonical_hash','deterministic_replay_passed',
         'source_manifest_hash','source_attempts','expected_required_source_keys',
         'required_source_selection_overflow','verification_envelope',
         'repeat_verification_envelope','replay_input','crawl_complete',
         'suppressed_removal_count','unsafe_mutation_count','raw_body_stored',
         'side_effect_proof_passed','observed_at','live_state_before',
         'live_state_after','conflict_count','catalog_identity_conflict_count',
         'proposal_count','proposal_disposition','canonical_benefit_hash',
         'previous_canonical_benefit_hash','staging_id',
         'staging_content_hash'
       )
     )
     OR evidence->>'catalog_identity_conflict_count' IS DISTINCT FROM '0'
     OR evidence->>'conflict_count' IS DISTINCT FROM '0'
     OR evidence->>'suppressed_removal_count' IS DISTINCT FROM '0'
     OR evidence->>'unsafe_mutation_count' IS DISTINCT FROM '0'
     OR evidence->'crawl_complete' IS DISTINCT FROM 'true'::jsonb
     OR evidence->'raw_body_stored' IS DISTINCT FROM 'false'::jsonb
     OR evidence->'side_effect_proof_passed' IS DISTINCT FROM 'true'::jsonb
     OR evidence->'deterministic_replay_passed' IS DISTINCT FROM 'true'::jsonb
     OR evidence->'required_source_selection_overflow'
          IS DISTINCT FROM 'false'::jsonb
     OR observed_at_value IS NULL
     OR evidence->'live_state_before' IS DISTINCT FROM evidence->'live_state_after'
     OR jsonb_typeof(evidence->'live_state_before') <> 'object'
     OR (SELECT count(*) FROM jsonb_object_keys(evidence->'live_state_before')) <> 3
     OR EXISTS (
       SELECT 1
       FROM jsonb_each(evidence->'live_state_before') AS snapshot(table_name, value)
       WHERE snapshot.table_name NOT IN (
         'card_catalog','benefits','card_benefit_mapping'
       ) OR jsonb_typeof(snapshot.value) <> 'object'
         OR (SELECT count(*) FROM jsonb_object_keys(snapshot.value)) <> 2
         OR jsonb_typeof(snapshot.value->'count') <> 'number'
         OR coalesce(snapshot.value->>'count','') !~ '^[0-9]+$'
         OR (snapshot.value->>'count')::numeric > 512
         OR coalesce(snapshot.value->>'row_hash','') !~ '^[0-9a-f]{64}$'
     )
     OR jsonb_typeof(evidence->'source_attempts') <> 'array'
     OR jsonb_array_length(evidence->'source_attempts') NOT BETWEEN 1 AND 9
     OR (SELECT count(*) FROM jsonb_array_elements(evidence->'source_attempts') AS attempt(value)
         WHERE attempt.value->>'role' = 'primary') <> 1
     OR EXISTS (
       SELECT 1 FROM jsonb_array_elements(evidence->'source_attempts') AS attempt(value)
       WHERE jsonb_typeof(attempt.value) <> 'object'
          OR attempt.value->>'role' NOT IN ('primary','required_supporting','supporting')
          OR attempt.value->>'status' NOT IN ('success','not_modified','failed')
          OR EXISTS (
            SELECT 1 FROM jsonb_object_keys(attempt.value) AS key(value)
            WHERE key.value NOT IN (
              'url','role','status','httpStatus','contentHash',
              'finalResourceIdentityHash','errorCode','attemptedAt',
              'parserCacheReusable','logicalSourceKey','attemptHistory',
              'attemptHistoryOverflow'
            )
          )
          OR (attempt.value->>'status' IN ('success','not_modified') AND (
            coalesce(attempt.value->>'contentHash','') !~ '^[0-9a-f]{64}$'
            OR coalesce(attempt.value->>'logicalSourceKey','') !~ '^[0-9a-f]{64}$'
            OR coalesce(attempt.value->>'finalResourceIdentityHash','') !~ '^[0-9a-f]{64}$'
          ))
          OR (attempt.value->>'status' = 'not_modified'
            AND attempt.value->'parserCacheReusable' IS DISTINCT FROM 'true'::jsonb)
          OR (attempt.value ? 'parserCacheReusable' AND
            jsonb_typeof(attempt.value->'parserCacheReusable') <> 'boolean')
          OR public.card_enrichment_pilot_timestamp(
            attempt.value->>'attemptedAt'
          ) IS NULL
          OR public.card_enrichment_pilot_timestamp(
            attempt.value->>'attemptedAt'
          ) > observed_at_value + interval '5 minutes'
          OR (attempt.value ? 'httpStatus' AND (
            jsonb_typeof(attempt.value->'httpStatus') <> 'number'
            OR coalesce(attempt.value->>'httpStatus','') !~ '^[0-9]+$'
            OR (attempt.value->>'httpStatus')::integer NOT BETWEEN 100 AND 599
          ))
          OR (attempt.value ? 'attemptHistory' AND (
            jsonb_typeof(attempt.value->'attemptHistory') <> 'array'
            OR jsonb_array_length(attempt.value->'attemptHistory') > 6
          ))
          OR (attempt.value->>'role' IN ('primary','required_supporting')
            AND attempt.value->>'status' NOT IN ('success','not_modified'))
          OR (attempt.value ? 'attemptHistoryOverflow' AND
            jsonb_typeof(attempt.value->'attemptHistoryOverflow') <> 'boolean')
          OR attempt.value->'attemptHistoryOverflow' = 'true'::jsonb
          OR EXISTS (
            -- Devanagari and Latin action-subject spans must match one exact
            -- authoritative issuer/product phrase; partial words never do.
            SELECT 1
            FROM jsonb_array_elements(CASE
              WHEN jsonb_typeof(attempt.value->'attemptHistory') = 'array'
              THEN attempt.value->'attemptHistory' ELSE '[]'::jsonb END
            ) AS history(value)
            WHERE jsonb_typeof(history.value) <> 'object'
               OR history.value->>'status' NOT IN ('success','not_modified','failed')
               OR public.card_enrichment_pilot_timestamp(
                 history.value->>'attemptedAt'
               ) IS NULL
               OR public.card_enrichment_pilot_timestamp(
                 history.value->>'attemptedAt'
               ) > observed_at_value + interval '5 minutes'
               OR (history.value ? 'httpStatus' AND (
                 jsonb_typeof(history.value->'httpStatus') <> 'number'
                 OR coalesce(history.value->>'httpStatus','') !~ '^[0-9]+$'
                 OR (history.value->>'httpStatus')::integer NOT BETWEEN 100 AND 599
               ))
               OR EXISTS (
                 SELECT 1 FROM jsonb_object_keys(history.value) AS key(value)
                 WHERE key.value NOT IN (
                   'status','httpStatus','errorCode',
                   'finalResourceIdentityHash','attemptedAt'
                 )
               )
          )
     )
     OR (SELECT attempt.value->>'logicalSourceKey'
         FROM jsonb_array_elements(evidence->'source_attempts') AS attempt(value)
         WHERE attempt.value->>'role' = 'primary') IS DISTINCT FROM
           public.card_enrichment_pilot_source_identity_hash(_job.canonical_url)
     OR EXISTS (
       SELECT attempt.value->>'logicalSourceKey'
       FROM jsonb_array_elements(evidence->'source_attempts') AS attempt(value)
       WHERE attempt.value->>'role' = 'required_supporting'
       GROUP BY attempt.value->>'logicalSourceKey'
       HAVING count(*) <> 1
     )
     OR evidence->>'source_manifest_hash' IS DISTINCT FROM
          public.card_enrichment_pilot_source_manifest_hash(evidence->'source_attempts')
     OR public.card_has_unresolved_catalog_identity(_job.card_id, _job.canonical_url)
  THEN RETURN false; END IF;

  replay_input := evidence->'replay_input';
  IF jsonb_typeof(replay_input) <> 'object'
     OR (SELECT count(*) FROM jsonb_object_keys(replay_input)) <> 3
     OR replay_input->'version' IS DISTINCT FROM '3'::jsonb
     OR jsonb_typeof(replay_input->'context') <> 'object'
     OR (SELECT count(*) FROM jsonb_object_keys(replay_input->'context')) <> 3
     OR replay_input->'context'->>'issuer' IS DISTINCT FROM _job.issuer
     OR length(replay_input->'context'->>'issuer') NOT BETWEEN 1 AND 128
     OR replay_input->'context'->>'primary_source_url' !~
       '^https://[^/@?#]+(?:/[^?#]*)?$'
     OR replay_input->'context'->>'primary_source_url' IS DISTINCT FROM
       public.card_enrichment_pilot_queryless_display_url(_job.canonical_url)
     OR jsonb_typeof(replay_input->'context'->'identity_labels') <> 'array'
     OR jsonb_array_length(replay_input->'context'->'identity_labels')
       NOT BETWEEN 1 AND 8
     OR EXISTS (
       SELECT 1
       FROM jsonb_array_elements(replay_input->'context'->'identity_labels')
         AS label(value)
       WHERE jsonb_typeof(label.value) <> 'string'
          OR length(label.value #>> '{}') NOT BETWEEN 1 AND 128
     )
     OR replay_input->'context'->'identity_labels'->>0 IS DISTINCT FROM (
       SELECT regexp_replace(trim(catalog.card_name), '\s+', ' ', 'g')
       FROM public.card_catalog AS catalog
       WHERE catalog.id = _job.card_id
     )
     OR EXISTS (
       SELECT 1
       FROM jsonb_array_elements_text(
         replay_input->'context'->'identity_labels'
       ) AS label(value)
       WHERE NOT EXISTS (
         SELECT 1 FROM (
           SELECT regexp_replace(trim(catalog.card_name), '\s+', ' ', 'g')
             AS allowed_label
           FROM public.card_catalog AS catalog
           WHERE catalog.id = _job.card_id
           UNION
           SELECT regexp_replace(trim(
             catalog.card_name || ' ' || coalesce(catalog.network, '')
           ), '\s+', ' ', 'g')
           FROM public.card_catalog AS catalog
           WHERE catalog.id = _job.card_id
           UNION
           SELECT regexp_replace(trim(alias.alias), '\s+', ' ', 'g')
           FROM public.card_catalog_aliases AS alias
           WHERE alias.card_id = _job.card_id
         ) AS authoritative
         WHERE authoritative.allowed_label = label.value
       )
     )
     OR jsonb_typeof(replay_input->'documents') <> 'array'
     OR jsonb_array_length(replay_input->'documents') NOT BETWEEN 1 AND 9
     OR octet_length(convert_to(
       public.canonical_json_text(replay_input), 'UTF8'
     )) > 1048576
     OR EXISTS (
       SELECT 1
       FROM jsonb_array_elements(replay_input->'documents') AS document(value)
       WHERE jsonb_typeof(document.value) <> 'object'
          OR (SELECT count(*) FROM jsonb_object_keys(document.value)) <> 13
          OR document.value->>'requested_source_url' !~
            '^https://[^/@?#]+(?:/[^?#]*)?$'
          OR document.value->>'final_source_url' !~
            '^https://[^/@?#]+(?:/[^?#]*)?$'
          OR public.card_enrichment_pilot_source_identity_hash(
               document.value->>'requested_resource_url'
             ) IS NULL
          OR public.card_enrichment_pilot_source_identity_hash(
               document.value->>'final_resource_url'
             ) IS NULL
          OR public.card_enrichment_pilot_queryless_display_url(
               document.value->>'requested_resource_url'
             ) IS DISTINCT FROM document.value->>'requested_source_url'
          OR public.card_enrichment_pilot_queryless_display_url(
               document.value->>'final_resource_url'
             ) IS DISTINCT FROM document.value->>'final_source_url'
          OR coalesce(document.value->>'requested_resource_identity_hash','')
            !~ '^[0-9a-f]{64}$'
          OR coalesce(document.value->>'final_resource_identity_hash','')
            !~ '^[0-9a-f]{64}$'
          OR public.card_enrichment_pilot_source_identity_hash(
               document.value->>'requested_resource_url'
             ) IS DISTINCT FROM
               document.value->>'requested_resource_identity_hash'
          OR public.card_enrichment_pilot_source_identity_hash(
               document.value->>'final_resource_url'
             ) IS DISTINCT FROM document.value->>'final_resource_identity_hash'
          OR coalesce(document.value->>'content_hash','')
            !~ '^[0-9a-f]{64}$'
          OR jsonb_typeof(document.value->'public_text') <> 'string'
          OR octet_length(convert_to(document.value->>'public_text','UTF8'))
            NOT BETWEEN 1 AND 65536
          OR jsonb_typeof(document.value->'fact_count') <> 'number'
          OR coalesce(document.value->>'fact_count','') !~ '^[0-9]+$'
          OR (document.value->>'fact_count')::integer NOT BETWEEN 1 AND 256
          OR (document.value->>'fact_count')::integer IS DISTINCT FROM
            cardinality(string_to_array(document.value->>'public_text', E'\n'))
          OR EXISTS (
            SELECT 1
            FROM unnest(string_to_array(
              document.value->>'public_text', E'\n'
            )) AS fact(value)
            WHERE octet_length(convert_to(fact.value, 'UTF8')) > 4096
          )
          OR document.value->'fact_overflow' IS DISTINCT FROM 'false'::jsonb
          OR document.value->'privacy_normalized' IS DISTINCT FROM 'true'::jsonb
          -- Edge emits NFKD-normalized facts. Fullwidth Unicode and combining
          -- forms, digit-script variants, zero-widths, and confusables must
          -- never survive into a forged database replay envelope. This is the
          -- SQL fail-closed mirror for U+200B/U+200C/U+200D/U+2060/U+FEFF and
          -- fullwidth Unicode U+FF10-U+FF19 input after bounded Edge decoding.
          OR document.value->>'public_text' IS DISTINCT FROM
            normalize(document.value->>'public_text', NFKD)
          -- Residual percent or named HTML entity material is never a
          -- privacy-safe normalized replay fact.
          OR document.value->>'public_text' ~*
            '%(25)*[0-9a-f]{2}|&(?:#x?[0-9a-f]+|[a-z][a-z0-9]{1,31});?'
          OR position(chr(8203) IN document.value->>'public_text') > 0
          OR position(chr(8204) IN document.value->>'public_text') > 0
          OR position(chr(8205) IN document.value->>'public_text') > 0
          OR position(chr(8288) IN document.value->>'public_text') > 0
          OR position(chr(65279) IN document.value->>'public_text') > 0
          OR EXISTS (
            -- Fail closed on every residual Unicode decimal-digit range.
            SELECT 1
            FROM regexp_split_to_table(
              document.value->>'public_text', ''
            ) AS residual_unicode_digit(character)
            CROSS JOIN unnest(ARRAY[
              1632,1776,1984,2406,2534,2662,2790,2918,3046,3174,
              3302,3430,3558,3664,3792,3872,4160,4240,6112,6160,
              6470,6608,6784,6800,6992,7088,7232,7248,42528,43216,
              43264,43472,43504,43600,44016,65296,66720,68912,69734,
              69872,69942,70096,70384,70736,70864,71248,71360,71472,
              71904,72016,72784,73040,73120,73552,92768,92864,93008,
              120782,120792,120802,120812,120822,123200,123632,124144,
              125264
            ]) AS digit_zero(codepoint)
            WHERE ascii(residual_unicode_digit.character)
              BETWEEN digit_zero.codepoint AND digit_zero.codepoint + 9
          )
          OR document.value->>'public_text' ~ '[ΑΒΕΖΗΙΚΜΝΟΡΤΥΧαβεικνορτυχАВЕКМНОРСТХУІаеіјорсху]'
          OR document.value->>'public_text' ~*
            '[a-z0-9._%+\-]+@[a-z0-9.\-]+\.[a-z]{2,}'
          OR document.value->>'public_text' ~
            '(^|[^[:alnum:]+])\+?([0-9][() .-]*){10,}([^[:alnum:]]|$)'
          OR document.value->>'public_text' ~
            '\m[A-Z]{5}[0-9]{4}[A-Z]\M'
          OR document.value->>'public_text' ~
            '\m[Nn]ame[[:space:]]*[:=#-][[:space:]]*[A-Z][a-z]{2,}([[:space:]]+[A-Z][a-z]{2,}){0,3}\M'
          OR document.value->>'public_text' ~*
            '(customer|account|card|payment|pan|phone|mobile)[[:space:]]*((name|number|no\.?|id)[[:space:]]*[:=#-]|[:=#])[[:space:]]*[^,;.[:space:]][^,;.]{1,127}'
          OR EXISTS (
            SELECT 1
            FROM regexp_matches(
              lower(document.value->>'public_text'),
              '^([a-zऀ-ॿ][a-zऀ-ॿ'' -]{2,127})[[:space:]]+((gets?|receives?)\M|will[[:space:]]+(call|contact)\M|is[[:space:]]+the[[:space:]]+(customer|cardholder|member)\M)',
              'gn'
            ) AS personal(match)
            WHERE trim(lower(personal.match[1])) NOT IN (
              'applicant','applicants','cardholder','cardholders',
              'customer','customers','member','members','user','users',
              'cashback','card'
            )
              AND NOT EXISTS (
                SELECT 1 FROM (
                  SELECT replay_input->'context'->>'issuer' AS value
                  UNION ALL
                  SELECT label.value
                  FROM jsonb_array_elements_text(
                    replay_input->'context'->'identity_labels'
                  ) AS label(value)
                ) AS exact_identity_phrase
                WHERE trim(lower(exact_identity_phrase.value)) =
                  trim(lower(personal.match[1]))
              )
          )
          OR public.card_enrichment_pilot_has_contextual_person(
            document.value->>'public_text',
            jsonb_build_array(replay_input->'context'->>'issuer') ||
              replay_input->'context'->'identity_labels'
          )
          OR jsonb_typeof(document.value->'hyperlinks') <> 'array'
          OR jsonb_array_length(document.value->'hyperlinks') > 8
          OR document.value->'hyperlink_overflow' IS DISTINCT FROM 'false'::jsonb
          OR EXISTS (
            SELECT 1
            FROM jsonb_array_elements(document.value->'hyperlinks') AS link(value)
            WHERE jsonb_typeof(link.value) <> 'object'
               OR (SELECT count(*) FROM jsonb_object_keys(link.value)) <> 5
               OR link.value->>'href' !~ '^https://[^/@?#]+(?:/[^?#]*)?$'
               OR public.card_enrichment_pilot_source_identity_hash(
                    link.value->>'resource_url'
                  ) IS NULL
               OR public.card_enrichment_pilot_queryless_display_url(
                    link.value->>'resource_url'
                  ) IS DISTINCT FROM link.value->>'href'
               OR length(coalesce(link.value->>'anchor_text','')) > 96
               OR link.value->>'anchor_text' !~
                 '^(|curated exact source|most important terms( and conditions)?|terms?( and conditions)?|conditions?|mitc|fees?|charges?|benefits?|rewards?|supporting (material|document))$'
               OR coalesce(link.value->>'resource_identity_hash','')
                 !~ '^[0-9a-f]{64}$'
               OR public.card_enrichment_pilot_source_identity_hash(
                    link.value->>'resource_url'
                  ) IS DISTINCT FROM link.value->>'resource_identity_hash'
               OR link.value->>'query_policy' IS DISTINCT FROM 'functional_only'
          )
          OR EXISTS (
            SELECT 1 FROM jsonb_object_keys(document.value) AS key(value)
            WHERE key.value NOT IN (
              'requested_source_url','final_source_url',
              'requested_resource_url','final_resource_url',
              'requested_resource_identity_hash','final_resource_identity_hash',
              'content_hash','public_text','fact_count','fact_overflow',
              'privacy_normalized','hyperlinks','hyperlink_overflow'
            )
          )
     )
     OR EXISTS (
       SELECT 1
       FROM jsonb_array_elements(replay_input->'documents') AS document(value)
       WHERE NOT EXISTS (
         SELECT 1
         FROM jsonb_array_elements(evidence->'source_attempts') AS attempt(value)
         WHERE attempt.value->>'url' = document.value->>'final_source_url'
           AND attempt.value->>'logicalSourceKey' =
                 document.value->>'requested_resource_identity_hash'
           AND attempt.value->>'finalResourceIdentityHash' =
                 document.value->>'final_resource_identity_hash'
           AND attempt.value->>'contentHash' = document.value->>'content_hash'
           AND attempt.value->>'status' IN ('success','not_modified')
       )
     )
     OR EXISTS (
       SELECT 1
       FROM jsonb_array_elements(replay_input->'documents') AS document(value)
       CROSS JOIN LATERAL jsonb_array_elements(document.value->'hyperlinks')
         AS link(value)
       WHERE NOT EXISTS (
         SELECT 1
         FROM jsonb_array_elements(evidence->'source_attempts') AS attempt(value)
         WHERE attempt.value->>'url' = link.value->>'href'
           AND attempt.value->>'logicalSourceKey' =
                 link.value->>'resource_identity_hash'
       ) AND NOT EXISTS (
         SELECT 1
         FROM jsonb_array_elements(replay_input->'documents')
           AS linked_document(value)
         WHERE linked_document.value->>'requested_source_url' =
                 link.value->>'href'
           AND linked_document.value->>'requested_resource_url' =
                 link.value->>'resource_url'
           AND linked_document.value->>'requested_resource_identity_hash' =
                 link.value->>'resource_identity_hash'
       )
     )
  THEN RETURN false; END IF;

  -- Recompute the required-source set from retained classifier inputs. This
  -- deliberately does not read the worker's expected set.
  SELECT coalesce(jsonb_agg(to_jsonb(
    required.source_key
  ) ORDER BY required.source_key), '[]'::jsonb)
  INTO replay_required_source_keys
  FROM (
    SELECT DISTINCT public.card_enrichment_pilot_source_identity_hash(
      link.value->>'resource_url'
    ) AS source_key
    FROM jsonb_array_elements(replay_input->'documents') AS document(value)
    CROSS JOIN LATERAL jsonb_array_elements(document.value->'hyperlinks')
      AS link(value)
    WHERE link.value->>'resource_url' ~*
      '(^|[/?=&_.-])(terms?|conditions?|mitc|fees?|charges?)(?:$|[/?=&_.-])'
       OR link.value->>'anchor_text' ~*
      '\m(most[[:space:]]+important[[:space:]]+terms|terms?|conditions?|mitc|fees?|charges?|curated[[:space:]]+exact[[:space:]]+source)\M'
  ) AS required;
  expected_required_source_keys := evidence->'expected_required_source_keys';
  SELECT coalesce(jsonb_agg(required.source_key ORDER BY required.source_key), '[]'::jsonb)
    INTO actual_required_source_keys
  FROM (
    SELECT DISTINCT attempt.value->>'logicalSourceKey' AS source_key
    FROM jsonb_array_elements(evidence->'source_attempts') AS attempt(value)
    WHERE attempt.value->>'role' = 'required_supporting'
  ) AS required;
  IF jsonb_typeof(expected_required_source_keys) <> 'array'
     OR jsonb_array_length(expected_required_source_keys) > 8
     OR EXISTS (
       SELECT 1 FROM jsonb_array_elements(expected_required_source_keys)
         WITH ORDINALITY AS required(value, ordinality)
       WHERE jsonb_typeof(required.value) <> 'string'
          OR trim(BOTH '"' FROM required.value::text) !~ '^[0-9a-f]{64}$'
          OR (required.ordinality > 1 AND trim(BOTH '"' FROM required.value::text) <= (
            SELECT trim(BOTH '"' FROM prior.value::text)
            FROM jsonb_array_elements(expected_required_source_keys)
              WITH ORDINALITY AS prior(value, ordinality)
            WHERE prior.ordinality = required.ordinality - 1
          ))
     )
     OR expected_required_source_keys IS DISTINCT FROM replay_required_source_keys
     OR replay_required_source_keys IS DISTINCT FROM actual_required_source_keys
  THEN RETURN false; END IF;

  verification_envelope := evidence->'verification_envelope';
  repeat_verification_envelope := evidence->'repeat_verification_envelope';
  SELECT jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'url', attempt.value->'url', 'role', attempt.value->'role',
      'status', attempt.value->'status', 'http_status', attempt.value->'httpStatus',
      'content_hash', attempt.value->'contentHash',
      'logical_source_key', attempt.value->'logicalSourceKey',
      'final_resource_identity_hash', attempt.value->'finalResourceIdentityHash',
      'error_code', attempt.value->'errorCode'
    )) ORDER BY attempt.ordinality)
    INTO expected_source_resources
  FROM jsonb_array_elements(evidence->'source_attempts')
    WITH ORDINALITY AS attempt(value, ordinality);
  IF jsonb_typeof(verification_envelope) <> 'object'
     OR jsonb_typeof(repeat_verification_envelope) <> 'object'
     OR verification_envelope IS DISTINCT FROM repeat_verification_envelope
     OR (SELECT count(*) FROM jsonb_object_keys(verification_envelope)) <> 11
     OR EXISTS (
       SELECT 1 FROM jsonb_object_keys(verification_envelope) AS key(value)
       WHERE key.value NOT IN (
         'parser_version','job_id','card_id','run_mode','source_manifest_hash',
         'source_resources','retained_documents','expected_required_source_keys',
         'required_source_selection_overflow','replay_input_hash',
         'canonical_proposals'
       )
     )
     OR octet_length(convert_to(
          public.canonical_json_text(verification_envelope), 'UTF8'
        )) > 262144
     OR jsonb_typeof(verification_envelope->'retained_documents') <> 'array'
     OR jsonb_array_length(verification_envelope->'retained_documents') > 9
     OR verification_envelope->'source_resources' IS DISTINCT FROM expected_source_resources
     OR verification_envelope->'expected_required_source_keys'
          IS DISTINCT FROM expected_required_source_keys
     OR verification_envelope->'required_source_selection_overflow'
          IS DISTINCT FROM 'false'::jsonb
     OR verification_envelope->>'replay_input_hash' IS DISTINCT FROM encode(
       extensions.digest(
         convert_to(public.canonical_json_text(replay_input), 'UTF8'), 'sha256'
       ), 'hex'
     )
     OR jsonb_array_length(verification_envelope->'retained_documents') <>
        (SELECT count(*) FROM jsonb_array_elements(expected_source_resources) AS resource(value)
         WHERE resource.value->>'status' IN ('success', 'not_modified')
           AND resource.value ? 'content_hash')
     OR EXISTS (
       SELECT 1 FROM jsonb_array_elements(verification_envelope->'retained_documents') AS document(value)
       WHERE jsonb_typeof(document.value) <> 'object'
          OR (SELECT count(*) FROM jsonb_object_keys(document.value)) <> 5
          OR coalesce(document.value->>'requested_resource_identity_hash', '') !~ '^[0-9a-f]{64}$'
          OR coalesce(document.value->>'final_resource_identity_hash', '') !~ '^[0-9a-f]{64}$'
          OR coalesce(document.value->>'content_hash', '') !~ '^[0-9a-f]{64}$'
          OR coalesce(document.value->>'document_text_hash', '') !~ '^[0-9a-f]{64}$'
          OR jsonb_typeof(document.value->'document_bytes') <> 'number'
          OR coalesce(document.value->>'document_bytes', '') !~ '^[0-9]+$'
          OR (document.value->>'document_bytes')::numeric > 1048576
          OR NOT EXISTS (
            SELECT 1 FROM jsonb_array_elements(expected_source_resources) AS resource(value)
            WHERE resource.value->>'logical_source_key' = document.value->>'requested_resource_identity_hash'
              AND resource.value->>'final_resource_identity_hash' = document.value->>'final_resource_identity_hash'
              AND resource.value->>'content_hash' = document.value->>'content_hash'
              AND resource.value->>'status' IN ('success', 'not_modified')
          )
     )
     OR EXISTS (
       SELECT 1
       FROM jsonb_array_elements(verification_envelope->'retained_documents')
         AS document(value)
       GROUP BY public.canonical_json_text(document.value)
       HAVING count(*) <> 1
     )
     OR EXISTS (
       SELECT 1 FROM jsonb_array_elements(expected_source_resources) AS resource(value)
       WHERE resource.value->>'status' IN ('success','not_modified')
         AND resource.value ? 'content_hash'
         AND (SELECT count(*)
              FROM jsonb_array_elements(verification_envelope->'retained_documents')
                AS document(value)
              WHERE document.value->>'requested_resource_identity_hash' =
                      resource.value->>'logical_source_key'
                AND document.value->>'final_resource_identity_hash' =
                      resource.value->>'final_resource_identity_hash'
                    AND document.value->>'content_hash' = resource.value->>'content_hash') <> 1
     )
     OR EXISTS (
       SELECT 1 FROM jsonb_array_elements(replay_input->'documents') AS input(value)
       WHERE (SELECT count(*)
         FROM jsonb_array_elements(verification_envelope->'retained_documents')
           AS retained(value)
         WHERE retained.value->>'requested_resource_identity_hash' =
                 input.value->>'requested_resource_identity_hash'
           AND retained.value->>'final_resource_identity_hash' =
                 input.value->>'final_resource_identity_hash'
           AND retained.value->>'content_hash' = input.value->>'content_hash'
           AND retained.value->>'document_text_hash' = encode(
             extensions.digest(
               convert_to(input.value->>'public_text','UTF8'), 'sha256'
             ), 'hex'
           )
           AND (retained.value->>'document_bytes')::integer =
             octet_length(convert_to(input.value->>'public_text','UTF8'))
       ) <> 1
     )
     OR evidence->>'canonical_hash' IS DISTINCT FROM encode(
          extensions.digest(convert_to(public.canonical_json_text(verification_envelope), 'UTF8'), 'sha256'), 'hex'
        )
     OR evidence->>'repeat_canonical_hash' IS DISTINCT FROM encode(
          extensions.digest(convert_to(public.canonical_json_text(repeat_verification_envelope), 'UTF8'), 'sha256'), 'hex'
        )
     OR evidence->>'canonical_hash' IS DISTINCT FROM evidence->>'repeat_canonical_hash'
     OR verification_envelope->>'job_id' IS DISTINCT FROM _job.id::text
     OR verification_envelope->>'card_id' IS DISTINCT FROM _job.card_id::text
     OR verification_envelope->>'parser_version' IS DISTINCT FROM _job.parser_version
     OR verification_envelope->>'run_mode' IS DISTINCT FROM 'pilot'
     OR verification_envelope->>'source_manifest_hash' IS DISTINCT FROM evidence->>'source_manifest_hash'
  THEN RETURN false; END IF;

  proposals := verification_envelope->'canonical_proposals';
  IF jsonb_typeof(proposals) <> 'array' OR EXISTS (
    SELECT 1 FROM jsonb_array_elements(proposals) AS proposal(value)
    WHERE jsonb_typeof(proposal.value) <> 'object'
       OR coalesce(
         proposal.value->>'conditionHash', proposal.value->>'dedupeKey', ''
       ) = ''
  ) THEN RETURN false; END IF;
  SELECT encode(extensions.digest(convert_to(coalesce(string_agg(
    coalesce(proposal.value->>'conditionHash', proposal.value->>'dedupeKey'),
    E'\n' ORDER BY coalesce(
      proposal.value->>'conditionHash', proposal.value->>'dedupeKey'
    )
  ), ''), 'UTF8'), 'sha256'), 'hex')
  INTO recomputed_canonical_benefit_hash
  FROM jsonb_array_elements(proposals) AS proposal(value);
  IF jsonb_typeof(proposals) <> 'array' OR jsonb_array_length(proposals) > 256
     OR proposals IS DISTINCT FROM repeat_verification_envelope->'canonical_proposals'
     OR (evidence->>'proposal_count')::integer IS DISTINCT FROM jsonb_array_length(proposals)
     OR evidence->>'proposal_disposition' NOT IN (
       'no_change','material','removal_review'
     )
     OR evidence->>'canonical_benefit_hash' IS DISTINCT FROM
       recomputed_canonical_benefit_hash
     OR jsonb_typeof(evidence->'previous_canonical_benefit_hash') IS NULL
     OR jsonb_typeof(evidence->'previous_canonical_benefit_hash')
       NOT IN ('null','string')
     OR (jsonb_typeof(evidence->'previous_canonical_benefit_hash') = 'string'
       AND evidence->>'previous_canonical_benefit_hash' !~ '^[0-9a-f]{64}$')
     OR (_job.run_mode = 'pilot' AND
       (_job.result_summary->>'proposals')::integer IS DISTINCT FROM
         jsonb_array_length(proposals))
  THEN RETURN false; END IF;

  IF evidence->>'proposal_disposition' = 'no_change' THEN
    RETURN evidence->'staging_id' = 'null'::jsonb
      AND evidence->'staging_content_hash' = 'null'::jsonb
      AND (_job.run_mode = 'scheduled' OR _job.staging_id IS NULL)
      AND (
        evidence->>'previous_canonical_benefit_hash' =
          recomputed_canonical_benefit_hash
        OR (
          evidence->'previous_canonical_benefit_hash' = 'null'::jsonb
          AND jsonb_array_length(proposals) = 0
          AND (current_live_state->'benefits'->>'count')::integer = 0
          AND (current_live_state->'card_benefit_mapping'->>'count')::integer = 0
        )
      )
      AND (_job.run_mode = 'scheduled' OR
        current_live_state IS NOT DISTINCT FROM evidence->'live_state_after')
      AND (_job.run_mode = 'scheduled'
        OR _job.result_summary->'successful_no_change' = 'true'::jsonb);
  END IF;
  IF _staging.id IS NULL
     OR _staging.id::text IS DISTINCT FROM evidence->>'staging_id'
     OR (_job.run_mode = 'pilot' AND _job.staging_id IS DISTINCT FROM _staging.id)
     OR _staging.card_id IS DISTINCT FROM _job.card_id
     OR _staging.parser_version IS DISTINCT FROM _job.parser_version
     OR _staging.content_hash IS DISTINCT FROM evidence->>'staging_content_hash'
     OR _staging.status IS DISTINCT FROM 'approved'
     OR _staging.extracted_data->'proposals' IS DISTINCT FROM proposals
     OR _staging.extracted_data->'retained_documents' IS DISTINCT FROM
          verification_envelope->'retained_documents'
     OR jsonb_typeof(_staging.extracted_data->'review_pre_live_state') <> 'object'
     OR _staging.extracted_data->'review_pre_live_state' IS DISTINCT FROM
          evidence->'live_state_after'
     OR jsonb_typeof(_staging.extracted_data->'published_live_state') <> 'object'
     OR (_job.run_mode = 'pilot' AND
       _staging.extracted_data->'published_live_state' IS DISTINCT FROM
         current_live_state)
  THEN RETURN false; END IF;

  decisions := _staging.benefit_decisions;
  removals := coalesce(_staging.extracted_data->'diff'->'possibleRemovals', '[]'::jsonb);
  IF jsonb_typeof(decisions) <> 'array' OR jsonb_array_length(decisions) > 64
     OR jsonb_typeof(removals) <> 'array'
     OR jsonb_array_length(decisions) <>
          jsonb_array_length(proposals) + jsonb_array_length(removals)
     OR EXISTS (
       SELECT 1 FROM jsonb_array_elements(decisions) AS decision(value)
       WHERE decision.value->>'action' NOT IN ('approve','edit','reject','retire','keep_existing')
          OR jsonb_typeof(decision.value->'reviewed_at') <> 'string'
          OR public.card_enrichment_pilot_timestamp(
            decision.value->>'reviewed_at'
          ) IS NULL
          OR public.card_enrichment_pilot_timestamp(
            decision.value->>'reviewed_at'
          ) < observed_at_value - interval '5 minutes'
     )
     OR EXISTS (
       SELECT 1 FROM jsonb_array_elements(decisions) AS decision(value)
       WHERE decision.value->>'action' IN ('approve','edit') AND (
         NOT (decision.value ? 'proposal_index')
         OR NOT (decision.value ? 'benefit_id')
         OR ((decision.value->>'proposal_index')) !~ '^[0-9]+$'
         OR ((decision.value->>'proposal_index'))::integer >= jsonb_array_length(proposals)
         OR coalesce((decision.value->>'benefit_id'),'') !~
           '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
         OR decision.value->>'dedupe_key' IS DISTINCT FROM
           proposals->(((decision.value->>'proposal_index'))::integer)->>'dedupeKey'
         OR decision.value->>'condition_hash' IS DISTINCT FROM
           proposals->(((decision.value->>'proposal_index'))::integer)->>'conditionHash'
       )
     )
     OR EXISTS (
       SELECT 1 FROM jsonb_array_elements(decisions) AS decision(value)
       WHERE decision.value->>'action' = 'reject' AND (
         (decision.value ? 'proposal_index') = (decision.value ? 'benefit_id')
         OR ((decision.value ? 'proposal_index') AND (
           ((decision.value->>'proposal_index')) !~ '^[0-9]+$'
           OR ((decision.value->>'proposal_index'))::integer >= jsonb_array_length(proposals)
           OR decision.value->>'dedupe_key' IS DISTINCT FROM
             proposals->(((decision.value->>'proposal_index'))::integer)->>'dedupeKey'
           OR decision.value->>'condition_hash' IS DISTINCT FROM
             proposals->(((decision.value->>'proposal_index'))::integer)->>'conditionHash'
         ))
         OR ((decision.value ? 'benefit_id') AND (
           coalesce((decision.value->>'benefit_id'),'') !~
             '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
           OR (SELECT count(*) FROM (
             SELECT 'benefit' AS target
             FROM jsonb_array_elements(removals) AS removal(value)
             WHERE coalesce(
               removal.value->'benefit'->>'liveBenefitId',
               removal.value->'benefit'->>'benefitId',
               removal.value->'benefit'->>'dedupeKey'
             ) = (decision.value->>'benefit_id')
             UNION ALL
             SELECT 'proposal:' || (proposal.ordinality - 1)::text
             FROM (
               SELECT item.value->'current' AS current,
                      item.value->'proposed' AS proposed
               FROM jsonb_array_elements(coalesce(
                 _staging.extracted_data->'diff'->'modifications', '[]'::jsonb
               )) AS item(value)
               UNION ALL
               SELECT item.value->'current', item.value->'proposed'
               FROM jsonb_array_elements(coalesce(
                 _staging.extracted_data->'diff'->'unchanged', '[]'::jsonb
               )) AS item(value)
             ) AS pair
             JOIN jsonb_array_elements(proposals) WITH ORDINALITY
               AS proposal(value, ordinality)
               ON public.canonical_json_text(proposal.value) =
                  public.canonical_json_text(pair.proposed)
             WHERE coalesce(
               pair.current->>'liveBenefitId', pair.current->>'benefitId',
               pair.current->>'dedupeKey'
             ) = (decision.value->>'benefit_id')
           ) AS exact_target) <> 1
         ))
       )
     )
     OR EXISTS (
       SELECT 1 FROM jsonb_array_elements(decisions) AS decision(value)
       WHERE decision.value->>'action' = 'retire' AND (
         decision.value ? 'proposal_index'
         OR NOT (decision.value ? 'benefit_id')
         OR coalesce((decision.value->>'benefit_id'),'') !~
           '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
         OR NOT EXISTS (
           SELECT 1 FROM jsonb_array_elements(removals) AS removal(value)
           WHERE coalesce(
             removal.value->'benefit'->>'liveBenefitId',
             removal.value->'benefit'->>'benefitId',
             removal.value->'benefit'->>'dedupeKey'
           ) = (decision.value->>'benefit_id')
         )
       )
     )
     OR EXISTS (
       SELECT 1 FROM jsonb_array_elements(decisions) AS decision(value)
       WHERE decision.value->>'action' = 'keep_existing' AND (
         decision.value ? 'proposal_index'
         OR NOT (decision.value ? 'benefit_id')
         OR coalesce((decision.value->>'benefit_id'),'') !~
           '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
         OR (SELECT count(*) FROM (
           SELECT 'benefit' AS target
           FROM jsonb_array_elements(removals) AS removal(value)
           WHERE coalesce(
             removal.value->'benefit'->>'liveBenefitId',
             removal.value->'benefit'->>'benefitId',
             removal.value->'benefit'->>'dedupeKey'
           ) = (decision.value->>'benefit_id')
           UNION ALL
           SELECT 'proposal:' || (proposal.ordinality - 1)::text
           FROM (
             SELECT item.value->'current' AS current,
                    item.value->'proposed' AS proposed
             FROM jsonb_array_elements(coalesce(
               _staging.extracted_data->'diff'->'modifications', '[]'::jsonb
             )) AS item(value)
             UNION ALL
             SELECT item.value->'current', item.value->'proposed'
             FROM jsonb_array_elements(coalesce(
               _staging.extracted_data->'diff'->'unchanged', '[]'::jsonb
             )) AS item(value)
           ) AS pair
           JOIN jsonb_array_elements(proposals) WITH ORDINALITY
             AS proposal(value, ordinality)
             ON public.canonical_json_text(proposal.value) =
                public.canonical_json_text(pair.proposed)
           WHERE coalesce(
             pair.current->>'liveBenefitId', pair.current->>'benefitId',
             pair.current->>'dedupeKey'
           ) = (decision.value->>'benefit_id')
         ) AS exact_target) <> 1
       )
     )
     OR EXISTS (
       SELECT identity FROM (
         SELECT CASE
           WHEN decision.value ? 'proposal_index'
             THEN 'proposal:' || (decision.value->>'proposal_index')
           WHEN decision.value->>'action' IN ('keep_existing','reject') THEN
             coalesce((
               SELECT 'proposal:' || (proposal.ordinality - 1)::text
               FROM (
                 SELECT item.value->'current' AS current,
                        item.value->'proposed' AS proposed
                 FROM jsonb_array_elements(coalesce(
                   _staging.extracted_data->'diff'->'modifications', '[]'::jsonb
                 )) AS item(value)
                 UNION ALL
                 SELECT item.value->'current', item.value->'proposed'
                 FROM jsonb_array_elements(coalesce(
                   _staging.extracted_data->'diff'->'unchanged', '[]'::jsonb
                 )) AS item(value)
               ) AS pair
               JOIN jsonb_array_elements(proposals) WITH ORDINALITY
                 AS proposal(value, ordinality)
                 ON public.canonical_json_text(proposal.value) =
                    public.canonical_json_text(pair.proposed)
               WHERE coalesce(
                 pair.current->>'liveBenefitId', pair.current->>'benefitId',
                 pair.current->>'dedupeKey'
               ) = (decision.value->>'benefit_id')
               LIMIT 1
             ), 'benefit:' || (decision.value->>'benefit_id'))
           ELSE 'benefit:' || (decision.value->>'benefit_id')
         END AS identity
         FROM jsonb_array_elements(decisions) AS decision(value)
       ) reviewed GROUP BY identity HAVING count(*) <> 1
     )
  THEN RETURN false; END IF;

  SELECT count(*) FILTER (WHERE value->>'action' IN ('approve','edit')),
         count(*) FILTER (WHERE value->>'action' = 'keep_existing'),
         count(*) FILTER (WHERE value->>'action' = 'retire'),
         count(*) FILTER (WHERE value->>'action' = 'reject')
    INTO approved_count, retained_count, retired_count, rejected_count
  FROM jsonb_array_elements(decisions);
  RETURN rejected_count = 0
    AND (_job.run_mode = 'scheduled' OR (
      approved_count = (_job.result_summary->>'approved_count')::integer
      AND retained_count = (_job.result_summary->>'retained_count')::integer
      AND retired_count = (_job.result_summary->>'retired_count')::integer
      AND rejected_count = (_job.result_summary->>'rejected_count')::integer
    ));
EXCEPTION WHEN OTHERS THEN
  RETURN false;
END;
$_$;


--
-- Name: card_enrichment_pilot_has_contextual_person(text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.card_enrichment_pilot_has_contextual_person(_text text, _known_identity_phrases jsonb) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'public', 'pg_temp'
    AS $_$
  SELECT CASE
    WHEN _text IS NULL OR octet_length(convert_to(_text, 'UTF8')) > 65536
      OR jsonb_typeof(_known_identity_phrases) <> 'array'
      OR jsonb_array_length(_known_identity_phrases) > 9
    THEN true
    ELSE EXISTS (
      SELECT 1
      FROM regexp_matches(
        lower(_text),
        '\m(for|to)[[:space:]]+(([[:alpha:]][^[:space:]]{1,})([[:space:]]+[[:alpha:]][^[:space:]]{1,}){0,3}?)([[:space:]]+(is|gets?|receives?|will)\M|[[:space:]]*[.,;:!?]|$)',
        'g'
      ) AS contextual_person(match)
      WHERE NOT EXISTS (
        SELECT 1
        FROM jsonb_array_elements_text(_known_identity_phrases)
          AS exact_identity_phrase(value)
        WHERE trim(lower(exact_identity_phrase.value)) =
          trim(lower(contextual_person.match[2]))
      )
        AND NOT EXISTS (
          -- POSIX alpha excludes combining vowel signs/viramas. Admit a
          -- bounded Unicode Mark set only after an alphabetic first
          -- character; digits, currency, and arbitrary punctuation remain
          -- outside the name-token grammar.
          SELECT 1
          FROM regexp_split_to_table(
            contextual_person.match[2], ''
          ) AS contextual_character(value)
          WHERE contextual_character.value <> ' '
            AND contextual_character.value !~ '^[[:alpha:]]$'
            AND contextual_character.value NOT IN ('''', '-')
            AND NOT (
              ascii(contextual_character.value) BETWEEN 768 AND 879
              OR ascii(contextual_character.value) BETWEEN 6832 AND 6911
              OR ascii(contextual_character.value) BETWEEN 7616 AND 7679
              OR ascii(contextual_character.value) BETWEEN 8400 AND 8447
              OR ascii(contextual_character.value) BETWEEN 65056 AND 65071
              OR ascii(contextual_character.value) BETWEEN 2304 AND 2307
              OR ascii(contextual_character.value) BETWEEN 2362 AND 2383
              OR ascii(contextual_character.value) BETWEEN 2385 AND 2391
              OR ascii(contextual_character.value) BETWEEN 2402 AND 2403
              OR ascii(contextual_character.value) BETWEEN 2433 AND 2435
              OR ascii(contextual_character.value) BETWEEN 2492 AND 2500
              OR ascii(contextual_character.value) BETWEEN 2503 AND 2504
              OR ascii(contextual_character.value) BETWEEN 2507 AND 2509
              OR ascii(contextual_character.value) = 2519
              OR ascii(contextual_character.value) BETWEEN 2530 AND 2531
              OR ascii(contextual_character.value) = 2558
            )
        )
        AND EXISTS (
          SELECT 1
          FROM regexp_split_to_table(
            trim(lower(contextual_person.match[2])), '[[:space:]]+'
          ) AS contextual_word(value)
          WHERE contextual_word.value NOT IN (
            'applicant','applicants','cardholder','cardholders',
            'customer','customers','member','members','user','users',
            'access','accelerated','annual','airport','bank','benefit','benefits',
            'bonus','cap','cashback','card','conditions','complimentary',
            'credit','cover','dining','discount','domestic','earn','enjoy',
            'exclusive','fee','fees','forex','fuel','get','international',
            'insurance','interest','lounge','mastercard','markup','maximum',
            'milestone','miles','minimum','mitc','most','movie','offer',
            'offers','important','points','program','reward','rewards',
            'rupay','spend','surcharge','terms','threshold','ticket',
            'tickets','travel','unlimited','visa','waiver','welcome','zero',
            'apr','renewal'
          )
        )
    )
  END;
$_$;


--
-- Name: card_enrichment_pilot_job_is_qualified(text, text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.card_enrichment_pilot_job_is_qualified(_status text, _failure_category text, _summary jsonb) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO 'public', 'pg_temp'
    AS $_$
DECLARE
  MAX_PILOT_REVIEW_COUNT constant bigint := 999999999;
  approved_count bigint;
  retained_count bigint;
  retired_count bigint;
  rejected_count bigint;
  approved_numeric numeric;
  retained_numeric numeric;
  retired_numeric numeric;
  rejected_numeric numeric;
  review_keys text[] := ARRAY[
    'review_status', 'approved_count', 'retained_count',
    'retired_count', 'rejected_count'
  ];
BEGIN
  IF jsonb_typeof(_summary) <> 'object'
     OR NOT (_summary ? 'unsafe_mutation_count')
     OR jsonb_typeof(_summary->'unsafe_mutation_count') <> 'number'
     OR _summary->'unsafe_mutation_count' IS DISTINCT FROM '0'::jsonb
     OR _summary->'idempotency_passed' IS DISTINCT FROM 'true'::jsonb
     OR NOT (_summary ? 'raw_body_stored')
     OR jsonb_typeof(_summary->'raw_body_stored') <> 'boolean'
     OR _summary->'raw_body_stored' IS DISTINCT FROM 'false'::jsonb
     OR _status NOT IN ('staged', 'completed', 'quarantined') THEN
    RETURN false;
  END IF;
  IF _status = 'quarantined' THEN
    RETURN trim(coalesce(_failure_category, '')) ~ '^[a-z0-9_]{1,64}$';
  END IF;
  IF _summary->'evidence_passed' IS DISTINCT FROM 'true'::jsonb THEN
    RETURN false;
  END IF;
  IF _status = 'staged' THEN RETURN true; END IF;

  IF _summary->'successful_no_change' = 'true'::jsonb
     AND NOT (_summary ?| review_keys) THEN
    RETURN true;
  END IF;
  IF jsonb_typeof(_summary->'review_status') IS DISTINCT FROM 'string'
     OR _summary->>'review_status' IS DISTINCT FROM 'approved'
     OR NOT (_summary ? 'approved_count')
     OR NOT (_summary ? 'retained_count')
     OR NOT (_summary ? 'retired_count')
     OR NOT (_summary ? 'rejected_count')
     OR jsonb_typeof(_summary->'approved_count') IS DISTINCT FROM 'number'
     OR jsonb_typeof(_summary->'retained_count') IS DISTINCT FROM 'number'
     OR jsonb_typeof(_summary->'retired_count') IS DISTINCT FROM 'number'
     OR jsonb_typeof(_summary->'rejected_count') IS DISTINCT FROM 'number' THEN
    RETURN false;
  END IF;
  approved_numeric := (_summary->>'approved_count')::numeric;
  retained_numeric := (_summary->>'retained_count')::numeric;
  retired_numeric := (_summary->>'retired_count')::numeric;
  rejected_numeric := (_summary->>'rejected_count')::numeric;
  IF approved_numeric <> trunc(approved_numeric)
     OR retained_numeric <> trunc(retained_numeric)
     OR retired_numeric <> trunc(retired_numeric)
     OR rejected_numeric <> trunc(rejected_numeric)
     OR approved_numeric NOT BETWEEN 0 AND MAX_PILOT_REVIEW_COUNT
     OR retained_numeric NOT BETWEEN 0 AND MAX_PILOT_REVIEW_COUNT
     OR retired_numeric NOT BETWEEN 0 AND MAX_PILOT_REVIEW_COUNT
     OR rejected_numeric NOT BETWEEN 0 AND MAX_PILOT_REVIEW_COUNT THEN
    RETURN false;
  END IF;
  approved_count := approved_numeric::bigint;
  retained_count := retained_numeric::bigint;
  retired_count := retired_numeric::bigint;
  rejected_count := rejected_numeric::bigint;
  RETURN rejected_count = 0
    AND approved_count + retained_count + retired_count > 0;
END;
$_$;


--
-- Name: card_enrichment_pilot_live_state_snapshot(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.card_enrichment_pilot_live_state_snapshot(_card_id uuid) RETURNS jsonb
    LANGUAGE sql STABLE
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
  -- The Task4 helper is the single serializer for card_catalog,
  -- card_benefit_mapping, and public.benefits and uses
  -- canonical_card_benefit_row_timestamp for UTC microsecond parity.
  SELECT public.card_benefit_review_live_state_snapshot(_card_id);
$$;


--
-- Name: card_enrichment_pilot_queryless_display_url(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.card_enrichment_pilot_queryless_display_url(_url text) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $_$
DECLARE
  parts text[];
  authority text;
  resource_path text;
BEGIN
  IF public.card_enrichment_pilot_source_identity_hash(_url) IS NULL THEN
    RETURN NULL;
  END IF;
  parts := regexp_match(
    trim(_url), '^https://([^/?#]+)([^?#]*)(\?[^#]*)?$', 'i'
  );
  IF parts IS NULL THEN RETURN NULL; END IF;
  authority := lower(regexp_replace(parts[1], ':443$', '', 'i'));
  resource_path := regexp_replace(coalesce(parts[2], ''), '/{2,}', '/', 'g');
  IF resource_path IN ('', '/') THEN
    resource_path := '';
  ELSE
    resource_path := regexp_replace(resource_path, '/$', '');
  END IF;
  RETURN 'https://' || authority || resource_path;
END;
$_$;


--
-- Name: card_enrichment_pilot_snapshot_rows(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.card_enrichment_pilot_snapshot_rows(_rows jsonb) RETURNS jsonb
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
  SELECT jsonb_build_object(
    'count', jsonb_array_length(_rows),
    'row_hash', encode(extensions.digest(
      convert_to(public.canonical_json_text(_rows), 'UTF8'), 'sha256'
    ), 'hex')
  );
$$;


--
-- Name: card_enrichment_pilot_source_identity_hash(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.card_enrichment_pilot_source_identity_hash(_url text) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $_$
DECLARE
  parts text[];
  authority text;
  resource_path text;
  resource_query text;
  canonical_url text;
  query_entry text;
  query_key text;
  query_value text;
  decoded_query_value text;
  query_entries text[];
BEGIN
  IF _url IS NULL OR length(trim(_url)) NOT BETWEEN 9 AND 2048
     OR trim(_url) ~ '[[:cntrl:][:space:]]' THEN
    RETURN NULL;
  END IF;
  parts := regexp_match(
    trim(_url), '^https://([^/?#]+)([^?#]*)(\?[^#]*)?$', 'i'
  );
  IF parts IS NULL OR parts[1] = '' OR parts[1] LIKE '%@%'
     OR parts[1] !~ '^[A-Za-z0-9.-]+(:[0-9]+)?$' THEN
    RETURN NULL;
  END IF;
  authority := lower(regexp_replace(parts[1], ':443$', '', 'i'));
  resource_path := coalesce(parts[2], '');
  resource_query := coalesce(parts[3], '');
  IF resource_query <> '' THEN
    query_entries := string_to_array(substr(resource_query, 2), '&');
    IF cardinality(query_entries) NOT BETWEEN 1 AND 8 THEN RETURN NULL; END IF;
    FOREACH query_entry IN ARRAY query_entries LOOP
      IF query_entry = '' OR position('=' IN query_entry) < 2
         OR length(split_part(query_entry, '=', 1)) > 64
         OR position('%' IN regexp_replace(
              query_entry, '%[0-9A-Fa-f]{2}', '', 'g'
            )) > 0 THEN
        RETURN NULL;
      END IF;
      query_key := lower(split_part(query_entry, '=', 1));
      query_value := substr(query_entry, position('=' IN query_entry) + 1);
      IF length(query_value) > 512 THEN RETURN NULL; END IF;
      IF query_key NOT IN ('document','file','locale','version') THEN
        RETURN NULL;
      END IF;
      decoded_query_value := replace(query_value, '+', ' ');
      decoded_query_value := regexp_replace(decoded_query_value, '%20', ' ', 'gi');
      decoded_query_value := regexp_replace(decoded_query_value, '%2D', '-', 'gi');
      decoded_query_value := regexp_replace(decoded_query_value, '%2E', '.', 'gi');
      decoded_query_value := regexp_replace(decoded_query_value, '%2F', '/', 'gi');
      decoded_query_value := regexp_replace(decoded_query_value, '%5F', '_', 'gi');
      decoded_query_value := regexp_replace(decoded_query_value, '%7E', '~', 'gi');
      IF decoded_query_value ~* '(authorization|bearer|access[_ -]?token|refresh[_ -]?token|lease[_ -]?token|password|secret|credential|customer|account|phone|email|pan|card[_ -]?(number|no\.?))'
         OR decoded_query_value ~* '(@|%40|%(25)+|%3[ad])'
         OR regexp_replace(
              query_value, '%(20|2D|2E|2F|5F|7E)', '', 'gi'
            ) !~ '^[A-Za-z0-9._~+/-]+$'
         OR length(regexp_replace(
              decoded_query_value, '[^0-9]', '', 'g'
            )) >= 10 THEN
        RETURN NULL;
      END IF;
    END LOOP;
  END IF;
  -- WHATWG URL serialization retains the root slash before a functional
  -- query and omits it only for a queryless origin.
  IF resource_query <> '' AND resource_path IN ('', '/') THEN
    resource_path := '/';
  ELSIF resource_query = '' AND resource_path IN ('', '/') THEN
    resource_path := '';
  END IF;
  canonical_url := 'https://' || authority || resource_path || resource_query;
  canonical_url := regexp_replace(canonical_url, '/$', '');
  RETURN encode(extensions.digest(convert_to(canonical_url, 'UTF8'), 'sha256'), 'hex');
END;
$_$;


--
-- Name: card_enrichment_pilot_source_manifest_hash(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.card_enrichment_pilot_source_manifest_hash(_attempts jsonb) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
  SELECT CASE WHEN jsonb_typeof(_attempts) = 'array'
                   AND jsonb_array_length(_attempts) BETWEEN 1 AND 9
    THEN encode(extensions.digest(convert_to(coalesce(string_agg(
      public.canonical_json_text(
        (attempt.value - 'attemptedAt' - 'attemptHistory') ||
        CASE WHEN jsonb_typeof(attempt.value->'attemptHistory') = 'array'
          THEN jsonb_build_object('attemptHistory', coalesce((
            SELECT jsonb_agg(history.value - 'attemptedAt' ORDER BY history.ordinality)
            FROM jsonb_array_elements(attempt.value->'attemptHistory')
              WITH ORDINALITY AS history(value, ordinality)
          ), '[]'::jsonb)) ELSE '{}'::jsonb END
      ), E'\n' ORDER BY public.canonical_json_text(
        (attempt.value - 'attemptedAt' - 'attemptHistory') ||
        CASE WHEN jsonb_typeof(attempt.value->'attemptHistory') = 'array'
          THEN jsonb_build_object('attemptHistory', coalesce((
            SELECT jsonb_agg(history.value - 'attemptedAt' ORDER BY history.ordinality)
            FROM jsonb_array_elements(attempt.value->'attemptHistory')
              WITH ORDINALITY AS history(value, ordinality)
          ), '[]'::jsonb)) ELSE '{}'::jsonb END
      )
    ), ''), 'UTF8'), 'sha256'), 'hex') ELSE NULL END
  FROM jsonb_array_elements(CASE WHEN jsonb_typeof(_attempts) = 'array'
    THEN _attempts ELSE '[]'::jsonb END) AS attempt(value);
$$;


--
-- Name: card_enrichment_pilot_timestamp(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.card_enrichment_pilot_timestamp(_value text) RETURNS timestamp with time zone
    LANGUAGE plpgsql STABLE
    SET search_path TO 'public', 'pg_temp'
    AS $_$
DECLARE
  parts text[];
  canonical_value text;
  parsed_value timestamptz;
  offset_hour integer;
  offset_minute integer;
BEGIN
  IF _value IS NULL OR length(_value) > 48 THEN RETURN NULL; END IF;
  parts := regexp_match(
    _value,
    '^(\d{4}-\d{2}-\d{2})[ T](\d{2}:\d{2}:\d{2})(?:\.(\d{1,6}))?(Z|([+-])(\d{2})(?::?(\d{2}))?)$'
  );
  IF parts IS NULL THEN RETURN NULL; END IF;
  offset_hour := CASE WHEN upper(parts[4]) = 'Z' THEN 0 ELSE parts[6]::integer END;
  offset_minute := CASE WHEN upper(parts[4]) = 'Z' THEN 0
    ELSE coalesce(parts[7], '0')::integer END;
  IF offset_hour > 14 OR offset_minute > 59
     OR (offset_hour = 14 AND offset_minute <> 0) THEN RETURN NULL; END IF;
  BEGIN
    parsed_value := _value::timestamptz;
  EXCEPTION WHEN OTHERS THEN
    RETURN NULL;
  END;
  canonical_value := public.canonical_card_benefit_row_timestamp(parsed_value);
  IF canonical_value IS NULL OR parsed_value < '2000-01-01T00:00:00Z'::timestamptz
     OR parsed_value > clock_timestamp() + interval '5 minutes' THEN
    RETURN NULL;
  END IF;
  RETURN parsed_value;
END;
$_$;


--
-- Name: card_enrichment_requeue_action(text, text, timestamp with time zone, timestamp with time zone, boolean, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.card_enrichment_requeue_action(_run_mode text, _status text, _next_run_at timestamp with time zone, _now timestamp with time zone, _eligible boolean, _has_pending_staging boolean) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
  IF _now IS NULL OR _eligible IS NULL OR _has_pending_staging IS NULL
     OR _status NOT IN ('completed', 'staged', 'quarantined', 'review_required', 'failed') THEN
    RETURN 'none';
  END IF;
  IF _run_mode <> 'scheduled' THEN
    RETURN CASE WHEN _next_run_at IS NULL THEN 'none' ELSE 'clear' END;
  END IF;
  IF NOT _eligible THEN
    RETURN CASE WHEN _next_run_at IS NULL THEN 'none' ELSE 'clear' END;
  END IF;
  IF _next_run_at IS NULL OR _next_run_at <= _now THEN
    RETURN 'queue';
  END IF;
  RETURN 'none';
END;
$$;


--
-- Name: card_has_unresolved_catalog_identity(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.card_has_unresolved_catalog_identity(_card_id uuid, _canonical_url text) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'public', 'pg_temp'
    AS $_$
  SELECT EXISTS (
    SELECT 1
    FROM public.card_catalog_review_queue AS review
    LEFT JOIN LATERAL jsonb_array_elements(
      CASE WHEN jsonb_typeof(review.existing_candidates) = 'array'
        THEN review.existing_candidates ELSE '[]'::jsonb END
    ) AS candidate(value) ON true
    WHERE review.status = 'pending'
      AND (
        candidate.value->>'id' = _card_id::text
        OR candidate.value->>'card_id' = _card_id::text
        OR candidate.value->>'cardId' = _card_id::text
        OR review.proposed_fields->>'card_id' = _card_id::text
        OR review.proposed_fields->>'cardId' = _card_id::text
        OR review.proposed_fields->>'existing_card_id' = _card_id::text
        OR regexp_replace(split_part(split_part(coalesce(
          review.proposed_fields->>'official_url',
          review.proposed_fields->>'card_url',
          review.proposed_fields->>'source_url',
          review.source_evidence->>'official_url',
          review.source_evidence->>'source_url',
          ''
        ), '#', 1), '?', 1), '/+$', '') =
          regexp_replace(split_part(split_part(coalesce(_canonical_url, ''), '#', 1), '?', 1), '/+$', '')
      )
  );
$_$;


--
-- Name: card_scoped_benefit_key(uuid, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.card_scoped_benefit_key(_card_id uuid, _condition jsonb) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
  SELECT 'card-benefit-v2:' || lower(_card_id::text) || ':' ||
    public.canonical_benefit_condition_hash(_condition);
$$;


--
-- Name: catalog_lifecycle_semantic_observation(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.catalog_lifecycle_semantic_observation(_value jsonb) RETURNS jsonb
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $_$
DECLARE
  result jsonb;
BEGIN
  IF _value IS NULL THEN RETURN 'null'::jsonb; END IF;
  IF jsonb_typeof(_value) = 'object' THEN
    SELECT coalesce(jsonb_object_agg(
      entry.key, cleaned.value ORDER BY entry.key
    ), '{}'::jsonb)
    INTO result
    FROM jsonb_each(_value) AS entry
    CROSS JOIN LATERAL (
      SELECT lower(regexp_replace(regexp_replace(
        trim(entry.key), '([a-z0-9])([A-Z])', '\1_\2', 'g'
      ), '[-[:space:]]+', '_', 'g')) AS normalized_key
    ) AS normalized
    CROSS JOIN LATERAL (
      SELECT public.catalog_lifecycle_semantic_observation(entry.value) AS value
    ) AS cleaned
    WHERE normalized.normalized_key NOT IN (
      'content_hash', 'etag', 'last_modified', 'not_modified',
      'retrieved_at', 'attempted_at', 'observed_at', 'transport',
      'duration_ms', 'retry_after_ms', 'request_started_at',
      'request_completed_at', 'nonce', 'footer', 'generated_at',
      'url', 'urls', 'url_hash', 'resource_identity_hash',
      'source_identity_hash'
    )
      AND normalized.normalized_key !~
        '(_url|_urls|_url_hash|_resource_identity_hash|_source_identity_hash)$'
      AND NOT (
        jsonb_typeof(entry.value) = 'object'
        AND entry.value <> '{}'::jsonb
        AND cleaned.value = '{}'::jsonb
      )
      AND NOT (
        jsonb_typeof(entry.value) = 'array'
        AND entry.value <> '[]'::jsonb
        AND cleaned.value = '[]'::jsonb
      );
    RETURN result;
  ELSIF jsonb_typeof(_value) = 'array' THEN
    SELECT coalesce(jsonb_agg(cleaned.value ORDER BY entry.ordinality), '[]'::jsonb)
    INTO result
    FROM jsonb_array_elements(_value) WITH ORDINALITY AS entry(value, ordinality)
    CROSS JOIN LATERAL (
      SELECT public.catalog_lifecycle_semantic_observation(entry.value) AS value
    ) AS cleaned
    WHERE NOT (
      jsonb_typeof(entry.value) = 'object'
      AND entry.value <> '{}'::jsonb
      AND cleaned.value = '{}'::jsonb
    )
      AND NOT (
        jsonb_typeof(entry.value) = 'array'
        AND entry.value <> '[]'::jsonb
        AND cleaned.value = '[]'::jsonb
      );
    RETURN result;
  END IF;
  RETURN _value;
END;
$_$;


--
-- Name: claim_card_catalog_enrichment_jobs(integer, integer, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.claim_card_catalog_enrichment_jobs(_max_jobs integer, _lease_seconds integer, _run_mode text, _parser_version text) RETURNS SETOF public.card_catalog_enrichment_jobs
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  selected_issuer text;
  maximum_jobs integer;
  lease_seconds integer;
  selected_parser text;
BEGIN
  selected_parser := trim(coalesce(_parser_version, ''));
  IF _max_jobs IS NULL OR _max_jobs < 1 OR _lease_seconds IS NULL
     OR _run_mode IS NULL OR _run_mode NOT IN ('pilot', 'scheduled', 'manual')
     OR length(selected_parser) < 3 OR lower(selected_parser) = 'catalog-v1' THEN
    RAISE EXCEPTION 'invalid_enrichment_claim';
  END IF;
  maximum_jobs := 1;
  lease_seconds := 300;
  PERFORM pg_advisory_xact_lock(
    hashtextextended('card_catalog_enrichment_claim:' || selected_parser, 0)
  );
  UPDATE public.card_catalog_enrichment_jobs AS job
  SET status = CASE
        WHEN public.card_enrichment_job_has_pending_staging(
          job.staging_id, job.card_id, job.parser_version
        ) THEN 'staged'
        WHEN job.attempt_count >= 3 THEN 'review_required'
        ELSE 'failed' END,
      -- expired_pending_failure_cadence: retaining a reviewable staging link
      -- must still select the seven-day failure recurrence, never success.
      failure_category = 'worker_resource_limit',
      next_retry_at = CASE
        WHEN public.card_enrichment_job_has_pending_staging(
          job.staging_id, job.card_id, job.parser_version
        ) THEN NULL
        WHEN job.attempt_count >= 3 THEN NULL
        WHEN job.attempt_count = 1 THEN now() + interval '15 minutes'
        ELSE now() + interval '60 minutes' END,
      next_run_at = NULL,
      result_summary = coalesce(job.result_summary, '{}'::jsonb) || jsonb_build_object(
        'lease_expired', true,
        'retry_scheduled', CASE
          WHEN public.card_enrichment_job_has_pending_staging(
            job.staging_id, job.card_id, job.parser_version
          ) THEN false
          ELSE job.attempt_count < 3 END
      ),
      lease_expires_at = NULL,
      lease_token = NULL,
      updated_at = now()
  WHERE job.status = 'processing'
    AND job.parser_version = selected_parser
    AND (job.lease_expires_at IS NULL OR job.lease_expires_at <= now());

  SELECT lower(trim(job.issuer)) INTO selected_issuer
  FROM public.card_catalog_enrichment_jobs AS job
  JOIN public.card_catalog AS card ON card.id = job.card_id
  WHERE job.status IN ('queued', 'failed')
    AND job.next_run_at IS NULL
    AND (job.next_retry_at IS NULL OR job.next_retry_at <= now())
    AND job.run_mode = _run_mode
    AND job.parser_version = selected_parser
    AND (
      coalesce(card.is_discontinued, false) = false
      OR EXISTS (
        SELECT 1 FROM public.user_cards AS user_card
        WHERE user_card.catalog_card_id = job.card_id
          AND user_card.is_active = true
      )
    )
    AND NOT public.card_has_unresolved_catalog_identity(job.card_id, job.canonical_url)
    AND NOT EXISTS (
      SELECT 1 FROM public.card_catalog_enrichment_jobs AS leased
      WHERE lower(trim(leased.issuer)) = lower(trim(job.issuer))
        AND leased.status = 'processing'
        AND leased.parser_version = selected_parser
        AND leased.lease_expires_at > now()
    )
  ORDER BY lower(trim(job.issuer)), card.card_name, job.created_at, job.id
  LIMIT 1;
  IF selected_issuer IS NULL THEN RETURN; END IF;

  RETURN QUERY
  WITH candidates AS (
    SELECT job.id
    FROM public.card_catalog_enrichment_jobs AS job
    JOIN public.card_catalog AS card ON card.id = job.card_id
    WHERE lower(trim(job.issuer)) = selected_issuer
      AND job.status IN ('queued', 'failed')
      AND job.next_run_at IS NULL
      AND (job.next_retry_at IS NULL OR job.next_retry_at <= now())
      AND job.run_mode = _run_mode
      AND job.parser_version = selected_parser
      AND (
        coalesce(card.is_discontinued, false) = false
        OR EXISTS (
          SELECT 1 FROM public.user_cards AS user_card
          WHERE user_card.catalog_card_id = job.card_id
            AND user_card.is_active = true
        )
      )
      AND NOT public.card_has_unresolved_catalog_identity(job.card_id, job.canonical_url)
    ORDER BY card.card_name, job.created_at, job.id
    LIMIT maximum_jobs
    FOR UPDATE OF job SKIP LOCKED
  )
  UPDATE public.card_catalog_enrichment_jobs AS job
  SET status = 'processing',
      attempt_count = job.attempt_count + 1,
      next_run_at = NULL,
      lease_expires_at = now() + make_interval(secs => lease_seconds),
      lease_token = gen_random_uuid(),
      updated_at = now()
  FROM candidates
  WHERE job.id = candidates.id
  RETURNING job.*;
END;
$$;


--
-- Name: consume_gemini_proxy_quota(uuid, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.consume_gemini_proxy_quota(_user_id uuid, _limit integer DEFAULT 10) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  recent_count integer;
BEGIN
  IF _user_id IS NULL OR _limit < 1 OR _limit > 60 THEN
    RETURN false;
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(_user_id::text));
  DELETE FROM public.gemini_proxy_usage
    WHERE created_at < now() - interval '1 hour';
  SELECT count(*) INTO recent_count
    FROM public.gemini_proxy_usage
    WHERE user_id = _user_id
      AND created_at >= now() - interval '1 minute';
  IF recent_count >= _limit THEN
    RETURN false;
  END IF;
  INSERT INTO public.gemini_proxy_usage(user_id) VALUES (_user_id);
  RETURN true;
END;
$$;


--
-- Name: create_or_get_card_catalog(text, text, text, text, numeric, numeric, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_or_get_card_catalog(_bank text, _card_name text, _network text, _card_type text DEFAULT 'credit'::text, _joining_fee numeric DEFAULT NULL::numeric, _annual_fee numeric DEFAULT NULL::numeric, _apr numeric DEFAULT NULL::numeric) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  card_id UUID;
BEGIN
  -- Try to find existing card
  SELECT id INTO card_id FROM card_catalog
  WHERE bank = _bank AND card_name = _card_name AND network = _network;

  -- If not found, create it
  IF card_id IS NULL THEN
    INSERT INTO card_catalog (
      bank, card_name, network, card_type, joining_fee, annual_fee, apr
    ) VALUES (
      _bank, _card_name, _network, _card_type, _joining_fee, _annual_fee, _apr
    ) RETURNING id INTO card_id;
  END IF;

  RETURN card_id;
END;
$$;


--
-- Name: decode_card_resource_component(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.decode_card_resource_component(_value text) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $_$
DECLARE
  input_value text := coalesce(_value, '');
  decoded_bytes bytea := ''::bytea;
  position integer := 1;
  character text;
BEGIN
  WHILE position <= length(input_value) LOOP
    character := substring(input_value FROM position FOR 1);
    IF character = '%' THEN
      IF position + 2 > length(input_value)
         OR substring(input_value FROM position + 1 FOR 2) !~ '^[0-9A-Fa-f]{2}$' THEN
        RAISE EXCEPTION 'unapproved_query';
      END IF;
      decoded_bytes := decoded_bytes || decode(
        substring(input_value FROM position + 1 FOR 2), 'hex'
      );
      position := position + 3;
    ELSIF character = '+' THEN
      decoded_bytes := decoded_bytes || decode('20', 'hex');
      position := position + 1;
    ELSE
      decoded_bytes := decoded_bytes || convert_to(character, 'UTF8');
      position := position + 1;
    END IF;
  END LOOP;
  RETURN convert_from(decoded_bytes, 'UTF8');
EXCEPTION WHEN character_not_in_repertoire OR untranslatable_character THEN
  RAISE EXCEPTION 'unapproved_query';
END;
$_$;


--
-- Name: enforce_card_benefit_enrichment_identity(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.enforce_card_benefit_enrichment_identity() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
  IF lower(trim(NEW.parser_version)) = 'benefits-v6' THEN
    PERFORM pg_advisory_xact_lock(hashtextextended(
      'card_benefit_enrichment_identity:' || NEW.card_id::text ||
        ':benefits-v6',
      0
    ));
    IF EXISTS (
      SELECT 1
      FROM public.card_catalog_enrichment_jobs AS existing_job
      WHERE existing_job.card_id = NEW.card_id
        AND lower(trim(existing_job.parser_version)) = 'benefits-v6'
        AND existing_job.id IS DISTINCT FROM NEW.id
        AND existing_job.job_key IS DISTINCT FROM NEW.job_key
    ) THEN
      RAISE EXCEPTION 'duplicate_v6_card_parser_identity';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: enqueue_card_benefit_enrichment_jobs(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.enqueue_card_benefit_enrichment_jobs(_jobs jsonb) RETURNS integer
    LANGUAGE plpgsql
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $_$
DECLARE
  input_count integer;
  invalid_count integer;
  inserted_count integer;
  identity_row record;
  locked_jobs jsonb;
BEGIN
  IF _jobs IS NULL OR jsonb_typeof(_jobs) <> 'array'
     OR jsonb_array_length(_jobs) < 1 OR jsonb_array_length(_jobs) > 200 THEN
    RAISE EXCEPTION 'invalid_enrichment_enqueue';
  END IF;
  WITH input AS (
    SELECT *
    FROM jsonb_to_recordset(_jobs) AS job(
      card_id uuid, issuer text, canonical_url text, final_url_hash text,
      content_hash text, parser_version text, job_key text, run_mode text,
      result_summary jsonb
    )
  )
  SELECT count(*), count(*) FILTER (
    WHERE card_id IS NULL OR length(trim(coalesce(issuer, ''))) < 2
      OR canonical_url IS NULL OR canonical_url !~ '^https://'
      OR final_url_hash IS NULL OR final_url_hash !~ '^[0-9a-f]{64}$'
      OR (content_hash IS NOT NULL AND content_hash !~ '^[0-9a-f]{64}$')
      OR trim(coalesce(parser_version, '')) <> 'benefits-v6'
      OR run_mode IS NULL OR run_mode NOT IN ('pilot', 'scheduled', 'manual')
      OR jsonb_typeof(result_summary) IS DISTINCT FROM 'object'
      OR job_key IS DISTINCT FROM (
        card_id::text || ':' || final_url_hash || ':' || trim(parser_version)
      )
  )
  INTO input_count, invalid_count
  FROM input;
  IF input_count <> jsonb_array_length(_jobs) OR invalid_count <> 0 THEN
    RAISE EXCEPTION 'invalid_enrichment_enqueue';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM jsonb_to_recordset(_jobs) AS duplicate_input(
      card_id uuid, parser_version text
    )
    GROUP BY duplicate_input.card_id, trim(duplicate_input.parser_version)
    HAVING count(*) > 1
  ) THEN
    RAISE EXCEPTION 'duplicate_card_parser_enqueue';
  END IF;

  -- The trigger, this RPC, and pilot initialization share this exact ordered
  -- identity namespace. The RPC then re-reads all mutable authority.
  FOR identity_row IN
    SELECT DISTINCT job.card_id, trim(job.parser_version) AS parser_version
    FROM jsonb_to_recordset(_jobs) AS job(
      card_id uuid, parser_version text
    )
    ORDER BY job.card_id, trim(job.parser_version)
  LOOP
    PERFORM pg_advisory_xact_lock(hashtextextended(
      'card_benefit_enrichment_identity:' || identity_row.card_id::text ||
        ':' || identity_row.parser_version,
      0
    ));
  END LOOP;

  WITH input AS (
    SELECT *
    FROM jsonb_to_recordset(_jobs) AS job(
      card_id uuid, issuer text, canonical_url text, final_url_hash text,
      content_hash text, parser_version text, job_key text, run_mode text,
      result_summary jsonb
    )
  ), locked_enqueue_authority AS MATERIALIZED (
    SELECT input.*, card.bank, card.card_url, card.card_type,
      card.is_discontinued
    FROM input
    JOIN public.card_catalog AS card ON card.id = input.card_id
    ORDER BY card.id
    FOR UPDATE OF card
  )
  SELECT coalesce(
    jsonb_agg(to_jsonb(authority) ORDER BY authority.card_id),
    '[]'::jsonb
  )
  INTO locked_jobs
  FROM locked_enqueue_authority AS authority;

  -- Stabilize existing active-holder evidence before the final eligibility
  -- check. A new holder can only make a previously ineligible card safer.
  PERFORM holder.id
  FROM public.user_cards AS holder
  WHERE holder.catalog_card_id IN (
    SELECT candidate.card_id
    FROM jsonb_to_recordset(locked_jobs) AS candidate(card_id uuid)
  )
    AND holder.is_active = true
  ORDER BY holder.id
  FOR SHARE;

  -- Lock every currently matching unresolved identity review before the final
  -- exclusion check. Review resolution and enqueue therefore cannot cross on
  -- a stale row; a newly inserted review remains a later independent event.
  PERFORM review.id
  FROM public.card_catalog_review_queue AS review
  LEFT JOIN LATERAL jsonb_array_elements(
    CASE WHEN jsonb_typeof(review.existing_candidates) = 'array'
      THEN review.existing_candidates ELSE '[]'::jsonb END
  ) AS review_candidate(value) ON true
  WHERE review.status = 'pending'
    AND EXISTS (
      SELECT 1
      FROM jsonb_to_recordset(locked_jobs) AS candidate(
        card_id uuid, canonical_url text
      )
      WHERE review_candidate.value->>'id' = candidate.card_id::text
        OR review_candidate.value->>'card_id' = candidate.card_id::text
        OR review_candidate.value->>'cardId' = candidate.card_id::text
        OR review.proposed_fields->>'card_id' = candidate.card_id::text
        OR review.proposed_fields->>'cardId' = candidate.card_id::text
        OR review.proposed_fields->>'existing_card_id' = candidate.card_id::text
        OR regexp_replace(split_part(split_part(coalesce(
          review.proposed_fields->>'official_url',
          review.proposed_fields->>'card_url',
          review.proposed_fields->>'source_url',
          review.source_evidence->>'official_url',
          review.source_evidence->>'source_url',
          ''
        ), '#', 1), '?', 1), '/+$', '') =
          regexp_replace(split_part(split_part(candidate.canonical_url, '#', 1), '?', 1), '/+$', '')
    )
  ORDER BY review.id
  FOR SHARE OF review;

  SELECT count(*) FILTER (
    WHERE NOT public.card_enrichment_enqueue_catalog_eligible(
      candidate.card_id,
      candidate.issuer,
      candidate.canonical_url,
      candidate.final_url_hash,
      candidate.bank,
      candidate.card_url,
      candidate.card_type,
      candidate.is_discontinued,
      EXISTS (
        SELECT 1 FROM public.user_cards AS holder
        WHERE holder.catalog_card_id = candidate.card_id
          AND holder.is_active = true
      ),
      public.card_has_unresolved_catalog_identity(
        candidate.card_id, candidate.canonical_url
      )
    )
  )
  INTO invalid_count
  FROM jsonb_to_recordset(locked_jobs) AS candidate(
    card_id uuid, issuer text, canonical_url text, final_url_hash text,
    content_hash text, parser_version text, job_key text, run_mode text,
    result_summary jsonb, bank text, card_url text, card_type text,
    is_discontinued boolean
  );
  IF jsonb_array_length(locked_jobs) <> input_count OR invalid_count <> 0 THEN
    RAISE EXCEPTION 'ineligible_enrichment_enqueue';
  END IF;

  -- A changed job key for an existing v6 card/parser is an identity conflict,
  -- never a partial batch success. Exact repeats remain idempotent.
  IF EXISTS (
    SELECT 1
    FROM jsonb_to_recordset(locked_jobs) AS candidate(
      card_id uuid, parser_version text, job_key text
    )
    JOIN public.card_catalog_enrichment_jobs AS existing_job
      ON existing_job.card_id = candidate.card_id
     AND existing_job.parser_version = candidate.parser_version
    WHERE existing_job.job_key IS DISTINCT FROM candidate.job_key
  ) THEN
    RAISE EXCEPTION 'duplicate_v6_card_parser_identity';
  END IF;

  INSERT INTO public.card_catalog_enrichment_jobs (
    card_id, issuer, canonical_url, final_url_hash, content_hash,
    parser_version, status, run_mode, job_key, result_summary, updated_at
  )
  SELECT candidate.card_id, trim(candidate.issuer),
    trim(candidate.canonical_url), lower(candidate.final_url_hash),
    lower(candidate.content_hash), trim(candidate.parser_version), 'queued',
    candidate.run_mode, candidate.job_key, candidate.result_summary,
    statement_timestamp()
  FROM jsonb_to_recordset(locked_jobs) AS candidate(
    card_id uuid, issuer text, canonical_url text, final_url_hash text,
    content_hash text, parser_version text, job_key text, run_mode text,
    result_summary jsonb
  )
  ORDER BY candidate.card_id, trim(candidate.parser_version)
  ON CONFLICT (job_key) DO NOTHING;
  GET DIAGNOSTICS inserted_count = ROW_COUNT;
  IF NOT public.card_enrichment_enqueue_count_is_valid(
    input_count, inserted_count
  ) THEN
    RAISE EXCEPTION 'invalid_enrichment_enqueue_count';
  END IF;
  RETURN inserted_count;
END;
$_$;


--
-- Name: enrich_waitlist(text, text, text, text, text, text, text[], boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.enrich_waitlist(p_enrichment_token text, p_name text DEFAULT NULL::text, p_card_count text DEFAULT NULL::text, p_monthly_spend_band text DEFAULT NULL::text, p_primary_goal text DEFAULT NULL::text, p_problem_detail text DEFAULT NULL::text, p_top_cards text[] DEFAULT NULL::text[], p_marketing_consent boolean DEFAULT false) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $_$
DECLARE v_token text := lower(btrim(p_enrichment_token)); v_hash text;
BEGIN
  IF v_token IS NULL OR v_token !~ '^[0-9a-f]{64}$' THEN RETURN false; END IF;
  IF p_card_count IS NULL
     OR p_monthly_spend_band IS NULL
     OR p_primary_goal IS NULL
     OR p_card_count NOT IN ('1-2','3-6','7+')
     OR p_monthly_spend_band NOT IN ('under-25k','25k-50k','50k-1l','1l-plus')
     OR p_primary_goal NOT IN ('maximize_rewards','track_benefits','simplify_card_choices')
     OR char_length(COALESCE(p_name,'')) > 100 OR char_length(COALESCE(p_problem_detail,'')) > 500
     OR (p_top_cards IS NOT NULL AND (
       cardinality(p_top_cards) > 2
       OR EXISTS (
         SELECT 1 FROM unnest(p_top_cards) AS card_name
         WHERE card_name IS NULL
            OR char_length(btrim(card_name)) NOT BETWEEN 1 AND 100
       )
     )) THEN
    RAISE EXCEPTION 'waitlist enrichment is invalid' USING ERRCODE = '22023';
  END IF;
  v_hash := encode(extensions.digest(v_token, 'sha256'), 'hex');
  UPDATE public.waitlist SET name = nullif(btrim(p_name), ''), card_count = p_card_count,
    monthly_spend_band = p_monthly_spend_band, primary_goal = p_primary_goal,
    problem_detail = nullif(btrim(p_problem_detail), ''),
    top_cards = CASE WHEN p_top_cards IS NULL THEN NULL ELSE ARRAY(
      SELECT btrim(card_name) FROM unnest(p_top_cards) AS card_name
    ) END,
    marketing_consent_requested_at = CASE WHEN p_marketing_consent THEN COALESCE(marketing_consent_requested_at, now()) ELSE marketing_consent_requested_at END,
    enriched_at = now(), enrichment_token_hash = NULL WHERE enrichment_token_hash = v_hash;
  RETURN true;
END; $_$;


--
-- Name: finalize_card_catalog_enrichment_job(uuid, uuid, text, uuid, text, jsonb, jsonb, text, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.finalize_card_catalog_enrichment_job(_job_id uuid, _lease_token uuid, _status text, _staging_id uuid, _content_hash text, _normalized_fields jsonb, _result_summary jsonb, _failure_category text, _next_retry_at timestamp with time zone) RETURNS uuid
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  affected_rows integer;
  job_row public.card_catalog_enrichment_jobs%ROWTYPE;
  staging_row public.card_benefits_staging%ROWTYPE;
  job_card_id uuid;
  candidate_staging_id uuid;
  current_observation jsonb;
  existing_observation_history jsonb;
  observation_history jsonb;
  safe_summary jsonb;
  has_pending_staging boolean;
  effective_status text;
  resolved_staging_id uuid;
  locked_staging_status text;
  locked_staging_valid boolean := false;
BEGIN
  IF _job_id IS NULL OR _lease_token IS NULL
     OR _status NOT IN ('staged', 'completed', 'quarantined', 'failed', 'review_required')
     OR jsonb_typeof(coalesce(_normalized_fields, '{}'::jsonb)) <> 'object'
     OR jsonb_typeof(coalesce(_result_summary, '{}'::jsonb)) <> 'object'
     OR (_status = 'staged' AND _staging_id IS NULL)
     OR (_status = 'completed' AND _staging_id IS NOT NULL)
     OR (_status = 'failed' AND _next_retry_at IS NULL)
     OR (_status <> 'failed' AND _next_retry_at IS NOT NULL) THEN
    RAISE EXCEPTION 'invalid_enrichment_finalization';
  END IF;
  -- Resolve only immutable identity before participating in the exact Task 3/4
  -- review serialization protocol. No queue or staging decision is cached.
  SELECT candidate.card_id INTO job_card_id
  FROM public.card_catalog_enrichment_jobs AS candidate
  WHERE candidate.id = _job_id;
  IF job_card_id IS NULL THEN
    RAISE EXCEPTION 'stale_enrichment_lease';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'card_benefit_enrichment_review:' || job_card_id::text,
    0
  ));

  SELECT candidate.* INTO job_row
  FROM public.card_catalog_enrichment_jobs AS candidate
  WHERE candidate.id = _job_id
    AND candidate.card_id = job_card_id
    AND candidate.status = 'processing'
    AND candidate.lease_token = _lease_token
    AND candidate.lease_expires_at > now()
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'stale_enrichment_lease'; END IF;

  candidate_staging_id := coalesce(_staging_id, job_row.staging_id);
  IF candidate_staging_id IS NOT NULL THEN
    SELECT staging.* INTO staging_row
    FROM public.card_benefits_staging AS staging
    WHERE staging.id = candidate_staging_id
      AND staging.card_id = job_row.card_id
      AND staging.parser_version = job_row.parser_version
      AND staging.request_type = 'official_benefit_enrichment'
    FOR UPDATE;
    IF FOUND THEN
      locked_staging_status := staging_row.status;
      locked_staging_valid := public.is_valid_official_source_evidence(
        staging_row.source_evidence
      );
    END IF;
  END IF;

  SELECT state.effective_status, state.audit_staging_id,
    state.has_pending_staging
  INTO effective_status, resolved_staging_id, has_pending_staging
  FROM public.card_enrichment_final_staging_state(
    _status, _staging_id, job_row.staging_id, staging_row.id,
    locked_staging_status, locked_staging_valid
  ) AS state;

  current_observation := public.sanitize_card_enrichment_observation(
    _result_summary->'observation', statement_timestamp()
  );
  existing_observation_history := CASE
    WHEN jsonb_typeof(job_row.result_summary->'observation') = 'object'
      THEN jsonb_build_array(job_row.result_summary->'observation')
    ELSE '[]'::jsonb
  END || CASE
    WHEN jsonb_typeof(job_row.result_summary->'observations') = 'array'
      THEN job_row.result_summary->'observations'
    ELSE '[]'::jsonb
  END;
  observation_history := public.normalize_card_enrichment_observation_history(
    existing_observation_history,
    _result_summary->'observation',
    statement_timestamp()
  );
  safe_summary := public.sanitize_card_enrichment_result_summary(_result_summary) ||
    jsonb_build_object('observations', observation_history);
  IF current_observation IS NOT NULL THEN
    safe_summary := safe_summary || jsonb_build_object('observation', current_observation);
  END IF;
  IF job_row.result_summary->'pilot_qualified' = 'true'::jsonb THEN
    safe_summary := safe_summary || jsonb_build_object('pilot_qualified', true);
  END IF;

  UPDATE public.card_catalog_enrichment_jobs
  SET status = effective_status,
      lease_expires_at = NULL,
      lease_token = NULL,
      staging_id = resolved_staging_id,
      content_hash = coalesce(_content_hash, job_row.content_hash),
      normalized_fields = coalesce(_normalized_fields, '{}'::jsonb),
      result_summary = safe_summary,
      failure_category = CASE
        WHEN _status = 'staged' AND resolved_staging_id IS NULL
          THEN 'invalid_enrichment_staging'
        ELSE _failure_category
      END,
      next_retry_at = CASE
        WHEN has_pending_staging THEN NULL
        ELSE _next_retry_at
      END,
      next_run_at = NULL,
      updated_at = now()
  WHERE id = _job_id
    AND status = 'processing'
    AND lease_token = _lease_token;
  GET DIAGNOSTICS affected_rows = ROW_COUNT;
  IF affected_rows <> 1 THEN RAISE EXCEPTION 'stale_enrichment_lease'; END IF;
  RETURN _job_id;
END;
$$;


--
-- Name: get_card_catalog(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_card_catalog() RETURNS TABLE(id uuid, bank text, card_name text, network text, card_type text, joining_fee numeric, annual_fee numeric, apr numeric, is_discontinued boolean, created_at timestamp with time zone, updated_at timestamp with time zone)
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
BEGIN
    RETURN QUERY
    SELECT
        cc.id,
        cc.bank,
        cc.card_name,
        cc.network,
        cc.card_type,
        cc.joining_fee,
        cc.annual_fee,
        cc.apr,
        cc.is_discontinued,
        cc.created_at,
        cc.updated_at
    FROM card_catalog cc
    WHERE cc.is_discontinued = false
    ORDER BY cc.bank, cc.card_name;
END;
$$;


--
-- Name: get_movie_benefit_mapping_health(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_movie_benefit_mapping_health() RETURNS TABLE(metric text, value bigint)
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
  IF auth.role() <> 'service_role' THEN
    RAISE EXCEPTION 'service_role_required' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  WITH movie_benefits AS (
    SELECT benefit.benefit_id
    FROM public.benefits AS benefit
    WHERE benefit.is_active = true
      AND (
        benefit.benefit_category = 'entertainment'
        OR benefit.value_config ->> 'category' ILIKE '%movie%'
        OR benefit.value_config ->> 'discount_type' ILIKE '%movie%'
        OR benefit.title ILIKE '%movie%'
        OR benefit.description ILIKE '%movie%'
        OR benefit.title ILIKE '%cinema%'
        OR benefit.description ILIKE '%cinema%'
        OR benefit.title ILIKE '%bookmyshow%'
        OR benefit.description ILIKE '%bookmyshow%'
        OR benefit.title ILIKE '%pvr%'
        OR benefit.description ILIKE '%pvr%'
        OR benefit.title ILIKE '%inox%'
        OR benefit.description ILIKE '%inox%'
        OR benefit.title ILIKE '%cinepolis%'
        OR benefit.description ILIKE '%cinepolis%'
      )
  ), mapped_movie_benefits AS (
    SELECT DISTINCT movie.benefit_id
    FROM movie_benefits AS movie
    JOIN public.card_benefit_mapping AS mapping
      ON mapping.benefit_id = movie.benefit_id
  )
  SELECT 'active_movie_benefits'::text, count(*)::bigint
  FROM movie_benefits
  UNION ALL
  SELECT 'mapped_active_movie_benefits'::text, count(*)::bigint
  FROM mapped_movie_benefits
  UNION ALL
  SELECT 'orphaned_active_movie_benefits'::text,
         (SELECT count(*) FROM movie_benefits) - count(*)
  FROM mapped_movie_benefits;
END;
$$;


--
-- Name: get_user_transactions(uuid, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_user_transactions(_user_id uuid, _limit integer DEFAULT 50) RETURNS TABLE(id uuid, user_id uuid, user_card_id uuid, amount numeric, currency text, description text, merchant_name text, category text, transaction_type text, transaction_date timestamp with time zone, location text, reward_earned numeric, reward_type text, statement_id text, metadata jsonb, created_at timestamp with time zone, updated_at timestamp with time zone, bank text, card_name text, last_four_digits text, network text, card_type text)
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
BEGIN
    RETURN QUERY
    SELECT
        t.id,
        t.user_id,
        t.user_card_id,
        t.amount,
        t.currency,
        t.description,
        t.merchant_name,
        t.category,
        t.transaction_type,
        t.transaction_date,
        t.location,
        t.reward_earned,
        t.reward_type,
        t.statement_id::text,
        t.metadata,
        t.created_at,
        t.updated_at,
        -- Card details from catalog via user_cards
        cc.bank,
        cc.card_name,
        uc.last_four_digits,
        cc.network,
        cc.card_type
    FROM transactions t
    LEFT JOIN user_cards uc ON t.user_card_id = uc.id
    LEFT JOIN card_catalog cc ON uc.catalog_card_id = cc.id
    WHERE t.user_id = _user_id
    ORDER BY t.transaction_date DESC
    LIMIT _limit;
END;
$$;


--
-- Name: initialize_card_benefit_enrichment_pilot(jsonb, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.initialize_card_benefit_enrichment_pilot(_candidates jsonb, _parser_version text) RETURNS SETOF public.card_catalog_enrichment_jobs
    LANGUAGE plpgsql
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
DECLARE
  selected_parser text := CASE
    WHEN lower(trim(coalesce(_parser_version, ''))) = 'benefits-v6'
      THEN 'benefits-v6'
    ELSE trim(coalesce(_parser_version, ''))
  END;
  pilot_count integer;
  promoted_count integer;
  pilot_card_count integer;
  pilot_profile_count integer;
  pilot_issuer_count integer;
  pilot_profiles text[];
  pilot_issuer_values_valid boolean;
  has_duplicate boolean;
  cohort_action text;
  eligible_count integer;
  distinct_card_count integer;
  distinct_profile_count integer;
  distinct_issuer_count integer;
  inserted_count integer;
  locked_candidates jsonb;
  candidate_identity record;
BEGIN
  IF coalesce(auth.role(), '') <> 'service_role' THEN
    RAISE EXCEPTION 'service_role_required';
  END IF;
  IF _candidates IS NULL OR jsonb_typeof(_candidates) <> 'array'
     OR jsonb_array_length(_candidates) <> 5
     OR length(selected_parser) < 3 THEN
    RAISE EXCEPTION 'invalid_pilot_candidates';
  END IF;
  IF lower(selected_parser) = 'catalog-v1' THEN
    RAISE EXCEPTION 'reserved_parser_version';
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended('card_benefit_enrichment_pilot:' || selected_parser, 0)
  );
  WITH locked_cohort AS MATERIALIZED (
    SELECT job.*
    FROM public.card_catalog_enrichment_jobs AS job
    WHERE job.parser_version = selected_parser
      AND (
        job.run_mode = 'pilot'
        OR (
          job.run_mode = 'scheduled'
          AND job.result_summary->'pilot_qualified' = 'true'::jsonb
        )
      )
    ORDER BY job.id
    FOR UPDATE OF job
  )
  SELECT count(*) FILTER (WHERE locked_cohort.run_mode = 'pilot'),
    count(*) FILTER (WHERE locked_cohort.run_mode = 'scheduled')
  INTO pilot_count, promoted_count
  FROM locked_cohort;
  SELECT EXISTS (
    SELECT 1
    FROM public.card_catalog_enrichment_jobs AS cohort_job
    JOIN public.card_catalog_enrichment_jobs AS other_job
      ON other_job.card_id = cohort_job.card_id
     AND other_job.parser_version = cohort_job.parser_version
     AND other_job.id <> cohort_job.id
    WHERE cohort_job.parser_version = selected_parser
      AND (
        cohort_job.run_mode = 'pilot'
        OR (
          cohort_job.run_mode = 'scheduled'
          AND cohort_job.result_summary->'pilot_qualified' = 'true'::jsonb
        )
      )
  ) INTO has_duplicate;
  cohort_action := public.card_enrichment_pilot_cohort_action(
    pilot_count, promoted_count, has_duplicate
  );

  IF cohort_action = 'return_promoted' THEN
    RETURN QUERY
    SELECT job.*
    FROM public.card_catalog_enrichment_jobs AS job
    JOIN public.card_catalog AS card ON card.id = job.card_id
    WHERE job.parser_version = selected_parser
      AND job.run_mode = 'scheduled'
      AND job.result_summary->'pilot_qualified' = 'true'::jsonb
    ORDER BY job.issuer, card.card_name, job.created_at;
    RETURN;
  ELSIF cohort_action = 'return_pilot' THEN
    RETURN QUERY
    SELECT job.*
    FROM public.card_catalog_enrichment_jobs AS job
    JOIN public.card_catalog AS card ON card.id = job.card_id
    WHERE job.parser_version = selected_parser
      AND job.run_mode = 'pilot'
    ORDER BY job.issuer, card.card_name, job.created_at;
    RETURN;
  ELSIF cohort_action <> 'initialize' THEN
    RAISE EXCEPTION 'pilot_state_incomplete';
  END IF;

  FOR candidate_identity IN
    SELECT DISTINCT candidate.card_id
    FROM jsonb_to_recordset(_candidates)
      AS candidate(card_id uuid, profile text)
    ORDER BY candidate.card_id
  LOOP
    PERFORM pg_advisory_xact_lock(hashtextextended(
      'card_benefit_enrichment_identity:' || candidate_identity.card_id::text ||
        ':' || selected_parser,
      0
    ));
  END LOOP;

  WITH input AS (
    SELECT candidate.card_id, lower(trim(candidate.profile)) AS profile
    FROM jsonb_to_recordset(_candidates)
      AS candidate(card_id uuid, profile text)
  ), locked_candidate_authority AS MATERIALIZED (
    SELECT input.card_id, input.profile, card.bank, card.card_url,
      card.is_discontinued, card.card_type
    FROM input
    JOIN public.card_catalog AS card ON card.id = input.card_id
    ORDER BY card.id
    FOR UPDATE OF card
  )
  SELECT coalesce(
    jsonb_agg(to_jsonb(authority) ORDER BY authority.card_id),
    '[]'::jsonb
  )
  INTO locked_candidates
  FROM locked_candidate_authority AS authority;

  WITH eligible AS (
    SELECT candidate.*
    FROM jsonb_to_recordset(locked_candidates) AS candidate(
      card_id uuid, profile text, bank text, card_url text,
      is_discontinued boolean, card_type text
    )
    WHERE candidate.is_discontinued = false
      AND lower(trim(candidate.card_type)) = 'credit'
      AND candidate.card_url ~ '^https://'
      AND candidate.profile IN (
        'straightforward', 'redirect_or_js', 'terms_linked',
        'known_invalid', 'additional_valid'
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.card_catalog_enrichment_jobs AS existing_job
        WHERE existing_job.card_id = candidate.card_id
          AND existing_job.parser_version = selected_parser
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
  SELECT candidate.card_id, candidate.bank, trim(candidate.card_url),
    encode(extensions.digest(convert_to(trim(candidate.card_url), 'UTF8'), 'sha256'), 'hex'),
    NULL, selected_parser, 'queued', 'pilot',
    candidate.card_id::text || ':' ||
      encode(extensions.digest(convert_to(trim(candidate.card_url), 'UTF8'), 'sha256'), 'hex') ||
      ':' || selected_parser,
    jsonb_build_object(
      'pilot_profile', candidate.profile,
      'unsafe_mutation_count', 0,
      'raw_body_stored', false,
      'evidence_passed', false,
      'idempotency_passed', false
    ),
    now()
  FROM jsonb_to_recordset(locked_candidates) AS candidate(
    card_id uuid, profile text, bank text, card_url text,
    is_discontinued boolean, card_type text
  )
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.card_catalog_enrichment_jobs AS existing_job
    WHERE existing_job.card_id = candidate.card_id
      AND existing_job.parser_version = selected_parser
  )
  ON CONFLICT (job_key) DO NOTHING;
  GET DIAGNOSTICS inserted_count = ROW_COUNT;
  IF inserted_count <> 5 THEN
    RAISE EXCEPTION 'pilot_candidate_conflict';
  END IF;

  RETURN QUERY
  SELECT job.*
  FROM public.card_catalog_enrichment_jobs AS job
  JOIN public.card_catalog AS card ON card.id = job.card_id
  WHERE job.parser_version = selected_parser
    AND job.run_mode = 'pilot'
  ORDER BY job.issuer, card.card_name, job.created_at;
END;
$$;


--
-- Name: join_waitlist(text, text, text, text, text, text, text, text, text, boolean, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.join_waitlist(p_email text, p_source text DEFAULT NULL::text, p_utm_source text DEFAULT NULL::text, p_utm_medium text DEFAULT NULL::text, p_utm_campaign text DEFAULT NULL::text, p_utm_term text DEFAULT NULL::text, p_utm_content text DEFAULT NULL::text, p_referrer_path text DEFAULT NULL::text, p_landing_variant text DEFAULT NULL::text, p_privacy_consent boolean DEFAULT false, p_website text DEFAULT NULL::text) RETURNS TABLE(status text, enrichment_token text)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $_$
DECLARE
  v_email text := lower(btrim(p_email));
  v_token text := encode(extensions.gen_random_bytes(32), 'hex');
  v_hash text;
  v_window timestamptz := date_bin('15 minutes', now(), timestamptz '2001-01-01');
  v_attempts integer;
BEGIN
  IF v_email IS NULL OR char_length(v_email) NOT BETWEEN 3 AND 254
     OR v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
     OR p_privacy_consent IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'valid email and privacy consent are required' USING ERRCODE = '22023';
  END IF;
  IF (nullif(btrim(p_source), '') IS NOT NULL AND btrim(p_source) !~ '^[a-z0-9][a-z0-9_-]{0,63}$')
     OR (nullif(btrim(p_landing_variant), '') IS NOT NULL AND btrim(p_landing_variant) !~ '^[a-z0-9][a-z0-9_-]{0,63}$')
     OR char_length(COALESCE(p_utm_source, '')) > 100 OR char_length(COALESCE(p_utm_medium, '')) > 100
     OR char_length(COALESCE(p_utm_campaign, '')) > 150 OR char_length(COALESCE(p_utm_term, '')) > 150
     OR char_length(COALESCE(p_utm_content, '')) > 150 OR char_length(COALESCE(p_referrer_path, '')) > 512
     OR (nullif(btrim(p_referrer_path), '') IS NOT NULL AND left(btrim(p_referrer_path), 1) <> '/') THEN
    RAISE EXCEPTION 'waitlist attribution is invalid' USING ERRCODE = '22023';
  END IF;
  v_hash := encode(extensions.digest(v_email, 'sha256'), 'hex');
  INSERT INTO public.waitlist_public_attempts(email_hash, window_started, attempt_count)
  VALUES (v_hash, v_window, 1)
  ON CONFLICT (email_hash, window_started) DO UPDATE
    SET attempt_count = public.waitlist_public_attempts.attempt_count + 1
  RETURNING attempt_count INTO v_attempts;
  IF nullif(btrim(p_website), '') IS NULL AND v_attempts <= 5 THEN
    INSERT INTO public.waitlist(email, enrichment_token_hash, acquisition_source, landing_variant,
      utm_source, utm_medium, utm_campaign, utm_term, utm_content, referrer_path, privacy_consent_at)
    VALUES (v_email, encode(extensions.digest(v_token, 'sha256'), 'hex'), nullif(btrim(p_source), ''),
      nullif(btrim(p_landing_variant), ''), nullif(btrim(p_utm_source), ''), nullif(btrim(p_utm_medium), ''),
      nullif(btrim(p_utm_campaign), ''), nullif(btrim(p_utm_term), ''), nullif(btrim(p_utm_content), ''),
      nullif(btrim(p_referrer_path), ''), now()) ON CONFLICT DO NOTHING;
  END IF;
  RETURN QUERY SELECT 'accepted'::text, v_token;
END; $_$;


--
-- Name: list_pending_catalog_entry_requests(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.list_pending_catalog_entry_requests() RETURNS TABLE(id uuid, source_url text, bank_name text, card_name text, requested_by uuid, created_at timestamp with time zone, extracted_data jsonb)
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT
    s.id,
    s.source_url,
    trim(s.extracted_data->>'bank_name') AS bank_name,
    trim(s.extracted_data->>'card_name') AS card_name,
    s.requested_by,
    s.created_at,
    s.extracted_data
  FROM public.card_benefits_staging s
  WHERE s.status = 'pending'
    AND s.card_id IS NULL
    AND s.extracted_data->>'request_type' = 'catalog_entry'
  ORDER BY s.created_at ASC;
$$;


--
-- Name: next_card_enrichment_observation_at(uuid, text, boolean, boolean, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.next_card_enrichment_observation_at(_card_id uuid, _completed_at text, _is_discontinued boolean, _has_active_cardholder boolean, _outcome text) RETURNS timestamp with time zone
    LANGUAGE plpgsql STABLE
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  normalized_outcome text := lower(trim(coalesce(_outcome, '')));
  completed_at_value timestamptz;
  cadence_seconds bigint;
  jitter_days integer;
BEGIN
  completed_at_value := public.canonical_card_enrichment_timestamp(_completed_at);
  IF _card_id IS NULL OR completed_at_value IS NULL
     OR completed_at_value > statement_timestamp() + interval '5 minutes'
     OR _is_discontinued IS NULL OR _has_active_cardholder IS NULL THEN
    RAISE EXCEPTION 'invalid_recurrence_policy';
  END IF;
  IF _is_discontinued AND NOT _has_active_cardholder THEN
    RETURN NULL;
  END IF;
  IF normalized_outcome IN ('success', 'not_modified') THEN
    cadence_seconds := extract(epoch FROM interval '30 days')::bigint;
    jitter_days := public.card_enrichment_jitter_days(_card_id, 3);
  ELSIF normalized_outcome IN ('blocked', 'missing', 'failed') THEN
    cadence_seconds := extract(epoch FROM interval '7 days')::bigint;
    jitter_days := public.card_enrichment_jitter_days(_card_id, 1);
  ELSE
    RAISE EXCEPTION 'invalid_recurrence_outcome';
  END IF;
  RETURN to_timestamp(
    extract(epoch FROM completed_at_value) + cadence_seconds +
    (jitter_days::bigint * 86400)
  );
END;
$$;


--
-- Name: normalize_benefit_exclusions_shape(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.normalize_benefit_exclusions_shape() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
  NEW.exclusions := public.normalize_benefit_exclusions_value(NEW.exclusions);
  RETURN NEW;
END;
$$;


--
-- Name: normalize_benefit_exclusions_value(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.normalize_benefit_exclusions_value(_exclusions jsonb) RETURNS jsonb
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO 'pg_catalog'
    AS $_$
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
$_$;


--
-- Name: normalize_card_catalog_family(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.normalize_card_catalog_family(_value text) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $_$
  SELECT lower(regexp_replace(
    regexp_replace(
      regexp_replace(
        trim(regexp_replace(coalesce(_value, ''),
          '^(fees[[:space:]]+and[[:space:]]+charges[[:space:]]+for|terms[[:space:]]+and[[:space:]]+conditions[[:space:]]+for|benefits[[:space:]]+of)[[:space:]]+',
          '', 'i')),
        '\m(visa|master[[:space:]]*card|rupay|american[[:space:]]+express|amex|bank|credit|card|statement|your|the|for|club|axis|hdfc|icici|kotak|mahindra|indusind|hsbc|pnb|punjab|national|sbi|au|world[[:space:]-]+elite|infinite|signature|world|platinum|gold|select|classic)\M',
        ' ', 'gi'
      ),
      '([[:space:]]+credit)?[[:space:]]+card$', '', 'i'
    ),
    '[^a-zA-Z0-9]+', '', 'g'
  ));
$_$;


--
-- Name: normalize_card_catalog_network(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.normalize_card_catalog_network(_value text) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
  SELECT CASE
    WHEN lower(regexp_replace(trim(coalesce(_value, '')), '[^a-z0-9]+', '', 'g'))
      IN ('mastercard', 'master') THEN 'mastercard'
    WHEN lower(regexp_replace(trim(coalesce(_value, '')), '[^a-z0-9]+', '', 'g'))
      IN ('americanexpress', 'amex') THEN 'americanexpress'
    WHEN lower(regexp_replace(trim(coalesce(_value, '')), '[^a-z0-9]+', '', 'g')) = 'visa' THEN 'visa'
    WHEN lower(regexp_replace(trim(coalesce(_value, '')), '[^a-z0-9]+', '', 'g')) = 'rupay' THEN 'rupay'
    ELSE nullif(lower(regexp_replace(trim(coalesce(_value, '')), '[^a-z0-9]+', '', 'g')), '')
  END;
$$;


--
-- Name: normalize_card_catalog_product(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.normalize_card_catalog_product(_value text) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $_$
  SELECT lower(regexp_replace(
    regexp_replace(
      regexp_replace(
        trim(regexp_replace(coalesce(_value, ''),
          '^(fees[[:space:]]+and[[:space:]]+charges[[:space:]]+for|terms[[:space:]]+and[[:space:]]+conditions[[:space:]]+for|benefits[[:space:]]+of)[[:space:]]+',
          '', 'i')),
        '\m(visa|master[[:space:]]*card|rupay|american[[:space:]]+express|amex|bank|credit|card|statement|your|the|for|club|axis|hdfc|icici|kotak|mahindra|indusind|hsbc|pnb|punjab|national|sbi|au)\M',
        ' ', 'gi'
      ),
      '([[:space:]]+credit)?[[:space:]]+card$', '', 'i'
    ),
    '[^a-zA-Z0-9]+', '', 'g'
  ));
$_$;


--
-- Name: normalize_card_catalog_tier(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.normalize_card_catalog_tier(_value text) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
  SELECT CASE
    WHEN lower(coalesce(_value, '')) ~ '\mworld[[:space:]-]+elite\M' THEN 'world-elite'
    WHEN lower(coalesce(_value, '')) ~ '\minfinite\M' THEN 'infinite'
    WHEN lower(coalesce(_value, '')) ~ '\msignature\M' THEN 'signature'
    WHEN lower(coalesce(_value, '')) ~ '\mworld\M' THEN 'world'
    WHEN lower(coalesce(_value, '')) ~ '\mplatinum\M' THEN 'platinum'
    WHEN lower(coalesce(_value, '')) ~ '\mgold\M' THEN 'gold'
    WHEN lower(coalesce(_value, '')) ~ '\mselect\M' THEN 'select'
    WHEN lower(coalesce(_value, '')) ~ '\mclassic\M' THEN 'classic'
    ELSE NULL
  END;
$$;


--
-- Name: normalize_card_enrichment_observation_history(jsonb, jsonb, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.normalize_card_enrichment_observation_history(_existing_history jsonb, _current_observation jsonb, _now timestamp with time zone) RETURNS jsonb
    LANGUAGE sql STABLE
    SET search_path TO 'public', 'pg_temp'
    AS $$
  WITH raw_observations AS (
    SELECT observation, observation_index::bigint AS source_priority
    FROM jsonb_array_elements(
      CASE WHEN jsonb_typeof(_existing_history) = 'array'
        THEN _existing_history ELSE '[]'::jsonb END
    ) WITH ORDINALITY AS existing(observation, observation_index)
    UNION ALL
    SELECT _current_observation, 0::bigint
  ), sanitized AS (
    SELECT public.sanitize_card_enrichment_observation(observation, _now) AS observation,
      source_priority
    FROM raw_observations
  ), deduplicated AS (
    SELECT DISTINCT ON (
      observation->>'observed_at',
      coalesce(observation->>'source_manifest_hash', ''),
      coalesce(observation->>'canonical_benefit_hash', '')
    ) observation
    FROM sanitized
    WHERE observation IS NOT NULL
    ORDER BY observation->>'observed_at',
      coalesce(observation->>'source_manifest_hash', ''),
      coalesce(observation->>'canonical_benefit_hash', ''),
      source_priority
  ), newest AS (
    SELECT observation
    FROM deduplicated
    ORDER BY (observation->>'observed_at')::timestamptz DESC,
      observation->>'source_manifest_hash', observation->>'canonical_benefit_hash'
    LIMIT 24
  )
  SELECT coalesce(jsonb_agg(observation ORDER BY
    (observation->>'observed_at')::timestamptz DESC,
    observation->>'source_manifest_hash', observation->>'canonical_benefit_hash'
  ), '[]'::jsonb)
  FROM newest;
$$;


--
-- Name: normalize_card_resource_path(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.normalize_card_resource_path(_path text) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
DECLARE
  segment text;
  decoded_segment text;
  retained_segments text[] := ARRAY[]::text[];
BEGIN
  FOREACH segment IN ARRAY regexp_split_to_array(coalesce(_path, ''), '/') LOOP
    decoded_segment := lower(public.decode_card_resource_component(
      replace(segment, '+', '%2B')
    ));
    IF segment = '' OR decoded_segment = '.' THEN
      CONTINUE;
    ELSIF decoded_segment = '..' THEN
      IF cardinality(retained_segments) > 0 THEN
        retained_segments := retained_segments[1:cardinality(retained_segments) - 1];
      END IF;
    ELSE
      retained_segments := array_append(retained_segments, segment);
    END IF;
  END LOOP;
  RETURN '/' || array_to_string(retained_segments, '/');
END;
$$;


--
-- Name: promote_qualified_card_benefit_enrichment_pilot(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.promote_qualified_card_benefit_enrichment_pilot(_parser_version text) RETURNS SETOF public.card_catalog_enrichment_jobs
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  selected_parser text := lower(trim(coalesce(_parser_version, '')));
  pilot_count integer;
  promoted_count integer;
  pilot_card_count integer;
  pilot_profile_count integer;
  pilot_issuer_count integer;
  pilot_profiles text[];
  pilot_issuer_values_valid boolean;
  all_qualified boolean;
  pilot_card_id uuid;
BEGIN
  IF selected_parser <> 'benefits-v6' THEN
    RAISE EXCEPTION 'invalid_pilot_promotion';
  END IF;
  PERFORM pg_advisory_xact_lock(
    hashtextextended('card_benefit_enrichment_pilot:' || selected_parser, 0)
  );
  FOR pilot_card_id IN
    SELECT job.card_id
    FROM public.card_catalog_enrichment_jobs AS job
    WHERE job.parser_version = selected_parser
      AND (job.run_mode = 'pilot'
        OR job.result_summary->'pilot_qualified' = 'true'::jsonb)
    ORDER BY job.card_id
  LOOP
    PERFORM pg_advisory_xact_lock(hashtextextended(
      'card_benefit_enrichment_review:' || pilot_card_id::text,
      0
    ));
  END LOOP;
  PERFORM 1 FROM public.card_catalog_enrichment_jobs AS job
    WHERE job.parser_version = selected_parser
      AND (job.run_mode = 'pilot'
        OR job.result_summary->'pilot_qualified' = 'true'::jsonb)
    ORDER BY job.id FOR UPDATE OF job;
  PERFORM 1 FROM public.card_benefits_staging AS staging
    JOIN public.card_catalog_enrichment_jobs AS job
      ON nullif(job.normalized_fields->'pilot_evidence'->>'staging_id', '')::uuid = staging.id
    WHERE job.parser_version = selected_parser
      AND (job.run_mode = 'pilot'
        OR job.result_summary->'pilot_qualified' = 'true'::jsonb)
    ORDER BY staging.id FOR UPDATE OF staging;
  -- Block a review/source/live mutation from racing the read/decision boundary.
  LOCK TABLE public.card_catalog_review_queue IN SHARE MODE;
  LOCK TABLE public.card_benefit_mapping IN SHARE MODE;
  LOCK TABLE public.benefits IN SHARE MODE;
  PERFORM 1 FROM public.card_catalog_review_queue AS review
    WHERE review.status = 'pending' ORDER BY review.id FOR SHARE;
  PERFORM 1 FROM public.card_catalog AS card
    JOIN public.card_catalog_enrichment_jobs AS job ON job.card_id = card.id
    WHERE job.parser_version = selected_parser ORDER BY card.id FOR SHARE OF card;
  PERFORM 1 FROM public.card_benefit_mapping AS mapping
    JOIN public.card_catalog_enrichment_jobs AS job ON job.card_id = mapping.card_id
    WHERE job.parser_version = selected_parser ORDER BY mapping.mapping_id FOR SHARE OF mapping;
  PERFORM 1 FROM public.benefits AS benefit
    JOIN public.card_benefit_mapping AS mapping ON mapping.benefit_id = benefit.benefit_id
    JOIN public.card_catalog_enrichment_jobs AS job ON job.card_id = mapping.card_id
    WHERE job.parser_version = selected_parser ORDER BY benefit.benefit_id FOR SHARE OF benefit;
  WITH locked_pilot AS MATERIALIZED (
    SELECT job.*
    FROM public.card_catalog_enrichment_jobs AS job
    WHERE job.parser_version = selected_parser
      AND (
        job.run_mode = 'pilot'
        OR (
          job.run_mode = 'scheduled'
          AND job.result_summary->'pilot_qualified' = 'true'::jsonb
        )
      )
    ORDER BY job.id
    FOR UPDATE OF job
  ), locked_staging AS MATERIALIZED (
    SELECT staging.*
    FROM public.card_benefits_staging AS staging
    JOIN locked_pilot AS pilot
      ON nullif(pilot.normalized_fields->'pilot_evidence'->>'staging_id', '')::uuid = staging.id
    ORDER BY staging.id
    FOR UPDATE OF staging
  )
  SELECT count(*) FILTER (WHERE locked_pilot.run_mode = 'pilot'),
    count(*) FILTER (WHERE locked_pilot.run_mode = 'scheduled'),
    count(DISTINCT locked_pilot.card_id),
    count(DISTINCT locked_pilot.normalized_fields->>'pilot_profile'),
    count(DISTINCT lower(trim(locked_pilot.issuer))),
    array_agg(DISTINCT locked_pilot.normalized_fields->>'pilot_profile'
      ORDER BY locked_pilot.normalized_fields->>'pilot_profile'),
    coalesce(bool_and(length(trim(locked_pilot.issuer)) > 0), false),
    coalesce(bool_and(
    public.card_enrichment_pilot_evidence_is_qualified(
      locked_pilot,
      locked_staging
    )
  ), false)
  INTO pilot_count, promoted_count, pilot_card_count, pilot_profile_count,
    pilot_issuer_count, pilot_profiles, pilot_issuer_values_valid, all_qualified
  FROM locked_pilot
  LEFT JOIN locked_staging ON locked_staging.id =
    nullif(locked_pilot.normalized_fields->'pilot_evidence'->>'staging_id', '')::uuid;
  IF pilot_count + promoted_count <> 5 OR pilot_card_count <> 5
     OR pilot_profile_count <> 5 OR pilot_issuer_count < 3
     OR NOT pilot_issuer_values_valid
     OR pilot_profiles IS DISTINCT FROM ARRAY[
       'additional_valid','known_invalid','redirect_or_js','straightforward',
       'terms_linked'
     ]::text[] THEN
    RAISE EXCEPTION 'pilot_not_qualified';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM public.card_catalog_enrichment_jobs AS pilot_job
    JOIN public.card_catalog_enrichment_jobs AS other_job
      ON other_job.card_id = pilot_job.card_id
     AND other_job.parser_version = pilot_job.parser_version
     AND other_job.id <> pilot_job.id
    WHERE pilot_job.parser_version = selected_parser
      AND (
        pilot_job.run_mode = 'pilot'
        OR pilot_job.result_summary->'pilot_qualified' = 'true'::jsonb
      )
  ) THEN
    RAISE EXCEPTION 'pilot_card_identity_conflict';
  END IF;
  IF promoted_count = 5 THEN
    IF EXISTS (
      SELECT 1
      FROM public.card_catalog_enrichment_jobs AS promoted_job
      WHERE promoted_job.parser_version = selected_parser
        AND promoted_job.run_mode = 'scheduled'
        AND promoted_job.result_summary->'pilot_qualified' = 'true'::jsonb
        AND NOT public.card_enrichment_pilot_evidence_is_qualified(
          promoted_job,
          (SELECT staging FROM public.card_benefits_staging AS staging
             WHERE staging.id = nullif(
               promoted_job.normalized_fields->'pilot_evidence'->>'staging_id',
               ''
             )::uuid)
        )
    ) THEN
      RAISE EXCEPTION 'pilot_not_qualified';
    END IF;
    RETURN QUERY
    SELECT job.*
    FROM public.card_catalog_enrichment_jobs AS job
    WHERE job.parser_version = selected_parser
      AND job.run_mode = 'scheduled'
      AND job.result_summary->'pilot_qualified' = 'true'::jsonb
    ORDER BY job.id;
    RETURN;
  END IF;
  IF pilot_count <> 5 OR promoted_count <> 0 OR NOT all_qualified THEN
    RAISE EXCEPTION 'pilot_not_qualified';
  END IF;

  UPDATE public.card_catalog_enrichment_jobs AS job
  SET run_mode = 'scheduled',
      result_summary = coalesce(job.result_summary, '{}'::jsonb) ||
        jsonb_build_object(
          'pilot_qualified', true,
          'pilot_qualified_at', statement_timestamp()
        ),
      updated_at = statement_timestamp()
  WHERE job.parser_version = selected_parser
    AND job.run_mode = 'pilot';

  IF EXISTS (
    SELECT 1
    FROM public.card_catalog_enrichment_jobs AS promoted_job
    WHERE promoted_job.parser_version = selected_parser
      AND promoted_job.run_mode = 'scheduled'
      AND promoted_job.result_summary->'pilot_qualified' = 'true'::jsonb
      AND NOT public.card_enrichment_pilot_evidence_is_qualified(
        promoted_job,
        (SELECT staging FROM public.card_benefits_staging AS staging
         WHERE staging.id = nullif(
           promoted_job.normalized_fields->'pilot_evidence'->>'staging_id', ''
         )::uuid)
      )
  ) THEN
    RAISE EXCEPTION 'pilot_not_qualified';
  END IF;

  RETURN QUERY
  SELECT job.*
  FROM public.card_catalog_enrichment_jobs AS job
  WHERE job.parser_version = selected_parser
    AND job.run_mode = 'scheduled'
    AND job.result_summary->'pilot_qualified' = 'true'::jsonb
  ORDER BY job.id;
END;
$$;


--
-- Name: protect_reconciled_statement_fields(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.protect_reconciled_statement_fields() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- Only the SECURITY DEFINER payment RPCs below may change these fields.
  -- A source re-import cannot set this transaction-local flag through the
  -- PostgREST table API.
  IF current_setting('cardcompass.reconciliation_write', true) = 'on' THEN
    RETURN NEW;
  END IF;

  NEW.payment_status := OLD.payment_status;
  NEW.paid_amount := OLD.paid_amount;
  NEW.paid_at := OLD.paid_at;

  IF OLD.metadata ? 'payment_reconciliation_state' THEN
    NEW.metadata := jsonb_set(
      COALESCE(NEW.metadata, '{}'::jsonb),
      '{payment_reconciliation_state}',
      OLD.metadata -> 'payment_reconciliation_state',
      true
    );
  END IF;

  IF OLD.metadata ? 'unmatched_payment_credit' THEN
    NEW.metadata := jsonb_set(
      COALESCE(NEW.metadata, '{}'::jsonb),
      '{unmatched_payment_credit}',
      OLD.metadata -> 'unmatched_payment_credit',
      true
    );
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: publish_card_catalog_identity(uuid, uuid, uuid, text, jsonb, uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.publish_card_catalog_identity(_discovery_job_id uuid, _review_item_id uuid, _actor_id uuid, _action text, _reviewed_fields jsonb, _merge_card_id uuid, _reason text, _parser_version text) RETURNS TABLE(card_id uuid, job_id uuid, resulting_status text)
    LANGUAGE plpgsql
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $_$
<<publish_card_catalog_identity_block>>
DECLARE
  observed_job public.card_discovery_jobs%ROWTYPE;
  observed_review public.card_catalog_review_queue%ROWTYPE;
  job_row public.card_discovery_jobs%ROWTYPE;
  review_row public.card_catalog_review_queue%ROWTYPE;
  card_row public.card_catalog%ROWTYPE;
  fields jsonb := coalesce(_reviewed_fields, '{}'::jsonb);
  client_fields jsonb := coalesce(_reviewed_fields, '{}'::jsonb);
  edit_field_allowlist text[] := ARRAY[
    'cardName', 'card_name', 'network', 'annual_fee', 'joining_fee', 'apr'
  ]::text[];
  reviewed_field_allowlist text[] := ARRAY[
    'issuer', 'bank', 'cardName', 'card_name', 'network', 'aliases',
    'official_url', 'card_url', 'submitted_url', 'final_url',
    'submitted_url_hash', 'final_url_hash',
    'submitted_resource_identity_hash', 'final_resource_identity_hash',
    'content_hash', 'retrieved_at', 'source_status', 'source_type',
    'source_observation', 'confidence', 'validation_version',
    'card_id', 'cardId', 'annual_fee', 'joining_fee', 'apr',
    'catalog_baseline', 'suggested_action'
  ]::text[];
  issuer text;
  reviewed_name text;
  reviewed_network text;
  reviewed_tier text;
  submitted_url text;
  final_url text;
  submitted_hash text;
  final_hash text;
  content_hash text;
  retrieved_at timestamptz;
  source_status integer;
  source_type text;
  resolved_card_id uuid;
  alias_value text;
  normalized_alias_value text;
  before_fields jsonb;
  after_fields jsonb;
  enqueued_count integer := 0;
  existing_v6_job_count integer := 0;
  adopted_count integer := 0;
  has_active_holder boolean := false;
  has_existing_v6 boolean := false;
  enrichment_url text;
  enrichment_hash text;
  enrichment_content_hash text;
  edit_target_card_id uuid;
  edit_target_bank text;
  edit_target_name text;
  edit_target_network text;
  edit_existing_target boolean := false;
  edit_preexisting_card_id uuid;
  stored_proposal_binding text;
  catalog_baseline jsonb;
  legacy_catalog_url text;
  legacy_catalog_url_hash text;
  legacy_provenance_retrieved_at timestamptz;
  edit_old_identity_lock text;
  edit_new_identity_lock text;
  new_family_conflict uuid;
  latest_lifecycle_job_id uuid;
  latest_lifecycle_state text;
  enrichment_exception text;
  issuer_quarantine_review boolean := false;
  issuer_quarantine_anchor_id uuid;
  issuer_quarantine_anchor public.card_discovery_jobs%ROWTYPE;
BEGIN
  IF _discovery_job_id IS NULL OR jsonb_typeof(fields) <> 'object'
     OR _parser_version <> 'benefits-v6'
     OR _action NOT IN (
       'resolve_verified', 'observe_existing', 'approve', 'edit_approve', 'merge', 'retry',
       'reject', 'mark_discontinued', 'reactivate'
     ) THEN
    RAISE EXCEPTION 'invalid_catalog_publication';
  END IF;
  IF octet_length(fields::text) > 16384
     OR NOT public.card_catalog_json_envelope_valid(fields, 0)
     OR public.card_catalog_json_contains_sensitive_url(fields) THEN
    RAISE EXCEPTION 'invalid_reviewed_fields_envelope';
  END IF;
  IF EXISTS (
    SELECT 1 FROM jsonb_object_keys(fields) AS reviewed_field(key)
    WHERE NOT (reviewed_field.key = ANY(reviewed_field_allowlist))
  ) THEN
    RAISE EXCEPTION 'unknown_reviewed_field';
  END IF;
  IF fields ? 'source_observation' AND (
    jsonb_typeof(fields->'source_observation') IS DISTINCT FROM 'object'
    OR octet_length((fields->'source_observation')::text) > 16384
  ) THEN
    RAISE EXCEPTION 'invalid_source_observation';
  END IF;
  SELECT job.* INTO observed_job
  FROM public.card_discovery_jobs AS job WHERE job.id = _discovery_job_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'discovery_job_not_found'; END IF;
  IF _action = 'resolve_verified' THEN
    IF _review_item_id IS NOT NULL OR _actor_id IS NOT NULL
       OR observed_job.discovery_source <> 'statement'
       OR observed_job.evidence->>'verification' <> 'independently_verified_statement' THEN
      RAISE EXCEPTION 'verified_statement_source_required';
    END IF;
  ELSIF _action = 'observe_existing' THEN
    IF _review_item_id IS NOT NULL OR _actor_id IS NOT NULL
       OR observed_job.discovery_source NOT IN ('statement', 'issuer_crawl')
       OR jsonb_typeof(fields->'source_observation') IS DISTINCT FROM 'object'
       OR fields->'source_observation'->>'kind' NOT IN (
         'strong_existing_official_card',
         'bound_official_card_observation',
         'legacy_bound_official_card_observation',
         'discovered_bound_official_card_observation'
       )
       OR fields->'source_observation'->>'identity_validated' IS DISTINCT FROM 'true'
       OR fields->'source_observation'->>'source_status' IS DISTINCT FROM '200'
       OR fields->>'source_type' IS DISTINCT FROM 'official_html'
       OR nullif(fields->>'card_id', '') IS NULL THEN
      RAISE EXCEPTION 'invalid_existing_observation_authority';
    END IF;
    IF observed_job.review_item_id IS NOT NULL
       OR observed_job.status = 'review_required'
       OR EXISTS (
         SELECT 1 FROM public.card_catalog_review_queue AS pending_review
         WHERE pending_review.discovery_job_id = observed_job.id
           AND pending_review.status = 'pending'
       ) THEN
      RAISE EXCEPTION 'existing_observation_requires_review';
    END IF;
  ELSIF _review_item_id IS NULL OR _actor_id IS NULL THEN
    RAISE EXCEPTION 'actor_required';
  ELSIF NOT EXISTS (
    SELECT 1 FROM public.users AS actor
    WHERE actor.id = _actor_id AND actor.is_admin IS TRUE
  ) THEN
    RAISE EXCEPTION 'administrator_required';
  END IF;
  IF _review_item_id IS NOT NULL THEN
    SELECT review.* INTO observed_review
    FROM public.card_catalog_review_queue AS review
    WHERE review.id = _review_item_id
      AND review.discovery_job_id = observed_job.id;
    IF NOT FOUND THEN RAISE EXCEPTION 'review_item_not_found'; END IF;
    review_row := observed_review;
    -- Immutable source URLs, hashes, timestamps, observation, target and
    -- proposal identity are always server-derived from the stored review.
    IF _action = 'edit_approve' THEN
      IF EXISTS (
        SELECT 1 FROM jsonb_object_keys(client_fields) AS client_field(key)
        WHERE NOT (client_field.key = ANY(edit_field_allowlist))
      ) THEN
        RAISE EXCEPTION 'immutable_reviewed_field_override';
      END IF;
      fields := review_row.proposed_fields || client_fields;
    ELSE
      IF client_fields <> '{}'::jsonb THEN
        RAISE EXCEPTION 'immutable_reviewed_field_override';
      END IF;
      fields := review_row.proposed_fields;
    END IF;
  END IF;
  -- Recheck after substituting stored proposal fields. The RPC never trusts a
  -- legacy review envelope merely because it was already persisted.
  IF octet_length(fields::text) > 16384
     OR NOT public.card_catalog_json_envelope_valid(fields, 0)
     OR public.card_catalog_json_contains_sensitive_url(fields) THEN
    RAISE EXCEPTION 'invalid_reviewed_fields_envelope';
  END IF;
  IF EXISTS (
    SELECT 1 FROM jsonb_object_keys(fields) AS reviewed_field(key)
    WHERE NOT (reviewed_field.key = ANY(reviewed_field_allowlist))
  ) THEN
    RAISE EXCEPTION 'unknown_reviewed_field';
  END IF;
  IF _action IN ('retry', 'reject', 'mark_discontinued', 'reactivate')
     AND length(trim(coalesce(_reason, ''))) < 2 THEN
    RAISE EXCEPTION 'reason_required';
  END IF;
  IF _action IN ('mark_discontinued', 'reactivate')
     AND jsonb_typeof(fields->'source_observation') <> 'object' THEN
    RAISE EXCEPTION 'source_observation_required';
  END IF;
  IF _action IN ('mark_discontinued', 'reactivate') AND (
    review_row.proposed_fields->>'suggested_action' IS DISTINCT FROM _action
    OR jsonb_typeof(review_row.source_evidence->'source_observation') <> 'object'
    OR fields->'source_observation' IS DISTINCT FROM
      review_row.source_evidence->'source_observation'
  ) THEN
    RAISE EXCEPTION 'lifecycle_action_mismatch';
  END IF;
  IF _action = 'mark_discontinued' AND NOT (
    (
      fields->'source_observation'->>'kind' = 'strong_gone_observation'
      AND fields->'source_observation'->>'source_status' = '410'
    )
    OR (
      fields->'source_observation'->>'kind' = 'strong_explicit_discontinuation'
      AND fields->'source_observation'->>'source_status' = '200'
      AND fields->'source_observation'->>'identity_validated' = 'true'
      AND fields->'source_observation'->>'explicit_discontinuation' = 'true'
    )
  ) THEN
    RAISE EXCEPTION 'lifecycle_action_mismatch';
  ELSIF _action = 'reactivate' AND NOT (
    fields->'source_observation'->>'kind' = 'exact_card_reappearance'
    AND fields->'source_observation'->>'source_status' = '200'
    AND fields->'source_observation'->>'identity_validated' = 'true'
    AND coalesce(
      (fields->'source_observation'->>'explicit_discontinuation')::boolean,
      false
    ) = false
  ) THEN
    RAISE EXCEPTION 'reactivation_evidence_conflict';
  END IF;
  IF _action IN ('mark_discontinued', 'reactivate')
     AND jsonb_typeof(fields->'catalog_baseline') IS DISTINCT FROM 'object' THEN
    RAISE EXCEPTION 'catalog_baseline_required';
  END IF;
  IF _action IN ('mark_discontinued', 'reactivate')
     AND fields->'catalog_baseline' IS DISTINCT FROM
       review_row.proposed_fields->'catalog_baseline' THEN
    RAISE EXCEPTION 'stale_catalog_baseline';
  END IF;
  issuer_quarantine_review :=
    review_row.proposed_fields->'source_observation'->>'classification' =
      'issuer_discovery_quarantine';
  IF issuer_quarantine_review AND _action NOT IN ('retry', 'reject') THEN
    RAISE EXCEPTION 'issuer_discovery_quarantine_action_required';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(
    'card_catalog_publication:job:' || _discovery_job_id::text, 0
  ));

  IF _action = 'observe_existing' THEN
    -- observe_existing_locked_revalidation: status and review authority are
    -- checked under the same job advisory/row lock used for publication, and
    -- immediately before the resolver can bind URL keys or mutate a card.
    SELECT job.* INTO job_row
    FROM public.card_discovery_jobs AS job
    WHERE job.id = _discovery_job_id
    FOR UPDATE;
    IF NOT FOUND
       OR job_row.discovery_source NOT IN ('statement', 'issuer_crawl')
       OR job_row.review_item_id IS NOT NULL
       OR job_row.status = 'review_required'
       OR job_row.issuer IS DISTINCT FROM observed_job.issuer
       OR job_row.proposed_product IS DISTINCT FROM observed_job.proposed_product
       OR job_row.evidence IS DISTINCT FROM observed_job.evidence
       OR EXISTS (
         SELECT 1 FROM public.card_catalog_review_queue AS pending_review
         WHERE pending_review.discovery_job_id = job_row.id
           AND pending_review.status = 'pending'
         FOR UPDATE
       ) THEN
      RAISE EXCEPTION 'existing_observation_requires_review';
    END IF;
    observed_job := job_row;
  END IF;

  IF _review_item_id IS NOT NULL
     AND _action NOT IN ('retry', 'reject')
     AND observed_job.status = 'resolved'
     AND review_row.status IN ('approved', 'merged')
     AND review_row.reviewed_by = _actor_id
     AND review_row.proposed_fields = fields
     AND EXISTS (
       SELECT 1 FROM public.card_catalog_review_audit AS replay_audit
       WHERE replay_audit.review_item_id = review_row.id
         AND replay_audit.actor_id = _actor_id
         AND replay_audit.action = _action
         AND replay_audit.details->>'reason' IS NOT DISTINCT FROM _reason
         AND replay_audit.details->>'merge_card_id' IS NOT DISTINCT FROM
           CASE WHEN _merge_card_id IS NULL THEN NULL ELSE _merge_card_id::text END
     )
     AND (
       (_action = 'merge' AND review_row.status = 'merged')
       OR (_action <> 'merge' AND review_row.status = 'approved')
     ) THEN
    -- idempotent_publication_replay: the first transaction already persisted
    -- every artifact and the v6 source boundary. Never append a second audit.
    card_id := observed_job.resolved_card_id;
    job_id := observed_job.id;
    resulting_status := CASE WHEN _action = 'merge' THEN 'merged' ELSE
      CASE WHEN _action IN ('mark_discontinued', 'reactivate') THEN _action ELSE 'approved' END
    END;
    RETURN NEXT;
    RETURN;
  END IF;

  IF _action IN ('retry', 'reject') THEN
    SELECT job.* INTO job_row FROM public.card_discovery_jobs AS job
    WHERE job.id = _discovery_job_id FOR UPDATE;
    SELECT review.* INTO review_row FROM public.card_catalog_review_queue AS review
    WHERE review.id = _review_item_id
      AND review.discovery_job_id = job_row.id FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'stale_catalog_review';
    END IF;
    IF issuer_quarantine_review THEN
      IF review_row.proposed_fields->'source_observation' IS DISTINCT FROM
           review_row.source_evidence->'source_observation'
         OR review_row.proposed_fields->'source_observation'->>'kind' IS DISTINCT FROM
           'issuer_discovery_quarantine'
         OR EXISTS (
           SELECT 1
           FROM jsonb_object_keys(
             review_row.proposed_fields->'source_observation'
           ) AS quarantine_field(key)
           WHERE quarantine_field.key NOT IN (
             'anchor_job_id', 'classification', 'episode_identity', 'issuer',
             'kind', 'reason', 'retryable', 'retryability_reason'
           )
         )
         OR jsonb_typeof(
           review_row.proposed_fields->'source_observation'->'retryable'
         ) IS DISTINCT FROM 'boolean'
         OR coalesce(
           review_row.proposed_fields->'source_observation'->>'retryability_reason', ''
         ) NOT IN ('attempt_budget_reset_allowed', 'manual_repair_required')
         OR (
           review_row.proposed_fields->'source_observation'->>'retryable' = 'true'
           AND (
             coalesce(
               review_row.proposed_fields->'source_observation'->>'reason', ''
             ) NOT IN ('resume_attempts_exhausted', 'transient_producer_state')
             OR review_row.proposed_fields->'source_observation'->>'retryability_reason'
               <> 'attempt_budget_reset_allowed'
           )
         )
         OR (
           review_row.proposed_fields->'source_observation'->>'retryable' = 'false'
           AND review_row.proposed_fields->'source_observation'->>'retryability_reason'
             <> 'manual_repair_required'
         ) THEN
        RAISE EXCEPTION 'invalid_issuer_discovery_quarantine';
      END IF;
      IF length(trim(coalesce(_reason, ''))) < 2 THEN
        RAISE EXCEPTION 'invalid_issuer_discovery_quarantine_reason';
      END IF;
      IF _action = 'retry' AND (
        review_row.proposed_fields->'source_observation'->>'retryable'
          IS DISTINCT FROM 'true'
        OR review_row.proposed_fields->'source_observation'->>'retryability_reason'
          IS DISTINCT FROM 'attempt_budget_reset_allowed'
      ) THEN
        RAISE EXCEPTION 'issuer_discovery_quarantine_manual_repair_required';
      END IF;
      issuer_quarantine_anchor_id := nullif(
        review_row.proposed_fields->'source_observation'->>'anchor_job_id', ''
      )::uuid;
      SELECT anchor.* INTO issuer_quarantine_anchor
      FROM public.card_discovery_jobs AS anchor
      WHERE anchor.id = issuer_quarantine_anchor_id
      FOR UPDATE;
      IF NOT FOUND
         OR issuer_quarantine_anchor.id = job_row.id
         OR issuer_quarantine_anchor.user_id IS NOT NULL
         OR issuer_quarantine_anchor.discovery_source <> 'issuer_crawl'
         OR issuer_quarantine_anchor.evidence->>'kind' NOT IN (
           'issuer_directory_anchor', 'issuer_directory_run'
         )
         OR (_action = 'retry' AND (
           lower(regexp_replace(
             trim(issuer_quarantine_anchor.evidence->>'issuer'),
             '\s+', ' ', 'g'
           )) IS DISTINCT FROM lower(regexp_replace(
             trim(issuer_quarantine_anchor.issuer), '\s+', ' ', 'g'
           ))
           OR public.canonical_card_resource_url(
             issuer_quarantine_anchor.evidence->>'canonical_url'
           ) IS DISTINCT FROM trim(
             issuer_quarantine_anchor.evidence->>'canonical_url'
           )
           OR NOT public.card_catalog_source_matches_issuer(
             issuer_quarantine_anchor.issuer,
             issuer_quarantine_anchor.evidence->>'canonical_url'
           )
           OR coalesce(
             issuer_quarantine_anchor.evidence->>'run_date', ''
           ) !~ '^\d{4}-\d{2}-\d{2}$'
           OR to_char(to_date(
             issuer_quarantine_anchor.evidence->>'run_date', 'YYYY-MM-DD'
           ), 'YYYY-MM-DD') IS DISTINCT FROM
             issuer_quarantine_anchor.evidence->>'run_date'
           OR issuer_quarantine_anchor.attempt_count NOT BETWEEN 0 AND 5
           OR (
             issuer_quarantine_anchor.evidence->>'kind' =
               'issuer_directory_anchor'
             AND issuer_quarantine_anchor.dedupe_key IS DISTINCT FROM encode(
               extensions.digest(convert_to(
                 'issuer-directory-anchor:' || lower(regexp_replace(
                   trim(issuer_quarantine_anchor.issuer), '\s+', ' ', 'g'
                 )), 'UTF8'
               ), 'sha256'), 'hex'
             )
           )
         ))
         OR issuer_quarantine_anchor.evidence->'quarantine_fence'->>'version'
           IS DISTINCT FROM '1'
         OR issuer_quarantine_anchor.evidence->'quarantine_fence'->>'classification'
           IS DISTINCT FROM 'issuer_discovery_quarantine'
         OR issuer_quarantine_anchor.evidence->'quarantine_fence'->>'anchor_job_id'
           IS DISTINCT FROM issuer_quarantine_anchor.id::text
         OR coalesce(
           issuer_quarantine_anchor.evidence->'quarantine_fence'->>'reason', ''
         ) NOT IN (
           'resume_attempts_exhausted', 'transient_producer_state',
           'invalid_run_evidence', 'legacy_anchor_conflict',
           'anchor_identity_conflict'
         )
         OR (
           issuer_quarantine_anchor.evidence->'quarantine_fence'->>'reason'
             IN ('resume_attempts_exhausted', 'transient_producer_state')
           AND (
             issuer_quarantine_anchor.evidence->'quarantine_fence'->>'retryable'
               IS DISTINCT FROM 'true'
             OR issuer_quarantine_anchor.evidence->'quarantine_fence'->>'retryability_reason'
               IS DISTINCT FROM 'attempt_budget_reset_allowed'
           )
         )
         OR (
           issuer_quarantine_anchor.evidence->'quarantine_fence'->>'reason'
             IN (
               'invalid_run_evidence', 'legacy_anchor_conflict',
               'anchor_identity_conflict'
             )
           AND (
             issuer_quarantine_anchor.evidence->'quarantine_fence'->>'retryable'
               IS DISTINCT FROM 'false'
             OR issuer_quarantine_anchor.evidence->'quarantine_fence'->>'retryability_reason'
               IS DISTINCT FROM 'manual_repair_required'
           )
         )
         OR lower(regexp_replace(
           trim(issuer_quarantine_anchor.evidence->'quarantine_fence'->>'issuer'),
           '\s+', ' ', 'g'
         )) IS DISTINCT FROM lower(regexp_replace(
           trim(issuer_quarantine_anchor.issuer), '\s+', ' ', 'g'
         ))
         OR review_row.proposed_fields->'source_observation'->>'classification'
           IS DISTINCT FROM
             issuer_quarantine_anchor.evidence->'quarantine_fence'->>'classification'
         OR review_row.proposed_fields->'source_observation'->>'reason'
           IS DISTINCT FROM
             issuer_quarantine_anchor.evidence->'quarantine_fence'->>'reason'
         OR review_row.proposed_fields->'source_observation'->>'retryable'
           IS DISTINCT FROM
             issuer_quarantine_anchor.evidence->'quarantine_fence'->>'retryable'
         OR review_row.proposed_fields->'source_observation'->>'retryability_reason'
           IS DISTINCT FROM
             issuer_quarantine_anchor.evidence->'quarantine_fence'->>'retryability_reason'
         OR NOT coalesce((
           (
             coalesce(
               (issuer_quarantine_anchor.evidence->'quarantine_fence'->>'episode'), ''
             ) ~ '^[1-9][0-9]{0,5}$'
             AND review_row.proposed_fields->'source_observation'->>'episode_identity'
               = issuer_quarantine_anchor.evidence->'quarantine_fence'->>'semantic_identity'
             AND review_row.proposed_fields->'source_observation'->>'episode_identity'
               = 'issuer-discovery-quarantine-v1:' ||
                 issuer_quarantine_anchor.id::text || ':' ||
                 (issuer_quarantine_anchor.evidence->'quarantine_fence'->>'episode')
           )
           OR (
             (issuer_quarantine_anchor.evidence->'quarantine_fence'->>'episode')
               IS NULL
             AND issuer_quarantine_anchor.evidence->'quarantine_fence'->>'semantic_identity'
               = 'issuer-discovery-quarantine-v1:' ||
                 issuer_quarantine_anchor.id::text
             AND review_row.proposed_fields->'source_observation'->>'episode_identity'
               IS NULL
           )
         ), false)
         OR lower(regexp_replace(
           trim(issuer_quarantine_anchor.issuer), '\s+', ' ', 'g'
         )) IS DISTINCT FROM lower(regexp_replace(
           trim(review_row.proposed_fields->'source_observation'->>'issuer'),
           '\s+', ' ', 'g'
         ))
         OR lower(regexp_replace(
           trim(job_row.issuer), '\s+', ' ', 'g'
         )) IS DISTINCT FROM lower(regexp_replace(
           trim(issuer_quarantine_anchor.issuer), '\s+', ' ', 'g'
         )) THEN
        RAISE EXCEPTION 'invalid_issuer_discovery_quarantine';
      END IF;
      IF EXISTS (
        SELECT 1 FROM public.card_catalog_review_audit AS replay_audit
        WHERE replay_audit.review_item_id = review_row.id
          AND replay_audit.actor_id = _actor_id
          AND replay_audit.action = _action
          AND replay_audit.details->>'reason' IS NOT DISTINCT FROM _reason
      ) AND (
        (_action = 'retry' AND review_row.status = 'approved'
          AND job_row.status = 'resolved')
        OR (_action = 'reject' AND review_row.status = 'rejected'
          AND job_row.status = 'rejected')
      ) THEN
        card_id := NULL;
        job_id := job_row.id;
        resulting_status := CASE
          WHEN _action = 'retry' THEN 'resolved' ELSE 'rejected'
        END;
        RETURN NEXT;
        RETURN;
      END IF;
      IF review_row.status <> 'pending'
         OR job_row.status <> 'review_required'
         OR review_row.proposed_fields IS DISTINCT FROM observed_review.proposed_fields
         OR review_row.source_evidence IS DISTINCT FROM observed_review.source_evidence
         OR review_row.updated_at IS DISTINCT FROM observed_review.updated_at
         OR job_row.evidence IS DISTINCT FROM observed_job.evidence
         OR job_row.updated_at IS DISTINCT FROM observed_job.updated_at
         OR issuer_quarantine_anchor.status <> 'failed'
         OR issuer_quarantine_anchor.failure_category IS DISTINCT FROM
           'issuer_discovery_quarantined'
         OR issuer_quarantine_anchor.next_retry_at IS NOT NULL THEN
        RAISE EXCEPTION 'stale_catalog_review';
      END IF;
      INSERT INTO public.card_catalog_review_audit(
        review_item_id, actor_id, action, details
      ) VALUES (
        review_row.id, _actor_id, _action,
        jsonb_build_object(
          'reason', _reason,
          'anchor_job_id', issuer_quarantine_anchor.id,
          'attempt_count_policy', CASE
            WHEN _action = 'retry' THEN 'reset_to_zero' ELSE 'retain'
          END,
          'retained_history', true
        )
      );
      IF _action = 'retry' THEN
        UPDATE public.card_discovery_jobs SET
          status = 'failed',
          attempt_count = 0,
          next_retry_at = statement_timestamp(),
          failure_category = 'issuer_discovery_operator_retry',
          updated_at = statement_timestamp()
        WHERE id = issuer_quarantine_anchor.id
          AND status = 'failed'
          AND failure_category = 'issuer_discovery_quarantined'
          AND next_retry_at IS NULL
          AND updated_at IS NOT DISTINCT FROM issuer_quarantine_anchor.updated_at;
        IF NOT FOUND THEN RAISE EXCEPTION 'stale_catalog_review'; END IF;
        UPDATE public.card_catalog_review_queue SET
          status = 'approved', reviewed_by = _actor_id,
          review_reason = _reason, reviewed_at = statement_timestamp(),
          updated_at = statement_timestamp()
        WHERE id = review_row.id AND status = 'pending'
          AND updated_at IS NOT DISTINCT FROM review_row.updated_at;
        IF NOT FOUND THEN RAISE EXCEPTION 'stale_catalog_review'; END IF;
        UPDATE public.card_discovery_jobs SET
          status = 'resolved', failure_category = NULL,
          next_retry_at = NULL, updated_at = statement_timestamp()
        WHERE id = job_row.id AND status = 'review_required'
          AND updated_at IS NOT DISTINCT FROM job_row.updated_at;
        IF NOT FOUND THEN RAISE EXCEPTION 'stale_catalog_review'; END IF;
        resulting_status := 'resolved';
      ELSE
        UPDATE public.card_catalog_review_queue SET
          status = 'rejected', reviewed_by = _actor_id,
          review_reason = _reason, reviewed_at = statement_timestamp(),
          updated_at = statement_timestamp()
        WHERE id = review_row.id AND status = 'pending'
          AND updated_at IS NOT DISTINCT FROM review_row.updated_at;
        IF NOT FOUND THEN RAISE EXCEPTION 'stale_catalog_review'; END IF;
        UPDATE public.card_discovery_jobs SET
          status = 'rejected', next_retry_at = NULL,
          updated_at = statement_timestamp()
        WHERE id = job_row.id AND status = 'review_required'
          AND updated_at IS NOT DISTINCT FROM job_row.updated_at;
        IF NOT FOUND THEN RAISE EXCEPTION 'stale_catalog_review'; END IF;
        -- The separate private producer remains failed and explicitly
        -- issuer_discovery_quarantined; reject never makes it claimable.
        resulting_status := 'rejected';
      END IF;
      card_id := NULL;
      job_id := job_row.id;
      RETURN NEXT;
      RETURN;
    END IF;
    -- idempotent_retry_reject_replay: compare the exact retained decision
    -- before treating its already-applied state as stale.
    IF EXISTS (
      SELECT 1 FROM public.card_catalog_review_audit AS replay_audit
      WHERE replay_audit.review_item_id = review_row.id
        AND replay_audit.actor_id = _actor_id
        AND replay_audit.action = _action
        AND replay_audit.details->>'reason' IS NOT DISTINCT FROM _reason
        AND replay_audit.details->>'merge_card_id' IS NOT DISTINCT FROM
          CASE WHEN _merge_card_id IS NULL THEN NULL ELSE _merge_card_id::text END
    ) AND (
      (_action = 'retry'
        AND review_row.status = 'pending' AND job_row.status = 'review_required')
      OR (_action = 'reject'
        AND review_row.status = 'rejected' AND job_row.status = 'rejected')
    ) THEN
      -- Exact current state returns without duplicate audit/timestamp mutation.
      card_id := job_row.resolved_card_id;
      job_id := job_row.id;
      resulting_status := CASE WHEN _action = 'retry' THEN 'review_required' ELSE 'rejected' END;
      RETURN NEXT;
      RETURN;
    END IF;
    IF (_action = 'reject' AND review_row.status <> 'pending')
       OR (_action = 'retry' AND review_row.status NOT IN ('pending', 'rejected'))
       OR (_action = 'retry' AND job_row.status = 'discovering')
       OR review_row.proposed_fields IS DISTINCT FROM observed_review.proposed_fields
       OR review_row.source_evidence IS DISTINCT FROM observed_review.source_evidence
       OR review_row.status IS DISTINCT FROM observed_review.status
       OR review_row.updated_at IS DISTINCT FROM observed_review.updated_at
       OR job_row.issuer IS DISTINCT FROM observed_job.issuer
       OR job_row.proposed_product IS DISTINCT FROM observed_job.proposed_product
       OR job_row.evidence IS DISTINCT FROM observed_job.evidence
       OR job_row.status IS DISTINCT FROM observed_job.status
       OR job_row.updated_at IS DISTINCT FROM observed_job.updated_at THEN
      RAISE EXCEPTION 'stale_catalog_review';
    END IF;
    IF _action = 'retry' THEN
      INSERT INTO public.card_catalog_review_audit(review_item_id, actor_id, action, details)
      VALUES (
        review_row.id, _actor_id, _action,
        jsonb_build_object(
          'reason', _reason,
          'retained_history', true,
          'prior_proposed_fields', review_row.proposed_fields,
          'prior_source_evidence', review_row.source_evidence,
          'merge_card_id', _merge_card_id
        )
      );
      UPDATE public.card_catalog_review_queue SET status = 'pending',
        reviewed_by = NULL, review_reason = NULL, reviewed_at = NULL,
        updated_at = statement_timestamp()
      WHERE id = review_row.id
        AND status IS NOT DISTINCT FROM review_row.status
        AND updated_at IS NOT DISTINCT FROM review_row.updated_at;
      IF NOT FOUND THEN RAISE EXCEPTION 'stale_catalog_review'; END IF;
      -- Retained-review reopen: no universal producer owns arbitrary reviewed
      -- identity jobs, so retry remains actionable review work.
      UPDATE public.card_discovery_jobs SET status = 'review_required',
        review_item_id = review_row.id,
        failure_category = NULL, next_retry_at = NULL,
        updated_at = statement_timestamp()
      WHERE id = job_row.id
        AND status IS NOT DISTINCT FROM job_row.status
        AND updated_at IS NOT DISTINCT FROM job_row.updated_at;
      IF NOT FOUND THEN RAISE EXCEPTION 'stale_catalog_review'; END IF;
      resulting_status := 'review_required';
    ELSE
      UPDATE public.card_catalog_review_queue SET status = 'rejected',
        reviewed_by = _actor_id, review_reason = _reason,
        reviewed_at = statement_timestamp(), updated_at = statement_timestamp()
      WHERE id = review_row.id
        AND status IS NOT DISTINCT FROM review_row.status
        AND updated_at IS NOT DISTINCT FROM review_row.updated_at;
      IF NOT FOUND THEN RAISE EXCEPTION 'stale_catalog_review'; END IF;
      UPDATE public.card_discovery_jobs SET status = 'rejected',
        next_retry_at = NULL, updated_at = statement_timestamp()
      WHERE id = job_row.id
        AND status IS NOT DISTINCT FROM job_row.status
        AND updated_at IS NOT DISTINCT FROM job_row.updated_at;
      IF NOT FOUND THEN RAISE EXCEPTION 'stale_catalog_review'; END IF;
      resulting_status := 'rejected';
    END IF;
    IF _action = 'reject' THEN
      INSERT INTO public.card_catalog_review_audit(review_item_id, actor_id, action, details)
      VALUES (review_row.id, _actor_id, _action,
        jsonb_build_object(
          'reason', _reason, 'retained_history', true,
          'merge_card_id', _merge_card_id
        ));
    END IF;
    card_id := NULL; job_id := job_row.id; RETURN NEXT; RETURN;
  END IF;

  IF _action IN ('mark_discontinued', 'reactivate') THEN
    resolved_card_id := coalesce(
      _merge_card_id,
      nullif(fields->>'card_id', '')::uuid,
      nullif(fields->>'cardId', '')::uuid,
      observed_job.resolved_card_id
    );
    IF resolved_card_id IS NULL THEN RAISE EXCEPTION 'card_target_required'; END IF;
    IF nullif(review_row.proposed_fields->>'card_id', '')::uuid
       IS DISTINCT FROM resolved_card_id THEN
      RAISE EXCEPTION 'card_target_conflict';
    END IF;
  ELSE
    issuer := trim(coalesce(fields->>'issuer', fields->>'bank', observed_job.issuer));
    reviewed_name := trim(coalesce(
      fields->>'cardName', fields->>'card_name', observed_job.proposed_product
    ));
    reviewed_network := public.card_catalog_effective_network(
      nullif(trim(coalesce(fields->>'network', '')), ''),
      reviewed_name,
      issuer
    );
    reviewed_tier := public.normalize_card_catalog_tier(reviewed_name);
    final_url := public.canonical_card_resource_url(coalesce(
      fields->>'final_url', review_row.source_evidence->>'final_url',
      observed_job.evidence->>'final_url', fields->>'official_url',
      fields->>'card_url', review_row.source_evidence->>'official_url',
      observed_job.evidence->>'official_url'
    ));
    submitted_url := public.canonical_card_resource_url(coalesce(
      fields->>'submitted_url', review_row.source_evidence->>'submitted_url',
      observed_job.evidence->>'submitted_url', final_url
    ));
    submitted_hash := lower(coalesce(
      fields->>'submitted_url_hash', fields->>'submitted_resource_identity_hash',
      review_row.source_evidence->>'submitted_url_hash',
      review_row.source_evidence->>'submitted_resource_identity_hash',
      observed_job.evidence->>'submitted_url_hash',
      observed_job.evidence->>'submitted_resource_identity_hash',
      encode(extensions.digest(convert_to(submitted_url, 'UTF8'), 'sha256'), 'hex')
    ));
    final_hash := lower(coalesce(
      fields->>'final_url_hash', fields->>'final_resource_identity_hash',
      review_row.source_evidence->>'final_url_hash',
      review_row.source_evidence->>'final_resource_identity_hash',
      observed_job.evidence->>'final_url_hash',
      observed_job.evidence->>'final_resource_identity_hash',
      encode(extensions.digest(convert_to(final_url, 'UTF8'), 'sha256'), 'hex')
    ));
    IF submitted_hash !~ '^[0-9a-f]{64}$' OR final_hash !~ '^[0-9a-f]{64}$' THEN
      RAISE EXCEPTION 'invalid_url_hash';
    END IF;
    IF submitted_hash <> encode(
      extensions.digest(convert_to(submitted_url, 'UTF8'), 'sha256'), 'hex'
    ) THEN
      RAISE EXCEPTION 'submitted_url_hash_mismatch';
    END IF;
    IF final_hash <> encode(
      extensions.digest(convert_to(final_url, 'UTF8'), 'sha256'), 'hex'
    ) THEN
      RAISE EXCEPTION 'final_url_hash_mismatch';
    END IF;
    IF NOT public.card_catalog_source_matches_issuer(issuer, submitted_url)
       OR NOT public.card_catalog_source_matches_issuer(issuer, final_url) THEN
      RAISE EXCEPTION 'unapproved_domain';
    END IF;
    IF _action = 'observe_existing' THEN
      resolved_card_id := nullif(fields->>'card_id', '')::uuid;
      IF resolved_card_id IS NULL THEN RAISE EXCEPTION 'card_target_required'; END IF;
      IF public.resolve_card_catalog_identity(
        issuer, reviewed_name, reviewed_network, final_url,
        submitted_hash, final_hash
      ) IS DISTINCT FROM resolved_card_id THEN
        RAISE EXCEPTION 'existing_observation_identity_conflict';
      END IF;
    ELSIF _action = 'merge' THEN
      IF _merge_card_id IS NULL THEN RAISE EXCEPTION 'merge_target_required'; END IF;
      SELECT catalog.bank, catalog.card_name, catalog.network
      INTO issuer, reviewed_name, reviewed_network
      FROM public.card_catalog AS catalog WHERE catalog.id = _merge_card_id;
      IF NOT FOUND THEN RAISE EXCEPTION 'merge_target_not_found'; END IF;
      -- Resolver must still prove the explicit target agrees with both URL keys.
      resolved_card_id := public.resolve_card_catalog_identity(
        issuer, reviewed_name, reviewed_network, final_url, submitted_hash, final_hash
      );
      IF resolved_card_id <> _merge_card_id THEN RAISE EXCEPTION 'merge_target_conflict'; END IF;
    ELSIF _action = 'edit_approve' THEN
      edit_target_card_id := coalesce(
        nullif(fields->>'card_id', '')::uuid,
        nullif(fields->>'cardId', '')::uuid,
        observed_job.resolved_card_id
      );
      IF edit_target_card_id IS NULL THEN
        SELECT bound.card_id INTO edit_preexisting_card_id
        FROM (
          SELECT key.card_id
          FROM public.card_catalog_url_keys AS key
          WHERE key.url_hash IN (submitted_hash, final_hash)
          UNION
          SELECT provenance.card_id
          FROM public.card_catalog_provenance AS provenance
          WHERE provenance.submitted_url_hash IN (submitted_hash, final_hash)
             OR provenance.final_url_hash IN (submitted_hash, final_hash)
        ) AS bound
        ORDER BY bound.card_id
        LIMIT 1;
        IF edit_preexisting_card_id IS NULL THEN
          SELECT candidate.id INTO edit_preexisting_card_id
          FROM public.card_catalog AS candidate
          WHERE lower(trim(candidate.bank)) = lower(trim(issuer))
            AND lower(trim(coalesce(candidate.card_type, ''))) = 'credit'
            AND coalesce(
              nullif(public.normalize_card_catalog_family(candidate.card_name), ''),
              public.normalize_card_catalog_product(candidate.card_name)
            ) = coalesce(
              nullif(public.normalize_card_catalog_family(reviewed_name), ''),
              public.normalize_card_catalog_product(reviewed_name)
            )
            AND public.card_catalog_effective_network(
              candidate.network, candidate.card_name, candidate.bank
            ) IS NOT DISTINCT FROM reviewed_network
            AND public.normalize_card_catalog_tier(candidate.card_name)
              IS NOT DISTINCT FROM reviewed_tier
          ORDER BY candidate.id
          LIMIT 1;
        END IF;
      END IF;
      edit_existing_target := edit_target_card_id IS NOT NULL
        OR edit_preexisting_card_id IS NOT NULL;
      IF edit_existing_target AND
         jsonb_typeof(fields->'catalog_baseline') IS DISTINCT FROM 'object' THEN
        RAISE EXCEPTION 'catalog_baseline_required';
      END IF;
      IF fields ? 'catalog_baseline' AND
         fields->'catalog_baseline' IS DISTINCT FROM
           review_row.proposed_fields->'catalog_baseline' THEN
        RAISE EXCEPTION 'stale_catalog_baseline';
      END IF;
      IF NOT edit_existing_target THEN
        stored_proposal_binding := coalesce(
          review_row.source_evidence->>'semantic_product_hash',
          review_row.source_evidence->>'content_hash'
        );
        IF nullif(stored_proposal_binding, '') IS NULL
           OR nullif(review_row.proposed_fields->>'issuer', '') IS NULL
           OR nullif(review_row.proposed_fields->>'cardName', '') IS NULL THEN
          RAISE EXCEPTION 'stored_proposal_binding_required';
        END IF;
      END IF;
      IF edit_target_card_id IS NOT NULL THEN
        SELECT catalog.bank, catalog.card_name, catalog.network
        INTO edit_target_bank, edit_target_name, edit_target_network
        FROM public.card_catalog AS catalog WHERE catalog.id = edit_target_card_id;
        IF NOT FOUND OR lower(trim(coalesce(edit_target_bank, ''))) <> lower(trim(issuer)) THEN
          RAISE EXCEPTION 'edit_target_conflict';
        END IF;
        -- A rename can move the row between resolver families. Take both old
        -- and new family locks in sorted order after the sorted URL locks, then
        -- reject a destination already owned by another credit card.
        PERFORM pg_advisory_xact_lock(hashtextextended(
          'card_catalog_publication:url:' || least(submitted_hash, final_hash), 0
        ));
        PERFORM pg_advisory_xact_lock(hashtextextended(
          'card_catalog_publication:url:' || greatest(submitted_hash, final_hash), 0
        ));
        edit_old_identity_lock := 'card_catalog_identity:' ||
          lower(trim(edit_target_bank)) || ':' || coalesce(
            nullif(public.normalize_card_catalog_family(edit_target_name), ''),
            public.normalize_card_catalog_product(edit_target_name)
          );
        edit_new_identity_lock := 'card_catalog_identity:' ||
          lower(trim(issuer)) || ':' || coalesce(
            nullif(public.normalize_card_catalog_family(reviewed_name), ''),
            public.normalize_card_catalog_product(reviewed_name)
          );
        PERFORM pg_advisory_xact_lock(hashtextextended(
          least(edit_old_identity_lock, edit_new_identity_lock), 0
        ));
        PERFORM pg_advisory_xact_lock(hashtextextended(
          greatest(edit_old_identity_lock, edit_new_identity_lock), 0
        ));
        SELECT conflict.id INTO new_family_conflict
        FROM public.card_catalog AS conflict
        WHERE conflict.id <> edit_target_card_id
          AND lower(trim(conflict.bank)) = lower(trim(issuer))
          AND lower(trim(coalesce(conflict.card_type, ''))) = 'credit'
          AND coalesce(
            nullif(public.normalize_card_catalog_family(conflict.card_name), ''),
            public.normalize_card_catalog_product(conflict.card_name)
          ) = coalesce(
            nullif(public.normalize_card_catalog_family(reviewed_name), ''),
            public.normalize_card_catalog_product(reviewed_name)
          )
          AND public.card_catalog_effective_network(
            conflict.network, conflict.card_name, conflict.bank
          ) IS NOT DISTINCT FROM reviewed_network
          AND public.normalize_card_catalog_tier(conflict.card_name)
            IS NOT DISTINCT FROM reviewed_tier
        ORDER BY conflict.id
        LIMIT 1
        FOR UPDATE;
        IF new_family_conflict IS NOT NULL THEN
          RAISE EXCEPTION 'edit_target_conflict';
        END IF;
        -- Validate stored column/name network agreement even if the review did
        -- not explicitly change the network field.
        PERFORM public.card_catalog_effective_network(
          edit_target_network, edit_target_name, edit_target_bank
        );
        -- Bind a reviewed rename/network/page move to the existing strong card
        -- before changing its mutable identity. Conflicting URL keys still fail.
        resolved_card_id := public.resolve_card_catalog_identity(
          edit_target_bank, edit_target_name, edit_target_network,
          final_url, submitted_hash, final_hash
        );
        IF resolved_card_id <> edit_target_card_id THEN
          RAISE EXCEPTION 'edit_target_conflict';
        END IF;
      ELSE
        resolved_card_id := public.resolve_card_catalog_identity(
          issuer, reviewed_name, reviewed_network, final_url, submitted_hash, final_hash
        );
      END IF;
    ELSE
      resolved_card_id := public.resolve_card_catalog_identity(
        issuer, reviewed_name, reviewed_network, final_url, submitted_hash, final_hash
      );
    END IF;
  END IF;

  -- Shared order with Task 6: benefit identity advisory lock, card row, then
  -- discovery job/review rows. Enqueue re-enters the same advisory lock.
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'card_benefit_enrichment_identity:' || resolved_card_id::text || ':benefits-v6', 0
  ));
  SELECT catalog.* INTO card_row FROM public.card_catalog AS catalog
  WHERE catalog.id = resolved_card_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'card_target_not_found'; END IF;
  IF _action IN ('mark_discontinued', 'reactivate')
     AND lower(trim(coalesce(card_row.card_type, ''))) <> 'credit' THEN
    RAISE EXCEPTION 'lifecycle_credit_card_required';
  END IF;
  SELECT job.* INTO job_row FROM public.card_discovery_jobs AS job
  WHERE job.id = _discovery_job_id FOR UPDATE;
  IF _review_item_id IS NOT NULL THEN
    SELECT review.* INTO review_row FROM public.card_catalog_review_queue AS review
    WHERE review.id = _review_item_id
      AND review.discovery_job_id = job_row.id FOR UPDATE;
    IF NOT FOUND OR review_row.status <> 'pending'
       OR job_row.review_item_id IS DISTINCT FROM review_row.id
       OR review_row.proposed_fields IS DISTINCT FROM observed_review.proposed_fields
       OR review_row.source_evidence IS DISTINCT FROM observed_review.source_evidence THEN
      RAISE EXCEPTION 'stale_catalog_review';
    END IF;
  END IF;
  IF job_row.discovery_source IS DISTINCT FROM observed_job.discovery_source
     OR job_row.issuer IS DISTINCT FROM observed_job.issuer
     OR job_row.proposed_product IS DISTINCT FROM observed_job.proposed_product
     OR job_row.evidence IS DISTINCT FROM observed_job.evidence
     OR (
       job_row.status IN ('resolved', 'rejected')
       AND NOT (
         _action = 'observe_existing'
         AND job_row.status = 'resolved'
         AND job_row.resolved_card_id = resolved_card_id
         AND job_row.review_item_id IS NULL
       )
     ) THEN
    RAISE EXCEPTION 'stale_catalog_publication';
  END IF;

  IF _action IN ('mark_discontinued', 'reactivate') THEN
    SELECT latest_job.id, latest_job.evidence->>'lifecycle_state'
    INTO latest_lifecycle_job_id, latest_lifecycle_state
    FROM public.card_discovery_jobs AS latest_job
    WHERE latest_job.user_id IS NULL
      AND latest_job.discovery_source = 'issuer_crawl'
      AND latest_job.evidence->>'card_id' = card_row.id::text
      AND latest_job.evidence ? 'lifecycle_state'
    ORDER BY nullif(latest_job.evidence->>'lifecycle_observed_at', '')::timestamptz DESC,
      latest_job.created_at DESC, latest_job.id DESC
    LIMIT 1
    FOR UPDATE;
    IF latest_lifecycle_job_id IS DISTINCT FROM job_row.id
       OR latest_lifecycle_state IS DISTINCT FROM (CASE
         WHEN _action = 'mark_discontinued' THEN 'discontinued' ELSE 'active' END) THEN
      RAISE EXCEPTION 'stale_catalog_lifecycle_review';
    END IF;
  END IF;

  catalog_baseline := fields->'catalog_baseline';
  IF (
       _action IN ('mark_discontinued', 'reactivate')
       OR (_action = 'edit_approve' AND edit_existing_target)
     )
     AND NOT public.card_catalog_baseline_matches(
       catalog_baseline,
       card_row.id,
       card_row.card_name,
       card_row.network,
       card_row.annual_fee,
       card_row.joining_fee,
       card_row.apr,
       card_row.card_url,
       card_row.is_discontinued,
       card_row.updated_at
     ) THEN
    RAISE EXCEPTION 'stale_catalog_baseline';
  END IF;

  before_fields := jsonb_build_object(
    'card_name', card_row.card_name, 'network', card_row.network,
    'annual_fee', card_row.annual_fee, 'joining_fee', card_row.joining_fee,
    'apr', card_row.apr, 'card_url', card_row.card_url,
    'is_discontinued', card_row.is_discontinued
  );

  IF _action IN ('mark_discontinued', 'reactivate') THEN
    UPDATE public.card_catalog AS catalog
    SET is_discontinued = (_action = 'mark_discontinued'),
        updated_at = statement_timestamp()
    WHERE catalog.id = resolved_card_id;
  ELSIF _action = 'edit_approve' THEN
    IF card_row.card_url IS NOT NULL THEN
      legacy_catalog_url := public.canonical_card_resource_url(card_row.card_url);
      IF NOT public.card_catalog_source_matches_issuer(card_row.bank, legacy_catalog_url) THEN
        RAISE EXCEPTION 'legacy_card_url_invalid';
      END IF;
      legacy_catalog_url_hash := encode(extensions.digest(
        convert_to(legacy_catalog_url, 'UTF8'), 'sha256'
      ), 'hex');
      INSERT INTO public.card_catalog_url_keys(url_hash, card_id, canonical_url)
      VALUES (legacy_catalog_url_hash, resolved_card_id, legacy_catalog_url)
      ON CONFLICT (url_hash) DO NOTHING;
      IF EXISTS (
        SELECT 1 FROM public.card_catalog_url_keys AS legacy_key
        WHERE legacy_key.url_hash = legacy_catalog_url_hash
          AND legacy_key.card_id <> resolved_card_id
      ) THEN
        RAISE EXCEPTION 'conflicting_url_identity';
      END IF;
      BEGIN
        legacy_provenance_retrieved_at := coalesce(
          card_row.updated_at,
          nullif(fields->>'retrieved_at', '')::timestamptz,
          nullif(review_row.source_evidence->>'retrieved_at', '')::timestamptz,
          nullif(observed_job.evidence->>'retrieved_at', '')::timestamptz,
          statement_timestamp()
        );
      EXCEPTION WHEN invalid_text_representation OR datetime_field_overflow THEN
        legacy_provenance_retrieved_at := statement_timestamp();
      END;
      INSERT INTO public.card_catalog_provenance(
        card_id, source_url, canonical_submitted_url, canonical_final_url,
        submitted_url_hash, final_url_hash, source_type, content_hash,
        extracted_fields, source_evidence, validation_version, confidence,
        approval_method, retrieved_at
      )
      SELECT
        resolved_card_id, legacy_catalog_url, legacy_catalog_url,
        legacy_catalog_url, legacy_catalog_url_hash, legacy_catalog_url_hash,
        'official_html', legacy_catalog_url_hash, before_fields,
        jsonb_build_object('kind', 'legacy_catalog_url_backfill'),
        'card-identity-v3', 1, 'admin', legacy_provenance_retrieved_at
      WHERE NOT EXISTS (
        SELECT 1 FROM public.card_catalog_provenance AS legacy_provenance
        WHERE legacy_provenance.card_id = resolved_card_id
          AND legacy_provenance.final_url_hash = legacy_catalog_url_hash
          AND legacy_provenance.source_evidence->>'kind' = 'legacy_catalog_url_backfill'
      );
    END IF;
    IF card_row.card_name IS DISTINCT FROM nullif(reviewed_name, '') THEN
      INSERT INTO public.card_catalog_aliases(card_id, alias, normalized_alias, evidence_type, source_url)
      VALUES (
        resolved_card_id, card_row.card_name,
        public.normalize_card_catalog_product(card_row.card_name), 'admin', card_row.card_url
      ) ON CONFLICT ON CONSTRAINT card_catalog_aliases_card_id_normalized_alias_key DO NOTHING;
    END IF;
    UPDATE public.card_catalog AS catalog SET
      card_name = coalesce(nullif(reviewed_name, ''), catalog.card_name),
      network = coalesce(reviewed_network, catalog.network),
      annual_fee = CASE WHEN jsonb_typeof(fields->'annual_fee') = 'number'
        THEN (fields->>'annual_fee')::numeric ELSE catalog.annual_fee END,
      joining_fee = CASE WHEN jsonb_typeof(fields->'joining_fee') = 'number'
        THEN (fields->>'joining_fee')::numeric ELSE catalog.joining_fee END,
      apr = CASE WHEN jsonb_typeof(fields->'apr') = 'number'
        THEN (fields->>'apr')::numeric ELSE catalog.apr END,
      card_url = coalesce(final_url, catalog.card_url),
      updated_at = statement_timestamp()
    WHERE catalog.id = resolved_card_id;
  END IF;

  IF _action NOT IN ('mark_discontinued', 'reactivate') THEN
    IF _action <> 'observe_existing' THEN
      FOR alias_value IN
        SELECT DISTINCT value FROM jsonb_array_elements_text(
          CASE WHEN jsonb_typeof(fields->'aliases') = 'array'
            THEN fields->'aliases' ELSE '[]'::jsonb END
        ) AS aliases(value)
      LOOP
        normalized_alias_value := public.normalize_card_catalog_product(alias_value);
        IF length(normalized_alias_value) >= 2 THEN
          INSERT INTO public.card_catalog_aliases(card_id, alias, normalized_alias, evidence_type, source_url)
          VALUES (
            resolved_card_id, trim(alias_value), normalized_alias_value,
            CASE WHEN _action = 'resolve_verified' THEN 'subject' ELSE 'admin' END,
            final_url
          ) ON CONFLICT ON CONSTRAINT card_catalog_aliases_card_id_normalized_alias_key DO NOTHING;
        END IF;
      END LOOP;
    END IF;

    INSERT INTO public.card_catalog_url_keys(url_hash, card_id, canonical_url)
    VALUES (submitted_hash, resolved_card_id, submitted_url)
    ON CONFLICT (url_hash) DO UPDATE SET canonical_url = EXCLUDED.canonical_url
    WHERE card_catalog_url_keys.card_id = EXCLUDED.card_id;
    IF final_hash <> submitted_hash THEN
      INSERT INTO public.card_catalog_url_keys(url_hash, card_id, canonical_url)
      VALUES (final_hash, resolved_card_id, final_url)
      ON CONFLICT (url_hash) DO UPDATE SET canonical_url = EXCLUDED.canonical_url
      WHERE card_catalog_url_keys.card_id = EXCLUDED.card_id;
    END IF;

    content_hash := lower(coalesce(
      fields->>'content_hash', review_row.source_evidence->>'content_hash',
      observed_job.evidence->>'content_hash',
      encode(extensions.digest(convert_to(final_url, 'UTF8'), 'sha256'), 'hex')
    ));
    IF content_hash !~ '^[0-9a-f]{64}$' THEN RAISE EXCEPTION 'invalid_content_hash'; END IF;
    BEGIN
      retrieved_at := coalesce(
        nullif(fields->>'retrieved_at', '')::timestamptz,
        nullif(review_row.source_evidence->>'retrieved_at', '')::timestamptz,
        statement_timestamp()
      );
      source_status := coalesce(
        nullif(fields->>'source_status', '')::integer,
        nullif(review_row.source_evidence->>'source_status', '')::integer
      );
    EXCEPTION WHEN invalid_text_representation OR datetime_field_overflow THEN
      RAISE EXCEPTION 'invalid_source_observation';
    END;
    IF source_status IS NOT NULL AND source_status NOT BETWEEN 100 AND 599 THEN
      RAISE EXCEPTION 'invalid_source_observation';
    END IF;
    source_type := CASE coalesce(fields->>'source_type', review_row.source_evidence->>'source_type')
      WHEN 'official_pdf' THEN 'official_pdf'
      WHEN 'secondary' THEN 'secondary'
      ELSE 'official_html' END;
    INSERT INTO public.card_catalog_provenance(
      card_id, source_url, canonical_submitted_url, canonical_final_url,
      submitted_url_hash, final_url_hash, source_type, content_hash,
      extracted_fields, source_evidence, validation_version, confidence,
      approval_method, retrieved_at
    ) SELECT
      resolved_card_id, final_url, submitted_url, final_url,
      submitted_hash, final_hash, source_type, content_hash,
      fields - ARRAY['source_observation'],
      jsonb_build_object(
        'source_observation', coalesce(fields->'source_observation', '{}'::jsonb),
        'source_status', source_status
      ),
      coalesce(nullif(fields->>'validation_version', ''), 'card-identity-v3'),
      CASE WHEN jsonb_typeof(fields->'confidence') = 'number'
        THEN least(1, greatest(0, (fields->>'confidence')::numeric)) ELSE 1 END,
      CASE WHEN _action IN ('resolve_verified', 'observe_existing')
        THEN 'automatic' ELSE 'admin' END,
      retrieved_at
    WHERE NOT EXISTS (
      SELECT 1 FROM public.card_catalog_provenance AS exact_observation
      WHERE exact_observation.card_id = resolved_card_id
        AND exact_observation.submitted_url_hash = submitted_hash
        AND exact_observation.final_url_hash = final_hash
        AND exact_observation.content_hash = publish_card_catalog_identity_block.content_hash
        AND exact_observation.retrieved_at = publish_card_catalog_identity_block.retrieved_at
    );
  END IF;

  SELECT to_jsonb(catalog) - ARRAY['created_at', 'updated_at'] INTO after_fields
  FROM public.card_catalog AS catalog WHERE catalog.id = resolved_card_id;

  IF _review_item_id IS NOT NULL THEN
    UPDATE public.card_catalog_review_queue SET
      status = CASE WHEN _action = 'merge' THEN 'merged' ELSE 'approved' END,
      proposed_fields = fields,
      reviewed_by = _actor_id,
      review_reason = _reason,
      reviewed_at = statement_timestamp(),
      updated_at = statement_timestamp()
    WHERE id = review_row.id;
  END IF;
  UPDATE public.card_discovery_jobs SET status = 'resolved',
    resolved_card_id = publish_card_catalog_identity_block.resolved_card_id,
    failure_category = NULL,
    next_retry_at = NULL, updated_at = statement_timestamp()
  WHERE id = job_row.id;

  IF _review_item_id IS NOT NULL THEN
    INSERT INTO public.card_catalog_review_audit(review_item_id, actor_id, action, details)
    VALUES (
      review_row.id, _actor_id, _action,
      jsonb_build_object(
        'card_id', resolved_card_id, 'reason', _reason,
        'merge_card_id', _merge_card_id,
        'before_fields', before_fields, 'after_fields', after_fields,
        'source_observation', coalesce(fields->'source_observation', '{}'::jsonb)
      )
    );
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.user_cards AS holder
    WHERE holder.catalog_card_id = resolved_card_id AND holder.is_active = true
  ) INTO has_active_holder;
  SELECT EXISTS (
    SELECT 1 FROM public.card_catalog_enrichment_jobs AS existing
    WHERE existing.card_id = resolved_card_id
      AND lower(trim(existing.parser_version)) = 'benefits-v6'
  ) INTO has_existing_v6;
  IF has_existing_v6 AND _action <> 'edit_approve' THEN
    SELECT existing.canonical_url, existing.final_url_hash,
      coalesce(existing.content_hash, existing.final_url_hash)
    INTO enrichment_url, enrichment_hash, enrichment_content_hash
    FROM public.card_catalog_enrichment_jobs AS existing
    WHERE existing.card_id = resolved_card_id
      AND lower(trim(existing.parser_version)) = 'benefits-v6';
  ELSE
    enrichment_url := coalesce(final_url, card_row.card_url);
    IF enrichment_url IS NOT NULL THEN
      enrichment_url := public.canonical_card_resource_url(enrichment_url);
      enrichment_hash := coalesce(
        final_hash,
        encode(extensions.digest(convert_to(enrichment_url, 'UTF8'), 'sha256'), 'hex')
      );
      enrichment_content_hash := coalesce(content_hash, enrichment_hash);
    END IF;
  END IF;
  IF _action NOT IN ('mark_discontinued', 'reactivate')
     OR has_existing_v6
     OR (_action = 'reactivate' OR has_active_holder) THEN
    IF enrichment_url IS NULL THEN RAISE EXCEPTION 'enrichment_source_required'; END IF;
    SELECT source.enqueued_count, source.existing_v6_job_count, source.adopted_count
    INTO enqueued_count, existing_v6_job_count, adopted_count
    FROM public.adopt_reviewed_card_enrichment_source(
      resolved_card_id, card_row.bank, enrichment_url, enrichment_hash,
      enrichment_content_hash, 'benefits-v6'
    ) AS source;
    IF enqueued_count + existing_v6_job_count <> 1 THEN
      RAISE EXCEPTION 'unexpected_enrichment_enqueue';
    END IF;
  ELSE
    -- Sole exact-one exception: a reviewed acquisition discontinuation for an
    -- unheld card is intentionally ineligible for Task 6 recurrence.
    enrichment_exception := 'unheld_reviewed_discontinuation';
    existing_v6_job_count := 0;
    enqueued_count := 0;
    IF _action <> 'mark_discontinued' OR has_active_holder OR has_existing_v6 THEN
      RAISE EXCEPTION 'unexpected_enrichment_enqueue';
    END IF;
    IF _review_item_id IS NOT NULL THEN
      UPDATE public.card_catalog_review_audit AS audit SET
        details = audit.details || jsonb_build_object(
          'enrichment_exception', enrichment_exception,
          'existing_v6_job_count', existing_v6_job_count,
          'enqueued_count', enqueued_count
        )
      WHERE audit.review_item_id = review_row.id
        AND audit.actor_id = _actor_id AND audit.action = _action;
    END IF;
  END IF;

  card_id := resolved_card_id;
  job_id := job_row.id;
  resulting_status := CASE
    WHEN _action = 'merge' THEN 'merged'
    WHEN _action = 'observe_existing' THEN 'resolved'
    WHEN _action IN ('mark_discontinued', 'reactivate') THEN _action
    ELSE 'approved' END;
  RETURN NEXT;
END;
$_$;


--
-- Name: reconcile_imported_statement_payment(uuid, uuid, uuid, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.reconcile_imported_statement_payment(p_source_statement_id uuid, p_user_id uuid, p_user_card_id uuid, p_expected_payment_credit numeric) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_source public.statements%ROWTYPE;
  v_target public.statements%ROWTYPE;
  v_credit numeric(12,2);
  v_remaining numeric(12,2);
  v_payment numeric(12,2);
  v_updates jsonb := '[]'::jsonb;
BEGIN
  IF auth.uid() IS NULL OR auth.uid() <> p_user_id THEN
    RAISE EXCEPTION 'statement payment reconciliation requires the owning user';
  END IF;
  PERFORM set_config('cardcompass.reconciliation_write', 'on', true);

  SELECT * INTO v_source FROM public.statements
  WHERE id = p_source_statement_id AND user_id = p_user_id AND user_card_id = p_user_card_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'source statement is not owned by the supplied user and card';
  END IF;
  IF v_source.metadata ->> 'payment_reconciliation_state' = 'applied' THEN
    RETURN jsonb_build_object('already_applied', true, 'updates', '[]'::jsonb,
      'unmatched_payment_credit', COALESCE((v_source.metadata ->> 'unmatched_payment_credit')::numeric, 0));
  END IF;

  v_credit := COALESCE((v_source.metadata ->> 'payments_received')::numeric, 0);
  IF v_credit <= 0 OR v_credit <> p_expected_payment_credit THEN
    RAISE EXCEPTION 'payment credit does not match the imported source statement';
  END IF;
  v_remaining := v_credit;

  UPDATE public.statements SET metadata = jsonb_set(v_source.metadata,
    '{payment_reconciliation_state}', '"applied"'::jsonb, true)
  WHERE id = p_source_statement_id;

  FOR v_target IN
    SELECT * FROM public.statements
    WHERE user_id = p_user_id AND user_card_id = p_user_card_id
      AND id <> p_source_statement_id
      AND statements.statement_date < v_source.statement_date
      AND payment_status IN ('pending', 'partial', 'overdue')
      AND total_amount > paid_amount
    ORDER BY statement_date ASC, due_date ASC, id ASC
    FOR UPDATE
  LOOP
    EXIT WHEN v_remaining <= 0;
    v_payment := LEAST(v_target.total_amount - v_target.paid_amount, v_remaining);
    v_remaining := v_remaining - v_payment;
    UPDATE public.statements
    SET paid_amount = paid_amount + v_payment,
        payment_status = CASE WHEN paid_amount + v_payment >= total_amount THEN 'paid' ELSE 'partial' END,
        -- paid_at means first payment observed; partial allocations must set it.
        paid_at = COALESCE(paid_at, NOW())
    WHERE id = v_target.id AND user_id = p_user_id AND user_card_id = p_user_card_id;
    v_updates := v_updates || jsonb_build_array(jsonb_build_object(
      'statement_id', v_target.id, 'payment_amount', v_payment,
      'payment_status', CASE WHEN v_target.paid_amount + v_payment >= v_target.total_amount THEN 'paid' ELSE 'partial' END));
  END LOOP;

  UPDATE public.statements
  SET metadata = jsonb_set(metadata, '{unmatched_payment_credit}', to_jsonb(v_remaining), true)
  WHERE id = p_source_statement_id AND user_id = p_user_id AND user_card_id = p_user_card_id;
  RETURN jsonb_build_object('already_applied', false, 'updates', v_updates,
    'unmatched_payment_credit', v_remaining);
END;
$$;


--
-- Name: reject_catalog_entry_request(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.reject_catalog_entry_request(_staging_id uuid, _reviewed_by uuid) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  updated_count integer;
BEGIN
  IF _staging_id IS NULL THEN
    RETURN false;
  END IF;

  UPDATE public.card_benefits_staging
  SET status = 'rejected',
      reviewed_at = now(),
      reviewed_by = _reviewed_by,
      rejected_at = COALESCE(rejected_at, now()),
      updated_at = now()
  WHERE id = _staging_id
    AND status = 'pending'
    AND card_id IS NULL
    AND extracted_data->>'request_type' = 'catalog_entry';

  GET DIAGNOSTICS updated_count = ROW_COUNT;
  RETURN updated_count = 1;
END;
$$;


--
-- Name: remove_user_card(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.remove_user_card(_user_id uuid, _catalog_card_id uuid) RETURNS boolean
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
DECLARE
    cards_updated INTEGER;
BEGIN
    UPDATE user_cards
    SET is_active = false, updated_at = NOW()
    WHERE user_id = _user_id AND catalog_card_id = _catalog_card_id AND is_active = true;

    GET DIAGNOSTICS cards_updated = ROW_COUNT;

    RETURN cards_updated > 0;
END;
$$;


--
-- Name: requeue_due_card_catalog_enrichment_jobs(text, integer, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.requeue_due_card_catalog_enrichment_jobs(_parser_version text, _limit integer, _now timestamp with time zone) RETURNS SETOF public.card_catalog_enrichment_jobs
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  selected_parser text := lower(trim(coalesce(_parser_version, '')));
BEGIN
  IF selected_parser <> 'benefits-v6' OR _now IS NULL
     OR _now > statement_timestamp() + interval '5 minutes'
     OR _limit IS NULL OR _limit < 1 OR _limit > 200 THEN
    RAISE EXCEPTION 'invalid_enrichment_requeue';
  END IF;
  RETURN QUERY
  WITH selected AS (
    SELECT job.id, decision.action
    FROM public.card_catalog_enrichment_jobs AS job
    JOIN public.card_catalog AS card ON card.id = job.card_id
    CROSS JOIN LATERAL (
      SELECT public.card_enrichment_requeue_action(
        job.run_mode,
        job.status,
        job.next_run_at,
        _now,
        (
          (
            coalesce(card.is_discontinued, false) = false
            OR EXISTS (
              SELECT 1 FROM public.user_cards AS user_card
              WHERE user_card.catalog_card_id = job.card_id
                AND user_card.is_active = true
            )
          )
          AND NOT public.card_has_unresolved_catalog_identity(
            job.card_id, job.canonical_url
          )
        ),
        public.card_enrichment_job_has_pending_staging(
          job.staging_id, job.card_id, job.parser_version
        )
      ) AS action
    ) AS decision
    WHERE job.parser_version = selected_parser
      AND job.status IN ('completed', 'staged', 'quarantined', 'review_required', 'failed')
      AND job.status <> 'processing'
      AND job.next_retry_at IS NULL
      AND (job.lease_expires_at IS NULL OR job.lease_expires_at <= _now)
      AND (job.run_mode = 'scheduled' OR decision.action = 'clear')
      AND (job.next_run_at IS NULL OR job.next_run_at <= _now OR decision.action = 'clear')
      AND decision.action <> 'none'
    ORDER BY CASE WHEN decision.action = 'queue' THEN 0 ELSE 1 END,
      job.next_run_at, lower(trim(job.issuer)), job.id
    LIMIT _limit
    FOR UPDATE OF job SKIP LOCKED
  ), updated AS (
    UPDATE public.card_catalog_enrichment_jobs AS job
    SET status = CASE WHEN selected.action = 'queue' THEN 'queued' ELSE job.status END,
      attempt_count = CASE WHEN selected.action = 'queue' THEN 0 ELSE job.attempt_count END,
      next_retry_at = CASE WHEN selected.action = 'queue' THEN NULL ELSE job.next_retry_at END,
      next_run_at = NULL,
      lease_expires_at = CASE WHEN selected.action = 'queue' THEN NULL ELSE job.lease_expires_at END,
      lease_token = CASE WHEN selected.action = 'queue' THEN NULL ELSE job.lease_token END,
      failure_category = CASE WHEN selected.action = 'queue' THEN NULL ELSE job.failure_category END,
      updated_at = _now
    FROM selected
    WHERE job.id = selected.id
    RETURNING job.id, selected.action
  )
  SELECT job.*
  FROM public.card_catalog_enrichment_jobs AS job
  JOIN updated ON updated.id = job.id
  WHERE updated.action = 'queue';
END;
$$;


--
-- Name: reset_my_cardcompass_data(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.reset_my_cardcompass_data() RETURNS void
    LANGUAGE sql
    SET search_path TO ''
    AS $$
  SELECT private.reset_my_cardcompass_data();
$$;


--
-- Name: resolve_card_catalog_identity(text, text, text, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.resolve_card_catalog_identity(_issuer text, _card_name text, _network text, _source_url text, _submitted_url_hash text, _final_url_hash text) RETURNS uuid
    LANGUAGE plpgsql
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $_$
DECLARE
  normalized_issuer text := lower(trim(coalesce(_issuer, '')));
  normalized_name text := public.normalize_card_catalog_product(_card_name);
  normalized_family text;
  normalized_network text;
  normalized_tier text := public.normalize_card_catalog_tier(_card_name);
  submitted_bound_cards uuid[];
  final_bound_cards uuid[];
  submitted_bound_card uuid;
  final_bound_card uuid;
  bound_card uuid;
  candidate_ids uuid[];
  compatible_candidate_ids uuid[];
  resolved_id uuid;
  resolved_bank text;
  resolved_name text;
  resolved_network text;
  resolved_tier text;
  resolved_card_type text;
BEGIN
  normalized_network := public.card_catalog_effective_network(
    _network, _card_name, _issuer
  );
  normalized_family := coalesce(
    nullif(public.normalize_card_catalog_family(_card_name), ''),
    nullif(normalized_name, ''),
    normalized_tier
  );
  IF length(normalized_issuer) < 2 OR length(normalized_name) < 2
     OR (normalized_name IN (
       'visa', 'mastercard', 'rupay', 'americanexpress',
       'gold', 'platinum', 'infinite', 'signature', 'world'
     ) AND NOT (
       normalized_issuer = 'american express'
       AND normalized_network = 'americanexpress'
       AND normalized_tier IS NOT NULL
     )) THEN
    RAISE EXCEPTION 'invalid_catalog_identity';
  END IF;
  IF public.canonical_card_resource_url(_source_url) IS DISTINCT FROM trim(_source_url) THEN
    RAISE EXCEPTION 'noncanonical_source_url';
  END IF;
  IF NOT public.card_catalog_source_matches_issuer(_issuer, _source_url) THEN
    RAISE EXCEPTION 'unapproved_domain';
  END IF;
  IF lower(coalesce(_submitted_url_hash, '')) !~ '^[0-9a-f]{64}$'
     OR lower(coalesce(_final_url_hash, '')) !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'invalid_url_hash';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(
    'card_catalog_publication:url:' || least(lower(_submitted_url_hash), lower(_final_url_hash)), 0
  ));
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'card_catalog_publication:url:' || greatest(lower(_submitted_url_hash), lower(_final_url_hash)), 0
  ));
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'card_catalog_identity:' || normalized_issuer || ':' || normalized_family, 0
  ));

  SELECT array_agg(DISTINCT binding.card_id ORDER BY binding.card_id)
  INTO submitted_bound_cards
  FROM (
    SELECT key.card_id FROM public.card_catalog_url_keys AS key
      WHERE key.url_hash = lower(_submitted_url_hash)
    UNION ALL
    SELECT provenance.card_id FROM public.card_catalog_provenance AS provenance
      WHERE provenance.submitted_url_hash = lower(_submitted_url_hash)
         OR provenance.final_url_hash = lower(_submitted_url_hash)
  ) AS binding;
  SELECT array_agg(DISTINCT binding.card_id ORDER BY binding.card_id)
  INTO final_bound_cards
  FROM (
    SELECT key.card_id FROM public.card_catalog_url_keys AS key
      WHERE key.url_hash = lower(_final_url_hash)
    UNION ALL
    SELECT provenance.card_id FROM public.card_catalog_provenance AS provenance
      WHERE provenance.submitted_url_hash = lower(_final_url_hash)
         OR provenance.final_url_hash = lower(_final_url_hash)
  ) AS binding;
  IF coalesce(cardinality(submitted_bound_cards), 0) > 1
     OR coalesce(cardinality(final_bound_cards), 0) > 1 THEN
    RAISE EXCEPTION 'conflicting_url_identity';
  END IF;
  submitted_bound_card := submitted_bound_cards[1];
  final_bound_card := final_bound_cards[1];
  IF submitted_bound_card IS NOT NULL AND final_bound_card IS NOT NULL
     AND submitted_bound_card <> final_bound_card THEN
    RAISE EXCEPTION 'conflicting_url_identity';
  END IF;
  bound_card := coalesce(submitted_bound_card, final_bound_card);

  WITH matches AS (
    SELECT catalog.id
    FROM public.card_catalog AS catalog
    WHERE lower(trim(catalog.bank)) = normalized_issuer
      AND lower(trim(coalesce(catalog.card_type, ''))) = 'credit'
      AND coalesce(
        nullif(public.normalize_card_catalog_family(catalog.card_name), ''),
        public.normalize_card_catalog_product(catalog.card_name)
      ) = normalized_family
    UNION
    SELECT catalog.id
    FROM public.card_catalog AS catalog
    JOIN public.card_catalog_aliases AS alias ON alias.card_id = catalog.id
    WHERE lower(trim(catalog.bank)) = normalized_issuer
      AND lower(trim(coalesce(catalog.card_type, ''))) = 'credit'
      AND public.normalize_card_catalog_product(alias.alias) = normalized_name
      AND normalized_name NOT IN (
        'visa', 'mastercard', 'rupay', 'americanexpress',
        'gold', 'platinum', 'infinite', 'signature', 'world'
      )
  )
  SELECT array_agg(id ORDER BY id) INTO candidate_ids FROM matches;

  IF bound_card IS NOT NULL THEN
    SELECT catalog.bank, catalog.card_name,
      public.card_catalog_effective_network(catalog.network, catalog.card_name, catalog.bank),
      public.normalize_card_catalog_tier(catalog.card_name), catalog.card_type
    INTO resolved_bank, resolved_name, resolved_network, resolved_tier,
      resolved_card_type
    FROM public.card_catalog AS catalog WHERE catalog.id = bound_card;
    IF lower(trim(coalesce(resolved_bank, ''))) <> normalized_issuer
       OR lower(trim(coalesce(resolved_card_type, ''))) <> 'credit'
       OR (resolved_network IS NOT NULL AND (
         normalized_network IS NULL OR normalized_network <> resolved_network
       ))
       OR (resolved_tier IS NOT NULL AND (
         normalized_tier IS NULL OR normalized_tier <> resolved_tier
       )) THEN
      RAISE EXCEPTION 'url_identity_incompatible';
    END IF;
    IF NOT (bound_card = ANY(coalesce(candidate_ids, ARRAY[]::uuid[]))) THEN
      RAISE EXCEPTION 'url_identity_incompatible';
    END IF;
    resolved_id := bound_card;
  ELSE
    SELECT array_agg(catalog.id ORDER BY catalog.id)
    INTO compatible_candidate_ids
    FROM public.card_catalog AS catalog
    WHERE catalog.id = ANY(coalesce(candidate_ids, ARRAY[]::uuid[]))
      AND lower(trim(coalesce(catalog.card_type, ''))) = 'credit'
      AND public.card_catalog_effective_network(catalog.network, catalog.card_name, catalog.bank)
        IS NOT DISTINCT FROM normalized_network
      AND public.normalize_card_catalog_tier(catalog.card_name)
        IS NOT DISTINCT FROM normalized_tier;
    IF coalesce(cardinality(compatible_candidate_ids), 0) > 1 THEN
      RAISE EXCEPTION 'ambiguous_catalog_identity';
    END IF;
    IF coalesce(cardinality(candidate_ids), 0) > 0
       AND coalesce(cardinality(compatible_candidate_ids), 0) = 0 THEN
      RAISE EXCEPTION 'strong_catalog_identity_conflict';
    END IF;
    resolved_id := compatible_candidate_ids[1];
  END IF;

  IF resolved_id IS NULL THEN
    INSERT INTO public.card_catalog(bank, card_name, network, card_type, card_url)
    VALUES (
      trim(_issuer), trim(_card_name), nullif(trim(_network), ''), 'credit', trim(_source_url)
    )
    RETURNING id INTO resolved_id;
  END IF;

  INSERT INTO public.card_catalog_url_keys(url_hash, card_id, canonical_url)
  VALUES (lower(_submitted_url_hash), resolved_id, trim(_source_url))
  ON CONFLICT (url_hash) DO NOTHING;
  IF lower(_final_url_hash) <> lower(_submitted_url_hash) THEN
    INSERT INTO public.card_catalog_url_keys(url_hash, card_id, canonical_url)
    VALUES (lower(_final_url_hash), resolved_id, trim(_source_url))
    ON CONFLICT (url_hash) DO NOTHING;
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.card_catalog_url_keys AS key
    WHERE key.url_hash IN (lower(_submitted_url_hash), lower(_final_url_hash))
      AND key.card_id <> resolved_id
  ) THEN
    RAISE EXCEPTION 'conflicting_url_identity';
  END IF;
  RETURN resolved_id;
END;
$_$;


--
-- Name: review_card_catalog_discovery(uuid, uuid, text, jsonb, uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.review_card_catalog_discovery(_review_item_id uuid, _actor_id uuid, _action text, _proposed_fields jsonb DEFAULT NULL::jsonb, _merge_card_id uuid DEFAULT NULL::uuid, _reason text DEFAULT NULL::text) RETURNS TABLE(card_id uuid, job_id uuid, resulting_status text)
    LANGUAGE plpgsql
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
DECLARE
  discovery_job_id uuid;
BEGIN
  SELECT review.discovery_job_id INTO discovery_job_id
  FROM public.card_catalog_review_queue AS review
  WHERE review.id = _review_item_id;
  IF discovery_job_id IS NULL THEN RAISE EXCEPTION 'review_item_not_found'; END IF;
  RETURN QUERY
  SELECT published.card_id, published.job_id, published.resulting_status
  FROM public.publish_card_catalog_identity(
    discovery_job_id, _review_item_id, _actor_id, _action,
    CASE WHEN _action = 'edit_approve'
      THEN coalesce(_proposed_fields, '{}'::jsonb)
      ELSE '{}'::jsonb END,
    _merge_card_id, _reason,
    'benefits-v6'
  ) AS published;
END;
$$;


--
-- Name: sanitize_card_enrichment_observation(jsonb, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sanitize_card_enrichment_observation(_observation jsonb, _now timestamp with time zone) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    SET search_path TO 'public', 'pg_temp'
    AS $_$
DECLARE
  observed_at_value text;
  safe_attempts jsonb;
  safe_absent_ids jsonb;
  safe_absent_legacy_ids jsonb;
  safe_source_observation jsonb;
BEGIN
  IF jsonb_typeof(_observation) <> 'object' OR _now IS NULL THEN RETURN NULL; END IF;
  observed_at_value := public.bounded_card_enrichment_timestamp(
    _observation->>'observed_at', _now
  );
  IF observed_at_value IS NULL THEN RETURN NULL; END IF;
  SELECT coalesce(jsonb_agg(value ORDER BY value), '[]'::jsonb)
  INTO safe_absent_ids
  FROM (
    SELECT DISTINCT left(jsonb_array_elements_text(
      CASE WHEN jsonb_typeof(_observation->'absent_benefit_ids') = 'array'
        THEN _observation->'absent_benefit_ids' ELSE '[]'::jsonb END
    ), 256) AS value
    LIMIT 256
  ) AS values;
  SELECT coalesce(jsonb_agg(value ORDER BY value), '[]'::jsonb)
  INTO safe_absent_legacy_ids
  FROM (
    SELECT DISTINCT left(jsonb_array_elements_text(
      CASE WHEN jsonb_typeof(_observation->'absent_legacy_benefit_ids') = 'array'
        THEN _observation->'absent_legacy_benefit_ids' ELSE '[]'::jsonb END
    ), 256) AS value
    LIMIT 256
  ) AS values;
  SELECT coalesce(jsonb_agg(safe_attempt ORDER BY attempt_index), '[]'::jsonb)
  INTO safe_attempts
  FROM (
    SELECT attempt_index,
      public.sanitize_card_enrichment_source_attempt(attempt, _now) AS safe_attempt
    FROM jsonb_array_elements(
      CASE WHEN jsonb_typeof(_observation->'source_attempts') = 'array'
        THEN _observation->'source_attempts' ELSE '[]'::jsonb END
    ) WITH ORDINALITY AS entries(attempt, attempt_index)
    ORDER BY attempt_index
    LIMIT 9
  ) AS attempts
  WHERE safe_attempt IS NOT NULL;
  safe_source_observation := CASE
    WHEN jsonb_typeof(_observation->'source_observation') = 'object' THEN
      jsonb_strip_nulls(jsonb_build_object(
        'parser_version', left(_observation#>>'{source_observation,parser_version}', 64),
        'terminal_disposition', left(_observation#>>'{source_observation,terminal_disposition}', 64),
        'review_reason', left(_observation#>>'{source_observation,review_reason}', 64),
        'crawl_complete', CASE
          WHEN jsonb_typeof(_observation#>'{source_observation,crawl_complete}') = 'boolean'
          THEN _observation#>'{source_observation,crawl_complete}' END,
        'http_status', CASE
          WHEN _observation#>>'{source_observation,http_status}' ~ '^[1-5][0-9]{2}$'
          THEN (_observation#>>'{source_observation,http_status}')::integer END,
        'submitted_url', CASE
          WHEN _observation#>>'{source_observation,submitted_url}' ~ '^https://[^/@?#]+(?:/[^?#]*)?$'
          THEN left(_observation#>>'{source_observation,submitted_url}', 2048) END,
        'final_url', CASE
          WHEN _observation#>>'{source_observation,final_url}' ~ '^https://[^/@?#]+(?:/[^?#]*)?$'
          THEN left(_observation#>>'{source_observation,final_url}', 2048) END,
        'canonical_url', CASE
          WHEN _observation#>>'{source_observation,canonical_url}' ~ '^https://[^/@?#]+(?:/[^?#]*)?$'
          THEN left(_observation#>>'{source_observation,canonical_url}', 2048) END,
        'retrieved_at', public.bounded_card_enrichment_timestamp(
          _observation#>>'{source_observation,retrieved_at}', _now
        ),
        'not_modified', CASE
          WHEN jsonb_typeof(_observation#>'{source_observation,not_modified}') = 'boolean'
          THEN _observation#>'{source_observation,not_modified}' END,
        'etag', left(_observation#>>'{source_observation,etag}', 512),
        'last_modified', left(_observation#>>'{source_observation,last_modified}', 512),
        'content_hash', CASE
          WHEN _observation#>>'{source_observation,content_hash}' ~ '^[0-9a-f]{64}$'
          THEN _observation#>>'{source_observation,content_hash}' END,
        'submitted_identity_hash', CASE
          WHEN _observation#>>'{source_observation,submitted_identity_hash}' ~ '^[0-9a-f]{64}$'
          THEN _observation#>>'{source_observation,submitted_identity_hash}' END,
        'final_resource_url', CASE
          WHEN _observation#>>'{source_observation,final_resource_url}' ~ '^https://[^/@?#]+(?:/[^?#]*)?$'
          THEN left(_observation#>>'{source_observation,final_resource_url}', 2048) END,
        'final_resource_identity_hash', CASE
          WHEN _observation#>>'{source_observation,final_resource_identity_hash}' ~ '^[0-9a-f]{64}$'
          THEN _observation#>>'{source_observation,final_resource_identity_hash}' END,
        'card_identity_validated', CASE
          WHEN jsonb_typeof(_observation#>'{source_observation,card_identity_validated}') = 'boolean'
          THEN _observation#>'{source_observation,card_identity_validated}' END
      ))
    ELSE NULL
  END;
  RETURN jsonb_strip_nulls(jsonb_build_object(
    'observed_at', observed_at_value,
    'crawl_complete', CASE WHEN jsonb_typeof(_observation->'crawl_complete') = 'boolean'
      THEN _observation->'crawl_complete' ELSE 'false'::jsonb END,
    'crawl_reason', left(coalesce(_observation->>'crawl_reason', 'invalid_observation'), 64),
    'source_manifest_hash', CASE WHEN _observation->>'source_manifest_hash' ~ '^[0-9a-f]{64}$'
      THEN _observation->>'source_manifest_hash' END,
    'canonical_benefit_hash', CASE WHEN _observation->>'canonical_benefit_hash' ~ '^[0-9a-f]{64}$'
      THEN _observation->>'canonical_benefit_hash' END,
    'absent_benefit_ids', safe_absent_ids,
    'absent_legacy_benefit_ids', safe_absent_legacy_ids,
    'source_attempts', safe_attempts,
    'source_observation', safe_source_observation
  ));
END;
$_$;


--
-- Name: sanitize_card_enrichment_result_summary(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sanitize_card_enrichment_result_summary(_summary jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    SET search_path TO 'public', 'pg_temp'
    AS $_$
DECLARE
  safe_summary jsonb := '{}'::jsonb;
  allowed_key text;
  allowed_value jsonb;
  allowed_text text;
BEGIN
  IF jsonb_typeof(_summary) <> 'object' THEN RETURN safe_summary; END IF;
  FOREACH allowed_key IN ARRAY ARRAY[
    'run_id', 'source_documents', 'proposals', 'additions', 'modifications',
    'possible_removals', 'retirement_eligible_removals',
    'suppressed_removal_count', 'conflicts', 'reused_staging',
    'material_proposal', 'proposal_disposition', 'successful_no_change',
    'source_manifest_hash', 'canonical_benefit_hash', 'crawl_complete',
    'unsafe_mutation_count', 'raw_body_stored', 'evidence_passed',
    'idempotency_passed', 'quarantine_reason', 'retry_scheduled',
    'lease_expired', 'pilot_qualified', 'reviewed_at', 'review_status', 'approved_count',
    'retired_count', 'rejected_count', 'retained_count'
  ] LOOP
    IF _summary ? allowed_key THEN
      allowed_value := _summary->allowed_key;
      allowed_text := allowed_value#>>'{}';
      IF allowed_key = ANY (ARRAY[
        'reused_staging', 'material_proposal', 'successful_no_change',
        'crawl_complete', 'raw_body_stored', 'evidence_passed',
        'idempotency_passed', 'retry_scheduled', 'lease_expired',
        'pilot_qualified'
      ]) AND jsonb_typeof(allowed_value) = 'boolean' THEN
        safe_summary := jsonb_set(safe_summary, ARRAY[allowed_key], allowed_value, true);
      ELSIF allowed_key = ANY (ARRAY[
        'source_documents', 'proposals', 'additions', 'modifications',
        'possible_removals', 'retirement_eligible_removals',
        'suppressed_removal_count', 'conflicts', 'unsafe_mutation_count',
        'approved_count', 'retired_count', 'rejected_count', 'retained_count'
      ]) AND jsonb_typeof(allowed_value) = 'number'
        AND allowed_text ~ '^[0-9]{1,9}$' THEN
        safe_summary := jsonb_set(safe_summary, ARRAY[allowed_key], allowed_value, true);
      ELSIF allowed_key IN ('source_manifest_hash', 'canonical_benefit_hash')
        AND jsonb_typeof(allowed_value) = 'string'
        AND allowed_text ~ '^[0-9a-f]{64}$' THEN
        safe_summary := jsonb_set(safe_summary, ARRAY[allowed_key], allowed_value, true);
      ELSIF allowed_key = 'run_id'
        AND jsonb_typeof(allowed_value) = 'string'
        AND allowed_text ~ '^[0-9a-f-]{1,64}$' THEN
        safe_summary := jsonb_set(safe_summary, ARRAY[allowed_key], allowed_value, true);
      ELSIF allowed_key = 'proposal_disposition'
        AND allowed_text IN ('material', 'removal_review', 'no_change', 'incomplete') THEN
        safe_summary := jsonb_set(safe_summary, ARRAY[allowed_key], allowed_value, true);
      ELSIF allowed_key = 'quarantine_reason'
        AND jsonb_typeof(allowed_value) = 'string'
        AND allowed_text ~ '^[a-z0-9_]{1,64}$' THEN
        safe_summary := jsonb_set(safe_summary, ARRAY[allowed_key], allowed_value, true);
      ELSIF allowed_key = 'review_status'
        AND allowed_text IN ('approved', 'rejected') THEN
        safe_summary := jsonb_set(safe_summary, ARRAY[allowed_key], allowed_value, true);
      ELSIF allowed_key = 'reviewed_at'
        AND jsonb_typeof(allowed_value) = 'string' THEN
        allowed_text := public.bounded_card_enrichment_timestamp(
          allowed_text, statement_timestamp()
        );
        IF allowed_text IS NOT NULL THEN
          safe_summary := jsonb_set(
            safe_summary, ARRAY[allowed_key], to_jsonb(allowed_text), true
          );
        END IF;
      END IF;
    END IF;
  END LOOP;
  RETURN safe_summary;
END;
$_$;


--
-- Name: sanitize_card_enrichment_source_attempt(jsonb, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sanitize_card_enrichment_source_attempt(_attempt jsonb, _now timestamp with time zone) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    SET search_path TO 'public', 'pg_temp'
    AS $_$
DECLARE
  attempted_at_value text;
  safe_url text;
  safe_history jsonb;
BEGIN
  IF jsonb_typeof(_attempt) <> 'object' OR _now IS NULL THEN RETURN NULL; END IF;
  attempted_at_value := public.bounded_card_enrichment_timestamp(
    _attempt->>'attemptedAt', _now
  );
  IF attempted_at_value IS NULL THEN RETURN NULL; END IF;
  safe_url := CASE
    WHEN _attempt->>'url' = 'invalid-source' THEN 'invalid-source'
    WHEN _attempt->>'url' ~ '^https://[^/@?#]+(?:/[^?#]*)?$'
      THEN left(_attempt->>'url', 2048)
    ELSE 'invalid-source'
  END;
  SELECT coalesce(jsonb_agg(history_value ORDER BY history_index), '[]'::jsonb)
  INTO safe_history
  FROM (
    SELECT history_index, jsonb_strip_nulls(jsonb_build_object(
      'status', CASE WHEN history->>'status' IN ('success', 'not_modified', 'failed')
        THEN history->>'status' END,
      'httpStatus', CASE WHEN history->>'httpStatus' ~ '^[1-5][0-9]{2}$'
        THEN (history->>'httpStatus')::integer END,
      'errorCode', CASE WHEN history->>'errorCode' ~ '^[a-z0-9_]{1,64}$'
        THEN history->>'errorCode' END,
      'finalResourceIdentityHash', CASE
        WHEN history->>'finalResourceIdentityHash' ~ '^[0-9a-f]{64}$'
        THEN history->>'finalResourceIdentityHash' END,
      'attemptedAt', public.bounded_card_enrichment_timestamp(
        history->>'attemptedAt', _now
      )
    )) AS history_value
    FROM jsonb_array_elements(
      CASE WHEN jsonb_typeof(_attempt->'attemptHistory') = 'array'
        THEN _attempt->'attemptHistory' ELSE '[]'::jsonb END
    ) WITH ORDINALITY AS entries(history, history_index)
    WHERE jsonb_typeof(history) = 'object'
    ORDER BY history_index
    LIMIT 6
  ) AS bounded_history;
  RETURN jsonb_strip_nulls(jsonb_build_object(
    'url', safe_url,
    'role', CASE WHEN _attempt->>'role' IN ('primary', 'required_supporting', 'supporting')
      THEN _attempt->>'role' END,
    'status', CASE WHEN _attempt->>'status' IN ('success', 'not_modified', 'failed')
      THEN _attempt->>'status' END,
    'httpStatus', CASE WHEN _attempt->>'httpStatus' ~ '^[1-5][0-9]{2}$'
      THEN (_attempt->>'httpStatus')::integer END,
    'contentHash', CASE WHEN _attempt->>'contentHash' ~ '^[0-9a-f]{64}$'
      THEN _attempt->>'contentHash' END,
    'finalResourceIdentityHash', CASE
      WHEN _attempt->>'finalResourceIdentityHash' ~ '^[0-9a-f]{64}$'
      THEN _attempt->>'finalResourceIdentityHash' END,
    'errorCode', CASE WHEN _attempt->>'errorCode' ~ '^[a-z0-9_]{1,64}$'
      THEN _attempt->>'errorCode' END,
    'attemptedAt', attempted_at_value,
    'parserCacheReusable', CASE WHEN jsonb_typeof(_attempt->'parserCacheReusable') = 'boolean'
      THEN _attempt->'parserCacheReusable' END,
    'logicalSourceKey', CASE WHEN _attempt->>'logicalSourceKey' ~ '^[0-9a-f]{64}$'
      THEN _attempt->>'logicalSourceKey' END,
    'attemptHistory', safe_history,
    'attemptHistoryOverflow', CASE WHEN jsonb_typeof(_attempt->'attemptHistoryOverflow') = 'boolean'
      THEN _attempt->'attemptHistoryOverflow' END
  ));
END;
$_$;


--
-- Name: schedule_terminal_card_enrichment_observation(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.schedule_terminal_card_enrichment_observation() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  card_is_discontinued boolean;
  active_cardholder boolean;
  terminal_disposition text;
  recurrence_outcome text;
BEGIN
  IF NEW.parser_version = 'benefits-v6'
     AND NEW.run_mode = 'scheduled'
     AND NEW.status IN ('completed', 'staged', 'quarantined', 'review_required', 'failed')
     AND NEW.next_retry_at IS NULL THEN
    SELECT coalesce(card.is_discontinued, false), EXISTS (
      SELECT 1 FROM public.user_cards AS user_card
      WHERE user_card.catalog_card_id = NEW.card_id
        AND user_card.is_active = true
    )
    INTO card_is_discontinued, active_cardholder
    FROM public.card_catalog AS card
    WHERE card.id = NEW.card_id;
    IF public.card_has_unresolved_catalog_identity(NEW.card_id, NEW.canonical_url) THEN
      NEW.next_run_at := NULL;
      RETURN NEW;
    END IF;
    terminal_disposition := lower(coalesce(
      NEW.result_summary#>>'{source_observation,terminal_disposition}',
      NEW.result_summary#>>'{observation,source_observation,terminal_disposition}',
      NEW.result_summary->>'terminal_disposition',
      ''
    ));
    recurrence_outcome := CASE
      WHEN terminal_disposition = 'not_modified' THEN 'not_modified'
      WHEN terminal_disposition IN ('missing', 'not_found')
        OR NEW.failure_category IN ('http_404', 'http_410', 'missing') THEN 'missing'
      WHEN terminal_disposition IN ('blocked', 'review_required')
        OR NEW.failure_category IN ('http_401', 'http_403', 'http_429', 'robots_disallowed', 'challenge_page')
        THEN 'blocked'
      WHEN NEW.failure_category IS NOT NULL
        OR terminal_disposition IN ('failed', 'timeout', 'unreachable', 'http_5xx')
        THEN 'failed'
      WHEN NEW.status IN ('completed', 'staged') THEN 'success'
      ELSE 'failed'
    END;
    NEW.next_run_at := public.next_card_enrichment_observation_at(
      NEW.card_id,
      to_char(
        statement_timestamp() AT TIME ZONE 'UTC',
        'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
      ),
      card_is_discontinued,
      active_cardholder,
      recurrence_outcome
    );
  ELSIF NEW.parser_version = 'benefits-v6' THEN
    NEW.next_run_at := NULL;
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: set_card_catalog_enrichment_job_key(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_card_catalog_enrichment_job_key() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
  NEW.job_key := NEW.card_id::text || ':' || NEW.final_url_hash || ':' || NEW.parser_version;
  RETURN NEW;
END;
$$;


--
-- Name: stage_card_benefit_enrichment(uuid, uuid, text, text, text, text, jsonb, numeric, jsonb, jsonb, jsonb, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.stage_card_benefit_enrichment(_job_id uuid, _lease_token uuid, _source_url text, _source_url_hash text, _parser_version text, _content_hash text, _extracted_data jsonb, _calculated_confidence numeric, _validation_reasons jsonb, _validation_warnings jsonb, _source_evidence jsonb, _validated_at timestamp with time zone) RETURNS TABLE(staging_id uuid, reused boolean)
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $_$
DECLARE
  job public.card_catalog_enrichment_jobs%ROWTYPE;
  job_card_id uuid;
  resolved_staging_id uuid;
  reused_staging boolean := false;
  newest_pending_id uuid;
  newest_pending_validated_at timestamptz;
BEGIN
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
     OR _validated_at IS NULL
     -- Keep the database guard aligned with MAX_EVIDENCE_CLOCK_SKEW_MS.
     OR _validated_at > statement_timestamp() + interval '5 minutes'
     OR NOT public.is_valid_official_source_evidence(_source_evidence) THEN
    RAISE EXCEPTION 'invalid_benefit_staging';
  END IF;

  -- Task 4 uses the same card-scoped serialization key. Pre-read only the
  -- immutable identity, then acquire the advisory lock before any row lock.
  SELECT candidate.card_id INTO job_card_id
  FROM public.card_catalog_enrichment_jobs AS candidate
  WHERE candidate.id = _job_id;
  IF job_card_id IS NULL THEN
    RAISE EXCEPTION 'stale_enrichment_lease';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'card_benefit_enrichment_review:' || job_card_id::text,
    0
  ));

  SELECT candidate.* INTO job
  FROM public.card_catalog_enrichment_jobs AS candidate
  WHERE candidate.id = _job_id
    AND candidate.card_id = job_card_id
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

  IF _parser_version = 'benefits-v6' THEN
    -- Acquire row locks in UUID order so concurrent reviewers/stagers cannot
    -- invert their lock order.
    PERFORM locked.id
    FROM (
      SELECT staging.id
      FROM public.card_benefits_staging AS staging
      WHERE staging.card_id = job.card_id
        AND staging.parser_version = _parser_version
        AND staging.request_type = 'official_benefit_enrichment'
        AND staging.status = 'pending'
      ORDER BY staging.id
      FOR UPDATE
    ) AS locked;

    -- A corrupt future row must not indefinitely win newest-observation order.
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
          'reason', 'invalid_future_observation_timestamp',
          'rejected_at', timezone('UTC', statement_timestamp())
        )),
        status = 'rejected',
        updated_at = statement_timestamp()
    WHERE staging.card_id = job.card_id
      AND staging.parser_version = _parser_version
      AND staging.request_type = 'official_benefit_enrichment'
      AND staging.status = 'pending'
      AND staging.validated_at > statement_timestamp() + interval '5 minutes';

    SELECT staging.id, staging.validated_at
    INTO newest_pending_id, newest_pending_validated_at
    FROM public.card_benefits_staging AS staging
    WHERE staging.card_id = job.card_id
      AND staging.parser_version = _parser_version
      AND staging.request_type = 'official_benefit_enrichment'
      AND staging.status = 'pending'
    ORDER BY staging.validated_at DESC NULLS FIRST, staging.id DESC
    LIMIT 1;

    -- Unknown legacy time or an equal/newer pending observation wins. The
    -- incoming job still records its crawl summary through finalization but
    -- cannot create a competing pending review row.
    IF newest_pending_id IS NOT NULL AND (
      newest_pending_validated_at IS NULL
      OR _validated_at <= newest_pending_validated_at
    ) THEN
      UPDATE public.card_catalog_enrichment_jobs
      SET staging_id = newest_pending_id,
          updated_at = now()
      WHERE id = _job_id;
      RETURN QUERY SELECT newest_pending_id, true;
      RETURN;
    END IF;
  END IF;

  SELECT staging.id INTO resolved_staging_id
  FROM public.card_benefits_staging AS staging
  WHERE staging.card_id = job.card_id
    AND staging.source_url_hash = _source_url_hash
    AND staging.parser_version = _parser_version
    AND staging.content_hash = _content_hash
    AND staging.request_type = 'official_benefit_enrichment'
    AND staging.status IN ('pending', 'approved')
    AND public.is_valid_official_source_evidence(staging.source_evidence)
  ORDER BY CASE WHEN staging.status = 'pending' THEN 0 ELSE 1 END,
           staging.validated_at DESC NULLS LAST,
           staging.id DESC
  LIMIT 1
  FOR UPDATE;
  reused_staging := FOUND;
  IF NOT reused_staging THEN
    resolved_staging_id := gen_random_uuid();
  END IF;

  IF _parser_version = 'benefits-v6' THEN
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
      AND staging.validated_at IS NOT NULL
      AND staging.validated_at < _validated_at
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
    _validated_at
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
$_$;


--
-- Name: stage_card_catalog_identity_review(uuid, text, uuid, text, text, text, text, jsonb, jsonb, jsonb, jsonb, numeric, text, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.stage_card_catalog_identity_review(_discovery_job_id uuid, _discovery_source text, _user_id uuid, _issuer text, _proposed_product text, _dedupe_key text, _semantic_hash text, _proposed_fields jsonb, _source_evidence jsonb, _existing_candidates jsonb, _validation_warnings jsonb, _confidence numeric, _expected_job_status text, _expected_job_updated_at timestamp with time zone) RETURNS TABLE(job_id uuid, review_item_id uuid, resulting_status text, created boolean)
    LANGUAGE plpgsql
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $_$
DECLARE
  locked_job public.card_discovery_jobs%ROWTYPE;
  locked_review public.card_catalog_review_queue%ROWTYPE;
  stage_identity text;
  stage_job_id uuid := _discovery_job_id;
  stage_review_id uuid;
  stage_now timestamptz := statement_timestamp();
  next_history jsonb;
  next_source_evidence jsonb;
  prior_semantic_hash text;
  mutable_statuses text[] := ARRAY[
    'queued', 'discovering', 'failed', 'review_required'
  ]::text[];
BEGIN
  IF _discovery_source NOT IN ('statement', 'issuer_crawl')
     OR length(trim(coalesce(_issuer, ''))) NOT BETWEEN 2 AND 120
     OR length(coalesce(_dedupe_key, '')) NOT BETWEEN 8 AND 256
     OR lower(coalesce(_semantic_hash, '')) !~ '^[0-9a-f]{64}$'
     OR jsonb_typeof(_proposed_fields) IS DISTINCT FROM 'object'
     OR jsonb_typeof(_source_evidence) IS DISTINCT FROM 'object'
     OR jsonb_typeof(_existing_candidates) IS DISTINCT FROM 'array'
     OR jsonb_typeof(_validation_warnings) IS DISTINCT FROM 'array'
     OR _confidence NOT BETWEEN 0 AND 1
     OR octet_length(_proposed_fields::text) > 16384
     OR octet_length(_source_evidence::text) > 16384
     OR octet_length(_existing_candidates::text) > 16384
     OR NOT public.card_catalog_json_envelope_valid(_proposed_fields, 0)
     OR NOT public.card_catalog_json_envelope_valid(_source_evidence, 0)
     OR NOT public.card_catalog_json_envelope_valid(_existing_candidates, 0)
     OR public.card_catalog_json_contains_sensitive_url(_proposed_fields)
     OR public.card_catalog_json_contains_sensitive_url(_source_evidence)
     OR public.card_catalog_json_contains_sensitive_url(_existing_candidates)
     OR (_discovery_source = 'statement' AND (_discovery_job_id IS NULL OR _user_id IS NULL))
     OR (_discovery_source = 'issuer_crawl' AND _user_id IS NOT NULL)
     OR (_expected_job_status IS NOT NULL AND
       NOT (_expected_job_status = ANY(mutable_statuses))) THEN
    RAISE EXCEPTION 'invalid_catalog_review_stage';
  END IF;

  stage_identity := _discovery_source || ':' || coalesce(_user_id::text, 'service') ||
    ':' || _dedupe_key || ':' || lower(_semantic_hash);
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'card_catalog_review_stage:' || stage_identity, 0
  ));

  IF stage_job_id IS NULL THEN
    SELECT job.id INTO stage_job_id
    FROM public.card_discovery_jobs AS job
    WHERE job.user_id IS NULL
      AND job.discovery_source = _discovery_source
      AND job.dedupe_key = _dedupe_key;
    IF stage_job_id IS NULL THEN
      INSERT INTO public.card_discovery_jobs(
        user_id, discovery_source, issuer, proposed_product, evidence,
        dedupe_key, status, updated_at
      ) VALUES (
        NULL, _discovery_source, trim(_issuer), nullif(trim(_proposed_product), ''),
        _source_evidence || jsonb_build_object(
          'semantic_product_hash', lower(_semantic_hash)
        ),
        _dedupe_key, 'queued', stage_now
      ) RETURNING id INTO stage_job_id;
    END IF;
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(
    'card_catalog_publication:job:' || stage_job_id::text, 0
  ));
  SELECT job.* INTO locked_job
  FROM public.card_discovery_jobs AS job
  WHERE job.id = stage_job_id
  FOR UPDATE;
  IF NOT FOUND
     OR locked_job.discovery_source IS DISTINCT FROM _discovery_source
     OR locked_job.user_id IS DISTINCT FROM _user_id
     OR lower(trim(locked_job.issuer)) IS DISTINCT FROM lower(trim(_issuer))
     OR locked_job.dedupe_key IS DISTINCT FROM _dedupe_key THEN
    RAISE EXCEPTION 'catalog_review_job_conflict';
  END IF;
  IF _expected_job_status IS NOT NULL AND (
    locked_job.status IS DISTINCT FROM _expected_job_status
    OR locked_job.updated_at IS DISTINCT FROM _expected_job_updated_at
  ) THEN
    RAISE EXCEPTION 'catalog_review_job_race';
  END IF;

  SELECT review.* INTO locked_review
  FROM public.card_catalog_review_queue AS review
  WHERE review.discovery_job_id = locked_job.id
  FOR UPDATE;

  prior_semantic_hash := coalesce(
    locked_review.source_evidence->>'semantic_product_hash',
    locked_job.evidence->>'semantic_product_hash'
  );
  IF locked_review.id IS NOT NULL
     AND locked_review.status IN ('approved', 'merged', 'rejected') THEN
    IF prior_semantic_hash IS DISTINCT FROM lower(_semantic_hash) THEN
      -- A material semantic observation must use a new versioned dedupe key;
      -- terminal decision artifacts are immutable.
      RAISE EXCEPTION 'terminal_catalog_review_requires_new_version';
    END IF;
    job_id := locked_job.id;
    review_item_id := locked_review.id;
    resulting_status := locked_job.status;
    created := false;
    RETURN NEXT;
    RETURN;
  END IF;

  next_history := public.append_catalog_observation_history(
    locked_review.source_evidence->'observation_history',
    jsonb_build_object(
      'observed_at', coalesce(
        _source_evidence->>'retrieved_at',
        _source_evidence->>'observed_at',
        stage_now::text
      ),
      'content_hash', _source_evidence->>'content_hash',
      'submitted_url_hash', coalesce(
        _source_evidence->>'submitted_url_hash',
        _source_evidence->>'submitted_resource_identity_hash'
      ),
      'final_url_hash', coalesce(
        _source_evidence->>'final_url_hash',
        _source_evidence->>'final_resource_identity_hash'
      ),
      'source_status', _source_evidence->'source_status',
      'semantic_hash', lower(_semantic_hash)
    )
  );
  next_source_evidence := _source_evidence || jsonb_build_object(
    'semantic_product_hash', lower(_semantic_hash),
    'observation_history', next_history
  );

  IF locked_review.id IS NULL THEN
    INSERT INTO public.card_catalog_review_queue(
      discovery_job_id, proposed_fields, source_evidence,
      existing_candidates, validation_warnings, confidence, status,
      updated_at
    ) VALUES (
      locked_job.id, _proposed_fields, next_source_evidence,
      _existing_candidates, _validation_warnings, _confidence, 'pending',
      stage_now
    ) RETURNING id INTO stage_review_id;
    created := true;
  ELSE
    stage_review_id := locked_review.id;
    UPDATE public.card_catalog_review_queue AS review SET
      proposed_fields = _proposed_fields,
      source_evidence = next_source_evidence,
      existing_candidates = _existing_candidates,
      validation_warnings = _validation_warnings,
      confidence = _confidence,
      updated_at = stage_now
    WHERE review.id = locked_review.id
      AND review.status = 'pending'
      AND review.updated_at IS NOT DISTINCT FROM locked_review.updated_at;
    IF NOT FOUND THEN RAISE EXCEPTION 'catalog_review_race'; END IF;
    INSERT INTO public.card_catalog_review_audit(
      review_item_id, actor_id, action, details
    ) VALUES (
      stage_review_id, NULL, 'refresh',
      jsonb_build_object(
        'semantic_product_hash', lower(_semantic_hash),
        'prior_semantic_product_hash', prior_semantic_hash,
        'history_retained', true
      )
    );
    created := false;
  END IF;

  UPDATE public.card_discovery_jobs AS job SET
    status = 'review_required',
    review_item_id = stage_review_id,
    failure_category = NULL,
    next_retry_at = NULL,
    evidence = job.evidence || jsonb_build_object(
      'semantic_product_hash', lower(_semantic_hash)
    ),
    updated_at = stage_now
  WHERE job.id = locked_job.id
    AND job.status = ANY(mutable_statuses)
    AND job.updated_at IS NOT DISTINCT FROM locked_job.updated_at;
  IF NOT FOUND THEN RAISE EXCEPTION 'catalog_review_job_race'; END IF;

  job_id := locked_job.id;
  review_item_id := stage_review_id;
  resulting_status := 'review_required';
  RETURN NEXT;
END;
$_$;


--
-- Name: stage_card_catalog_lifecycle_review(uuid, text, jsonb, text, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.stage_card_catalog_lifecycle_review(_card_id uuid, _suggested_action text, _source_observation jsonb, _source_url text, _source_url_hash text, _content_hash text, _parser_version text) RETURNS uuid
    LANGUAGE plpgsql
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $_$
DECLARE
  card_row public.card_catalog%ROWTYPE;
  catalog_baseline jsonb;
  lifecycle_dedupe_key text;
  lifecycle_job_id uuid;
  latest_lifecycle_job_id uuid;
  latest_lifecycle_state text;
  latest_lifecycle_observed_at timestamptz;
  latest_lifecycle_semantic_hash text;
  lifecycle_state text;
  lifecycle_observed_at timestamptz;
  existing_review public.card_catalog_review_queue%ROWTYPE;
  lifecycle_review_id uuid;
  source_status integer;
  observation_kind text;
  identity_validated boolean;
  explicit_discontinuation boolean;
  semantic_observation jsonb;
  source_observation_semantic_hash text;
  history_entry jsonb;
  prior_review_updated_at timestamptz;
BEGIN
  IF _card_id IS NULL
     OR _suggested_action NOT IN ('mark_discontinued', 'reactivate', 'observe_current')
     OR jsonb_typeof(_source_observation) IS DISTINCT FROM 'object'
     OR octet_length(_source_observation::text) > 16384
     OR NOT public.card_catalog_json_envelope_valid(_source_observation, 0)
     OR public.card_catalog_json_contains_sensitive_url(_source_observation)
     OR _parser_version IS DISTINCT FROM 'benefits-v6'
     OR lower(coalesce(_source_url_hash, '')) !~ '^[0-9a-f]{64}$'
     OR (_content_hash IS NOT NULL AND lower(_content_hash) !~ '^[0-9a-f]{64}$') THEN
    RAISE EXCEPTION 'invalid_catalog_lifecycle_review';
  END IF;
  IF public.canonical_card_resource_url(_source_url) IS DISTINCT FROM _source_url
     OR lower(_source_url_hash) IS DISTINCT FROM encode(
       extensions.digest(convert_to(_source_url, 'UTF8'), 'sha256'), 'hex'
     ) THEN
    RAISE EXCEPTION 'invalid_catalog_lifecycle_review';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(
    'card_benefit_enrichment_identity:' || _card_id::text || ':benefits-v6', 0
  ));
  SELECT catalog.* INTO card_row
  FROM public.card_catalog AS catalog
  WHERE catalog.id = _card_id
  FOR UPDATE;
  IF NOT FOUND
     OR lower(trim(coalesce(card_row.card_type, ''))) IS DISTINCT FROM 'credit'
     OR NOT public.card_catalog_source_matches_issuer(card_row.bank, _source_url) THEN
    RAISE EXCEPTION 'invalid_catalog_lifecycle_review';
  END IF;

  BEGIN
    source_status := nullif(_source_observation->>'source_status', '')::integer;
    lifecycle_observed_at := coalesce(
      nullif(_source_observation->>'retrieved_at', '')::timestamptz,
      nullif(_source_observation->>'attempted_at', '')::timestamptz,
      statement_timestamp()
    );
    explicit_discontinuation := coalesce(
      nullif(_source_observation->>'explicit_discontinuation', '')::boolean,
      false
    );
  EXCEPTION WHEN invalid_text_representation OR datetime_field_overflow THEN
    RAISE EXCEPTION 'invalid_catalog_lifecycle_review';
  END;
  IF lifecycle_observed_at > statement_timestamp() + interval '5 minutes' THEN
    RAISE EXCEPTION 'stale_catalog_lifecycle_observation';
  END IF;
  observation_kind := _source_observation->>'kind';
  identity_validated := _source_observation->>'identity_validated' = 'true';
  IF _suggested_action = 'mark_discontinued' THEN
    IF card_row.is_discontinued IS TRUE OR NOT (
      (observation_kind = 'strong_gone_observation' AND source_status = 410)
      OR (
        observation_kind = 'strong_explicit_discontinuation'
        AND source_status = 200 AND identity_validated
        AND explicit_discontinuation
      )
    ) THEN
      RAISE EXCEPTION 'invalid_catalog_lifecycle_review';
    END IF;
    lifecycle_state := 'discontinued';
  ELSIF _suggested_action = 'reactivate' THEN
    IF card_row.is_discontinued IS DISTINCT FROM true
       OR observation_kind IS DISTINCT FROM 'exact_card_reappearance'
       OR source_status IS DISTINCT FROM 200
       OR identity_validated IS DISTINCT FROM true
       OR explicit_discontinuation THEN
      RAISE EXCEPTION 'invalid_catalog_lifecycle_review';
    END IF;
    lifecycle_state := 'active';
  ELSIF card_row.is_discontinued IS TRUE THEN
    IF NOT (
      (observation_kind = 'strong_gone_observation' AND source_status = 410)
      OR (
        observation_kind = 'strong_explicit_discontinuation'
        AND source_status = 200 AND identity_validated
        AND explicit_discontinuation
      )
    ) THEN
      RAISE EXCEPTION 'invalid_catalog_lifecycle_review';
    END IF;
    lifecycle_state := 'discontinued';
  ELSE
    IF observation_kind IS DISTINCT FROM 'exact_card_reappearance'
       OR source_status IS DISTINCT FROM 200
       OR identity_validated IS DISTINCT FROM true
       OR explicit_discontinuation THEN
      RAISE EXCEPTION 'invalid_catalog_lifecycle_review';
    END IF;
    lifecycle_state := 'active';
  END IF;

  catalog_baseline := jsonb_build_object(
    'card_id', card_row.id,
    'card_name', card_row.card_name,
    'network', card_row.network,
    'annual_fee', card_row.annual_fee,
    'joining_fee', card_row.joining_fee,
    'apr', card_row.apr,
    'card_url', card_row.card_url,
    'is_discontinued', card_row.is_discontinued,
    'updated_at', card_row.updated_at,
    'version_observed_at', coalesce(
      card_row.updated_at,
      nullif(_source_observation->>'retrieved_at', '')::timestamptz
    )
  );
  semantic_observation := public.catalog_lifecycle_semantic_observation(
    _source_observation
  );
  source_observation_semantic_hash := encode(extensions.digest(
    convert_to(semantic_observation::text, 'UTF8'), 'sha256'
  ), 'hex');
  lifecycle_dedupe_key := encode(extensions.digest(convert_to(
    'catalog-lifecycle:' || card_row.id::text || ':' || _suggested_action || ':' ||
    (catalog_baseline - ARRAY['updated_at', 'version_observed_at'])::text || ':' ||
    lower(_source_url_hash) || ':' || source_observation_semantic_hash,
    'UTF8'
  ), 'sha256'), 'hex');
  history_entry := jsonb_build_object(
    'source_observation_semantic_hash', source_observation_semantic_hash,
    'semantic_hash', source_observation_semantic_hash,
    'observed_at', lifecycle_observed_at,
    'source_observation', _source_observation
  );

  -- latest_lifecycle_job_id is the serialized per-card evidence contract.
  SELECT job.id, job.evidence->>'lifecycle_state',
    nullif(job.evidence->>'lifecycle_observed_at', '')::timestamptz,
    job.evidence->>'source_observation_semantic_hash'
  INTO latest_lifecycle_job_id, latest_lifecycle_state,
    latest_lifecycle_observed_at, latest_lifecycle_semantic_hash
  FROM public.card_discovery_jobs AS job
  WHERE job.user_id IS NULL
    AND job.discovery_source = 'issuer_crawl'
    AND job.evidence->>'card_id' = card_row.id::text
    AND job.evidence ? 'lifecycle_state'
  ORDER BY nullif(job.evidence->>'lifecycle_observed_at', '')::timestamptz DESC,
    job.created_at DESC, job.id DESC
  LIMIT 1
  FOR UPDATE;
  IF latest_lifecycle_observed_at IS NOT NULL AND (
    lifecycle_observed_at < latest_lifecycle_observed_at
    OR (
      lifecycle_observed_at = latest_lifecycle_observed_at
      AND source_observation_semantic_hash IS DISTINCT FROM latest_lifecycle_semantic_hash
    )
  ) THEN
    RAISE EXCEPTION 'stale_catalog_lifecycle_observation';
  END IF;

  UPDATE public.card_catalog_review_queue AS stale_review
  SET status = 'rejected',
      review_reason = 'superseded_by_newer_lifecycle_observation',
      reviewed_at = statement_timestamp(),
      source_evidence = stale_review.source_evidence || jsonb_build_object(
        'superseded_by_newer_lifecycle_observation', true,
        'superseding_state', lifecycle_state,
        'superseding_observed_at', lifecycle_observed_at
      ),
      updated_at = statement_timestamp()
  FROM public.card_discovery_jobs AS stale_job
  WHERE stale_review.discovery_job_id = stale_job.id
    AND stale_review.status = 'pending'
    AND stale_job.user_id IS NULL
    AND stale_job.discovery_source = 'issuer_crawl'
    AND stale_job.evidence->>'card_id' = card_row.id::text
    AND stale_job.evidence->>'lifecycle_state' <> lifecycle_state
    AND coalesce(
      nullif(stale_job.evidence->>'lifecycle_observed_at', '')::timestamptz,
      '-infinity'::timestamptz
    ) <= lifecycle_observed_at;
  UPDATE public.card_discovery_jobs AS stale_job
  SET status = 'rejected', next_retry_at = NULL,
      failure_category = 'superseded_by_newer_lifecycle_observation',
      updated_at = statement_timestamp()
  WHERE stale_job.user_id IS NULL
    AND stale_job.discovery_source = 'issuer_crawl'
    AND stale_job.evidence->>'card_id' = card_row.id::text
    AND stale_job.evidence->>'lifecycle_state' <> lifecycle_state
    AND stale_job.status = 'review_required'
    AND EXISTS (
      SELECT 1 FROM public.card_catalog_review_queue AS stale_review
      WHERE stale_review.discovery_job_id = stale_job.id
        AND stale_review.status = 'rejected'
        AND stale_review.review_reason = 'superseded_by_newer_lifecycle_observation'
    );

  SELECT job.id INTO lifecycle_job_id
  FROM public.card_discovery_jobs AS job
  WHERE job.user_id IS NULL
    AND job.discovery_source = 'issuer_crawl'
    AND job.dedupe_key = lifecycle_dedupe_key;
  IF lifecycle_job_id IS NULL THEN
    INSERT INTO public.card_discovery_jobs(
      user_id, discovery_source, issuer, proposed_product, evidence,
      dedupe_key, status, updated_at
    ) VALUES (
      NULL, 'issuer_crawl', card_row.bank, card_row.card_name,
      jsonb_build_object(
        'card_id', card_row.id,
        'suggested_action', _suggested_action,
        'source_observation', _source_observation,
        'source_url', _source_url,
        'source_url_hash', lower(_source_url_hash),
        'content_hash', coalesce(lower(_content_hash), lower(_source_url_hash)),
        'source_observation_semantic_hash', source_observation_semantic_hash,
        'lifecycle_state', lifecycle_state,
        'lifecycle_observed_at', lifecycle_observed_at,
        'observation_history', jsonb_build_array(history_entry),
        'catalog_baseline', catalog_baseline
      ),
      lifecycle_dedupe_key,
      CASE WHEN _suggested_action = 'observe_current' THEN 'resolved' ELSE 'queued' END,
      statement_timestamp()
    )
    ON CONFLICT (discovery_source, dedupe_key)
      WHERE user_id IS NULL AND discovery_source = 'issuer_crawl'
    DO NOTHING
    RETURNING id INTO lifecycle_job_id;
    IF lifecycle_job_id IS NULL THEN
      SELECT job.id INTO lifecycle_job_id
      FROM public.card_discovery_jobs AS job
      WHERE job.user_id IS NULL
        AND job.discovery_source = 'issuer_crawl'
        AND job.dedupe_key = lifecycle_dedupe_key;
    END IF;
  END IF;

  -- Transport-only re-observations keep one semantic unit, advance its latest
  -- evidence time, and retain only the newest 24 distinct observations.
  UPDATE public.card_discovery_jobs AS job
  SET evidence = job.evidence || jsonb_build_object(
        'source_observation', _source_observation,
        'lifecycle_observed_at', greatest(
          coalesce(nullif(job.evidence->>'lifecycle_observed_at', '')::timestamptz,
            '-infinity'::timestamptz),
          lifecycle_observed_at
        ),
        'observation_history', public.append_catalog_observation_history(
          job.evidence->'observation_history', history_entry
        )
      ),
      resolved_card_id = CASE WHEN _suggested_action = 'observe_current'
        THEN card_row.id ELSE job.resolved_card_id END,
      updated_at = CASE
        WHEN lifecycle_observed_at > coalesce(
          nullif(job.evidence->>'lifecycle_observed_at', '')::timestamptz,
          '-infinity'::timestamptz
        ) THEN statement_timestamp()
        ELSE job.updated_at END
  WHERE job.id = lifecycle_job_id;

  IF _suggested_action = 'observe_current' THEN
    RETURN lifecycle_job_id;
  END IF;

  SELECT review.* INTO existing_review
  FROM public.card_catalog_review_queue AS review
  WHERE review.discovery_job_id = lifecycle_job_id
  FOR UPDATE;
  IF FOUND AND existing_review.status IN ('approved', 'merged', 'rejected') THEN
    RETURN existing_review.id;
  END IF;
  IF NOT FOUND THEN
    INSERT INTO public.card_catalog_review_queue(
      discovery_job_id, proposed_fields, source_evidence,
      existing_candidates, validation_warnings, confidence, status, updated_at
    ) VALUES (
      lifecycle_job_id,
      jsonb_build_object(
        'card_id', card_row.id,
        'issuer', card_row.bank,
        'cardName', card_row.card_name,
        'suggested_action', _suggested_action,
        'source_observation', _source_observation,
        'catalog_baseline', catalog_baseline
      ),
      jsonb_build_object(
        'source_url', _source_url,
        'source_url_hash', lower(_source_url_hash),
        'content_hash', coalesce(lower(_content_hash), lower(_source_url_hash)),
        'source_observation_semantic_hash', source_observation_semantic_hash,
        'source_observation', _source_observation,
        'lifecycle_state', lifecycle_state,
        'lifecycle_observed_at', lifecycle_observed_at,
        'catalog_baseline', catalog_baseline,
        'observation_history', jsonb_build_array(history_entry)
      ),
      jsonb_build_array(jsonb_build_object(
        'card_id', card_row.id,
        'card_name', card_row.card_name,
        'network', card_row.network,
        'card_type', card_row.card_type,
        'is_discontinued', card_row.is_discontinued
      )),
      jsonb_build_array('catalog_lifecycle_review_required'),
      1, 'pending', statement_timestamp()
    )
    ON CONFLICT (discovery_job_id) DO NOTHING
    RETURNING id INTO lifecycle_review_id;
  ELSE
    lifecycle_review_id := existing_review.id;
    prior_review_updated_at := existing_review.updated_at;
    UPDATE public.card_catalog_review_queue AS review SET
      proposed_fields = jsonb_build_object(
        'card_id', card_row.id,
        'issuer', card_row.bank,
        'cardName', card_row.card_name,
        'suggested_action', _suggested_action,
        'source_observation', _source_observation,
        'catalog_baseline', catalog_baseline
      ),
      source_evidence = jsonb_build_object(
        'source_url', _source_url,
        'source_url_hash', lower(_source_url_hash),
        'content_hash', coalesce(lower(_content_hash), lower(_source_url_hash)),
        'source_observation_semantic_hash', source_observation_semantic_hash,
        'source_observation', _source_observation,
        'lifecycle_state', lifecycle_state,
        'lifecycle_observed_at', lifecycle_observed_at,
        'catalog_baseline', catalog_baseline,
        'observation_history', public.append_catalog_observation_history(
          existing_review.source_evidence->'observation_history', history_entry
        )
      ),
      updated_at = statement_timestamp()
    WHERE review.id = lifecycle_review_id AND review.status = 'pending'
      AND review.updated_at IS NOT DISTINCT FROM prior_review_updated_at;
    IF NOT FOUND THEN RAISE EXCEPTION 'catalog_lifecycle_review_race'; END IF;
  END IF;
  IF lifecycle_review_id IS NULL THEN
    SELECT review.id INTO lifecycle_review_id
    FROM public.card_catalog_review_queue AS review
    WHERE review.discovery_job_id = lifecycle_job_id;
  END IF;
  IF lifecycle_review_id IS NULL THEN
    RAISE EXCEPTION 'catalog_lifecycle_review_race';
  END IF;
  UPDATE public.card_discovery_jobs SET
    status = 'review_required', review_item_id = lifecycle_review_id,
    failure_category = NULL, next_retry_at = NULL,
    updated_at = statement_timestamp()
  WHERE id = lifecycle_job_id AND status NOT IN ('resolved', 'rejected');
  RETURN lifecycle_review_id;
END;
$_$;


--
-- Name: submit_card_catalog_request(uuid, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.submit_card_catalog_request(_user_id uuid, _bank_name text, _card_name text, _card_url text) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  pending_count integer;
BEGIN
  IF _user_id IS NULL OR length(_bank_name) NOT BETWEEN 2 AND 100
     OR length(_card_name) NOT BETWEEN 2 AND 150
     OR length(_card_url) > 2048 THEN
    RETURN false;
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('catalog:' || _user_id::text));
  IF EXISTS (
    SELECT 1 FROM public.card_benefits_staging
    WHERE requested_by = _user_id AND source_url = _card_url
  ) THEN
    RETURN true;
  END IF;
  SELECT count(*) INTO pending_count
    FROM public.card_benefits_staging
    WHERE requested_by = _user_id AND status = 'pending';
  IF pending_count >= 10 THEN
    RETURN false;
  END IF;
  INSERT INTO public.card_benefits_staging(
    source_url, extracted_data, status, requested_by
  ) VALUES (
    _card_url,
    jsonb_build_object(
      'request_type', 'catalog_entry',
      'bank_name', _bank_name,
      'card_name', _card_name
    ),
    'pending',
    _user_id
  );
  RETURN true;
END;
$$;


--
-- Name: terminalize_calculator_review_rows(uuid, integer, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.terminalize_calculator_review_rows(_actor_id uuid, _limit integer DEFAULT 100, _confirmed boolean DEFAULT false) RETURNS integer
    LANGUAGE plpgsql
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
DECLARE
  calculator_review_terminal record;
  transitioned integer := 0;
BEGIN
  IF _actor_id IS NULL OR _limit NOT BETWEEN 1 AND 1000
     OR _confirmed IS DISTINCT FROM true THEN
    -- explicit_admin_confirmation: listing review rows is read-only; this
    -- classification-bound transition must be deliberately requested.
    RAISE EXCEPTION 'invalid_terminal_review_transition';
  END IF;
  PERFORM 1 FROM public.users AS actor
  WHERE actor.id = _actor_id AND actor.is_admin IS TRUE
  FOR KEY SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'administrator_required'; END IF;
  FOR calculator_review_terminal IN
    SELECT review.id, review.discovery_job_id
    FROM public.card_catalog_review_queue AS review
    JOIN public.card_discovery_jobs AS job ON job.id = review.discovery_job_id
    WHERE review.status = 'pending' AND job.discovery_source = 'issuer_crawl'
      AND (
        review.validation_warnings @>
          '["non_product_calculator_resource"]'::jsonb
        OR review.source_evidence->'source_observation'->>'classification'
          = 'non_product_calculator_resource'
      )
    ORDER BY review.discovery_job_id, review.id LIMIT _limit
  LOOP
    PERFORM pg_advisory_xact_lock(hashtextextended(
      'card_catalog_publication:job:' || calculator_review_terminal.discovery_job_id::text,
      0
    ));
    PERFORM 1 FROM public.card_discovery_jobs AS job
    WHERE job.id = calculator_review_terminal.discovery_job_id
      AND job.discovery_source = 'issuer_crawl'
      AND job.status NOT IN ('resolved', 'rejected')
    FOR UPDATE;
    IF NOT FOUND THEN CONTINUE; END IF;
    PERFORM 1 FROM public.card_catalog_review_queue AS review
    WHERE review.id = calculator_review_terminal.id AND review.status = 'pending'
    FOR UPDATE;
    IF NOT FOUND THEN CONTINUE; END IF;
    UPDATE public.card_catalog_review_queue SET status = 'rejected',
      reviewed_by = _actor_id, review_reason = 'non_product_calculator_resource',
      reviewed_at = statement_timestamp(), updated_at = statement_timestamp()
    WHERE id = calculator_review_terminal.id;
    UPDATE public.card_discovery_jobs SET status = 'rejected',
      failure_category = 'non_product_calculator_resource', next_retry_at = NULL,
      updated_at = statement_timestamp()
    WHERE id = calculator_review_terminal.discovery_job_id;
    INSERT INTO public.card_catalog_review_audit(review_item_id, actor_id, action, details)
    VALUES (
      calculator_review_terminal.id, _actor_id, 'reject',
      jsonb_build_object('reason', 'non_product_calculator_resource', 'retained_history', true)
    );
    transitioned := transitioned + 1;
  END LOOP;
  RETURN transitioned;
END;
$$;


--
-- Name: update_updated_at_column(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_updated_at_column() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;


--
-- Name: update_waitlist_operator(uuid, text, text, integer, timestamp with time zone, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_waitlist_operator(p_id uuid, p_status text, p_notes text DEFAULT NULL::text, p_operator_score integer DEFAULT NULL::integer, p_contacted_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_invited_at timestamp with time zone DEFAULT NULL::timestamp with time zone) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
  IF p_status NOT IN ('new','reviewing','qualified','not_a_fit','waitlisted','invited')
     OR (p_operator_score IS NOT NULL AND p_operator_score NOT BETWEEN 0 AND 100)
     OR char_length(COALESCE(p_notes,'')) > 2000 THEN
    RAISE EXCEPTION 'operator update is invalid' USING ERRCODE = '22023';
  END IF;
  UPDATE public.waitlist SET operator_status=p_status, operator_notes=nullif(btrim(p_notes),''),
    qualification_score=p_operator_score, contacted_at=p_contacted_at, invited_at=p_invited_at WHERE id=p_id;
  RETURN FOUND;
END; $$;


--
-- Name: validate_benefit_publication_envelope(jsonb, uuid, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.validate_benefit_publication_envelope(_envelope jsonb, _card_id uuid, _staged_proposal jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $_$
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
     OR ((benefit_value->'value_config') - 'offer_subject'::text - 'restrictions'::text - 'exclusions'::text)
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
$_$;


--
-- Name: validate_locked_benefit_proposals(jsonb, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.validate_locked_benefit_proposals(_proposals jsonb, _parser_version text) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO 'public', 'pg_temp'
    AS $_$
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
       OR EXISTS (
         SELECT 1
         FROM jsonb_each(CASE
           WHEN jsonb_typeof(proposal.value->'valueConfig') = 'object'
           THEN proposal.value->'valueConfig' ELSE '{}'::jsonb END
         ) AS config_item(key, value)
         WHERE config_item.key NOT IN ('restrictions', 'exclusions')
           AND jsonb_typeof(config_item.value) NOT IN (
             'string', 'number', 'boolean', 'null'
           )
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
  IF EXISTS (
    SELECT public.canonical_locked_benefit_condition(
      proposal.value, _parser_version
    ) AS canonical_target
    FROM jsonb_array_elements(_proposals) AS proposal(value)
    GROUP BY canonical_target
    HAVING count(*) > 1
  ) THEN RAISE EXCEPTION 'duplicate_staged_publication_target'; END IF;
  RETURN true;
END;
$_$;


--
-- Name: validate_locked_retirement_evidence(jsonb, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.validate_locked_retirement_evidence(_extracted_data jsonb, _live_benefit_id uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    SET search_path TO 'public', 'pg_temp'
    AS $_$
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
$_$;


--
-- Name: benefits; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.benefits (
    benefit_id uuid DEFAULT gen_random_uuid() NOT NULL,
    title text NOT NULL,
    description text,
    benefit_category text NOT NULL,
    benefit_type text,
    value_config jsonb,
    partners jsonb DEFAULT '[]'::jsonb,
    exclusions jsonb DEFAULT '{}'::jsonb,
    regions jsonb DEFAULT '[]'::jsonb,
    source_url text,
    valid_from date,
    valid_until date,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    dedupe_key text NOT NULL,
    CONSTRAINT benefits_exclusions_object_check CHECK (((exclusions IS NOT NULL) AND (jsonb_typeof(exclusions) = 'object'::text) AND COALESCE((jsonb_typeof((exclusions -> 'days'::text)) = 'array'::text), false) AND COALESCE((jsonb_typeof((exclusions -> 'mcc_codes'::text)) = 'array'::text), false) AND COALESCE((jsonb_typeof((exclusions -> 'merchants'::text)) = 'array'::text), false) AND COALESCE((jsonb_typeof((exclusions -> 'categories'::text)) = 'array'::text), false) AND COALESCE((jsonb_typeof((exclusions -> 'transaction_types'::text)) = 'array'::text), false) AND COALESCE((jsonb_typeof((exclusions -> 'additional'::text)) = 'object'::text), false) AND ((NOT ((exclusions -> 'additional'::text) ? 'source_terms'::text)) OR COALESCE((jsonb_typeof(((exclusions -> 'additional'::text) -> 'source_terms'::text)) = 'array'::text), false)))),
    CONSTRAINT benefits_partners_array_check CHECK (((partners IS NOT NULL) AND (jsonb_typeof(partners) = 'array'::text))),
    CONSTRAINT benefits_regions_array_check CHECK (((regions IS NOT NULL) AND (jsonb_typeof(regions) = 'array'::text))),
    CONSTRAINT benefits_value_config_object_check CHECK (((value_config IS NOT NULL) AND (jsonb_typeof(value_config) = 'object'::text)))
);


--
-- Name: TABLE benefits; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.benefits IS 'Master list of card benefits with flexible JSONB configuration';


--
-- Name: COLUMN benefits.dedupe_key; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.benefits.dedupe_key IS 'Canonical normalized category, type, and title key used for database-enforced benefit deduplication.';


--
-- Name: card_benefit_mapping; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.card_benefit_mapping (
    mapping_id uuid DEFAULT gen_random_uuid() NOT NULL,
    card_id uuid NOT NULL,
    benefit_id uuid NOT NULL,
    display_priority integer DEFAULT 1,
    is_primary boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now(),
    category_codes text[] DEFAULT '{}'::text[] NOT NULL,
    retired_at timestamp with time zone
);


--
-- Name: TABLE card_benefit_mapping; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.card_benefit_mapping IS 'Simple mapping between cards and benefits for display';


--
-- Name: COLUMN card_benefit_mapping.category_codes; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.card_benefit_mapping.category_codes IS 'Normalized searchable categories for this card-specific benefit mapping; one mapping may include several codes.';


--
-- Name: active_card_benefits; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.active_card_benefits WITH (security_invoker='true') AS
 SELECT mapping.mapping_id,
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
   FROM ((public.card_benefit_mapping mapping
     JOIN public.benefits benefit ON ((benefit.benefit_id = mapping.benefit_id)))
     CROSS JOIN LATERAL ( SELECT (timezone('UTC'::text, statement_timestamp()))::date AS utc_date) database_clock)
  WHERE (((mapping.retired_at IS NULL) OR (mapping.retired_at > now())) AND (benefit.is_active = true) AND ((benefit.valid_from IS NULL) OR (benefit.valid_from <= database_clock.utc_date)) AND ((benefit.valid_until IS NULL) OR (benefit.valid_until >= database_clock.utc_date)));


--
-- Name: benefit_categories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.benefit_categories (
    category_code text NOT NULL,
    name text NOT NULL,
    description text,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


--
-- Name: TABLE benefit_categories; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.benefit_categories IS 'Categories for organizing benefits (dining, travel, fuel, etc.)';


--
-- Name: benefit_platform_confirmations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.benefit_platform_confirmations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    benefit_id uuid NOT NULL,
    platform text NOT NULL,
    platform_key text GENERATED ALWAYS AS (lower(TRIM(BOTH FROM platform))) STORED,
    user_id uuid NOT NULL,
    confirmed_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT benefit_platform_confirmations_platform_check CHECK ((TRIM(BOTH FROM platform) <> ''::text))
);


--
-- Name: benefit_platform_confirmation_counts; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.benefit_platform_confirmation_counts WITH (security_invoker='false') AS
 SELECT benefit_id,
    platform_key,
    count(DISTINCT user_id) AS confirmation_count
   FROM public.benefit_platform_confirmations
  GROUP BY benefit_id, platform_key;


--
-- Name: card_benefits; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.card_benefits (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    benefit_id uuid,
    value numeric(12,2),
    configuration jsonb,
    spending_categories text[],
    monthly_cap numeric(12,2),
    annual_cap numeric(12,2),
    valid_from date,
    valid_to date,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


--
-- Name: TABLE card_benefits; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.card_benefits IS 'Historical generic benefit value/configuration rows. Card associations use card_benefit_mapping only.';


--
-- Name: card_catalog; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.card_catalog (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    card_name text NOT NULL,
    bank text,
    network text,
    card_type text,
    annual_fee numeric(10,2),
    joining_fee numeric(10,2),
    apr numeric(5,2),
    card_url text,
    is_discontinued boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


--
-- Name: TABLE card_catalog; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.card_catalog IS 'Master catalog of all credit cards available in the system';


--
-- Name: card_catalog_aliases; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.card_catalog_aliases (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    card_id uuid NOT NULL,
    alias text NOT NULL,
    normalized_alias text NOT NULL,
    evidence_type text NOT NULL,
    source_url text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT card_catalog_aliases_alias_check CHECK (((length(TRIM(BOTH FROM alias)) >= 2) AND (length(TRIM(BOTH FROM alias)) <= 160))),
    CONSTRAINT card_catalog_aliases_evidence_type_check CHECK ((evidence_type = ANY (ARRAY['subject'::text, 'filename'::text, 'pdf_header'::text, 'issuer_page'::text, 'admin'::text]))),
    CONSTRAINT card_catalog_aliases_normalized_alias_check CHECK (((length(normalized_alias) >= 2) AND (length(normalized_alias) <= 160)))
);


--
-- Name: card_catalog_provenance; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.card_catalog_provenance (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    card_id uuid NOT NULL,
    source_url text NOT NULL,
    source_type text NOT NULL,
    content_hash text NOT NULL,
    extracted_fields jsonb DEFAULT '{}'::jsonb NOT NULL,
    source_evidence jsonb DEFAULT '{}'::jsonb NOT NULL,
    validation_version text NOT NULL,
    confidence numeric(5,4) NOT NULL,
    approval_method text NOT NULL,
    retrieved_at timestamp with time zone NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    canonical_submitted_url text,
    canonical_final_url text,
    submitted_url_hash text,
    final_url_hash text,
    CONSTRAINT card_catalog_provenance_approval_method_check CHECK ((approval_method = ANY (ARRAY['automatic'::text, 'admin'::text]))),
    CONSTRAINT card_catalog_provenance_confidence_check CHECK (((confidence >= (0)::numeric) AND (confidence <= (1)::numeric))),
    CONSTRAINT card_catalog_provenance_extracted_fields_check CHECK ((jsonb_typeof(extracted_fields) = 'object'::text)),
    CONSTRAINT card_catalog_provenance_source_evidence_check CHECK ((jsonb_typeof(source_evidence) = 'object'::text)),
    CONSTRAINT card_catalog_provenance_source_type_check CHECK ((source_type = ANY (ARRAY['official_html'::text, 'official_pdf'::text, 'secondary'::text]))),
    CONSTRAINT card_catalog_provenance_source_url_check CHECK ((source_url ~ '^https://'::text))
);


--
-- Name: card_catalog_review_audit; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.card_catalog_review_audit (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    review_item_id uuid NOT NULL,
    actor_id uuid,
    action text NOT NULL,
    details jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT card_catalog_review_audit_action_check CHECK ((action = ANY (ARRAY['approve'::text, 'merge'::text, 'edit_approve'::text, 'retry'::text, 'reject'::text, 'mark_discontinued'::text, 'reactivate'::text, 'refresh'::text]))),
    CONSTRAINT card_catalog_review_audit_details_check CHECK ((jsonb_typeof(details) = 'object'::text))
);


--
-- Name: card_catalog_review_queue; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.card_catalog_review_queue (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    discovery_job_id uuid NOT NULL,
    proposed_fields jsonb DEFAULT '{}'::jsonb NOT NULL,
    source_evidence jsonb DEFAULT '{}'::jsonb NOT NULL,
    existing_candidates jsonb DEFAULT '[]'::jsonb NOT NULL,
    validation_warnings jsonb DEFAULT '[]'::jsonb NOT NULL,
    confidence numeric(5,4) DEFAULT 0 NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    reviewed_by uuid,
    review_reason text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    reviewed_at timestamp with time zone,
    CONSTRAINT card_catalog_review_queue_confidence_check CHECK (((confidence >= (0)::numeric) AND (confidence <= (1)::numeric))),
    CONSTRAINT card_catalog_review_queue_existing_candidates_check CHECK ((jsonb_typeof(existing_candidates) = 'array'::text)),
    CONSTRAINT card_catalog_review_queue_proposed_fields_check CHECK ((jsonb_typeof(proposed_fields) = 'object'::text)),
    CONSTRAINT card_catalog_review_queue_source_evidence_check CHECK ((jsonb_typeof(source_evidence) = 'object'::text)),
    CONSTRAINT card_catalog_review_queue_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'merged'::text, 'rejected'::text]))),
    CONSTRAINT card_catalog_review_queue_validation_warnings_check CHECK ((jsonb_typeof(validation_warnings) = 'array'::text))
);


--
-- Name: card_catalog_url_keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.card_catalog_url_keys (
    url_hash text NOT NULL,
    card_id uuid NOT NULL,
    canonical_url text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT card_catalog_url_keys_canonical_url_check CHECK ((canonical_url ~ '^https://'::text)),
    CONSTRAINT card_catalog_url_keys_url_hash_check CHECK ((url_hash ~ '^[0-9a-f]{64}$'::text))
);


--
-- Name: card_discovery_jobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.card_discovery_jobs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid,
    issuer text NOT NULL,
    proposed_product text,
    evidence jsonb DEFAULT '{}'::jsonb NOT NULL,
    dedupe_key text NOT NULL,
    status text DEFAULT 'queued'::text NOT NULL,
    attempt_count integer DEFAULT 0 NOT NULL,
    next_retry_at timestamp with time zone,
    failure_category text,
    resolved_card_id uuid,
    review_item_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    discovery_source text DEFAULT 'statement'::text NOT NULL,
    CONSTRAINT card_discovery_jobs_attempt_count_check CHECK ((attempt_count >= 0)),
    CONSTRAINT card_discovery_jobs_dedupe_key_check CHECK (((length(dedupe_key) >= 8) AND (length(dedupe_key) <= 256))),
    CONSTRAINT card_discovery_jobs_discovery_source_check CHECK ((discovery_source = ANY (ARRAY['statement'::text, 'issuer_crawl'::text]))),
    CONSTRAINT card_discovery_jobs_evidence_check CHECK ((jsonb_typeof(evidence) = 'object'::text)),
    CONSTRAINT card_discovery_jobs_issuer_check CHECK (((length(TRIM(BOTH FROM issuer)) >= 2) AND (length(TRIM(BOTH FROM issuer)) <= 120))),
    CONSTRAINT card_discovery_jobs_proposed_product_check CHECK (((proposed_product IS NULL) OR ((length(TRIM(BOTH FROM proposed_product)) >= 2) AND (length(TRIM(BOTH FROM proposed_product)) <= 160)))),
    CONSTRAINT card_discovery_jobs_status_check CHECK ((status = ANY (ARRAY['queued'::text, 'discovering'::text, 'resolved'::text, 'review_required'::text, 'rejected'::text, 'failed'::text])))
);


--
-- Name: emails; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.emails (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid,
    email_id text NOT NULL,
    subject text,
    sender text,
    received_date timestamp with time zone,
    has_attachments boolean DEFAULT false,
    processed boolean DEFAULT false,
    bank_detected text,
    statement_id text,
    metadata jsonb DEFAULT '{}'::jsonb,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: gemini_proxy_usage; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.gemini_proxy_usage (
    id bigint NOT NULL,
    user_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: gemini_proxy_usage_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.gemini_proxy_usage ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.gemini_proxy_usage_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: merchant_category_map; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_category_map (
    merchant_name_normalized text NOT NULL,
    category text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT merchant_category_map_category_check CHECK ((category = ANY (ARRAY['food'::text, 'fuel'::text, 'grocery'::text, 'entertainment'::text, 'travel'::text, 'shopping'::text, 'utilities'::text, 'insurance'::text, 'medical'::text, 'education'::text, 'investment'::text, 'transport'::text, 'rental'::text, 'subscription'::text, 'gift'::text, 'other'::text])))
);


--
-- Name: waitlist; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.waitlist (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    email text NOT NULL,
    name text,
    card_count text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    enrichment_token_hash text,
    primary_goal text,
    monthly_spend_band text,
    problem_detail text,
    top_cards text[],
    acquisition_source text,
    landing_variant text,
    utm_source text,
    utm_medium text,
    utm_campaign text,
    utm_term text,
    utm_content text,
    referrer_path text,
    privacy_consent_at timestamp with time zone,
    marketing_consent_at timestamp with time zone,
    marketing_consent_requested_at timestamp with time zone,
    enriched_at timestamp with time zone,
    operator_status text DEFAULT 'new'::text NOT NULL,
    qualification_score integer,
    operator_notes text,
    contacted_at timestamp with time zone,
    invited_at timestamp with time zone,
    CONSTRAINT waitlist_card_count_check CHECK (((card_count = ANY (ARRAY['1-2'::text, '3-6'::text, '7+'::text, 'legacy-6-plus'::text])) OR (card_count IS NULL))),
    CONSTRAINT waitlist_monthly_spend_band_check CHECK (((monthly_spend_band = ANY (ARRAY['under-25k'::text, '25k-50k'::text, '50k-1l'::text, '1l-plus'::text])) OR (monthly_spend_band IS NULL))),
    CONSTRAINT waitlist_operator_status_check CHECK ((operator_status = ANY (ARRAY['new'::text, 'reviewing'::text, 'qualified'::text, 'not_a_fit'::text, 'waitlisted'::text, 'invited'::text]))),
    CONSTRAINT waitlist_primary_goal_check CHECK (((primary_goal = ANY (ARRAY['maximize_rewards'::text, 'track_benefits'::text, 'simplify_card_choices'::text])) OR (primary_goal IS NULL))),
    CONSTRAINT waitlist_problem_detail_check CHECK (((char_length(problem_detail) <= 500) OR (problem_detail IS NULL))),
    CONSTRAINT waitlist_qualification_score_check CHECK ((((qualification_score >= 0) AND (qualification_score <= 100)) OR (qualification_score IS NULL))),
    CONSTRAINT waitlist_top_cards_check CHECK (((top_cards IS NULL) OR (cardinality(top_cards) <= 2)))
);


--
-- Name: operator_waitlist_ranked; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.operator_waitlist_ranked WITH (security_invoker='true') AS
 SELECT id,
    email,
    name,
    card_count,
    monthly_spend_band,
    primary_goal,
    problem_detail,
    top_cards,
    acquisition_source,
    landing_variant,
    utm_source,
    utm_medium,
    utm_campaign,
    utm_term,
    utm_content,
    referrer_path,
    privacy_consent_at,
    marketing_consent_at,
    marketing_consent_requested_at,
    created_at,
    enriched_at,
    operator_status,
    qualification_score,
    operator_notes,
    contacted_at,
    invited_at,
    (card_count = 'legacy-6-plus'::text) AS needs_requalification,
        CASE
            WHEN ((card_count IS NULL) OR (card_count = 'legacy-6-plus'::text) OR (monthly_spend_band IS NULL) OR (primary_goal IS NULL)) THEN 0
            ELSE (((
            CASE card_count
                WHEN '3-6'::text THEN 45
                WHEN '7+'::text THEN 30
                WHEN '1-2'::text THEN 15
                ELSE NULL::integer
            END +
            CASE monthly_spend_band
                WHEN '1l-plus'::text THEN 25
                WHEN '50k-1l'::text THEN 20
                WHEN '25k-50k'::text THEN 15
                WHEN 'under-25k'::text THEN 10
                ELSE NULL::integer
            END) +
            CASE primary_goal
                WHEN 'maximize_rewards'::text THEN 20
                WHEN 'track_benefits'::text THEN 15
                WHEN 'simplify_card_choices'::text THEN 10
                ELSE NULL::integer
            END) + COALESCE(qualification_score, 0))
        END AS rank_score
   FROM public.waitlist w
  ORDER BY
        CASE
            WHEN ((card_count IS NULL) OR (card_count = 'legacy-6-plus'::text) OR (monthly_spend_band IS NULL) OR (primary_goal IS NULL)) THEN 0
            ELSE (((
            CASE card_count
                WHEN '3-6'::text THEN 45
                WHEN '7+'::text THEN 30
                WHEN '1-2'::text THEN 15
                ELSE NULL::integer
            END +
            CASE monthly_spend_band
                WHEN '1l-plus'::text THEN 25
                WHEN '50k-1l'::text THEN 20
                WHEN '25k-50k'::text THEN 15
                WHEN 'under-25k'::text THEN 10
                ELSE NULL::integer
            END) +
            CASE primary_goal
                WHEN 'maximize_rewards'::text THEN 20
                WHEN 'track_benefits'::text THEN 15
                WHEN 'simplify_card_choices'::text THEN 10
                ELSE NULL::integer
            END) + COALESCE(qualification_score, 0))
        END DESC, created_at;


--
-- Name: transactions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.transactions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    user_card_id uuid NOT NULL,
    amount numeric(12,2) NOT NULL,
    currency text DEFAULT 'INR'::text,
    description text NOT NULL,
    merchant_name text,
    category text,
    transaction_type text,
    transaction_date timestamp with time zone NOT NULL,
    location text,
    reward_earned numeric(12,2),
    reward_type text,
    statement_id uuid,
    metadata jsonb DEFAULT '{}'::jsonb,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    mcc_code text,
    mcc_description text,
    mcc_source text,
    mcc_confidence numeric(4,3),
    mcc_verified_at timestamp with time zone,
    CONSTRAINT transactions_category_valid CHECK (((category IS NULL) OR (category = ANY (ARRAY['food'::text, 'fuel'::text, 'grocery'::text, 'entertainment'::text, 'travel'::text, 'shopping'::text, 'utilities'::text, 'insurance'::text, 'medical'::text, 'education'::text, 'investment'::text, 'transport'::text, 'rental'::text, 'subscription'::text, 'gift'::text, 'other'::text])))),
    CONSTRAINT transactions_mcc_confidence_check CHECK (((mcc_confidence IS NULL) OR ((mcc_confidence >= (0)::numeric) AND (mcc_confidence <= (1)::numeric)))),
    CONSTRAINT transactions_mcc_source_check CHECK (((mcc_source IS NULL) OR (mcc_source = ANY (ARRAY['bank_statement'::text, 'verified_provider'::text, 'merchant_registry'::text, 'inferred'::text, 'unknown'::text]))))
);


--
-- Name: TABLE transactions; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.transactions IS 'All card transactions for users';


--
-- Name: reward_balances; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.reward_balances WITH (security_invoker='true') AS
 SELECT encode(sha256(((((user_card_id)::text || ':'::text) || reward_type))::bytea), 'hex'::text) AS id,
    user_id,
    user_card_id,
    reward_type,
    sum(reward_earned) AS available_balance,
    sum(reward_earned) AS total_earned,
    (0)::numeric(12,2) AS total_redeemed,
    (0)::numeric(12,2) AS pending_balance,
    max(transaction_date) AS last_earned_at,
    max(updated_at) AS last_updated,
    min(created_at) AS created_at
   FROM public.transactions t
  WHERE ((reward_earned IS NOT NULL) AND (reward_earned > (0)::numeric) AND (reward_type IS NOT NULL))
  GROUP BY user_id, user_card_id, reward_type;


--
-- Name: statement_milestone_cache; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.statement_milestone_cache (
    id integer NOT NULL,
    user_id uuid NOT NULL,
    card_id uuid NOT NULL,
    user_card_id uuid,
    benefit_category character varying(50) NOT NULL,
    statement_start_date date NOT NULL,
    statement_end_date date NOT NULL,
    total_spending numeric(12,2) DEFAULT 0,
    milestone_progress numeric(5,2) DEFAULT 0,
    last_updated timestamp with time zone DEFAULT now()
);


--
-- Name: TABLE statement_milestone_cache; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.statement_milestone_cache IS 'Stores card spending by statement cycle for milestone tracking';


--
-- Name: statement_milestone_cache_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.statement_milestone_cache_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: statement_milestone_cache_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.statement_milestone_cache_id_seq OWNED BY public.statement_milestone_cache.id;


--
-- Name: statements; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.statements (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    card_id uuid NOT NULL,
    user_card_id uuid NOT NULL,
    statement_date date NOT NULL,
    due_date date NOT NULL,
    total_amount numeric(12,2) DEFAULT 0 NOT NULL,
    minimum_payment numeric(12,2) DEFAULT 0,
    closing_balance numeric(12,2) DEFAULT 0,
    available_credit numeric(12,2) DEFAULT 0,
    interest_charged numeric(12,2) DEFAULT 0,
    fees_charged numeric(12,2) DEFAULT 0,
    payment_status text DEFAULT 'pending'::text,
    rewards_earned numeric(12,2) DEFAULT 0,
    file_path text,
    file_name text,
    processed boolean DEFAULT false,
    transaction_count integer,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    paid_amount numeric(12,2) DEFAULT 0 NOT NULL,
    paid_at timestamp with time zone,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    CONSTRAINT statements_paid_amount_bounds_check CHECK (((paid_amount >= (0)::numeric) AND (paid_amount <= total_amount)))
);


--
-- Name: TABLE statements; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.statements IS 'Parsed credit card statements';


--
-- Name: user_cards; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_cards (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    catalog_card_id uuid NOT NULL,
    last_four_digits text,
    card_holder_name text,
    credit_limit numeric(12,2),
    statement_date integer,
    due_date integer,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT user_cards_due_date_check CHECK (((due_date >= 1) AND (due_date <= 31))),
    CONSTRAINT user_cards_statement_date_check CHECK (((statement_date >= 1) AND (statement_date <= 31)))
);


--
-- Name: TABLE user_cards; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.user_cards IS 'Active schema stores catalog identity and last four digits only; legacy PAN/expiry columns were logically removed.';


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    email text NOT NULL,
    full_name text,
    avatar_url text,
    phone text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    preferences jsonb DEFAULT '{}'::jsonb,
    is_active boolean DEFAULT true,
    given_name text,
    family_name text,
    date_of_birth date,
    profile_data jsonb DEFAULT '{}'::jsonb,
    is_admin boolean DEFAULT false NOT NULL
);


--
-- Name: COLUMN users.is_admin; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.users.is_admin IS 'Server-governed access flag for the CardCompass operator console.';


--
-- Name: waitlist_public_attempts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.waitlist_public_attempts (
    email_hash text NOT NULL,
    window_started timestamp with time zone NOT NULL,
    attempt_count integer DEFAULT 1 NOT NULL
);


--
-- Name: statement_milestone_cache id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.statement_milestone_cache ALTER COLUMN id SET DEFAULT nextval('public.statement_milestone_cache_id_seq'::regclass);


--
-- Name: benefit_categories benefit_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.benefit_categories
    ADD CONSTRAINT benefit_categories_pkey PRIMARY KEY (category_code);


--
-- Name: benefit_platform_confirmations benefit_platform_confirmation_user_id_benefit_id_platform_k_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.benefit_platform_confirmations
    ADD CONSTRAINT benefit_platform_confirmation_user_id_benefit_id_platform_k_key UNIQUE (user_id, benefit_id, platform_key);


--
-- Name: benefit_platform_confirmations benefit_platform_confirmations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.benefit_platform_confirmations
    ADD CONSTRAINT benefit_platform_confirmations_pkey PRIMARY KEY (id);


--
-- Name: benefits benefits_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.benefits
    ADD CONSTRAINT benefits_pkey PRIMARY KEY (benefit_id);


--
-- Name: card_benefit_mapping card_benefit_mapping_card_id_benefit_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.card_benefit_mapping
    ADD CONSTRAINT card_benefit_mapping_card_id_benefit_id_key UNIQUE (card_id, benefit_id);


--
-- Name: card_benefit_mapping card_benefit_mapping_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.card_benefit_mapping
    ADD CONSTRAINT card_benefit_mapping_pkey PRIMARY KEY (mapping_id);


--
-- Name: card_benefits card_benefits_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.card_benefits
    ADD CONSTRAINT card_benefits_pkey PRIMARY KEY (id);


--
-- Name: card_benefits_staging card_benefits_staging_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.card_benefits_staging
    ADD CONSTRAINT card_benefits_staging_pkey PRIMARY KEY (id);


--
-- Name: card_catalog_aliases card_catalog_aliases_card_id_normalized_alias_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.card_catalog_aliases
    ADD CONSTRAINT card_catalog_aliases_card_id_normalized_alias_key UNIQUE (card_id, normalized_alias);


--
-- Name: card_catalog_aliases card_catalog_aliases_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.card_catalog_aliases
    ADD CONSTRAINT card_catalog_aliases_pkey PRIMARY KEY (id);


--
-- Name: card_catalog_enrichment_jobs card_catalog_enrichment_jobs_job_key_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.card_catalog_enrichment_jobs
    ADD CONSTRAINT card_catalog_enrichment_jobs_job_key_key UNIQUE (job_key);


--
-- Name: card_catalog_enrichment_jobs card_catalog_enrichment_jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.card_catalog_enrichment_jobs
    ADD CONSTRAINT card_catalog_enrichment_jobs_pkey PRIMARY KEY (id);


--
-- Name: card_catalog card_catalog_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.card_catalog
    ADD CONSTRAINT card_catalog_pkey PRIMARY KEY (id);


--
-- Name: card_catalog_provenance card_catalog_provenance_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.card_catalog_provenance
    ADD CONSTRAINT card_catalog_provenance_pkey PRIMARY KEY (id);


--
-- Name: card_catalog_review_audit card_catalog_review_audit_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.card_catalog_review_audit
    ADD CONSTRAINT card_catalog_review_audit_pkey PRIMARY KEY (id);


--
-- Name: card_catalog_review_queue card_catalog_review_queue_discovery_job_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.card_catalog_review_queue
    ADD CONSTRAINT card_catalog_review_queue_discovery_job_id_key UNIQUE (discovery_job_id);


--
-- Name: card_catalog_review_queue card_catalog_review_queue_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.card_catalog_review_queue
    ADD CONSTRAINT card_catalog_review_queue_pkey PRIMARY KEY (id);


--
-- Name: card_catalog_url_keys card_catalog_url_keys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.card_catalog_url_keys
    ADD CONSTRAINT card_catalog_url_keys_pkey PRIMARY KEY (url_hash);


--
-- Name: card_discovery_jobs card_discovery_jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.card_discovery_jobs
    ADD CONSTRAINT card_discovery_jobs_pkey PRIMARY KEY (id);


--
-- Name: emails emails_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.emails
    ADD CONSTRAINT emails_pkey PRIMARY KEY (id);


--
-- Name: gemini_proxy_usage gemini_proxy_usage_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gemini_proxy_usage
    ADD CONSTRAINT gemini_proxy_usage_pkey PRIMARY KEY (id);


--
-- Name: merchant_category_map merchant_category_map_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_category_map
    ADD CONSTRAINT merchant_category_map_pkey PRIMARY KEY (merchant_name_normalized);


--
-- Name: statement_milestone_cache statement_milestone_cache_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.statement_milestone_cache
    ADD CONSTRAINT statement_milestone_cache_pkey PRIMARY KEY (id);


--
-- Name: statement_milestone_cache statement_milestone_cache_user_id_card_id_benefit_category__key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.statement_milestone_cache
    ADD CONSTRAINT statement_milestone_cache_user_id_card_id_benefit_category__key UNIQUE (user_id, card_id, benefit_category, statement_start_date, statement_end_date);


--
-- Name: statements statements_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.statements
    ADD CONSTRAINT statements_pkey PRIMARY KEY (id);


--
-- Name: statements statements_user_card_statement_date_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.statements
    ADD CONSTRAINT statements_user_card_statement_date_key UNIQUE (user_card_id, statement_date);


--
-- Name: transactions transactions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transactions
    ADD CONSTRAINT transactions_pkey PRIMARY KEY (id);


--
-- Name: user_cards user_cards_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_cards
    ADD CONSTRAINT user_cards_pkey PRIMARY KEY (id);


--
-- Name: user_cards user_cards_user_id_catalog_card_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_cards
    ADD CONSTRAINT user_cards_user_id_catalog_card_id_key UNIQUE (user_id, catalog_card_id);


--
-- Name: users users_email_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key UNIQUE (email);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: waitlist waitlist_email_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.waitlist
    ADD CONSTRAINT waitlist_email_key UNIQUE (email);


--
-- Name: waitlist waitlist_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.waitlist
    ADD CONSTRAINT waitlist_pkey PRIMARY KEY (id);


--
-- Name: waitlist_public_attempts waitlist_public_attempts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.waitlist_public_attempts
    ADD CONSTRAINT waitlist_public_attempts_pkey PRIMARY KEY (email_hash, window_started);


--
-- Name: card_benefits_staging_official_identity; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX card_benefits_staging_official_identity ON public.card_benefits_staging USING btree (card_id, source_url_hash, parser_version, content_hash) WHERE (request_type = 'official_benefit_enrichment'::text);


--
-- Name: idx_benefit_categories_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_benefit_categories_active ON public.benefit_categories USING btree (is_active);


--
-- Name: idx_benefit_platform_confirmations_lookup; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_benefit_platform_confirmations_lookup ON public.benefit_platform_confirmations USING btree (benefit_id, platform_key);


--
-- Name: idx_benefits_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_benefits_active ON public.benefits USING btree (is_active);


--
-- Name: idx_benefits_category; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_benefits_category ON public.benefits USING btree (benefit_category);


--
-- Name: idx_benefits_dedupe_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_benefits_dedupe_key ON public.benefits USING btree (dedupe_key);


--
-- Name: idx_card_benefit_benefit; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_card_benefit_benefit ON public.card_benefit_mapping USING btree (benefit_id);


--
-- Name: idx_card_benefit_card; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_card_benefit_card ON public.card_benefit_mapping USING btree (card_id);


--
-- Name: idx_card_benefit_mapping_active_card_priority; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_card_benefit_mapping_active_card_priority ON public.card_benefit_mapping USING btree (card_id, display_priority) WHERE (retired_at IS NULL);


--
-- Name: idx_card_benefit_mapping_category_codes; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_card_benefit_mapping_category_codes ON public.card_benefit_mapping USING gin (category_codes);


--
-- Name: idx_card_benefit_primary; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_card_benefit_primary ON public.card_benefit_mapping USING btree (card_id, is_primary);


--
-- Name: idx_card_benefits_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_card_benefits_active ON public.card_benefits USING btree (is_active);


--
-- Name: idx_card_benefits_benefit; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_card_benefits_benefit ON public.card_benefits USING btree (benefit_id);


--
-- Name: idx_card_benefits_staging_card_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_card_benefits_staging_card_created ON public.card_benefits_staging USING btree (card_id, created_at DESC);


--
-- Name: idx_card_benefits_staging_catalog_entry_pending; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_card_benefits_staging_catalog_entry_pending ON public.card_benefits_staging USING btree (status, ((extracted_data ->> 'request_type'::text))) WHERE ((card_id IS NULL) AND (status = 'pending'::text));


--
-- Name: idx_card_benefits_staging_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_card_benefits_staging_status ON public.card_benefits_staging USING btree (status);


--
-- Name: idx_card_catalog_aliases_normalized; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_card_catalog_aliases_normalized ON public.card_catalog_aliases USING btree (normalized_alias);


--
-- Name: idx_card_catalog_bank; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_card_catalog_bank ON public.card_catalog USING btree (bank);


--
-- Name: idx_card_catalog_discontinued; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_card_catalog_discontinued ON public.card_catalog USING btree (is_discontinued);


--
-- Name: idx_card_catalog_enrichment_jobs_due_v6; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_card_catalog_enrichment_jobs_due_v6 ON public.card_catalog_enrichment_jobs USING btree (parser_version, run_mode, next_run_at, issuer) WHERE ((status = ANY (ARRAY['staged'::text, 'completed'::text, 'review_required'::text, 'quarantined'::text])) AND (next_run_at IS NOT NULL));


--
-- Name: idx_card_catalog_enrichment_jobs_pending; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_card_catalog_enrichment_jobs_pending ON public.card_catalog_enrichment_jobs USING btree (status, next_retry_at) WHERE (status = ANY (ARRAY['queued'::text, 'failed'::text]));


--
-- Name: idx_card_catalog_enrichment_jobs_recurrence_v6; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_card_catalog_enrichment_jobs_recurrence_v6 ON public.card_catalog_enrichment_jobs USING btree (parser_version, run_mode, status, next_run_at, issuer, id) WHERE ((parser_version = 'benefits-v6'::text) AND (status = ANY (ARRAY['completed'::text, 'staged'::text, 'quarantined'::text, 'review_required'::text, 'failed'::text])));


--
-- Name: idx_card_catalog_enrichment_jobs_unique_v6_card_parser; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_card_catalog_enrichment_jobs_unique_v6_card_parser ON public.card_catalog_enrichment_jobs USING btree (card_id, lower(TRIM(BOTH FROM parser_version))) WHERE (lower(TRIM(BOTH FROM parser_version)) = 'benefits-v6'::text);


--
-- Name: idx_card_catalog_network; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_card_catalog_network ON public.card_catalog USING btree (network);


--
-- Name: idx_card_catalog_provenance_card_source_content; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_card_catalog_provenance_card_source_content ON public.card_catalog_provenance USING btree (card_id, source_url, content_hash);


--
-- Name: idx_card_catalog_provenance_final_url_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_card_catalog_provenance_final_url_hash ON public.card_catalog_provenance USING btree (final_url_hash) WHERE (final_url_hash IS NOT NULL);


--
-- Name: idx_card_catalog_provenance_submitted_url_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_card_catalog_provenance_submitted_url_hash ON public.card_catalog_provenance USING btree (submitted_url_hash) WHERE (submitted_url_hash IS NOT NULL);


--
-- Name: idx_card_catalog_review_queue_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_card_catalog_review_queue_status ON public.card_catalog_review_queue USING btree (status, created_at);


--
-- Name: idx_card_catalog_url_keys_card; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_card_catalog_url_keys_card ON public.card_catalog_url_keys USING btree (card_id);


--
-- Name: idx_card_discovery_jobs_retry; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_card_discovery_jobs_retry ON public.card_discovery_jobs USING btree (status, next_retry_at) WHERE (status = ANY (ARRAY['queued'::text, 'failed'::text]));


--
-- Name: idx_card_discovery_jobs_service_dedupe_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_card_discovery_jobs_service_dedupe_key ON public.card_discovery_jobs USING btree (discovery_source, dedupe_key) WHERE ((user_id IS NULL) AND (discovery_source = 'issuer_crawl'::text));


--
-- Name: idx_card_discovery_jobs_user_dedupe_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_card_discovery_jobs_user_dedupe_key ON public.card_discovery_jobs USING btree (user_id, dedupe_key) WHERE (user_id IS NOT NULL);


--
-- Name: idx_card_discovery_jobs_user_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_card_discovery_jobs_user_status ON public.card_discovery_jobs USING btree (user_id, status, updated_at DESC);


--
-- Name: idx_card_staging_requester_url; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_card_staging_requester_url ON public.card_benefits_staging USING btree (requested_by, source_url) WHERE (requested_by IS NOT NULL);


--
-- Name: idx_emails_unprocessed; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_emails_unprocessed ON public.emails USING btree (user_id, processed) WHERE (processed = false);


--
-- Name: idx_emails_user_email_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_emails_user_email_id ON public.emails USING btree (user_id, email_id);


--
-- Name: idx_emails_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_emails_user_id ON public.emails USING btree (user_id);


--
-- Name: idx_emails_user_received_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_emails_user_received_date ON public.emails USING btree (user_id, received_date DESC);


--
-- Name: idx_gemini_proxy_usage_user_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_gemini_proxy_usage_user_created ON public.gemini_proxy_usage USING btree (user_id, created_at DESC);


--
-- Name: idx_statement_milestone_cache_lookup; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_statement_milestone_cache_lookup ON public.statement_milestone_cache USING btree (user_id, card_id, benefit_category, statement_start_date, statement_end_date);


--
-- Name: idx_statement_milestone_user_card; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_statement_milestone_user_card ON public.statement_milestone_cache USING btree (user_card_id);


--
-- Name: idx_statements_card; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_statements_card ON public.statements USING btree (card_id);


--
-- Name: idx_statements_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_statements_date ON public.statements USING btree (statement_date);


--
-- Name: idx_statements_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_statements_user ON public.statements USING btree (user_id);


--
-- Name: idx_transactions_card; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_transactions_card ON public.transactions USING btree (user_card_id);


--
-- Name: idx_transactions_card_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_transactions_card_date ON public.transactions USING btree (user_card_id, transaction_date);


--
-- Name: idx_transactions_category; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_transactions_category ON public.transactions USING btree (category);


--
-- Name: idx_transactions_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_transactions_date ON public.transactions USING btree (transaction_date);


--
-- Name: idx_transactions_dedup; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_transactions_dedup ON public.transactions USING btree (user_id, user_card_id, transaction_date, description, amount);


--
-- Name: idx_transactions_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_transactions_user ON public.transactions USING btree (user_id);


--
-- Name: idx_transactions_user_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_transactions_user_date ON public.transactions USING btree (user_id, transaction_date);


--
-- Name: idx_user_cards_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_user_cards_active ON public.user_cards USING btree (user_id, is_active);


--
-- Name: idx_user_cards_catalog_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_user_cards_catalog_id ON public.user_cards USING btree (catalog_card_id);


--
-- Name: idx_user_cards_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_user_cards_user_id ON public.user_cards USING btree (user_id);


--
-- Name: idx_users_date_of_birth; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_users_date_of_birth ON public.users USING btree (date_of_birth);


--
-- Name: idx_users_profile_data_gin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_users_profile_data_gin ON public.users USING gin (profile_data);


--
-- Name: statements_user_card_open_due_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX statements_user_card_open_due_idx ON public.statements USING btree (user_card_id, payment_status, due_date);


--
-- Name: waitlist_email_lower_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX waitlist_email_lower_key ON public.waitlist USING btree (lower(email));


--
-- Name: waitlist_enrichment_token_hash_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX waitlist_enrichment_token_hash_key ON public.waitlist USING btree (enrichment_token_hash) WHERE (enrichment_token_hash IS NOT NULL);


--
-- Name: card_benefits_staging capture_card_enrichment_pilot_publication_snapshot; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER capture_card_enrichment_pilot_publication_snapshot BEFORE UPDATE OF status ON public.card_benefits_staging FOR EACH ROW EXECUTE FUNCTION public.capture_card_enrichment_pilot_publication_snapshot();


--
-- Name: card_catalog_enrichment_jobs enforce_card_benefit_enrichment_identity; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER enforce_card_benefit_enrichment_identity BEFORE INSERT OR UPDATE OF card_id, parser_version ON public.card_catalog_enrichment_jobs FOR EACH ROW EXECUTE FUNCTION public.enforce_card_benefit_enrichment_identity();


--
-- Name: benefits normalize_benefit_exclusions_shape; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER normalize_benefit_exclusions_shape BEFORE INSERT OR UPDATE OF exclusions ON public.benefits FOR EACH ROW EXECUTE FUNCTION public.normalize_benefit_exclusions_shape();


--
-- Name: statements protect_reconciled_statement_fields; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER protect_reconciled_statement_fields BEFORE UPDATE ON public.statements FOR EACH ROW EXECUTE FUNCTION public.protect_reconciled_statement_fields();


--
-- Name: card_catalog_enrichment_jobs schedule_terminal_card_enrichment_observation; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER schedule_terminal_card_enrichment_observation BEFORE INSERT OR UPDATE OF status, next_retry_at, result_summary, failure_category, parser_version, run_mode, staging_id, card_id ON public.card_catalog_enrichment_jobs FOR EACH ROW EXECUTE FUNCTION public.schedule_terminal_card_enrichment_observation();


--
-- Name: card_catalog_enrichment_jobs set_card_catalog_enrichment_job_key; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_card_catalog_enrichment_job_key BEFORE INSERT OR UPDATE OF card_id, final_url_hash, parser_version, job_key ON public.card_catalog_enrichment_jobs FOR EACH ROW EXECUTE FUNCTION public.set_card_catalog_enrichment_job_key();


--
-- Name: benefits update_benefits_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_benefits_updated_at BEFORE UPDATE ON public.benefits FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: card_catalog update_card_catalog_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_card_catalog_updated_at BEFORE UPDATE ON public.card_catalog FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: transactions update_transactions_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_transactions_updated_at BEFORE UPDATE ON public.transactions FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: users update_users_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON public.users FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: benefit_platform_confirmations benefit_platform_confirmations_benefit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.benefit_platform_confirmations
    ADD CONSTRAINT benefit_platform_confirmations_benefit_id_fkey FOREIGN KEY (benefit_id) REFERENCES public.benefits(benefit_id);


--
-- Name: benefit_platform_confirmations benefit_platform_confirmations_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.benefit_platform_confirmations
    ADD CONSTRAINT benefit_platform_confirmations_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id);


--
-- Name: card_benefit_mapping card_benefit_mapping_benefit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.card_benefit_mapping
    ADD CONSTRAINT card_benefit_mapping_benefit_id_fkey FOREIGN KEY (benefit_id) REFERENCES public.benefits(benefit_id) ON DELETE CASCADE;


--
-- Name: card_benefit_mapping card_benefit_mapping_card_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.card_benefit_mapping
    ADD CONSTRAINT card_benefit_mapping_card_id_fkey FOREIGN KEY (card_id) REFERENCES public.card_catalog(id) ON DELETE CASCADE;


--
-- Name: card_benefits card_benefits_benefit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.card_benefits
    ADD CONSTRAINT card_benefits_benefit_id_fkey FOREIGN KEY (benefit_id) REFERENCES public.benefits(benefit_id) ON DELETE SET NULL;


--
-- Name: card_benefits_staging card_benefits_staging_card_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.card_benefits_staging
    ADD CONSTRAINT card_benefits_staging_card_id_fkey FOREIGN KEY (card_id) REFERENCES public.card_catalog(id) ON DELETE CASCADE;


--
-- Name: card_benefits_staging card_benefits_staging_requested_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.card_benefits_staging
    ADD CONSTRAINT card_benefits_staging_requested_by_fkey FOREIGN KEY (requested_by) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: card_benefits_staging card_benefits_staging_reviewed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.card_benefits_staging
    ADD CONSTRAINT card_benefits_staging_reviewed_by_fkey FOREIGN KEY (reviewed_by) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: card_catalog_aliases card_catalog_aliases_card_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.card_catalog_aliases
    ADD CONSTRAINT card_catalog_aliases_card_id_fkey FOREIGN KEY (card_id) REFERENCES public.card_catalog(id) ON DELETE RESTRICT;


--
-- Name: card_catalog_enrichment_jobs card_catalog_enrichment_jobs_card_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.card_catalog_enrichment_jobs
    ADD CONSTRAINT card_catalog_enrichment_jobs_card_id_fkey FOREIGN KEY (card_id) REFERENCES public.card_catalog(id) ON DELETE RESTRICT;


--
-- Name: card_catalog_enrichment_jobs card_catalog_enrichment_jobs_discovery_job_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.card_catalog_enrichment_jobs
    ADD CONSTRAINT card_catalog_enrichment_jobs_discovery_job_id_fkey FOREIGN KEY (discovery_job_id) REFERENCES public.card_discovery_jobs(id) ON DELETE SET NULL;


--
-- Name: card_catalog_enrichment_jobs card_catalog_enrichment_jobs_staging_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.card_catalog_enrichment_jobs
    ADD CONSTRAINT card_catalog_enrichment_jobs_staging_id_fkey FOREIGN KEY (staging_id) REFERENCES public.card_benefits_staging(id);


--
-- Name: card_catalog_provenance card_catalog_provenance_card_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.card_catalog_provenance
    ADD CONSTRAINT card_catalog_provenance_card_id_fkey FOREIGN KEY (card_id) REFERENCES public.card_catalog(id) ON DELETE RESTRICT;


--
-- Name: card_catalog_review_audit card_catalog_review_audit_actor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.card_catalog_review_audit
    ADD CONSTRAINT card_catalog_review_audit_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: card_catalog_review_audit card_catalog_review_audit_review_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.card_catalog_review_audit
    ADD CONSTRAINT card_catalog_review_audit_review_item_id_fkey FOREIGN KEY (review_item_id) REFERENCES public.card_catalog_review_queue(id) ON DELETE RESTRICT;


--
-- Name: card_catalog_review_queue card_catalog_review_queue_discovery_job_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.card_catalog_review_queue
    ADD CONSTRAINT card_catalog_review_queue_discovery_job_id_fkey FOREIGN KEY (discovery_job_id) REFERENCES public.card_discovery_jobs(id) ON DELETE RESTRICT;


--
-- Name: card_catalog_review_queue card_catalog_review_queue_reviewed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.card_catalog_review_queue
    ADD CONSTRAINT card_catalog_review_queue_reviewed_by_fkey FOREIGN KEY (reviewed_by) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: card_catalog_url_keys card_catalog_url_keys_card_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.card_catalog_url_keys
    ADD CONSTRAINT card_catalog_url_keys_card_id_fkey FOREIGN KEY (card_id) REFERENCES public.card_catalog(id) ON DELETE RESTRICT;


--
-- Name: card_discovery_jobs card_discovery_jobs_resolved_card_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.card_discovery_jobs
    ADD CONSTRAINT card_discovery_jobs_resolved_card_id_fkey FOREIGN KEY (resolved_card_id) REFERENCES public.card_catalog(id) ON DELETE SET NULL;


--
-- Name: card_discovery_jobs card_discovery_jobs_review_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.card_discovery_jobs
    ADD CONSTRAINT card_discovery_jobs_review_item_id_fkey FOREIGN KEY (review_item_id) REFERENCES public.card_catalog_review_queue(id) ON DELETE SET NULL;


--
-- Name: card_discovery_jobs card_discovery_jobs_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.card_discovery_jobs
    ADD CONSTRAINT card_discovery_jobs_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: emails emails_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.emails
    ADD CONSTRAINT emails_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: gemini_proxy_usage gemini_proxy_usage_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gemini_proxy_usage
    ADD CONSTRAINT gemini_proxy_usage_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: statement_milestone_cache statement_milestone_cache_card_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.statement_milestone_cache
    ADD CONSTRAINT statement_milestone_cache_card_id_fkey FOREIGN KEY (card_id) REFERENCES public.card_catalog(id) ON DELETE CASCADE;


--
-- Name: statement_milestone_cache statement_milestone_cache_user_card_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.statement_milestone_cache
    ADD CONSTRAINT statement_milestone_cache_user_card_id_fkey FOREIGN KEY (user_card_id) REFERENCES public.user_cards(id) ON DELETE CASCADE;


--
-- Name: statement_milestone_cache statement_milestone_cache_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.statement_milestone_cache
    ADD CONSTRAINT statement_milestone_cache_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: statements statements_card_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.statements
    ADD CONSTRAINT statements_card_id_fkey FOREIGN KEY (card_id) REFERENCES public.card_catalog(id) ON DELETE CASCADE;


--
-- Name: statements statements_user_card_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.statements
    ADD CONSTRAINT statements_user_card_id_fkey FOREIGN KEY (user_card_id) REFERENCES public.user_cards(id) ON DELETE CASCADE;


--
-- Name: statements statements_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.statements
    ADD CONSTRAINT statements_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: transactions transactions_statement_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transactions
    ADD CONSTRAINT transactions_statement_id_fkey FOREIGN KEY (statement_id) REFERENCES public.statements(id) ON DELETE SET NULL;


--
-- Name: transactions transactions_user_card_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transactions
    ADD CONSTRAINT transactions_user_card_id_fkey FOREIGN KEY (user_card_id) REFERENCES public.user_cards(id) ON DELETE CASCADE;


--
-- Name: transactions transactions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transactions
    ADD CONSTRAINT transactions_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: user_cards user_cards_catalog_card_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_cards
    ADD CONSTRAINT user_cards_catalog_card_id_fkey FOREIGN KEY (catalog_card_id) REFERENCES public.card_catalog(id) ON DELETE CASCADE;


--
-- Name: user_cards user_cards_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_cards
    ADD CONSTRAINT user_cards_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: card_catalog_aliases Authenticated users can read catalog aliases; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Authenticated users can read catalog aliases" ON public.card_catalog_aliases FOR SELECT TO authenticated USING ((( SELECT auth.uid() AS uid) IS NOT NULL));


--
-- Name: benefit_platform_confirmations authenticated insert own confirmation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "authenticated insert own confirmation" ON public.benefit_platform_confirmations FOR INSERT TO authenticated WITH CHECK ((auth.uid() = user_id));


--
-- Name: benefit_categories authenticated_read_benefit_categories; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_read_benefit_categories ON public.benefit_categories FOR SELECT TO authenticated USING (true);


--
-- Name: benefits authenticated_read_benefits; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_read_benefits ON public.benefits FOR SELECT TO authenticated USING (true);


--
-- Name: card_benefit_mapping authenticated_read_card_benefit_mapping; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_read_card_benefit_mapping ON public.card_benefit_mapping FOR SELECT TO authenticated USING (true);


--
-- Name: card_catalog authenticated_read_card_catalog; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY authenticated_read_card_catalog ON public.card_catalog FOR SELECT TO authenticated USING (true);


--
-- Name: benefit_categories; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.benefit_categories ENABLE ROW LEVEL SECURITY;

--
-- Name: benefit_platform_confirmations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.benefit_platform_confirmations ENABLE ROW LEVEL SECURITY;

--
-- Name: benefits; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.benefits ENABLE ROW LEVEL SECURITY;

--
-- Name: card_benefit_mapping; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.card_benefit_mapping ENABLE ROW LEVEL SECURITY;

--
-- Name: card_benefits_staging; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.card_benefits_staging ENABLE ROW LEVEL SECURITY;

--
-- Name: card_catalog; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.card_catalog ENABLE ROW LEVEL SECURITY;

--
-- Name: card_catalog_aliases; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.card_catalog_aliases ENABLE ROW LEVEL SECURITY;

--
-- Name: card_catalog_enrichment_jobs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.card_catalog_enrichment_jobs ENABLE ROW LEVEL SECURITY;

--
-- Name: card_catalog_provenance; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.card_catalog_provenance ENABLE ROW LEVEL SECURITY;

--
-- Name: card_catalog_review_audit; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.card_catalog_review_audit ENABLE ROW LEVEL SECURITY;

--
-- Name: card_catalog_review_queue; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.card_catalog_review_queue ENABLE ROW LEVEL SECURITY;

--
-- Name: card_catalog_url_keys; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.card_catalog_url_keys ENABLE ROW LEVEL SECURITY;

--
-- Name: card_discovery_jobs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.card_discovery_jobs ENABLE ROW LEVEL SECURITY;

--
-- Name: emails; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.emails ENABLE ROW LEVEL SECURITY;

--
-- Name: emails emails_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY emails_policy ON public.emails TO authenticated USING ((( SELECT auth.uid() AS uid) = user_id)) WITH CHECK ((( SELECT auth.uid() AS uid) = user_id));


--
-- Name: gemini_proxy_usage; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.gemini_proxy_usage ENABLE ROW LEVEL SECURITY;

--
-- Name: merchant_category_map; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.merchant_category_map ENABLE ROW LEVEL SECURITY;

--
-- Name: merchant_category_map merchant_category_map_select_authenticated; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY merchant_category_map_select_authenticated ON public.merchant_category_map FOR SELECT TO authenticated USING (true);


--
-- Name: statement_milestone_cache; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.statement_milestone_cache ENABLE ROW LEVEL SECURITY;

--
-- Name: statement_milestone_cache statement_milestone_user_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY statement_milestone_user_policy ON public.statement_milestone_cache TO authenticated USING ((auth.uid() = user_id));


--
-- Name: statements; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.statements ENABLE ROW LEVEL SECURITY;

--
-- Name: statements statements_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY statements_policy ON public.statements TO authenticated USING ((auth.uid() = user_id));


--
-- Name: transactions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.transactions ENABLE ROW LEVEL SECURITY;

--
-- Name: transactions transactions_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY transactions_policy ON public.transactions TO authenticated USING ((auth.uid() = user_id));


--
-- Name: user_cards; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.user_cards ENABLE ROW LEVEL SECURITY;

--
-- Name: user_cards user_cards_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY user_cards_policy ON public.user_cards TO authenticated USING ((auth.uid() = user_id));


--
-- Name: users; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

--
-- Name: users users_own_data_policy; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY users_own_data_policy ON public.users TO authenticated USING ((auth.uid() = id)) WITH CHECK ((auth.uid() = id));


--
-- Name: waitlist; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.waitlist ENABLE ROW LEVEL SECURITY;

--
-- Name: waitlist_public_attempts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.waitlist_public_attempts ENABLE ROW LEVEL SECURITY;

--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: -
--

GRANT USAGE ON SCHEMA public TO postgres;
GRANT USAGE ON SCHEMA public TO anon;
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT USAGE ON SCHEMA public TO service_role;


--
-- Name: FUNCTION add_transaction(_user_id uuid, _user_card_id uuid, _amount numeric, _description text, _transaction_date timestamp with time zone, _category text, _type text, _currency text, _merchant_name text, _location text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.add_transaction(_user_id uuid, _user_card_id uuid, _amount numeric, _description text, _transaction_date timestamp with time zone, _category text, _type text, _currency text, _merchant_name text, _location text) TO authenticated;
GRANT ALL ON FUNCTION public.add_transaction(_user_id uuid, _user_card_id uuid, _amount numeric, _description text, _transaction_date timestamp with time zone, _category text, _type text, _currency text, _merchant_name text, _location text) TO service_role;


--
-- Name: FUNCTION adopt_reviewed_card_enrichment_source(_card_id uuid, _issuer text, _canonical_url text, _final_url_hash text, _content_hash text, _parser_version text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.adopt_reviewed_card_enrichment_source(_card_id uuid, _issuer text, _canonical_url text, _final_url_hash text, _content_hash text, _parser_version text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.adopt_reviewed_card_enrichment_source(_card_id uuid, _issuer text, _canonical_url text, _final_url_hash text, _content_hash text, _parser_version text) TO service_role;


--
-- Name: FUNCTION append_catalog_observation_history(_history jsonb, _entry jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.append_catalog_observation_history(_history jsonb, _entry jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.append_catalog_observation_history(_history jsonb, _entry jsonb) TO service_role;


--
-- Name: FUNCTION apply_statement_payment(p_statement_id uuid, p_user_id uuid, p_user_card_id uuid, p_payment_amount numeric, p_mark_paid boolean); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.apply_statement_payment(p_statement_id uuid, p_user_id uuid, p_user_card_id uuid, p_payment_amount numeric, p_mark_paid boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION public.apply_statement_payment(p_statement_id uuid, p_user_id uuid, p_user_card_id uuid, p_payment_amount numeric, p_mark_paid boolean) TO anon;
GRANT ALL ON FUNCTION public.apply_statement_payment(p_statement_id uuid, p_user_id uuid, p_user_card_id uuid, p_payment_amount numeric, p_mark_paid boolean) TO authenticated;
GRANT ALL ON FUNCTION public.apply_statement_payment(p_statement_id uuid, p_user_id uuid, p_user_card_id uuid, p_payment_amount numeric, p_mark_paid boolean) TO service_role;


--
-- Name: FUNCTION approve_card_benefit_enrichment(_staging_id uuid, _reviewed_by uuid, _decisions jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.approve_card_benefit_enrichment(_staging_id uuid, _reviewed_by uuid, _decisions jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.approve_card_benefit_enrichment(_staging_id uuid, _reviewed_by uuid, _decisions jsonb) TO service_role;


--
-- Name: FUNCTION approve_catalog_entry_request(_staging_id uuid, _reviewed_by uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.approve_catalog_entry_request(_staging_id uuid, _reviewed_by uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.approve_catalog_entry_request(_staging_id uuid, _reviewed_by uuid) TO service_role;


--
-- Name: FUNCTION bounded_card_enrichment_timestamp(_value text, _now timestamp with time zone); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.bounded_card_enrichment_timestamp(_value text, _now timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION public.bounded_card_enrichment_timestamp(_value text, _now timestamp with time zone) TO service_role;


--
-- Name: FUNCTION canonical_benefit_condition_hash(_condition jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.canonical_benefit_condition_hash(_condition jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.canonical_benefit_condition_hash(_condition jsonb) TO service_role;


--
-- Name: FUNCTION canonical_card_benefit_row_timestamp(_value timestamp with time zone); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.canonical_card_benefit_row_timestamp(_value timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION public.canonical_card_benefit_row_timestamp(_value timestamp with time zone) TO service_role;


--
-- Name: FUNCTION canonical_card_enrichment_timestamp(_value text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.canonical_card_enrichment_timestamp(_value text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.canonical_card_enrichment_timestamp(_value text) TO service_role;


--
-- Name: FUNCTION canonical_card_resource_url(_url text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.canonical_card_resource_url(_url text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.canonical_card_resource_url(_url text) TO service_role;


--
-- Name: FUNCTION canonical_json_numbers_are_safe(_value jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.canonical_json_numbers_are_safe(_value jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.canonical_json_numbers_are_safe(_value jsonb) TO service_role;


--
-- Name: FUNCTION canonical_json_shape_is_bounded(_value jsonb, _max_depth integer, _max_keys integer, _max_array_items integer, _max_key_chars integer, _max_string_chars integer); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.canonical_json_shape_is_bounded(_value jsonb, _max_depth integer, _max_keys integer, _max_array_items integer, _max_key_chars integer, _max_string_chars integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.canonical_json_shape_is_bounded(_value jsonb, _max_depth integer, _max_keys integer, _max_array_items integer, _max_key_chars integer, _max_string_chars integer) TO service_role;


--
-- Name: FUNCTION canonical_json_text(_value jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.canonical_json_text(_value jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.canonical_json_text(_value jsonb) TO service_role;


--
-- Name: FUNCTION canonical_locked_benefit_condition(_proposal jsonb, _parser_version text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.canonical_locked_benefit_condition(_proposal jsonb, _parser_version text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.canonical_locked_benefit_condition(_proposal jsonb, _parser_version text) TO service_role;


--
-- Name: FUNCTION capture_card_enrichment_pilot_publication_snapshot(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.capture_card_enrichment_pilot_publication_snapshot() FROM PUBLIC;


--
-- Name: FUNCTION card_benefit_review_live_state_snapshot(_card_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.card_benefit_review_live_state_snapshot(_card_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.card_benefit_review_live_state_snapshot(_card_id uuid) TO service_role;


--
-- Name: FUNCTION card_benefit_review_snapshot_rows(_rows jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.card_benefit_review_snapshot_rows(_rows jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.card_benefit_review_snapshot_rows(_rows jsonb) TO service_role;


--
-- Name: FUNCTION card_catalog_baseline_matches(_baseline jsonb, _card_id uuid, _card_name text, _network text, _annual_fee numeric, _joining_fee numeric, _apr numeric, _card_url text, _is_discontinued boolean, _updated_at timestamp with time zone); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.card_catalog_baseline_matches(_baseline jsonb, _card_id uuid, _card_name text, _network text, _annual_fee numeric, _joining_fee numeric, _apr numeric, _card_url text, _is_discontinued boolean, _updated_at timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION public.card_catalog_baseline_matches(_baseline jsonb, _card_id uuid, _card_name text, _network text, _annual_fee numeric, _joining_fee numeric, _apr numeric, _card_url text, _is_discontinued boolean, _updated_at timestamp with time zone) TO service_role;


--
-- Name: FUNCTION card_catalog_effective_network(_network text, _card_name text, _issuer text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.card_catalog_effective_network(_network text, _card_name text, _issuer text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.card_catalog_effective_network(_network text, _card_name text, _issuer text) TO service_role;


--
-- Name: FUNCTION card_catalog_json_contains_sensitive_url(_value jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.card_catalog_json_contains_sensitive_url(_value jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.card_catalog_json_contains_sensitive_url(_value jsonb) TO service_role;


--
-- Name: FUNCTION card_catalog_json_envelope_valid(_value jsonb, _depth integer); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.card_catalog_json_envelope_valid(_value jsonb, _depth integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.card_catalog_json_envelope_valid(_value jsonb, _depth integer) TO service_role;


--
-- Name: FUNCTION card_catalog_source_matches_issuer(_issuer text, _url text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.card_catalog_source_matches_issuer(_issuer text, _url text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.card_catalog_source_matches_issuer(_issuer text, _url text) TO service_role;


--
-- Name: FUNCTION card_enrichment_effective_terminal_status(_requested_status text, _has_pending_staging boolean); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.card_enrichment_effective_terminal_status(_requested_status text, _has_pending_staging boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION public.card_enrichment_effective_terminal_status(_requested_status text, _has_pending_staging boolean) TO service_role;


--
-- Name: FUNCTION card_enrichment_enqueue_catalog_eligible(_card_id uuid, _input_issuer text, _input_url text, _input_url_hash text, _card_bank text, _card_url text, _card_type text, _is_discontinued boolean, _has_active_cardholder boolean, _has_unresolved_identity boolean); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.card_enrichment_enqueue_catalog_eligible(_card_id uuid, _input_issuer text, _input_url text, _input_url_hash text, _card_bank text, _card_url text, _card_type text, _is_discontinued boolean, _has_active_cardholder boolean, _has_unresolved_identity boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION public.card_enrichment_enqueue_catalog_eligible(_card_id uuid, _input_issuer text, _input_url text, _input_url_hash text, _card_bank text, _card_url text, _card_type text, _is_discontinued boolean, _has_active_cardholder boolean, _has_unresolved_identity boolean) TO service_role;


--
-- Name: FUNCTION card_enrichment_enqueue_count_is_valid(_requested_count integer, _inserted_count integer); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.card_enrichment_enqueue_count_is_valid(_requested_count integer, _inserted_count integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.card_enrichment_enqueue_count_is_valid(_requested_count integer, _inserted_count integer) TO service_role;


--
-- Name: FUNCTION card_enrichment_final_staging_state(_requested_status text, _requested_staging_id uuid, _prior_staging_id uuid, _locked_staging_id uuid, _locked_staging_status text, _locked_staging_valid boolean); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.card_enrichment_final_staging_state(_requested_status text, _requested_staging_id uuid, _prior_staging_id uuid, _locked_staging_id uuid, _locked_staging_status text, _locked_staging_valid boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION public.card_enrichment_final_staging_state(_requested_status text, _requested_staging_id uuid, _prior_staging_id uuid, _locked_staging_id uuid, _locked_staging_status text, _locked_staging_valid boolean) TO service_role;


--
-- Name: FUNCTION card_enrichment_jitter_days(_card_id uuid, _radius integer); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.card_enrichment_jitter_days(_card_id uuid, _radius integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.card_enrichment_jitter_days(_card_id uuid, _radius integer) TO service_role;


--
-- Name: FUNCTION card_enrichment_job_has_pending_staging(_staging_id uuid, _card_id uuid, _parser_version text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.card_enrichment_job_has_pending_staging(_staging_id uuid, _card_id uuid, _parser_version text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.card_enrichment_job_has_pending_staging(_staging_id uuid, _card_id uuid, _parser_version text) TO service_role;


--
-- Name: FUNCTION card_enrichment_pilot_cohort_action(_pilot_count integer, _promoted_count integer, _has_duplicate boolean); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.card_enrichment_pilot_cohort_action(_pilot_count integer, _promoted_count integer, _has_duplicate boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION public.card_enrichment_pilot_cohort_action(_pilot_count integer, _promoted_count integer, _has_duplicate boolean) TO service_role;


--
-- Name: FUNCTION is_valid_official_source_evidence(_source_evidence jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.is_valid_official_source_evidence(_source_evidence jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.is_valid_official_source_evidence(_source_evidence jsonb) TO service_role;


--
-- Name: TABLE card_benefits_staging; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.card_benefits_staging TO service_role;


--
-- Name: TABLE card_catalog_enrichment_jobs; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.card_catalog_enrichment_jobs TO service_role;


--
-- Name: FUNCTION card_enrichment_pilot_evidence_is_qualified(_job public.card_catalog_enrichment_jobs, _staging public.card_benefits_staging); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.card_enrichment_pilot_evidence_is_qualified(_job public.card_catalog_enrichment_jobs, _staging public.card_benefits_staging) FROM PUBLIC;
GRANT ALL ON FUNCTION public.card_enrichment_pilot_evidence_is_qualified(_job public.card_catalog_enrichment_jobs, _staging public.card_benefits_staging) TO service_role;


--
-- Name: FUNCTION card_enrichment_pilot_has_contextual_person(_text text, _known_identity_phrases jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.card_enrichment_pilot_has_contextual_person(_text text, _known_identity_phrases jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.card_enrichment_pilot_has_contextual_person(_text text, _known_identity_phrases jsonb) TO service_role;


--
-- Name: FUNCTION card_enrichment_pilot_job_is_qualified(_status text, _failure_category text, _summary jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.card_enrichment_pilot_job_is_qualified(_status text, _failure_category text, _summary jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.card_enrichment_pilot_job_is_qualified(_status text, _failure_category text, _summary jsonb) TO service_role;


--
-- Name: FUNCTION card_enrichment_pilot_live_state_snapshot(_card_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.card_enrichment_pilot_live_state_snapshot(_card_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.card_enrichment_pilot_live_state_snapshot(_card_id uuid) TO service_role;


--
-- Name: FUNCTION card_enrichment_pilot_queryless_display_url(_url text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.card_enrichment_pilot_queryless_display_url(_url text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.card_enrichment_pilot_queryless_display_url(_url text) TO service_role;


--
-- Name: FUNCTION card_enrichment_pilot_snapshot_rows(_rows jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.card_enrichment_pilot_snapshot_rows(_rows jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.card_enrichment_pilot_snapshot_rows(_rows jsonb) TO service_role;


--
-- Name: FUNCTION card_enrichment_pilot_source_identity_hash(_url text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.card_enrichment_pilot_source_identity_hash(_url text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.card_enrichment_pilot_source_identity_hash(_url text) TO service_role;


--
-- Name: FUNCTION card_enrichment_pilot_source_manifest_hash(_attempts jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.card_enrichment_pilot_source_manifest_hash(_attempts jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.card_enrichment_pilot_source_manifest_hash(_attempts jsonb) TO service_role;


--
-- Name: FUNCTION card_enrichment_pilot_timestamp(_value text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.card_enrichment_pilot_timestamp(_value text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.card_enrichment_pilot_timestamp(_value text) TO service_role;


--
-- Name: FUNCTION card_enrichment_requeue_action(_run_mode text, _status text, _next_run_at timestamp with time zone, _now timestamp with time zone, _eligible boolean, _has_pending_staging boolean); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.card_enrichment_requeue_action(_run_mode text, _status text, _next_run_at timestamp with time zone, _now timestamp with time zone, _eligible boolean, _has_pending_staging boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION public.card_enrichment_requeue_action(_run_mode text, _status text, _next_run_at timestamp with time zone, _now timestamp with time zone, _eligible boolean, _has_pending_staging boolean) TO service_role;


--
-- Name: FUNCTION card_has_unresolved_catalog_identity(_card_id uuid, _canonical_url text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.card_has_unresolved_catalog_identity(_card_id uuid, _canonical_url text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.card_has_unresolved_catalog_identity(_card_id uuid, _canonical_url text) TO service_role;


--
-- Name: FUNCTION card_scoped_benefit_key(_card_id uuid, _condition jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.card_scoped_benefit_key(_card_id uuid, _condition jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.card_scoped_benefit_key(_card_id uuid, _condition jsonb) TO service_role;


--
-- Name: FUNCTION catalog_lifecycle_semantic_observation(_value jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.catalog_lifecycle_semantic_observation(_value jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.catalog_lifecycle_semantic_observation(_value jsonb) TO service_role;


--
-- Name: FUNCTION claim_card_catalog_enrichment_jobs(_max_jobs integer, _lease_seconds integer, _run_mode text, _parser_version text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.claim_card_catalog_enrichment_jobs(_max_jobs integer, _lease_seconds integer, _run_mode text, _parser_version text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.claim_card_catalog_enrichment_jobs(_max_jobs integer, _lease_seconds integer, _run_mode text, _parser_version text) TO service_role;


--
-- Name: FUNCTION consume_gemini_proxy_quota(_user_id uuid, _limit integer); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.consume_gemini_proxy_quota(_user_id uuid, _limit integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.consume_gemini_proxy_quota(_user_id uuid, _limit integer) TO service_role;


--
-- Name: FUNCTION create_or_get_card_catalog(_bank text, _card_name text, _network text, _card_type text, _joining_fee numeric, _annual_fee numeric, _apr numeric); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.create_or_get_card_catalog(_bank text, _card_name text, _network text, _card_type text, _joining_fee numeric, _annual_fee numeric, _apr numeric) FROM PUBLIC;


--
-- Name: FUNCTION decode_card_resource_component(_value text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.decode_card_resource_component(_value text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.decode_card_resource_component(_value text) TO service_role;


--
-- Name: FUNCTION enforce_card_benefit_enrichment_identity(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.enforce_card_benefit_enrichment_identity() FROM PUBLIC;
GRANT ALL ON FUNCTION public.enforce_card_benefit_enrichment_identity() TO service_role;


--
-- Name: FUNCTION enqueue_card_benefit_enrichment_jobs(_jobs jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.enqueue_card_benefit_enrichment_jobs(_jobs jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.enqueue_card_benefit_enrichment_jobs(_jobs jsonb) TO service_role;


--
-- Name: FUNCTION enrich_waitlist(p_enrichment_token text, p_name text, p_card_count text, p_monthly_spend_band text, p_primary_goal text, p_problem_detail text, p_top_cards text[], p_marketing_consent boolean); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.enrich_waitlist(p_enrichment_token text, p_name text, p_card_count text, p_monthly_spend_band text, p_primary_goal text, p_problem_detail text, p_top_cards text[], p_marketing_consent boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION public.enrich_waitlist(p_enrichment_token text, p_name text, p_card_count text, p_monthly_spend_band text, p_primary_goal text, p_problem_detail text, p_top_cards text[], p_marketing_consent boolean) TO service_role;
GRANT ALL ON FUNCTION public.enrich_waitlist(p_enrichment_token text, p_name text, p_card_count text, p_monthly_spend_band text, p_primary_goal text, p_problem_detail text, p_top_cards text[], p_marketing_consent boolean) TO anon;
GRANT ALL ON FUNCTION public.enrich_waitlist(p_enrichment_token text, p_name text, p_card_count text, p_monthly_spend_band text, p_primary_goal text, p_problem_detail text, p_top_cards text[], p_marketing_consent boolean) TO authenticated;


--
-- Name: FUNCTION finalize_card_catalog_enrichment_job(_job_id uuid, _lease_token uuid, _status text, _staging_id uuid, _content_hash text, _normalized_fields jsonb, _result_summary jsonb, _failure_category text, _next_retry_at timestamp with time zone); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.finalize_card_catalog_enrichment_job(_job_id uuid, _lease_token uuid, _status text, _staging_id uuid, _content_hash text, _normalized_fields jsonb, _result_summary jsonb, _failure_category text, _next_retry_at timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION public.finalize_card_catalog_enrichment_job(_job_id uuid, _lease_token uuid, _status text, _staging_id uuid, _content_hash text, _normalized_fields jsonb, _result_summary jsonb, _failure_category text, _next_retry_at timestamp with time zone) TO service_role;


--
-- Name: FUNCTION get_card_catalog(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.get_card_catalog() TO authenticated;
GRANT ALL ON FUNCTION public.get_card_catalog() TO service_role;


--
-- Name: FUNCTION get_movie_benefit_mapping_health(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.get_movie_benefit_mapping_health() FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_movie_benefit_mapping_health() TO service_role;


--
-- Name: FUNCTION get_user_transactions(_user_id uuid, _limit integer); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.get_user_transactions(_user_id uuid, _limit integer) TO authenticated;
GRANT ALL ON FUNCTION public.get_user_transactions(_user_id uuid, _limit integer) TO service_role;


--
-- Name: FUNCTION initialize_card_benefit_enrichment_pilot(_candidates jsonb, _parser_version text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.initialize_card_benefit_enrichment_pilot(_candidates jsonb, _parser_version text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.initialize_card_benefit_enrichment_pilot(_candidates jsonb, _parser_version text) TO service_role;


--
-- Name: FUNCTION join_waitlist(p_email text, p_source text, p_utm_source text, p_utm_medium text, p_utm_campaign text, p_utm_term text, p_utm_content text, p_referrer_path text, p_landing_variant text, p_privacy_consent boolean, p_website text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.join_waitlist(p_email text, p_source text, p_utm_source text, p_utm_medium text, p_utm_campaign text, p_utm_term text, p_utm_content text, p_referrer_path text, p_landing_variant text, p_privacy_consent boolean, p_website text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.join_waitlist(p_email text, p_source text, p_utm_source text, p_utm_medium text, p_utm_campaign text, p_utm_term text, p_utm_content text, p_referrer_path text, p_landing_variant text, p_privacy_consent boolean, p_website text) TO service_role;
GRANT ALL ON FUNCTION public.join_waitlist(p_email text, p_source text, p_utm_source text, p_utm_medium text, p_utm_campaign text, p_utm_term text, p_utm_content text, p_referrer_path text, p_landing_variant text, p_privacy_consent boolean, p_website text) TO anon;
GRANT ALL ON FUNCTION public.join_waitlist(p_email text, p_source text, p_utm_source text, p_utm_medium text, p_utm_campaign text, p_utm_term text, p_utm_content text, p_referrer_path text, p_landing_variant text, p_privacy_consent boolean, p_website text) TO authenticated;


--
-- Name: FUNCTION list_pending_catalog_entry_requests(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.list_pending_catalog_entry_requests() FROM PUBLIC;
GRANT ALL ON FUNCTION public.list_pending_catalog_entry_requests() TO service_role;


--
-- Name: FUNCTION next_card_enrichment_observation_at(_card_id uuid, _completed_at text, _is_discontinued boolean, _has_active_cardholder boolean, _outcome text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.next_card_enrichment_observation_at(_card_id uuid, _completed_at text, _is_discontinued boolean, _has_active_cardholder boolean, _outcome text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.next_card_enrichment_observation_at(_card_id uuid, _completed_at text, _is_discontinued boolean, _has_active_cardholder boolean, _outcome text) TO service_role;


--
-- Name: FUNCTION normalize_benefit_exclusions_shape(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.normalize_benefit_exclusions_shape() TO anon;
GRANT ALL ON FUNCTION public.normalize_benefit_exclusions_shape() TO authenticated;
GRANT ALL ON FUNCTION public.normalize_benefit_exclusions_shape() TO service_role;


--
-- Name: FUNCTION normalize_benefit_exclusions_value(_exclusions jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.normalize_benefit_exclusions_value(_exclusions jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.normalize_benefit_exclusions_value(_exclusions jsonb) TO service_role;


--
-- Name: FUNCTION normalize_card_catalog_family(_value text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.normalize_card_catalog_family(_value text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.normalize_card_catalog_family(_value text) TO service_role;


--
-- Name: FUNCTION normalize_card_catalog_network(_value text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.normalize_card_catalog_network(_value text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.normalize_card_catalog_network(_value text) TO service_role;


--
-- Name: FUNCTION normalize_card_catalog_product(_value text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.normalize_card_catalog_product(_value text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.normalize_card_catalog_product(_value text) TO service_role;


--
-- Name: FUNCTION normalize_card_catalog_tier(_value text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.normalize_card_catalog_tier(_value text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.normalize_card_catalog_tier(_value text) TO service_role;


--
-- Name: FUNCTION normalize_card_enrichment_observation_history(_existing_history jsonb, _current_observation jsonb, _now timestamp with time zone); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.normalize_card_enrichment_observation_history(_existing_history jsonb, _current_observation jsonb, _now timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION public.normalize_card_enrichment_observation_history(_existing_history jsonb, _current_observation jsonb, _now timestamp with time zone) TO service_role;


--
-- Name: FUNCTION normalize_card_resource_path(_path text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.normalize_card_resource_path(_path text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.normalize_card_resource_path(_path text) TO service_role;


--
-- Name: FUNCTION promote_qualified_card_benefit_enrichment_pilot(_parser_version text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.promote_qualified_card_benefit_enrichment_pilot(_parser_version text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.promote_qualified_card_benefit_enrichment_pilot(_parser_version text) TO service_role;


--
-- Name: FUNCTION protect_reconciled_statement_fields(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.protect_reconciled_statement_fields() TO anon;
GRANT ALL ON FUNCTION public.protect_reconciled_statement_fields() TO authenticated;
GRANT ALL ON FUNCTION public.protect_reconciled_statement_fields() TO service_role;


--
-- Name: FUNCTION publish_card_catalog_identity(_discovery_job_id uuid, _review_item_id uuid, _actor_id uuid, _action text, _reviewed_fields jsonb, _merge_card_id uuid, _reason text, _parser_version text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.publish_card_catalog_identity(_discovery_job_id uuid, _review_item_id uuid, _actor_id uuid, _action text, _reviewed_fields jsonb, _merge_card_id uuid, _reason text, _parser_version text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.publish_card_catalog_identity(_discovery_job_id uuid, _review_item_id uuid, _actor_id uuid, _action text, _reviewed_fields jsonb, _merge_card_id uuid, _reason text, _parser_version text) TO service_role;


--
-- Name: FUNCTION reconcile_imported_statement_payment(p_source_statement_id uuid, p_user_id uuid, p_user_card_id uuid, p_expected_payment_credit numeric); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.reconcile_imported_statement_payment(p_source_statement_id uuid, p_user_id uuid, p_user_card_id uuid, p_expected_payment_credit numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION public.reconcile_imported_statement_payment(p_source_statement_id uuid, p_user_id uuid, p_user_card_id uuid, p_expected_payment_credit numeric) TO anon;
GRANT ALL ON FUNCTION public.reconcile_imported_statement_payment(p_source_statement_id uuid, p_user_id uuid, p_user_card_id uuid, p_expected_payment_credit numeric) TO authenticated;
GRANT ALL ON FUNCTION public.reconcile_imported_statement_payment(p_source_statement_id uuid, p_user_id uuid, p_user_card_id uuid, p_expected_payment_credit numeric) TO service_role;


--
-- Name: FUNCTION reject_catalog_entry_request(_staging_id uuid, _reviewed_by uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.reject_catalog_entry_request(_staging_id uuid, _reviewed_by uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.reject_catalog_entry_request(_staging_id uuid, _reviewed_by uuid) TO service_role;


--
-- Name: FUNCTION remove_user_card(_user_id uuid, _catalog_card_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.remove_user_card(_user_id uuid, _catalog_card_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.remove_user_card(_user_id uuid, _catalog_card_id uuid) TO service_role;


--
-- Name: FUNCTION requeue_due_card_catalog_enrichment_jobs(_parser_version text, _limit integer, _now timestamp with time zone); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.requeue_due_card_catalog_enrichment_jobs(_parser_version text, _limit integer, _now timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION public.requeue_due_card_catalog_enrichment_jobs(_parser_version text, _limit integer, _now timestamp with time zone) TO service_role;


--
-- Name: FUNCTION reset_my_cardcompass_data(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.reset_my_cardcompass_data() FROM PUBLIC;
GRANT ALL ON FUNCTION public.reset_my_cardcompass_data() TO authenticated;
GRANT ALL ON FUNCTION public.reset_my_cardcompass_data() TO service_role;


--
-- Name: FUNCTION resolve_card_catalog_identity(_issuer text, _card_name text, _network text, _source_url text, _submitted_url_hash text, _final_url_hash text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.resolve_card_catalog_identity(_issuer text, _card_name text, _network text, _source_url text, _submitted_url_hash text, _final_url_hash text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.resolve_card_catalog_identity(_issuer text, _card_name text, _network text, _source_url text, _submitted_url_hash text, _final_url_hash text) TO service_role;


--
-- Name: FUNCTION review_card_catalog_discovery(_review_item_id uuid, _actor_id uuid, _action text, _proposed_fields jsonb, _merge_card_id uuid, _reason text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.review_card_catalog_discovery(_review_item_id uuid, _actor_id uuid, _action text, _proposed_fields jsonb, _merge_card_id uuid, _reason text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.review_card_catalog_discovery(_review_item_id uuid, _actor_id uuid, _action text, _proposed_fields jsonb, _merge_card_id uuid, _reason text) TO service_role;


--
-- Name: FUNCTION sanitize_card_enrichment_observation(_observation jsonb, _now timestamp with time zone); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.sanitize_card_enrichment_observation(_observation jsonb, _now timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION public.sanitize_card_enrichment_observation(_observation jsonb, _now timestamp with time zone) TO service_role;


--
-- Name: FUNCTION sanitize_card_enrichment_result_summary(_summary jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.sanitize_card_enrichment_result_summary(_summary jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.sanitize_card_enrichment_result_summary(_summary jsonb) TO service_role;


--
-- Name: FUNCTION sanitize_card_enrichment_source_attempt(_attempt jsonb, _now timestamp with time zone); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.sanitize_card_enrichment_source_attempt(_attempt jsonb, _now timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION public.sanitize_card_enrichment_source_attempt(_attempt jsonb, _now timestamp with time zone) TO service_role;


--
-- Name: FUNCTION schedule_terminal_card_enrichment_observation(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.schedule_terminal_card_enrichment_observation() FROM PUBLIC;


--
-- Name: FUNCTION set_card_catalog_enrichment_job_key(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.set_card_catalog_enrichment_job_key() TO anon;
GRANT ALL ON FUNCTION public.set_card_catalog_enrichment_job_key() TO authenticated;
GRANT ALL ON FUNCTION public.set_card_catalog_enrichment_job_key() TO service_role;


--
-- Name: FUNCTION stage_card_benefit_enrichment(_job_id uuid, _lease_token uuid, _source_url text, _source_url_hash text, _parser_version text, _content_hash text, _extracted_data jsonb, _calculated_confidence numeric, _validation_reasons jsonb, _validation_warnings jsonb, _source_evidence jsonb, _validated_at timestamp with time zone); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.stage_card_benefit_enrichment(_job_id uuid, _lease_token uuid, _source_url text, _source_url_hash text, _parser_version text, _content_hash text, _extracted_data jsonb, _calculated_confidence numeric, _validation_reasons jsonb, _validation_warnings jsonb, _source_evidence jsonb, _validated_at timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION public.stage_card_benefit_enrichment(_job_id uuid, _lease_token uuid, _source_url text, _source_url_hash text, _parser_version text, _content_hash text, _extracted_data jsonb, _calculated_confidence numeric, _validation_reasons jsonb, _validation_warnings jsonb, _source_evidence jsonb, _validated_at timestamp with time zone) TO service_role;


--
-- Name: FUNCTION stage_card_catalog_identity_review(_discovery_job_id uuid, _discovery_source text, _user_id uuid, _issuer text, _proposed_product text, _dedupe_key text, _semantic_hash text, _proposed_fields jsonb, _source_evidence jsonb, _existing_candidates jsonb, _validation_warnings jsonb, _confidence numeric, _expected_job_status text, _expected_job_updated_at timestamp with time zone); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.stage_card_catalog_identity_review(_discovery_job_id uuid, _discovery_source text, _user_id uuid, _issuer text, _proposed_product text, _dedupe_key text, _semantic_hash text, _proposed_fields jsonb, _source_evidence jsonb, _existing_candidates jsonb, _validation_warnings jsonb, _confidence numeric, _expected_job_status text, _expected_job_updated_at timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION public.stage_card_catalog_identity_review(_discovery_job_id uuid, _discovery_source text, _user_id uuid, _issuer text, _proposed_product text, _dedupe_key text, _semantic_hash text, _proposed_fields jsonb, _source_evidence jsonb, _existing_candidates jsonb, _validation_warnings jsonb, _confidence numeric, _expected_job_status text, _expected_job_updated_at timestamp with time zone) TO service_role;


--
-- Name: FUNCTION stage_card_catalog_lifecycle_review(_card_id uuid, _suggested_action text, _source_observation jsonb, _source_url text, _source_url_hash text, _content_hash text, _parser_version text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.stage_card_catalog_lifecycle_review(_card_id uuid, _suggested_action text, _source_observation jsonb, _source_url text, _source_url_hash text, _content_hash text, _parser_version text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.stage_card_catalog_lifecycle_review(_card_id uuid, _suggested_action text, _source_observation jsonb, _source_url text, _source_url_hash text, _content_hash text, _parser_version text) TO service_role;


--
-- Name: FUNCTION submit_card_catalog_request(_user_id uuid, _bank_name text, _card_name text, _card_url text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.submit_card_catalog_request(_user_id uuid, _bank_name text, _card_name text, _card_url text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.submit_card_catalog_request(_user_id uuid, _bank_name text, _card_name text, _card_url text) TO service_role;


--
-- Name: FUNCTION terminalize_calculator_review_rows(_actor_id uuid, _limit integer, _confirmed boolean); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.terminalize_calculator_review_rows(_actor_id uuid, _limit integer, _confirmed boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION public.terminalize_calculator_review_rows(_actor_id uuid, _limit integer, _confirmed boolean) TO service_role;


--
-- Name: FUNCTION update_updated_at_column(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.update_updated_at_column() TO anon;
GRANT ALL ON FUNCTION public.update_updated_at_column() TO authenticated;
GRANT ALL ON FUNCTION public.update_updated_at_column() TO service_role;


--
-- Name: FUNCTION update_waitlist_operator(p_id uuid, p_status text, p_notes text, p_operator_score integer, p_contacted_at timestamp with time zone, p_invited_at timestamp with time zone); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.update_waitlist_operator(p_id uuid, p_status text, p_notes text, p_operator_score integer, p_contacted_at timestamp with time zone, p_invited_at timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION public.update_waitlist_operator(p_id uuid, p_status text, p_notes text, p_operator_score integer, p_contacted_at timestamp with time zone, p_invited_at timestamp with time zone) TO service_role;


--
-- Name: FUNCTION validate_benefit_publication_envelope(_envelope jsonb, _card_id uuid, _staged_proposal jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.validate_benefit_publication_envelope(_envelope jsonb, _card_id uuid, _staged_proposal jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.validate_benefit_publication_envelope(_envelope jsonb, _card_id uuid, _staged_proposal jsonb) TO service_role;


--
-- Name: FUNCTION validate_locked_benefit_proposals(_proposals jsonb, _parser_version text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.validate_locked_benefit_proposals(_proposals jsonb, _parser_version text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.validate_locked_benefit_proposals(_proposals jsonb, _parser_version text) TO service_role;


--
-- Name: FUNCTION validate_locked_retirement_evidence(_extracted_data jsonb, _live_benefit_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.validate_locked_retirement_evidence(_extracted_data jsonb, _live_benefit_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.validate_locked_retirement_evidence(_extracted_data jsonb, _live_benefit_id uuid) TO service_role;


--
-- Name: TABLE benefits; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE public.benefits TO anon;
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE public.benefits TO authenticated;
GRANT ALL ON TABLE public.benefits TO service_role;


--
-- Name: TABLE card_benefit_mapping; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE public.card_benefit_mapping TO anon;
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE public.card_benefit_mapping TO authenticated;
GRANT ALL ON TABLE public.card_benefit_mapping TO service_role;


--
-- Name: TABLE active_card_benefits; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.active_card_benefits TO authenticated;
GRANT ALL ON TABLE public.active_card_benefits TO service_role;


--
-- Name: TABLE benefit_categories; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE public.benefit_categories TO anon;
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE public.benefit_categories TO authenticated;
GRANT ALL ON TABLE public.benefit_categories TO service_role;


--
-- Name: TABLE benefit_platform_confirmations; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.benefit_platform_confirmations TO anon;
GRANT ALL ON TABLE public.benefit_platform_confirmations TO service_role;
GRANT INSERT ON TABLE public.benefit_platform_confirmations TO authenticated;


--
-- Name: TABLE benefit_platform_confirmation_counts; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.benefit_platform_confirmation_counts TO anon;
GRANT ALL ON TABLE public.benefit_platform_confirmation_counts TO authenticated;
GRANT ALL ON TABLE public.benefit_platform_confirmation_counts TO service_role;


--
-- Name: TABLE card_benefits; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.card_benefits TO service_role;


--
-- Name: TABLE card_catalog; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE public.card_catalog TO anon;
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE public.card_catalog TO authenticated;
GRANT ALL ON TABLE public.card_catalog TO service_role;


--
-- Name: TABLE card_catalog_aliases; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.card_catalog_aliases TO service_role;
GRANT SELECT ON TABLE public.card_catalog_aliases TO authenticated;


--
-- Name: TABLE card_catalog_provenance; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.card_catalog_provenance TO service_role;


--
-- Name: TABLE card_catalog_review_audit; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.card_catalog_review_audit TO service_role;


--
-- Name: TABLE card_catalog_review_queue; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.card_catalog_review_queue TO service_role;


--
-- Name: TABLE card_catalog_url_keys; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.card_catalog_url_keys TO service_role;


--
-- Name: TABLE card_discovery_jobs; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.card_discovery_jobs TO service_role;


--
-- Name: TABLE emails; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.emails TO anon;
GRANT ALL ON TABLE public.emails TO authenticated;
GRANT ALL ON TABLE public.emails TO service_role;


--
-- Name: TABLE gemini_proxy_usage; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.gemini_proxy_usage TO service_role;


--
-- Name: SEQUENCE gemini_proxy_usage_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.gemini_proxy_usage_id_seq TO anon;
GRANT ALL ON SEQUENCE public.gemini_proxy_usage_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.gemini_proxy_usage_id_seq TO service_role;


--
-- Name: TABLE merchant_category_map; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.merchant_category_map TO anon;
GRANT ALL ON TABLE public.merchant_category_map TO authenticated;
GRANT ALL ON TABLE public.merchant_category_map TO service_role;


--
-- Name: TABLE waitlist; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN ON TABLE public.waitlist TO service_role;


--
-- Name: TABLE operator_waitlist_ranked; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.operator_waitlist_ranked TO service_role;


--
-- Name: TABLE transactions; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.transactions TO anon;
GRANT ALL ON TABLE public.transactions TO authenticated;
GRANT ALL ON TABLE public.transactions TO service_role;


--
-- Name: TABLE reward_balances; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.reward_balances TO anon;
GRANT ALL ON TABLE public.reward_balances TO authenticated;
GRANT ALL ON TABLE public.reward_balances TO service_role;


--
-- Name: TABLE statement_milestone_cache; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.statement_milestone_cache TO anon;
GRANT ALL ON TABLE public.statement_milestone_cache TO authenticated;
GRANT ALL ON TABLE public.statement_milestone_cache TO service_role;


--
-- Name: SEQUENCE statement_milestone_cache_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.statement_milestone_cache_id_seq TO anon;
GRANT ALL ON SEQUENCE public.statement_milestone_cache_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.statement_milestone_cache_id_seq TO service_role;


--
-- Name: TABLE statements; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.statements TO anon;
GRANT ALL ON TABLE public.statements TO authenticated;
GRANT ALL ON TABLE public.statements TO service_role;


--
-- Name: TABLE user_cards; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.user_cards TO anon;
GRANT ALL ON TABLE public.user_cards TO authenticated;
GRANT ALL ON TABLE public.user_cards TO service_role;


--
-- Name: TABLE users; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.users TO anon;
GRANT SELECT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN ON TABLE public.users TO authenticated;
GRANT ALL ON TABLE public.users TO service_role;


--
-- Name: COLUMN users.id; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(id),UPDATE(id) ON TABLE public.users TO authenticated;


--
-- Name: COLUMN users.email; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(email),UPDATE(email) ON TABLE public.users TO authenticated;


--
-- Name: COLUMN users.full_name; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(full_name),UPDATE(full_name) ON TABLE public.users TO authenticated;


--
-- Name: COLUMN users.avatar_url; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(avatar_url),UPDATE(avatar_url) ON TABLE public.users TO authenticated;


--
-- Name: COLUMN users.phone; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(phone),UPDATE(phone) ON TABLE public.users TO authenticated;


--
-- Name: COLUMN users.created_at; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(created_at),UPDATE(created_at) ON TABLE public.users TO authenticated;


--
-- Name: COLUMN users.updated_at; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(updated_at),UPDATE(updated_at) ON TABLE public.users TO authenticated;


--
-- Name: COLUMN users.preferences; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(preferences),UPDATE(preferences) ON TABLE public.users TO authenticated;


--
-- Name: COLUMN users.is_active; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(is_active),UPDATE(is_active) ON TABLE public.users TO authenticated;


--
-- Name: COLUMN users.given_name; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(given_name),UPDATE(given_name) ON TABLE public.users TO authenticated;


--
-- Name: COLUMN users.family_name; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(family_name),UPDATE(family_name) ON TABLE public.users TO authenticated;


--
-- Name: COLUMN users.date_of_birth; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(date_of_birth),UPDATE(date_of_birth) ON TABLE public.users TO authenticated;


--
-- Name: COLUMN users.profile_data; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(profile_data),UPDATE(profile_data) ON TABLE public.users TO authenticated;


--
-- Name: TABLE waitlist_public_attempts; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.waitlist_public_attempts TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO service_role;


--
-- PostgreSQL database dump complete
--

\unrestrict ll6MZjhMAf84oGBGwhgVVbhp3f6Qh7gXe94XBtiklgle4FobDVKmYRVqzNkfBKg
