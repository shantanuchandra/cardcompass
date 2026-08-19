import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/brand_components.dart';
import '../../../core/theme/brand_tokens.dart';
import '../providers/auth_provider.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key, this.onRetry, this.onBackToSignIn});

  final VoidCallback? onRetry;
  final VoidCallback? onBackToSignIn;

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  static const _timeout = Duration(seconds: 8);
  Timer? _timeoutTimer;
  bool _timedOut = false;

  @override
  void initState() {
    super.initState();
    _startTimeout();
  }

  void _startTimeout() {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(_timeout, () {
      if (mounted) setState(() => _timedOut = true);
    });
  }

  void _retry() {
    if (widget.onRetry case final callback?) {
      callback();
    } else {
      ref.invalidate(authNotifierProvider);
    }
    setState(() => _timedOut = false);
    _startTimeout();
  }

  void _backToSignIn() {
    if (widget.onBackToSignIn case final callback?) {
      callback();
      return;
    }
    context.go('/app/login');
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.marketing,
      child: Scaffold(
        backgroundColor: BrandColors.ink,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BrandCompassMark(size: 72)
                  .animate()
                  .fadeIn(duration: 600.ms)
                  .scaleXY(
                    begin: 0.9,
                    duration: 600.ms,
                    curve: Curves.easeOutCubic,
                  ),
              const SizedBox(height: BrandSpacing.md),
              Text(
                    'CardCompass',
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: BrandColors.paper,
                      letterSpacing: -0.5,
                    ),
                  )
                  .animate(delay: 200.ms)
                  .fadeIn(duration: 400.ms)
                  .slideY(begin: 0.2, duration: 400.ms),
              const SizedBox(height: BrandSpacing.sm),
              const Text(
                'Securing your session',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 14,
                  color: BrandColors.mutedPaper,
                ),
              ).animate(delay: 400.ms).fadeIn(duration: 400.ms),
              const SizedBox(height: BrandSpacing.xs),
              const Text(
                'Loading your wallet',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 14,
                  color: BrandColors.mutedPaper,
                ),
              ).animate(delay: 520.ms).fadeIn(duration: 400.ms),
              const SizedBox(height: BrandSpacing.xl),
              if (_timedOut)
                Wrap(
                  spacing: BrandSpacing.sm,
                  children: [
                    OutlinedButton(
                      onPressed: _retry,
                      child: const Text('Retry'),
                    ),
                    TextButton(
                      onPressed: _backToSignIn,
                      child: const Text('Back to sign in'),
                    ),
                  ],
                )
              else
                SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: BrandColors.signal.withValues(alpha: 0.6),
                  ),
                ).animate(delay: 600.ms).fadeIn(duration: 300.ms),
            ],
          ),
        ),
      ),
    );
  }
}
