-- Add the two movie variants that could not be promoted by automated
-- enrichment on 2026-08-18, using exact first-party product evidence.
--
-- AU Zenith and Zenith+ are distinct products. The live catalog contained
-- only Zenith, while AU's current Zenith+ product page and exact BookMyShow
-- terms identify the movie offer as a Zenith+ benefit. This migration adds
-- Zenith+ as its own catalog row rather than aliasing or mutating Zenith.
--
-- PSB SBI Card ELITE's server-rendered product page identifies the exact
-- product, but the detailed movie terms are in an official, font-encoded PDF
-- that the Edge runtime's bounded PDF text reader cannot decode. The PDF says
-- BookMyShow reduces a qualifying booking by Rs.500 or the cost of two
-- tickets, whichever is lower, for at most two tickets per month. The product
-- page describes this as Rs.6,000 of free movie tickets per year.
BEGIN;

INSERT INTO public.card_catalog (
  bank,
  card_name,
  network,
  card_type,
  annual_fee,
  joining_fee,
  card_url
)
SELECT
  'AU Small Finance Bank',
  'Zenith+',
  'Visa',
  'Credit',
  4999,
  4999,
  'https://www.au.bank.in/premium-banking/credit-cards/zenith-plus-credit-card'
WHERE NOT EXISTS (
  SELECT 1
  FROM public.card_catalog
  WHERE bank ILIKE 'AU Small Finance Bank'
    AND card_name ILIKE 'Zenith+'
);

INSERT INTO public.benefits (
  title,
  description,
  benefit_category,
  benefit_type,
  value_config,
  partners,
  source_url,
  dedupe_key
)
SELECT
  'AU Zenith+ BookMyShow BOGO',
  'Buy 1 movie or event ticket and get 1 complimentary ticket on BookMyShow, capped at Rs.500 per booking and redeemable 4 times per calendar quarter.',
  'entertainment',
  'bogo',
  jsonb_build_object(
    'category', 'movie_tickets',
    'discount_type', 'bogo',
    'max_discount_per_transaction', 500,
    'max_usage_per_period', 4,
    'usage_period', 'quarter'
  ),
  jsonb_build_array('BookMyShow'),
  'https://www.au.bank.in/zenith-plus_tnc-book-my-show-terms-and-conditions.pdf',
  lower(regexp_replace(trim('entertainment'), '\s+', ' ', 'g'))
    || '|bogo|'
    || lower(regexp_replace(trim('AU Zenith+ BookMyShow BOGO'), '\s+', ' ', 'g'))
WHERE NOT EXISTS (
  SELECT 1
  FROM public.benefits
  WHERE title = 'AU Zenith+ BookMyShow BOGO'
);

INSERT INTO public.card_benefit_mapping (card_id, benefit_id, display_priority)
SELECT card.id, benefit.benefit_id, 1
FROM public.card_catalog AS card
JOIN public.benefits AS benefit
  ON benefit.title = 'AU Zenith+ BookMyShow BOGO'
WHERE card.bank ILIKE 'AU Small Finance Bank'
  AND card.card_name ILIKE 'Zenith+'
ON CONFLICT (card_id, benefit_id) DO NOTHING;

INSERT INTO public.benefits (
  title,
  description,
  benefit_category,
  benefit_type,
  value_config,
  partners,
  source_url,
  dedupe_key
)
SELECT
  'PSB SBI Card ELITE Movie Tickets',
  'Get free movie tickets worth Rs.6,000 per year on BookMyShow. Each monthly redemption covers up to two tickets with a maximum total discount of Rs.500; primary cards only.',
  'entertainment',
  'annual_benefit',
  jsonb_build_object(
    'category', 'movie_tickets',
    'unit', 'fixed',
    'annual_cap', 6000,
    'reward_value', 6000,
    'max_discount_per_transaction', 500,
    'max_usage_per_month', 1
  ),
  jsonb_build_array('BookMyShow'),
  'https://www.sbicard.com/sbi-card-en/assets/docs/pdf/banking-tnc/psb-elite-tnc.pdf',
  lower(regexp_replace(trim('entertainment'), '\s+', ' ', 'g'))
    || '|annual_benefit|'
    || lower(regexp_replace(trim('PSB SBI Card ELITE Movie Tickets'), '\s+', ' ', 'g'))
WHERE NOT EXISTS (
  SELECT 1
  FROM public.benefits
  WHERE title = 'PSB SBI Card ELITE Movie Tickets'
);

INSERT INTO public.card_benefit_mapping (card_id, benefit_id, display_priority)
SELECT benefit_card.id, benefit.benefit_id, 1
FROM public.card_catalog AS benefit_card
JOIN public.benefits AS benefit
  ON benefit.title = 'PSB SBI Card ELITE Movie Tickets'
WHERE benefit_card.bank = 'SBI Card'
  AND benefit_card.card_name ILIKE 'Psb Elite'
ON CONFLICT (card_id, benefit_id) DO NOTHING;

COMMIT;
