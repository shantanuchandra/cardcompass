import 'package:cardcompass/core/providers/supabase_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_provider.dart';
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

/// The identity is a cache partition only. It is never sent as an
/// authorization claim; the gateway authenticates its bearer token and reads
/// the current database flags on every request.
final adminAccessIdentityProvider = Provider<String?>((ref) {
  final auth = ref.watch(authNotifierProvider);
  if (auth.valueOrNull == AuthStatus.unauthenticated) return null;
  return ref.watch(authSessionAccessProvider).currentUserId;
});

final _adminRouteAccessByIdentityProvider = FutureProvider.autoDispose
    .family<AdminAccess, String>((ref, _) {
      return ref.watch(adminOperatorRepositoryProvider).access();
    });

final _adminEntryAccessByIdentityProvider = FutureProvider.autoDispose
    .family<AdminAccess, String>((ref, _) {
      return ref.watch(adminOperatorRepositoryProvider).access();
    });

/// A direct Admin2 mount always uses the route-specific cache. It never reuses
/// an entry-visibility result from the ordinary app shell.
final adminAccessProvider = FutureProvider.autoDispose<AdminAccess>((ref) {
  final identity = ref.watch(adminAccessIdentityProvider);
  if (identity == null) return const AdminAccess(isAdmin: false);
  return ref.watch(_adminRouteAccessByIdentityProvider(identity).future);
});

/// Cached presentation state derived solely from the operator gateway access
/// response. Unauthenticated sessions are hidden without a gateway request.
final adminEntryVisibilityProvider = Provider.autoDispose<AsyncValue<bool>>((
  ref,
) {
  final identity = ref.watch(adminAccessIdentityProvider);
  if (identity == null) return const AsyncValue.data(false);
  return ref
      .watch(_adminEntryAccessByIdentityProvider(identity))
      .whenData((access) => access.isAdmin);
});
