-- Forward copy of the movie-benefit corrections that previously shared the
-- already-applied 20260817020000 version with card_discovery_queue. Keeping a
-- unique version preserves linked migration history without repair/rewrite.
-- The predicates make replay safe when the target rows were already corrected.
--
-- Two IDFC First movie benefits had an empty partners array despite distinct,
-- attributable platform terms:
--
-- 1. The IDFC First Wealth "Buy-1-Get-1 Movie Ticket Offer" already says in
--    its stored description that redemption is through the District app; the
--    platform was present in source data but missing from `partners`.
-- 2. The IDFC First Millennia "25% off on movie tickets" row lacked both its
--    District platform and its per-transaction cap. CardInsider, BankBazaar,
--    and Paisabazaar independently identify District by Zomato and a Rs 100
--    cap for this exact variant. Less-specific BookMyShow/Paytm results belong
--    to a different IDFC card variant and are intentionally excluded.
--
-- Those sources also describe a prior-calendar-month transaction requirement.
-- This schema has no safe field for that rolling eligibility condition, so it
-- is deliberately not encoded here. Only the existing partners and
-- `max_discount_per_transaction` fields are corrected.

BEGIN;

UPDATE public.benefits
SET partners = '["District"]'::jsonb
WHERE title = 'Buy-1-Get-1 Movie Ticket Offer'
  AND source_url ILIKE '%idfcfirstbank.com/credit-card/wealth%'
  AND partners = '[]'::jsonb;

UPDATE public.benefits
SET partners = '["District"]'::jsonb,
    value_config = value_config || jsonb_build_object(
      'max_discount_per_transaction', 100
    )
WHERE title = '25% off on movie tickets'
  AND source_url ILIKE '%idfcfirstbank.com/credit-card/millennia%'
  AND partners = '[]'::jsonb;

COMMIT;
