import 'package:cardcompass/core/providers/supabase_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/admin_operator_api.dart';
import '../data/admin_operator_repository.dart';

final adminOperatorRepositoryProvider = Provider<AdminOperatorRepository>((
  ref,
) {
  return AdminOperatorRepository(
    SupabaseAdminOperatorApi(ref.watch(supabaseClientProvider)),
  );
});
