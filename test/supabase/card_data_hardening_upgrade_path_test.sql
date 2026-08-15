-- Run after `supabase db reset` with:
--   psql --set ON_ERROR_STOP=1 postgresql://postgres:postgres@127.0.0.1:54322/postgres \
--     -f test/supabase/card_data_hardening_upgrade_path_test.sql
--
-- This transaction restores the legacy columns and unsafe signatures, applies
-- the real forward migration again, and verifies the upgraded catalog state.
BEGIN;

ALTER TABLE public.user_cards
  ADD COLUMN card_number text,
  ADD COLUMN expiry_date text;

CREATE FUNCTION public.associate_user_with_card(
  _user_id uuid,
  _catalog_card_id uuid,
  _last_four_digits text DEFAULT NULL,
  _card_number text DEFAULT NULL,
  _expiry_date text DEFAULT NULL,
  _card_holder_name text DEFAULT NULL,
  _credit_limit numeric DEFAULT NULL,
  _statement_date integer DEFAULT NULL,
  _due_date integer DEFAULT NULL
) RETURNS uuid
LANGUAGE sql
AS $$ SELECT NULL::uuid $$;

CREATE FUNCTION public.update_user_card(
  _user_id uuid,
  _catalog_card_id uuid,
  _last_four_digits text DEFAULT NULL,
  _credit_limit numeric DEFAULT NULL,
  _card_holder_name text DEFAULT NULL,
  _expiry_date text DEFAULT NULL,
  _statement_date integer DEFAULT NULL,
  _due_date integer DEFAULT NULL
) RETURNS boolean
LANGUAGE sql
AS $$ SELECT false $$;

CREATE FUNCTION public.get_user_cards(_user_id uuid)
RETURNS TABLE(
  id uuid,
  user_id uuid,
  catalog_card_id uuid,
  last_four_digits text,
  card_number text,
  expiry_date text,
  card_holder_name text,
  credit_limit numeric,
  statement_date integer,
  due_date integer,
  is_active boolean,
  created_at timestamptz,
  updated_at timestamptz,
  bank text,
  card_name text,
  network text,
  card_type text,
  joining_fee numeric,
  annual_fee numeric,
  apr numeric,
  is_discontinued boolean
)
LANGUAGE sql
AS $$
  SELECT
    NULL::uuid, NULL::uuid, NULL::uuid, NULL::text, NULL::text, NULL::text,
    NULL::text, NULL::numeric, NULL::integer, NULL::integer, NULL::boolean,
    NULL::timestamptz, NULL::timestamptz, NULL::text, NULL::text, NULL::text,
    NULL::text, NULL::numeric, NULL::numeric, NULL::numeric, NULL::boolean
  WHERE false
$$;

GRANT EXECUTE ON FUNCTION public.associate_user_with_card(
  uuid, uuid, text, text, text, text, numeric, integer, integer
) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.update_user_card(
  uuid, uuid, text, numeric, text, text, integer, integer
) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_user_cards(uuid) TO anon, authenticated;

\ir ../../supabase/migrations/20260815090910_remove_legacy_card_secrets.sql

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'user_cards'
      AND column_name IN ('card_number', 'expiry_date')
  ) THEN
    RAISE EXCEPTION 'legacy PAN or expiry storage still exists';
  END IF;

  IF to_regprocedure(
    'public.associate_user_with_card(uuid,uuid,text,text,text,text,numeric,integer,integer)'
  ) IS NOT NULL THEN
    RAISE EXCEPTION 'unsafe associate_user_with_card overload still exists';
  END IF;

  IF to_regprocedure(
    'public.update_user_card(uuid,uuid,text,numeric,text,text,integer,integer)'
  ) IS NOT NULL THEN
    RAISE EXCEPTION 'unsafe update_user_card overload still exists';
  END IF;

  IF to_regprocedure('public.get_user_cards(uuid)') IS NOT NULL THEN
    RAISE EXCEPTION 'unsafe get_user_cards overload still exists';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'user_cards'
      AND column_name = 'last_four_digits'
  ) THEN
    RAISE EXCEPTION 'safe last-four storage was removed';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'user_cards'
      AND qual ILIKE '%auth.uid()%user_id%'
      -- PostgreSQL uses USING as WITH CHECK when WITH CHECK is omitted.
      AND COALESCE(with_check, qual) ILIKE '%auth.uid()%user_id%'
  ) THEN
    RAISE EXCEPTION 'user_cards ownership policy is missing';
  END IF;
END;
$$;

ROLLBACK;
