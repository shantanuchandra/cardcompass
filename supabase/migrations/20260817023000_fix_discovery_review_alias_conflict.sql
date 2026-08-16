CREATE OR REPLACE FUNCTION public.review_card_catalog_discovery(
  _review_item_id uuid,
  _actor_id uuid,
  _action text,
  _proposed_fields jsonb DEFAULT NULL,
  _merge_card_id uuid DEFAULT NULL,
  _reason text DEFAULT NULL
) RETURNS TABLE (card_id uuid, job_id uuid, resulting_status text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  review_row public.card_catalog_review_queue%ROWTYPE;
  job_row public.card_discovery_jobs%ROWTYPE;
  fields jsonb;
  resolved_card uuid;
  normalized_alias_value text;
  alias_value text;
BEGIN
  IF _action NOT IN ('approve', 'merge', 'edit_approve', 'retry', 'reject') THEN
    RAISE EXCEPTION 'Unsupported review action';
  END IF;

  SELECT * INTO review_row
  FROM public.card_catalog_review_queue
  WHERE id = _review_item_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Review item not found'; END IF;

  SELECT * INTO job_row
  FROM public.card_discovery_jobs
  WHERE id = review_row.discovery_job_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Discovery job not found'; END IF;

  IF _action = 'retry' THEN
    UPDATE public.card_catalog_review_queue
    SET status = 'pending', review_reason = _reason, updated_at = now()
    WHERE id = review_row.id;
    UPDATE public.card_discovery_jobs
    SET status = 'queued', review_item_id = NULL, failure_category = NULL,
        next_retry_at = now(), updated_at = now()
    WHERE id = job_row.id;
    INSERT INTO public.card_catalog_review_audit(review_item_id, actor_id, action, details)
    VALUES (review_row.id, _actor_id, _action, jsonb_build_object('reason', _reason));
    RETURN QUERY SELECT NULL::uuid, job_row.id, 'queued'::text;
    RETURN;
  END IF;

  IF _action = 'reject' THEN
    IF _reason IS NULL OR length(trim(_reason)) < 2 THEN
      RAISE EXCEPTION 'A rejection reason is required';
    END IF;
    UPDATE public.card_catalog_review_queue
    SET status = 'rejected', reviewed_by = _actor_id, review_reason = _reason,
        reviewed_at = now(), updated_at = now()
    WHERE id = review_row.id;
    UPDATE public.card_discovery_jobs
    SET status = 'rejected', updated_at = now()
    WHERE id = job_row.id;
    INSERT INTO public.card_catalog_review_audit(review_item_id, actor_id, action, details)
    VALUES (review_row.id, _actor_id, _action, jsonb_build_object('reason', _reason));
    RETURN QUERY SELECT NULL::uuid, job_row.id, 'rejected'::text;
    RETURN;
  END IF;

  fields := COALESCE(_proposed_fields, review_row.proposed_fields);
  IF _action = 'merge' THEN
    IF _merge_card_id IS NULL THEN RAISE EXCEPTION 'merge_card_id is required'; END IF;
    SELECT id INTO resolved_card FROM public.card_catalog WHERE id = _merge_card_id;
    IF resolved_card IS NULL THEN RAISE EXCEPTION 'Merge target not found'; END IF;
  ELSE
    IF length(trim(COALESCE(fields->>'issuer', fields->>'bank', ''))) < 2
       OR length(trim(COALESCE(fields->>'cardName', fields->>'card_name', ''))) < 2 THEN
      RAISE EXCEPTION 'Issuer and card name are required';
    END IF;
    SELECT id INTO resolved_card
    FROM public.card_catalog
    WHERE lower(trim(bank)) = lower(trim(COALESCE(fields->>'issuer', fields->>'bank')))
      AND lower(trim(card_name)) = lower(trim(COALESCE(fields->>'cardName', fields->>'card_name')))
    ORDER BY created_at
    LIMIT 1;
    IF resolved_card IS NULL THEN
      INSERT INTO public.card_catalog(bank, card_name, network, card_type, card_url)
      VALUES (
        trim(COALESCE(fields->>'issuer', fields->>'bank')),
        trim(COALESCE(fields->>'cardName', fields->>'card_name')),
        NULLIF(trim(fields->>'network'), ''),
        'credit',
        NULLIF(trim(COALESCE(fields->>'official_url', fields->>'card_url')), '')
      ) RETURNING id INTO resolved_card;
    END IF;
  END IF;

  FOR alias_value IN
    SELECT DISTINCT value
    FROM jsonb_array_elements_text(
      COALESCE(fields->'aliases', '[]'::jsonb) ||
      COALESCE(job_row.evidence->'product_signals', '[]'::jsonb)
    ) AS aliases(value)
    WHERE length(trim(value)) >= 2
  LOOP
    normalized_alias_value := lower(regexp_replace(alias_value, '[^a-zA-Z0-9]+', '', 'g'));
    IF length(normalized_alias_value) >= 2 THEN
      INSERT INTO public.card_catalog_aliases(
        card_id, alias, normalized_alias, evidence_type, source_url
      ) VALUES (
        resolved_card, alias_value, normalized_alias_value, 'admin',
        NULLIF(trim(COALESCE(fields->>'official_url', fields->>'card_url')), '')
      ) ON CONFLICT ON CONSTRAINT card_catalog_aliases_card_id_normalized_alias_key
        DO NOTHING;
    END IF;
  END LOOP;

  UPDATE public.card_catalog_review_queue
  SET status = CASE WHEN _action = 'merge' THEN 'merged' ELSE 'approved' END,
      proposed_fields = fields,
      reviewed_by = _actor_id,
      review_reason = _reason,
      reviewed_at = now(),
      updated_at = now()
  WHERE id = review_row.id;
  UPDATE public.card_discovery_jobs
  SET status = 'resolved', resolved_card_id = resolved_card,
      failure_category = NULL, next_retry_at = NULL, updated_at = now()
  WHERE id = job_row.id;
  INSERT INTO public.card_catalog_review_audit(review_item_id, actor_id, action, details)
  VALUES (
    review_row.id, _actor_id, _action,
    jsonb_build_object('card_id', resolved_card, 'reason', _reason, 'fields', fields)
  );

  RETURN QUERY SELECT resolved_card, job_row.id,
    CASE WHEN _action = 'merge' THEN 'merged'::text ELSE 'approved'::text END;
END;
$$;

REVOKE ALL ON FUNCTION public.review_card_catalog_discovery(uuid, uuid, text, jsonb, uuid, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.review_card_catalog_discovery(uuid, uuid, text, jsonb, uuid, text)
  TO service_role;
