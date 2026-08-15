import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/repository_providers.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../../core/services/eligible_spend.dart';
import '../../../shared/models/transaction.dart';
import '../../../shared/models/user_card.dart';

enum TxnGrouping { flat, byCard, byCategory, byDate }

class TxnFilter {
  final String? cardId;
  final DateTime? from;
  final DateTime? to;
  final String? category;

  const TxnFilter({this.cardId, this.from, this.to, this.category});

  TxnFilter copyWith({
    Object? cardId = _sentinel,
    Object? from = _sentinel,
    Object? to = _sentinel,
    Object? category = _sentinel,
  }) {
    return TxnFilter(
      cardId: cardId == _sentinel ? this.cardId : cardId as String?,
      from: from == _sentinel ? this.from : from as DateTime?,
      to: to == _sentinel ? this.to : to as DateTime?,
      category: category == _sentinel ? this.category : category as String?,
    );
  }

  static const _sentinel = Object();

  String get label {
    final parts = <String>[];
    if (from != null && to != null) {
      parts.add('${_mon(from!)} – ${_mon(to!)}');
    } else if (from != null) {
      parts.add('From ${_mon(from!)}');
    }
    if (category != null) parts.add(category!);
    return parts.isEmpty ? 'All time' : parts.join(' · ');
  }

  static String _mon(DateTime d) => '${d.day} ${_months[d.month - 1]}';
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
}

class TrendPoint {
  final DateTime date;
  final double total;
  const TrendPoint(this.date, this.total);
}

class SpendTrend {
  final List<TrendPoint> points;
  final double dailyAverage;
  final String? peakLabel;
  final double? percentVsPrior;

  const SpendTrend({
    required this.points,
    required this.dailyAverage,
    this.peakLabel,
    this.percentVsPrior,
  });
}

class TxnsState {
  final List<Transaction> all;
  final List<UserCard> cards;
  final TxnFilter filter;
  final TxnGrouping grouping;

  const TxnsState({
    this.all = const [],
    this.cards = const [],
    this.filter = const TxnFilter(),
    this.grouping = TxnGrouping.flat,
  });

  TxnsState copyWith({
    List<Transaction>? all,
    List<UserCard>? cards,
    TxnFilter? filter,
    TxnGrouping? grouping,
  }) => TxnsState(
    all: all ?? this.all,
    cards: cards ?? this.cards,
    filter: filter ?? this.filter,
    grouping: grouping ?? this.grouping,
  );

  List<Transaction> get filtered {
    var txns = all;
    if (filter.cardId != null)
      txns = txns.where((t) => t.userCardId == filter.cardId).toList();
    if (filter.from != null)
      txns = txns
          .where((t) => !t.transactionDate.isBefore(filter.from!))
          .toList();
    if (filter.to != null)
      txns = txns
          .where(
            (t) => !t.transactionDate.isAfter(
              filter.to!.add(const Duration(days: 1)),
            ),
          )
          .toList();
    if (filter.category != null)
      txns = txns
          .where(
            (t) => t.category?.toLowerCase() == filter.category!.toLowerCase(),
          )
          .toList();
    return txns;
  }

  double get totalSpend =>
      filtered.where(isEligibleRetailSpend).fold(0, (s, t) => s + t.amount);
  double get totalRewards =>
      filtered.fold(0, (s, t) => s + (t.rewardEarned ?? 0));
  String? get topCategory {
    final map = <String, double>{};
    for (final t in filtered) {
      if (isEligibleRetailSpend(t) && t.category != null) {
        map[t.category!] = (map[t.category!] ?? 0) + t.amount;
      }
    }
    if (map.isEmpty) return null;
    return map.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }

  Map<String, List<Transaction>> get grouped {
    final txns = filtered;
    switch (grouping) {
      case TxnGrouping.flat:
        return {'All': txns};
      case TxnGrouping.byCard:
        final m = <String, List<Transaction>>{};
        for (final t in txns) {
          (m[t.userCardId] ??= []).add(t);
        }
        return m;
      case TxnGrouping.byCategory:
        final m = <String, List<Transaction>>{};
        for (final t in txns) {
          (m[t.category ?? 'Other'] ??= []).add(t);
        }
        return m;
      case TxnGrouping.byDate:
        final m = <String, List<Transaction>>{};
        for (final t in txns) {
          final d = t.transactionDate.toLocal();
          final key = '${d.day} ${_TxnsState._months[d.month - 1]} ${d.year}';
          (m[key] ??= []).add(t);
        }
        return m;
    }
  }

  SpendTrend get spendTrend {
    final txns = filtered.where(isEligibleRetailSpend).toList();
    if (txns.isEmpty) return const SpendTrend(points: [], dailyAverage: 0);

    // bucket by day
    final byDay = <String, double>{};
    final dayMap = <String, DateTime>{};
    for (final t in txns) {
      final d = t.transactionDate.toLocal();
      final key =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      byDay[key] = (byDay[key] ?? 0) + t.amount;
      dayMap[key] = DateTime(d.year, d.month, d.day);
    }
    final keys = byDay.keys.toList()..sort();
    final points = keys.map((k) => TrendPoint(dayMap[k]!, byDay[k]!)).toList();

    final total = points.fold(0.0, (s, p) => s + p.total);
    final avg = points.isEmpty ? 0.0 : total / points.length;

    TrendPoint? peak;
    for (final p in points) {
      if (peak == null || p.total > peak.total) peak = p;
    }
    String? peakLabel;
    if (peak != null) {
      final d = peak.date;
      peakLabel = '${d.day} ${_TxnsState._months[d.month - 1]}';
    }

    // prior period comparison
    double? percentVsPrior;
    if (filter.from != null && filter.to != null) {
      final duration = filter.to!.difference(filter.from!);
      final priorFrom = filter.from!.subtract(duration);
      final priorTo = filter.from!.subtract(const Duration(days: 1));
      final priorTotal = all
          .where(
            (t) =>
                isEligibleRetailSpend(t) &&
                !t.transactionDate.isBefore(priorFrom) &&
                !t.transactionDate.isAfter(
                  priorTo.add(const Duration(days: 1)),
                ),
          )
          .fold(0.0, (s, t) => s + t.amount);
      if (priorTotal > 0) {
        percentVsPrior = (total - priorTotal) / priorTotal * 100;
      }
    }

    return SpendTrend(
      points: points,
      dailyAverage: avg,
      peakLabel: peakLabel,
      percentVsPrior: percentVsPrior,
    );
  }
}

// ignore: library_private_types_in_public_api
class _TxnsState {
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
}

class TxnsNotifier extends AsyncNotifier<TxnsState> {
  @override
  Future<TxnsState> build() async {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const TxnsState();

    final txnRepo = ref.read(transactionsRepositoryProvider);
    final cardsRepo = ref.read(cardsRepositoryProvider);

    final results = await Future.wait([
      txnRepo.getTransactions(userId: user.id, limit: 500),
      cardsRepo.getUserCards(user.id),
    ]);

    return TxnsState(
      all: results[0] as List<Transaction>,
      cards: results[1] as List<UserCard>,
      filter: _defaultThisMonthFilter(),
    );
  }

  TxnFilter _defaultThisMonthFilter() {
    final now = DateTime.now();
    return TxnFilter(from: DateTime(now.year, now.month, 1));
  }

  void setFilter(TxnFilter filter) {
    state = state.whenData((s) => s.copyWith(filter: filter));
  }

  void setGrouping(TxnGrouping g) {
    state = state.whenData((s) => s.copyWith(grouping: g));
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }
}

final txnsNotifierProvider = AsyncNotifierProvider<TxnsNotifier, TxnsState>(
  TxnsNotifier.new,
);
