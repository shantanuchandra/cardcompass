import 'package:cardcompass/core/repositories/card_repository.dart';
import 'package:cardcompass/core/repositories/transaction_repository.dart';
import 'package:cardcompass/core/services/merchant_rate_service.dart';
import 'package:cardcompass/core/services/milestone_tracker.dart';
import 'package:cardcompass/core/services/recommendation_service_impl.dart';
import 'package:cardcompass/core/services/reward_calculator.dart';
import 'package:cardcompass/shared/models/credit_card.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final tata = _card(
    id: 'user-tata',
    catalogId: 'catalog-tata',
    bank: 'HDFC Bank',
    name: 'Tata Neu Infinity',
  );
  final amazon = _card(
    id: 'user-amazon',
    catalogId: 'catalog-amazon',
    bank: 'ICICI Bank',
    name: 'Amazon Pay',
  );

  test('Amazon purchase uses Amazon Pay ICICI merchant cashback', () async {
    final repository = _CardRepository(
      userCards: [tata, amazon],
      rewardsByCatalogId: {
        'catalog-tata': 13.50,
        'catalog-amazon': 9.00,
      },
    );
    final calculator = RewardCalculator(
      merchantRateService: MerchantRateService(),
      milestoneTracker: MilestoneTracker(),
      cardRepository: repository,
    );

    final reward = await calculator.calculateRewardValue(
      amazon,
      900,
      'shopping',
      merchantName: 'Amazon',
    );

    expect(reward, 45);
    expect(repository.requestedCardIds, contains('catalog-amazon'));
    expect(repository.requestedCardIds, isNot(contains('user-amazon')));
  });

  test('recommends owned Amazon Pay ICICI over Tata Neu for Amazon', () async {
    final repository = _CardRepository(
      userCards: [tata, amazon],
      allCards: [tata, amazon],
      rewardsByCatalogId: {
        'catalog-tata': 13.50,
        'catalog-amazon': 9.00,
      },
    );
    final service = RecommendationServiceImpl(
      merchantRateService: MerchantRateService(),
      milestoneTracker: MilestoneTracker(),
      cardRepository: repository,
      transactionRepository: _TransactionRepository(),
    );

    final result = await service.getBestCardForTransaction(
      userId: 'user-1',
      merchantName: 'Amazon',
      category: 'shopping',
      amount: 900,
    );

    expect(result.bestUserCard?.id, 'user-amazon');
    expect(result.bestUserReward, 45);
    expect(result.potentialSavings, 0);
  });
}

CreditCard _card({
  required String id,
  required String catalogId,
  required String bank,
  required String name,
}) {
  final now = DateTime(2026);
  return CreditCard(
    id: id,
    catalogCardId: catalogId,
    userId: 'user-1',
    cardName: name,
    bankName: bank,
    network: CardNetwork.visa,
    type: CardType.credit,
    issuedDate: now,
    createdAt: now,
    updatedAt: now,
  );
}

class _CardRepository implements CardRepository {
  _CardRepository({
    required this.userCards,
    this.allCards = const [],
    required this.rewardsByCatalogId,
  });

  final List<CreditCard> userCards;
  final List<CreditCard> allCards;
  final Map<String, double> rewardsByCatalogId;
  final List<String> requestedCardIds = [];

  @override
  Future<List<CreditCard>> getUserCards(String userId) async => userCards;

  @override
  Future<List<CreditCard>> getAllCards() async => allCards;

  @override
  Future<double> calculateReward({
    required String cardId,
    required String category,
    required double amount,
  }) async {
    requestedCardIds.add(cardId);
    return rewardsByCatalogId[cardId] ?? 0;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TransactionRepository implements TransactionRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
