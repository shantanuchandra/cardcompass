// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cards_viewmodel.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(CardsViewModelController)
final cardsViewModelControllerProvider = CardsViewModelControllerProvider._();

final class CardsViewModelControllerProvider
    extends $NotifierProvider<CardsViewModelController, CardsViewState> {
  CardsViewModelControllerProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'cardsViewModelControllerProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$cardsViewModelControllerHash();

  @$internal
  @override
  CardsViewModelController create() => CardsViewModelController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CardsViewState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CardsViewState>(value),
    );
  }
}

String _$cardsViewModelControllerHash() =>
    r'f5be77ff45482c33e664fe7a83523767a5978e8c';

abstract class _$CardsViewModelController extends $Notifier<CardsViewState> {
  CardsViewState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<CardsViewState, CardsViewState>;
    final element = ref.element as $ClassProviderElement<
        AnyNotifier<CardsViewState, CardsViewState>,
        CardsViewState,
        Object?,
        Object?>;
    return element.handleCreate(ref, build);
  }
}
