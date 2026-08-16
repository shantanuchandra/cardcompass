import 'package:cardcompass/app.dart' show navigatorKey;
import 'package:cardcompass/core/services/password_input_service.dart';
import 'package:cardcompass/core/services/pdf_password_detection_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepts a correct password on the first manual attempt', () async {
    final attempts = <int>[];

    final result = await runManualPasswordAttempts(
      requestPassword: (attempt, maxAttempts) async {
        attempts.add(attempt);
        return 'correct';
      },
      verifyPassword: (password) async => password == 'correct' ? 'text' : null,
    );

    expect(result.outcome, ManualPasswordOutcome.succeeded);
    expect(result.text, 'text');
    expect(attempts, [1]);
  });

  test('accepts a correct password on the second manual attempt', () async {
    final attempts = <int>[];

    final result = await runManualPasswordAttempts(
      requestPassword: (attempt, maxAttempts) async {
        attempts.add(attempt);
        return attempt == 1 ? 'wrong' : 'correct';
      },
      verifyPassword: (password) async => password == 'correct' ? 'text' : null,
    );

    expect(result.outcome, ManualPasswordOutcome.succeeded);
    expect(result.text, 'text');
    expect(attempts, [1, 2]);
  });

  test('stops after two incorrect manual passwords', () async {
    final attempts = <int>[];

    final result = await runManualPasswordAttempts(
      requestPassword: (attempt, maxAttempts) async {
        attempts.add(attempt);
        return 'wrong';
      },
      verifyPassword: (_) async => null,
    );

    expect(result.outcome, ManualPasswordOutcome.attemptsExhausted);
    expect(result.text, isNull);
    expect(attempts, [1, 2]);
  });

  test(
    'cancel stops immediately without requesting a second password',
    () async {
      final attempts = <int>[];

      final result = await runManualPasswordAttempts(
        requestPassword: (attempt, maxAttempts) async {
          attempts.add(attempt);
          return null;
        },
        verifyPassword: (_) async => throw StateError('must not verify cancel'),
      );

      expect(result.outcome, ManualPasswordOutcome.cancelled);
      expect(result.text, isNull);
      expect(attempts, [1]);
    },
  );

  testWidgets('retry prompt shows attempt count without echoing a password', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigatorKey, home: const SizedBox()),
    );

    final first = PasswordInputService.requestPassword(
      'HSBC',
      attempt: 1,
      maxAttempts: 2,
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'private-password');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(await first, 'private-password');

    final second = PasswordInputService.requestPassword(
      'HSBC',
      attempt: 2,
      maxAttempts: 2,
    );
    await tester.pumpAndSettle();

    expect(find.text('Attempt 2 of 2'), findsOneWidget);
    expect(find.textContaining('private-password'), findsNothing);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await second, isNull);
  });

  testWidgets('password prompt shows the issuer instruction as a hint', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigatorKey, home: const SizedBox()),
    );

    final password = PasswordInputService.requestPassword(
      'HSBC',
      attempt: 1,
      maxAttempts: 2,
      hint: 'Use the first four letters of your name followed by DDMM.',
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Hint: Use the first four letters of your name followed by DDMM.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await password, isNull);
  });
}
