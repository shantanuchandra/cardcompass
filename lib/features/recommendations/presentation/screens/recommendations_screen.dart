import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cardcompass/shared/components/app_bar.dart';
import 'package:cardcompass/shared/widgets/empty_state.dart' as empty_widgets;
import 'package:cardcompass/features/auth/providers/auth_provider.dart';

/// Screen displaying personalized credit card recommendations
class RecommendationsScreen extends ConsumerStatefulWidget {
  const RecommendationsScreen({super.key});

  @override
  ConsumerState<RecommendationsScreen> createState() => _RecommendationsScreenState();
}

class _RecommendationsScreenState extends ConsumerState<RecommendationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadRecommendations();
    });
  }

  void _loadRecommendations() {
    final user = ref.read(authStateProvider).user;
    if (user != null) {
      // TODO: Load recommendations when viewmodel is ready
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
        onRefresh: () async {
          _loadRecommendations();
        },
        child: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    // For now, show a placeholder until the recommendation service is complete
    return const empty_widgets.EmptyState(
      icon: Icons.recommend,
      title: 'Coming Soon',
      message: 'Personalized card recommendations will be available here based on your spending patterns',
      buttonText: 'Analyze Transactions',
      // onButtonPressed: () => Navigator.pushNamed(context, '/transactions'),
    );
  }
}
