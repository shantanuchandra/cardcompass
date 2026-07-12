-- Preserve validation evidence and rejection diagnostics for benefit extraction.
ALTER TABLE card_benefits_staging
  ADD COLUMN IF NOT EXISTS validation_version TEXT,
  ADD COLUMN IF NOT EXISTS calculated_confidence NUMERIC(5,4),
  ADD COLUMN IF NOT EXISTS validation_reasons JSONB NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS validation_warnings JSONB NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS source_evidence JSONB,
  ADD COLUMN IF NOT EXISTS validated_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS rejected_at TIMESTAMPTZ;

ALTER TABLE card_benefits_staging
  DROP CONSTRAINT IF EXISTS card_benefits_staging_status_check;

ALTER TABLE card_benefits_staging
  ADD CONSTRAINT card_benefits_staging_status_check
  CHECK (status IN ('pending', 'approved', 'rejected'));

ALTER TABLE card_benefits_staging
  DROP CONSTRAINT IF EXISTS card_benefits_staging_confidence_check;

ALTER TABLE card_benefits_staging
  ADD CONSTRAINT card_benefits_staging_confidence_check
  CHECK (calculated_confidence IS NULL OR
         (calculated_confidence >= 0 AND calculated_confidence <= 1));

CREATE INDEX IF NOT EXISTS idx_card_benefits_staging_status
  ON card_benefits_staging(status);

CREATE INDEX IF NOT EXISTS idx_card_benefits_staging_card_created
  ON card_benefits_staging(card_id, created_at DESC);

-- Historical pending rows predate evidence grounding. Retain them for audit,
-- but prevent accidental approval until they are re-extracted and validated.
UPDATE card_benefits_staging
SET status = 'rejected',
    validation_version = 'legacy-unvalidated',
    calculated_confidence = 0,
    validation_reasons = jsonb_build_array(jsonb_build_object(
      'code', 'legacy_unvalidated',
      'message', 'Extraction predates source-grounding validation and must be re-extracted.'
    )),
    validated_at = COALESCE(validated_at, NOW()),
    rejected_at = COALESCE(rejected_at, NOW()),
    updated_at = NOW()
WHERE status = 'pending'
  AND (validation_version IS NULL OR source_evidence IS NULL);
