import 'package:flutter/material.dart';
import 'package:cardcompass/shared/models/credit_card.dart';
import 'package:cardcompass/shared/components/cards.dart';
import 'package:cardcompass/config/constants.dart';

/// Widget displaying credit card recommendation with reward details
class CardRecommendation extends StatelessWidget {
  final String title;
  final CreditCard card;
  final double rewardAmount;
  final bool isUserCard;

  const CardRecommendation({
    super.key,
    required this.title,
    required this.card,
    required this.rewardAmount,
    this.isUserCard = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isUserCard ? Colors.blue[50] : Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isUserCard ? Colors.blue[300]! : Colors.grey[300]!,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title and reward amount
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isUserCard ? Colors.blue[700] : Colors.grey[800],
                ),
              ),
              Text(
                '${AppConstants.currencySymbol}${rewardAmount.toStringAsFixed(2)}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isUserCard ? Colors.blue[700] : Colors.grey[800],
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 12),
          
          // Card visualization
          SimpleCreditCardView(card: card),
          
          const SizedBox(height: 12),
          
          // Card details
          Row(
            children: [
              Expanded(
                child: _buildDetailItem(
                  context,
                  'Bank',
                  card.bankName,
                  Icons.account_balance,
                ),
              ),
              Expanded(
                child: _buildDetailItem(
                  context,
                  'Network',
                  card.network.toString().split('.').last.toUpperCase(),
                  Icons.credit_card,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 8),
          
          // Card reward rate visualization
          const SizedBox(height: 8),
          
          LinearProgressIndicator(
            value: _calculateRewardPercentage(),
            backgroundColor: Colors.grey[200],
            color: isUserCard ? Colors.blue : Colors.grey[600],
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
          
          const SizedBox(height: 4),
          
          Text(
            _getRewardDescription(),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: isUserCard ? Colors.blue[600] : Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  /// Build detail item with icon and text
  Widget _buildDetailItem(
    BuildContext context,
    String label,
    String value,
    IconData icon,
  ) {
    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: isUserCard ? Colors.blue[600] : Colors.grey[600],
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[600],
                ),
              ),
              Text(
                value,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Calculate reward percentage for visualization
  double _calculateRewardPercentage() {
    // Assuming max realistic reward is 10%
    double percent = (rewardAmount / _getTransactionAmount()) * 100;
    return percent > 10 ? 1.0 : percent / 10;
  }

  /// Get transaction amount from reward amount
  double _getTransactionAmount() {
    // Estimate based on typical reward rates
    double rate = _estimateRewardRate();
    return rewardAmount / (rate / 100);
  }

  /// Estimate reward rate based on card type
  double _estimateRewardRate() {
    switch (card.type.toString().split('.').last) {
      case 'credit':        // Further categorize based on benefits or other criteria
        if (card.benefits.any((benefit) => 
            benefit.calculationMethod == 'points')) {
          return 2.5; // Premium card with reward points
        }
        return 1.5; // Regular credit card
      default:
        return 1.0; // Basic card
    }
  }

  /// Get reward description text
  String _getRewardDescription() {
    double rate = _estimateRewardRate();
    return 'Estimated ${rate.toStringAsFixed(2)}% reward rate';
  }
}
