-- Admin approval path for user-submitted catalog_entry staging rows.

CREATE INDEX IF NOT EXISTS idx_card_benefits_staging_catalog_entry_pending
  ON public.card_benefits_staging(status, (extracted_data->>'request_type'))
  WHERE card_id IS NULL AND status = 'pending';

CREATE OR REPLACE FUNCTION public.list_pending_catalog_entry_requests()
RETURNS TABLE (
  id uuid,
  source_url text,
  bank_name text,
  card_name text,
  requested_by uuid,
  created_at timestamptz,
  extracted_data jsonb
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
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

CREATE OR REPLACE FUNCTION public.approve_catalog_entry_request(
  _staging_id uuid,
  _reviewed_by uuid
) RETURNS TABLE (
  card_id uuid,
  bank_name text,
  card_name text,
  source_url text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  staging_row public.card_benefits_staging%ROWTYPE;
  resolved_card_id uuid;
  resolved_bank text;
  resolved_card text;
BEGIN
  IF _staging_id IS NULL THEN
    RAISE EXCEPTION 'staging_id is required';
  END IF;

  SELECT * INTO staging_row
  FROM public.card_benefits_staging
  WHERE id = _staging_id
    AND status = 'pending'
    AND card_id IS NULL
    AND extracted_data->>'request_type' = 'catalog_entry'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invalid or non-pending catalog entry request';
  END IF;

  resolved_bank := trim(staging_row.extracted_data->>'bank_name');
  resolved_card := trim(staging_row.extracted_data->>'card_name');

  IF length(resolved_bank) < 2 OR length(resolved_card) < 2
     OR staging_row.source_url IS NULL
     OR length(staging_row.source_url) = 0 THEN
    RAISE EXCEPTION 'Catalog entry request is missing required fields';
  END IF;

  SELECT cc.id INTO resolved_card_id
  FROM public.card_catalog cc
  WHERE lower(trim(cc.bank)) = lower(resolved_bank)
    AND lower(trim(cc.card_name)) = lower(resolved_card)
  ORDER BY cc.created_at ASC
  LIMIT 1;

  IF resolved_card_id IS NULL THEN
    INSERT INTO public.card_catalog (
      bank,
      card_name,
      card_url,
      card_type
    ) VALUES (
      resolved_bank,
      resolved_card,
      staging_row.source_url,
      'credit'
    )
    RETURNING id INTO resolved_card_id;
  ELSE
    UPDATE public.card_catalog
    SET card_url = COALESCE(card_url, staging_row.source_url),
        updated_at = now()
    WHERE id = resolved_card_id;
  END IF;

  UPDATE public.card_benefits_staging
  SET status = 'approved',
      card_id = resolved_card_id,
      reviewed_at = now(),
      reviewed_by = _reviewed_by,
      updated_at = now()
  WHERE id = _staging_id;

  RETURN QUERY
  SELECT resolved_card_id, resolved_bank, resolved_card, staging_row.source_url;
END;
$$;

CREATE OR REPLACE FUNCTION public.reject_catalog_entry_request(
  _staging_id uuid,
  _reviewed_by uuid
) RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
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
