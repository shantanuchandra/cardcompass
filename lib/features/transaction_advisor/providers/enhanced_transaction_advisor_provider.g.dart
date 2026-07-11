// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'enhanced_transaction_advisor_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Provider for Advanced Benefit Calculation Service

@ProviderFor(advancedBenefitCalculationService)
final advancedBenefitCalculationServiceProvider =
    AdvancedBenefitCalculationServiceProvider._();

/// Provider for Advanced Benefit Calculation Service

final class AdvancedBenefitCalculationServiceProvider
    extends $FunctionalProvider<AdvancedBenefitCalculationService,
        AdvancedBenefitCalculationService, AdvancedBenefitCalculationService>
    with $Provider<AdvancedBenefitCalculationService> {
  /// Provider for Advanced Benefit Calculation Service
  AdvancedBenefitCalculationServiceProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'advancedBenefitCalculationServiceProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() =>
      _$advancedBenefitCalculationServiceHash();

  @$internal
  @override
  $ProviderElement<AdvancedBenefitCalculationService> $createElement(
          $ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AdvancedBenefitCalculationService create(Ref ref) {
    return advancedBenefitCalculationService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AdvancedBenefitCalculationService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride:
          $SyncValueProvider<AdvancedBenefitCalculationService>(value),
    );
  }
}

String _$advancedBenefitCalculationServiceHash() =>
    r'9233262a0c5325cadabe3109fbd61c80aa76316d';

/// ViewModel for Enhanced Transaction Advisor

@ProviderFor(EnhancedTransactionAdvisorViewModel)
final enhancedTransactionAdvisorViewModelProvider =
    EnhancedTransactionAdvisorViewModelProvider._();

/// ViewModel for Enhanced Transaction Advisor
final class EnhancedTransactionAdvisorViewModelProvider
    extends $NotifierProvider<EnhancedTransactionAdvisorViewModel,
        EnhancedTransactionAdvisorState> {
  /// ViewModel for Enhanced Transaction Advisor
  EnhancedTransactionAdvisorViewModelProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'enhancedTransactionAdvisorViewModelProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() =>
      _$enhancedTransactionAdvisorViewModelHash();

  @$internal
  @override
  EnhancedTransactionAdvisorViewModel create() =>
      EnhancedTransactionAdvisorViewModel();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(EnhancedTransactionAdvisorState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride:
          $SyncValueProvider<EnhancedTransactionAdvisorState>(value),
    );
  }
}

String _$enhancedTransactionAdvisorViewModelHash() =>
    r'2bdec415e7c0222354aa4ccb5cdbdb7ae7176ccb';

/// ViewModel for Enhanced Transaction Advisor

abstract class _$EnhancedTransactionAdvisorViewModel
    extends $Notifier<EnhancedTransactionAdvisorState> {
  EnhancedTransactionAdvisorState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<EnhancedTransactionAdvisorState,
        EnhancedTransactionAdvisorState>;
    final element = ref.element as $ClassProviderElement<
        AnyNotifier<EnhancedTransactionAdvisorState,
            EnhancedTransactionAdvisorState>,
        EnhancedTransactionAdvisorState,
        Object?,
        Object?>;
    return element.handleCreate(ref, build);
  }
}
