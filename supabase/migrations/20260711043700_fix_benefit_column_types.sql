-- supabase/migrations/20260711043700_fix_benefit_column_types.sql
--
-- Design spec §3.1 P0 #2. Timestamped BETWEEN 20260711043541_initial_schema.sql
-- (creates partners/exclusions/regions as TEXT[]) and
-- 20260711043900_restore_reference_data.sql (seeds them with JSON-array
-- literal syntax, which COPY cannot load into TEXT[]). This ordering is
-- load-bearing — a fix appended after the existing chain would run too late
-- to matter, since the seed load would already have failed.
BEGIN;

ALTER TABLE benefits
  ALTER COLUMN partners TYPE JSONB USING
    CASE
      WHEN partners IS NULL THEN '[]'::jsonb
      ELSE to_jsonb(partners)
    END,
  ALTER COLUMN partners SET DEFAULT '[]'::jsonb;

-- exclusions is conceptually an object ({"mcc_codes": [...], ...}, see the
-- COMMENT below), unlike partners/regions above which are conceptually
-- arrays — to_jsonb() on a legacy TEXT[] would produce an array shape
-- ["a","b"], not an object, silently mismatching that shape. This migration
-- runs before 20260711043900_restore_reference_data.sql ever seeds
-- `benefits`, so no non-null, non-empty legacy exclusions value should exist
-- in the intended deploy order — but that's an environmental assumption,
-- not a property of this SQL, so this guard raises loudly if it's ever
-- wrong (e.g. a re-run against a database that already has rows) instead of
-- silently converting a legacy array into the wrong JSON shape.
--
-- cardinality(exclusions) > 0 correctly handles all 3 real cases for this
-- nullable TEXT[] column without needing a separate IS NOT NULL check:
-- cardinality(NULL) is NULL (NULL > 0 is NULL, filtered out by WHERE same
-- as FALSE); cardinality('{}') is 0 (0 > 0 is FALSE, filtered out); only a
-- genuinely non-empty array (cardinality > 0) survives the WHERE and fires
-- the guard. This relies on ordinary WHERE-clause NULL-exclusion semantics,
-- not any NULL-input special-casing in cardinality() itself.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM benefits
    WHERE cardinality(exclusions) > 0
  ) THEN
    RAISE EXCEPTION
      'benefits.exclusions has non-empty legacy TEXT[] rows — this migration only knows how to convert NULL/empty exclusions to JSONB {}. Decide the correct object shape for the existing values before proceeding.';
  END IF;
END $$;

ALTER TABLE benefits
  ALTER COLUMN exclusions TYPE JSONB USING '{}'::jsonb,
  ALTER COLUMN exclusions SET DEFAULT '{}'::jsonb;

ALTER TABLE benefits
  ALTER COLUMN regions TYPE JSONB USING
    CASE
      WHEN regions IS NULL THEN '[]'::jsonb
      ELSE to_jsonb(regions)
    END,
  ALTER COLUMN regions SET DEFAULT '[]'::jsonb;

COMMENT ON COLUMN benefits.partners IS
  'Partner names where benefit is applicable (JSONB — matches production data shape, corrected from TEXT[] before seed data loads).';
COMMENT ON COLUMN benefits.exclusions IS
  'Exclusion conditions, e.g. {"mcc_codes": [...], "merchants": [...], "categories": [...]} (JSONB — corrected from TEXT[] before seed data loads).';
COMMENT ON COLUMN benefits.regions IS
  'Geographic regions where benefit is valid (JSONB — corrected from TEXT[] before seed data loads).';

COMMIT;
