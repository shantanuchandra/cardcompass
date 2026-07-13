import 'dart:async';

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

/// Wrapper widget that shows splash screen until dashboard is ready
class DashboardLoadingWrapper extends ConsumerStatefulWidget {
  final VoidCallback? onDashboardReady;
  
  const DashboardLoadingWrapper({
    super.key,
    this.onDashboardReady,
  });

  @override
  ConsumerState<DashboardLoadingWrapper> createState() => _DashboardLoadingWrapperState();
}

class _DashboardLoadingWrapperState extends ConsumerState<DashboardLoadingWrapper> {
  // The dashboard load below is bounded by _dashboardLoadTimeout; the fixed
  // status delays (500+700+500ms) add a small, known amount on top. The
  // fallback Timer's duration is derived from these instead of being an
  // independent guess, so the two can't silently drift out of sync if
  // either changes.
  static const _dashboardLoadTimeout = Duration(seconds: 8);
  static const _fixedDelaysBudget = Duration(milliseconds: 500 + 700 + 500);
  static const _fallbackHeadroom = Duration(seconds: 2);
  static final _fallbackTimeout = _dashboardLoadTimeout + _fixedDelaysBudget + _fallbackHeadroom;

  String _currentStatus = 'Loading your dashboard...';
  bool _dashboardReady = false;
  bool _showTimeoutFallback = false;
  double _progressValue = 0.1;
  Timer? _timeoutTimer;

  @override
  void initState() {
    super.initState();
    _initializeDashboard();
    _timeoutTimer = Timer(_fallbackTimeout, () {
      if (mounted && !_dashboardReady) {
        setState(() {
          _showTimeoutFallback = true;
        });
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
        await _updateStatus('Loading your cards...', 0.3);
        await Future.delayed(const Duration(milliseconds: 500));

        // Load dashboard data — bounded so a hung dependency can't block
        // navigation indefinitely (the timeout Timer below only toggles the
        // fallback UI, it doesn't cancel this call on its own).
        await ref
            .read(dashboardViewModelProvider.notifier)
            .loadDashboardData(authState.user!.id)
            .timeout(_dashboardLoadTimeout);

        await _updateStatus('Setting up your experience...', 0.6);
        await Future.delayed(const Duration(milliseconds: 700));

        await _updateStatus('Almost ready...', 0.9);
        await Future.delayed(const Duration(milliseconds: 500));

        widget.onDashboardReady?.call();

        if (mounted) {
          setState(() {
            _dashboardReady = true;
            _progressValue = 1.0;
          });

          await Future.delayed(const Duration(milliseconds: 400));

          if (mounted) {
            _timeoutTimer?.cancel();
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) => const HomeScreen(),
              ),
            );
          }
        }
      }
    } catch (e) {
      await _updateStatus('Loading dashboard...', 0.8);
      await Future.delayed(const Duration(milliseconds: 1000));

      if (mounted) {
        _timeoutTimer?.cancel();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => const HomeScreen(),
          ),
        );
      }
    }
  }

  Future<void> _updateStatus(String status, double progress) async {
    if (mounted) {
      setState(() {
        _currentStatus = status;
        _progressValue = progress;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF050B18),
              const Color(0xFF0C152B),
              AppTheme.secondaryColor.withValues(alpha: 0.15),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                flex: 3,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // App Logo with neon cyber styling
                      Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              AppTheme.primaryColor,
                              AppTheme.secondaryColor,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: AppTheme.neonGlow(color: AppTheme.primaryColor, opacity: 0.4),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.2),
                            width: 1.5,
                          ),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            const Icon(
                              Icons.credit_card,
                              size: 70,
                              color: Color(0xFF050B18),
                            ),
                            Positioned(
                              bottom: 18,
                              right: 18,
                              child: Container(
                                padding: const EdgeInsets.all(AppSpacing.xs),
                                decoration: const BoxDecoration(
                                  color: AppTheme.accentColor,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.star,
                                  size: 16,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                      .animate()
                      .scale(duration: 1000.ms, curve: Curves.elasticOut)
                      .shimmer(delay: 500.ms, duration: 1500.ms),

                      const SizedBox(height: AppSpacing.xl),

                      // App Name
                      Text(
                        AppConfig.appName.toUpperCase(),
                        style: GoogleFonts.spaceGrotesk(
                          fontWeight: FontWeight.bold,
                          fontSize: 36,
                          letterSpacing: 3.0,
                          color: Colors.white,
                          shadows: [
                            Shadow(
                              color: AppTheme.primaryColor.withValues(alpha: 0.5),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                      )
                      .animate()
                      .slideY(begin: 0.3, duration: 800.ms, curve: Curves.easeOut)
                      .fadeIn(duration: 800.ms),

                      const SizedBox(height: 12),

                      // Tagline
                      Text(
                        'NEXT-GEN CARD INTELLIGENCE',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 2.0,
                          color: AppTheme.primaryColor,
                        ),
                      )
                      .animate()
                      .slideY(begin: 0.3, duration: 800.ms, delay: 200.ms, curve: Curves.easeOut)
                      .fadeIn(duration: 800.ms, delay: 200.ms),
                    ],
                  ),
                ),
              ),
              
              // Status & progress loader
              Expanded(
                flex: 1,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Linear Cyber Progress Bar
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Stack(
                          children: [
                            Container(
                              height: 6,
                              width: double.infinity,
                              color: const Color(0xFF0F172A),
                            ),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              height: 6,
                              width: MediaQuery.of(context).size.width * 0.8 * _progressValue,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    AppTheme.primaryColor,
                                    AppTheme.secondaryColor,
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: AppTheme.neonGlow(color: AppTheme.primaryColor, opacity: 0.5, blurRadius: 8),
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: AppSpacing.lg),

                      // Status text
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: Text(
                          _currentStatus,
                          key: ValueKey(_currentStatus),
                          style: AppTextStyles.body2.copyWith(
                            color: Colors.white70,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),

                      if (_dashboardReady) ...[
                        const SizedBox(height: 12),
                        Text(
                          'CONNECTION SECURED',
                          style: GoogleFonts.spaceGrotesk(
                            color: AppTheme.successColor,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        )
                        .animate()
                        .scale(duration: 400.ms, curve: Curves.elasticOut)
                        .fadeIn(duration: 300.ms),
                      ],

                      if (_showTimeoutFallback && !_dashboardReady) ...[
                        const SizedBox(height: AppSpacing.lg),
                        Text(
                          'This is taking longer than expected.',
                          style: AppTextStyles.caption.copyWith(
                            color: Colors.white54,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        TextButton(
                          onPressed: () {
                            _timeoutTimer?.cancel();
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(
                                builder: (context) => const HomeScreen(),
                              ),
                            );
                          },
                          child: Text(
                            'Continue anyway',
                            style: AppTextStyles.body2.copyWith(
                              color: AppTheme.primaryColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  // The auth check below is bounded by _authCheckTimeout; the fixed status
  // delays (800+600+400+500ms) add a small, known amount on top. The
  // fallback Timer's duration is derived from these instead of being an
  // independent guess, so the two can't silently drift out of sync if
  // either changes.
  static const _authCheckTimeout = Duration(seconds: 8);
  static const _fixedDelaysBudget = Duration(milliseconds: 800 + 600 + 400 + 500);
  static const _fallbackHeadroom = Duration(seconds: 2);
  static final _fallbackTimeout = _authCheckTimeout + _fixedDelaysBudget + _fallbackHeadroom;

  String _currentStatus = 'INITIALIZING SYSTEM...';
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
        setState(() {
          _showTimeoutFallback = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    super.dispose();
  }

  Future<void> _initializeApp() async {
    // Check if the app was launched with an admin route deep link
    final initialRoute = WidgetsBinding.instance.platformDispatcher.defaultRouteName.toLowerCase();
    if (initialRoute.contains('/admin/')) {
      print('🚪 SplashScreen: Admin initial route detected ($initialRoute). Skipping home redirect.');
      _isAdminDeepLink = true;
      return;
    }

    await _updateStatus('STARTING HYPERDRIVE...');
    await Future.delayed(const Duration(milliseconds: 800));
    
    await _updateStatus('CONNECTING TO QUANTUM LEDGER...');
    await Future.delayed(const Duration(milliseconds: 600));
    
    if (mounted) {
      await _updateStatus('AUTHENTICATING IDENTITY...');

      // Wait for auth check with a hard safety timeout
      try {
        await ref.read(authStateProvider.notifier).refreshAuthState()
            .timeout(_authCheckTimeout, onTimeout: () {
          print('⚠️ SplashScreen: Auth check timed out after ${_authCheckTimeout.inSeconds}s, proceeding to login');
        });
      } catch (e) {
        print('⚠️ SplashScreen: Auth error: $e, proceeding to login');
      }
      
      await Future.delayed(const Duration(milliseconds: 400));
      
      if (mounted) {
        final authState = ref.read(authStateProvider);
        
        if (authState.isAuthenticated) {
          await _updateStatus('LOADING PORTFOLIO...');
          await Future.delayed(const Duration(milliseconds: 500));

          _navigated = true;
          _timeoutTimer?.cancel();
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => DashboardLoadingWrapper(
                onDashboardReady: () async {
                  await _updateStatus('WELCOME BACK');
                },
              ),
            ),
          );
        } else {
          // Any non-authenticated state (unauthenticated, error, loading) → go to login
          await _updateStatus('SIGN IN REQUIRED');
          await Future.delayed(const Duration(milliseconds: 300));

          _navigated = true;
          _timeoutTimer?.cancel();
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => const LoginScreen(),
            ),
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
      MaterialPageRoute(
        builder: (context) => const LoginScreen(),
      ),
    );
  }

  Future<void> _updateStatus(String status) async {
    if (mounted) {
      setState(() {
        _currentStatus = status;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF050B18),
              const Color(0xFF0C152B),
              AppTheme.secondaryColor.withValues(alpha: 0.15),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Top section with logo and branding
              Expanded(
                flex: 3,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // App Logo with enhanced cyber design
                      Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              AppTheme.primaryColor,
                              AppTheme.secondaryColor,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: AppTheme.neonGlow(color: AppTheme.primaryColor, opacity: 0.4),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.2),
                            width: 1.5,
                          ),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            const Icon(
                              Icons.credit_card,
                              size: 70,
                              color: Color(0xFF050B18),
                            ),
                            Positioned(
                              bottom: 18,
                              right: 18,
                              child: Container(
                                padding: const EdgeInsets.all(AppSpacing.xs),
                                decoration: const BoxDecoration(
                                  color: AppTheme.accentColor,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.star,
                                  size: 16,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                      .animate()
                      .scale(duration: 1000.ms, curve: Curves.elasticOut)
                      .shimmer(delay: 500.ms, duration: 1500.ms),

                      const SizedBox(height: AppSpacing.xl),

                      // App Name
                      Text(
                        AppConfig.appName.toUpperCase(),
                        style: GoogleFonts.spaceGrotesk(
                          fontWeight: FontWeight.bold,
                          fontSize: 36,
                          letterSpacing: 3.0,
                          color: Colors.white,
                          shadows: [
                            Shadow(
                              color: AppTheme.primaryColor.withValues(alpha: 0.5),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                      )
                      .animate()
                      .fadeIn(delay: 500.ms, duration: 800.ms)
                      .slideY(begin: 0.3, end: 0),
                      
                      const SizedBox(height: 12),
                      
                      // Tagline
                      Text(
                        'YOUR FUTURISTIC REWARDS ADVISOR',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 2.0,
                          color: AppTheme.primaryColor,
                        ),
                      )
                      .animate()
                      .fadeIn(delay: 700.ms, duration: 800.ms)
                      .slideY(begin: 0.3, end: 0),
                      
                      const SizedBox(height: AppSpacing.lg),

                      // Cyber Chips
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildFeatureChip(context, 'INTELLIGENT TRACK', Icons.analytics),
                          const SizedBox(width: AppSpacing.sm),
                          _buildFeatureChip(context, 'NEON OPTIMIZE', Icons.trending_up),
                        ],
                      )
                      .animate()
                      .fadeIn(delay: 900.ms, duration: 600.ms)
                      .slideY(begin: 0.2, end: 0),
                    ],
                  ),
                ),
              ),
              
              // Bottom section with loading progress
              Expanded(
                flex: 1,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Glowing cyber dot scanner
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0C152B),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppTheme.primaryColor.withValues(alpha: 0.3),
                          width: 1.5,
                        ),
                        boxShadow: AppTheme.neonGlow(color: AppTheme.primaryColor, opacity: 0.2, blurRadius: 10),
                      ),
                      child: const Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
                          ),
                        ),
                      ),
                    )
                    .animate()
                    .fadeIn(delay: 1100.ms, duration: 600.ms)
                    .scale(delay: 1100.ms, duration: 600.ms),
                    
                    const SizedBox(height: 20),
                    
                    // Dynamic status text
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Text(
                        _currentStatus,
                        key: ValueKey(_currentStatus),
                        style: GoogleFonts.spaceGrotesk(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          letterSpacing: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    )
                    .animate()
                    .fadeIn(delay: 1300.ms, duration: 600.ms),

                    if (_showTimeoutFallback && !_navigated) ...[
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'This is taking longer than expected.',
                        style: AppTextStyles.caption.copyWith(
                          color: Colors.white54,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      TextButton(
                        onPressed: _continueToLogin,
                        child: Text(
                          'Continue to Login',
                          style: AppTextStyles.body2.copyWith(
                            color: AppTheme.primaryColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Bottom branding
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                child: Text(
                  'POWERED BY AI • CARDCOMPASS CORE v2026',
                  style: GoogleFonts.spaceGrotesk(
                    color: Colors.white30,
                    fontSize: 9,
                    letterSpacing: 1.5,
                  ),
                ),
              )
              .animate()
              .fadeIn(delay: 1500.ms, duration: 800.ms),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureChip(BuildContext context, String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppBorderRadius.lg),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 13,
            color: AppTheme.primaryColor,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.spaceGrotesk(
              color: AppTheme.primaryColor,
              fontWeight: FontWeight.bold,
              fontSize: 10,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
