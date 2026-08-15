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
  ADD COLUMN IF NOT EXISTS enriched_at timestamptz,
  ADD COLUMN IF NOT EXISTS operator_status text NOT NULL DEFAULT 'new',
  ADD COLUMN IF NOT EXISTS qualification_score integer,
  ADD COLUMN IF NOT EXISTS operator_notes text,
  ADD COLUMN IF NOT EXISTS contacted_at timestamptz,
  ADD COLUMN IF NOT EXISTS invited_at timestamptz;

-- The original launch used `3-5` and `6+`; preserve those historical rows
-- while moving the public qualification taxonomy to the approved bands.
UPDATE public.waitlist
SET card_count = CASE card_count
  WHEN '3-5' THEN '3-6'
  WHEN '6+' THEN '7+'
  ELSE card_count
END
WHERE card_count IN ('3-5', '6+');

ALTER TABLE public.waitlist
  DROP CONSTRAINT IF EXISTS waitlist_card_count_check,
  ADD CONSTRAINT waitlist_card_count_check
    CHECK (card_count IN ('1-2', '3-6', '7+') OR card_count IS NULL),
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
  p_privacy_consent boolean DEFAULT false
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
  v_waitlist_id uuid;
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
  ON CONFLICT (email) DO NOTHING
  RETURNING id INTO v_waitlist_id;

  IF v_waitlist_id IS NULL THEN
    RETURN QUERY SELECT 'already_joined'::text, NULL::text;
    RETURN;
  END IF;

  RETURN QUERY SELECT 'joined'::text, v_token;
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
  v_updated integer;
BEGIN
  -- Treat an invalid or expired token as an ordinary unsuccessful update so
  -- callers cannot use this endpoint to learn whether a signup exists.
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
    marketing_consent_at = CASE
      WHEN p_marketing_consent THEN COALESCE(marketing_consent_at, now())
      ELSE marketing_consent_at
    END,
    enriched_at = now(),
    enrichment_token_hash = NULL
  WHERE enrichment_token_hash = v_token_hash;

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  RETURN v_updated = 1;
END;
$$;

REVOKE ALL ON FUNCTION public.join_waitlist(
  text, text, text, text, text, text, text, text, text, boolean
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.join_waitlist(
  text, text, text, text, text, text, text, text, text, boolean
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
  w.created_at,
  w.enriched_at,
  w.operator_status,
  w.qualification_score,
  w.operator_notes,
  w.contacted_at,
  w.invited_at,
  CASE
    WHEN w.card_count IS NULL
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
      + CASE WHEN w.marketing_consent_at IS NOT NULL THEN 5 ELSE 0 END
      + COALESCE(w.qualification_score, 0)
  END AS rank_score
FROM public.waitlist w
ORDER BY
  CASE
    WHEN w.card_count IS NULL
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
      + CASE WHEN w.marketing_consent_at IS NOT NULL THEN 5 ELSE 0 END
      + COALESCE(w.qualification_score, 0)
  END DESC,
  w.created_at ASC;

REVOKE ALL ON TABLE public.operator_waitlist_ranked FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.operator_waitlist_ranked TO service_role;
