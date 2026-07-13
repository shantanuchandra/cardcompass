BEGIN;

-- The legacy table is no longer the card-to-benefit relationship. Preserve
-- canonical benefits, but reset only the two approved relationship/config rows.
DELETE FROM public.card_benefit_mapping;
DELETE FROM public.card_benefits;

-- One stable key identifies the canonical row for an equivalence class. Legacy
-- duplicate rows are retained, not deleted, and receive their own legacy key.
ALTER TABLE public.benefits
  ADD COLUMN IF NOT EXISTS dedupe_key text;

WITH ranked AS (
  SELECT
    benefit_id,
    lower(regexp_replace(trim(coalesce(benefit_category, '')), '\\s+', ' ', 'g'))
      || '|' || lower(regexp_replace(trim(coalesce(benefit_type, '')), '\\s+', ' ', 'g'))
      || '|' || lower(regexp_replace(trim(coalesce(title, '')), '\\s+', ' ', 'g')) AS canonical_key,
    row_number() OVER (
      PARTITION BY
        lower(regexp_replace(trim(coalesce(benefit_category, '')), '\\s+', ' ', 'g')),
        lower(regexp_replace(trim(coalesce(benefit_type, '')), '\\s+', ' ', 'g')),
        lower(regexp_replace(trim(coalesce(title, '')), '\\s+', ' ', 'g'))
      ORDER BY created_at, benefit_id
    ) AS rank
  FROM public.benefits
)
UPDATE public.benefits AS benefit
SET dedupe_key = CASE
  WHEN ranked.rank = 1 THEN ranked.canonical_key
  ELSE 'legacy:' || benefit.benefit_id::text
END
FROM ranked
WHERE benefit.benefit_id = ranked.benefit_id;

ALTER TABLE public.benefits
  ALTER COLUMN dedupe_key SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_benefits_dedupe_key
  ON public.benefits(dedupe_key);

-- Only historical generic benefit value/configuration columns remain here.
ALTER TABLE public.card_benefits
  DROP COLUMN IF EXISTS card_id,
  DROP COLUMN IF EXISTS ai_extracted,
  DROP COLUMN IF EXISTS extraction_confidence,
  DROP COLUMN IF EXISTS last_scraped_at,
  DROP COLUMN IF EXISTS source_url,
  DROP COLUMN IF EXISTS json_configuration,
  DROP COLUMN IF EXISTS usage_period,
  DROP COLUMN IF EXISTS priority_score,
  DROP COLUMN IF EXISTS efficiency_threshold,
  DROP COLUMN IF EXISTS last_usage_update;

ALTER TABLE public.card_benefits_staging
  ADD COLUMN IF NOT EXISTS benefit_decisions jsonb NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS reviewed_at timestamptz,
  ADD COLUMN IF NOT EXISTS reviewed_by uuid REFERENCES auth.users(id) ON DELETE SET NULL;

COMMENT ON TABLE public.card_benefits IS
  'Historical generic benefit value/configuration rows. Card associations use card_benefit_mapping only.';
COMMENT ON COLUMN public.benefits.dedupe_key IS
  'Canonical normalized category, type, and title key used for database-enforced benefit deduplication.';

COMMIT;
