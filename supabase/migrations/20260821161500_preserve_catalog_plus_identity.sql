BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

-- A visible plus sign is part of a product identity (for example AU Zenith+),
-- not punctuation. Normalize its common superscript form to the word "plus"
-- before the existing issuer/network/card-token projection. This keeps
-- Zenith and Zenith+ in separate catalog identity namespaces.
CREATE OR REPLACE FUNCTION public.normalize_card_catalog_product(_value text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SECURITY INVOKER
SET search_path = public, extensions, pg_temp
AS $$
  WITH prepared AS (
    SELECT regexp_replace(
      regexp_replace(coalesce(_value, ''), '[+⁺]', ' plus ', 'g'),
      '\mplus([[:space:]]+plus)+\M', 'plus', 'gi'
    ) AS value
  )
  SELECT lower(regexp_replace(
    regexp_replace(
      regexp_replace(
        trim(regexp_replace(value,
          '^(fees[[:space:]]+and[[:space:]]+charges[[:space:]]+for|terms[[:space:]]+and[[:space:]]+conditions[[:space:]]+for|benefits[[:space:]]+of)[[:space:]]+',
          '', 'i')),
        '\m(visa|master[[:space:]]*card|rupay|american[[:space:]]+express|amex|bank|credit|card|statement|your|the|for|club|axis|hdfc|icici|kotak|mahindra|indusind|hsbc|pnb|punjab|national|sbi|au)\M',
        ' ', 'gi'
      ),
      '([[:space:]]+credit)?[[:space:]]+card$', '', 'i'
    ),
    '[^a-zA-Z0-9]+', '', 'g'
  ))
  FROM prepared;
$$;

CREATE OR REPLACE FUNCTION public.normalize_card_catalog_family(_value text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SECURITY INVOKER
SET search_path = public, extensions, pg_temp
AS $$
  WITH prepared AS (
    SELECT regexp_replace(
      regexp_replace(coalesce(_value, ''), '[+⁺]', ' plus ', 'g'),
      '\mplus([[:space:]]+plus)+\M', 'plus', 'gi'
    ) AS value
  )
  SELECT lower(regexp_replace(
    regexp_replace(
      regexp_replace(
        trim(regexp_replace(value,
          '^(fees[[:space:]]+and[[:space:]]+charges[[:space:]]+for|terms[[:space:]]+and[[:space:]]+conditions[[:space:]]+for|benefits[[:space:]]+of)[[:space:]]+',
          '', 'i')),
        '\m(visa|master[[:space:]]*card|rupay|american[[:space:]]+express|amex|bank|credit|card|statement|your|the|for|club|axis|hdfc|icici|kotak|mahindra|indusind|hsbc|pnb|punjab|national|sbi|au|world[[:space:]-]+elite|infinite|signature|world|platinum|gold|select|classic)\M',
        ' ', 'gi'
      ),
      '([[:space:]]+credit)?[[:space:]]+card$', '', 'i'
    ),
    '[^a-zA-Z0-9]+', '', 'g'
  ))
  FROM prepared;
$$;

REVOKE ALL ON FUNCTION public.normalize_card_catalog_product(text)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.normalize_card_catalog_family(text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.normalize_card_catalog_product(text)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.normalize_card_catalog_family(text)
  TO service_role;

DO $preserve_catalog_plus_identity_apply$
BEGIN
  IF public.normalize_card_catalog_product('Zenith+') <> 'zenithplus'
     OR public.normalize_card_catalog_product('Zenith⁺ Plus Credit Card') <> 'zenithplus'
     OR public.normalize_card_catalog_product('Zenith Credit Card') <> 'zenith'
     OR public.normalize_card_catalog_family('Zenith+') <> 'zenithplus'
     OR public.normalize_card_catalog_family('Zenith Credit Card') <> 'zenith' THEN
    RAISE EXCEPTION 'catalog plus identity normalization is inconsistent';
  END IF;

  IF has_function_privilege(
       'authenticated',
       'public.normalize_card_catalog_product(text)',
       'EXECUTE'
     )
     OR has_function_privilege(
       'authenticated',
       'public.normalize_card_catalog_family(text)',
       'EXECUTE'
     )
     OR NOT has_function_privilege(
       'service_role',
       'public.normalize_card_catalog_product(text)',
       'EXECUTE'
     )
     OR NOT has_function_privilege(
       'service_role',
       'public.normalize_card_catalog_family(text)',
       'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'catalog plus identity helper grants are inconsistent';
  END IF;
END
$preserve_catalog_plus_identity_apply$;

COMMIT;
