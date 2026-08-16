-- supabase/migrations/20260817020000_movie_benefit_platform_and_cap_corrections.sql
--
-- Two IDFC First movie benefits had an empty partners array despite real,
-- confirmable platform terms:
--
-- 1. "Buy-1-Get-1 Movie Ticket Offer" (IDFC First Wealth) — this benefit's
--    OWN description column already states "using the Buy-One-Get-One movie
--    ticket offer via District mobile app" — the platform was present in
--    the source data all along, just never extracted into partners.
--
-- 2. "25% off on movie tickets" (IDFC First Millennia) — no platform stated
--    in this row's own description, and no cap in value_config at all
--    (bare discount_percent: 25, uncapped). Verified against three
--    independent, converging secondary sources (a first-party IDFC page
--    fetch was attempted but blocked — the site is JS-rendered and returned
--    only nav chrome, not offer content):
--      - cardinsider.com/idfc-first-bank/idfc-first-millennia-card/ — exact
--        quote: "25% Discount Up to ₹100 on District App (Benefit Available
--        on Completing at Least One Transaction in the Previous Calendar
--        Month)"
--      - bankbazaar.com and paisabazaar.com's Millennia card pages both
--        independently state "25% discount on movie tickets booked via
--        District by Zomato mobile app (Up to Rs. 100)"
--    All three name District specifically (not BookMyShow/Paytm, which
--    appeared in a less-specific initial search but were confirmed to
--    describe a DIFFERENT IDFC card variant's separate BOGO offer, not
--    Millennia's). The "requires a transaction in the prior calendar month"
--    eligibility condition is NOT encoded here — no field in this schema
--    represents a rolling prior-month-activity gate, and inventing one
--    would be a bigger, separate change; the cap itself is captured via the
--    already-existing max_discount_per_transaction key (used by real bogo
--    and other percent-type rows in this same table), which
--    movie_deal_rule_normalizer.dart's _normalizePercent now reads (a
--    genuine, separate gap this migration exposed: percentDiscount rows
--    with this key were previously silently uncapped everywhere, not just
--    for this one row).
BEGIN;

UPDATE benefits
SET partners = '["District"]'::jsonb
WHERE title = 'Buy-1-Get-1 Movie Ticket Offer'
  AND source_url ILIKE '%idfcfirstbank.com/credit-card/wealth%'
  AND partners = '[]'::jsonb;

UPDATE benefits
SET partners = '["District"]'::jsonb,
    value_config = value_config || jsonb_build_object('max_discount_per_transaction', 100)
WHERE title = '25% off on movie tickets'
  AND source_url ILIKE '%idfcfirstbank.com/credit-card/millennia%'
  AND partners = '[]'::jsonb;

COMMIT;
