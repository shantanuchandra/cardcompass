import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cardcompass/shared/widgets/state_widgets.dart';
import 'package:cardcompass/features/auth/providers/auth_provider.dart';
import 'package:cardcompass/core/providers/service_providers.dart';
import 'package:cardcompass/core/services/recommendation_service.dart';
import 'package:cardcompass/core/theme.dart';

/// Screen displaying personalized credit card recommendations in cyber-fintech visual style
class RecommendationsScreen extends ConsumerStatefulWidget {
  const RecommendationsScreen({super.key});

  @override
  ConsumerState<RecommendationsScreen> createState() => _RecommendationsScreenState();
}

class _RecommendationsScreenState extends ConsumerState<RecommendationsScreen> {
  bool _isLoading = true;
  String? _error;
  List<SpendingOptimization> _optimizations = const [];
  List<RewardOptimization> _rewardOptimizations = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadRecommendations();
    });
  }

  Future<void> _loadRecommendations() async {
    final user = ref.read(authStateProvider).user;
    if (user == null) {
      setState(() {
        _isLoading = false;
        _error = 'Please sign in to view recommendations.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final service = ref.read(recommendationServiceProvider);
      final results = await Future.wait([
        service.getSpendingOptimizations(userId: user.id),
        service.getRewardOptimizations(userId: user.id),
      ]);
      if (!mounted) return;
      setState(() {
        _optimizations = results[0] as List<SpendingOptimization>;
        _rewardOptimizations = results[1] as List<RewardOptimization>;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not decrypt recommendations: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050B18),
      appBar: AppBar(
        title: Text(
          'RECOMMENDATIONS',
          style: GoogleFonts.spaceGrotesk(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
            fontSize: 18,
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadRecommendations,
        color: AppTheme.primaryColor,
        backgroundColor: const Color(0xFF0C152B),
        child: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation(AppTheme.primaryColor),
        ),
      );
    }

    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          const SizedBox(height: 80),
          EmptyState(
            icon: Icons.recommend,
            title: 'NO RECOMMENDATIONS YET',
            message: _error!,
          ),
        ],
      );
    }

    if (_optimizations.isEmpty && _rewardOptimizations.isEmpty) {
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          const SizedBox(height: 80),
          EmptyState(
            icon: Icons.recommend,
            title: 'YOU ARE FULLY OPTIMIZED',
            message: 'We don\'t see any better card matches for your recent spending patterns right now.',
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 80),
      children: [
        if (_rewardOptimizations.isNotEmpty) ...[
          Text(
            'REWARD OPPORTUNITIES',
            style: GoogleFonts.spaceGrotesk(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 12),
          ..._rewardOptimizations.map((r) => _buildRewardCard(context, r)),
          const SizedBox(height: 24),
        ],
        if (_optimizations.isNotEmpty) ...[
          Text(
            'SPENDING OPTIMIZATIONS',
            style: GoogleFonts.spaceGrotesk(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 12),
          ..._optimizations.map((o) => _buildOptimizationCard(context, o)),
        ],
      ],
    );
  }

  Widget _buildRewardCard(BuildContext context, RewardOptimization r) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0C152B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.accentColor.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.accentColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.3), width: 1),
            ),
            child: const Icon(
              Icons.stars,
              color: AppTheme.accentColor,
              size: 18,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.title,
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  r.description,
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white60,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '+₹${r.potentialReward.toStringAsFixed(0)}',
            style: GoogleFonts.spaceGrotesk(
              color: AppTheme.successColor,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptimizationCard(BuildContext context, SpendingOptimization o) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0C152B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.3), width: 1),
            ),
            child: const Icon(
              Icons.trending_up,
              color: AppTheme.primaryColor,
              size: 18,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${o.category.toUpperCase()} OPTIMIZATION',
                  style: GoogleFonts.spaceGrotesk(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  o.suggestion,
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white60,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '+₹${o.potentialSavings.toStringAsFixed(0)}',
            style: GoogleFonts.spaceGrotesk(
              color: AppTheme.successColor,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}
