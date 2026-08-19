// Test-only compiled browser entrypoint. Production builds use lib/main.dart.
import 'package:cardcompass/app.dart';
import 'package:cardcompass/core/providers/supabase_provider.dart';
import 'package:cardcompass/features/admin2/data/admin_operator_api.dart';
import 'package:cardcompass/features/admin2/data/admin_operator_repository.dart';
import 'package:cardcompass/features/admin2/models/admin_access.dart';
import 'package:cardcompass/features/admin2/providers/admin_access_provider.dart';
import 'package:cardcompass/features/auth/providers/auth_provider.dart';
import 'package:cardcompass/features/cards/providers/cards_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

const browserFixtureMarker = 'cardcompass-browser-fixture-only';
late final SemanticsHandle browserFixtureSemanticsHandle;

final class _FixtureAuthNotifier extends AuthNotifier {
  @override
  Future<AuthStatus> build() async {
    final query = Uri.base.queryParameters;
    return query['fixture_auth'] == 'true' || query['section'] == 'card-data'
        ? AuthStatus.authenticated
        : AuthStatus.unauthenticated;
  }
}

final class _FixtureSession implements AuthSessionAccess {
  @override
  String? get currentUserId => '00000000-0000-4000-8000-000000000001';
  @override
  Future<void> signOut() async {}
}

final class _FixtureAdminApi implements AdminOperatorApi {
  const _FixtureAdminApi();

  @override
  Future<AdminOperatorResponse> invoke(Map<String, dynamic> body) async {
    return switch (body['action']) {
      'access' => const AdminOperatorResponse(200, {'is_admin': true}),
      'inbox-list' => const AdminOperatorResponse(200, {
        'items': [],
        'partial_failures': [],
        'refreshed_at': '2026-08-20T00:00:00Z',
      }),
      'card-review-list' => AdminOperatorResponse(200, {
        'lane': body['lane'],
        'items': const [],
        'page': 1,
        'limit': 25,
        'has_more': false,
      }),
      _ => const AdminOperatorResponse(400, {'error': 'invalid_request'}),
    };
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  browserFixtureSemanticsHandle = WidgetsBinding.instance.ensureSemantics();
  runApp(
    ProviderScope(
      overrides: [
        authNotifierProvider.overrideWith(_FixtureAuthNotifier.new),
        authSessionAccessProvider.overrideWithValue(_FixtureSession()),
        currentUserProvider.overrideWithValue(null),
        adminAccessProvider.overrideWith(
          (_) async => const AdminAccess(isAdmin: true),
        ),
        adminEntryVisibilityProvider.overrideWithValue(
          const AsyncValue.data(true),
        ),
        adminOperatorRepositoryProvider.overrideWithValue(
          const AdminOperatorRepository(_FixtureAdminApi()),
        ),
        userCardsProvider.overrideWith((_) async => const []),
        latestCardStatementsProvider.overrideWith((_) async => const {}),
      ],
      child: Semantics(
        label: browserFixtureMarker,
        container: true,
        child: const CardCompassApp(),
      ),
    ),
  );
}
