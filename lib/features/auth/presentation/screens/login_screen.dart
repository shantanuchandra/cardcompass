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
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              const Spacer(),
              
              // Welcome Section
              Column(
                children: [
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(
                      Icons.credit_card,
                      size: 48,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  )
                  .animate()
                  .scale(duration: 600.ms, curve: Curves.elasticOut),
                  
                  const SizedBox(height: 32),
                  
                  Text(
                    'Welcome to\n${AppConfig.appName}',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.heading1.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  )
                  .animate()
                  .fadeIn(delay: 200.ms, duration: 600.ms)
                  .slideY(begin: 0.3, end: 0),
                  
                  const SizedBox(height: 16),
                  Text(
                    'Maximize your credit card rewards and never miss out on benefits again',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.body1.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  )
                  .animate()
                  .fadeIn(delay: 400.ms, duration: 600.ms)
                  .slideY(begin: 0.3, end: 0),
                ],
              ),
              
              const Spacer(),
              
              // Login Buttons
              Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: authState.isLoading 
                        ? null 
                        : () => ref.read(authStateProvider.notifier).signInWithGoogle(),
                      icon: authState.isLoading 
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Image.asset(
                            'assets/icons/google.png',
                            width: 24,
                            height: 24,
                            errorBuilder: (context, error, stackTrace) => 
                              const Icon(Icons.login, size: 24),
                          ),
                      label: Text(
                        authState.isLoading ? 'Signing In...' : 'Continue with Google',
                        style: AppTextStyles.button,
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Theme.of(context).colorScheme.onPrimary,
                      ),
                    ),
                  )
                  .animate()
                  .fadeIn(delay: 600.ms, duration: 600.ms)
                  .slideY(begin: 0.5, end: 0),
                  
                  const SizedBox(height: 16),
                  
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: OutlinedButton.icon(
                      onPressed: authState.isLoading 
                        ? null 
                        : () => ref.read(authStateProvider.notifier).signInAsGuest(),
                      icon: const Icon(Icons.person_outline),
                      label: Text(
                        'Continue as Guest',
                        style: AppTextStyles.button,
                      ),
                    ),
                  )
                  .animate()
                  .fadeIn(delay: 800.ms, duration: 600.ms)
                  .slideY(begin: 0.5, end: 0),
                ],
              ),
              
              const SizedBox(height: 32),
              
              // Terms and Privacy
              Text(                'By continuing, you agree to our Terms of Service and Privacy Policy',
                textAlign: TextAlign.center,
                style: AppTextStyles.caption.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              )
              .animate()
              .fadeIn(delay: 1000.ms, duration: 600.ms),
              
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
