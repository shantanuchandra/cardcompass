import 'dart:collection';

import 'package:cardcompass/features/dashboard/domain/dashboard_metrics.dart';
import 'package:cardcompass/features/transactions/providers/transactions_provider.dart';
import 'package:cardcompass/shared/models/transaction.dart';
import 'package:cardcompass/shared/models/user_card.dart';
import 'package:flutter_test/flutter_test.dart';

Transaction _transaction({
  required String id,
  TransactionType type = TransactionType.debit,
  required double amount,
  String category = 'food',
  Map<String, dynamic> metadata = const {},
  String userCardId = 'card-1',
  String currency = 'INR',
  String? description,
  DateTime? date,
  double? rewardEarned,
}) {
  final transactionDate = date ?? DateTime(2026, 8, 1);
  return Transaction(
    id: id,
    userId: 'user-1',
    userCardId: userCardId,
    amount: amount,
    currency: currency,
    description: description ?? id,
    category: category,
    transactionType: type,
    transactionDate: transactionDate,
    rewardEarned: rewardEarned,
    metadata: metadata,
    createdAt: transactionDate,
  );
}

UserCard _userCard({required String id, String? bank}) {
  return UserCard(
    id: id,
    userId: 'user-1',
    catalogCardId: 'catalog-1',
    createdAt: DateTime(2026, 8, 1),
    bank: bank,
  );
}

class _TraversalCountingList extends ListBase<Transaction> {
  _TraversalCountingList(this._rows);

  final List<Transaction> _rows;
  int traversals = 0;

  @override
  int get length => _rows.length;

  @override
  set length(int value) => _rows.length = value;

  @override
  Transaction operator [](int index) => _rows[index];

  @override
  void operator []=(int index, Transaction value) => _rows[index] = value;

  @override
  Iterator<Transaction> get iterator {
    traversals++;
    return _rows.iterator;
  }
}

void main() {
  test('totals and top category include eligible retail spend only', () {
    final state = TxnsState(
      all: [
        _transaction(
          id: 'purchase',
          type: TransactionType.debit,
          amount: 500,
          category: 'grocery',
        ),
        _transaction(id: 'fee', type: TransactionType.fee, amount: 100),
        _transaction(id: 'refund', type: TransactionType.refund, amount: 200),
        _transaction(
          id: 'withdrawal',
          type: TransactionType.debit,
          amount: 1000,
          metadata: const {'normalized_transaction_type': 'cash_withdrawal'},
        ),
      ],
    );

    expect(state.totalSpend, 500);
    expect(state.topCategory, 'grocery');
    expect(state.spendTrend.points.single.total, 500);
  });

  test('current-period aggregates match the Dashboard canonical policy', () {
    final reportingCutoff = DateTime(2026, 8, 17, 12);
    final purchaseDate = DateTime(2026, 8, 5, 9);
    final rows = [
      _transaction(
        id: 'purchase',
        amount: 100,
        category: 'grocery',
        description: 'Same billed purchase',
        date: purchaseDate,
        rewardEarned: 10,
      ),
      _transaction(
        id: 'duplicate-id',
        amount: 100,
        category: 'grocery',
        description: 'Same billed purchase',
        date: purchaseDate,
        rewardEarned: 90,
      ),
      _transaction(
        id: 'future',
        amount: 500,
        category: 'travel',
        date: reportingCutoff.add(const Duration(microseconds: 1)),
        rewardEarned: 50,
      ),
      _transaction(
        id: 'cash',
        amount: 300,
        category: 'grocery',
        date: DateTime(2026, 8, 6),
        rewardEarned: 30,
        metadata: const {'normalized_transaction_type': 'cash_withdrawal'},
      ),
      _transaction(
        id: 'refund',
        type: TransactionType.refund,
        amount: 40,
        category: 'grocery',
        date: DateTime(2026, 8, 7),
        rewardEarned: 7,
      ),
      _transaction(
        id: 'credit',
        type: TransactionType.credit,
        amount: 60,
        category: 'grocery',
        date: DateTime(2026, 8, 8),
        rewardEarned: 8,
      ),
      _transaction(
        id: 'negative-reward',
        amount: 25,
        category: 'travel',
        date: DateTime(2026, 8, 9),
        rewardEarned: -2,
      ),
      _transaction(
        id: 'nan-reward',
        amount: 75,
        category: 'grocery',
        date: DateTime(2026, 8, 10),
        rewardEarned: double.nan,
      ),
    ];
    final dashboard = calculateDashboardMetrics(
      cards: const [],
      transactions: rows,
      trendStart: DateTime(2026, 8, 1),
      periodEnd: reportingCutoff,
      monthCount: 1,
    );
    final state = TxnsState(
      all: rows,
      filter: TxnFilter(from: DateTime(2026, 8, 1)),
      reportingCutoff: reportingCutoff,
    );

    expect(state.totalSpend, dashboard.monthlySpendTrend.single);
    expect(state.totalRewards, dashboard.monthlyRewardsTrend.single);
    expect(state.totalSpend, 200);
    expect(state.totalRewards, 10);
    expect(state.topCategory, 'grocery');
    expect(
      state.spendTrend.points
          .map((point) => (point.date, point.total))
          .toList(),
      [
        (DateTime(2026, 8, 5), 100),
        (DateTime(2026, 8, 9), 25),
        (DateTime(2026, 8, 10), 75),
      ],
    );
    expect(state.filtered.map((transaction) => transaction.id), [
      'purchase',
      'duplicate-id',
      'cash',
      'refund',
      'credit',
      'negative-reward',
      'nan-reward',
    ]);
  });

  test('explicit calendar end excludes exactly next-day midnight', () {
    final state = TxnsState(
      all: [
        _transaction(
          id: 'end-of-day',
          amount: 100,
          date: DateTime(2026, 8, 5, 23, 59, 59, 999, 999),
        ),
        _transaction(
          id: 'next-midnight',
          amount: 200,
          date: DateTime(2026, 8, 6),
        ),
      ],
      filter: TxnFilter(from: DateTime(2026, 8, 1), to: DateTime(2026, 8, 5)),
      reportingCutoff: DateTime(2026, 8, 31),
    );

    expect(state.filtered.map((transaction) => transaction.id), ['end-of-day']);
    expect(state.totalSpend, 100);
  });

  test(
    'all-time retains history but excludes rows after its captured cutoff',
    () {
      final reportingCutoff = DateTime(2026, 8, 17, 12);
      final state = TxnsState(
        all: [
          _transaction(id: 'history', amount: 100, date: DateTime(2024, 1, 1)),
          _transaction(id: 'at-cutoff', amount: 200, date: reportingCutoff),
          _transaction(
            id: 'future',
            amount: 500,
            date: reportingCutoff.add(const Duration(microseconds: 1)),
          ),
        ],
        reportingCutoff: reportingCutoff,
      );

      expect(state.filtered.map((transaction) => transaction.id), [
        'history',
        'at-cutoff',
      ]);
      expect(state.totalSpend, 300);
    },
  );

  test(
    'prior-period comparison uses canonical purchases for equal date spans',
    () {
      final state = TxnsState(
        all: [
          _transaction(id: 'current', amount: 200, date: DateTime(2026, 8, 10)),
          _transaction(
            id: 'prior',
            amount: 100,
            description: 'Prior natural key',
            date: DateTime(2026, 8, 9),
          ),
          _transaction(
            id: 'prior-duplicate',
            amount: 100,
            description: 'Prior natural key',
            date: DateTime(2026, 8, 9),
          ),
          _transaction(
            id: 'prior-cash',
            amount: 400,
            date: DateTime(2026, 8, 8),
            metadata: const {'normalized_transaction_type': 'cash_withdrawal'},
          ),
        ],
        filter: TxnFilter(
          from: DateTime(2026, 8, 10),
          to: DateTime(2026, 8, 11),
        ),
        reportingCutoff: DateTime(2026, 8, 31),
      );

      expect(state.spendTrend.percentVsPrior, 100);
    },
  );

  test(
    'category selection cannot resurrect a cross-category natural duplicate',
    () {
      final currentDate = DateTime(2026, 8, 10, 9);
      final priorDate = DateTime(2026, 8, 9, 9);
      final state = TxnsState(
        all: [
          _transaction(
            id: 'current-first-grocery',
            amount: 100,
            category: 'grocery',
            description: 'Current shared natural key',
            date: currentDate,
            rewardEarned: 10,
          ),
          _transaction(
            id: 'current-later-travel-duplicate',
            amount: 100,
            category: 'travel',
            description: 'Current shared natural key',
            date: currentDate,
            rewardEarned: 90,
          ),
          _transaction(
            id: 'current-unique-travel',
            amount: 200,
            category: 'travel',
            description: 'Unique travel purchase',
            date: currentDate.add(const Duration(hours: 1)),
            rewardEarned: 20,
          ),
          _transaction(
            id: 'prior-first-grocery',
            amount: 50,
            category: 'grocery',
            description: 'Prior shared natural key',
            date: priorDate,
            rewardEarned: 5,
          ),
          _transaction(
            id: 'prior-later-travel-duplicate',
            amount: 50,
            category: 'travel',
            description: 'Prior shared natural key',
            date: priorDate,
            rewardEarned: 45,
          ),
        ],
        filter: TxnFilter(
          from: DateTime(2026, 8, 10),
          to: DateTime(2026, 8, 10),
          category: 'travel',
        ),
        grouping: TxnGrouping.byCategory,
        reportingCutoff: DateTime(2026, 8, 31),
      );

      expect(state.filtered.map((transaction) => transaction.id), [
        'current-later-travel-duplicate',
        'current-unique-travel',
      ]);
      expect(state.totalSpend, 200);
      expect(state.totalRewards, 20);
      expect(state.topCategory, 'travel');
      expect(state.spendTrend.points.single.total, 200);
      expect(state.spendTrend.percentVsPrior, isNull);
      expect(state.canonicalSubtotal(state.grouped['travel']!), 200);
    },
  );

  test('one immutable state projection scans its source ledger once', () {
    final rows = _TraversalCountingList([
      _transaction(
        id: 'grocery',
        amount: 100,
        category: 'grocery',
        rewardEarned: 10,
      ),
      _transaction(id: 'travel', amount: 200, category: 'travel'),
      _transaction(id: 'food', amount: 300, category: 'food'),
    ]);
    final state = TxnsState(all: rows, grouping: TxnGrouping.byCategory);

    expect(state.totalSpend, 600);
    expect(state.totalRewards, 10);
    expect(state.topCategory, 'food');
    expect(state.spendTrend.points.single.total, 600);
    final groups = state.grouped;
    expect(state.canonicalSubtotal(groups['grocery']!), 100);
    expect(state.canonicalSubtotal(groups['travel']!), 200);
    expect(state.canonicalSubtotal(groups['food']!), 300);
    expect(rows.traversals, 1);
  });

  test('external list mutation cannot alter or stale a state projection', () {
    final purchase = _transaction(id: 'purchase', amount: 100);
    final card = _userCard(id: 'card-1', bank: 'HDFC');
    final rows = <Transaction>[purchase];
    final cards = <UserCard>[card];
    final state = TxnsState(all: rows, cards: cards);

    expect(state.totalSpend, 100);

    rows.clear();
    cards.clear();

    expect(state.all.map((transaction) => transaction.id), ['purchase']);
    expect(state.cards.map((userCard) => userCard.id), ['card-1']);
    expect(state.filtered.map((transaction) => transaction.id), ['purchase']);
    expect(() => state.all.clear(), throwsUnsupportedError);
    expect(() => state.cards.clear(), throwsUnsupportedError);
  });

  test('five-thousand-row ledger snapshot is flattened and indexed once', () {
    final rows = _TraversalCountingList(
      List.generate(
        5000,
        (index) => _transaction(
          id: 'txn-${index.toString().padLeft(4, '0')}',
          amount: index + 1,
          category: 'category-${index % 4}',
        ),
      ),
    );
    final state = TxnsState(all: rows, grouping: TxnGrouping.byCategory);
    final ledgerItems = state.ledgerItems;

    expect(ledgerItems, hasLength(5004));
    expect(identical(ledgerItems, state.ledgerItems), isTrue);
    expect(state.ledgerIndexForTransactionId('txn-0000'), 1);
    expect(state.ledgerIndexForTransactionId('txn-4999'), 5003);
    for (var index = 0; index < ledgerItems.length; index++) {
      expect(ledgerItems[index], isA<TxnLedgerItem>());
    }
    expect(rows.traversals, 1);
  });

  test('isTransactionInternational is false when the card is not found', () {
    final txn = _transaction(
      id: 'txn-1',
      type: TransactionType.debit,
      amount: 100,
      userCardId: 'card-missing',
      currency: 'USD',
    );
    final state = TxnsState(all: [txn], cards: const []);

    expect(state.isTransactionInternational(txn), isFalse);
  });

  test('isTransactionInternational is false when the card has no bank', () {
    final txn = _transaction(
      id: 'txn-2',
      type: TransactionType.debit,
      amount: 100,
      userCardId: 'card-1',
      currency: 'USD',
    );
    final state = TxnsState(
      all: [txn],
      cards: [_userCard(id: 'card-1', bank: null)],
    );

    expect(state.isTransactionInternational(txn), isFalse);
  });

  test(
    'isTransactionInternational is false for a bank currencyForBank does not recognize',
    () {
      final txn = _transaction(
        id: 'txn-3',
        type: TransactionType.debit,
        amount: 100,
        userCardId: 'card-1',
        currency: 'USD',
      );
      final state = TxnsState(
        all: [txn],
        cards: [
          _userCard(id: 'card-1', bank: 'Some Random Bank Nobody Recognizes'),
        ],
      );

      expect(state.isTransactionInternational(txn), isFalse);
    },
  );

  test(
    'isTransactionInternational is true for a recognized bank with a differing currency',
    () {
      final txn = _transaction(
        id: 'txn-4',
        type: TransactionType.debit,
        amount: 100,
        userCardId: 'card-1',
        currency: 'USD',
      );
      final state = TxnsState(
        all: [txn],
        cards: [_userCard(id: 'card-1', bank: 'HDFC')],
      );

      expect(state.isTransactionInternational(txn), isTrue);
    },
  );
}
