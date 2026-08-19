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
