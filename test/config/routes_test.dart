import 'package:cardcompass/config/routes.dart';
import 'package:cardcompass/features/auth/presentation/screens/splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeBuildContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('root route opens the customer splash screen', () {
    final route = AppRoutes.generateRoute(
      const RouteSettings(name: AppRoutes.splash),
    );

    expect(
      (route as MaterialPageRoute<dynamic>).builder(_FakeBuildContext()),
      isA<SplashScreen>(),
    );
  });
}
