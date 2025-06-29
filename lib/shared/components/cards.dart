import 'package:flutter/material.dart';
import 'package:cardcompass/shared/models/credit_card.dart';

/// Simple credit card visualization widget
class SimpleCreditCardView extends StatelessWidget {
  final CreditCard card;
  final bool showDetails;
  
  const SimpleCreditCardView({
    super.key,
    required this.card,
    this.showDetails = false,
  });
  
  @override
  Widget build(BuildContext context) {
    // Determine card color based on type
    Color cardColor;
    switch (card.type.toString().split('.').last) {
      case 'credit':
        cardColor = Colors.blue[700]!;
        break;
      case 'debit':
        cardColor = Colors.green[700]!;
        break;
      case 'prepaid':
        cardColor = Colors.orange[700]!;
        break;
      default:
        cardColor = Colors.blue[900]!;
    }
    
    // Create gradient based on card color
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        cardColor,
        cardColor.withValues(alpha: 0.8),
        cardColor.withValues(alpha: 0.6),
      ],
    );
    
    return Container(
      height: 120,
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: cardColor.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Card network logo (positioned in corner)
          Positioned(
            top: 12,
            right: 12,
            child: _buildNetworkLogo(card.network.toString().split('.').last),
          ),
          
          // Card content
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Bank logo or name
                Text(
                  card.bankName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                
                // Card number (if showing details)
                if (showDetails && card.cardNumber != null && card.cardNumber!.isNotEmpty)
                  Text(
                    card.maskedCardNumber,
                    style: const TextStyle(
                      color: Colors.white,
                      letterSpacing: 2,
                    ),
                  ),
                
                // Card name
                Flexible(
                  child: Text(
                    card.cardName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  /// Build network logo widget based on card network
  Widget _buildNetworkLogo(String network) {
    switch (network.toLowerCase()) {
      case 'visa':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            'VISA',
            style: TextStyle(
              color: Colors.blue[900],
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        );
      case 'mastercard':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
              ),
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(left: 2),
                decoration: const BoxDecoration(
                  color: Colors.amber,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        );
      case 'rupay':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            'RuPay',
            style: TextStyle(
              color: Colors.green[800],
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        );
      case 'amex':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            'AMEX',
            style: TextStyle(
              color: Colors.blue[800],
              fontWeight: FontWeight.bold,
              fontSize: 10,
            ),
          ),
        );
      case 'diners':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            'DINERS',
            style: TextStyle(
              color: Colors.blue[800],
              fontWeight: FontWeight.bold,
              fontSize: 10,
            ),
          ),
        );
      default:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            network.toUpperCase(),
            style: const TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        );
    }
  }
}
