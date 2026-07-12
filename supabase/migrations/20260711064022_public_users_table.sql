-- public.users was missing from schema.sql entirely, despite being actively
-- used by the app (auth_service_impl.dart, supabase_user_repository.dart,
-- user_profile_database_service.dart all read/write .from('users')). It
-- existed in the old live database (captured in the db_cluster backup) but
-- was never captured in the canonical schema.sql file. Adding it here so the
-- app's user-profile flows actually work against the new project.

CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email TEXT NOT NULL UNIQUE,
  full_name TEXT,
  avatar_url TEXT,
  phone TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  preferences JSONB DEFAULT '{}',
  is_active BOOLEAN DEFAULT true,
  given_name TEXT,
  family_name TEXT,
  date_of_birth DATE,
  profile_data JSONB DEFAULT '{}'
);

CREATE INDEX IF NOT EXISTS idx_users_date_of_birth ON users(date_of_birth);
CREATE INDEX IF NOT EXISTS idx_users_profile_data_gin ON users USING gin(profile_data);

ALTER TABLE users ENABLE ROW LEVEL SECURITY;

CREATE POLICY users_own_data_policy ON users
  FOR ALL TO authenticated
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

GRANT SELECT, INSERT, UPDATE, DELETE ON users TO authenticated;

CREATE TRIGGER update_users_updated_at
  BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
