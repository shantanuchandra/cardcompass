SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

-- The installed Task 7 implementation stripped characters before lowercasing,
-- so title-cased values such as Visa normalized to "isa" and conflicted with
-- the same strong network carried in a card name. Normalize case first.
CREATE OR REPLACE FUNCTION public.normalize_card_catalog_network(_value text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SECURITY INVOKER
SET search_path = public, extensions, pg_temp
AS $$
  SELECT CASE
    WHEN regexp_replace(lower(trim(coalesce(_value, ''))), '[^a-z0-9]+', '', 'g')
      IN ('mastercard', 'master') THEN 'mastercard'
    WHEN regexp_replace(lower(trim(coalesce(_value, ''))), '[^a-z0-9]+', '', 'g')
      IN ('americanexpress', 'amex') THEN 'americanexpress'
    WHEN regexp_replace(lower(trim(coalesce(_value, ''))), '[^a-z0-9]+', '', 'g') = 'visa'
      THEN 'visa'
    WHEN regexp_replace(lower(trim(coalesce(_value, ''))), '[^a-z0-9]+', '', 'g') = 'rupay'
      THEN 'rupay'
    ELSE nullif(
      regexp_replace(lower(trim(coalesce(_value, ''))), '[^a-z0-9]+', '', 'g'),
      ''
    )
  END;
$$;

REVOKE ALL ON FUNCTION public.normalize_card_catalog_network(text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.normalize_card_catalog_network(text)
  TO service_role;

DO $$
BEGIN
  IF public.normalize_card_catalog_network('Visa') IS DISTINCT FROM 'visa'
     OR public.normalize_card_catalog_network('VISA') IS DISTINCT FROM 'visa'
     OR public.normalize_card_catalog_network('MasterCard') IS DISTINCT FROM 'mastercard'
     OR public.normalize_card_catalog_network('MASTERCARD') IS DISTINCT FROM 'mastercard'
     OR public.normalize_card_catalog_network('American Express')
       IS DISTINCT FROM 'americanexpress'
     OR public.normalize_card_catalog_network('RuPay') IS DISTINCT FROM 'rupay'
     OR public.card_catalog_effective_network(
       'Visa', 'Task11 Visa Infinite Credit Card', 'Axis Bank'
     ) IS DISTINCT FROM 'visa' THEN
    RAISE EXCEPTION 'card_catalog_network_case_normalization_failed';
  END IF;
END;
$$;
