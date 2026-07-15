-- Repair payment data after the original payment-tracking migration. This is
-- intentionally forward-only: 20260716090000 and later migrations may already
-- have been applied in deployed databases.
--
-- Historical paid_at is intentionally left unchanged. The old schema did not
-- record when a bill was paid, so inventing a timestamp during this repair
-- would falsely imply an audited payment time.
SELECT set_config('cardcompass.reconciliation_write', 'on', false);

UPDATE public.statements
SET paid_amount = total_amount
WHERE payment_status = 'paid'
  AND paid_amount <> total_amount;

RESET cardcompass.reconciliation_write;

-- A payment reported by a newly imported statement can settle only earlier
-- statement cycles. Equal statement dates are not ordered cycles, so the same statement date is deliberately excluded rather than selected by UUID order.
CREATE OR REPLACE FUNCTION public.reconcile_imported_statement_payment(
  p_source_statement_id uuid,
  p_user_id uuid,
  p_user_card_id uuid,
  p_expected_payment_credit numeric
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_source public.statements%ROWTYPE;
  v_target public.statements%ROWTYPE;
  v_credit numeric(12,2);
  v_remaining numeric(12,2);
  v_payment numeric(12,2);
  v_updates jsonb := '[]'::jsonb;
BEGIN
  IF auth.uid() IS NULL OR auth.uid() <> p_user_id THEN
    RAISE EXCEPTION 'statement payment reconciliation requires the owning user';
  END IF;
  PERFORM set_config('cardcompass.reconciliation_write', 'on', true);

  SELECT * INTO v_source FROM public.statements
  WHERE id = p_source_statement_id AND user_id = p_user_id AND user_card_id = p_user_card_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'source statement is not owned by the supplied user and card';
  END IF;
  IF v_source.metadata ->> 'payment_reconciliation_state' = 'applied' THEN
    RETURN jsonb_build_object('already_applied', true, 'updates', '[]'::jsonb,
      'unmatched_payment_credit', COALESCE((v_source.metadata ->> 'unmatched_payment_credit')::numeric, 0));
  END IF;

  v_credit := COALESCE((v_source.metadata ->> 'payments_received')::numeric, 0);
  IF v_credit <= 0 OR v_credit <> p_expected_payment_credit THEN
    RAISE EXCEPTION 'payment credit does not match the imported source statement';
  END IF;
  v_remaining := v_credit;

  UPDATE public.statements SET metadata = jsonb_set(v_source.metadata,
    '{payment_reconciliation_state}', '"applied"'::jsonb, true)
  WHERE id = p_source_statement_id;

  FOR v_target IN
    SELECT * FROM public.statements
    WHERE user_id = p_user_id AND user_card_id = p_user_card_id
      AND id <> p_source_statement_id
      AND statements.statement_date < v_source.statement_date
      AND payment_status IN ('pending', 'partial', 'overdue')
      AND total_amount > paid_amount
    ORDER BY statement_date ASC, due_date ASC, id ASC
    FOR UPDATE
  LOOP
    EXIT WHEN v_remaining <= 0;
    v_payment := LEAST(v_target.total_amount - v_target.paid_amount, v_remaining);
    v_remaining := v_remaining - v_payment;
    UPDATE public.statements
    SET paid_amount = paid_amount + v_payment,
        payment_status = CASE WHEN paid_amount + v_payment >= total_amount THEN 'paid' ELSE 'partial' END,
        -- paid_at means first payment observed; partial allocations must set it.
        paid_at = COALESCE(paid_at, NOW())
    WHERE id = v_target.id AND user_id = p_user_id AND user_card_id = p_user_card_id;
    v_updates := v_updates || jsonb_build_array(jsonb_build_object(
      'statement_id', v_target.id, 'payment_amount', v_payment,
      'payment_status', CASE WHEN v_target.paid_amount + v_payment >= v_target.total_amount THEN 'paid' ELSE 'partial' END));
  END LOOP;

  UPDATE public.statements
  SET metadata = jsonb_set(metadata, '{unmatched_payment_credit}', to_jsonb(v_remaining), true)
  WHERE id = p_source_statement_id AND user_id = p_user_id AND user_card_id = p_user_card_id;
  RETURN jsonb_build_object('already_applied', false, 'updates', v_updates,
    'unmatched_payment_credit', v_remaining);
END;
$$;

CREATE OR REPLACE FUNCTION public.apply_statement_payment(
  p_statement_id uuid,
  p_user_id uuid,
  p_user_card_id uuid,
  p_payment_amount numeric,
  p_mark_paid boolean DEFAULT false
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_statement public.statements%ROWTYPE;
  v_payment numeric(12,2);
BEGIN
  IF auth.uid() IS NULL OR auth.uid() <> p_user_id THEN
    RAISE EXCEPTION 'statement payment requires the owning user';
  END IF;
  PERFORM set_config('cardcompass.reconciliation_write', 'on', true);

  SELECT * INTO v_statement FROM public.statements
  WHERE id = p_statement_id AND user_id = p_user_id AND user_card_id = p_user_card_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'statement is not owned by the supplied user and card';
  END IF;
  v_payment := CASE WHEN p_mark_paid THEN v_statement.total_amount - v_statement.paid_amount ELSE p_payment_amount END;
  IF v_payment <= 0 OR v_payment > v_statement.total_amount - v_statement.paid_amount THEN
    RAISE EXCEPTION 'payment amount must be positive and no greater than the remaining balance';
  END IF;
  UPDATE public.statements
  SET paid_amount = paid_amount + v_payment,
      payment_status = CASE WHEN paid_amount + v_payment >= total_amount THEN 'paid' ELSE 'partial' END,
      -- Preserve the time of the first recorded allocation, including partials.
      paid_at = COALESCE(paid_at, NOW())
  WHERE id = p_statement_id AND user_id = p_user_id AND user_card_id = p_user_card_id;
  RETURN jsonb_build_object('payment_amount', v_payment);
END;
$$;
