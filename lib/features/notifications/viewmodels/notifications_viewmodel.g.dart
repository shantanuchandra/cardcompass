// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'notifications_viewmodel.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Repository provider

@ProviderFor(supabaseNotificationRepository)
final supabaseNotificationRepositoryProvider =
    SupabaseNotificationRepositoryProvider._();

/// Repository provider

final class SupabaseNotificationRepositoryProvider extends $FunctionalProvider<
        SupabaseNotificationRepository,
        SupabaseNotificationRepository,
        SupabaseNotificationRepository>
    with $Provider<SupabaseNotificationRepository> {
  /// Repository provider
  SupabaseNotificationRepositoryProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'supabaseNotificationRepositoryProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$supabaseNotificationRepositoryHash();

  @$internal
  @override
  $ProviderElement<SupabaseNotificationRepository> $createElement(
          $ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  SupabaseNotificationRepository create(Ref ref) {
    return supabaseNotificationRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SupabaseNotificationRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride:
          $SyncValueProvider<SupabaseNotificationRepository>(value),
    );
  }
}

String _$supabaseNotificationRepositoryHash() =>
    r'165b9ed6414bb81b23a136c9d05411a3af60710a';

@ProviderFor(NotificationsViewModel)
final notificationsViewModelProvider = NotificationsViewModelProvider._();

final class NotificationsViewModelProvider
    extends $NotifierProvider<NotificationsViewModel, NotificationsViewState> {
  NotificationsViewModelProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'notificationsViewModelProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$notificationsViewModelHash();

  @$internal
  @override
  NotificationsViewModel create() => NotificationsViewModel();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(NotificationsViewState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<NotificationsViewState>(value),
    );
  }
}

String _$notificationsViewModelHash() =>
    r'185749924fa3776f77ed644368ee9590946080d1';

abstract class _$NotificationsViewModel
    extends $Notifier<NotificationsViewState> {
  NotificationsViewState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<NotificationsViewState, NotificationsViewState>;
    final element = ref.element as $ClassProviderElement<
        AnyNotifier<NotificationsViewState, NotificationsViewState>,
        NotificationsViewState,
        Object?,
        Object?>;
    return element.handleCreate(ref, build);
  }
}
