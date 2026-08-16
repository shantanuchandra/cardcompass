const localSupabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

final localSupabaseSkipReason = localSupabaseAnonKey.isEmpty
    ? 'Requires a running local Supabase instance and SUPABASE_ANON_KEY.'
    : null;
