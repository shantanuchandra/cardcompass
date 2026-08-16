-- Persistent, privacy-bounded discovery state for missing credit-card variants.
-- All writes go through service-role Edge Functions; authenticated clients do
-- not receive direct table access.

CREATE TABLE IF NOT EXISTS public.card_catalog_aliases (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  card_id uuid NOT NULL REFERENCES public.card_catalog(id) ON DELETE CASCADE,
  alias text NOT NULL CHECK (length(trim(alias)) BETWEEN 2 AND 160),
  normalized_alias text NOT NULL CHECK (length(normalized_alias) BETWEEN 2 AND 160),
  evidence_type text NOT NULL CHECK (
    evidence_type IN ('subject', 'filename', 'pdf_header', 'issuer_page', 'admin')
  ),
  source_url text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_card_catalog_aliases_card_normalized
  ON public.card_catalog_aliases(card_id, normalized_alias);
CREATE INDEX IF NOT EXISTS idx_card_catalog_aliases_normalized
  ON public.card_catalog_aliases(normalized_alias);

CREATE TABLE IF NOT EXISTS public.card_catalog_provenance (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  card_id uuid NOT NULL REFERENCES public.card_catalog(id) ON DELETE CASCADE,
  source_url text NOT NULL CHECK (source_url ~ '^https://'),
  source_type text NOT NULL CHECK (source_type IN ('official_html', 'official_pdf', 'secondary')),
  content_hash text NOT NULL,
  extracted_fields jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(extracted_fields) = 'object'),
  source_evidence jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(source_evidence) = 'object'),
  validation_version text NOT NULL,
  confidence numeric(5,4) NOT NULL CHECK (confidence BETWEEN 0 AND 1),
  approval_method text NOT NULL CHECK (approval_method IN ('automatic', 'admin')),
  retrieved_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(card_id, source_url, content_hash)
);

CREATE TABLE IF NOT EXISTS public.card_discovery_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  issuer text NOT NULL CHECK (length(trim(issuer)) BETWEEN 2 AND 120),
  proposed_product text CHECK (proposed_product IS NULL OR length(trim(proposed_product)) BETWEEN 2 AND 160),
  evidence jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(evidence) = 'object'),
  dedupe_key text NOT NULL CHECK (length(dedupe_key) BETWEEN 8 AND 256),
  status text NOT NULL DEFAULT 'queued' CHECK (
    status IN ('queued', 'discovering', 'resolved', 'review_required', 'rejected', 'failed')
  ),
  attempt_count integer NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
  next_retry_at timestamptz,
  failure_category text,
  resolved_card_id uuid REFERENCES public.card_catalog(id) ON DELETE SET NULL,
  review_item_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, dedupe_key)
);

CREATE INDEX IF NOT EXISTS idx_card_discovery_jobs_user_status
  ON public.card_discovery_jobs(user_id, status, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_card_discovery_jobs_retry
  ON public.card_discovery_jobs(status, next_retry_at)
  WHERE status IN ('queued', 'failed');

CREATE TABLE IF NOT EXISTS public.card_catalog_review_queue (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  discovery_job_id uuid NOT NULL UNIQUE REFERENCES public.card_discovery_jobs(id) ON DELETE CASCADE,
  proposed_fields jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(proposed_fields) = 'object'),
  source_evidence jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(source_evidence) = 'object'),
  existing_candidates jsonb NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(existing_candidates) = 'array'),
  validation_warnings jsonb NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(validation_warnings) = 'array'),
  confidence numeric(5,4) NOT NULL DEFAULT 0 CHECK (confidence BETWEEN 0 AND 1),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'merged', 'rejected')),
  reviewed_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  review_reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  reviewed_at timestamptz
);

ALTER TABLE public.card_discovery_jobs
  DROP CONSTRAINT IF EXISTS card_discovery_jobs_review_item_id_fkey;
ALTER TABLE public.card_discovery_jobs
  ADD CONSTRAINT card_discovery_jobs_review_item_id_fkey
  FOREIGN KEY (review_item_id) REFERENCES public.card_catalog_review_queue(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_card_catalog_review_queue_status
  ON public.card_catalog_review_queue(status, created_at);

CREATE TABLE IF NOT EXISTS public.card_catalog_review_audit (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  review_item_id uuid NOT NULL REFERENCES public.card_catalog_review_queue(id) ON DELETE CASCADE,
  actor_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  action text NOT NULL CHECK (action IN ('approve', 'merge', 'edit_approve', 'retry', 'reject')),
  details jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(details) = 'object'),
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.card_catalog_aliases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.card_catalog_provenance ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.card_discovery_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.card_catalog_review_queue ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.card_catalog_review_audit ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.card_catalog_aliases FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.card_catalog_provenance FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.card_discovery_jobs FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.card_catalog_review_queue FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.card_catalog_review_audit FROM PUBLIC, anon, authenticated;

GRANT ALL ON public.card_catalog_aliases TO service_role;
GRANT ALL ON public.card_catalog_provenance TO service_role;
GRANT ALL ON public.card_discovery_jobs TO service_role;
GRANT ALL ON public.card_catalog_review_queue TO service_role;
GRANT ALL ON public.card_catalog_review_audit TO service_role;

-- Preserve the existing catalog identity when it was imported under the
-- statement-specific label "Privilege Easy".
UPDATE public.card_catalog
SET card_name = 'Privilege',
    network = COALESCE(network, 'American Express'),
    card_url = COALESCE(
      card_url,
      'https://www.axis.bank.in/cards/credit-card/privilege-credit-card-with-unlimited-benefits'
    ),
    updated_at = now()
WHERE lower(trim(bank)) = 'axis bank'
  AND lower(trim(card_name)) = 'privilege easy'
  AND NOT EXISTS (
    SELECT 1 FROM public.card_catalog existing
    WHERE lower(trim(existing.bank)) = 'axis bank'
      AND lower(trim(existing.card_name)) = 'privilege'
  );

INSERT INTO public.card_catalog (bank, card_name, network, card_type, joining_fee, annual_fee, card_url)
SELECT
  'Axis Bank', 'Privilege', 'American Express', 'credit', 1500, 1500,
  'https://www.axis.bank.in/cards/credit-card/privilege-credit-card-with-unlimited-benefits'
WHERE NOT EXISTS (
  SELECT 1 FROM public.card_catalog
  WHERE lower(trim(bank)) = 'axis bank' AND lower(trim(card_name)) = 'privilege'
);

INSERT INTO public.card_catalog (bank, card_name, card_type, joining_fee, annual_fee, card_url)
SELECT
  'IndusInd Bank', 'EazyDiner Platinum', 'credit', 0, 0,
  'https://www.indusind.com/in/en/personal/cards/credit-card/eazydiner-platinum-credit-card.html'
WHERE NOT EXISTS (
  SELECT 1 FROM public.card_catalog
  WHERE lower(trim(bank)) = 'indusind bank'
    AND lower(trim(card_name)) = 'eazydiner platinum'
);

INSERT INTO public.card_catalog_aliases (card_id, alias, normalized_alias, evidence_type, source_url)
SELECT id, 'Amex Privilege', 'privilege', 'subject',
  'https://www.axis.bank.in/cards/credit-card/privilege-credit-card-with-unlimited-benefits'
FROM public.card_catalog
WHERE lower(trim(bank)) = 'axis bank' AND lower(trim(card_name)) = 'privilege'
ON CONFLICT (card_id, normalized_alias) DO NOTHING;

INSERT INTO public.card_catalog_aliases (card_id, alias, normalized_alias, evidence_type, source_url)
SELECT id, 'EazyDiner IndusInd Bank Platinum Credit Card', 'eazydinerplatinum', 'pdf_header',
  'https://www.indusind.com/in/en/personal/cards/credit-card/eazydiner-platinum-credit-card.html'
FROM public.card_catalog
WHERE lower(trim(bank)) = 'indusind bank' AND lower(trim(card_name)) = 'eazydiner platinum'
ON CONFLICT (card_id, normalized_alias) DO NOTHING;

INSERT INTO public.card_catalog_aliases (card_id, alias, normalized_alias, evidence_type, source_url)
SELECT id, 'White Reserve Credit Card', 'whitereserve', 'subject',
  'https://www.kotak.com/content/dam/Kotak/files/key-fact-statement/key-fact-statement-kfs-white-reserve.pdf'
FROM public.card_catalog
WHERE lower(trim(bank)) = 'kotak bank' AND lower(trim(card_name)) = 'white reserve'
ON CONFLICT (card_id, normalized_alias) DO NOTHING;

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
      ) ON CONFLICT (card_id, normalized_alias) DO NOTHING;
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
