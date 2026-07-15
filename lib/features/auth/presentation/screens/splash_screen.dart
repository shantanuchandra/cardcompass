import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/app_config.dart';
import '../../../../core/theme.dart';
import '../../../cards/presentation/screens/home_screen.dart';
import '../../../dashboard/viewmodels/dashboard_viewmodel.dart';
import '../../providers/auth_provider.dart';
import 'login_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// CARDCOMPASS SPLASH — 2026 Edition
//
// Design principles (CardCompass cyberpunk fintech):
//
// FROM GROWTHX — what we learned:
//   • Confidence through restraint — fewer elements, more impact
//   • Generous whitespace — let the logo breathe
//   • Single continuous experience — no jarring stage transitions
//   • Purposeful, subtle animation — nothing gratuitous
//
// TRANSLATED INTO CARDCOMPASS DESIGN LANGUAGE:
//   • Background: surfaceVoid (#020810) — our deepest, most cinematic surface
//   • Brand gradient glow: cyan → purple, softly radiating behind the logo
//   • Logo: real app icon with neonGlow — our signature glow effect
//   • Typography: Space Grotesk (our brand font), neon cyan accent
//   • Loader: pulsing dots in primary cyan — minimal, alive
//   • Copy: human-readable but on-brand ("Every Swipe, Optimised.")
// ═══════════════════════════════════════════════════════════════════════════════

/// Dashboard loading wrapper — continues the splash visual seamlessly
/// while loading dashboard data. Eliminates "double splash" by sharing
/// the same [_SplashSurface] as [SplashScreen].
class DashboardLoadingWrapper extends ConsumerStatefulWidget {
  final VoidCallback? onDashboardReady;

  const DashboardLoadingWrapper({
    super.key,
    this.onDashboardReady,
  });

  @override
  ConsumerState<DashboardLoadingWrapper> createState() =>
      _DashboardLoadingWrapperState();
}

class _DashboardLoadingWrapperState
    extends ConsumerState<DashboardLoadingWrapper> {
  static const _dashboardLoadTimeout = Duration(seconds: 8);
  static const _fixedDelaysBudget = Duration(milliseconds: 500 + 700 + 500);
  static const _fallbackHeadroom = Duration(seconds: 2);
  static final _fallbackTimeout =
      _dashboardLoadTimeout + _fixedDelaysBudget + _fallbackHeadroom;

  String _currentStatus = 'Loading your dashboard...';
  bool _dashboardReady = false;
  bool _showTimeoutFallback = false;
  Timer? _timeoutTimer;

  @override
  void initState() {
    super.initState();
    _initializeDashboard();
    _timeoutTimer = Timer(_fallbackTimeout, () {
      if (mounted && !_dashboardReady) {
        setState(() => _showTimeoutFallback = true);
      }
    });
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    super.dispose();
  }

  Future<void> _initializeDashboard() async {
    try {
      final authState = ref.read(authStateProvider);
      if (authState.user != null) {
        await _updateStatus('Syncing your cards...');
        await Future.delayed(const Duration(milliseconds: 500));

        await ref
            .read(dashboardViewModelProvider.notifier)
            .loadDashboardData(authState.user!.id)
            .timeout(_dashboardLoadTimeout);

        await _updateStatus('Preparing your insights...');
        await Future.delayed(const Duration(milliseconds: 700));

        await _updateStatus('Almost ready...');
        await Future.delayed(const Duration(milliseconds: 500));

        widget.onDashboardReady?.call();

        if (mounted) {
          setState(() => _dashboardReady = true);
          await Future.delayed(const Duration(milliseconds: 400));

          if (mounted) {
            _timeoutTimer?.cancel();
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const HomeScreen()),
            );
          }
        }
      }
    } catch (e) {
      await _updateStatus('Finishing up...');
      await Future.delayed(const Duration(milliseconds: 1000));

      if (mounted) {
        _timeoutTimer?.cancel();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    }
  }

  Future<void> _updateStatus(String status) async {
    if (mounted) setState(() => _currentStatus = status);
  }

  @override
  Widget build(BuildContext context) {
    return _SplashSurface(
      status: _currentStatus,
      showReady: _dashboardReady,
      showTimeout: _showTimeoutFallback && !_dashboardReady,
      onTimeoutAction: () {
        _timeoutTimer?.cancel();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      },
      animateEntry: false, // Seamless continuation — no re-animation
    );
  }
}

/// Initial splash screen — handles auth check and routes accordingly.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  static const _authCheckTimeout = Duration(seconds: 8);
  static const _fixedDelaysBudget =
      Duration(milliseconds: 800 + 600 + 400 + 500);
  static const _fallbackHeadroom = Duration(seconds: 2);
  static final _fallbackTimeout =
      _authCheckTimeout + _fixedDelaysBudget + _fallbackHeadroom;

  String _currentStatus = 'Initializing...';
  bool _showTimeoutFallback = false;
  bool _navigated = false;
  bool _isAdminDeepLink = false;
  Timer? _timeoutTimer;

  @override
  void initState() {
    super.initState();
    _initializeApp();
    _timeoutTimer = Timer(_fallbackTimeout, () {
      if (mounted && !_navigated && !_isAdminDeepLink) {
        setState(() => _showTimeoutFallback = true);
      }
    });
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    super.dispose();
  }

  Future<void> _initializeApp() async {
    final initialRoute = WidgetsBinding
        .instance.platformDispatcher.defaultRouteName
        .toLowerCase();
    if (initialRoute.contains('/admin/')) {
      print(
          '🚪 SplashScreen: Admin initial route detected ($initialRoute). Skipping home redirect.');
      _isAdminDeepLink = true;
      return;
    }

    await _updateStatus('Setting up...');
    await Future.delayed(const Duration(milliseconds: 800));

    await _updateStatus('Connecting securely...');
    await Future.delayed(const Duration(milliseconds: 600));

    if (mounted) {
      await _updateStatus('Checking your session...');

      try {
        await ref
            .read(authStateProvider.notifier)
            .refreshAuthState()
            .timeout(_authCheckTimeout, onTimeout: () {
          print(
              '⚠️ SplashScreen: Auth check timed out after ${_authCheckTimeout.inSeconds}s');
        });
      } catch (e) {
        print('⚠️ SplashScreen: Auth error: $e, proceeding to login');
      }

      await Future.delayed(const Duration(milliseconds: 400));

      if (mounted) {
        final authState = ref.read(authStateProvider);

        if (authState.isAuthenticated) {
          await _updateStatus('Welcome back!');
          await Future.delayed(const Duration(milliseconds: 500));

          _navigated = true;
          _timeoutTimer?.cancel();
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => DashboardLoadingWrapper(
                onDashboardReady: () async {
                  await _updateStatus('Ready');
                },
              ),
            ),
          );
        } else {
          await _updateStatus('Sign in to continue');
          await Future.delayed(const Duration(milliseconds: 300));

          _navigated = true;
          _timeoutTimer?.cancel();
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
          );
        }
      }
    }
  }

  void _continueToLogin() {
    if (_navigated) return;
    _navigated = true;
    _timeoutTimer?.cancel();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  Future<void> _updateStatus(String status) async {
    if (mounted) setState(() => _currentStatus = status);
  }

  @override
  Widget build(BuildContext context) {
    return _SplashSurface(
      status: _currentStatus,
      showTimeout: _showTimeoutFallback && !_navigated,
      onTimeoutAction: _continueToLogin,
      animateEntry: true,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// UNIFIED SPLASH SURFACE
//
// Shared by both SplashScreen (entry animations) and DashboardLoadingWrapper
// (no animations, seamless continuation). This ensures users see ONE
// consistent branded experience from cold start to dashboard.
//
// Uses CardCompass design tokens throughout:
//   - surfaceVoid for deepest background
//   - primaryColor (neon cyan) for interactive accents
//   - secondaryColor (purple) for ambient glow
//   - accentColor (magenta) for warm gradient balance
//   - neonGlow for the signature logo illumination
//   - Space Grotesk for all typography
// ═══════════════════════════════════════════════════════════════════════════════

class _SplashSurface extends StatefulWidget {
  final String status;
  final bool showReady;
  final bool showTimeout;
  final VoidCallback? onTimeoutAction;
  final bool animateEntry;

  const _SplashSurface({
    required this.status,
    this.showReady = false,
    this.showTimeout = false,
    this.onTimeoutAction,
    this.animateEntry = true,
  });

  @override
  State<_SplashSurface> createState() => _SplashSurfaceState();
}

class _SplashSurfaceState extends State<_SplashSurface>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breatheController;

  @override
  void initState() {
    super.initState();
    _breatheController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _breatheController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceVoid,
      body: AnimatedBuilder(
        animation: _breatheController,
        builder: (context, _) {
          final breathe = _breatheController.value;
          return SizedBox.expand(
            child: Stack(
              children: [
                // ─── Ambient brand glow ───
                // A soft radial gradient that breathes — creates
                // the signature CardCompass "neon atmosphere" without
                // being busy or distracting.
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(0.0, -0.2),
                        radius: 1.0 + breathe * 0.08,
                        colors: [
                          AppTheme.secondaryColor
                              .withValues(alpha: 0.06 + breathe * 0.02),
                          AppTheme.surfaceVoid,
                        ],
                        stops: const [0.0, 0.7],
                      ),
                    ),
                  ),
                ),

                // ─── Subtle accent warmth — bottom edge ───
                // A touch of magenta/cyan at the bottom creates depth
                // and visual interest without competing with the logo.
                Positioned(
                  bottom: -120,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      width: 500,
                      height: 250,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            AppTheme.primaryColor
                                .withValues(alpha: 0.04 + breathe * 0.01),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // ─── Main content ───
                Positioned.fill(
                  child: SafeArea(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // ─── App icon with neon glow ───
                          _buildLogo(breathe),

                          const SizedBox(height: 36),

                          // ─── Brand name ───
                          _buildTitle(),

                          const SizedBox(height: 10),

                          // ─── Tagline ───
                          _buildTagline(),

                          const SizedBox(height: 40),

                          // ─── Loader: thin progress bar + pulsing dots ───
                          SizedBox(
                            width: 180,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(
                                backgroundColor:
                                    AppTheme.surfaceSubtle.withValues(alpha: 0.4),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  AppTheme.primaryColor.withValues(alpha: 0.7),
                                ),
                                minHeight: 2,
                              ),
                            ),
                          ),

                          const SizedBox(height: 24),

                          // ─── Pulsing dots ───
                          _buildLoader(),

                          const SizedBox(height: 20),

                          // ─── Status message ───
                          _buildStatus(),

                          // ─── Ready confirmation ───
                          if (widget.showReady) ...[
                            const SizedBox(height: 12),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.check_circle_outline,
                                  color: AppTheme.successColor,
                                  size: 14,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Ready',
                                  style: GoogleFonts.spaceGrotesk(
                                    color: AppTheme.successColor,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            )
                                .animate()
                                .fadeIn(duration: 300.ms)
                                .scale(
                                    duration: 400.ms,
                                    curve: Curves.easeOutBack),
                          ],

                          // ─── Timeout fallback ───
                          if (widget.showTimeout) ...[
                            const SizedBox(height: 24),
                            Text(
                              'Taking longer than expected.',
                              style: GoogleFonts.spaceGrotesk(
                                color: Colors.white.withValues(alpha: 0.3),
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: widget.onTimeoutAction,
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 10),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  side: BorderSide(
                                    color: AppTheme.primaryColor
                                        .withValues(alpha: 0.3),
                                  ),
                                ),
                              ),
                              child: Text(
                                'Continue anyway',
                                style: GoogleFonts.spaceGrotesk(
                                  color: AppTheme.primaryColor,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ─── Logo ────────────────────────────────────────────────────────────────
  // The app icon sits in a subtle glassmorphic container with the
  // signature CardCompass neon glow. The glow breathes with the ambient
  // animation, creating a sense of the app being "alive."

  Widget _buildLogo(double breathe) {
    Widget logo = Container(
      width: 110,
      height: 110,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        // Neon glow — our signature effect, scaled for the splash context
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryColor
                .withValues(alpha: 0.12 + breathe * 0.06),
            blurRadius: 40 + breathe * 10,
            spreadRadius: 2,
          ),
          BoxShadow(
            color: AppTheme.secondaryColor
                .withValues(alpha: 0.08 + breathe * 0.04),
            blurRadius: 60 + breathe * 15,
            spreadRadius: 5,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Container(
          decoration: BoxDecoration(
            // Subtle surface raised tint behind the icon
            color: AppTheme.surfaceRaised,
            border: Border.all(
              color: AppTheme.surfaceSubtle.withValues(alpha: 0.5),
              width: 1,
            ),
          ),
          child: Image.asset(
            'assets/icons/app-icon.png',
            fit: BoxFit.cover,
          ),
        ),
      ),
    );

    if (widget.animateEntry) {
      logo = logo
          .animate()
          .fadeIn(duration: 600.ms, curve: Curves.easeOut)
          .scale(
            begin: const Offset(0.85, 0.85),
            end: const Offset(1.0, 1.0),
            duration: 700.ms,
            curve: Curves.easeOutBack,
          );
    }

    return logo;
  }

  // ─── Title ───────────────────────────────────────────────────────────────
  // Space Grotesk bold — our brand font. Clean white, no text-shadow
  // because the background glow provides enough depth.

  Widget _buildTitle() {
    Widget title = Text(
      AppConfig.appName.toUpperCase(),
      style: GoogleFonts.spaceGrotesk(
        fontWeight: FontWeight.w700,
        fontSize: 26,
        letterSpacing: 5.0,
        color: Colors.white,
      ),
    );

    if (widget.animateEntry) {
      title = title
          .animate()
          .fadeIn(delay: 300.ms, duration: 600.ms)
          .slideY(begin: 0.12, end: 0, delay: 300.ms, duration: 600.ms);
    }

    return title;
  }

  // ─── Tagline ─────────────────────────────────────────────────────────────
  // Subdued neon cyan — not white, because that would create visual
  // competition with the title. The cyan connects it to the brand.

  Widget _buildTagline() {
    Widget tagline = Text(
      'Every Swipe, Optimised.',
      style: GoogleFonts.spaceGrotesk(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.8,
        color: AppTheme.primaryColor.withValues(alpha: 0.6),
      ),
    );

    if (widget.animateEntry) {
      tagline = tagline
          .animate()
          .fadeIn(delay: 500.ms, duration: 600.ms)
          .slideY(begin: 0.12, end: 0, delay: 500.ms, duration: 600.ms);
    }

    return tagline;
  }

  // ─── Loader ──────────────────────────────────────────────────────────────

  Widget _buildLoader() {
    Widget loader = const _PulsingDots();

    if (widget.animateEntry) {
      loader = loader.animate().fadeIn(delay: 700.ms, duration: 500.ms);
    }

    return loader;
  }

  // ─── Status ──────────────────────────────────────────────────────────────
  // Very low opacity white — informational, not attention-grabbing.
  // The user's focus should be on the logo and brand, not the loading text.

  Widget _buildStatus() {
    Widget statusWidget = AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: Text(
        widget.status,
        key: ValueKey(widget.status),
        style: GoogleFonts.spaceGrotesk(
          color: Colors.white.withValues(alpha: 0.3),
          fontWeight: FontWeight.w400,
          fontSize: 12,
          letterSpacing: 0.5,
        ),
        textAlign: TextAlign.center,
      ),
    );

    if (widget.animateEntry) {
      statusWidget =
          statusWidget.animate().fadeIn(delay: 800.ms, duration: 500.ms);
    }

    return statusWidget;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PULSING DOTS — Minimal micro-interaction
//
// Three dots that pulse in sequence using the primary cyan color.
// No box-shadow / glow — the dots are small enough that adding glow
// would just create visual noise. Restraint is the point.
// ═══════════════════════════════════════════════════════════════════════════════

class _PulsingDots extends StatefulWidget {
  const _PulsingDots();

  @override
  State<_PulsingDots> createState() => _PulsingDotsState();
}

class _PulsingDotsState extends State<_PulsingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final delay = i * 0.25;
            final t = (_controller.value + delay) % 1.0;
            final opacity = 0.15 + 0.85 * math.sin(t * math.pi);

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.primaryColor.withValues(alpha: opacity),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
