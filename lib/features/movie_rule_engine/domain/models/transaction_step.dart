/// A single transaction step in the optimized movie ticket purchase strategy
class TransactionStep {
  final String platform;
  final String cardName;
  final String cardId;
  final int ticketCount;
  final double amount;
  final double savings;
  final String benefitType; // BOGO, PERCENT_DISCOUNT, CASHBACK, MILESTONE
  final String explanation;
  final Map<String, dynamic>? benefitDetails;

  const TransactionStep({
    required this.platform,
    required this.cardName,
    required this.cardId,
    required this.ticketCount,
    required this.amount,
    required this.savings,
    required this.benefitType,
    required this.explanation,
    this.benefitDetails,
  });

  double get effectiveAmount => amount - savings;
  double get savingsPercentage => amount > 0 ? (savings / amount) * 100 : 0;

  Map<String, dynamic> toJson() => {
    'platform': platform,
    'cardName': cardName,
    'cardId': cardId,
    'ticketCount': ticketCount,
    'amount': amount,
    'savings': savings,
    'benefitType': benefitType,
    'explanation': explanation,
    'effectiveAmount': effectiveAmount,
    'savingsPercentage': savingsPercentage,
    'benefitDetails': benefitDetails,
  };

  factory TransactionStep.fromJson(Map<String, dynamic> json) {
    return TransactionStep(
      platform: json['platform'] ?? '',
      cardName: json['cardName'] ?? '',
      cardId: json['cardId'] ?? '',
      ticketCount: json['ticketCount'] ?? 0,
      amount: (json['amount'] ?? 0.0).toDouble(),
      savings: (json['savings'] ?? 0.0).toDouble(),
      benefitType: json['benefitType'] ?? '',
      explanation: json['explanation'] ?? '',
      benefitDetails: json['benefitDetails'],
    );
  }

  @override
  String toString() => 'TransactionStep('
      '$ticketCount tickets via $cardName on $platform: '
      '₹$amount - ₹$savings = ₹$effectiveAmount'
      ')';
}
