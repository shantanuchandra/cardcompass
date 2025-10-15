import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cardcompass/shared/models/credit_card.dart';
import 'package:cardcompass/core/services/recommendation_service.dart';
import 'package:cardcompass/core/providers/service_providers.dart';

/// Widget for smart transaction analysis using AI
class SmartTransactionAnalyzer extends ConsumerStatefulWidget {
  final String? userId;
  
  const SmartTransactionAnalyzer({
    super.key,
    this.userId,
  });

  @override
  ConsumerState<SmartTransactionAnalyzer> createState() => _SmartTransactionAnalyzerState();
}

class _SmartTransactionAnalyzerState extends ConsumerState<SmartTransactionAnalyzer> {
  final _merchantController = TextEditingController();
  final _amountController = TextEditingController();
  String _selectedCategory = 'dining';
  bool _isAnalyzing = false;
  CardRecommendationResult? _recommendation;

  final List<String> _categories = [
    'dining',
    'fuel',
    'grocery',
    'shopping',
    'travel',
    'entertainment',
    'utilities',
  ];

  @override
  void dispose() {
    _merchantController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(
                  Icons.analytics,
                  color: Theme.of(context).primaryColor,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  'Smart Transaction Analyzer',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Input form
            _buildInputForm(),
            
            const SizedBox(height: 16),
            
            // Analyze button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isAnalyzing ? null : _analyzeTransaction,
                child: _isAnalyzing
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Analyze & Get Best Card'),
              ),
            ),
            
            // Results
            if (_recommendation != null) ...[
              const SizedBox(height: 20),
              _buildRecommendationResult(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInputForm() {
    return Column(
      children: [
        // Merchant name
        TextField(
          controller: _merchantController,
          decoration: const InputDecoration(
            labelText: 'Merchant Name',
            hintText: 'e.g., McDonald\'s, Shell',
            border: OutlineInputBorder(),
          ),
        ),
        
        const SizedBox(height: 12),
        
        // Amount
        TextField(
          controller: _amountController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Amount (₹)',
            hintText: 'e.g., 500',
            border: OutlineInputBorder(),
            prefixText: '₹ ',
          ),
        ),
        
        const SizedBox(height: 12),
        
        // Category dropdown
        DropdownButtonFormField<String>(
          initialValue: _selectedCategory,
          decoration: const InputDecoration(
            labelText: 'Category',
            border: OutlineInputBorder(),
          ),
          items: _categories.map((category) {
            return DropdownMenuItem(
              value: category,
              child: Text(_getCategoryDisplayName(category)),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null) {
              setState(() {
                _selectedCategory = value;
              });
            }
          },
        ),
      ],
    );
  }

  Widget _buildRecommendationResult() {
    final recommendation = _recommendation!;
    
    return Container(
      padding: const EdgeInsets.all(16),      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).primaryColor.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.lightbulb,
                color: Theme.of(context).primaryColor,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'AI Recommendation',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 12),
          
          // Best user card
          if (recommendation.bestUserCard != null) ...[
            _buildCardRecommendationTile(
              'Best Card You Own',
              recommendation.bestUserCard!,
              recommendation.bestUserReward,
              Colors.blue,
            ),
            const SizedBox(height: 8),
          ],
          
          // Best overall card
          if (recommendation.bestOverallCard != null) ...[
            _buildCardRecommendationTile(
              'Best Card Overall',
              recommendation.bestOverallCard!,
              recommendation.bestOverallReward,
              Colors.green,
            ),
            const SizedBox(height: 8),
          ],
          
          // Potential savings
          if (recommendation.potentialSavings > 0) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.savings, color: Colors.orange[700]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Potential Additional Savings',
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '₹${recommendation.potentialSavings.toStringAsFixed(2)}',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.orange[700],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          
          // AI explanation
          if (recommendation.explanation.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: Colors.grey[600], size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      recommendation.explanation,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCardRecommendationTile(
    String title,
    CreditCard card,
    double reward,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.credit_card, color: color, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  card.cardName,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  card.bankName,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '₹${reward.toStringAsFixed(2)}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'Reward',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _analyzeTransaction() async {
    if (_merchantController.text.isEmpty || _amountController.text.isEmpty) {
      _showErrorSnackBar('Please fill in all fields');
      return;
    }

    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      _showErrorSnackBar('Please enter a valid amount');
      return;
    }

    if (widget.userId == null) {
      _showErrorSnackBar('User not authenticated');
      return;
    }

    setState(() {
      _isAnalyzing = true;
      _recommendation = null;
    });

    try {
      final recommendationService = ref.read(recommendationServiceProvider);
      final result = await recommendationService.getBestCardForTransaction(
        userId: widget.userId!,
        merchantName: _merchantController.text.trim(),
        category: _selectedCategory,
        amount: amount,
      );

      setState(() {
        _recommendation = result;
      });
    } catch (error) {
      _showErrorSnackBar('Analysis failed: ${error.toString()}');
    } finally {
      setState(() {
        _isAnalyzing = false;
      });
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  String _getCategoryDisplayName(String category) {
    switch (category) {
      case 'dining':
        return 'Dining & Food';
      case 'fuel':
        return 'Fuel & Gas';
      case 'grocery':
        return 'Grocery & Supermarket';
      case 'shopping':
        return 'Shopping & Retail';
      case 'travel':
        return 'Travel & Transport';
      case 'entertainment':
        return 'Entertainment';
      case 'utilities':
        return 'Utilities & Bills';
      default:
        return category.toUpperCase();
    }
  }
}
