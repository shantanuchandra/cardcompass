import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cardcompass/shared/components/app_bar.dart';
import 'package:cardcompass/shared/widgets/empty_state.dart' as empty_widgets;
import 'package:cardcompass/features/auth/providers/auth_provider.dart';
import 'package:cardcompass/core/providers/service_providers.dart';
import 'package:cardcompass/core/services/recommendation_service.dart';
import 'package:cardcompass/core/theme.dart';

/// Screen displaying personalized credit card recommendations
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
        _error = 'Please sign in to see recommendations.';
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
        _error = 'Could not load recommendations: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(
        title: 'Card Recommendations',
        showBackButton: true,
      ),
      body: RefreshIndicator(
        onRefresh: _loadRecommendations,
        child: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          empty_widgets.EmptyState(
            icon: Icons.recommend,
            title: 'No recommendations yet',
            message: _error!,
          ),
        ],
      );
    }

    if (_optimizations.isEmpty && _rewardOptimizations.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 80),
          empty_widgets.EmptyState(
            icon: Icons.recommend,
            title: 'You\'re all optimized!',
            message: 'We don\'t see any better card matches for your recent spending right now.',
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_rewardOptimizations.isNotEmpty) ...[
          Text('Reward opportunities', style: AppTextStyles.heading3),
          const SizedBox(height: 12),
          ..._rewardOptimizations.map((r) => _buildRewardCard(context, r)),
          const SizedBox(height: 24),
        ],
        if (_optimizations.isNotEmpty) ...[
          Text('Spending optimizations', style: AppTextStyles.heading3),
          const SizedBox(height: 12),
          ..._optimizations.map((o) => _buildOptimizationCard(context, o)),
        ],
      ],
    );
  }

  Widget _buildRewardCard(BuildContext context, RewardOptimization r) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppTheme.accentColor.withValues(alpha: 0.15),
          child: const Icon(Icons.stars, color: AppTheme.accentColor),
        ),
        title: Text(r.title, style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.w600)),
        subtitle: Text(r.description),
        trailing: Text(
          '+₹${r.potentialReward.toStringAsFixed(0)}',
          style: AppTextStyles.body1.copyWith(color: AppTheme.successColor, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _buildOptimizationCard(BuildContext context, SpendingOptimization o) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Icon(Icons.trending_up, color: Theme.of(context).colorScheme.primary),
        ),
        title: Text('${o.category} spending', style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.w600)),
        subtitle: Text(o.suggestion),
        trailing: Text(
          '+₹${o.potentialSavings.toStringAsFixed(0)}',
          style: AppTextStyles.body1.copyWith(color: AppTheme.successColor, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
