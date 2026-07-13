import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme.dart';
import '../../../../shared/widgets/app_scaffold.dart';
import '../../../../shared/widgets/state_widgets.dart';
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
      await Future.wait(<Future<void>>[
        ref.read(cardsProvider.notifier).loadUserCards(authState.user!.id),
        ref.read(transactionsProvider.notifier).loadUserTransactions(authState.user!.id),
      ]);
      _hasLoadedData = true;
    } catch (e) {
      // Handle error silently
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// Pull-to-refresh entry point: forces a fresh reload even if data was
  /// already loaded once, unlike [_loadDataOnce] which is a load-once guard
  /// used on initial screen entry.
  Future<void> _handleRefresh() async {
    _hasLoadedData = false;
    await _loadDataOnce();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final cards = ref.watch(cardsProvider);
    final allTransactions = ref.watch(transactionsProvider);
    final transactions = allTransactions.where((t) => t.amount <= 100000).toList();

    return CardCompassScaffold(
      title: 'Analytics',
      actions: [
        IconButton(
          onPressed: () {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                backgroundColor: const Color(0xFF0C152B),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppBorderRadius.xl),
                  side: const BorderSide(color: Color(0xFF1E293B)),
                ),
                title: Text(
                  'EXPORT INTEL',
                  style: AppTextStyles.heading3.copyWith(color: Colors.white),
                ),
                content: Text(
                  'CSV/PDF ledger download isn\'t available in guest mode.',
                  style: AppTextStyles.body1.copyWith(color: Colors.white70),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('OK', style: GoogleFonts.spaceGrotesk(color: AppTheme.primaryColor, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            );
          },
          icon: const Icon(Icons.file_download, color: AppTheme.primaryColor),
        ),
      ],
      body: RefreshIndicator(
        onRefresh: _handleRefresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, 12, AppSpacing.md, 100), // padding for floating dock
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Section
              Text(
                'Financial Intelligence',
                style: AppTextStyles.heading2.copyWith(color: Colors.white),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Real-time deep analysis of reward utilization and billing habits.',
                style: AppTextStyles.body2.copyWith(color: Colors.white60),
              ),
              const SizedBox(height: AppSpacing.lg),

              // Analytics Content
              Builder(
                builder: (context) {
                  if (_isLoading) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 80),
                      child: LoadingState(),
                    );
                  }

                  if (!authState.isAuthenticated || authState.user == null) {
                    return _buildAuthRequiredState(context);
                  }

                  if (cards.isEmpty && transactions.isEmpty) {
                    return _buildEmptyDataState(context);
                  }

                  return FinancialInsightsWidget(
                    userId: authState.user!.id,
                    transactions: transactions,
                    creditCards: cards,
                  );
                },
              ),
            ],
          ).animate().fadeIn(duration: 250.ms, curve: Curves.easeOut).slideY(begin: 0.05, end: 0, duration: 250.ms, curve: Curves.easeOut),
        ),
      ),
    );
  }

  Widget _buildAuthRequiredState(BuildContext context) {
    return const EmptyState(
      icon: Icons.lock_outline,
      title: 'Access Restricted',
      message: 'Please authenticate your session to decrypt and view financial analytics.',
    );
  }

  Widget _buildEmptyDataState(BuildContext context) {
    return const EmptyState(
      icon: Icons.analytics_outlined,
      title: 'No Data Decrypted',
      message: 'Add credit cards and import statements to compile financial intelligence graphs.',
    );
  }
}
