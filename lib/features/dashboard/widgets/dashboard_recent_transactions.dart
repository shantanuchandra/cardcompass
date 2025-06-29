import 'package:flutter/material.dart';
import 'package:cardcompass/features/dashboard/viewmodels/dashboard_viewmodel.dart';
import 'package:cardcompass/shared/widgets/state_widgets.dart';
import 'package:cardcompass/config/routes.dart';

/// Recent transactions section widget
class DashboardRecentTransactions extends StatelessWidget {
  final DashboardViewState state;

  const DashboardRecentTransactions({
    super.key,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Recent Activity',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pushNamed(AppRoutes.transactions);
              },
              child: const Text('See All'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (state.recentTransactions.isEmpty)
          const EmptyState(
            title: 'No Recent Activity',
            message: 'Your recent transactions will appear here',
            icon: Icons.receipt_long,
          )
        else
          ...state.recentTransactions.take(5).map((transaction) => Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                child: Icon(
                  Icons.shopping_bag,
                  color: Theme.of(context).primaryColor,
                ),
              ),
              title: Text(transaction.merchantName ?? 'Unknown Merchant'),
              subtitle: Text(transaction.description),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '₹${transaction.amount.toStringAsFixed(2)}',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (transaction.rewardEarned != null && transaction.rewardEarned! > 0)
                    Text(
                      '+₹${transaction.rewardEarned!.toStringAsFixed(2)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.green,
                      ),
                    ),
                ],
              ),
            ),
          )),
      ],
    );
  }
}
