import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/repository_providers.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../../shared/models/user_card.dart';

final userCardsProvider = FutureProvider<List<UserCard>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];
  return ref.read(cardsRepositoryProvider).getUserCards(user.id);
});

final addCardSaveCoordinatorProvider = Provider<AddCardSaveCoordinator>(
  AddCardSaveCoordinator.new,
);

class AddCardSaveCoordinator {
  AddCardSaveCoordinator(this._ref);

  final Ref _ref;
  final Map<String, Future<void>> _inFlight = {};

  Future<void> save({
    required String userId,
    required String catalogCardId,
    String? lastFourDigits,
    String? cardHolderName,
  }) {
    final key = '$userId:$catalogCardId';
    final existing = _inFlight[key];
    if (existing != null) return existing;

    final repository = _ref.read(cardsRepositoryProvider);
    final save = () async {
      await repository.addUserCard(
        userId: userId,
        catalogCardId: catalogCardId,
        lastFourDigits: lastFourDigits,
        cardHolderName: cardHolderName,
      );
      _ref.invalidate(userCardsProvider);
    }();
    late final Future<void> trackedSave;
    trackedSave = save.whenComplete(() {
      if (identical(_inFlight[key], trackedSave)) _inFlight.remove(key);
    });
    _inFlight[key] = trackedSave;
    return trackedSave;
  }
}
