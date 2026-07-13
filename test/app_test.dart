import 'package:cardcompass/app.dart';
import 'package:cardcompass/config/routes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('app starts on the customer route', () {
    expect(CardCompassApp.initialRoute, AppRoutes.splash);
  });

  test('hash admin deep link starts directly on the PM route', () {
    expect(
      AppRoutes.startupRoute(defaultRouteName: '/', webHash: '#/admin/pm'),
      AppRoutes.adminPm,
    );
  });

  test('admin startup creates only the PM route, never a splash prefix route',
      () {
    final routes = AppRoutes.generateInitialRoutes(AppRoutes.adminPm);

    expect(routes, hasLength(1));
    expect(routes.single.settings.name, AppRoutes.adminPm);
  });

  test('an unknown hash deep link falls back to the customer splash route', () {
    expect(
      AppRoutes.startupRoute(defaultRouteName: '/', webHash: '#/unknown'),
      AppRoutes.splash,
    );
  });
}
