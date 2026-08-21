BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

-- Card type is an identity gate throughout discovery and recurrence. Preserve
-- only the already-proven credit rows while removing historical casing drift.
UPDATE public.card_catalog
SET card_type = 'credit',
    updated_at = statement_timestamp()
WHERE lower(btrim(card_type)) = 'credit'
  AND card_type IS DISTINCT FROM 'credit';

-- The legacy detailed table is empty and no longer serves application reads,
-- but it remains in the public schema. Keep it deny-by-default like the active
-- ingestion tables instead of relying on an accidental lack of grants.
ALTER TABLE public.card_benefits ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.card_benefits FROM PUBLIC, anon, authenticated;

-- Task 12 deploys the new parser and issuer rotation dark. Both scheduled
-- actions share this fail-closed control; an administrator must explicitly
-- resume them after the five-card pilot and review queue checks pass.
INSERT INTO public.admin_runtime_controls (
  control_key, is_paused, reason, updated_by, updated_at
) VALUES (
  'benefit_enrichment_scheduled', true,
  'Dark rollout pending benefits-v6 pilot verification',
  NULL, statement_timestamp()
)
ON CONFLICT (control_key) DO UPDATE
SET is_paused = true,
    reason = 'Dark rollout pending benefits-v6 pilot verification',
    updated_by = NULL,
    updated_at = statement_timestamp();

DO $catalog_ingestion_normalization_apply$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.card_catalog
    WHERE lower(btrim(card_type)) = 'credit'
      AND card_type IS DISTINCT FROM 'credit'
  ) THEN
    RAISE EXCEPTION 'noncanonical credit card_type remains';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_class AS class
    JOIN pg_namespace AS namespace ON namespace.oid = class.relnamespace
    WHERE namespace.nspname = 'public'
      AND class.relname = 'card_benefits'
      AND class.relrowsecurity = true
  ) THEN
    RAISE EXCEPTION 'legacy card_benefits RLS is disabled';
  END IF;
END
$catalog_ingestion_normalization_apply$;

COMMIT;
