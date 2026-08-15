-- Replace the original client-writable waitlist table with two deliberately
-- narrow public RPCs. Existing rows remain valid; all fields added here are
-- nullable so this migration is safe to apply after the original launch.
ALTER TABLE public.waitlist
  ADD COLUMN IF NOT EXISTS enrichment_token_hash text,
  ADD COLUMN IF NOT EXISTS primary_goal text,
  ADD COLUMN IF NOT EXISTS monthly_spend_band text,
  ADD COLUMN IF NOT EXISTS problem_detail text,
  ADD COLUMN IF NOT EXISTS top_cards text[],
  ADD COLUMN IF NOT EXISTS acquisition_source text,
  ADD COLUMN IF NOT EXISTS landing_variant text,
  ADD COLUMN IF NOT EXISTS utm_source text,
  ADD COLUMN IF NOT EXISTS utm_medium text,
  ADD COLUMN IF NOT EXISTS utm_campaign text,
  ADD COLUMN IF NOT EXISTS utm_term text,
  ADD COLUMN IF NOT EXISTS utm_content text,
  ADD COLUMN IF NOT EXISTS referrer_path text,
  ADD COLUMN IF NOT EXISTS privacy_consent_at timestamptz,
  ADD COLUMN IF NOT EXISTS marketing_consent_at timestamptz,
  ADD COLUMN IF NOT EXISTS marketing_consent_requested_at timestamptz,
  ADD COLUMN IF NOT EXISTS enriched_at timestamptz,
  ADD COLUMN IF NOT EXISTS operator_status text NOT NULL DEFAULT 'new',
  ADD COLUMN IF NOT EXISTS qualification_score integer,
  ADD COLUMN IF NOT EXISTS operator_notes text,
  ADD COLUMN IF NOT EXISTS contacted_at timestamptz,
  ADD COLUMN IF NOT EXISTS invited_at timestamptz;

-- Drop the historical check before rewriting its values; otherwise the
-- pre-upgrade constraint rejects the values intended for the new taxonomy.
ALTER TABLE public.waitlist
  DROP CONSTRAINT IF EXISTS waitlist_card_count_check;

-- The original launch used `3-5` and the ambiguous `6+`. Preserve that
-- ambiguity for requalification rather than asserting that it meant 7+.
UPDATE public.waitlist
SET card_count = CASE card_count
  WHEN '3-5' THEN '3-6'
  WHEN '6+' THEN 'legacy-6-plus'
  ELSE card_count
END
WHERE card_count IN ('3-5', '6+');

-- Case variants were distinct under the original UNIQUE(email) constraint.
-- Keep the earliest row (then the smallest UUID for a deterministic tie),
-- merge its earliest non-null values from the duplicate set, delete the
-- redundant rows, then normalize the surviving address before adding the
-- durable case-insensitive uniqueness index.
WITH ranked AS (
  SELECT
    w.*,
    first_value(w.id) OVER (
      PARTITION BY lower(btrim(w.email))
      ORDER BY w.created_at ASC, w.id ASC
    ) AS survivor_id
  FROM public.waitlist AS w
),
merged AS (
  SELECT
    survivor_id,
    min(created_at) AS created_at,
    (array_agg(name ORDER BY created_at ASC, id ASC)
      FILTER (WHERE name IS NOT NULL))[1] AS name,
    (array_agg(card_count ORDER BY created_at ASC, id ASC)
      FILTER (WHERE card_count IS NOT NULL))[1] AS card_count,
    (array_agg(primary_goal ORDER BY created_at ASC, id ASC)
      FILTER (WHERE primary_goal IS NOT NULL))[1] AS primary_goal,
    (array_agg(monthly_spend_band ORDER BY created_at ASC, id ASC)
      FILTER (WHERE monthly_spend_band IS NOT NULL))[1] AS monthly_spend_band,
    (array_agg(problem_detail ORDER BY created_at ASC, id ASC)
      FILTER (WHERE problem_detail IS NOT NULL))[1] AS problem_detail,
    (array_agg(top_cards ORDER BY created_at ASC, id ASC)
      FILTER (WHERE top_cards IS NOT NULL))[1] AS top_cards,
    (array_agg(acquisition_source ORDER BY created_at ASC, id ASC)
      FILTER (WHERE acquisition_source IS NOT NULL))[1] AS acquisition_source,
    (array_agg(landing_variant ORDER BY created_at ASC, id ASC)
      FILTER (WHERE landing_variant IS NOT NULL))[1] AS landing_variant,
    (array_agg(utm_source ORDER BY created_at ASC, id ASC)
      FILTER (WHERE utm_source IS NOT NULL))[1] AS utm_source,
    (array_agg(utm_medium ORDER BY created_at ASC, id ASC)
      FILTER (WHERE utm_medium IS NOT NULL))[1] AS utm_medium,
    (array_agg(utm_campaign ORDER BY created_at ASC, id ASC)
      FILTER (WHERE utm_campaign IS NOT NULL))[1] AS utm_campaign,
    (array_agg(utm_term ORDER BY created_at ASC, id ASC)
      FILTER (WHERE utm_term IS NOT NULL))[1] AS utm_term,
    (array_agg(utm_content ORDER BY created_at ASC, id ASC)
      FILTER (WHERE utm_content IS NOT NULL))[1] AS utm_content,
    (array_agg(referrer_path ORDER BY created_at ASC, id ASC)
      FILTER (WHERE referrer_path IS NOT NULL))[1] AS referrer_path,
    min(privacy_consent_at) AS privacy_consent_at,
    min(marketing_consent_at) AS marketing_consent_at,
    min(marketing_consent_requested_at) AS marketing_consent_requested_at,
    min(enriched_at) AS enriched_at,
    (array_agg(operator_status ORDER BY created_at ASC, id ASC))[1] AS operator_status,
    max(qualification_score) AS qualification_score,
    (array_agg(operator_notes ORDER BY created_at ASC, id ASC)
      FILTER (WHERE operator_notes IS NOT NULL))[1] AS operator_notes,
    min(contacted_at) AS contacted_at,
    min(invited_at) AS invited_at,
    (array_agg(enrichment_token_hash ORDER BY created_at ASC, id ASC)
      FILTER (WHERE enrichment_token_hash IS NOT NULL))[1] AS enrichment_token_hash
  FROM ranked
  GROUP BY survivor_id
)
UPDATE public.waitlist AS target
SET
  created_at = merged.created_at,
  name = merged.name,
  card_count = merged.card_count,
  primary_goal = merged.primary_goal,
  monthly_spend_band = merged.monthly_spend_band,
  problem_detail = merged.problem_detail,
  top_cards = merged.top_cards,
  acquisition_source = merged.acquisition_source,
  landing_variant = merged.landing_variant,
  utm_source = merged.utm_source,
  utm_medium = merged.utm_medium,
  utm_campaign = merged.utm_campaign,
  utm_term = merged.utm_term,
  utm_content = merged.utm_content,
  referrer_path = merged.referrer_path,
  privacy_consent_at = merged.privacy_consent_at,
  marketing_consent_at = merged.marketing_consent_at,
  marketing_consent_requested_at = merged.marketing_consent_requested_at,
  enriched_at = merged.enriched_at,
  operator_status = merged.operator_status,
  qualification_score = merged.qualification_score,
  operator_notes = merged.operator_notes,
  contacted_at = merged.contacted_at,
  invited_at = merged.invited_at,
  enrichment_token_hash = merged.enrichment_token_hash
FROM merged
WHERE target.id = merged.survivor_id;

WITH ranked AS (
  SELECT
    w.id,
    first_value(w.id) OVER (
      PARTITION BY lower(btrim(w.email))
      ORDER BY w.created_at ASC, w.id ASC
    ) AS survivor_id
  FROM public.waitlist AS w
)
DELETE FROM public.waitlist AS target
USING ranked
WHERE target.id = ranked.id
  AND ranked.id <> ranked.survivor_id;

UPDATE public.waitlist
SET email = lower(btrim(email));

CREATE UNIQUE INDEX IF NOT EXISTS waitlist_email_lower_key
  ON public.waitlist (lower(email));

ALTER TABLE public.waitlist
  ADD CONSTRAINT waitlist_card_count_check
    CHECK (card_count IN ('1-2', '3-6', '7+', 'legacy-6-plus') OR card_count IS NULL),
  ADD CONSTRAINT waitlist_primary_goal_check
    CHECK (
      primary_goal IN ('maximize_rewards', 'track_benefits', 'simplify_card_choices')
      OR primary_goal IS NULL
    ),
  ADD CONSTRAINT waitlist_monthly_spend_band_check
    CHECK (
      monthly_spend_band IN ('under-25k', '25k-50k', '50k-1l', '1l-plus')
      OR monthly_spend_band IS NULL
    ),
  ADD CONSTRAINT waitlist_problem_detail_check
    CHECK (char_length(problem_detail) <= 500 OR problem_detail IS NULL),
  ADD CONSTRAINT waitlist_top_cards_check
    CHECK (
      top_cards IS NULL
      OR cardinality(top_cards) <= 2
    ),
  ADD CONSTRAINT waitlist_operator_status_check
    CHECK (operator_status IN ('new', 'reviewing', 'qualified', 'not_a_fit', 'waitlisted', 'invited')),
  ADD CONSTRAINT waitlist_qualification_score_check
    CHECK (qualification_score BETWEEN 0 AND 100 OR qualification_score IS NULL);

CREATE UNIQUE INDEX IF NOT EXISTS waitlist_enrichment_token_hash_key
  ON public.waitlist (enrichment_token_hash)
  WHERE enrichment_token_hash IS NOT NULL;

-- Policies from the initial landing launch are no longer a public API. Keep
-- RLS enabled as a second guard, but remove every direct browser path.
ALTER TABLE public.waitlist ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "anon insert" ON public.waitlist;
DROP POLICY IF EXISTS "anon update own row" ON public.waitlist;
DROP POLICY IF EXISTS "anon select own" ON public.waitlist;
DROP POLICY IF EXISTS "authenticated insert" ON public.waitlist;
DROP POLICY IF EXISTS "authenticated select own" ON public.waitlist;
REVOKE ALL ON TABLE public.waitlist FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.waitlist TO service_role;

CREATE TABLE IF NOT EXISTS public.waitlist_public_attempts (
  email_hash text NOT NULL,
  window_started timestamptz NOT NULL,
  attempt_count integer NOT NULL DEFAULT 1,
  PRIMARY KEY (email_hash, window_started)
);
ALTER TABLE public.waitlist_public_attempts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.waitlist_public_attempts FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.join_waitlist(
  p_email text,
  p_source text DEFAULT NULL,
  p_utm_source text DEFAULT NULL,
  p_utm_medium text DEFAULT NULL,
  p_utm_campaign text DEFAULT NULL,
  p_utm_term text DEFAULT NULL,
  p_utm_content text DEFAULT NULL,
  p_referrer_path text DEFAULT NULL,
  p_landing_variant text DEFAULT NULL,
  p_privacy_consent boolean DEFAULT false,
  p_website text DEFAULT NULL
)
RETURNS TABLE (status text, enrichment_token text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_email text := lower(btrim(p_email));
  v_source text := nullif(btrim(p_source), '');
  v_utm_source text := nullif(btrim(p_utm_source), '');
  v_utm_medium text := nullif(btrim(p_utm_medium), '');
  v_utm_campaign text := nullif(btrim(p_utm_campaign), '');
  v_utm_term text := nullif(btrim(p_utm_term), '');
  v_utm_content text := nullif(btrim(p_utm_content), '');
  v_referrer_path text := nullif(btrim(p_referrer_path), '');
  v_landing_variant text := nullif(btrim(p_landing_variant), '');
  v_token text;
  v_token_hash text;
  v_email_hash text;
  v_window timestamptz := date_bin('15 minutes', now(), timestamptz '2001-01-01');
  v_attempt_count integer;
BEGIN
  IF v_email IS NULL
     OR char_length(v_email) NOT BETWEEN 3 AND 254
     OR v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' THEN
    RAISE EXCEPTION 'email must be a valid address' USING ERRCODE = '22023';
  END IF;

  IF p_privacy_consent IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'privacy consent is required' USING ERRCODE = '22023';
  END IF;

  IF (v_source IS NOT NULL AND v_source !~ '^[a-z0-9][a-z0-9_-]{0,63}$')
     OR (v_utm_source IS NOT NULL AND char_length(v_utm_source) > 100)
     OR (v_utm_medium IS NOT NULL AND char_length(v_utm_medium) > 100)
     OR (v_utm_campaign IS NOT NULL AND char_length(v_utm_campaign) > 150)
     OR (v_utm_term IS NOT NULL AND char_length(v_utm_term) > 150)
     OR (v_utm_content IS NOT NULL AND char_length(v_utm_content) > 150)
     OR (v_landing_variant IS NOT NULL AND v_landing_variant !~ '^[a-z0-9][a-z0-9_-]{0,63}$')
     OR (v_referrer_path IS NOT NULL AND (
       char_length(v_referrer_path) > 512 OR left(v_referrer_path, 1) <> '/'
     )) THEN
    RAISE EXCEPTION 'waitlist attribution is invalid' USING ERRCODE = '22023';
  END IF;

  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  v_token_hash := encode(extensions.digest(v_token, 'sha256'), 'hex');
  v_email_hash := encode(extensions.digest(v_email, 'sha256'), 'hex');

  INSERT INTO public.waitlist_public_attempts (email_hash, window_started, attempt_count)
  VALUES (v_email_hash, v_window, 1)
  ON CONFLICT (email_hash, window_started) DO UPDATE
    SET attempt_count = public.waitlist_public_attempts.attempt_count + 1
  RETURNING attempt_count INTO v_attempt_count;

  -- Honeypot and rate-limited calls keep the public success shape but cannot
  -- create or mutate a lead. The table stores only a one-way email hash.
  IF nullif(btrim(p_website), '') IS NOT NULL OR v_attempt_count > 5 THEN
    RETURN QUERY SELECT 'accepted'::text, v_token;
    RETURN;
  END IF;

  INSERT INTO public.waitlist (
    email,
    enrichment_token_hash,
    acquisition_source,
    landing_variant,
    utm_source,
    utm_medium,
    utm_campaign,
    utm_term,
    utm_content,
    referrer_path,
    privacy_consent_at
  ) VALUES (
    v_email,
    v_token_hash,
    v_source,
    v_landing_variant,
    v_utm_source,
    v_utm_medium,
    v_utm_campaign,
    v_utm_term,
    v_utm_content,
    v_referrer_path,
    now()
  )
  ON CONFLICT DO NOTHING;

  -- The token is deliberately a decoy when the normalized email already
  -- exists. The public response is identical in either case, preventing this
  -- endpoint from becoming a waitlist-membership oracle.
  RETURN QUERY SELECT 'accepted'::text, v_token;
END;
$$;

CREATE OR REPLACE FUNCTION public.enrich_waitlist(
  p_enrichment_token text,
  p_name text DEFAULT NULL,
  p_card_count text DEFAULT NULL,
  p_monthly_spend_band text DEFAULT NULL,
  p_primary_goal text DEFAULT NULL,
  p_problem_detail text DEFAULT NULL,
  p_top_cards text[] DEFAULT NULL,
  p_marketing_consent boolean DEFAULT false
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_token text := lower(btrim(p_enrichment_token));
  v_name text := nullif(btrim(p_name), '');
  v_card_count text := nullif(btrim(p_card_count), '');
  v_monthly_spend_band text := nullif(btrim(p_monthly_spend_band), '');
  v_primary_goal text := nullif(btrim(p_primary_goal), '');
  v_problem_detail text := nullif(btrim(p_problem_detail), '');
  v_top_cards text[];
  v_token_hash text;
BEGIN
  -- Reject malformed tokens without touching the table. Valid-shaped decoy
  -- and consumed tokens are handled below with the same public result.
  IF v_token IS NULL OR v_token !~ '^[0-9a-f]{64}$' THEN
    RETURN false;
  END IF;

  IF v_card_count IS NULL
     OR v_monthly_spend_band IS NULL
     OR v_primary_goal IS NULL THEN
    RAISE EXCEPTION 'card count, monthly spend, and primary goal are required'
      USING ERRCODE = '22023';
  END IF;

  IF (v_name IS NOT NULL AND char_length(v_name) > 100)
     OR v_card_count NOT IN ('1-2', '3-6', '7+')
     OR v_monthly_spend_band NOT IN ('under-25k', '25k-50k', '50k-1l', '1l-plus')
     OR v_primary_goal NOT IN (
       'maximize_rewards', 'track_benefits', 'simplify_card_choices'
     )
     OR (v_problem_detail IS NOT NULL AND char_length(v_problem_detail) > 500)
     OR (p_top_cards IS NOT NULL AND (
       cardinality(p_top_cards) > 2
       OR EXISTS (
         SELECT 1
         FROM unnest(p_top_cards) AS card_name
         WHERE card_name IS NULL
            OR char_length(btrim(card_name)) NOT BETWEEN 1 AND 100
       )
     )) THEN
    RAISE EXCEPTION 'waitlist enrichment is invalid' USING ERRCODE = '22023';
  END IF;

  IF p_top_cards IS NOT NULL THEN
    SELECT array_agg(btrim(card_name))
    INTO v_top_cards
    FROM unnest(p_top_cards) AS card_name;
  END IF;

  v_token_hash := encode(extensions.digest(v_token, 'sha256'), 'hex');

  UPDATE public.waitlist
  SET
    name = COALESCE(v_name, name),
    card_count = v_card_count,
    monthly_spend_band = v_monthly_spend_band,
    primary_goal = v_primary_goal,
    problem_detail = v_problem_detail,
    top_cards = v_top_cards,
    marketing_consent_requested_at = CASE
      WHEN p_marketing_consent THEN COALESCE(marketing_consent_requested_at, now())
      ELSE marketing_consent_requested_at
    END,
    enriched_at = now(),
    enrichment_token_hash = NULL
  WHERE enrichment_token_hash = v_token_hash;

  -- A valid-shaped decoy token from a duplicate join and a real, consumed
  -- token deliberately receive the same success-shaped response. Only a
  -- matching stored hash can mutate a row.
  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.join_waitlist(
  text, text, text, text, text, text, text, text, text, boolean, text
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.join_waitlist(
  text, text, text, text, text, text, text, text, text, boolean, text
) TO anon, authenticated;

REVOKE ALL ON FUNCTION public.enrich_waitlist(
  text, text, text, text, text, text, text[], boolean
)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.enrich_waitlist(
  text, text, text, text, text, text, text[], boolean
)
  TO anon, authenticated;

-- Operators access this from Supabase Studio/service-role only. The view is
-- security-invoker so its grant cannot bypass the table's service-role-only
-- policy, and it intentionally never exposes the token hash.
CREATE OR REPLACE VIEW public.operator_waitlist_ranked
WITH (security_invoker = true)
AS
SELECT
  w.id,
  w.email,
  w.name,
  w.card_count,
  w.monthly_spend_band,
  w.primary_goal,
  w.problem_detail,
  w.top_cards,
  w.acquisition_source,
  w.landing_variant,
  w.utm_source,
  w.utm_medium,
  w.utm_campaign,
  w.utm_term,
  w.utm_content,
  w.referrer_path,
  w.privacy_consent_at,
  w.marketing_consent_at,
  w.marketing_consent_requested_at,
  w.created_at,
  w.enriched_at,
  w.operator_status,
  w.qualification_score,
  w.operator_notes,
  w.contacted_at,
  w.invited_at,
  (w.card_count = 'legacy-6-plus') AS needs_requalification,
  CASE
    WHEN w.card_count IS NULL OR w.card_count = 'legacy-6-plus'
      OR w.monthly_spend_band IS NULL
      OR w.primary_goal IS NULL THEN 0
    ELSE
      CASE w.card_count
        WHEN '3-6' THEN 45
        WHEN '7+' THEN 30
        WHEN '1-2' THEN 15
      END
      + CASE w.monthly_spend_band
        WHEN '1l-plus' THEN 25
        WHEN '50k-1l' THEN 20
        WHEN '25k-50k' THEN 15
        WHEN 'under-25k' THEN 10
      END
      + CASE w.primary_goal
        WHEN 'maximize_rewards' THEN 20
        WHEN 'track_benefits' THEN 15
        WHEN 'simplify_card_choices' THEN 10
      END
      + COALESCE(w.qualification_score, 0)
  END AS rank_score
FROM public.waitlist w
ORDER BY
  CASE
    WHEN w.card_count IS NULL OR w.card_count = 'legacy-6-plus'
      OR w.monthly_spend_band IS NULL
      OR w.primary_goal IS NULL THEN 0
    ELSE
      CASE w.card_count
        WHEN '3-6' THEN 45
        WHEN '7+' THEN 30
        WHEN '1-2' THEN 15
      END
      + CASE w.monthly_spend_band
        WHEN '1l-plus' THEN 25
        WHEN '50k-1l' THEN 20
        WHEN '25k-50k' THEN 15
        WHEN 'under-25k' THEN 10
      END
      + CASE w.primary_goal
        WHEN 'maximize_rewards' THEN 20
        WHEN 'track_benefits' THEN 15
        WHEN 'simplify_card_choices' THEN 10
      END
      + COALESCE(w.qualification_score, 0)
  END DESC,
  w.created_at ASC;

REVOKE ALL ON TABLE public.operator_waitlist_ranked FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.operator_waitlist_ranked TO service_role;

CREATE OR REPLACE FUNCTION public.update_waitlist_operator(
  p_id uuid, p_status text, p_notes text DEFAULT NULL,
  p_operator_score integer DEFAULT NULL, p_contacted_at timestamptz DEFAULT NULL,
  p_invited_at timestamptz DEFAULT NULL
) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF p_status NOT IN ('new','reviewing','qualified','not_a_fit','waitlisted','invited')
     OR (p_operator_score IS NOT NULL AND p_operator_score NOT BETWEEN 0 AND 100)
     OR char_length(COALESCE(p_notes,'')) > 2000 THEN
    RAISE EXCEPTION 'operator update is invalid' USING ERRCODE = '22023';
  END IF;
  UPDATE public.waitlist SET operator_status=p_status,
    operator_notes=nullif(btrim(p_notes),''), qualification_score=p_operator_score,
    contacted_at=p_contacted_at, invited_at=p_invited_at WHERE id=p_id;
  RETURN FOUND;
END; $$;
REVOKE ALL ON FUNCTION public.update_waitlist_operator(uuid,text,text,integer,timestamptz,timestamptz)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.update_waitlist_operator(uuid,text,text,integer,timestamptz,timestamptz)
  TO service_role;
