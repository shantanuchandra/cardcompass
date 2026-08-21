BEGIN;

SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '60s';

DO $user_owned_rls_policy_preflight$
BEGIN
  IF NOT EXISTS (
       SELECT 1 FROM pg_policies
       WHERE schemaname = 'public'
         AND tablename = 'user_cards'
         AND policyname = 'user_cards_policy'
         AND cmd = 'ALL'
         AND roles @> ARRAY['authenticated']::name[]
         AND qual = '(auth.uid() = user_id)'
     )
     OR NOT EXISTS (
       SELECT 1 FROM pg_policies
       WHERE schemaname = 'public'
         AND tablename = 'statement_milestone_cache'
         AND policyname = 'statement_milestone_user_policy'
         AND cmd = 'ALL'
         AND roles @> ARRAY['authenticated']::name[]
         AND qual = '(auth.uid() = user_id)'
     ) THEN
    RAISE EXCEPTION 'user_owned_rls_policy_preflight_failed';
  END IF;
END;
$user_owned_rls_policy_preflight$;

ALTER TABLE public.user_cards ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.statement_milestone_cache ENABLE ROW LEVEL SECURITY;

DO $user_owned_rls_enabled_assertions$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_class AS relation
    JOIN pg_namespace AS namespace ON namespace.oid = relation.relnamespace
    WHERE namespace.nspname = 'public'
      AND relation.relname IN ('user_cards', 'statement_milestone_cache')
      AND NOT relation.relrowsecurity
  ) THEN
    RAISE EXCEPTION 'user_owned_rls_enable_failed';
  END IF;
END;
$user_owned_rls_enabled_assertions$;

COMMIT;
