import 'package:flutter/material.dart';
import 'package:cardcompass/shared/models/credit_card.dart';
import 'package:cardcompass/shared/components/cards.dart';

/// Widget displaying a credit card item in the cards list
class CardItem extends StatelessWidget {
  final CreditCard card;
  final bool isUserCard;
  final VoidCallback? onTap;
  final VoidCallback? onAddPressed;
  
  const CardItem({
    super.key,
    required this.card,
    this.isUserCard = false,
    this.onTap,
    this.onAddPressed,
  });
  
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isUserCard 
            ? BorderSide(color: Theme.of(context).primaryColor, width: 2) 
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Card visualization
              SimpleCreditCardView(card: card),
              
              const SizedBox(height: 16),
              
              // Card details
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          card.cardName,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          card.bankName,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // Add button or owned indicator
                  if (isUserCard)
                    Chip(
                      label: const Text('Owned'),
                      backgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                      labelStyle: TextStyle(
                        color: Theme.of(context).primaryColor,
                        fontWeight: FontWeight.w500,
                      ),
                    )
                  else if (onAddPressed != null)
                    ElevatedButton.icon(
                      onPressed: onAddPressed,
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Add'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                    ),
                ],
              ),
              
              const SizedBox(height: 12),
              
              // Card features
              _buildCardFeatures(context),
              
              // Annual fee if applicable
              if (card.annualFee != null && card.annualFee! > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'Annual Fee: ₹${card.annualFee!.toStringAsFixed(0)}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
  
  /// Build card features section
  Widget _buildCardFeatures(BuildContext context) {
    // Extract features from card object
    final features = _getCardFeatures();
    
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: features.map((feature) {
        return Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 4,
          ),
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            feature,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        );
      }).toList(),
    );
  }
  
  /// Get card features based on card type and properties
  List<String> _getCardFeatures() {
    final List<String> features = [];
    
    // Add network
    features.add(card.network.toString().split('.').last.toUpperCase());
    
    // Add card type
    switch (card.type.toString().split('.').last) {
      case 'credit':
        features.add('Credit Card');
        break;
      case 'debit':
        features.add('Debit Card');
        break;
      case 'prepaid':
        features.add('Prepaid Card');
        break;
    }
    
    // Add features from benefits
    for (final benefit in card.benefits) {
      switch (benefit.calculationMethod) {
        case 'percentage':
          features.add('Cashback');
          break;
        case 'points':
          features.add('Reward Points');
          break;
        case 'loungeAccess':
          features.add('Lounge Access');
          break;
        case 'fuelSurcharge':
          features.add('Fuel Waiver');
          break;
        case 'insurance':
          features.add('Insurance');
          break;
      }
    }
    
    return features;
  }
}
