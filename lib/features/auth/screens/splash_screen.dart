import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/theme/brand_components.dart';
import '../../../core/theme/brand_tokens.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
            Text(
              'Every Swipe, Optimised.',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 14,
                color: BrandColors.mutedPaper,
              ),
            ).animate(delay: 400.ms).fadeIn(duration: 400.ms),
            const SizedBox(height: BrandSpacing.xxl),
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
    );
  }
}
