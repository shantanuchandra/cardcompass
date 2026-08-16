BEGIN;

CREATE SCHEMA IF NOT EXISTS private;
REVOKE ALL ON SCHEMA private FROM PUBLIC;
GRANT USAGE ON SCHEMA private TO authenticated;

CREATE OR REPLACE FUNCTION private.reset_my_cardcompass_data()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
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

REVOKE ALL ON FUNCTION private.reset_my_cardcompass_data() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION private.reset_my_cardcompass_data()
  TO authenticated;

CREATE OR REPLACE FUNCTION public.reset_my_cardcompass_data()
RETURNS void
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT private.reset_my_cardcompass_data();
$$;

REVOKE ALL ON FUNCTION public.reset_my_cardcompass_data() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reset_my_cardcompass_data() TO authenticated;

DROP POLICY IF EXISTS "authenticated delete own confirmation"
  ON public.benefit_platform_confirmations;
REVOKE DELETE ON public.benefit_platform_confirmations FROM authenticated;

DROP POLICY IF EXISTS "authenticated delete own gemini usage"
  ON public.gemini_proxy_usage;
REVOKE DELETE ON public.gemini_proxy_usage FROM authenticated;

COMMIT;
