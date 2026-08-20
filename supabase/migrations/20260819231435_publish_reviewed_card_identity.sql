BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '120s';
SET LOCAL TIME ZONE 'UTC';

-- URL hashes are identity keys in card_catalog_url_keys. Provenance is an
-- append-only observation history, so repeated content observations for one
-- resource must not be collapsed by the legacy per-column unique indexes.
DROP INDEX IF EXISTS public.idx_card_catalog_provenance_submitted_url_hash;
DROP INDEX IF EXISTS public.idx_card_catalog_provenance_final_url_hash;
CREATE INDEX idx_card_catalog_provenance_submitted_url_hash
  ON public.card_catalog_provenance(submitted_url_hash)
  WHERE submitted_url_hash IS NOT NULL;
CREATE INDEX idx_card_catalog_provenance_final_url_hash
  ON public.card_catalog_provenance(final_url_hash)
  WHERE final_url_hash IS NOT NULL;
ALTER TABLE public.card_catalog_provenance
  DROP CONSTRAINT IF EXISTS card_catalog_provenance_card_id_source_url_content_hash_key;
CREATE INDEX IF NOT EXISTS idx_card_catalog_provenance_card_source_content
  ON public.card_catalog_provenance(card_id, source_url, content_hash);

ALTER TABLE public.card_catalog_review_audit
  DROP CONSTRAINT IF EXISTS card_catalog_review_audit_action_check;
ALTER TABLE public.card_catalog_review_audit
  ADD CONSTRAINT card_catalog_review_audit_action_check CHECK (
    action IN (
      'approve', 'merge', 'edit_approve', 'retry', 'reject',
      'mark_discontinued', 'reactivate'
    )
  );

-- Retention is structural: deleting a user de-identifies statement discovery,
-- while canonical identity/history parents cannot cascade-delete evidence.
DROP INDEX IF EXISTS public.idx_card_discovery_jobs_service_dedupe_key;
CREATE UNIQUE INDEX idx_card_discovery_jobs_service_dedupe_key
  ON public.card_discovery_jobs(discovery_source, dedupe_key)
  WHERE user_id IS NULL AND discovery_source = 'issuer_crawl';

ALTER TABLE public.card_discovery_jobs
  DROP CONSTRAINT IF EXISTS card_discovery_jobs_user_id_fkey;
ALTER TABLE public.card_discovery_jobs
  ADD CONSTRAINT card_discovery_jobs_user_id_fkey
  FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE public.card_catalog_review_queue
  DROP CONSTRAINT IF EXISTS card_catalog_review_queue_discovery_job_id_fkey;
ALTER TABLE public.card_catalog_review_queue
  ADD CONSTRAINT card_catalog_review_queue_discovery_job_id_fkey
  FOREIGN KEY (discovery_job_id) REFERENCES public.card_discovery_jobs(id)
  ON DELETE RESTRICT;

ALTER TABLE public.card_catalog_review_audit
  DROP CONSTRAINT IF EXISTS card_catalog_review_audit_review_item_id_fkey;
ALTER TABLE public.card_catalog_review_audit
  ADD CONSTRAINT card_catalog_review_audit_review_item_id_fkey
  FOREIGN KEY (review_item_id) REFERENCES public.card_catalog_review_queue(id)
  ON DELETE RESTRICT;

ALTER TABLE public.card_catalog_aliases
  DROP CONSTRAINT IF EXISTS card_catalog_aliases_card_id_fkey;
ALTER TABLE public.card_catalog_aliases
  ADD CONSTRAINT card_catalog_aliases_card_id_fkey
  FOREIGN KEY (card_id) REFERENCES public.card_catalog(id) ON DELETE RESTRICT;

ALTER TABLE public.card_catalog_provenance
  DROP CONSTRAINT IF EXISTS card_catalog_provenance_card_id_fkey;
ALTER TABLE public.card_catalog_provenance
  ADD CONSTRAINT card_catalog_provenance_card_id_fkey
  FOREIGN KEY (card_id) REFERENCES public.card_catalog(id) ON DELETE RESTRICT;

ALTER TABLE public.card_catalog_url_keys
  DROP CONSTRAINT IF EXISTS card_catalog_url_keys_card_id_fkey;
ALTER TABLE public.card_catalog_url_keys
  ADD CONSTRAINT card_catalog_url_keys_card_id_fkey
  FOREIGN KEY (card_id) REFERENCES public.card_catalog(id) ON DELETE RESTRICT;

ALTER TABLE public.card_catalog_enrichment_jobs
  DROP CONSTRAINT IF EXISTS card_catalog_enrichment_jobs_card_id_fkey;
ALTER TABLE public.card_catalog_enrichment_jobs
  ADD CONSTRAINT card_catalog_enrichment_jobs_card_id_fkey
  FOREIGN KEY (card_id) REFERENCES public.card_catalog(id) ON DELETE RESTRICT;

CREATE OR REPLACE FUNCTION public.decode_card_resource_component(_value text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SECURITY INVOKER
SET search_path = public, extensions, pg_temp
AS $$
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
$$;

CREATE OR REPLACE FUNCTION public.normalize_card_resource_path(_path text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SECURITY INVOKER
SET search_path = public, extensions, pg_temp
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

CREATE OR REPLACE FUNCTION public.canonical_card_resource_url(_url text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SECURITY INVOKER
SET search_path = public, extensions, pg_temp
AS $$
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
$$;

CREATE OR REPLACE FUNCTION public.card_catalog_source_matches_issuer(
  _issuer text,
  _url text
) RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
SECURITY INVOKER
SET search_path = public, extensions, pg_temp
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

CREATE OR REPLACE FUNCTION public.card_enrichment_enqueue_catalog_eligible(
  _card_id uuid,
  _input_issuer text,
  _input_url text,
  _input_url_hash text,
  _card_bank text,
  _card_url text,
  _card_type text,
  _is_discontinued boolean,
  _has_active_cardholder boolean,
  _has_unresolved_identity boolean
) RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
SECURITY INVOKER
SET search_path = public, extensions, pg_temp
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

CREATE OR REPLACE FUNCTION public.normalize_card_catalog_product(_value text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SECURITY INVOKER
SET search_path = public, extensions, pg_temp
AS $$
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
$$;

CREATE OR REPLACE FUNCTION public.normalize_card_catalog_family(_value text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SECURITY INVOKER
SET search_path = public, extensions, pg_temp
AS $$
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
$$;

CREATE OR REPLACE FUNCTION public.normalize_card_catalog_network(_value text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SECURITY INVOKER
SET search_path = public, extensions, pg_temp
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

CREATE OR REPLACE FUNCTION public.normalize_card_catalog_tier(_value text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SECURITY INVOKER
SET search_path = public, extensions, pg_temp
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

CREATE OR REPLACE FUNCTION public.card_catalog_effective_network(
  _network text,
  _card_name text,
  _issuer text
) RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SECURITY INVOKER
SET search_path = public, extensions, pg_temp
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

CREATE OR REPLACE FUNCTION public.card_catalog_json_contains_sensitive_url(
  _value jsonb
) RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
SECURITY INVOKER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  item record;
  scalar text;
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
  RETURN scalar ~ 'https?://[^/[:space:]<>"'']+@'
    OR scalar ~ '[?&](token|session|secret|password|passwd|credential|auth|signature|sig|key|code|state|nonce)='
    OR scalar ~ 'https?://[^[:space:]<>"'']+#[^[:space:]<>"'']*'
    OR scalar ~ '%3f[^[:space:]]*(token|session|secret|password|credential|auth|signature|nonce)%3d'
    OR scalar ~ '%40[^[:space:]]*(%2f|/|%3f|\?)';
END;
$$;

CREATE OR REPLACE FUNCTION public.card_catalog_json_envelope_valid(
  _value jsonb,
  _depth integer DEFAULT 0
) RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
SECURITY INVOKER
SET search_path = public, extensions, pg_temp
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

CREATE OR REPLACE FUNCTION public.catalog_lifecycle_semantic_observation(
  _value jsonb
) RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
SECURITY INVOKER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  result jsonb;
BEGIN
  IF _value IS NULL THEN RETURN 'null'::jsonb; END IF;
  IF jsonb_typeof(_value) = 'object' THEN
    SELECT coalesce(jsonb_object_agg(entry.key,
      public.catalog_lifecycle_semantic_observation(entry.value)
      ORDER BY entry.key), '{}'::jsonb)
    INTO result
    FROM jsonb_each(_value) AS entry
    WHERE entry.key NOT IN (
      'retrieved_at', 'attempted_at', 'observed_at', 'transport',
      'duration_ms', 'retry_after_ms', 'request_started_at',
      'request_completed_at'
    );
    RETURN result;
  ELSIF jsonb_typeof(_value) = 'array' THEN
    SELECT coalesce(jsonb_agg(
      public.catalog_lifecycle_semantic_observation(entry.value)
      ORDER BY entry.ordinality
    ), '[]'::jsonb)
    INTO result
    FROM jsonb_array_elements(_value) WITH ORDINALITY AS entry(value, ordinality);
    RETURN result;
  END IF;
  RETURN _value;
END;
$$;

CREATE OR REPLACE FUNCTION public.append_catalog_observation_history(
  _history jsonb,
  _entry jsonb
) RETURNS jsonb
LANGUAGE sql
IMMUTABLE
SECURITY INVOKER
SET search_path = public, extensions, pg_temp
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

CREATE OR REPLACE FUNCTION public.resolve_card_catalog_identity(
  _issuer text,
  _card_name text,
  _network text,
  _source_url text,
  _submitted_url_hash text,
  _final_url_hash text
) RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, extensions, pg_temp
AS $$
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
$$;

CREATE OR REPLACE FUNCTION public.adopt_reviewed_card_enrichment_source(
  _card_id uuid,
  _issuer text,
  _canonical_url text,
  _final_url_hash text,
  _content_hash text,
  _parser_version text
) RETURNS TABLE (
  enqueued_count integer,
  existing_v6_job_count integer,
  adopted_count integer
)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, extensions, pg_temp
AS $$
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
$$;

-- A reviewed page move changes only the source identity of the same recurring
-- observation job. Do not let that source-only update reset its existing due
-- clock; all terminal state changes still pass through the Task 6 scheduler.
DROP TRIGGER IF EXISTS schedule_terminal_card_enrichment_observation
  ON public.card_catalog_enrichment_jobs;
CREATE TRIGGER schedule_terminal_card_enrichment_observation
BEFORE INSERT OR UPDATE OF status, next_retry_at, result_summary,
  failure_category, parser_version, run_mode, staging_id, card_id
ON public.card_catalog_enrichment_jobs
FOR EACH ROW EXECUTE FUNCTION public.schedule_terminal_card_enrichment_observation();

CREATE OR REPLACE FUNCTION public.card_catalog_baseline_matches(
  _baseline jsonb,
  _card_id uuid,
  _card_name text,
  _network text,
  _annual_fee numeric,
  _joining_fee numeric,
  _apr numeric,
  _card_url text,
  _is_discontinued boolean,
  _updated_at timestamptz
) RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
SECURITY INVOKER
SET search_path = public, extensions, pg_temp
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

CREATE OR REPLACE FUNCTION public.stage_card_catalog_lifecycle_review(
  _card_id uuid,
  _suggested_action text,
  _source_observation jsonb,
  _source_url text,
  _source_url_hash text,
  _content_hash text,
  _parser_version text
) RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, extensions, pg_temp
AS $$
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
    (catalog_baseline - 'version_observed_at')::text || ':' ||
    lower(_source_url_hash) || ':' || coalesce(lower(_content_hash), '') ||
    ':' || source_observation_semantic_hash,
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
$$;

CREATE OR REPLACE FUNCTION public.publish_card_catalog_identity(
  _discovery_job_id uuid,
  _review_item_id uuid,
  _actor_id uuid,
  _action text,
  _reviewed_fields jsonb,
  _merge_card_id uuid,
  _reason text,
  _parser_version text
) RETURNS TABLE (card_id uuid, job_id uuid, resulting_status text)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  observed_job public.card_discovery_jobs%ROWTYPE;
  observed_review public.card_catalog_review_queue%ROWTYPE;
  job_row public.card_discovery_jobs%ROWTYPE;
  review_row public.card_catalog_review_queue%ROWTYPE;
  card_row public.card_catalog%ROWTYPE;
  fields jsonb := coalesce(_reviewed_fields, '{}'::jsonb);
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
    IF fields = '{}'::jsonb THEN fields := review_row.proposed_fields; END IF;
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
  IF _action IN ('edit_approve', 'mark_discontinued', 'reactivate')
     AND jsonb_typeof(fields->'catalog_baseline') IS DISTINCT FROM 'object' THEN
    RAISE EXCEPTION 'catalog_baseline_required';
  END IF;
  IF _action IN ('edit_approve', 'mark_discontinued', 'reactivate')
     AND fields->'catalog_baseline' IS DISTINCT FROM
       review_row.proposed_fields->'catalog_baseline' THEN
    RAISE EXCEPTION 'stale_catalog_baseline';
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
        AND review_row.status = 'pending' AND job_row.status = 'queued')
      OR (_action = 'reject'
        AND review_row.status = 'rejected' AND job_row.status = 'rejected')
    ) THEN
      -- Exact current state returns without duplicate audit/timestamp mutation.
      card_id := job_row.resolved_card_id;
      job_id := job_row.id;
      resulting_status := CASE WHEN _action = 'retry' THEN 'queued' ELSE 'rejected' END;
      RETURN NEXT;
      RETURN;
    END IF;
    IF (_action = 'reject' AND review_row.status <> 'pending')
       OR (_action = 'retry' AND review_row.status NOT IN ('pending', 'rejected'))
       OR review_row.proposed_fields IS DISTINCT FROM observed_review.proposed_fields
       OR review_row.source_evidence IS DISTINCT FROM observed_review.source_evidence
       OR job_row.issuer IS DISTINCT FROM observed_job.issuer
       OR job_row.proposed_product IS DISTINCT FROM observed_job.proposed_product
       OR job_row.evidence IS DISTINCT FROM observed_job.evidence THEN
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
      WHERE id = review_row.id;
      UPDATE public.card_discovery_jobs SET status = 'queued',
        review_item_id = review_row.id,
        failure_category = NULL, next_retry_at = statement_timestamp(),
        updated_at = statement_timestamp() WHERE id = job_row.id;
      resulting_status := 'queued';
    ELSE
      UPDATE public.card_catalog_review_queue SET status = 'rejected',
        reviewed_by = _actor_id, review_reason = _reason,
        reviewed_at = statement_timestamp(), updated_at = statement_timestamp()
      WHERE id = review_row.id;
      UPDATE public.card_discovery_jobs SET status = 'rejected',
        next_retry_at = NULL, updated_at = statement_timestamp()
      WHERE id = job_row.id;
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
      AND latest_job.evidence->>'card_id' = resolved_card_id::text
      AND latest_job.evidence ? 'lifecycle_state'
    ORDER BY nullif(latest_job.evidence->>'lifecycle_observed_at', '')::timestamptz DESC,
      latest_job.created_at DESC, latest_job.id DESC
    LIMIT 1
    FOR UPDATE;
    IF latest_lifecycle_job_id IS DISTINCT FROM job_row.id
       OR latest_lifecycle_state IS DISTINCT FROM CASE
         WHEN _action = 'mark_discontinued' THEN 'discontinued' ELSE 'active' END THEN
      RAISE EXCEPTION 'stale_catalog_lifecycle_review';
    END IF;
  END IF;

  catalog_baseline := fields->'catalog_baseline';
  IF _action IN ('edit_approve', 'mark_discontinued', 'reactivate')
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
      ) ON CONFLICT (card_id, normalized_alias) DO NOTHING;
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
          ) ON CONFLICT (card_id, normalized_alias) DO NOTHING;
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
        AND exact_observation.content_hash = publish_card_catalog_identity.content_hash
        AND exact_observation.retrieved_at = publish_card_catalog_identity.retrieved_at
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
    resolved_card_id = publish_card_catalog_identity.resolved_card_id,
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
$$;

CREATE OR REPLACE FUNCTION public.review_card_catalog_discovery(
  _review_item_id uuid,
  _actor_id uuid,
  _action text,
  _proposed_fields jsonb DEFAULT NULL,
  _merge_card_id uuid DEFAULT NULL,
  _reason text DEFAULT NULL
) RETURNS TABLE (card_id uuid, job_id uuid, resulting_status text)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, extensions, pg_temp
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
    coalesce(_proposed_fields, '{}'::jsonb), _merge_card_id, _reason,
    'benefits-v6'
  ) AS published;
END;
$$;

CREATE OR REPLACE FUNCTION public.terminalize_calculator_review_rows(
  _actor_id uuid,
  _limit integer DEFAULT 100
) RETURNS integer
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  calculator_review_terminal record;
  transitioned integer := 0;
BEGIN
  IF _actor_id IS NULL OR _limit NOT BETWEEN 1 AND 1000 THEN
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
      AND lower(coalesce(
        review.proposed_fields->>'official_url',
        review.source_evidence->>'official_url', ''
      )) LIKE '%calculator%'
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

-- Compatibility for the older catalog-entry queue. It creates durable review
-- artifacts, delegates publication, and retains the staging row as audit.
CREATE OR REPLACE FUNCTION public.approve_catalog_entry_request(
  _staging_id uuid,
  _reviewed_by uuid
) RETURNS TABLE (card_id uuid, bank_name text, card_name text, source_url text)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, extensions, pg_temp
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
    discovery_id, review_id, _reviewed_by, 'approve', fields,
    NULL, 'approved manual catalog request', 'benefits-v6'
  );
  UPDATE public.card_benefits_staging SET status = 'approved',
    card_id = published.card_id, reviewed_at = statement_timestamp(),
    reviewed_by = _reviewed_by, updated_at = statement_timestamp()
  WHERE id = _staging_id;
  RETURN QUERY SELECT published.card_id, fields->>'issuer', fields->>'cardName', staging_row.source_url;
END;
$$;

REVOKE ALL ON FUNCTION public.decode_card_resource_component(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.normalize_card_resource_path(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.canonical_card_resource_url(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.card_catalog_source_matches_issuer(text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.card_enrichment_enqueue_catalog_eligible(uuid, text, text, text, text, text, text, boolean, boolean, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.normalize_card_catalog_product(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.normalize_card_catalog_family(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.normalize_card_catalog_network(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.normalize_card_catalog_tier(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.card_catalog_effective_network(text, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.card_catalog_json_contains_sensitive_url(jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.card_catalog_json_envelope_valid(jsonb, integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.catalog_lifecycle_semantic_observation(jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.append_catalog_observation_history(jsonb, jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.resolve_card_catalog_identity(text, text, text, text, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.adopt_reviewed_card_enrichment_source(uuid, text, text, text, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.card_catalog_baseline_matches(jsonb, uuid, text, text, numeric, numeric, numeric, text, boolean, timestamptz) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.stage_card_catalog_lifecycle_review(uuid, text, jsonb, text, text, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.publish_card_catalog_identity(uuid, uuid, uuid, text, jsonb, uuid, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.review_card_catalog_discovery(uuid, uuid, text, jsonb, uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.terminalize_calculator_review_rows(uuid, integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.approve_catalog_entry_request(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.create_or_get_card_catalog(
  text, text, text, text, numeric, numeric, numeric
) FROM service_role;

GRANT EXECUTE ON FUNCTION public.decode_card_resource_component(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.normalize_card_resource_path(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.canonical_card_resource_url(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.card_catalog_source_matches_issuer(text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.card_enrichment_enqueue_catalog_eligible(uuid, text, text, text, text, text, text, boolean, boolean, boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public.normalize_card_catalog_product(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.normalize_card_catalog_family(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.normalize_card_catalog_network(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.normalize_card_catalog_tier(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.card_catalog_effective_network(text, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.card_catalog_json_contains_sensitive_url(jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.card_catalog_json_envelope_valid(jsonb, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.catalog_lifecycle_semantic_observation(jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.append_catalog_observation_history(jsonb, jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.resolve_card_catalog_identity(text, text, text, text, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.adopt_reviewed_card_enrichment_source(uuid, text, text, text, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.card_catalog_baseline_matches(jsonb, uuid, text, text, numeric, numeric, numeric, text, boolean, timestamptz) TO service_role;
GRANT EXECUTE ON FUNCTION public.stage_card_catalog_lifecycle_review(uuid, text, jsonb, text, text, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.publish_card_catalog_identity(uuid, uuid, uuid, text, jsonb, uuid, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.review_card_catalog_discovery(uuid, uuid, text, jsonb, uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.terminalize_calculator_review_rows(uuid, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.approve_catalog_entry_request(uuid, uuid) TO service_role;

DO $publication_lock_order_assertions$
DECLARE
  publication_definition text;
  adoption_definition text;
  resolver_definition text;
BEGIN
  IF to_regprocedure('public.resolve_card_catalog_identity(text,text,text,text,text,text)') IS NULL
     OR to_regprocedure('public.normalize_card_catalog_family(text)') IS NULL
     OR to_regprocedure('public.publish_card_catalog_identity(uuid,uuid,uuid,text,jsonb,uuid,text,text)') IS NULL
     OR to_regprocedure('public.review_card_catalog_discovery(uuid,uuid,text,jsonb,uuid,text)') IS NULL
     OR to_regprocedure('public.adopt_reviewed_card_enrichment_source(uuid,text,text,text,text,text)') IS NULL THEN
    RAISE EXCEPTION 'publication_signature_assertion_failed';
  END IF;
  SELECT pg_get_functiondef(
    'public.publish_card_catalog_identity(uuid,uuid,uuid,text,jsonb,uuid,text,text)'::regprocedure
  ) INTO publication_definition;
  SELECT pg_get_functiondef(
    'public.adopt_reviewed_card_enrichment_source(uuid,text,text,text,text,text)'::regprocedure
  ) INTO adoption_definition;
  SELECT pg_get_functiondef(
    'public.resolve_card_catalog_identity(text,text,text,text,text,text)'::regprocedure
  ) INTO resolver_definition;
  IF strpos(publication_definition, 'card_catalog_publication:job:') = 0
     OR strpos(publication_definition, 'card_benefit_enrichment_identity:') = 0
     OR strpos(publication_definition, 'FOR UPDATE') = 0
     OR strpos(adoption_definition, 'card_benefit_enrichment_identity:') = 0
     OR strpos(adoption_definition, 'reviewed_enrichment_source_busy') = 0
     OR strpos(publication_definition, 'card_catalog_publication:job:') >=
       strpos(publication_definition, 'public.resolve_card_catalog_identity(')
     OR strpos(publication_definition, 'public.resolve_card_catalog_identity(') >=
       strpos(publication_definition, 'card_benefit_enrichment_identity:')
     OR strpos(resolver_definition, 'least(lower(_submitted_url_hash)') >=
       strpos(resolver_definition, 'greatest(lower(_submitted_url_hash)')
     OR strpos(resolver_definition, 'greatest(lower(_submitted_url_hash)') >=
       strpos(resolver_definition, 'card_catalog_identity:') THEN
    RAISE EXCEPTION 'publication_lock_order_assertion_failed';
  END IF;
END;
$publication_lock_order_assertions$;

DO $publish_reviewed_card_identity_assertions$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc AS function_row
    JOIN pg_namespace AS namespace ON namespace.oid = function_row.pronamespace
    WHERE namespace.nspname = 'public'
      AND function_row.proname = 'publish_card_catalog_identity'
      AND function_row.prosecdef = false
  ) THEN RAISE EXCEPTION 'publication_invoker_assertion_failed'; END IF;
  IF NOT has_function_privilege(
       'service_role',
       'public.publish_card_catalog_identity(uuid,uuid,uuid,text,jsonb,uuid,text,text)',
       'EXECUTE'
     )
     OR has_function_privilege(
       'authenticated',
       'public.publish_card_catalog_identity(uuid,uuid,uuid,text,jsonb,uuid,text,text)',
       'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'publication_grant_assertion_failed';
  END IF;
  IF strpos(pg_get_functiondef(
       'public.publish_card_catalog_identity(uuid,uuid,uuid,text,jsonb,uuid,text,text)'::regprocedure
     ), 'benefits-v5') > 0
     OR strpos(pg_get_functiondef(
       'public.adopt_reviewed_card_enrichment_source(uuid,text,text,text,text,text)'::regprocedure
     ), 'benefits-v5') > 0 THEN
    RAISE EXCEPTION 'benefits-v5_rollback_lane_changed';
  END IF;
  IF to_regprocedure('public.enqueue_card_benefit_enrichment_jobs(jsonb)') IS NULL THEN
    RAISE EXCEPTION 'benefits-v6_enqueue_boundary_missing';
  END IF;
  IF to_regprocedure('public.stage_card_catalog_lifecycle_review(uuid,text,jsonb,text,text,text,text)') IS NULL
     OR NOT has_function_privilege(
       'service_role',
       'public.stage_card_catalog_lifecycle_review(uuid,text,jsonb,text,text,text,text)',
       'EXECUTE'
     )
     OR has_function_privilege(
       'authenticated',
       'public.stage_card_catalog_lifecycle_review(uuid,text,jsonb,text,text,text,text)',
       'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'catalog_lifecycle_review_grant_assertion_failed';
  END IF;
END;
$publish_reviewed_card_identity_assertions$;

DO $card_resource_url_behavior_assertions$
DECLARE
  invalid_authority_rejected boolean := false;
BEGIN
  IF public.canonical_card_resource_url(
    'https://www.axis.bank.in/cards/./credit/../neo?%76ariant=gold&utm_medium=email#top'
  ) IS DISTINCT FROM 'https://www.axis.bank.in/cards/neo?%76ariant=gold' THEN
    RAISE EXCEPTION 'encoded_query_key_parity_assertion_failed';
  END IF;
  IF public.canonical_card_resource_url(
    'https://www.axis.bank.in/cards/%2e/credit/%2E%2e/neo'
  ) IS DISTINCT FROM 'https://www.axis.bank.in/cards/neo' THEN
    RAISE EXCEPTION 'dot_path_parity_assertion_failed';
  END IF;
  IF public.canonical_card_resource_url(
    'https://www.axis.bank.in/card?variant=gold&variant=platinum&lang=en'
  ) IS DISTINCT FROM
    'https://www.axis.bank.in/card?variant=gold&variant=platinum&lang=en' THEN
    RAISE EXCEPTION 'query_order_duplicate_parity_assertion_failed';
  END IF;
  BEGIN
    PERFORM public.canonical_card_resource_url(
      'https://www.axis.bank.in:invalid/card?variant=gold'
    );
  EXCEPTION WHEN OTHERS THEN
    invalid_authority_rejected := true;
  END;
  IF NOT invalid_authority_rejected THEN
    RAISE EXCEPTION 'invalid_authority_parity_assertion_failed';
  END IF;
END;
$card_resource_url_behavior_assertions$;

DO $card_catalog_variant_behavior_assertions$
BEGIN
  IF public.normalize_card_catalog_product(
       'Privilege Visa Infinite Credit Card'
     ) IS DISTINCT FROM 'privilegeinfinite'
     OR public.normalize_card_catalog_family(
       'Privilege Visa Infinite Credit Card'
     ) IS DISTINCT FROM 'privilege'
     OR public.normalize_card_catalog_tier(
       'Privilege Visa Infinite Credit Card'
     ) IS DISTINCT FROM 'infinite'
     OR public.normalize_card_catalog_product(
       'Privilege Mastercard World Elite Credit Card'
     ) IS DISTINCT FROM 'privilegeworldelite'
     OR public.normalize_card_catalog_family(
       'Privilege Mastercard World Elite Credit Card'
     ) IS DISTINCT FROM 'privilege'
     OR public.normalize_card_catalog_product(
       'Axis Bank Privilege Visa Infinite Credit Card'
     ) IS DISTINCT FROM 'privilegeinfinite' THEN
    RAISE EXCEPTION 'catalog_variant_normalization_assertion_failed';
  END IF;
END;
$card_catalog_variant_behavior_assertions$;

DO $catalog_baseline_behavior_assertions$
DECLARE
  baseline jsonb := jsonb_build_object(
    'card_id', '11111111-1111-4111-8111-111111111111'::uuid,
    'card_name', 'Privilege',
    'network', 'Visa',
    'annual_fee', 1500::numeric,
    'joining_fee', NULL,
    'apr', 42::numeric,
    'card_url', 'https://www.axis.bank.in/card?variant=infinite',
    'is_discontinued', false,
    'updated_at', '2026-08-20T00:00:00.000Z'::timestamptz
  );
BEGIN
  IF public.card_catalog_baseline_matches(
    baseline, '11111111-1111-4111-8111-111111111111', 'Privilege', 'Visa',
    1500, NULL, 42, 'https://www.axis.bank.in/card?variant=infinite', false,
    '2026-08-20T00:00:00.000Z'
  ) IS DISTINCT FROM true
  OR public.card_catalog_baseline_matches(
    baseline, '11111111-1111-4111-8111-111111111111', 'Privilege', 'Visa',
    1600, NULL, 42, 'https://www.axis.bank.in/card?variant=infinite', false,
    '2026-08-20T00:00:00.000Z'
  ) IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'pending_edit_baseline_assertion_failed';
  END IF;
  IF public.card_catalog_baseline_matches(
    baseline, '11111111-1111-4111-8111-111111111111', 'Privilege', 'Visa',
    1500, NULL, 42, 'https://www.axis.bank.in/card?variant=infinite', true,
    '2026-08-20T00:00:00.000Z'
  ) IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'pending_lifecycle_baseline_assertion_failed';
  END IF;
END;
$catalog_baseline_behavior_assertions$;

DO $task7_identity_hardening_assertions$
DECLARE
  publication_definition text := pg_get_functiondef(
    'public.publish_card_catalog_identity(uuid,uuid,uuid,text,jsonb,uuid,text,text)'::regprocedure
  );
  lifecycle_definition text := pg_get_functiondef(
    'public.stage_card_catalog_lifecycle_review(uuid,text,jsonb,text,text,text,text)'::regprocedure
  );
  rejected boolean := false;
  history jsonb;
BEGIN
  IF strpos(publication_definition, 'observe_existing_locked_revalidation') = 0
     OR strpos(publication_definition, 'card_catalog_publication:job:') >=
       strpos(publication_definition, 'observe_existing_locked_revalidation')
     OR strpos(publication_definition, 'observe_existing_locked_revalidation') >=
       strpos(publication_definition, 'public.resolve_card_catalog_identity(') THEN
    RAISE EXCEPTION 'observe_existing_locked_revalidation_assertion_failed';
  END IF;
  IF strpos(publication_definition, 'edit_old_identity_lock') = 0
     OR strpos(publication_definition, 'edit_new_identity_lock') = 0
     OR strpos(publication_definition, 'new_family_conflict') = 0
     OR strpos(publication_definition, 'least(edit_old_identity_lock') = 0
     OR strpos(publication_definition, 'greatest(edit_old_identity_lock') = 0 THEN
    RAISE EXCEPTION 'rename_dual_family_lock_assertion_failed';
  END IF;
  IF strpos(publication_definition, 'legacy_provenance_retrieved_at') = 0
     OR strpos(publication_definition, 'legacy_catalog_url_backfill') = 0
     OR strpos(publication_definition, 'statement_timestamp()') = 0 THEN
    RAISE EXCEPTION 'legacy_provenance_timestamp_assertion_failed';
  END IF;
  IF strpos(lifecycle_definition, 'observe_current') = 0
     OR strpos(lifecycle_definition, 'latest_lifecycle_job_id') = 0
     OR strpos(lifecycle_definition, 'source_observation_semantic_hash') = 0
     OR strpos(lifecycle_definition, 'append_catalog_observation_history') = 0
     OR strpos(lifecycle_definition, 'superseded_by_newer_lifecycle_observation') = 0
     OR strpos(publication_definition, 'stale_catalog_lifecycle_review') = 0 THEN
    RAISE EXCEPTION 'lifecycle_latest_evidence_assertion_failed';
  END IF;
  IF public.card_catalog_effective_network(
       NULL, 'Platinum Credit Card', 'American Express'
     ) IS DISTINCT FROM 'americanexpress'
     OR public.normalize_card_catalog_tier('American Express Platinum Card')
       IS DISTINCT FROM 'platinum' THEN
    RAISE EXCEPTION 'amex_tier_identity_assertion_failed';
  END IF;
  BEGIN
    PERFORM public.card_catalog_effective_network(
      'Visa', 'Privilege Mastercard Credit Card', 'Axis Bank'
    );
  EXCEPTION WHEN OTHERS THEN
    rejected := true;
  END;
  IF NOT rejected THEN
    RAISE EXCEPTION 'amex_tier_identity_assertion_failed';
  END IF;
  IF strpos(publication_definition, 'idempotent_retry_reject_replay') = 0
     OR strpos(publication_definition, 'replay_audit.actor_id') = 0
     OR strpos(publication_definition, 'review_row.status = ''rejected''') = 0 THEN
    RAISE EXCEPTION 'retry_reject_replay_assertion_failed';
  END IF;
  IF to_regprocedure('public.card_catalog_json_envelope_valid(jsonb,integer)') IS NULL
     OR to_regprocedure('public.card_catalog_json_contains_sensitive_url(jsonb)') IS NULL
     OR strpos(publication_definition, 'reviewed_field_allowlist') = 0
     OR strpos(publication_definition, 'unknown_reviewed_field') = 0
     OR NOT public.card_catalog_json_envelope_valid(
       jsonb_build_object('source_observation', jsonb_build_object('kind', 'exact')), 0
     )
     OR public.card_catalog_json_envelope_valid(
       jsonb_build_object('value', repeat('x', 2049)), 0
     )
     OR NOT public.card_catalog_json_contains_sensitive_url(
       to_jsonb('https://user@example.com/card'::text)
     ) THEN
    RAISE EXCEPTION 'reviewed_fields_envelope_assertion_failed';
  END IF;
  history := public.append_catalog_observation_history(
    jsonb_build_array(jsonb_build_object(
      'semantic_hash', repeat('a', 64), 'observed_at', '2026-08-20T00:00:00Z'
    )),
    jsonb_build_object(
      'semantic_hash', repeat('a', 64), 'observed_at', '2026-08-20T01:00:00Z'
    )
  );
  IF jsonb_array_length(history) <> 1
     OR history->0->>'observed_at' <> '2026-08-20T01:00:00Z' THEN
    RAISE EXCEPTION 'lifecycle_latest_evidence_assertion_failed';
  END IF;
  rejected := false;
  BEGIN
    PERFORM public.canonical_card_resource_url('https://www.axis.bank.in/card?');
  EXCEPTION WHEN OTHERS THEN rejected := true;
  END;
  IF NOT rejected THEN
    RAISE EXCEPTION 'empty_query_separator_parity_assertion_failed';
  END IF;
  rejected := false;
  BEGIN
    PERFORM public.canonical_card_resource_url(
      'https://www.axis.bank.in/card?variant=gold&'
    );
  EXCEPTION WHEN OTHERS THEN rejected := true;
  END;
  IF NOT rejected THEN
    RAISE EXCEPTION 'empty_query_separator_parity_assertion_failed';
  END IF;
END;
$task7_identity_hardening_assertions$;

COMMIT;
