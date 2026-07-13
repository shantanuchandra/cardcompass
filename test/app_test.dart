import 'package:cardcompass/app.dart';
import 'package:cardcompass/config/routes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('app starts on the customer route', () {
    expect(CardCompassApp.initialRoute, AppRoutes.splash);
  });
}
