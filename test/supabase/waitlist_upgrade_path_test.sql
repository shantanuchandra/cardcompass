-- Run with:
--   psql --set ON_ERROR_STOP=1 postgresql://postgres:postgres@127.0.0.1:54322/postgres \
--     -f test/supabase/waitlist_upgrade_path_test.sql
--
-- This is an isolated transaction that recreates the pre-upgrade waitlist
-- shape, applies the real forward migration, and verifies the data upgrade
-- plus ACLs through PostgreSQL's privilege API (not RLS behavior).
BEGIN;

DROP VIEW IF EXISTS public.operator_waitlist_ranked;
DROP FUNCTION IF EXISTS public.join_waitlist(
  text, text, text, text, text, text, text, text, text, boolean
);
DROP FUNCTION IF EXISTS public.enrich_waitlist(
  text, text, text, text, text, text, text[], boolean
);
ALTER INDEX IF EXISTS public.waitlist_enrichment_token_hash_key
  RENAME TO waitlist_enrichment_token_hash_key_upgrade_backup;
ALTER INDEX IF EXISTS public.waitlist_email_lower_key
  RENAME TO waitlist_email_lower_key_upgrade_backup;
ALTER TABLE public.waitlist RENAME TO waitlist_post_upgrade_backup;

CREATE TABLE public.waitlist (
  id uuid CONSTRAINT waitlist_upgrade_fixture_pkey PRIMARY KEY DEFAULT gen_random_uuid(),
  email text NOT NULL CONSTRAINT waitlist_upgrade_fixture_email_key UNIQUE,
  name text,
  card_count text CONSTRAINT waitlist_card_count_check
    CHECK (card_count IN ('1-2', '3-5', '6+') OR card_count IS NULL),
  created_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO public.waitlist (id, email, name, card_count, created_at) VALUES
  (
    '10000000-0000-0000-0000-000000000001',
    'Aarav@Example.com',
    NULL,
    NULL,
    '2026-01-01T00:00:00Z'
  ),
  (
    '10000000-0000-0000-0000-000000000002',
    'aarav@example.com',
    'Aarav',
    '3-5',
    '2026-01-02T00:00:00Z'
  ),
  (
    '10000000-0000-0000-0000-000000000003',
    'legacy-band@example.com',
    'Diya',
    '6+',
    '2026-01-03T00:00:00Z'
  );

\ir ../../supabase/migrations/20260815073740_secure_waitlist_operator_workflow.sql

DO $$
DECLARE
  privilege_name text;
  role_name text;
BEGIN
  IF (SELECT count(*) FROM public.waitlist WHERE lower(email) = 'aarav@example.com') <> 1 THEN
    RAISE EXCEPTION 'case-colliding legacy rows were not merged';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.waitlist
    WHERE id = '10000000-0000-0000-0000-000000000001'
      AND email = 'aarav@example.com'
      AND name = 'Aarav'
      AND card_count = '3-6'
      AND created_at = '2026-01-01T00:00:00Z'
  ) THEN
    RAISE EXCEPTION 'legacy merge did not preserve the earliest row and non-null enrichment';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.waitlist
    WHERE email = 'legacy-band@example.com' AND card_count = '7+'
  ) THEN
    RAISE EXCEPTION 'legacy card count was not upgraded after dropping its old constraint';
  END IF;

  BEGIN
    INSERT INTO public.waitlist (email) VALUES ('AARAV@EXAMPLE.COM');
    RAISE EXCEPTION 'case-insensitive waitlist email uniqueness is missing';
  EXCEPTION
    WHEN unique_violation THEN NULL;
  END;

  FOREACH role_name IN ARRAY ARRAY['anon', 'authenticated'] LOOP
    FOREACH privilege_name IN ARRAY ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE'] LOOP
      IF has_table_privilege(role_name, 'public.waitlist', privilege_name) THEN
        RAISE EXCEPTION '% unexpectedly has % on public.waitlist',
          role_name, privilege_name;
      END IF;
    END LOOP;
  END LOOP;

  IF NOT has_table_privilege('service_role', 'public.waitlist', 'SELECT') THEN
    RAISE EXCEPTION 'service_role needs SELECT on public.waitlist for the security-invoker operator view';
  END IF;

  IF NOT has_table_privilege('service_role', 'public.operator_waitlist_ranked', 'SELECT') THEN
    RAISE EXCEPTION 'service_role cannot read public.operator_waitlist_ranked';
  END IF;
END;
$$;

ROLLBACK;
