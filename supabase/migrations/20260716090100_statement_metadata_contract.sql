-- Added separately so databases that already applied statement payment
-- tracking receive the ingestion metadata contract as well.
ALTER TABLE public.statements
  ADD COLUMN IF NOT EXISTS metadata JSONB DEFAULT '{}'::jsonb;

ALTER TABLE public.statements
  ALTER COLUMN metadata SET DEFAULT '{}'::jsonb;

UPDATE public.statements
SET metadata = '{}'::jsonb
WHERE metadata IS NULL;

ALTER TABLE public.statements
  ALTER COLUMN metadata SET NOT NULL;
