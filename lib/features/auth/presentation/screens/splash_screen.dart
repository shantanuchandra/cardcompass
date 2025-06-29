import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/app_config.dart';
import '../../../dashboard/presentation/screens/dashboard_screen_refactored.dart';
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
  String _currentStatus = 'Loading your dashboard...';
  bool _dashboardReady = false;

  @override
  void initState() {
    super.initState();
    _initializeDashboard();
  }

  Future<void> _initializeDashboard() async {
    try {
      // Get the current user
      final authState = ref.read(authStateProvider);
      if (authState.user != null) {
        await _updateStatus('Loading your cards...');
        await Future.delayed(const Duration(milliseconds: 500));
        
        // Load dashboard data
        await ref.read(dashboardViewModelProvider.notifier).loadDashboardData(authState.user!.id);
        
        await _updateStatus('Setting up your experience...');
        await Future.delayed(const Duration(milliseconds: 700));
        
        await _updateStatus('Almost ready...');
        await Future.delayed(const Duration(milliseconds: 500));
        
        widget.onDashboardReady?.call();
        
        if (mounted) {
          setState(() {
            _dashboardReady = true;
          });
          
          // Small delay to show "Ready!" message
          await Future.delayed(const Duration(milliseconds: 300));
          
          // Replace with actual dashboard
          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) => const DashboardScreenRefactored(),
              ),
            );
          }
        }
      }
    } catch (e) {
      await _updateStatus('Loading dashboard...');
      // Fallback to dashboard even if loading fails
      await Future.delayed(const Duration(milliseconds: 1000));
      
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => const DashboardScreenRefactored(),
          ),
        );
      }
    }
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
              Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
              Theme.of(context).colorScheme.surface,
              Theme.of(context).colorScheme.secondary.withValues(alpha: 0.05),
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
                      // App Logo with enhanced design
                      Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Theme.of(context).colorScheme.primary,
                              Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Icon(
                              Icons.credit_card,
                              size: 70,
                              color: Theme.of(context).colorScheme.onPrimary,
                            ),
                            Positioned(
                              bottom: 20,
                              right: 20,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Colors.green,
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
                      .scale(duration: 1000.ms, curve: Curves.elasticOut),
                      
                      const SizedBox(height: 32),
                      
                      // App Name
                      Text(
                        AppConfig.appName,
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      )
                      .animate()
                      .slideY(begin: 0.3, duration: 800.ms, curve: Curves.easeOut)
                      .fadeIn(duration: 800.ms),
                      
                      const SizedBox(height: 8),
                      
                      // Tagline
                      Text(
                        'Smart Credit Card Management',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                      )
                      .animate()
                      .slideY(begin: 0.3, duration: 800.ms, delay: 200.ms, curve: Curves.easeOut)
                      .fadeIn(duration: 800.ms, delay: 200.ms),
                    ],
                  ),
                ),
              ),
              
              // Status and loading section
              Expanded(
                flex: 1,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Loading indicator
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Theme.of(context).colorScheme.primary,
                        ),
                        strokeWidth: 3,
                      ),
                    )
                    .animate()
                    .scale(duration: 1200.ms, curve: Curves.easeInOut)
                    .then()
                    .shake(duration: 500.ms),
                    
                    const SizedBox(height: 24),
                    
                    // Status text
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Text(
                        _currentStatus,
                        key: ValueKey(_currentStatus),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    
                    if (_dashboardReady) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Ready! 🎉',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.green,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                      .animate()
                      .scale(duration: 400.ms, curve: Curves.elasticOut)
                      .fadeIn(duration: 300.ms),
                    ],
                  ],
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
  String _currentStatus = 'Initializing CardCompass...';
  
  @override
  void initState() {
    super.initState();
    _initializeApp();
  }
  Future<void> _initializeApp() async {
    await _updateStatus('Starting up...');
    await Future.delayed(const Duration(milliseconds: 800));
    
    await _updateStatus('Connecting to services...');
    await Future.delayed(const Duration(milliseconds: 600));
    
    if (mounted) {
      await _updateStatus('Checking authentication...');
      await ref.read(authStateProvider.notifier).refreshAuthState();
      
      await Future.delayed(const Duration(milliseconds: 500));
      
      if (mounted) {
        final authState = ref.read(authStateProvider);
        
        if (authState.isAuthenticated) {
          await _updateStatus('Loading your dashboard...');
          await Future.delayed(const Duration(milliseconds: 500));
          
          // Navigate to dashboard with extended loading
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => DashboardLoadingWrapper(
                onDashboardReady: () async {
                  await _updateStatus('Welcome back!');
                },
              ),
            ),
          );
        } else {
          await _updateStatus('Please sign in');
          await Future.delayed(const Duration(milliseconds: 300));
          
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => const LoginScreen(),
            ),
          );
        }
      }
    }
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
              Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
              Theme.of(context).colorScheme.surface,
              Theme.of(context).colorScheme.secondary.withValues(alpha: 0.05),
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
                      // App Logo with enhanced design
                      Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Theme.of(context).colorScheme.primary,
                              Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Icon(
                              Icons.credit_card,
                              size: 70,
                              color: Theme.of(context).colorScheme.onPrimary,
                            ),
                            Positioned(
                              bottom: 20,
                              right: 20,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Colors.green,
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
                      .shimmer(delay: 500.ms, duration: 1200.ms),
                      
                      const SizedBox(height: 32),
                      
                      // App Name with enhanced typography
                      Text(
                        AppConfig.appName,
                        style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                          fontSize: 32,
                          letterSpacing: -0.5,
                        ),
                      )
                      .animate()
                      .fadeIn(delay: 700.ms, duration: 800.ms)
                      .slideY(begin: 0.3, end: 0),
                      
                      const SizedBox(height: 12),
                      
                      // Enhanced tagline
                      Text(
                        'Your Smart Credit Card Companion',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      )
                      .animate()
                      .fadeIn(delay: 900.ms, duration: 800.ms)
                      .slideY(begin: 0.3, end: 0),
                      
                      const SizedBox(height: 8),
                      
                      // Feature highlights
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildFeatureChip(context, 'Track', Icons.analytics),
                          const SizedBox(width: 8),
                          _buildFeatureChip(context, 'Optimize', Icons.trending_up),
                          const SizedBox(width: 8),
                          _buildFeatureChip(context, 'Rewards', Icons.stars),
                        ],
                      )
                      .animate()
                      .fadeIn(delay: 1100.ms, duration: 600.ms)
                      .slideY(begin: 0.2, end: 0),
                    ],
                  ),
                ),
              ),
              
              // Bottom section with loading and status
              Expanded(
                flex: 1,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Enhanced loading indicator
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Center(
                        child: SizedBox(
                          width: 30,
                          height: 30,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                      ),
                    )
                    .animate()
                    .fadeIn(delay: 1300.ms, duration: 600.ms)
                    .scale(delay: 1300.ms, duration: 600.ms),
                    
                    const SizedBox(height: 24),
                    
                    // Dynamic status text
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Text(
                        _currentStatus,
                        key: ValueKey(_currentStatus),
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    )
                    .animate()
                    .fadeIn(delay: 1500.ms, duration: 600.ms),
                    
                    const SizedBox(height: 12),
                    
                    // Progress dots
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(3, (index) => Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                          shape: BoxShape.circle,
                        ),
                      ))
                      .animate(interval: 200.ms)
                      .fadeIn(delay: 1700.ms)
                      .scale(delay: 1700.ms)
                      .then()
                      .shimmer(duration: 1000.ms, delay: 2000.ms),
                    ),
                  ],
                ),
              ),
              
              // Bottom branding
              Padding(
                padding: const EdgeInsets.only(bottom: 32),
                child: Text(
                  'Powered by AI • Secured by Design',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                    letterSpacing: 0.5,
                  ),
                ),
              )
              .animate()
              .fadeIn(delay: 2000.ms, duration: 800.ms),
            ],
          ),
        ),
      ),
    );
  }

  /// Build feature chip for highlighting app capabilities
  Widget _buildFeatureChip(BuildContext context, String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
