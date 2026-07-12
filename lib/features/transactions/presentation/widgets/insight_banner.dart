// lib/features/transactions/presentation/widgets/insight_banner.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme.dart';
import '../../providers/transactions_provider.dart';

class InsightBanner extends ConsumerWidget {
  const InsightBanner({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spending = ref.watch(monthlySpendingProvider);
    final rewards = ref.watch(monthlyRewardsProvider);
    final insights = [
      'You spent \$${spending.toStringAsFixed(0)} this month',
      'Earned \$${rewards.toStringAsFixed(0)} in rewards',
    ];
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primaryColor.withOpacity(0.2),
            AppTheme.secondaryColor.withOpacity(0.2)
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppBorderRadius.lg),
        boxShadow: AppTheme.neonGlow(
          color: AppTheme.primaryColor,
          opacity: 0.15,
          blurRadius: 12,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: insights
            .map((s) => Text(
                  s,
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white,
                    fontSize: 14,
                  ),
                ))
            .toList(),
      ),
    );
  }
}
