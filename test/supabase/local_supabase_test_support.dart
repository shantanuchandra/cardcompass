const localSupabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
const localSupabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'http://127.0.0.1:54321',
);
const runSupabaseIntegration = bool.fromEnvironment(
  'RUN_SUPABASE_INTEGRATION',
);

final localSupabaseSkipReason = !runSupabaseIntegration
    ? 'Requires RUN_SUPABASE_INTEGRATION=true.'
    : localSupabaseAnonKey.isEmpty
    ? 'Requires SUPABASE_ANON_KEY.'
    : null;
