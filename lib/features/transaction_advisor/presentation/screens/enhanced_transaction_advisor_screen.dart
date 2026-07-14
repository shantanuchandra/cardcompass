import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cardcompass/features/auth/providers/auth_provider.dart';
import 'package:cardcompass/core/services/advanced_benefit_calculation_service.dart';
import 'package:cardcompass/shared/widgets/state_widgets.dart';
import 'package:cardcompass/shared/widgets/app_scaffold.dart';
import 'package:cardcompass/features/movie_rule_engine/presentation/movie_analyzer_tab.dart';
import 'package:intl/intl.dart';
import 'package:cardcompass/core/theme.dart';

/// Enhanced transaction advisor with advanced benefit calculations in tech-neon style
class EnhancedTransactionAdvisorScreen extends ConsumerStatefulWidget {
  final int initialTabIndex;

  const EnhancedTransactionAdvisorScreen({super.key, this.initialTabIndex = 0});

  @override
  ConsumerState<EnhancedTransactionAdvisorScreen> createState() =>
      _EnhancedTransactionAdvisorScreenState();
}

class _EnhancedTransactionAdvisorScreenState
    extends ConsumerState<EnhancedTransactionAdvisorScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  final AdvancedBenefitCalculationService _benefitService =
      AdvancedBenefitCalculationService();

  final _amountController = TextEditingController();
  final _merchantController = TextEditingController();

  String _selectedCategory = 'dining';
  bool _isCalculating = false;
  Map<String, dynamic>? _recommendation;
  List<Map<String, dynamic>> _optimizations = [];
  Map<String, dynamic>? _rewardSummary;
  List<Map<String, dynamic>> _personalizedRecommendations = [];
  bool _isLoadingOptimizations = false;
  bool _isLoadingSummary = false;
  bool _isLoadingRecommendations = false;

  final List<String> _categories = [
    'dining',
    'fuel',
    'groceries',
    'shopping',
    'travel',
    'utilities',
    'entertainment',
    'healthcare',
    'education',
    'other',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 5,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInitialData();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _amountController.dispose();
    _merchantController.dispose();
    super.dispose();
  }

  void _loadInitialData() {
    _loadOptimizations();
    _loadRewardSummary();
    _loadPersonalizedRecommendations();
  }

  Future<void> _calculateBestCard() async {
    if (_amountController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('Please enter an amount.', style: AppTextStyles.caption),
          backgroundColor: AppTheme.errorColor,
        ),
      );
      return;
    }

    final user = ref.read(authStateProvider).user;
    if (user == null) return;

    setState(() {
      _isCalculating = true;
      _recommendation = null;
    });

    try {
      final amount = double.parse(_amountController.text);
      final merchant = _merchantController.text.trim();

      final result = await _benefitService.calculateBestCard(
        userId: user.id,
        amount: amount,
        merchantName: merchant.isEmpty ? 'General Merchant' : merchant,
        category: _selectedCategory,
      );

      setState(() {
        _recommendation = result;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Error calculating: $e', style: AppTextStyles.caption),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } finally {
      setState(() {
        _isCalculating = false;
      });
    }
  }

  Future<void> _loadOptimizations() async {
    final user = ref.read(authStateProvider).user;
    if (user == null) return;

    setState(() {
      _isLoadingOptimizations = true;
    });

    try {
      final optimizations =
          await _benefitService.getSpendingOptimizations(user.id);
      setState(() {
        _optimizations = optimizations;
      });
    } catch (e) {
      print('Error loading optimizations: $e');
    } finally {
      setState(() {
        _isLoadingOptimizations = false;
      });
    }
  }

  Future<void> _loadRewardSummary() async {
    final user = ref.read(authStateProvider).user;
    if (user == null) return;

    setState(() {
      _isLoadingSummary = true;
    });

    try {
      final summary = await _benefitService.getMonthlyRewardSummary(user.id);
      setState(() {
        _rewardSummary = summary;
      });
    } catch (e) {
      print('Error loading reward summary: $e');
    } finally {
      setState(() {
        _isLoadingSummary = false;
      });
    }
  }

  Future<void> _loadPersonalizedRecommendations() async {
    final user = ref.read(authStateProvider).user;
    if (user == null) return;

    setState(() {
      _isLoadingRecommendations = true;
    });

    try {
      final recommendations =
          await _benefitService.getPersonalizedCardRecommendations(user.id);
      setState(() {
        _personalizedRecommendations = recommendations;
      });
    } catch (e) {
      print('Error loading personalized recommendations: $e');
    } finally {
      setState(() {
        _isLoadingRecommendations = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return CardCompassScaffold(
      title: 'Smart Card Advisor',
      bottom: TabBar(
        controller: _tabController,
        labelColor: AppTheme.primaryColor,
        unselectedLabelColor: Colors.white38,
        indicatorColor: AppTheme.primaryColor,
        indicatorSize: TabBarIndicatorSize.tab,
        isScrollable: true,
        labelStyle: GoogleFonts.spaceGrotesk(
          fontWeight: FontWeight.bold,
          fontSize: 10,
          letterSpacing: 0.5,
        ),
        tabs: const [
          Tab(
              icon: Icon(Icons.calculate_outlined, size: 18),
              text: 'CALCULATE'),
          Tab(
              icon: Icon(Icons.local_movies_outlined, size: 18),
              text: 'MOVIE DEALS'),
          Tab(icon: Icon(Icons.trending_up, size: 18), text: 'OPTIMIZE'),
          Tab(icon: Icon(Icons.analytics_outlined, size: 18), text: 'SUMMARY'),
          Tab(
              icon: Icon(Icons.recommend_outlined, size: 18),
              text: 'SUGGESTIONS'),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildCalculatorTab(),
          _buildMovieAnalyzerTab(),
          _buildOptimizationsTab(),
          _buildSummaryTab(),
          _buildRecommendationsTab(),
        ],
      ),
    );
  }

  Widget _buildCalculatorTab() {
    return SingleChildScrollView(
      padding:
          const EdgeInsets.symmetric(horizontal: 18, vertical: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF0C152B),
              borderRadius: BorderRadius.circular(AppBorderRadius.xl),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TRANSACTION DATA INPUT',
                  style: GoogleFonts.spaceGrotesk(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontSize: 11,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _amountController,
                  style: AppTextStyles.body1.copyWith(color: Colors.white),
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Amount (₹)',
                    prefixIcon: Icon(Icons.currency_rupee,
                        color: AppTheme.primaryColor),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _merchantController,
                  style: AppTextStyles.body1.copyWith(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Merchant Name (Optional)',
                    prefixIcon: Icon(Icons.store_outlined,
                        color: AppTheme.primaryColor),
                    hintText: 'e.g., Amazon, Swiggy, BPCL',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<String>(
                  dropdownColor: const Color(0xFF0C152B),
                  initialValue: _selectedCategory,
                  decoration: const InputDecoration(
                    labelText: 'Spend Category',
                    prefixIcon: Icon(Icons.category_outlined,
                        color: AppTheme.primaryColor),
                  ),
                  items: _categories.map((category) {
                    return DropdownMenuItem(
                      value: category,
                      child: Text(
                        category.toUpperCase(),
                        style: GoogleFonts.spaceGrotesk(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold),
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedCategory = value!;
                    });
                  },
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isCalculating ? null : _calculateBestCard,
                    icon: _isCalculating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation(Colors.black)),
                          )
                        : const Icon(Icons.bolt, color: Colors.black, size: 16),
                    label: Text(
                      _isCalculating ? 'EVALUATING ROUTE...' : 'FIND BEST CARD',
                      style: GoogleFonts.spaceGrotesk(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: Colors.black,
                          letterSpacing: 0.5),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      disabledBackgroundColor: Colors.white10,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppBorderRadius.lg)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_recommendation != null) ...[
            const SizedBox(height: AppSpacing.lg),
            _buildRecommendationResult(),
          ],
          const SizedBox(height: 80),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 250.ms, curve: Curves.easeOut)
        .slideY(begin: 0.05, end: 0, duration: 250.ms, curve: Curves.easeOut);
  }

  Widget _buildRecommendationResult() {
    final bestCard = _recommendation!['bestCard'];
    final recommendations =
        _recommendation!['recommendations'] as List<dynamic>;

    if (bestCard == null) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF0C152B),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Column(
          children: [
            const Icon(Icons.info_outline, size: 40, color: Colors.white24),
            const SizedBox(height: 12),
            Text(
              'NO ACTIVE MATCHES',
              style: GoogleFonts.spaceGrotesk(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12),
            ),
            const SizedBox(height: 6),
            Text(
              'No configured benefits yield rewards for this specific transaction profile.',
              style: GoogleFonts.plusJakartaSans(
                  color: Colors.white38, fontSize: 11),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Best Card Container
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF0C152B),
            borderRadius: BorderRadius.circular(AppBorderRadius.xl),
            border: Border.all(
                color: AppTheme.successColor.withValues(alpha: 0.3),
                width: 1.5),
            boxShadow: AppTheme.neonGlow(
                color: AppTheme.successColor, opacity: 0.08, blurRadius: 12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.verified_outlined,
                      color: AppTheme.successColor, size: 20),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    'BEST ROUTING MATCH',
                    style: GoogleFonts.spaceGrotesk(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.successColor,
                      fontSize: 12,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                (bestCard['card']['card_name'] as String).toUpperCase(),
                style: GoogleFonts.spaceGrotesk(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              Text(
                (bestCard['card']['bank_name'] as String).toUpperCase(),
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white38,
                  fontSize: 10,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF050B18),
                  borderRadius: BorderRadius.circular(AppBorderRadius.lg),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'ESTIMATED YIELD:',
                      style: GoogleFonts.spaceGrotesk(
                          color: Colors.white60,
                          fontSize: 10,
                          fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '₹${bestCard['total_reward'].toStringAsFixed(2)} (${bestCard['reward_percentage'].toStringAsFixed(2)}%)',
                      style: GoogleFonts.spaceGrotesk(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.successColor,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const Divider(color: Color(0xFF1E293B)),
              const SizedBox(height: 6),
              Text(
                'APPLICABLE SAVINGS RULES:',
                style: GoogleFonts.spaceGrotesk(
                    color: Colors.white70,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5),
              ),
              const SizedBox(height: AppSpacing.sm),
              ...bestCard['applicable_benefits'].map<Widget>((benefit) {
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_outline,
                          size: 14, color: AppTheme.successColor),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          '${benefit['benefit_name'].toString().toUpperCase()}: ₹${benefit['reward'].toStringAsFixed(2)}',
                          style: GoogleFonts.spaceGrotesk(
                              color: Colors.white60,
                              fontSize: 10,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ],
          ),
        ),

        // Alternative Options list
        if (recommendations.length > 1) ...[
          const SizedBox(height: AppSpacing.lg),
          Text(
            'ALTERNATIVE INTEGRATIONS',
            style: GoogleFonts.spaceGrotesk(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 11,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          ...recommendations.map<Widget>((rec) {
            final isFirst = rec == recommendations.first;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF0C152B),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isFirst
                      ? AppTheme.successColor.withValues(alpha: 0.25)
                      : Colors.white.withValues(alpha: 0.05),
                ),
              ),
              // Material(transparency) restores ListTile ink splashes/tap
              // feedback, which the DecoratedBox above would otherwise hide.
              child: Material(
                type: MaterialType.transparency,
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isFirst
                        ? AppTheme.successColor.withValues(alpha: 0.15)
                        : Colors.white.withValues(alpha: 0.05),
                    child: Icon(
                      isFirst
                          ? Icons.verified_outlined
                          : Icons.credit_card_outlined,
                      color: isFirst ? AppTheme.successColor : Colors.white38,
                      size: 18,
                    ),
                  ),
                  title: Text(
                    (rec['card']['card_name'] as String).toUpperCase(),
                    style: GoogleFonts.spaceGrotesk(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    (rec['card']['bank_name'] as String).toUpperCase(),
                    style: GoogleFonts.plusJakartaSans(
                        color: Colors.white38, fontSize: 9),
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '₹${rec['total_reward'].toStringAsFixed(2)}',
                        style: GoogleFonts.spaceGrotesk(
                          fontWeight: FontWeight.bold,
                          color: isFirst ? AppTheme.successColor : Colors.white,
                          fontSize: 11,
                        ),
                      ),
                      Text(
                        '${rec['reward_percentage'].toStringAsFixed(2)}%',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 9,
                          color:
                              isFirst ? AppTheme.successColor : Colors.white38,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ],
      ],
    );
  }

  Widget _buildOptimizationsTab() {
    if (_isLoadingOptimizations) {
      return const LoadingState(message: 'DECRYPTING EXPENDITURE METRICS...');
    }

    if (_optimizations.isEmpty) {
      return const EmptyState(
        icon: Icons.trending_up,
        title: 'ROUTING OPTIMAL',
        message:
            'All transaction categories processed yield optimal reward matching.',
      );
    }

    return RefreshIndicator(
      color: AppTheme.primaryColor,
      backgroundColor: const Color(0xFF0C152B),
      onRefresh: _loadOptimizations,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
        itemCount: _optimizations.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            final totalMissedRewards = _optimizations.fold<double>(
                0.0, (sum, opt) => sum + opt['potential_savings']);

            return Container(
              margin: const EdgeInsets.only(bottom: 20),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF0C152B),
                borderRadius: BorderRadius.circular(AppBorderRadius.xl),
                border: Border.all(
                    color: AppTheme.secondaryColor.withValues(alpha: 0.3),
                    width: 1.5),
                boxShadow: AppTheme.neonGlow(
                    color: AppTheme.secondaryColor,
                    opacity: 0.08,
                    blurRadius: 10),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.insights_outlined,
                    size: 36,
                    color: AppTheme.secondaryColor,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'REWARDS DISCREPANCY DETECTED',
                    style: GoogleFonts.spaceGrotesk(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '₹${totalMissedRewards.toStringAsFixed(2)} was uncollected due to sub-optimal routing.',
                    style: GoogleFonts.spaceGrotesk(
                      color: AppTheme.secondaryColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          final optimization = _optimizations[index - 1];
          final transaction = optimization['transaction'];
          final bestCard = optimization['best_card'];

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0C152B),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        (transaction['merchant_name'] ?? 'UNKNOWN')
                            .toString()
                            .toUpperCase(),
                        style: GoogleFonts.spaceGrotesk(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.errorColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(AppBorderRadius.md),
                        border: Border.all(
                            color: AppTheme.errorColor.withValues(alpha: 0.2)),
                      ),
                      child: Text(
                        '₹${optimization['potential_savings'].toStringAsFixed(2)} MISSED',
                        style: GoogleFonts.spaceGrotesk(
                          color: AppTheme.errorColor,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Amount: ₹${transaction['amount']}',
                  style: GoogleFonts.plusJakartaSans(
                      color: Colors.white60, fontSize: 11),
                ),
                Text(
                  'Date: ${DateFormat('MMM dd, yyyy').format(DateTime.parse(transaction['transaction_date']))}',
                  style: GoogleFonts.plusJakartaSans(
                      color: Colors.white38, fontSize: 10),
                ),
                const SizedBox(height: 12),
                const Divider(color: Color(0xFF1E293B)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.lightbulb_outline,
                        size: 14, color: AppTheme.primaryColor),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'BEST CARD: ${bestCard['card']['card_name'].toString().toUpperCase()}',
                        style: GoogleFonts.spaceGrotesk(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryColor,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  'Potential returns return rate: ₹${optimization['optimal_reward'].toStringAsFixed(2)}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    color: Colors.white30,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSummaryTab() {
    if (_isLoadingSummary) {
      return const LoadingState(message: 'DECRYPTING LEDGER REWARDS...');
    }

    if (_rewardSummary == null || _rewardSummary!.isEmpty) {
      return const EmptyState(
        icon: Icons.analytics,
        title: 'NO LEDGERS STAGED',
        message: 'Import statements to verify rewards audit logs.',
      );
    }

    final summary = _rewardSummary!;

    return RefreshIndicator(
      color: AppTheme.primaryColor,
      backgroundColor: const Color(0xFF0C152B),
      onRefresh: _loadRewardSummary,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Overall summary grid wrapper
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF0C152B),
                borderRadius: BorderRadius.circular(AppBorderRadius.xl),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'REWARDS AUDIT SUMMARY',
                    style: GoogleFonts.spaceGrotesk(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: _buildSummaryItem(
                          'TOTAL SPEND',
                          '₹${summary['total_spending']?.toStringAsFixed(0) ?? '0'}',
                          Icons.account_balance_wallet_outlined,
                          AppTheme.primaryColor,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildSummaryItem(
                          'SAVED YIELD',
                          '₹${summary['total_rewards_earned']?.toStringAsFixed(2) ?? '0'}',
                          Icons.verified_outlined,
                          AppTheme.successColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _buildSummaryItem(
                          'MISSED YIELD',
                          '₹${summary['missed_rewards']?.toStringAsFixed(2) ?? '0'}',
                          Icons.warning_amber_outlined,
                          AppTheme.errorColor,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildSummaryItem(
                          'EFFICIENCY SCORE',
                          '${summary['optimization_score']?.toStringAsFixed(1) ?? '0'}%',
                          Icons.speed_outlined,
                          AppTheme.secondaryColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Category breakdown
            if (summary['category_breakdown'] != null) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF0C152B),
                  borderRadius: BorderRadius.circular(AppBorderRadius.xl),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.06)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SAVINGS BREAKDOWN BY CLASSIFICATION',
                      style: GoogleFonts.spaceGrotesk(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ...(summary['category_breakdown'] as Map<String, dynamic>)
                        .entries
                        .map((entry) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              entry.key.toUpperCase(),
                              style: GoogleFonts.spaceGrotesk(
                                  color: Colors.white70,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold),
                            ),
                            Text(
                              '₹${entry.value.toStringAsFixed(2)}',
                              style: GoogleFonts.spaceGrotesk(
                                fontWeight: FontWeight.bold,
                                color: AppTheme.successColor,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(
      String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF050B18),
        borderRadius: BorderRadius.circular(AppBorderRadius.lg),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: AppSpacing.sm),
          Text(
            value,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: GoogleFonts.spaceGrotesk(
                color: Colors.white38,
                fontSize: 8,
                fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendationsTab() {
    if (_isLoadingRecommendations) {
      return const LoadingState(message: 'SCANNING CATALOG ROUTINGS...');
    }

    if (_personalizedRecommendations.isEmpty) {
      return const EmptyState(
        icon: Icons.recommend,
        title: 'NO CATALOG SUGGESTIONS',
        message:
            'Import further transaction histories to calculate card recommendation index.',
      );
    }

    return RefreshIndicator(
      color: AppTheme.primaryColor,
      backgroundColor: const Color(0xFF0C152B),
      onRefresh: _loadPersonalizedRecommendations,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
        itemCount: _personalizedRecommendations.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Container(
              margin: const EdgeInsets.only(bottom: 20),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF0C152B),
                borderRadius: BorderRadius.circular(AppBorderRadius.xl),
                border: Border.all(
                    color: AppTheme.primaryColor.withValues(alpha: 0.2),
                    width: 1.5),
                boxShadow: AppTheme.neonGlow(
                    color: AppTheme.primaryColor,
                    opacity: 0.06,
                    blurRadius: 10),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.auto_awesome_outlined,
                    size: 36,
                    color: AppTheme.primaryColor,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'PORTFOLIO UPGRADES REGISTER',
                    style: GoogleFonts.spaceGrotesk(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'These credit cards align optimal matching rates with your spending history.',
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white70,
                      fontSize: 11,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          final recommendation = _personalizedRecommendations[index - 1];
          final card = recommendation['card'];

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0C152B),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (card['card_name'] as String).toUpperCase(),
                            style: GoogleFonts.spaceGrotesk(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            (card['bank_name'] as String).toUpperCase(),
                            style: GoogleFonts.plusJakartaSans(
                              color: Colors.white38,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.successColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(AppBorderRadius.md),
                        border: Border.all(
                            color:
                                AppTheme.successColor.withValues(alpha: 0.2)),
                      ),
                      child: Text(
                        '+₹${recommendation['projected_monthly_reward'].toStringAsFixed(0)}/MO',
                        style: GoogleFonts.spaceGrotesk(
                          color: AppTheme.successColor,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Annual Fee: ₹${card['annual_fee']?.toStringAsFixed(0) ?? '0'}',
                  style: GoogleFonts.plusJakartaSans(
                      color: Colors.white38, fontSize: 10),
                ),
                Text(
                  'Net Annual Benefit: ₹${recommendation['net_annual_benefit'].toStringAsFixed(0)}',
                  style: GoogleFonts.spaceGrotesk(
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    color: recommendation['net_annual_benefit'] > 0
                        ? AppTheme.successColor
                        : AppTheme.errorColor,
                  ),
                ),
                const SizedBox(height: 12),
                const Divider(color: Color(0xFF1E293B)),
                const SizedBox(height: 6),
                Text(
                  'COMPATIBLE BENEFITS PATH:',
                  style: GoogleFonts.spaceGrotesk(
                      color: Colors.white70,
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5),
                ),
                const SizedBox(height: AppSpacing.sm),
                ...recommendation['matching_categories']
                    .take(3)
                    .map<Widget>((category) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.check,
                            size: 12, color: AppTheme.successColor),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            category.toString().toUpperCase(),
                            style: GoogleFonts.spaceGrotesk(
                              color: Colors.white60,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMovieAnalyzerTab() {
    return const MovieAnalyzerTab();
  }
}
