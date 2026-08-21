-- Forward copy of the movie-benefit corrections that previously shared the
-- already-applied 20260817020000 version with card_discovery_queue. Keeping a
-- unique version preserves linked migration history without repair/rewrite.
-- The predicates make replay safe when the target rows were already corrected.

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
