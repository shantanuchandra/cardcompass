import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
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

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final cards = ref.watch(cardsProvider);
    final allTransactions = ref.watch(transactionsProvider);
    final transactions = allTransactions.where((t) => t.amount <= 100000).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF050B18),
      appBar: AppBar(
        title: Text(
          'ANALYTICS',
          style: GoogleFonts.spaceGrotesk(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  backgroundColor: const Color(0xFF0C152B),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: const BorderSide(color: Color(0xFF1E293B)),
                  ),
                  title: Text(
                    'EXPORT INTEL',
                    style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  content: Text(
                    'CSV/PDF ledger download isn\'t available in guest mode.',
                    style: GoogleFonts.plusJakartaSans(color: Colors.white70),
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
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100), // padding for floating dock
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Section
            Text(
              'FINANCIAL INTELLIGENCE',
              style: GoogleFonts.spaceGrotesk(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 22,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Real-time deep analysis of reward utilization and billing habits.',
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white60,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 24),
            
            // Analytics Content
            Builder(
              builder: (context) {
                if (_isLoading) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 80),
                    child: Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation(AppTheme.primaryColor),
                      ),
                    ),
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
        ),
      ),
    );
  }

  Widget _buildAuthRequiredState(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF0C152B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.lock_outline, size: 48, color: AppTheme.accentColor),
          const SizedBox(height: 16),
          Text(
            'ACCESS RESTRICTED',
            style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.0),
          ),
          const SizedBox(height: 8),
          Text(
            'Please authenticate your session to decrypt and view financial analytics.',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyDataState(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF0C152B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.analytics_outlined, size: 48, color: Colors.white24),
          const SizedBox(height: 16),
          Text(
            'NO DATA DECRYPTED',
            style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.0),
          ),
          const SizedBox(height: 8),
          Text(
            'Add credit cards and import statements to compile financial intelligence graphs.',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
