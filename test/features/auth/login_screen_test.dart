import 'package:cardcompass/features/auth/screens/login_screen.dart';
import 'package:cardcompass/core/theme/brand_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _testApp({
  bool disableAnimations = false,
  bool isLoading = false,
  VoidCallback? onGoogleSignIn,
  ValueChanged<String>? onOpenLegal,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: const Size(1440, 1000),
        disableAnimations: disableAnimations,
      ),
      child: LoginView(
        isLoading: isLoading,
        error: null,
        onGoogleSignIn: onGoogleSignIn ?? () {},
        onOpenLegal: onOpenLegal ?? (_) {},
      ),
    ),
  );
}

Future<void> _setSurface(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

void main() {
  testWidgets('headline reserves reward yellow for the CardCompass name', (
    tester,
  ) async {
    await _setSurface(tester, const Size(1440, 1000));
    await tester.pumpWidget(_testApp());
    await tester.pump();

    final headline = tester.widget<RichText>(
      find.byKey(const Key('login-headline')),
    );
    final root = headline.text as TextSpan;
    final brandSpan = root.children!.cast<TextSpan>().singleWhere(
      (span) => span.text == 'CardCompass',
    );
    expect(brandSpan.style?.color, BrandColors.reward);
    expect(root.toPlainText(), 'Continue to your\nCardCompass wallet.');
  });

  testWidgets('login uses bundled font families and available weights', (
    tester,
  ) async {
    await _setSurface(tester, const Size(1440, 1000));
    await tester.pumpWidget(_testApp());
    await tester.pump();

    final accessLabel = tester.widget<Text>(
      find.text('CARDHOLDER ACCESS · PRIVATE'),
    );
    expect(accessLabel.style?.fontFamily, 'IBM Plex Mono');
    expect(accessLabel.style?.fontWeight, FontWeight.w600);

    final folioHeading = tester.widget<Text>(
      find.text('Your wallet,\nready when you are.'),
    );
    expect(folioHeading.style?.fontFamily, 'Fraunces');
    expect(folioHeading.style?.fontWeight, FontWeight.w600);
  });

  testWidgets('desktop login keeps authentication left of the product proof', (
    tester,
  ) async {
    await _setSurface(tester, const Size(1440, 1000));
    await tester.pumpWidget(_testApp());
    await tester.pump();

    expect(find.byKey(const Key('login-headline')), findsOneWidget);
    expect(find.byKey(const Key('login-panel')), findsOneWidget);
    expect(find.byKey(const Key('recommendation-proof')), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const Key('login-panel'))).dx,
      lessThan(
        tester.getTopLeft(find.byKey(const Key('recommendation-proof'))).dx,
      ),
    );
    expect(find.textContaining('Gmail access'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
  });

  testWidgets('login copy is selectable for browser users', (tester) async {
    await _setSurface(tester, const Size(1440, 1000));
    await tester.pumpWidget(_testApp());
    await tester.pump();

    expect(find.byType(SelectionArea), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(SelectionArea),
        matching: find.byKey(const Key('login-headline')),
      ),
      findsOneWidget,
    );
  });

  testWidgets('header compass animation becomes static with reduced motion', (
    tester,
  ) async {
    await _setSurface(tester, const Size(1440, 1000));
    await tester.pumpWidget(_testApp());
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byKey(const Key('cardcompass-mark')), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isTrue);

    await tester.pumpWidget(_testApp(disableAnimations: true));
    await tester.pump();
    expect(find.byKey(const Key('cardcompass-mark')), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('sign-in folio explains each Google permission before consent', (
    tester,
  ) async {
    await _setSurface(tester, const Size(1440, 1000));
    await tester.pumpWidget(_testApp());
    await tester.pump();

    expect(find.byKey(const Key('login-card')), findsOneWidget);
    expect(find.text('CARDHOLDER ACCESS · PRIVATE'), findsOneWidget);
    expect(find.text('Your wallet,\nready when you are.'), findsOneWidget);
    expect(find.byKey(const Key('permission-profile')), findsOneWidget);
    expect(find.byKey(const Key('permission-birthday')), findsOneWidget);
    expect(find.byKey(const Key('permission-gmail')), findsOneWidget);
    expect(find.text('Name and email'), findsOneWidget);
    expect(find.text('Benefit eligibility'), findsOneWidget);
    expect(
      find.text('Read-only Gmail access for statement discovery'),
      findsOneWidget,
    );
    expect(
      find.text('NEVER REQUESTED · CVV / PIN / OTP / BANK PASSWORD'),
      findsOneWidget,
    );

    final button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Continue with Google'),
    );
    expect(
      button.style?.backgroundColor?.resolve(<WidgetState>{}),
      const Color(0xFFF7F7F4),
    );
  });

  testWidgets('legal controls open their matching public pages', (
    tester,
  ) async {
    final opened = <String>[];
    await _setSurface(tester, const Size(1440, 1000));
    await tester.pumpWidget(_testApp(onOpenLegal: opened.add));
    await tester.pump();

    for (final destination in const {
      'Privacy': '/privacy/',
      'Data & Security': '/data-security/',
      'Terms': '/terms/',
    }.entries) {
      await tester.tap(find.text(destination.key));
      await tester.pump();
      expect(opened.last, destination.value);
    }
  });

  testWidgets('Google action fires once and is disabled while loading', (
    tester,
  ) async {
    var signInCount = 0;
    await _setSurface(tester, const Size(1440, 1000));
    await tester.pumpWidget(_testApp(onGoogleSignIn: () => signInCount++));
    await tester.pump();
    await tester.tap(find.text('Continue with Google'));
    expect(signInCount, 1);

    await tester.pumpWidget(
      _testApp(isLoading: true, onGoogleSignIn: () => signInCount++),
    );
    await tester.pump();
    final loadingButton = tester.widget<OutlinedButton>(
      find.byType(OutlinedButton),
    );
    expect(loadingButton.onPressed, isNull);
    expect(signInCount, 1);
  });

  testWidgets('product proof preserves the landing receipt specification', (
    tester,
  ) async {
    await _setSurface(tester, const Size(1440, 1000));
    await tester.pumpWidget(_testApp());
    await tester.pump();

    expect(
      tester.getSize(find.byKey(const Key('decision-receipt'))).width,
      closeTo(510, 0.1),
    );
    expect(find.byKey(const Key('receipt-perforations')), findsOneWidget);
    expect(find.text('EXAMPLE EARN'), findsOneWidget);
    expect(find.text('5% cashback'), findsOneWidget);
    expect(
      find.text('Illustrative rule set—not live issuer data'),
      findsOneWidget,
    );
    expect(find.text('15 Aug 2026'), findsOneWidget);
    expect(
      find.text(
        'This preview demonstrates the decision format. It is not a live recommendation or financial advice.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'desktop proof occupies the same coordinates as the landing page',
    (tester) async {
      await _setSurface(tester, const Size(1745, 982));
      await tester.pumpWidget(_testApp());
      await tester.pump();

      final proof = tester.getRect(
        find.byKey(const Key('recommendation-proof')),
      );
      final receipt = tester.getRect(find.byKey(const Key('decision-receipt')));
      final heading = tester.getRect(find.byKey(const Key('proof-heading')));
      final tabs = tester.getRect(find.byKey(const Key('scenario-tabs')));

      expect(proof.left, closeTo(921, 1));
      expect(proof.top, closeTo(205, 1));
      expect(
        {
          'headingTop': heading.top,
          'headingHeight': heading.height,
          'tabsTop': tabs.top,
          'tabsHeight': tabs.height,
        },
        {
          'headingTop': closeTo(221, 1),
          'headingHeight': closeTo(89, 1),
          'tabsTop': closeTo(328, 1),
          'tabsHeight': closeTo(38, 1),
        },
      );
      expect(receipt.left, closeTo(1002, 1));
      expect(receipt.top, closeTo(378, 1));
    },
  );

  testWidgets(
    'recommendation proof rotates and manual choice restarts the cycle',
    (tester) async {
      await _setSurface(tester, const Size(1440, 1000));
      await tester.pumpWidget(_testApp());
      await tester.pump();

      expect(find.text('Neighbourhood grocery'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      expect(find.text('Weekend restaurant'), findsOneWidget);

      await tester.tap(find.text('Movies'));
      await tester.pump();
      expect(find.text('Two cinema tickets'), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Two cinema tickets'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Neighbourhood grocery'), findsOneWidget);
    },
  );

  testWidgets('reduced motion leaves scenarios under manual control', (
    tester,
  ) async {
    await _setSurface(tester, const Size(1440, 1000));
    await tester.pumpWidget(_testApp(disableAnimations: true));
    await tester.pump();

    expect(find.text('Neighbourhood grocery'), findsOneWidget);
    await tester.pump(const Duration(seconds: 8));
    expect(find.text('Neighbourhood grocery'), findsOneWidget);

    await tester.tap(find.text('Dining'));
    await tester.pump();
    expect(find.text('Weekend restaurant'), findsOneWidget);
  });

  testWidgets(
    'mobile presents authentication before the recommendation proof',
    (tester) async {
      await _setSurface(tester, const Size(390, 844));
      await tester.pumpWidget(_testApp());
      await tester.pump();

      expect(
        tester.getTopLeft(find.byKey(const Key('login-panel'))).dy,
        lessThan(
          tester.getTopLeft(find.byKey(const Key('recommendation-proof'))).dy,
        ),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
