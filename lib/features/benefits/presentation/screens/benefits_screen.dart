import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cardcompass/features/auth/providers/auth_provider.dart';
import 'package:cardcompass/features/benefits/viewmodels/benefits_viewmodel.dart';
import 'package:cardcompass/shared/models/credit_card.dart';
import 'package:cardcompass/shared/widgets/state_widgets.dart';
import 'package:cardcompass/core/theme.dart';

/// Screen to manage and view credit card benefits in cyber-fintech style
class BenefitsScreen extends ConsumerStatefulWidget {
  const BenefitsScreen({super.key});

  @override
  ConsumerState<BenefitsScreen> createState() => _BenefitsScreenState();
}

class _BenefitsScreenState extends ConsumerState<BenefitsScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadBenefits();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
  
  void _loadBenefits() {
    final user = ref.read(authStateProvider).user;
    if (user != null) {
      ref.read(benefitsViewModelProvider.notifier).loadBenefitsData(user.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final benefitsState = ref.watch(benefitsViewModelProvider);

    if (benefitsState.isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF050B18),
        body: LoadingState(message: 'DECRYPTING BENEFITS DATA...'),
      );
    }

    if (benefitsState.error != null) {
      return Scaffold(
        backgroundColor: const Color(0xFF050B18),
        body: ErrorState(
          error: benefitsState.error!,
          onRetry: _loadBenefits,
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF050B18),
      appBar: AppBar(
        title: Text(
          'BENEFITS CENTER',
          style: GoogleFonts.spaceGrotesk(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
            fontSize: 16,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.primaryColor,
          unselectedLabelColor: Colors.white38,
          indicatorColor: AppTheme.primaryColor,
          indicatorSize: TabBarIndicatorSize.tab,
          labelStyle: GoogleFonts.spaceGrotesk(
            fontWeight: FontWeight.bold,
            fontSize: 10,
            letterSpacing: 0.5,
          ),
          tabs: const [
            Tab(icon: Icon(Icons.card_giftcard, size: 18), text: 'ACTIVE'),
            Tab(icon: Icon(Icons.trending_up, size: 18), text: 'USAGE'),
            Tab(icon: Icon(Icons.compare_arrows, size: 18), text: 'COMPARE'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildActiveBenefitsTab(benefitsState),
          _buildUsageTab(benefitsState),
          _buildCompareTab(benefitsState.userCards),
        ],
      ),
    );
  }

  Widget _buildActiveBenefitsTab(BenefitsViewState state) {
    if (state.userCards.isEmpty) {
      return const EmptyState(
        title: 'NO ACTIVE CARDS',
        message: 'Integrate credit cards to track active benefits.',
        icon: Icons.credit_card_off,
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildBenefitsSummaryCard(state.userCards),
          const SizedBox(height: 20),
          _buildCardSelector(state.userCards),
          const SizedBox(height: 24),
          _buildBenefitsList(state.userCards),
        ],
      ),
    );
  }

  Widget _buildBenefitsSummaryCard(List<CreditCard> userCards) {
    final totalBenefits = userCards.fold<int>(0, (sum, card) => sum + card.benefits.length);
    final activeBenefits = userCards.fold<int>(0, (sum, card) => 
      sum + card.benefits.where((b) => b.isActive).length);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0C152B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: 0.2),
          width: 1.5,
        ),
        boxShadow: AppTheme.neonGlow(color: AppTheme.primaryColor, opacity: 0.1, blurRadius: 10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bolt, color: AppTheme.primaryColor, size: 22),
              const SizedBox(width: 8),
              Text(
                'BENEFITS METRICS',
                style: GoogleFonts.spaceGrotesk(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildSummaryItem(
                  'RULES LOADED',
                  totalBenefits.toString(),
                  Icons.inventory_2_outlined,
                  AppTheme.primaryColor,
                ),
              ),
              Expanded(
                child: _buildSummaryItem(
                  'ACTIVE OFFERS',
                  activeBenefits.toString(),
                  Icons.verified_outlined,
                  AppTheme.successColor,
                ),
              ),
              Expanded(
                child: _buildSummaryItem(
                  'INTEGRATIONS',
                  userCards.length.toString(),
                  Icons.credit_card_outlined,
                  AppTheme.accentColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 8),
        Text(
          value,
          style: GoogleFonts.spaceGrotesk(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.spaceGrotesk(
            color: Colors.white38,
            fontSize: 8,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildCardSelector(List<CreditCard> userCards) {
    final benefitsState = ref.watch(benefitsViewModelProvider);
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0C152B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: DropdownButton<String>(
        value: benefitsState.selectedCardId.isEmpty ? null : benefitsState.selectedCardId,
        dropdownColor: const Color(0xFF0C152B),
        hint: Text(
          'SELECT PORTFOLIO INTEGRATION',
          style: GoogleFonts.spaceGrotesk(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold),
        ),
        isExpanded: true,
        underline: const SizedBox(),
        icon: const Icon(Icons.arrow_drop_down, color: AppTheme.primaryColor),
        items: [
          DropdownMenuItem<String>(
            value: '',
            child: Text(
              'ALL PORTFOLIO CARDS',
              style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
          ...userCards.map((card) {
            return DropdownMenuItem<String>(
              value: card.id,
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 20,
                    decoration: BoxDecoration(
                      color: card.networkColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: card.networkColor.withValues(alpha: 0.3)),
                    ),
                    child: Center(
                      child: Text(
                        card.network.name.substring(0, 1).toUpperCase(),
                        style: GoogleFonts.spaceGrotesk(
                          color: card.networkColor,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          card.cardName.toUpperCase(),
                          style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          card.bankName.toUpperCase(),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 9,
                            color: Colors.white38,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
        onChanged: (value) {
          ref.read(benefitsViewModelProvider.notifier).setSelectedCard(value ?? '');
        },
      ),
    );
  }

  Widget _buildBenefitsList(List<CreditCard> userCards) {
    final benefitsViewModel = ref.read(benefitsViewModelProvider.notifier);
    final selectedCards = benefitsViewModel.getSelectedCards();

    if (selectedCards.isEmpty) {
      return const EmptyState(
        title: 'NO CONFIGURATIONS FOUND',
        message: 'The selected card profile contains no benefits.',
        icon: Icons.card_membership,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'CONFIGURED BENEFITS DETAILS',
          style: GoogleFonts.spaceGrotesk(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 12,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 14),
        ...selectedCards.map((card) => _buildCardBenefits(card)),
      ],
    );
  }

  Widget _buildCardBenefits(CreditCard card) {
    final benefitsViewModel = ref.read(benefitsViewModelProvider.notifier);
    final realBenefits = benefitsViewModel.getCardBenefits(card.id);
    
    final headerWidget = Row(
      children: [
        Container(
          width: 32,
          height: 20,
          decoration: BoxDecoration(
            color: card.networkColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: card.networkColor.withValues(alpha: 0.3)),
          ),
          child: Center(
            child: Text(
              card.network.name.substring(0, 1).toUpperCase(),
              style: GoogleFonts.spaceGrotesk(
                color: card.networkColor,
                fontWeight: FontWeight.bold,
                fontSize: 10,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                card.cardName.toUpperCase(),
                style: GoogleFonts.spaceGrotesk(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              Text(
                card.bankName.toUpperCase(),
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white38,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    if (realBenefits.isEmpty) {
      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF0C152B),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            headerWidget,
            const SizedBox(height: 16),
            Center(
              child: Text(
                'No rules configured for this model.',
                style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 12),
              ),
            ),
          ],
        ),
      );
    }
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0C152B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          headerWidget,
          const SizedBox(height: 16),
          ...realBenefits.map((benefit) => _buildRealBenefitItem(benefit)),
        ],
      ),
    );
  }

  Widget _buildRealBenefitItem(dynamic benefit) {
    final isActive = benefit is Map ? (benefit['isActive'] ?? true) : true;
    final category = benefit is Map ? (benefit['category'] ?? 'General') : 'General';
    final description = benefit is Map ? (benefit['description'] ?? 'No description') : 'No description';
    final value = benefit is Map ? (benefit['value'] ?? 'N/A') : 'N/A';
    final activeColor = isActive ? AppTheme.successColor : Colors.white30;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF050B18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: activeColor.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isActive ? Icons.verified_outlined : Icons.pause_circle_outline,
            color: activeColor,
            size: 16,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        category.toUpperCase(),
                        style: GoogleFonts.spaceGrotesk(
                          fontWeight: FontWeight.bold,
                          color: isActive ? Colors.white : Colors.white30,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: activeColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: activeColor.withValues(alpha: 0.2)),
                      ),
                      child: Text(
                        value.toString().toUpperCase(),
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: activeColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: isActive ? Colors.white60 : Colors.white30,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUsageTab(BenefitsViewState state) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SAVINGS PROFILE MONITOR',
            style: GoogleFonts.spaceGrotesk(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 16),
          
          // Period Card
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF0C152B),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SELECT EVALUATION TIMELINE',
                  style: GoogleFonts.spaceGrotesk(
                    color: Colors.white70,
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          ref.read(benefitsViewModelProvider.notifier).setSelectedPeriod('current_month');
                        },
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: state.selectedPeriod == 'current_month' 
                                ? AppTheme.primaryColor 
                                : Colors.white.withValues(alpha: 0.1),
                          ),
                        ),
                        child: Text('THIS MONTH', style: GoogleFonts.spaceGrotesk(fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          ref.read(benefitsViewModelProvider.notifier).setSelectedPeriod('previous_month');
                        },
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: state.selectedPeriod == 'previous_month' 
                                ? AppTheme.primaryColor 
                                : Colors.white.withValues(alpha: 0.1),
                          ),
                        ),
                        child: Text('PREVIOUS MONTH', style: GoogleFonts.spaceGrotesk(fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 20),
          _buildUsageMetrics(state),
          const SizedBox(height: 20),
          _buildUsageHistory(state),
        ],
      ),
    );
  }

  Widget _buildCompareTab(List<CreditCard> userCards) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'CROSS-CARD RULE EVALUATIONS',
            style: GoogleFonts.spaceGrotesk(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 16),
          _buildComparisonTable(userCards),
        ],
      ),
    );
  }

  Widget _buildUsageMetrics(BenefitsViewState state) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF0C152B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SAVINGS DECRYPTION LEDGER',
            style: GoogleFonts.spaceGrotesk(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 11,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: state.metrics.isEmpty 
                ? [
                    Expanded(
                      child: Center(
                        child: Text(
                          'No metrics recorded for selected evaluation timeframe.',
                          style: GoogleFonts.plusJakartaSans(color: Colors.white30, fontSize: 11),
                        ),
                      ),
                    )
                  ]
                : state.metrics.map((metric) => Expanded(
                    child: _buildMetricItem(
                      metric.label.toUpperCase(), 
                      metric.value, 
                      _getIconFromString(metric.icon), 
                      _getColorFromString(metric.color),
                    ),
                  )).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricItem(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 8),
        Text(
          value,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 8,
            color: Colors.white38,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildUsageHistory(BenefitsViewState state) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF0C152B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'CHRONOLOGICAL SAVINGS FEED',
            style: GoogleFonts.spaceGrotesk(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 11,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 20),
          if (state.recentUsage.isEmpty)
            Center(
              child: Text(
                'No recorded savings events.',
                style: GoogleFonts.plusJakartaSans(color: Colors.white30, fontSize: 11),
              ),
            )
          else
            ...state.recentUsage.map((usage) => _buildUsageItem(
              usage.benefitName.toUpperCase(),
              '₹${usage.amountSaved.toStringAsFixed(0)} SAVED',
              _formatDate(usage.usageDate),
              AppTheme.successColor,
            )),
        ],
      ),
    );
  }

  Widget _buildUsageItem(String benefit, String saving, String date, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  benefit,
                  style: GoogleFonts.spaceGrotesk(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  saving,
                  style: GoogleFonts.spaceGrotesk(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Text(
            date.toUpperCase(),
            style: GoogleFonts.spaceGrotesk(
              color: Colors.white38,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComparisonTable(List<CreditCard> userCards) {
    if (userCards.isEmpty) {
      return const EmptyState(
        title: 'NO INTEL TO COMPARE',
        message: 'Add card integration credentials to verify benefits routing.',
        icon: Icons.compare_arrows,
      );
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF0C152B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'FEATURE CROSS-TAB',
            style: GoogleFonts.spaceGrotesk(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 11,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(const Color(0xFF050B18)),
              columns: [
                DataColumn(
                  label: Text('FEATURE', style: GoogleFonts.spaceGrotesk(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 10)),
                ),
                ...userCards.take(3).map((card) => DataColumn(
                  label: Text(
                    card.cardName.toUpperCase(),
                    style: GoogleFonts.spaceGrotesk(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 9),
                  ),
                )),
              ],
              rows: _buildComparisonRows(userCards),
            ),
          ),
        ],
      ),
    );
  }

  List<DataRow> _buildComparisonRows(List<CreditCard> userCards) {
    return [];
  }

  IconData _getIconFromString(String iconName) {
    switch (iconName) {
      case 'check_circle':
        return Icons.check_circle_outline;
      case 'savings':
        return Icons.savings_outlined;
      case 'card_giftcard':
        return Icons.card_giftcard;
      case 'warning':
        return Icons.warning_amber_outlined;
      default:
        return Icons.info_outline;
    }
  }

  Color _getColorFromString(String colorName) {
    switch (colorName) {
      case 'green':
        return AppTheme.successColor;
      case 'blue':
        return AppTheme.primaryColor;
      case 'orange':
        return AppTheme.warningColor;
      case 'red':
        return AppTheme.errorColor;
      default:
        return Colors.white60;
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date).inDays;
    
    if (difference == 0) {
      return 'Today';
    } else if (difference == 1) {
      return 'Yesterday';
    } else {
      return '$difference days ago';
    }
  }
}
