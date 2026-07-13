BEGIN;

-- Keep one card-to-benefit row. A mapping can be eligible for several
-- searchable categories, such as DINING and GROCERY, without duplicating the
-- canonical benefit or the (card_id, benefit_id) relationship.
ALTER TABLE public.card_benefit_mapping
  ADD COLUMN IF NOT EXISTS category_codes text[] NOT NULL DEFAULT '{}'::text[];

CREATE INDEX IF NOT EXISTS idx_card_benefit_mapping_category_codes
  ON public.card_benefit_mapping USING gin (category_codes);

-- Preserve the current single-category behavior for existing mappings when
-- the catalog category corresponds to a configured category code.
UPDATE public.card_benefit_mapping AS mapping
SET category_codes = ARRAY[category.category_code]
FROM public.benefits AS benefit
JOIN LATERAL (
  SELECT category_code
  FROM public.benefit_categories
  WHERE upper(category_code) = upper(benefit.benefit_category)
  ORDER BY (category_code = upper(category_code)) DESC, category_code
  LIMIT 1
) AS category ON true
WHERE mapping.benefit_id = benefit.benefit_id
  AND cardinality(mapping.category_codes) = 0;

COMMENT ON COLUMN public.card_benefit_mapping.category_codes IS
  'Normalized searchable categories for this card-specific benefit mapping; one mapping may include several codes.';

COMMIT;
