import 'dart:async';

import 'package:cardcompass/features/auth/providers/auth_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _ProfileReader implements UserAccessProfileReader {
  _ProfileReader(this.result);
  final Future<UserAccessProfileState> Function(String) result;
  @override
  Future<UserAccessProfileState> read(String userId) => result(userId);
}

class _Session implements AuthSessionAccess {
  _Session(this.userId);
  final String? userId;
  int signOuts = 0;
  @override
  String? get currentUserId => userId;
  @override
  Future<void> signOut() async => signOuts++;
}

ProviderContainer _container(
  AuthSessionAccess session,
  UserAccessProfileReader reader,
) {
  return ProviderContainer(
    overrides: [
      authSessionAccessProvider.overrideWithValue(session),
      userAccessProfileReaderProvider.overrideWithValue(reader),
    ],
  );
}

void main() {
  test(
    'a resolved auth value is not blocked by dependency refresh loading',
    () {
      final refreshing = const AsyncLoading<AuthStatus>().copyWithPrevious(
        const AsyncData(AuthStatus.unauthenticated),
        isRefresh: false,
      );

      expect(refreshing.isLoading, isTrue);
      expect(refreshing.hasValue, isTrue);
      expect(authStatusIsPending(refreshing), isFalse);
      expect(authStatusIsPending(const AsyncLoading<AuthStatus>()), isTrue);
    },
  );

  test(
    'missing auth user is unauthenticated without reading a profile',
    () async {
      var reads = 0;
      final container = _container(
        _Session(null),
        _ProfileReader((_) async {
          reads++;
          return UserAccessProfileState.active;
        }),
      );
      addTearDown(container.dispose);
      expect(
        await container.read(authNotifierProvider.future),
        AuthStatus.unauthenticated,
      );
      expect(reads, 0);
    },
  );

  test('active profile is authenticated', () async {
    final container = _container(
      _Session('user-1'),
      _ProfileReader(
        (id) async => id == 'user-1'
            ? UserAccessProfileState.active
            : UserAccessProfileState.missing,
      ),
    );
    addTearDown(container.dispose);
    expect(
      await container.read(authNotifierProvider.future),
      AuthStatus.authenticated,
    );
  });

  test(
    'inactive profile signs out and fails closed with typed error',
    () async {
      final session = _Session('user-1');
      final container = _container(
        session,
        _ProfileReader((_) async => UserAccessProfileState.inactive),
      );
      addTearDown(container.dispose);
      await expectLater(
        container.read(authNotifierProvider.future),
        throwsA(isA<InactiveAccountException>()),
      );
      expect(session.signOuts, 1);
    },
  );

  test('missing profile fails closed without claiming inactive', () async {
    final session = _Session('user-1');
    final container = _container(
      session,
      _ProfileReader((_) async => UserAccessProfileState.missing),
    );
    addTearDown(container.dispose);
    await expectLater(
      container.read(authNotifierProvider.future),
      throwsA(isA<MissingAccessProfileException>()),
    );
    expect(session.signOuts, 0);
  });

  test('stale inactive read cannot sign out a replacement identity', () async {
    final session = _MutableSession('user-1');
    final profile = Completer<UserAccessProfileState>();
    final container = _container(
      session,
      _ProfileReader((_) => profile.future),
    );
    addTearDown(container.dispose);
    final result = container.read(authNotifierProvider.future);
    session.userId = 'user-2';
    profile.complete(UserAccessProfileState.inactive);
    await expectLater(result, throwsA(isA<AuthIdentityChangedException>()));
    expect(session.signOuts, 0);
  });

  test(
    'profile read failure remains an error and does not authenticate',
    () async {
      final session = _Session('user-1');
      final container = _container(
        session,
        _ProfileReader((_) async => throw StateError('offline')),
      );
      addTearDown(container.dispose);
      await expectLater(
        container.read(authNotifierProvider.future),
        throwsA(isA<StateError>()),
      );
      expect(session.signOuts, 0);
    },
  );
}

class _MutableSession implements AuthSessionAccess {
  _MutableSession(this.userId);
  String? userId;
  int signOuts = 0;
  @override
  String? get currentUserId => userId;
  @override
  Future<void> signOut() async => signOuts++;
}
