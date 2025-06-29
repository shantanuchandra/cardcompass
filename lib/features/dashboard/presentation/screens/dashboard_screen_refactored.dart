import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cardcompass/features/auth/providers/auth_provider.dart';
import 'package:cardcompass/features/dashboard/viewmodels/dashboard_viewmodel.dart';
import 'package:cardcompass/features/dashboard/widgets/dashboard_quick_actions.dart';
import 'package:cardcompass/features/dashboard/widgets/dashboard_summary_cards.dart';
import 'package:cardcompass/features/dashboard/widgets/ai_insights_section.dart';
import 'package:cardcompass/features/dashboard/widgets/smart_transaction_analyzer.dart';
import 'package:cardcompass/features/dashboard/services/dashboard_operations_service.dart';
import 'package:cardcompass/features/dashboard/utils/dashboard_dialogs.dart';
import 'package:cardcompass/features/notifications/viewmodels/notifications_viewmodel.dart';
import 'package:cardcompass/shared/widgets/state_widgets.dart';
import 'package:cardcompass/config/routes.dart';

/// Refactored, clean dashboard screen with separated concerns
class DashboardScreenRefactored extends ConsumerStatefulWidget {
  const DashboardScreenRefactored({super.key});

  @override
  ConsumerState<DashboardScreenRefactored> createState() => _DashboardScreenRefactoredState();
}

class _DashboardScreenRefactoredState extends ConsumerState<DashboardScreenRefactored> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadDashboardData();
    });
  }

  /// Load dashboard data
  void _loadDashboardData() {
    final user = ref.read(authStateProvider).user;
    if (user != null) {
      ref.read(dashboardViewModelProvider.notifier).loadDashboardData(user.id);
      // Also load notifications for the badge
      try {
        ref.read(notificationsViewModelProvider.notifier).loadNotifications(user.id);
      } catch (e) {
        // Ignore notification loading errors - not critical for dashboard
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final dashboardState = ref.watch(dashboardViewModelProvider);
    final dashboardViewModel = ref.read(dashboardViewModelProvider.notifier);

    return Scaffold(
      appBar: _buildAppBar(context),
      body: RefreshIndicator(
        onRefresh: () async {
          if (authState.user != null) {
            await dashboardViewModel.refreshData(authState.user!.id);
          }
        },
        child: dashboardState.isLoading
            ? _buildSplashStyleLoading()
            : dashboardState.error != null
                ? ErrorState(
                    error: dashboardState.error!,
                    onRetry: _loadDashboardData,
                  )
                : _buildDashboardContent(context, dashboardState, dashboardViewModel, authState),
      ),
      bottomNavigationBar: _buildBottomNavigationBar(context),
    );
  }

  /// Build app bar with consistent styling
  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      title: const Text('CardCompass'),
      elevation: 0,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      foregroundColor: Theme.of(context).textTheme.titleLarge?.color,
      actions: [
        IconButton(
          onPressed: () => Navigator.of(context).pushNamed(AppRoutes.benefits),
          icon: const Icon(Icons.card_giftcard),
          tooltip: 'Benefits',
        ),
        _buildNotificationIcon(),
        IconButton(
          onPressed: () => Navigator.of(context).pushNamed(AppRoutes.profile),
          icon: const Icon(Icons.person_outline),
          tooltip: 'Profile',
        ),
      ],
    );
  }

  /// Build notification icon with badge
  Widget _buildNotificationIcon() {
    return Stack(
      children: [
        IconButton(
          onPressed: () => Navigator.of(context).pushNamed(AppRoutes.notifications),
          icon: const Icon(Icons.notifications_outlined),
          tooltip: 'Notifications',
        ),
        Positioned(
          right: 8,
          top: 8,
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(6),
            ),
            constraints: const BoxConstraints(minWidth: 12, minHeight: 12),
            child: const Text(
              '•',
              style: TextStyle(color: Colors.white, fontSize: 8),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }

  /// Build main dashboard content with extracted widgets
  Widget _buildDashboardContent(
    BuildContext context,
    DashboardViewState state,
    DashboardViewModel viewModel,
    AuthState authState,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Welcome section (would need to be updated to work without provider)
          // DashboardWelcomeSection(),
          _buildWelcomeSection(context, state),
          
          const SizedBox(height: 24),
          
          // Quick actions with callbacks
          DashboardQuickActions(
            onSyncPressed: () => _handleSyncData(context),
            onDeletePressed: () => _handleDeleteData(context),
            onAIBenefitsPressed: () => _handleAIBenefits(context),
          ),
          
          const SizedBox(height: 24),
          
          // Summary cards
          DashboardSummaryCards(state: state, viewModel: viewModel),
          
          const SizedBox(height: 24),
          
          // AI Insights Section
          AiInsightsSection(
            insights: state.aiInsights,
            optimizations: state.spendingOptimizations,
            cardRecommendations: state.aiCardRecommendations,
            isLoading: state.isLoading,
          ),
          
          const SizedBox(height: 24),
          
          // Spending Insights Section
          _buildSpendingInsights(context, state, viewModel),
          
          const SizedBox(height: 24),
          
          // Smart Transaction Analyzer
          SmartTransactionAnalyzer(userId: authState.user?.id),
          
          const SizedBox(height: 24),
          
          // Recent transactions section
          _buildRecentSection(context, state),
        ],
      ),
    );
  }

  /// Temporary welcome section (should be replaced with extracted widget)
  Widget _buildWelcomeSection(BuildContext context, DashboardViewState state) {
    final user = ref.read(authStateProvider).user;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.blue.withValues(alpha: 0.1),
            Colors.blue.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        'Welcome back, ${user?.name ?? 'User'}!',
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  /// Handle sync data operation
  Future<void> _handleSyncData(BuildContext context) async {
    final authState = ref.read(authStateProvider);
    if (!authState.isAuthenticated || authState.user == null) {
      _showSnackBar(context, 'Please log in first', Colors.red);
      return;
    }

    final config = await DashboardDialogs.showSyncDialog(context);
    if (config == null) return;

    try {
      final success = await DashboardOperationsService.syncDataFromGmail(
        userId: authState.user!.id,
        numberOfEmails: config['numberOfEmails'],
        startDate: config['startDate'],
        context: context,
      );

      if (success && mounted) {
        _showSnackBar(context, 'Data sync completed!', Colors.green);
        _refreshDashboard();
      }
    } catch (error) {
      if (mounted) {
        _showSnackBar(context, 'Sync failed: ${error.toString()}', Colors.red);
      }
    }
  }

  /// Handle delete data operation
  Future<void> _handleDeleteData(BuildContext context) async {
    final authState = ref.read(authStateProvider);
    if (!authState.isAuthenticated || authState.user == null) {
      _showSnackBar(context, 'Please log in first', Colors.red);
      return;
    }

    try {
      // Show loading dialog while fetching counts
      DashboardDialogs.showLoadingDialog(context, 'Loading data counts...');
      
      final counts = await DashboardOperationsService.getUserDataCounts(authState.user!.id);
      
      // Close loading dialog
      if (mounted) Navigator.of(context).pop();
      
      // Show confirmation dialog
      final confirmed = await DashboardDialogs.showDeleteConfirmationDialog(context, counts);
      if (confirmed != true) return;

      final success = await DashboardOperationsService.deleteAllUserData(
        userId: authState.user!.id,
        context: context,
      );

      if (success && mounted) {
        _showSnackBar(context, 'All data deleted successfully!', Colors.green);
        _refreshDashboard();
      }
    } catch (error) {
      if (mounted) {
        Navigator.of(context).pop(); // Close any open dialogs
        _showSnackBar(context, 'Delete failed: ${error.toString()}', Colors.red);
      }
    }
  }

  /// Handle AI benefits extraction
  Future<void> _handleAIBenefits(BuildContext context) async {
    final authState = ref.read(authStateProvider);
    if (!authState.isAuthenticated || authState.user == null) {
      _showSnackBar(context, 'Please log in first', Colors.red);
      return;
    }

    try {
      final results = await DashboardOperationsService.extractBenefitsWithAI(
        userId: authState.user!.id,
        context: context,
      );

      if (mounted) {
        final success = results['success'] ?? false;
        DashboardDialogs.showResultsDialog(
          context,
          title: 'AI Benefits Extraction',
          message: success 
            ? 'Benefits extraction completed successfully!'
            : 'Benefits extraction completed with some issues.',
          success: success,
          actionButtonText: 'View Benefits',
          onActionPressed: () => Navigator.of(context).pushNamed(AppRoutes.benefits),
        );
      }
    } catch (error) {
      if (mounted) {
        _showSnackBar(context, 'AI extraction failed: ${error.toString()}', Colors.red);
      }
    }
  }

  /// Helper method to show snackbar
  void _showSnackBar(BuildContext context, String message, Color backgroundColor) {
    if (mounted && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: backgroundColor),
      );
    }
  }

  /// Helper method to refresh dashboard
  void _refreshDashboard() {
    if (mounted) {
      final user = ref.read(authStateProvider).user;
      if (user != null) {
        ref.read(dashboardViewModelProvider.notifier).loadDashboardData(user.id);
      }
    }
  }

  // ... Rest of the methods would be similar extractions and simplifications
  // Placeholder for remaining methods
  Widget _buildSpendingInsights(BuildContext context, DashboardViewState state, DashboardViewModel viewModel) {
    return const Placeholder(child: Text('Spending Insights - Extract to separate widget'));
  }

  Widget _buildRecentSection(BuildContext context, DashboardViewState state) {
    return const Placeholder(child: Text('Recent Section - Extract to separate widget'));
  }

  Widget _buildBottomNavigationBar(BuildContext context) {
    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      currentIndex: 0,
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Dashboard'),
        BottomNavigationBarItem(icon: Icon(Icons.credit_card), label: 'Cards'),
        BottomNavigationBarItem(icon: Icon(Icons.analytics), label: 'Analytics'),
        BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
      ],
      onTap: (index) {
        switch (index) {
          case 1: Navigator.of(context).pushNamed(AppRoutes.cards); break;
          case 2: Navigator.of(context).pushNamed(AppRoutes.analytics); break;
          case 3: Navigator.of(context).pushNamed(AppRoutes.profile); break;
        }
      },
    );
  }

  Widget _buildSplashStyleLoading() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
            Theme.of(context).colorScheme.surface,
          ],
        ),
      ),
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Setting up your dashboard...'),
          ],
        ),
      ),
    );
  }
}
