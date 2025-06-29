import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme.dart';
import '../../../../features/dashboard/widgets/financial_insights_widget.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../../cards/providers/cards_provider.dart';
import '../../../transactions/providers/transactions_provider.dart';

class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  bool _isLoading = false;
  bool _hasLoadedData = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadDataOnce();
    });
  }

  Future<void> _loadDataOnce() async {
    if (_hasLoadedData || _isLoading) return;
    
    final authState = ref.read(authStateProvider);
    if (!authState.isAuthenticated || authState.user == null) return;
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      // Load data only once
      await Future.wait([
        ref.read(cardsProvider.notifier).loadUserCards(authState.user!.id),
        ref.read(transactionsProvider.notifier).loadUserTransactions(authState.user!.id),
      ]);
        _hasLoadedData = true;
    } catch (e) {
      // Handle error silently for production
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final cards = ref.watch(cardsProvider);
    final allTransactions = ref.watch(transactionsProvider);    // Filter out suspicious transactions (amounts over ₹1,00,000)
    final transactions = allTransactions.where((t) => t.amount <= 100000).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytics'),
        actions: [
          IconButton(
            onPressed: () {
              // TODO: Export analytics
            },
            icon: const Icon(Icons.file_download),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Section
            Text(
              'Financial Analytics',
              style: AppTextStyles.heading2,
            ),
            const SizedBox(height: 8),
            Text(
              'Comprehensive insights into your spending patterns and financial health',
              style: AppTextStyles.body1.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 24),
              // Analytics Content
            Builder(
              builder: (context) {
                // Show loading indicator
                if (_isLoading) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }
                
                // Check if user is authenticated
                if (!authState.isAuthenticated || authState.user == null) {
                  return _buildAuthRequiredState(context);
                }
                
                // Check if we have data
                if (cards.isEmpty && transactions.isEmpty) {
                  return _buildEmptyDataState(context);
                }
                
                // Show comprehensive analytics with filtered data
                return FinancialInsightsWidget(
                  userId: authState.user!.id,
                  transactions: transactions,
                  creditCards: cards,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
  Widget _buildAuthRequiredState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.login,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            'Login Required',
            style: AppTextStyles.heading3,
          ),
          const SizedBox(height: 8),
          Text(
            'Please log in to view your financial analytics',
            style: AppTextStyles.body1.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyDataState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.analytics,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            'No Data Available',
            style: AppTextStyles.heading3,
          ),
          const SizedBox(height: 8),
          Text(
            'Add some credit cards and transactions to see your analytics',
            style: AppTextStyles.body1.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
