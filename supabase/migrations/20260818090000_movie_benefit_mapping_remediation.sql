-- Conservative remediation after the 2026-08-18 movie-benefit audit.
-- Deliberately excludes SBI rows: their titles and source URLs conflict often
-- enough that URL equality alone is not sufficient evidence of applicability.
BEGIN;

-- Exact, source-verified orphan: both records identify the IDFC FIRST Classic
-- product page and the benefit is explicitly categorised as entertainment.
INSERT INTO public.card_benefit_mapping (card_id, benefit_id, display_priority)
SELECT c.id, b.benefit_id, 1
FROM public.card_catalog AS c
JOIN public.benefits AS b ON c.card_url = b.source_url
WHERE c.bank = 'IDFC FIRST Bank'
  AND c.card_name = 'Classic'
  AND c.card_url = 'https://www.idfcfirstbank.com/credit-card/classic'
  AND b.title = '25% Off on Movie Tickets'
  AND b.is_active = true
ON CONFLICT (card_id, benefit_id) DO NOTHING;

-- These two rows describe the same monthly ₹80k / ₹500 Diners Club Black
-- voucher choice. Keep the clearer canonical mapping and retain the duplicate
-- benefit row as evidence/history instead of destroying source data.
DELETE FROM public.card_benefit_mapping AS mapping
USING public.card_catalog AS c, public.benefits AS b
WHERE mapping.card_id = c.id
  AND mapping.benefit_id = b.benefit_id
  AND c.bank = 'HDFC Bank'
  AND c.card_name = 'Diners Club Black'
  AND c.card_url = 'https://www.hdfcbank.com/personal/pay/cards/credit-cards/diners-club-black'
  AND b.title = 'Monthly Milestone Benefits'
  AND b.source_url = c.card_url;

-- Exact known scrape-label repairs. URL guards prevent similarly named cards
-- at other issuers from being touched.
UPDATE public.card_catalog
SET card_name = 'FIRST Private Credit Card'
WHERE bank = 'IDFC FIRST Bank'
  AND card_name = 'Firstprivatecreditcard'
  AND card_url = 'https://www.idfcfirstbank.com/credit-card/FIRSTPrivateCreditCard';

UPDATE public.card_catalog
SET card_name = 'IndianOil'
WHERE bank = 'Axis Bank'
  AND card_name = 'Indianoil'
  AND card_url = 'https://www.axisbank.com/retail/cards/credit-card/indianoil-axis-bank-credit-card';

UPDATE public.card_catalog
SET bank = 'IDFC FIRST Bank'
WHERE bank = 'IDFC First Bank';

-- Service-only observability for recurring orphan checks. The Movies query
-- intentionally mirrors the app repository's broad discovery predicate; the
-- mapped count remains distinct-by-benefit so multiple card mappings do not
-- inflate health.
CREATE OR REPLACE FUNCTION public.get_movie_benefit_mapping_health()
RETURNS TABLE (metric text, value bigint)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
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
        lower(coalesce(benefit.category, '')) IN ('entertainment', 'movies')
        OR lower(coalesce(benefit.subcategory, '')) IN ('entertainment', 'movies')
        OR benefit.title ILIKE '%movie%'
        OR benefit.description ILIKE '%movie%'
        OR benefit.title ILIKE '%bookmyshow%'
        OR benefit.description ILIKE '%bookmyshow%'
        OR benefit.title ILIKE '%district%'
        OR benefit.description ILIKE '%district%'
        OR benefit.partners::text ILIKE '%bookmyshow%'
        OR benefit.partners::text ILIKE '%zomato%'
        OR benefit.partners::text ILIKE '%district%'
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

REVOKE ALL ON FUNCTION public.get_movie_benefit_mapping_health()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_movie_benefit_mapping_health()
  TO service_role;

COMMIT;
