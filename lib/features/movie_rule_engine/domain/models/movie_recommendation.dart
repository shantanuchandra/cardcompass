import 'transaction_step.dart';

/// Complete recommendation for optimized movie ticket purchase
class MovieRecommendation {
  final List<TransactionStep> steps;
  final double totalAmount;
  final double totalSavings;
  final double finalAmount;
  final String explanation;
  final DateTime calculatedAt;
  final Map<String, dynamic>? metadata;

  const MovieRecommendation({
    required this.steps,
    required this.totalAmount,
    required this.totalSavings,
    required this.finalAmount,
    required this.explanation,
    required this.calculatedAt,
    this.metadata,
  });

  double get savingsPercentage => 
      totalAmount > 0 ? (totalSavings / totalAmount) * 100 : 0;

  int get totalTickets => steps.fold(0, (sum, step) => sum + step.ticketCount);

  bool get hasRecommendations => steps.isNotEmpty;

  /// Get top 3 recommendations (steps are already sorted by efficiency)
  List<TransactionStep> get topRecommendations => 
      steps.take(3).toList();

  Map<String, dynamic> toJson() => {
    'steps': steps.map((step) => step.toJson()).toList(),
    'totalAmount': totalAmount,
    'totalSavings': totalSavings,
    'finalAmount': finalAmount,
    'explanation': explanation,
    'calculatedAt': calculatedAt.toIso8601String(),
    'savingsPercentage': savingsPercentage,
    'totalTickets': totalTickets,
    'hasRecommendations': hasRecommendations,
    'metadata': metadata,
  };

  factory MovieRecommendation.fromJson(Map<String, dynamic> json) {
    return MovieRecommendation(
      steps: (json['steps'] as List<dynamic>?)
          ?.map((step) => TransactionStep.fromJson(step))
          .toList() ?? [],
      totalAmount: (json['totalAmount'] ?? 0.0).toDouble(),
      totalSavings: (json['totalSavings'] ?? 0.0).toDouble(),
      finalAmount: (json['finalAmount'] ?? 0.0).toDouble(),
      explanation: json['explanation'] ?? '',
      calculatedAt: DateTime.parse(json['calculatedAt'] ?? DateTime.now().toIso8601String()),
      metadata: json['metadata'],
    );
  }

  /// Create an empty recommendation when no benefits are found
  factory MovieRecommendation.empty({
    required double totalAmount,
    required int tickets,
  }) {
    return MovieRecommendation(
      steps: [],
      totalAmount: totalAmount,
      totalSavings: 0.0,
      finalAmount: totalAmount,
      explanation: 'No suitable movie benefits found for $tickets tickets worth ₹$totalAmount. '
          'Consider using a general cashback card for basic rewards.',
      calculatedAt: DateTime.now(),
    );
  }

  @override
  String toString() => 'MovieRecommendation('
      '$totalTickets tickets, '
      '₹$totalAmount → ₹$finalAmount, '
      'saved ₹$totalSavings (${savingsPercentage.toStringAsFixed(1)}%)'
      ')';
}
