import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/auth_provider.dart';

class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authNotifierProvider);
    final isLoading = auth.isLoading;
    final error = auth.error;

    ref.listen(authNotifierProvider, (_, next) {
      if (next.hasError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sign-in failed: ${next.error}')),
        );
      }
    });

    return Scaffold(
      backgroundColor: AppColors.surfaceVoid,
      body: Stack(
        children: [
          // Background blobs
          _Blobs(),
          // Content
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              child: Column(
                children: [
                  const Spacer(flex: 2),
                  // Logo
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      gradient: AppTheme.cyanGradient,
                      borderRadius: BorderRadius.circular(AppRadius.xl),
                      boxShadow: AppTheme.neonGlow(spread: 12),
                    ),
                    child: const Icon(Icons.explore, color: AppColors.textInverse, size: 40),
                  )
                      .animate()
                      .fadeIn(duration: 700.ms)
                      .scaleXY(begin: 0.7, curve: Curves.easeOutBack),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'CardCompass',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                      letterSpacing: -1,
                    ),
                  )
                      .animate(delay: 150.ms)
                      .fadeIn()
                      .slideY(begin: 0.2),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Every Swipe, Optimised.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      color: AppColors.textSecondary,
                    ),
                  )
                      .animate(delay: 250.ms)
                      .fadeIn()
                      .slideY(begin: 0.15),
                  const SizedBox(height: AppSpacing.lg),
                  // Feature bullets
                  ...[
                    ('183+ Indian credit cards', Icons.credit_card),
                    ('Gemini AI reads your statements', Icons.auto_awesome),
                    ('Best card for every merchant', Icons.star),
                  ].asMap().entries.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(e.value.$2, size: 16, color: AppColors.neonCyan),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          e.value.$1,
                          style: GoogleFonts.inter(fontSize: 14, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  )
                      .animate(delay: Duration(milliseconds: 300 + e.key * 80))
                      .fadeIn()
                      .slideX(begin: -0.1)),
                  const Spacer(flex: 3),
                  // CTA
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: Text(
                        'Something went wrong. Please try again.',
                        style: GoogleFonts.inter(fontSize: 13, color: AppColors.error),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  _GoogleSignInButton(
                    isLoading: isLoading,
                    onPressed: () => ref.read(authNotifierProvider.notifier).signInWithGoogle(),
                  )
                      .animate(delay: 600.ms)
                      .fadeIn()
                      .slideY(begin: 0.3),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'By continuing you agree to our Terms of Service\nand Privacy Policy.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted, height: 1.5),
                  )
                      .animate(delay: 700.ms)
                      .fadeIn(),
                  const SizedBox(height: AppSpacing.xl),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GoogleSignInButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onPressed;

  const _GoogleSignInButton({required this.isLoading, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: OutlinedButton(
        onPressed: isLoading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.neonCyan, width: 1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
          backgroundColor: AppColors.neonCyan.withValues(alpha: 0.05),
        ),
        child: isLoading
            ? const SizedBox(
                width: 22, height: 22,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.neonCyan),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Google G logo colours
                  _GoogleIcon(),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    'Continue with Google',
                    style: GoogleFonts.inter(
                      fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _GoogleIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 20, height: 20,
      child: CustomPaint(painter: _GoogleLogoPainter()),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  const _GoogleLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final c = Offset(r, r);
    // Simple 4-color G approximation using arcs
    const colors = [Color(0xFF4285F4), Color(0xFF34A853), Color(0xFFFBBC05), Color(0xFFEA4335)];
    const sweeps = [90.0, 90.0, 90.0, 90.0];
    const starts = [-180.0, -90.0, 0.0, 90.0];
    for (int i = 0; i < 4; i++) {
      final paint = Paint()
        ..color = colors[i]
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.28;
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r * 0.72),
        starts[i] * (3.14159 / 180),
        sweeps[i] * (3.14159 / 180),
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

class _Blobs extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return SizedBox.expand(
      child: Stack(
        children: [
          Positioned(
            left: -60,
            top: size.height * 0.1,
            child: _blob(AppColors.neonCyan.withValues(alpha: 0.06), 280),
          ),
          Positioned(
            right: -80,
            bottom: size.height * 0.2,
            child: _blob(AppColors.violet.withValues(alpha: 0.07), 320),
          ),
        ],
      ),
    );
  }

  Widget _blob(Color color, double size) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
      child: BackdropFilter(
        filter: ColorFilter.matrix(const <double>[
          1, 0, 0, 0, 0,
          0, 1, 0, 0, 0,
          0, 0, 1, 0, 0,
          0, 0, 0, 1, 0,
        ]),
        child: const SizedBox(),
      ),
    );
  }
}
