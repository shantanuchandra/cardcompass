import 'package:cardcompass/shared/models/credit_card.dart';
import 'package:cardcompass/shared/models/transaction.dart';
import 'package:cardcompass/shared/models/reward_balance.dart';
import 'package:cardcompass/shared/models/statement.dart';

/// Shared identifiers so every mock repository/viewmodel refers to the
/// same guest user, cards, and reward balances.
class MockIds {
  static const String guestUserId = 'guest';
  static const String cardHdfcRegalia = 'mock-card-hdfc-regalia';
  static const String cardAxisAce = 'mock-card-axis-ace';
  static const String cardIciciAmazonPay = 'mock-card-icici-amazonpay';
}

/// Centralized, internally-consistent mock data for guest mode.
///
/// Dates are computed relative to [DateTime.now()] at call time (not baked
/// into static const values) so "last 2 months" always looks current.
class MockData {
  static List<CreditCard> creditCards() {
    final now = DateTime.now();
    final issuedTwoYearsAgo = DateTime(now.year - 2, now.month, 1);

    return [
      CreditCard(
        id: MockIds.cardHdfcRegalia,
        userId: MockIds.guestUserId,
        cardName: 'HDFC Regalia Gold',
        bankName: 'HDFC Bank',
        cardNumber: '4821',
        network: CardNetwork.visa,
        type: CardType.credit,
        issuedDate: issuedTwoYearsAgo,
        expiryDate: DateTime(now.year + 3, now.month, 1),
        annualFee: 2500,
        creditLimit: 350000,
        rewardRates: const {'dining': 4.0, 'travel': 4.0, 'other': 1.0},
        isActive: true,
        createdAt: issuedTwoYearsAgo,
        updatedAt: now,
      ),
      CreditCard(
        id: MockIds.cardAxisAce,
        userId: MockIds.guestUserId,
        cardName: 'Axis Ace',
        bankName: 'Axis Bank',
        cardNumber: '3390',
        network: CardNetwork.rupay,
        type: CardType.credit,
        issuedDate: DateTime(now.year - 1, now.month, 1),
        expiryDate: DateTime(now.year + 4, now.month, 1),
        annualFee: 499,
        creditLimit: 180000,
        rewardRates: const {'utilities': 5.0, 'fuel': 5.0, 'other': 2.0},
        isActive: true,
        createdAt: DateTime(now.year - 1, now.month, 1),
        updatedAt: now,
      ),
      CreditCard(
        id: MockIds.cardIciciAmazonPay,
        userId: MockIds.guestUserId,
        cardName: 'ICICI Amazon Pay',
        bankName: 'ICICI Bank',
        cardNumber: '7714',
        network: CardNetwork.amex,
        type: CardType.credit,
        issuedDate: now.subtract(const Duration(days: 180)),
        expiryDate: DateTime(now.year + 4, now.month, 1),
        annualFee: 0,
        creditLimit: 220000,
        rewardRates: const {'shopping': 5.0, 'other': 1.0},
        isActive: true,
        createdAt: now.subtract(const Duration(days: 180)),
        updatedAt: now,
      ),
    ];
  }

  /// ~25 transactions spread across the last 2 months, varied categories,
  /// each with a plausible reward earned relative to its card's reward rate.
  static List<Transaction> transactions() {
    final now = DateTime.now();
    final entries = <_TxSeed>[
      _TxSeed(2, 'Swiggy', TransactionCategory.food, 640, MockIds.cardHdfcRegalia, 25.6),
      _TxSeed(3, 'Indian Oil', TransactionCategory.fuel, 3200, MockIds.cardAxisAce, 160.0),
      _TxSeed(5, 'Amazon.in', TransactionCategory.shopping, 2199, MockIds.cardIciciAmazonPay, 109.95),
      _TxSeed(6, 'BigBasket', TransactionCategory.grocery, 1850, MockIds.cardAxisAce, 18.5),
      _TxSeed(8, 'Netflix', TransactionCategory.subscription, 649, MockIds.cardHdfcRegalia, 6.49),
      _TxSeed(9, 'BESCOM Electricity', TransactionCategory.utilities, 2400, MockIds.cardAxisAce, 120.0),
      _TxSeed(11, 'IndiGo Airlines', TransactionCategory.travel, 8400, MockIds.cardHdfcRegalia, 336.0),
      _TxSeed(13, 'Barbeque Nation', TransactionCategory.food, 3100, MockIds.cardHdfcRegalia, 124.0),
      _TxSeed(15, 'Amazon.in', TransactionCategory.shopping, 4599, MockIds.cardIciciAmazonPay, 229.95),
      _TxSeed(16, 'PVR Cinemas', TransactionCategory.entertainment, 850, MockIds.cardAxisAce, 17.0),
      _TxSeed(18, 'Shell Petrol', TransactionCategory.fuel, 2800, MockIds.cardAxisAce, 140.0),
      _TxSeed(20, 'Zomato', TransactionCategory.food, 520, MockIds.cardHdfcRegalia, 20.8),
      _TxSeed(22, 'Reliance Digital', TransactionCategory.shopping, 12999, MockIds.cardIciciAmazonPay, 649.95),
      _TxSeed(24, 'LIC Premium', TransactionCategory.insurance, 5600, MockIds.cardHdfcRegalia, 56.0),
      _TxSeed(26, 'Apollo Pharmacy', TransactionCategory.medical, 780, MockIds.cardAxisAce, 15.6),
      _TxSeed(28, 'BookMyShow', TransactionCategory.entertainment, 640, MockIds.cardHdfcRegalia, 25.6),
      _TxSeed(31, 'Ola Cabs', TransactionCategory.transport, 340, MockIds.cardAxisAce, 6.8),
      _TxSeed(33, 'Housing Rent', TransactionCategory.rental, 25000, MockIds.cardHdfcRegalia, 250.0),
      _TxSeed(36, 'Amazon.in', TransactionCategory.shopping, 1299, MockIds.cardIciciAmazonPay, 64.95),
      _TxSeed(39, 'Spotify', TransactionCategory.subscription, 119, MockIds.cardHdfcRegalia, 1.19),
      _TxSeed(42, "Domino's Pizza", TransactionCategory.food, 890, MockIds.cardHdfcRegalia, 35.6),
      _TxSeed(45, 'IndianOil Fuel', TransactionCategory.fuel, 3000, MockIds.cardAxisAce, 150.0),
      _TxSeed(48, 'Udemy', TransactionCategory.education, 499, MockIds.cardIciciAmazonPay, 4.99),
      _TxSeed(52, 'MakeMyTrip', TransactionCategory.travel, 6200, MockIds.cardHdfcRegalia, 248.0),
      _TxSeed(56, 'D-Mart', TransactionCategory.grocery, 2340, MockIds.cardAxisAce, 23.4),
    ];

    return entries.asMap().entries.map((entry) {
      final index = entry.key;
      final tx = entry.value;
      final date = now.subtract(Duration(days: tx.daysAgo));
      return Transaction(
        id: 'mock-txn-${index + 1}',
        userId: MockIds.guestUserId,
        userCardId: tx.cardId,
        amount: tx.amount,
        description: tx.merchant,
        merchantName: tx.merchant,
        category: tx.category,
        type: TransactionType.debit,
        transactionDate: date,
        rewardEarned: tx.rewardEarned,
        rewardType: 'points',
        createdAt: date,
      );
    }).toList();
  }

  static List<RewardBalance> rewardBalances() {
    final now = DateTime.now();
    return [
      RewardBalance(
        id: 'mock-reward-hdfc',
        userId: MockIds.guestUserId,
        userCardId: MockIds.cardHdfcRegalia,
        rewardType: 'points',
        availableBalance: 4820,
        totalEarned: 6100,
        totalRedeemed: 1280,
        expiryDate: DateTime(now.year + 1, now.month, 1),
        lastUpdated: now,
        createdAt: now.subtract(const Duration(days: 400)),
      ),
      RewardBalance(
        id: 'mock-reward-axis',
        userId: MockIds.guestUserId,
        userCardId: MockIds.cardAxisAce,
        rewardType: 'cashback',
        availableBalance: 612.40,
        totalEarned: 890.0,
        totalRedeemed: 277.60,
        lastUpdated: now,
        createdAt: now.subtract(const Duration(days: 200)),
      ),
      RewardBalance(
        id: 'mock-reward-icici',
        userId: MockIds.guestUserId,
        userCardId: MockIds.cardIciciAmazonPay,
        rewardType: 'points',
        availableBalance: 2140,
        totalEarned: 2140,
        totalRedeemed: 0,
        lastUpdated: now,
        createdAt: now.subtract(const Duration(days: 90)),
      ),
    ];
  }

  static List<Statement> statements() {
    final now = DateTime.now();
    Statement build({
      required String id,
      required String cardId,
      required int monthsAgo,
      required double total,
      required PaymentStatus status,
    }) {
      final statementDate = DateTime(now.year, now.month - monthsAgo, 5);
      return Statement(
        id: id,
        userId: MockIds.guestUserId,
        userCardId: cardId,
        statementDate: statementDate,
        dueDate: statementDate.add(const Duration(days: 20)),
        totalAmount: total,
        minimumPayment: (total * 0.05).roundToDouble(),
        closingBalance: total,
        availableCredit: 350000 - total,
        rewardsEarned: (total * 0.02).roundToDouble(),
        interestCharged: status == PaymentStatus.overdue ? (total * 0.03).roundToDouble() : 0,
        feesCharged: 0,
        paymentStatus: status,
        filePath: '',
        fileName: 'statement_${statementDate.year}_${statementDate.month}.pdf',
        createdAt: statementDate,
        processed: true,
        transactionCount: 8,
      );
    }

    return [
      build(id: 'mock-stmt-1', cardId: MockIds.cardHdfcRegalia, monthsAgo: 0, total: 18420, status: PaymentStatus.pending),
      build(id: 'mock-stmt-2', cardId: MockIds.cardAxisAce, monthsAgo: 1, total: 9640, status: PaymentStatus.paid),
      build(id: 'mock-stmt-3', cardId: MockIds.cardIciciAmazonPay, monthsAgo: 1, total: 21897, status: PaymentStatus.paid),
    ];
  }

  static List<Map<String, dynamic>> cardBenefits(String cardId) {
    final now = DateTime.now();
    final byCard = <String, List<Map<String, dynamic>>>{
      MockIds.cardHdfcRegalia: [
        {'name': 'Airport Lounge Access', 'category': 'Travel', 'description': '8 complimentary domestic lounge visits per year', 'isActive': true},
        {'name': 'Dining Privileges', 'category': 'Dining', 'description': '4x reward points on dining spends', 'isActive': true},
        {'name': 'Fuel Surcharge Waiver', 'category': 'Fuel', 'description': '1% waiver up to ₹250/month', 'isActive': true},
      ],
      MockIds.cardAxisAce: [
        {'name': 'Bill Payment Cashback', 'category': 'Utilities', 'description': '5% cashback on utility bill payments', 'isActive': true},
        {'name': 'Fuel Cashback', 'category': 'Fuel', 'description': '5% cashback at fuel stations', 'isActive': true},
      ],
      MockIds.cardIciciAmazonPay: [
        {'name': 'Amazon Cashback', 'category': 'Shopping', 'description': '5% unlimited cashback on Amazon for Prime members', 'isActive': true},
        {'name': 'No Annual Fee', 'category': 'Fees', 'description': 'Lifetime free card, zero joining/annual fee', 'isActive': true},
      ],
    };
    return (byCard[cardId] ?? const [])
        .map((b) => {...b, 'updatedAt': now.toIso8601String()})
        .toList();
  }
}

class _TxSeed {
  final int daysAgo;
  final String merchant;
  final TransactionCategory category;
  final double amount;
  final String cardId;
  final double rewardEarned;

  const _TxSeed(this.daysAgo, this.merchant, this.category, this.amount, this.cardId, this.rewardEarned);
}
