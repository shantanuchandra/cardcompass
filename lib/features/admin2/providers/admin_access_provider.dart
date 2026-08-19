import 'package:cardcompass/core/providers/supabase_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/admin_operator_api.dart';
import '../data/admin_operator_repository.dart';
import '../models/admin_access.dart';

final adminOperatorRepositoryProvider = Provider<AdminOperatorRepository>((
  ref,
) {
  return AdminOperatorRepository(
    SupabaseAdminOperatorApi(ref.watch(supabaseClientProvider)),
  );
});

final adminAccessProvider = FutureProvider<AdminAccess>((ref) {
  return ref.watch(adminOperatorRepositoryProvider).access();
});

/// Cached presentation state derived solely from the operator gateway access
/// response. Route visibility is a convenience; the destination still checks
/// [adminAccessProvider] when mounted.
final adminEntryVisibilityProvider = Provider<AsyncValue<bool>>((ref) {
  return ref.watch(adminAccessProvider).whenData((access) => access.isAdmin);
});
