import 'package:flutter/material.dart';
import 'package:cardcompass/config/routes.dart';

/// Quick actions grid widget extracted from dashboard
class DashboardQuickActions extends StatelessWidget {
  final VoidCallback onSyncPressed;
  final VoidCallback onDeletePressed;
  final VoidCallback onAIBenefitsPressed;

  const DashboardQuickActions({
    super.key,
    required this.onSyncPressed,
    required this.onDeletePressed,
    required this.onAIBenefitsPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick Actions',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: Colors.grey[700],
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final screenWidth = constraints.maxWidth;
            final isWideScreen = screenWidth > 600;
            final crossAxisCount = isWideScreen ? 4 : 3;
            final itemHeight = isWideScreen ? 70.0 : 65.0;
            
            return GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: screenWidth / (crossAxisCount * itemHeight),
              children: [
                _buildCompactQuickActionCard(
                  context,
                  'Cards',
                  Icons.credit_card,
                  Colors.blue,
                  () => Navigator.of(context).pushNamed(AppRoutes.cards),
                ),
                _buildCompactQuickActionCard(
                  context,
                  'Benefits',
                  Icons.card_giftcard,
                  Colors.green,
                  () => Navigator.of(context).pushNamed(AppRoutes.benefits),
                ),
                _buildCompactQuickActionCard(
                  context,
                  'Advisor',
                  Icons.lightbulb,
                  Colors.orange,
                  () => Navigator.of(context).pushNamed(AppRoutes.enhancedTransactionAdvisor),
                ),
                _buildCompactQuickActionCard(
                  context,
                  'Analytics',
                  Icons.analytics,
                  Colors.purple,
                  () => Navigator.of(context).pushNamed(AppRoutes.analytics),
                ),
                _buildCompactQuickActionCard(
                  context,
                  'AI Benefits',
                  Icons.auto_awesome,
                  Colors.indigo,
                  onAIBenefitsPressed,
                ),
                _buildCompactQuickActionCard(
                  context,
                  'Sync',
                  Icons.sync,
                  Colors.teal,
                  onSyncPressed,
                ),
                _buildCompactQuickActionCard(
                  context,
                  'Delete',
                  Icons.delete_sweep,
                  Colors.red.shade400,
                  onDeletePressed,
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildCompactQuickActionCard(
    BuildContext context,
    String title,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(height: 2),
              Flexible(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w500,
                    fontSize: 10,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
