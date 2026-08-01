import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../repositories/cards_repository.dart';
import '../repositories/transactions_repository.dart';
import '../repositories/statements_repository.dart';
import 'supabase_provider.dart';

final cardsRepositoryProvider = Provider<CardsRepository>((ref) {
  return CardsRepository(ref.watch(supabaseClientProvider));
});

final transactionsRepositoryProvider = Provider<TransactionsRepository>((ref) {
  return TransactionsRepository(ref.watch(supabaseClientProvider));
});

final statementsRepositoryProvider = Provider<StatementsRepository>((ref) {
  return StatementsRepository(ref.watch(supabaseClientProvider));
});
