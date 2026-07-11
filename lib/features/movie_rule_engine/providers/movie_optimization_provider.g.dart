// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'movie_optimization_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Provider for movie rule engine service

@ProviderFor(movieRuleEngineService)
final movieRuleEngineServiceProvider = MovieRuleEngineServiceProvider._();

/// Provider for movie rule engine service

final class MovieRuleEngineServiceProvider extends $FunctionalProvider<
    MovieRuleEngineService,
    MovieRuleEngineService,
    MovieRuleEngineService> with $Provider<MovieRuleEngineService> {
  /// Provider for movie rule engine service
  MovieRuleEngineServiceProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'movieRuleEngineServiceProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$movieRuleEngineServiceHash();

  @$internal
  @override
  $ProviderElement<MovieRuleEngineService> $createElement(
          $ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  MovieRuleEngineService create(Ref ref) {
    return movieRuleEngineService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MovieRuleEngineService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MovieRuleEngineService>(value),
    );
  }
}

String _$movieRuleEngineServiceHash() =>
    r'd2bec40a2ed05e5cd5bcd23496bfe5d24151dda9';

/// Future provider for movie optimization

@ProviderFor(movieOptimization)
final movieOptimizationProvider = MovieOptimizationFamily._();

/// Future provider for movie optimization

final class MovieOptimizationProvider extends $FunctionalProvider<
        AsyncValue<MovieRecommendation>,
        MovieRecommendation,
        FutureOr<MovieRecommendation>>
    with
        $FutureModifier<MovieRecommendation>,
        $FutureProvider<MovieRecommendation> {
  /// Future provider for movie optimization
  MovieOptimizationProvider._(
      {required MovieOptimizationFamily super.from,
      required (
        String,
        MovieTicketRequest,
      )
          super.argument})
      : super(
          retry: null,
          name: r'movieOptimizationProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$movieOptimizationHash();

  @override
  String toString() {
    return r'movieOptimizationProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<MovieRecommendation> $createElement(
          $ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<MovieRecommendation> create(Ref ref) {
    final argument = this.argument as (
      String,
      MovieTicketRequest,
    );
    return movieOptimization(
      ref,
      argument,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is MovieOptimizationProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$movieOptimizationHash() => r'00e1eee1ddccccc23238980995e4af27150ddeaa';

/// Future provider for movie optimization

final class MovieOptimizationFamily extends $Family
    with
        $FunctionalFamilyOverride<
            FutureOr<MovieRecommendation>,
            (
              String,
              MovieTicketRequest,
            )> {
  MovieOptimizationFamily._()
      : super(
          retry: null,
          name: r'movieOptimizationProvider',
          dependencies: null,
          $allTransitiveDependencies: null,
          isAutoDispose: true,
        );

  /// Future provider for movie optimization

  MovieOptimizationProvider call(
    (
      String,
      MovieTicketRequest,
    ) params,
  ) =>
      MovieOptimizationProvider._(argument: params, from: this);

  @override
  String toString() => r'movieOptimizationProvider';
}

/// Provider for all card-benefit combinations

@ProviderFor(allMovieCardBenefits)
final allMovieCardBenefitsProvider = AllMovieCardBenefitsFamily._();

/// Provider for all card-benefit combinations

final class AllMovieCardBenefitsProvider extends $FunctionalProvider<
        AsyncValue<List<Map<String, dynamic>>>,
        List<Map<String, dynamic>>,
        FutureOr<List<Map<String, dynamic>>>>
    with
        $FutureModifier<List<Map<String, dynamic>>>,
        $FutureProvider<List<Map<String, dynamic>>> {
  /// Provider for all card-benefit combinations
  AllMovieCardBenefitsProvider._(
      {required AllMovieCardBenefitsFamily super.from,
      required String super.argument})
      : super(
          retry: null,
          name: r'allMovieCardBenefitsProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$allMovieCardBenefitsHash();

  @override
  String toString() {
    return r'allMovieCardBenefitsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<Map<String, dynamic>>> $createElement(
          $ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<List<Map<String, dynamic>>> create(Ref ref) {
    final argument = this.argument as String;
    return allMovieCardBenefits(
      ref,
      argument,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AllMovieCardBenefitsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$allMovieCardBenefitsHash() =>
    r'496555769b589d90bb8e819825f933ddd2f5aab2';

/// Provider for all card-benefit combinations

final class AllMovieCardBenefitsFamily extends $Family
    with
        $FunctionalFamilyOverride<FutureOr<List<Map<String, dynamic>>>,
            String> {
  AllMovieCardBenefitsFamily._()
      : super(
          retry: null,
          name: r'allMovieCardBenefitsProvider',
          dependencies: null,
          $allTransitiveDependencies: null,
          isAutoDispose: true,
        );

  /// Provider for all card-benefit combinations

  AllMovieCardBenefitsProvider call(
    String userId,
  ) =>
      AllMovieCardBenefitsProvider._(argument: userId, from: this);

  @override
  String toString() => r'allMovieCardBenefitsProvider';
}

/// Controller for managing movie optimization state

@ProviderFor(MovieOptimizationController)
final movieOptimizationControllerProvider =
    MovieOptimizationControllerProvider._();

/// Controller for managing movie optimization state
final class MovieOptimizationControllerProvider extends $NotifierProvider<
    MovieOptimizationController, AsyncValue<MovieRecommendation?>> {
  /// Controller for managing movie optimization state
  MovieOptimizationControllerProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'movieOptimizationControllerProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$movieOptimizationControllerHash();

  @$internal
  @override
  MovieOptimizationController create() => MovieOptimizationController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AsyncValue<MovieRecommendation?> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride:
          $SyncValueProvider<AsyncValue<MovieRecommendation?>>(value),
    );
  }
}

String _$movieOptimizationControllerHash() =>
    r'6044be50abd94b6aa30b8dbc6e4c431f655a13ae';

/// Controller for managing movie optimization state

abstract class _$MovieOptimizationController
    extends $Notifier<AsyncValue<MovieRecommendation?>> {
  AsyncValue<MovieRecommendation?> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<MovieRecommendation?>,
        AsyncValue<MovieRecommendation?>>;
    final element = ref.element as $ClassProviderElement<
        AnyNotifier<AsyncValue<MovieRecommendation?>,
            AsyncValue<MovieRecommendation?>>,
        AsyncValue<MovieRecommendation?>,
        Object?,
        Object?>;
    return element.handleCreate(ref, build);
  }
}
