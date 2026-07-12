import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:cardcompass/shared/models/credit_card.dart';
import 'package:cardcompass/core/repositories/card_repository.dart';

part 'cards_viewmodel.g.dart';

class CardsViewState {
  final List<CreditCard> userCards;
  final List<CreditCard> allCards;
  final List<CreditCard> filteredCards;
  final bool isLoading;
  final String? error;
  final String? bankFilter;
  final String? cardTypeFilter;
  final String? networkFilter;
  final double? maxAnnualFee;

  const CardsViewState({
    this.userCards = const [],
    this.allCards = const [],
    this.filteredCards = const [],
    this.isLoading = false,
    this.error,
    this.bankFilter,
    this.cardTypeFilter,
    this.networkFilter,
    this.maxAnnualFee,
  });

  CardsViewState copyWith({
    List<CreditCard>? userCards,
    List<CreditCard>? allCards,
    List<CreditCard>? filteredCards,
    bool? isLoading,
    String? error,
    String? bankFilter,
    String? cardTypeFilter,
    String? networkFilter,
    double? maxAnnualFee,
  }) {
    return CardsViewState(
      userCards: userCards ?? this.userCards,
      allCards: allCards ?? this.allCards,
      filteredCards: filteredCards ?? this.filteredCards,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      bankFilter: bankFilter ?? this.bankFilter,
      cardTypeFilter: cardTypeFilter ?? this.cardTypeFilter,
      networkFilter: networkFilter ?? this.networkFilter,
      maxAnnualFee: maxAnnualFee ?? this.maxAnnualFee,
    );
  }

  bool get hasActiveFilters {
    return bankFilter != null ||
           cardTypeFilter != null ||
           networkFilter != null ||
           maxAnnualFee != null;
  }

  List<String> get availableBanks {
    return allCards.map((card) => card.bankName).toSet().toList()..sort();
  }
  List<String> get availableNetworks {
    return allCards.map((card) => card.network.toString().split('.').last).toSet().toList()..sort();
  }
}

@riverpod
class CardsViewModelController extends _$CardsViewModelController {
  late final CardRepository _cardsRepository;

  @override
  CardsViewState build() {
    _cardsRepository = ref.watch(cardsRepositoryProvider);
    return const CardsViewState();
  }

  Future<void> loadCards(String userId) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final userCards = await _cardsRepository.getUserCards(userId);
      final allCards = await _cardsRepository.getAllCards();

      state = state.copyWith(
        userCards: userCards,
        allCards: allCards,
        filteredCards: _applyFilters(allCards),
        isLoading: false,
      );
    } catch (error) {
      state = state.copyWith(
        error: error.toString(),
        isLoading: false,
      );
    }
  }

  Future<void> addUserCard({
    required String userId,
    required String cardId,
    required String lastFourDigits,
  }) async {
    try {
      await _cardsRepository.addUserCard(
        userId: userId,
        cardId: cardId,
        lastFourDigits: lastFourDigits,
      );

      // Reload cards to reflect changes
      await loadCards(userId);
    } catch (error) {
      state = state.copyWith(error: error.toString());
    }
  }

  Future<void> removeUserCard({
    required String userId,
    required String cardId,
  }) async {
    try {
      await _cardsRepository.removeUserCard(
        userId: userId,
        cardId: cardId,
      );

      // Reload cards to reflect changes
      await loadCards(userId);
    } catch (error) {
      state = state.copyWith(error: error.toString());
    }
  }

  void applyBankFilter(String bank) {
    state = state.copyWith(
      bankFilter: bank,
      filteredCards: _applyFilters(state.allCards),
    );
  }

  void clearBankFilter() {
    state = state.copyWith(
      bankFilter: null,
      filteredCards: _applyFilters(state.allCards),
    );
  }

  void applyCardTypeFilter(String cardType) {
    state = state.copyWith(
      cardTypeFilter: cardType,
      filteredCards: _applyFilters(state.allCards),
    );
  }

  void clearCardTypeFilter() {
    state = state.copyWith(
      cardTypeFilter: null,
      filteredCards: _applyFilters(state.allCards),
    );
  }

  void applyNetworkFilter(String network) {
    state = state.copyWith(
      networkFilter: network,
      filteredCards: _applyFilters(state.allCards),
    );
  }

  void clearNetworkFilter() {
    state = state.copyWith(
      networkFilter: null,
      filteredCards: _applyFilters(state.allCards),
    );
  }

  void applyFeeFilter(double maxFee) {
    state = state.copyWith(
      maxAnnualFee: maxFee,
      filteredCards: _applyFilters(state.allCards),
    );
  }

  void clearFeeFilter() {
    state = state.copyWith(
      maxAnnualFee: null,
      filteredCards: _applyFilters(state.allCards),
    );
  }

  void clearAllFilters() {
    state = state.copyWith(
      bankFilter: null,
      cardTypeFilter: null,
      networkFilter: null,
      maxAnnualFee: null,
      filteredCards: state.allCards,
    );
  }

  List<CreditCard> _applyFilters(List<CreditCard> cards) {
    var filtered = cards;

    if (state.bankFilter != null) {
      filtered = filtered.where((card) => card.bankName == state.bankFilter).toList();
    }
    if (state.cardTypeFilter != null) {
      filtered = filtered.where((card) => card.type.toString().split('.').last == state.cardTypeFilter).toList();
    }

    if (state.networkFilter != null) {
      filtered = filtered.where((card) => card.network.toString().split('.').last == state.networkFilter).toList();
    }

    if (state.maxAnnualFee != null) {
      filtered = filtered.where((card) {
        final fee = card.annualFee ?? 0;
        return fee <= state.maxAnnualFee!;
      }).toList();
    }

    return filtered;
  }

  void clearError() {
    state = state.copyWith(error: null);
  }
}

// Alias for compatibility
final cardsViewModelProvider = cardsViewModelControllerProvider;

// Provider for CardsRepository (to be defined)
final cardsRepositoryProvider = Provider<CardRepository>((ref) {
  throw UnimplementedError('CardsRepository provider not implemented');
});
