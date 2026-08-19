import 'package:cardcompass/features/auth/providers/auth_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _ProfileReader implements UserAccessProfileReader {
  _ProfileReader(this.result);
  final Future<bool> Function(String) result;
  @override
  Future<bool> isActive(String userId) => result(userId);
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

ProviderContainer _container(_Session session, UserAccessProfileReader reader) {
  return ProviderContainer(
    overrides: [
      authSessionAccessProvider.overrideWithValue(session),
      userAccessProfileReaderProvider.overrideWithValue(reader),
    ],
  );
}

void main() {
  test(
    'missing auth user is unauthenticated without reading a profile',
    () async {
      var reads = 0;
      final container = _container(
        _Session(null),
        _ProfileReader((_) async {
          reads++;
          return true;
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
      _ProfileReader((id) async => id == 'user-1'),
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
      final container = _container(session, _ProfileReader((_) async => false));
      addTearDown(container.dispose);
      await expectLater(
        container.read(authNotifierProvider.future),
        throwsA(isA<InactiveAccountException>()),
      );
      expect(session.signOuts, 1);
    },
  );

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
