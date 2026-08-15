-- Final public-waitlist launch hardening. This is forward-only for any
-- environment that rehearsed the earlier migration; production remains gated
-- on applying and behaviorally verifying this migration in staging first.
ALTER TABLE public.waitlist
  ADD COLUMN IF NOT EXISTS marketing_consent_requested_at timestamptz;

-- A public checkbox records intent only. Existing unverified timestamps are
-- downgraded to pending requests; a future verified-email workflow may set
-- marketing_consent_at after ownership confirmation.
UPDATE public.waitlist
SET marketing_consent_requested_at = COALESCE(marketing_consent_requested_at, marketing_consent_at),
    marketing_consent_at = NULL
WHERE marketing_consent_at IS NOT NULL;

ALTER TABLE public.waitlist DROP CONSTRAINT IF EXISTS waitlist_card_count_check;
ALTER TABLE public.waitlist ADD CONSTRAINT waitlist_card_count_check
  CHECK (card_count IN ('1-2', '3-6', '7+', 'legacy-6-plus') OR card_count IS NULL);

CREATE TABLE IF NOT EXISTS public.waitlist_public_attempts (
  email_hash text NOT NULL,
  window_started timestamptz NOT NULL,
  attempt_count integer NOT NULL DEFAULT 1,
  PRIMARY KEY (email_hash, window_started)
);
ALTER TABLE public.waitlist_public_attempts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.waitlist_public_attempts FROM PUBLIC, anon, authenticated;

DROP FUNCTION IF EXISTS public.join_waitlist(text,text,text,text,text,text,text,text,text,boolean);
CREATE OR REPLACE FUNCTION public.join_waitlist(
  p_email text, p_source text DEFAULT NULL, p_utm_source text DEFAULT NULL,
  p_utm_medium text DEFAULT NULL, p_utm_campaign text DEFAULT NULL,
  p_utm_term text DEFAULT NULL, p_utm_content text DEFAULT NULL,
  p_referrer_path text DEFAULT NULL, p_landing_variant text DEFAULT NULL,
  p_privacy_consent boolean DEFAULT false, p_website text DEFAULT NULL
) RETURNS TABLE (status text, enrichment_token text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
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
END; $$;
REVOKE ALL ON FUNCTION public.join_waitlist(text,text,text,text,text,text,text,text,text,boolean,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.join_waitlist(text,text,text,text,text,text,text,text,text,boolean,text) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.enrich_waitlist(
  p_enrichment_token text, p_name text DEFAULT NULL, p_card_count text DEFAULT NULL,
  p_monthly_spend_band text DEFAULT NULL, p_primary_goal text DEFAULT NULL,
  p_problem_detail text DEFAULT NULL, p_top_cards text[] DEFAULT NULL,
  p_marketing_consent boolean DEFAULT false
) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
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
END; $$;

-- A narrow operator mutation boundary; no direct service_role UPDATE grant is
-- needed and public/authenticated roles cannot execute it.
CREATE OR REPLACE FUNCTION public.update_waitlist_operator(
  p_id uuid, p_status text, p_notes text DEFAULT NULL, p_operator_score integer DEFAULT NULL,
  p_contacted_at timestamptz DEFAULT NULL, p_invited_at timestamptz DEFAULT NULL
) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
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
REVOKE ALL ON FUNCTION public.update_waitlist_operator(uuid,text,text,integer,timestamptz,timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.update_waitlist_operator(uuid,text,text,integer,timestamptz,timestamptz) TO service_role;
REVOKE UPDATE ON TABLE public.waitlist FROM service_role;

DROP VIEW IF EXISTS public.operator_waitlist_ranked;
CREATE VIEW public.operator_waitlist_ranked WITH (security_invoker = true) AS
SELECT w.id, w.email, w.name, w.card_count, w.monthly_spend_band, w.primary_goal,
  w.problem_detail, w.top_cards, w.acquisition_source, w.landing_variant,
  w.utm_source, w.utm_medium, w.utm_campaign, w.utm_term, w.utm_content,
  w.referrer_path, w.privacy_consent_at, w.marketing_consent_at,
  w.marketing_consent_requested_at, w.created_at, w.enriched_at,
  w.operator_status, w.qualification_score, w.operator_notes, w.contacted_at,
  w.invited_at, (w.card_count = 'legacy-6-plus') AS needs_requalification,
  CASE WHEN w.card_count IS NULL OR w.card_count = 'legacy-6-plus'
    OR w.monthly_spend_band IS NULL OR w.primary_goal IS NULL THEN 0
  ELSE CASE w.card_count WHEN '3-6' THEN 45 WHEN '7+' THEN 30 WHEN '1-2' THEN 15 END
    + CASE w.monthly_spend_band WHEN '1l-plus' THEN 25 WHEN '50k-1l' THEN 20 WHEN '25k-50k' THEN 15 WHEN 'under-25k' THEN 10 END
    + CASE w.primary_goal WHEN 'maximize_rewards' THEN 20 WHEN 'track_benefits' THEN 15 WHEN 'simplify_card_choices' THEN 10 END
    + COALESCE(w.qualification_score, 0) END AS rank_score
FROM public.waitlist w
ORDER BY rank_score DESC, w.created_at ASC;
REVOKE ALL ON TABLE public.operator_waitlist_ranked FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.operator_waitlist_ranked TO service_role;
