import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../../core/app_config.dart';
import '../../../../core/theme.dart';
import '../../../cards/presentation/screens/home_screen.dart';
import '../../providers/auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);

    // Listen for auth state changes and navigate accordingly
    ref.listen<AuthState>(authStateProvider, (previous, next) {
      if (next.isAuthenticated) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => const HomeScreen(),
          ),
        );
      } else if (next.hasError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.error ?? 'Authentication failed'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    });

    return Scaffold(
      backgroundColor: const Color(0xFF050B18),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF0C152B),
              const Color(0xFF050B18),
              AppTheme.secondaryColor.withValues(alpha: 0.1),
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 30, vertical: AppSpacing.md),
            child: Column(
              children: [
                const Spacer(),

                // Glowing Glass Card Container for Branding
                Container(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0C152B).withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: AppTheme.primaryColor.withValues(alpha: 0.25),
                      width: 1.5,
                    ),
                    boxShadow: AppTheme.neonGlow(
                        color: AppTheme.primaryColor,
                        opacity: 0.15,
                        blurRadius: 20),
                  ),
                  child: Column(
                    children: [
                      // App Logo (Glowing Credit Card)
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              AppTheme.primaryColor,
                              AppTheme.secondaryColor
                            ],
                          ),
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: AppTheme.neonGlow(
                              color: AppTheme.primaryColor,
                              opacity: 0.3,
                              blurRadius: 10),
                        ),
                        child: const Icon(
                          Icons.credit_card,
                          size: 40,
                          color: Color(0xFF050B18),
                        ),
                      )
                          .animate()
                          .scale(duration: 600.ms, curve: Curves.elasticOut),

                      const SizedBox(height: AppSpacing.lg),

                      Text(
                        AppConfig.appName.toUpperCase(),
                        textAlign: TextAlign.center,
                        style: AppTextStyles.heading1.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2.0,
                          color: Colors.white,
                        ),
                      )
                          .animate()
                          .fadeIn(delay: 200.ms, duration: 600.ms)
                          .slideY(begin: 0.2, end: 0),

                      const SizedBox(height: 12),

                      Text(
                        'Maximize your rewards. Hyper-optimize your card choices in real-time.',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.body2.copyWith(
                          color: Colors.white70,
                          height: 1.5,
                        ),
                      )
                          .animate()
                          .fadeIn(delay: 400.ms, duration: 600.ms)
                          .slideY(begin: 0.2, end: 0),
                    ],
                  ),
                ),

                const Spacer(),

                // Login Buttons
                Column(
                  children: [
                    // Google sign-in with Neon Cyber style
                    Container(
                      width: double.infinity,
                      height: 56,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: AppTheme.neonGlow(
                            color: AppTheme.primaryColor,
                            opacity: 0.1,
                            blurRadius: 10),
                      ),
                      child: ElevatedButton.icon(
                        onPressed: authState.isLoading
                            ? null
                            : () => ref
                                .read(authStateProvider.notifier)
                                .signInWithGoogle(),
                        icon: authState.isLoading
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: const CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor:
                                      AlwaysStoppedAnimation(Color(0xFF050B18)),
                                ),
                              )
                            : Image.asset(
                                'assets/icons/google.png',
                                width: 24,
                                height: 24,
                                errorBuilder: (context, error, stackTrace) =>
                                    const Icon(Icons.login, size: 24),
                              ),
                        label: Text(
                          authState.isLoading
                              ? 'AUTHENTICATING...'
                              : 'SIGN IN WITH GOOGLE',
                          style: AppTextStyles.button.copyWith(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          foregroundColor: const Color(0xFF050B18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    )
                        .animate()
                        .fadeIn(delay: 600.ms, duration: 600.ms)
                        .slideY(begin: 0.3, end: 0),

                    const SizedBox(height: AppSpacing.md),

                    // Continue as Guest (Neon Outlined style)
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: OutlinedButton.icon(
                        onPressed: authState.isLoading
                            ? null
                            : () => ref
                                .read(authStateProvider.notifier)
                                .signInAsGuest(),
                        icon: const Icon(Icons.person_outline,
                            color: AppTheme.secondaryColor),
                        label: Text(
                          'CONTINUE AS GUEST',
                          style: AppTextStyles.button.copyWith(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                            color: Colors.white,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(
                              color: AppTheme.secondaryColor, width: 1.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    )
                        .animate()
                        .fadeIn(delay: 800.ms, duration: 600.ms)
                        .slideY(begin: 0.3, end: 0),
                  ],
                ),

                const SizedBox(height: AppSpacing.xl),

                // Terms and Privacy
                Text(
                  'By continuing, you agree to our Terms of Service and Privacy Policy.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.caption.copyWith(
                    fontSize: 11,
                    color: Colors.white30,
                    letterSpacing: 0.2,
                  ),
                ).animate().fadeIn(delay: 1000.ms, duration: 600.ms),

                const SizedBox(height: 10),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
