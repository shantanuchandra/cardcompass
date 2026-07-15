ALTER TABLE public.statements
  ADD COLUMN IF NOT EXISTS paid_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS paid_at TIMESTAMPTZ;

-- Statement ingestion persists parser provenance and reconciliation facts here.
-- The backfill also repairs installations where this column existed before the
-- migration but allowed NULL values.
ALTER TABLE public.statements
  ADD COLUMN IF NOT EXISTS metadata JSONB NOT NULL DEFAULT '{}'::jsonb;

ALTER TABLE public.statements
  ALTER COLUMN metadata SET DEFAULT '{}'::jsonb;

UPDATE public.statements
SET metadata = '{}'::jsonb
WHERE metadata IS NULL;

ALTER TABLE public.statements
  ALTER COLUMN metadata SET NOT NULL;

UPDATE public.statements
SET total_amount = 0
WHERE total_amount IS NULL;

ALTER TABLE public.statements
  ALTER COLUMN total_amount SET NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'statements_paid_amount_bounds_check'
      AND conrelid = 'public.statements'::regclass
  ) THEN
    ALTER TABLE public.statements
      ADD CONSTRAINT statements_paid_amount_bounds_check
      CHECK (paid_amount >= 0 AND paid_amount <= total_amount);
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS statements_user_card_open_due_idx
  ON public.statements (user_card_id, payment_status, due_date);
