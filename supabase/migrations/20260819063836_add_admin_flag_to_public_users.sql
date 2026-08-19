ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS is_admin boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.users.is_admin IS
  'Server-governed access flag for the CardCompass operator console.';

UPDATE public.users
SET is_admin = true
WHERE lower(email) = 'shantanu.msp@gmail.com';

-- The existing own-row RLS policy permits authenticated inserts and updates.
-- Replace table-wide write privileges with column grants so clients cannot
-- assign or change the server-governed admin flag.
REVOKE INSERT, UPDATE ON TABLE public.users FROM authenticated;

GRANT INSERT (
  id,
  email,
  full_name,
  avatar_url,
  phone,
  created_at,
  updated_at,
  preferences,
  is_active,
  given_name,
  family_name,
  date_of_birth,
  profile_data
) ON TABLE public.users TO authenticated;

GRANT UPDATE (
  id,
  email,
  full_name,
  avatar_url,
  phone,
  created_at,
  updated_at,
  preferences,
  is_active,
  given_name,
  family_name,
  date_of_birth,
  profile_data
) ON TABLE public.users TO authenticated;
