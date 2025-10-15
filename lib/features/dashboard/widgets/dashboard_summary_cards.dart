import 'package:flutter/material.dart';
import 'package:cardcompass/features/dashboard/viewmodels/dashboard_viewmodel.dart';
import 'package:intl/intl.dart';

/// Summary cards section widget
class DashboardSummaryCards extends StatelessWidget {
  final DashboardViewState state;
  final DashboardViewModel viewModel;

  const DashboardSummaryCards({
    super.key,
    required this.state,
    required this.viewModel,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'This Month',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildSummaryCard(
                context,
                'Spending',
                // Format spending with thousand separators and currency symbol
                NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
                    .format(viewModel.totalMonthlySpending),
                'This month',
                Icons.account_balance_wallet_outlined,
                Theme.of(context).primaryColor,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildSummaryCard(
                context,
                'Rewards',
                '₹${viewModel.totalMonthlyRewards.toStringAsFixed(0)}',
                'Earned',
                Icons.stars_outlined,
                Colors.green,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildSummaryCard(
                context,
                'Cards',
                '${state.userCards.length}',
                'Active',
                Icons.credit_card_outlined,
                Colors.blue,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildSummaryCard(
                context,
                'Savings',
                '${viewModel.totalMonthlySpending > 0 ? ((viewModel.totalMonthlyRewards / viewModel.totalMonthlySpending) * 100).toStringAsFixed(1) : "0"}%',
                'Rate',
                Icons.trending_up,
                Colors.orange,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSummaryCard(
    BuildContext context,
    String title,
    String value,
    String subtitle,
    IconData icon,
    Color color,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: title == 'Spending' 
                    ? const Color.fromARGB(255, 72, 247, 124)
                    : color,
                height: 1.1, // Tighten line height
                letterSpacing: -0.5, // Tighten letter spacing
                shadows: [
                  Shadow(
                    color: Colors.black26.withOpacity(0.3),
                    offset: const Offset(0, 1),
                    blurRadius: 2,
                  ),
                ],
              ),
            ),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
