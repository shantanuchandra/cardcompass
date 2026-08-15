-- supabase/migrations/20260802100000_curated_movie_benefit_mappings.sql
--
-- Design spec §3.1 P0 #1 + #3. card_benefit_mapping was emptied by
-- 20260713180753_normalize_card_benefit_mappings.sql and never repopulated.
-- This migration inserts ONLY mappings whose card name is internally
-- consistent with the benefit's own source_url — never a mechanical
-- restoration of the original (partly commercially-inaccurate) deleted set.
--
-- WHERE-clause note: card_catalog.card_name is matched with exact,
-- case-insensitive ILIKE (no wildcards) rather than substring wildcards.
-- Statically verified against 20260711043900_restore_reference_data.sql:
-- substring patterns such as '%Millennia%', '%Wealth%', and
-- '%Diners Club Black%' each match MORE THAN ONE card_catalog row from
-- different banks (e.g. IDFC FIRST Bank "Millennia" vs. HDFC Bank
-- "Millennia Cc New"; IDFC FIRST Bank "Wealth" vs. Kotak Bank "Wealth
-- Management Infinite"; HDFC "Diners Club Black" vs. HDFC "Diners Club
-- Black Metal Edition"). Because the SELECT is a cross join filtered
-- independently on each side, a loose wildcard would silently pair the
-- WRONG card with this benefit in addition to the right one. Exact
-- card_name equality (via ILIKE with no % wildcards) avoids that. The
-- "Indianoil" card_name is additionally ambiguous ACROSS BANKS (both Axis
-- Bank and HDFC Bank have a card_catalog row named exactly "Indianoil"), so
-- that mapping also constrains on c.bank.
BEGIN;

-- "BookMyShow Discount" (fixedDiscount, monthly_cap 1500) → IDFC FIRST
-- Private, whose source_url is /credit-card/FIRSTPrivateCreditCard —
-- internally consistent. card_catalog.card_name for this card is the
-- concatenated "Firstprivatecreditcard" (no space) — verified directly
-- against the seed row; a '%FIRST Private%' pattern (with a space) would
-- match zero rows.
INSERT INTO card_benefit_mapping (card_id, benefit_id, display_priority)
SELECT c.id, b.benefit_id, 1
FROM card_catalog c, benefits b
WHERE c.card_name ILIKE 'Firstprivatecreditcard'
  AND b.title = 'BookMyShow Discount'
  AND b.source_url ILIKE '%FIRSTPrivateCreditCard%'
ON CONFLICT DO NOTHING;

-- "Instant Discount on Bookmyshow" (percentDiscount, 10%) → Axis IndianOil,
-- whose source_url is /credit-card/indianoil-axis-bank-credit-card —
-- internally consistent. Constrained to c.bank = 'Axis Bank' because HDFC
-- Bank also has a card_catalog row named exactly "Indianoil" (different
-- card, different source_url) that would otherwise also match.
INSERT INTO card_benefit_mapping (card_id, benefit_id, display_priority)
SELECT c.id, b.benefit_id, 1
FROM card_catalog c, benefits b
WHERE c.bank = 'Axis Bank'
  AND c.card_name ILIKE 'Indianoil'
  AND b.title = 'Instant Discount on Bookmyshow'
  AND b.source_url ILIKE '%indianoil-axis-bank%'
ON CONFLICT DO NOTHING;

-- "Twin ticket treats" (bogo, Zomato) → IDFC FIRST Mayura, whose source_url
-- is /credit-card/metal-credit-card/mayura — internally consistent.
-- card_catalog.card_name "Mayura" is unique in the seed data.
INSERT INTO card_benefit_mapping (card_id, benefit_id, display_priority)
SELECT c.id, b.benefit_id, 1
FROM card_catalog c, benefits b
WHERE c.card_name ILIKE 'Mayura'
  AND b.title = 'Twin ticket treats'
  AND b.source_url ILIKE '%mayura%'
ON CONFLICT DO NOTHING;

-- "Buy-1-Get-1 Movie Ticket Offer" (bogo, no recorded partner) → IDFC FIRST
-- Wealth, whose source_url is /credit-card/wealth — internally consistent.
-- Exact match on card_name excludes Kotak Bank's "Wealth Management
-- Infinite", which a '%Wealth%' substring pattern would otherwise catch.
INSERT INTO card_benefit_mapping (card_id, benefit_id, display_priority)
SELECT c.id, b.benefit_id, 1
FROM card_catalog c, benefits b
WHERE c.card_name ILIKE 'Wealth'
  AND b.title = 'Buy-1-Get-1 Movie Ticket Offer'
  AND b.source_url ILIKE '%wealth%'
ON CONFLICT DO NOTHING;

-- "25% off on movie tickets" → IDFC FIRST Millennia, whose source_url is
-- /credit-card/millennia — internally consistent. NOTE: the seed data
-- contains TWO rows with near-identical titles at different casing:
-- "25% Off on Movie Tickets" (source_url .../credit-card/classic) and
-- "25% off on movie tickets" (source_url .../credit-card/millennia, exact
-- lowercase match required below — Postgres string equality is
-- case-sensitive). Only the lowercase title pairs with the millennia
-- source_url; using the capitalized title here would join the wrong
-- benefit row (or zero rows). Exact match on card_name excludes HDFC
-- Bank's "Millennia Cc New", which a '%Millennia%' substring pattern would
-- otherwise catch.
INSERT INTO card_benefit_mapping (card_id, benefit_id, display_priority)
SELECT c.id, b.benefit_id, 1
FROM card_catalog c, benefits b
WHERE c.card_name ILIKE 'Millennia'
  AND b.title = '25% off on movie tickets'
  AND b.source_url ILIKE '%millennia%'
ON CONFLICT DO NOTHING;

-- "Monthly Vouchers on Spends" / "Monthly Milestone Benefits" (milestone,
-- Uber/cult.fit/BookMyShow/TataCliQ) → HDFC Diners Club Black, whose
-- source_url is /credit-cards/diners-club-black — internally consistent.
-- Exact match on card_name excludes HDFC's "Diners Club Black Metal
-- Edition", which a '%Diners Club Black%' substring pattern would
-- otherwise also catch (different card_id, different source_url).
INSERT INTO card_benefit_mapping (card_id, benefit_id, display_priority)
SELECT c.id, b.benefit_id, 1
FROM card_catalog c, benefits b
WHERE c.card_name ILIKE 'Diners Club Black'
  AND b.title IN ('Monthly Vouchers on Spends', 'Monthly Milestone Benefits')
  AND b.source_url ILIKE '%diners-club-black%'
ON CONFLICT DO NOTHING;

COMMIT;
