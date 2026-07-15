ALTER TABLE public.statements
  ADD COLUMN IF NOT EXISTS paid_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS paid_at TIMESTAMPTZ;

ALTER TABLE public.statements
  ADD CONSTRAINT statements_paid_amount_bounds_check
  CHECK (paid_amount >= 0 AND paid_amount <= total_amount);

CREATE INDEX IF NOT EXISTS statements_user_card_open_due_idx
  ON public.statements (user_card_id, payment_status, due_date);
