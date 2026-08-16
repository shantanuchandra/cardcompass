BEGIN;

-- These two append-only tables previously allowed no user deletion. The reset
-- function remains SECURITY INVOKER, so narrowly permit authenticated users to
-- delete only their own rows through the same RLS boundary.
DROP POLICY IF EXISTS "authenticated delete own confirmation"
  ON public.benefit_platform_confirmations;
CREATE POLICY "authenticated delete own confirmation"
  ON public.benefit_platform_confirmations FOR DELETE
  TO authenticated
  USING ((SELECT auth.uid()) = user_id);
GRANT DELETE ON public.benefit_platform_confirmations TO authenticated;

DROP POLICY IF EXISTS "authenticated delete own gemini usage"
  ON public.gemini_proxy_usage;
CREATE POLICY "authenticated delete own gemini usage"
  ON public.gemini_proxy_usage FOR DELETE
  TO authenticated
  USING ((SELECT auth.uid()) = user_id);
GRANT DELETE ON public.gemini_proxy_usage TO authenticated;

CREATE OR REPLACE FUNCTION public.reset_my_cardcompass_data()
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  current_user_id uuid := auth.uid();
BEGIN
  IF current_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;

  DELETE FROM public.transactions WHERE user_id = current_user_id;
  DELETE FROM public.emails WHERE user_id = current_user_id;
  DELETE FROM public.statement_milestone_cache WHERE user_id = current_user_id;
  DELETE FROM public.statements WHERE user_id = current_user_id;
  DELETE FROM public.benefit_platform_confirmations
    WHERE user_id = current_user_id;
  DELETE FROM public.gemini_proxy_usage WHERE user_id = current_user_id;
  DELETE FROM public.user_cards WHERE user_id = current_user_id;

  UPDATE public.users
  SET preferences = '{}'::jsonb,
      updated_at = now()
  WHERE id = current_user_id;
END;
$$;

REVOKE ALL ON FUNCTION public.reset_my_cardcompass_data() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reset_my_cardcompass_data() TO authenticated;

COMMIT;
