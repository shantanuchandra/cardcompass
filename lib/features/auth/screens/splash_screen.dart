import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceVoid,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Logo mark
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                gradient: AppTheme.cyanGradient,
                borderRadius: BorderRadius.circular(AppRadius.xl),
                boxShadow: AppTheme.neonGlow(),
              ),
              child: const Icon(Icons.explore, color: AppColors.textInverse, size: 36),
            )
                .animate()
                .fadeIn(duration: 600.ms)
                .scaleXY(begin: 0.8, duration: 600.ms, curve: Curves.easeOutBack),
            const SizedBox(height: AppSpacing.md),
            Text(
              'CardCompass',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                letterSpacing: -0.5,
              ),
            )
                .animate(delay: 200.ms)
                .fadeIn(duration: 400.ms)
                .slideY(begin: 0.2, duration: 400.ms),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Every Swipe, Optimised.',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            )
                .animate(delay: 400.ms)
                .fadeIn(duration: 400.ms),
            const SizedBox(height: AppSpacing.xxl),
            SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.neonCyan.withValues(alpha: 0.6),
              ),
            )
                .animate(delay: 600.ms)
                .fadeIn(duration: 300.ms),
          ],
        ),
      ),
    );
  }
}
