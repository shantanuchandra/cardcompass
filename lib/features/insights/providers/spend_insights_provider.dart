import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/repository_providers.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../../core/repositories/transactions_repository.dart';
import '../../../core/services/spend_insight_aggregator.dart';
import '../../../shared/models/transaction.dart';
import '../domain/spend_insight.dart';

class InsightPeriod {
  const InsightPeriod(this.start, this.end);

  final DateTime start;
  final DateTime end;

  factory InsightPeriod.initial(DateTime now) =>
      InsightPeriod(now.subtract(const Duration(days: 60)), now);

  @override
  bool operator ==(Object other) =>
      other is InsightPeriod && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

abstract interface class SpendInsightsTransactionReader {
  Future<List<Transaction>> getTransactions({
    required String userId,
    required DateTime from,
    required DateTime to,
    required int limit,
  });
}

class _RepositoryTransactionReader implements SpendInsightsTransactionReader {
  const _RepositoryTransactionReader(this._repository);

  final TransactionsRepository _repository;

  @override
  Future<List<Transaction>> getTransactions({
    required String userId,
    required DateTime from,
    required DateTime to,
    required int limit,
  }) {
    return _repository.getTransactions(
      userId: userId,
      from: from,
      to: to,
      limit: limit,
    );
  }
}

final spendInsightsClockProvider = Provider<DateTime Function()>(
  (_) => DateTime.now,
);

final spendInsightsUserIdProvider = Provider<String?>((ref) {
  return ref.watch(currentUserProvider)?.id;
});

final spendInsightsTransactionReaderProvider =
    Provider<SpendInsightsTransactionReader>((ref) {
      return _RepositoryTransactionReader(
        ref.watch(transactionsRepositoryProvider),
      );
    });

class SpendInsightsNotifier extends AsyncNotifier<List<SpendInsight>> {
  late InsightPeriod _period;

  InsightPeriod get period => _period;

  @override
  Future<List<SpendInsight>> build() async {
    _period = InsightPeriod.initial(ref.watch(spendInsightsClockProvider)());
    return _load();
  }

  Future<void> setPeriod(InsightPeriod period) async {
    if (period.end.isBefore(period.start)) {
      throw ArgumentError.value(period, 'period', 'end must not precede start');
    }
    _period = period;
    await reload();
  }

  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_load);
  }

  Future<List<SpendInsight>> _load() async {
    final userId = ref.read(spendInsightsUserIdProvider);
    if (userId == null) throw StateError('Not authenticated');

    final transactions = await ref
        .read(spendInsightsTransactionReaderProvider)
        .getTransactions(
          userId: userId,
          from: _period.start,
          to: _period.end,
          limit: 2000,
        );
    return buildSpendInsights(
      transactions: transactions,
      periodStart: _period.start,
      periodEnd: _period.end,
    );
  }
}

final spendInsightsProvider =
    AsyncNotifierProvider<SpendInsightsNotifier, List<SpendInsight>>(
      SpendInsightsNotifier.new,
    );
