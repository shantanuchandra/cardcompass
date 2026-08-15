-- Remove the legacy capability to store or exchange primary account numbers
-- and card expiry values. Current application flows use catalog identity and
-- last four digits only.

-- Revoke every historical overload before dropping it so no caller retains a
-- window of access during the transactional migration.
REVOKE ALL ON FUNCTION public.associate_user_with_card(
  uuid, uuid, text, text, text, text, numeric, integer, integer
) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.update_user_card(
  uuid, uuid, text, numeric, text, text, integer, integer
) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_user_cards(uuid)
  FROM PUBLIC, anon, authenticated, service_role;

DROP FUNCTION IF EXISTS public.associate_user_with_card(
  uuid, uuid, text, text, text, text, numeric, integer, integer
);
DROP FUNCTION IF EXISTS public.update_user_card(
  uuid, uuid, text, numeric, text, text, integer, integer
);
DROP FUNCTION IF EXISTS public.get_user_cards(uuid);

-- Take an exclusive lock, overwrite any historical values, then remove the
-- storage columns in the same transaction. The explicit overwrite prevents
-- old values from surviving in the live row version while the DDL completes.
LOCK TABLE public.user_cards IN ACCESS EXCLUSIVE MODE;
UPDATE public.user_cards
SET card_number = NULL,
    expiry_date = NULL
WHERE card_number IS NOT NULL
   OR expiry_date IS NOT NULL;

ALTER TABLE public.user_cards
  DROP COLUMN IF EXISTS card_number,
  DROP COLUMN IF EXISTS expiry_date;

COMMENT ON TABLE public.user_cards IS
  'User-owned credit cards linked to catalog; stores last four digits only, never PAN or expiry.';
