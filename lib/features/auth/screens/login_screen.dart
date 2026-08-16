import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/brand_tokens.dart';
import '../providers/auth_provider.dart';

class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authNotifierProvider);
    ref.listen(authNotifierProvider, (_, next) {
      if (next.hasError) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sign-in failed. Please try again.')),
        );
      }
    });
    return LoginView(
      isLoading: auth.isLoading,
      error: auth.error,
      onGoogleSignIn: () =>
          ref.read(authNotifierProvider.notifier).signInWithGoogle(),
      onOpenLegal: (path) =>
          launchUrl(Uri.parse(path), webOnlyWindowName: '_blank'),
    );
  }
}

class LoginView extends StatefulWidget {
  const LoginView({
    required this.isLoading,
    required this.error,
    required this.onGoogleSignIn,
    required this.onOpenLegal,
    super.key,
  });

  final bool isLoading;
  final Object? error;
  final VoidCallback onGoogleSignIn;
  final ValueChanged<String> onOpenLegal;

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  Timer? _timer;
  int _scenarioIndex = 0;
  bool _paused = false;
  bool _reducedMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (reduced != _reducedMotion) {
      _reducedMotion = reduced;
      _restartTimer();
    } else if (_timer == null && !_reducedMotion) {
      _restartTimer();
    }
  }

  void _restartTimer() {
    _timer?.cancel();
    _timer = null;
    if (_reducedMotion || _paused) return;
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted) return;
      setState(() => _scenarioIndex = (_scenarioIndex + 1) % _scenarios.length);
    });
  }

  void _selectScenario(int index) {
    setState(() => _scenarioIndex = index);
    _restartTimer();
  }

  void _setPaused(bool paused) {
    if (_paused == paused) return;
    _paused = paused;
    _restartTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BrandColors.ink,
      body: Stack(
        children: [
          const Positioned.fill(child: CustomPaint(painter: _GridPainter())),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final desktop = constraints.maxWidth >= 900;
                final horizontal = desktop
                    ? (constraints.maxWidth * .04).clamp(32.0, 64.0)
                    : 20.0;
                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(horizontal, 20, horizontal, 40),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1440),
                      child: Column(
                        children: [
                          const _Header(),
                          SizedBox(height: desktop ? 82 : 38),
                          if (desktop)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 102,
                                  child: _LoginColumn(
                                    isLoading: widget.isLoading,
                                    error: widget.error,
                                    onGoogleSignIn: widget.onGoogleSignIn,
                                    onOpenLegal: widget.onOpenLegal,
                                  ),
                                ),
                                const SizedBox(width: 70),
                                Expanded(
                                  flex: 98,
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 75),
                                    child: _ProofColumn(
                                      index: _scenarioIndex,
                                      onSelect: _selectScenario,
                                      onPauseChanged: _setPaused,
                                    ),
                                  ),
                                ),
                              ],
                            )
                          else
                            Column(
                              children: [
                                _LoginColumn(
                                  isLoading: widget.isLoading,
                                  error: widget.error,
                                  onGoogleSignIn: widget.onGoogleSignIn,
                                  onOpenLegal: widget.onOpenLegal,
                                ),
                                const SizedBox(height: 46),
                                _ProofColumn(
                                  index: _scenarioIndex,
                                  onSelect: _selectScenario,
                                  onPauseChanged: _setPaused,
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => Row(
        children: [
          const _AnimatedCompassMark(),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              'CardCompass',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Manrope',
                color: BrandColors.paper,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (constraints.maxWidth >= 460)
            Text(
              'Secure sign-in',
              style: TextStyle(
                fontFamily: 'Manrope',
                color: BrandColors.mutedPaper,
                fontSize: 12,
              ),
            ),
        ],
      ),
    );
  }
}

class _AnimatedCompassMark extends StatefulWidget {
  const _AnimatedCompassMark();

  @override
  State<_AnimatedCompassMark> createState() => _AnimatedCompassMarkState();
}

class _AnimatedCompassMarkState extends State<_AnimatedCompassMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _reducedMotion = false;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    if (reducedMotion == _reducedMotion && _controller.value > 0) return;
    _reducedMotion = reducedMotion;
    if (reducedMotion) {
      _controller.stop();
      _controller.value = 1;
    } else if (!_controller.isCompleted) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: AnimatedRotation(
      turns: _reducedMotion ? 0 : (_hovered ? .012 : 0),
      duration: _reducedMotion
          ? Duration.zero
          : const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      child: RepaintBoundary(
        key: const Key('cardcompass-mark'),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (_, _) => CustomPaint(
            size: const Size.square(28),
            painter: _CompassMarkPainter(_controller.value),
          ),
        ),
      ),
    ),
  );
}

class _CompassMarkPainter extends CustomPainter {
  const _CompassMarkPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final radius = size.width * .21;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius)),
      Paint()..color = const Color(0xFF0D102F),
    );

    final center = rect.center;
    final arcRect = Rect.fromCircle(center: center, radius: size.width * .36);
    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * .105
      ..strokeCap = StrokeCap.round
      ..shader = const SweepGradient(
        startAngle: math.pi * .75,
        endAngle: math.pi * 2.25,
        colors: [Color(0xFFFF008A), Color(0xFF8B50EC), Color(0xFF00DFED)],
      ).createShader(arcRect);
    canvas.drawArc(
      arcRect,
      math.pi * .72,
      math.pi * 1.56 * Curves.easeOutCubic.transform(progress),
      false,
      arcPaint,
    );

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate((1 - Curves.easeOutBack.transform(progress)) * -.42);
    final needleOpacity = progress.clamp(0.0, 1.0);
    canvas.drawPath(
      Path()
        ..moveTo(0, -size.width * .31)
        ..lineTo(size.width * .085, -size.width * .035)
        ..lineTo(0, -size.width * .13)
        ..lineTo(-size.width * .085, -size.width * .035)
        ..close(),
      Paint()..color = Colors.white.withValues(alpha: needleOpacity),
    );
    canvas.drawPath(
      Path()
        ..moveTo(0, size.width * .31)
        ..lineTo(size.width * .085, size.width * .035)
        ..lineTo(0, size.width * .13)
        ..lineTo(-size.width * .085, size.width * .035)
        ..close(),
      Paint()..color = const Color(0xFF00DFED).withValues(alpha: needleOpacity),
    );
    canvas.drawCircle(
      Offset.zero,
      size.width * .08,
      Paint()
        ..color = Colors.transparent
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      Offset.zero,
      size.width * .08,
      Paint()
        ..color = Colors.white.withValues(alpha: needleOpacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * .025,
    );
    canvas.restore();

    final pulse = ((progress - .72) / .28).clamp(0.0, 1.0);
    if (pulse > 0 && pulse < 1) {
      canvas.drawCircle(
        center,
        size.width * (.14 + .09 * pulse),
        Paint()
          ..color = const Color(0xFF62D8CE).withValues(alpha: (1 - pulse) * .35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CompassMarkPainter oldDelegate) =>
      progress != oldDelegate.progress;
}

class _LoginColumn extends StatelessWidget {
  const _LoginColumn({
    required this.isLoading,
    required this.error,
    required this.onGoogleSignIn,
    required this.onOpenLegal,
  });

  final bool isLoading;
  final Object? error;
  final VoidCallback onGoogleSignIn;
  final ValueChanged<String> onOpenLegal;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 660),
      child: Column(
        key: const Key('login-panel'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Kicker('WELCOME BACK · SECURE ACCESS'),
          const SizedBox(height: 14),
          RichText(
            key: const Key('login-headline'),
            text: TextSpan(
              style: GoogleFonts.manrope(
                color: BrandColors.paper,
                fontSize: 48,
                height: .98,
                letterSpacing: -2.1,
                fontWeight: FontWeight.w700,
              ),
              children: const [
                TextSpan(text: 'Continue to your\n'),
                TextSpan(
                  text: 'CardCompass',
                  style: TextStyle(color: BrandColors.reward),
                ),
                TextSpan(text: ' wallet.'),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Compare the cards you already own and understand the calculation behind every recommendation.',
            style: TextStyle(
              fontFamily: 'Manrope',
              color: BrandColors.mutedPaper,
              fontSize: 16,
              height: 1.65,
            ),
          ),
          const SizedBox(height: 28),
          Container(
            key: const Key('login-card'),
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFFF3EEE4),
              borderRadius: BorderRadius.circular(2),
              border: Border.all(color: const Color(0xFFD8D1C5)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0xB3382A13),
                  blurRadius: 0,
                  offset: Offset(9, 10),
                ),
              ],
            ),
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: Container(width: 5, color: const Color(0xFF62D8CE)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(30, 27, 27, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CARDHOLDER ACCESS · PRIVATE',
                        style: GoogleFonts.ibmPlexMono(
                          color: const Color(0xFF397B76),
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.25,
                        ),
                      ),
                      const SizedBox(height: 11),
                      Text(
                        'Your wallet,\nready when you are.',
                        style: GoogleFonts.fraunces(
                          color: const Color(0xFF141B1E),
                          fontSize: 29,
                          height: 1.02,
                          letterSpacing: -.8,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Continue with the Google account connected to CardCompass.',
                        style: TextStyle(
                          fontFamily: 'Manrope',
                          color: const Color(0xFF526064),
                          fontSize: 12,
                          height: 1.45,
                        ),
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Sign-in failed. Check your connection and try again.',
                          style: TextStyle(
                            fontFamily: 'Manrope',
                            color: const Color(0xFFB3261E),
                            fontSize: 12,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      _GoogleSignInButton(
                        isLoading: isLoading,
                        onPressed: onGoogleSignIn,
                      ),
                      const SizedBox(height: 17),
                      const Divider(color: Color(0xFFB9B4AB), height: 1),
                      const SizedBox(height: 5),
                      const _PermissionRow(
                        rowKey: Key('permission-profile'),
                        label: 'PROFILE',
                        value: 'Name and email',
                      ),
                      const _PermissionRow(
                        rowKey: Key('permission-birthday'),
                        label: 'BIRTHDAY',
                        value: 'Benefit eligibility',
                      ),
                      const _PermissionRow(
                        rowKey: Key('permission-gmail'),
                        label: 'GMAIL',
                        value: 'Read-only Gmail access for statement discovery',
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 9,
                        ),
                        color: const Color(0xFF142124),
                        child: Text(
                          'NEVER REQUESTED · CVV / PIN / OTP / BANK PASSWORD',
                          style: GoogleFonts.ibmPlexMono(
                            color: const Color(0xFFBCE9E4),
                            fontSize: 8.5,
                            height: 1.4,
                            letterSpacing: .35,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: Wrap(
                          spacing: 14,
                          runSpacing: 2,
                          alignment: WrapAlignment.center,
                          children: [
                            _LegalLink(
                              'Privacy',
                              destination: '/privacy/',
                              onOpen: onOpenLegal,
                              dark: true,
                            ),
                            _LegalLink(
                              'Data & Security',
                              destination: '/data-security/',
                              onOpen: onOpenLegal,
                              dark: true,
                            ),
                            _LegalLink(
                              'Terms',
                              destination: '/terms/',
                              onOpen: onOpenLegal,
                              dark: true,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProofColumn extends StatelessWidget {
  const _ProofColumn({
    required this.index,
    required this.onSelect,
    required this.onPauseChanged,
  });
  final int index;
  final ValueChanged<int> onSelect;
  final ValueChanged<bool> onPauseChanged;

  @override
  Widget build(BuildContext context) {
    final scenario = _scenarios[index];
    return Focus(
      onFocusChange: onPauseChanged,
      child: MouseRegion(
        onEnter: (_) => onPauseChanged(true),
        onExit: (_) => onPauseChanged(false),
        child: Column(
          key: const Key('recommendation-proof'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            SizedBox(
              key: const Key('proof-heading'),
              height: 89,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Kicker('INTERACTIVE PREVIEW'),
                        const SizedBox(height: 5),
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.topLeft,
                            child: Text(
                              'One purchase. One clear\ndecision.',
                              style: GoogleFonts.fraunces(
                                color: const Color(0xFFF3F0E8),
                                fontSize: 29,
                                height: 1.15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0x808E6C35)),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Text(
                      'ILLUSTRATIVE',
                      style: GoogleFonts.ibmPlexMono(
                        color: const Color(0xFFFFB547),
                        fontSize: 9,
                        letterSpacing: 1.08,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Wrap(
              key: const Key('scenario-tabs'),
              spacing: 7,
              children: List.generate(_scenarios.length, (i) {
                final selected = i == index;
                return SizedBox(
                  height: 38,
                  child: TextButton(
                    onPressed: () => onSelect(i),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 38),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      foregroundColor: selected
                          ? BrandColors.ink
                          : BrandColors.mutedPaper,
                      backgroundColor: selected
                          ? const Color(0xFF62D8CE)
                          : const Color(0x0AF4F0E6),
                      side: BorderSide(
                        color: selected
                            ? const Color(0xFF62D8CE)
                            : Colors.white.withValues(alpha: .13),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(3),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 13),
                    ),
                    child: Text(
                      _scenarios[i].label,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 12),
            AnimatedSwitcher(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 260),
              child: _Receipt(
                key: ValueKey(scenario.label),
                scenario: scenario,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Receipt extends StatelessWidget {
  const _Receipt({required this.scenario, super.key});
  final _Scenario scenario;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        key: const Key('decision-receipt'),
        width: 510,
        child: CustomPaint(
          key: const Key('receipt-perforations'),
          foregroundPainter: const _ReceiptPaperPainter(),
          child: Container(
            padding: const EdgeInsets.fromLTRB(28, 26, 28, 24),
            decoration: const BoxDecoration(
              color: Color(0xFFF4F0E6),
              boxShadow: [
                BoxShadow(color: Color(0xFFFFB547), offset: Offset(14, 18)),
                BoxShadow(
                  color: Color(0x3303070A),
                  blurRadius: 36,
                  offset: Offset(0, 18),
                ),
              ],
            ),
            child: DefaultTextStyle(
              style: GoogleFonts.manrope(
                color: const Color(0xFF0B1015),
                fontSize: 11,
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _Mono('CARD CHOICE / DEMO'),
                        _Mono(scenario.code),
                      ],
                    ),
                  ),
                  const _DashedRule(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 22, 0, 18),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Text(
                            scenario.merchant,
                            style: const TextStyle(
                              color: Color(0xFF566064),
                              fontSize: 13,
                            ),
                          ),
                        ),
                        Text(
                          scenario.amount,
                          style: GoogleFonts.ibmPlexMono(
                            fontSize: 25,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      const Expanded(
                        child: Divider(color: Color(0xFF69A69E), height: 1),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 9),
                        child: _Mono(
                          'BEST FIT',
                          color: const Color(0xFF28756D),
                        ),
                      ),
                      const Expanded(
                        child: Divider(color: Color(0xFF69A69E), height: 1),
                      ),
                    ],
                  ),
                  const SizedBox(height: 17),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCE7E3),
                      border: Border.all(color: const Color(0xFF9FB8B0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Mono('USE THIS CARD', color: const Color(0xFF28756D)),
                        const SizedBox(height: 2),
                        Text(
                          scenario.card,
                          style: GoogleFonts.fraunces(
                            fontSize: 27,
                            height: 1.15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 15),
                        const Divider(color: Color(0x240B1015), height: 1),
                        const SizedBox(height: 11),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Expanded(
                              child: Text(
                                'Illustrative value',
                                style: TextStyle(
                                  color: Color(0xFF566064),
                                  fontSize: 10,
                                ),
                              ),
                            ),
                            Text(
                              scenario.value,
                              style: GoogleFonts.ibmPlexMono(
                                color: const Color(0xFF9B5A00),
                                fontSize: 27,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 17),
                  _ReceiptLine('EXAMPLE EARN', scenario.earn),
                  _ReceiptLine('WHAT TO CHECK', scenario.check),
                  _ReceiptLine('WHY IT WINS', scenario.reason),
                  const SizedBox(height: 15),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(11),
                    color: const Color(0xFF0B1015),
                    child: const Column(
                      children: [
                        _VerificationLine(
                          'SOURCE',
                          'Illustrative rule set—not live issuer data',
                        ),
                        SizedBox(height: 6),
                        _VerificationLine('DEMO UPDATED', '15 Aug 2026'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 13),
                  Text(
                    'This preview demonstrates the decision format. It is not a live recommendation or financial advice.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.manrope(
                      color: const Color(0xFF777C79),
                      fontSize: 8,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VerificationLine extends StatelessWidget {
  const _VerificationLine(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(
        width: 86,
        child: Text(
          label,
          style: GoogleFonts.ibmPlexMono(
            color: const Color(0xFF3FE0D0),
            fontSize: 8,
          ),
        ),
      ),
      Expanded(
        child: Text(
          value,
          textAlign: TextAlign.right,
          style: GoogleFonts.ibmPlexMono(
            color: const Color(0xFFF4F0E6),
            fontSize: 8,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    ],
  );
}

class _ReceiptLine extends StatelessWidget {
  const _ReceiptLine(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 112,
              child: _Mono(label, color: const Color(0xFF566064)),
            ),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        const _DashedRule(),
      ],
    ),
  );
}

class _DashedRule extends StatelessWidget {
  const _DashedRule();
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 1,
    child: CustomPaint(painter: const _DashedRulePainter()),
  );
}

class _DashedRulePainter extends CustomPainter {
  const _DashedRulePainter();
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x570B1015)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 7) {
      canvas.drawLine(
        Offset(x, 0),
        Offset((x + 4).clamp(0, size.width), 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ReceiptPaperPainter extends CustomPainter {
  const _ReceiptPaperPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = const Color(0x080B1015)
      ..strokeWidth = 1;
    for (double y = 28; y < size.height; y += 28) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }
    final holePaint = Paint()..color = const Color(0xFF0B1015);
    for (double y = 8; y < size.height; y += 16) {
      canvas.drawCircle(Offset(0, y), 3, holePaint);
      canvas.drawCircle(Offset(size.width, y), 3, holePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Kicker extends StatelessWidget {
  const _Kicker(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: GoogleFonts.ibmPlexMono(
      color: const Color(0xFF62D8CE),
      fontSize: 10,
      fontWeight: FontWeight.w600,
      letterSpacing: 1.4,
    ),
  );
}

class _Mono extends StatelessWidget {
  const _Mono(this.text, {this.color = const Color(0xFF334043)});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: GoogleFonts.ibmPlexMono(
      color: color,
      fontSize: 8,
      letterSpacing: .8,
    ),
  );
}

class _LegalLink extends StatelessWidget {
  const _LegalLink(
    this.text, {
    required this.destination,
    required this.onOpen,
    this.dark = false,
  });
  final String text;
  final String destination;
  final ValueChanged<String> onOpen;
  final bool dark;
  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () => onOpen(destination),
    style: TextButton.styleFrom(
      foregroundColor: dark ? const Color(0xFF536064) : BrandColors.mutedPaper,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      minimumSize: const Size(44, 36),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    child: Semantics(
      label: 'Open $text in a new tab',
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 10,
          decoration: TextDecoration.underline,
        ),
      ),
    ),
  );
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.rowKey,
    required this.label,
    required this.value,
  });

  final Key rowKey;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    key: rowKey,
    padding: const EdgeInsets.symmetric(vertical: 8),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: Color(0xFFD4D0C8))),
    ),
    child: Row(
      children: [
        SizedBox(
          width: 94,
          child: Text(
            label,
            style: GoogleFonts.ibmPlexMono(
              color: const Color(0xFF637174),
              fontSize: 8.5,
              letterSpacing: .65,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontFamily: 'Manrope',
              color: const Color(0xFF202A2D),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

class _GoogleSignInButton extends StatelessWidget {
  const _GoogleSignInButton({required this.isLoading, required this.onPressed});
  final bool isLoading;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 50,
    child: OutlinedButton(
      onPressed: isLoading ? null : onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: const Color(0xFFF7F7F4),
        disabledBackgroundColor: const Color(0xFFE2E3DF),
        foregroundColor: const Color(0xFF182124),
        side: const BorderSide(color: Color(0xFFD8D9D5)),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      ),
      child: isLoading
          ? const SizedBox(
              width: 21,
              height: 21,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF182124),
              ),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const _GoogleIcon(),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    'Continue with Google',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      color: const Color(0xFF182124),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
    ),
  );
}

class _GoogleIcon extends StatelessWidget {
  const _GoogleIcon();
  @override
  Widget build(BuildContext context) => Container(
    width: 20,
    height: 20,
    alignment: Alignment.center,
    decoration: const BoxDecoration(
      color: Colors.white,
      shape: BoxShape.circle,
    ),
    child: const Text(
      'G',
      style: TextStyle(
        color: Color(0xFF4285F4),
        fontWeight: FontWeight.w800,
        fontSize: 13,
      ),
    ),
  );
}

class _GridPainter extends CustomPainter {
  const _GridPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x0F3FE0D0)
      ..strokeWidth = .6;
    for (double x = 0; x < size.width; x += 42) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += 42) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Scenario {
  const _Scenario(
    this.label,
    this.code,
    this.merchant,
    this.amount,
    this.card,
    this.value,
    this.earn,
    this.check,
    this.reason,
  );
  final String label;
  final String code;
  final String merchant;
  final String amount;
  final String card;
  final String value;
  final String earn;
  final String check;
  final String reason;
}

const _scenarios = [
  _Scenario(
    'Groceries',
    'CC-0815-01',
    'Neighbourhood grocery',
    '₹2,400',
    'Example Cashback Card',
    '₹120',
    '5% cashback',
    'Category eligibility and monthly cashback cap',
    'Higher example return than the other cards in this demo wallet',
  ),
  _Scenario(
    'Dining',
    'CC-0815-02',
    'Weekend restaurant',
    '₹3,200',
    'Example Dining Card',
    '₹320',
    '10% example value',
    'Partner restaurant list and per-transaction cap',
    'Partner offer beats the base rewards in this illustrative comparison',
  ),
  _Scenario(
    'Movies',
    'CC-0815-03',
    'Two cinema tickets',
    '₹900',
    'Example Movie Card',
    '₹450',
    'Illustrative BOGO',
    'Booking channel, ticket limit, and monthly usage',
    'The example ticket benefit is worth more than a standard earn rate here',
  ),
];
