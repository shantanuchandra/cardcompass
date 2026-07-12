// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'recommendations_viewmodel.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(RecommendationsViewModel)
final recommendationsViewModelProvider = RecommendationsViewModelProvider._();

final class RecommendationsViewModelProvider extends $NotifierProvider<
    RecommendationsViewModel, RecommendationsViewState> {
  RecommendationsViewModelProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'recommendationsViewModelProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$recommendationsViewModelHash();

  @$internal
  @override
  RecommendationsViewModel create() => RecommendationsViewModel();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RecommendationsViewState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RecommendationsViewState>(value),
    );
  }
}

String _$recommendationsViewModelHash() =>
    r'0ab00e76f6ce03d2080faeb3014535e0beaf8de9';

abstract class _$RecommendationsViewModel
    extends $Notifier<RecommendationsViewState> {
  RecommendationsViewState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<RecommendationsViewState, RecommendationsViewState>;
    final element = ref.element as $ClassProviderElement<
        AnyNotifier<RecommendationsViewState, RecommendationsViewState>,
        RecommendationsViewState,
        Object?,
        Object?>;
    return element.handleCreate(ref, build);
  }
}
