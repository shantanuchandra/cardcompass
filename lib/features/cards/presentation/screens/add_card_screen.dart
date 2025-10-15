import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme.dart';
import '../../../../core/providers/service_providers.dart';
import '../../../../shared/models/credit_card.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../providers/cards_provider.dart';

class AddCardScreen extends ConsumerStatefulWidget {
  const AddCardScreen({super.key});

  @override
  ConsumerState<AddCardScreen> createState() => _AddCardScreenState();
}

class _AddCardScreenState extends ConsumerState<AddCardScreen> {
  final _formKey = GlobalKey<FormState>();
  final _cardNameController = TextEditingController();
  final _bankNameController = TextEditingController();
  final _lastFourDigitsController = TextEditingController();
  final _creditLimitController = TextEditingController();
  
  CardNetwork _selectedNetwork = CardNetwork.visa;
  DateTime? _expiryDate;
  List<Map<String, dynamic>> _identifiedCards = [];
  bool _isLoadingIdentifiedCards = false;

  @override
  void initState() {
    super.initState();
    _loadIdentifiedCards();
  }

  Future<void> _loadIdentifiedCards() async {
    final authState = ref.read(authStateProvider);
    if (!authState.isAuthenticated || authState.user == null) {
      return;
    }

    setState(() {
      _isLoadingIdentifiedCards = true;
    });

    try {
      final cardService = ref.read(cardIdentificationServiceProvider);
      final identifiedCards = await cardService.getIdentifiedButUnassociatedCards(
        authState.user!.id,
      );
      
      setState(() {
        _identifiedCards = identifiedCards;
        _isLoadingIdentifiedCards = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingIdentifiedCards = false;
      });
    }
  }

  @override
  void dispose() {
    _cardNameController.dispose();
    _bankNameController.dispose();
    _lastFourDigitsController.dispose();
    _creditLimitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Credit Card'),
        actions: [
          TextButton(
            onPressed: _saveCard,
            child: const Text('Save'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Card Preview
              Container(
                height: 200,
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 32),
                decoration: BoxDecoration(                  gradient: LinearGradient(
                    colors: [
                      _getNetworkColor(_selectedNetwork).withValues(alpha: 0.8),
                      _getNetworkColor(_selectedNetwork),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _bankNameController.text.isEmpty 
                              ? 'Bank Name' 
                              : _bankNameController.text,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            _selectedNetwork.name.toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        '**** **** **** ${_lastFourDigitsController.text.isEmpty ? '0000' : _lastFourDigitsController.text}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _cardNameController.text.isEmpty 
                              ? 'Card Name' 
                              : _cardNameController.text,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            _expiryDate != null 
                              ? '${_expiryDate!.month.toString().padLeft(2, '0')}/${_expiryDate!.year.toString().substring(2)}'
                              : 'MM/YY',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // Form Fields
              Text(
                'Card Details',
                style: AppTextStyles.heading3,
              ),
              const SizedBox(height: 16),

              // Quick Add Suggestions (for identified cards)
              _buildQuickAddSuggestions(),

              TextFormField(
                controller: _cardNameController,
                decoration: const InputDecoration(
                  labelText: 'Card Name',
                  hintText: 'e.g., HDFC Regalia Credit Card',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter card name';
                  }
                  return null;
                },
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _bankNameController,
                decoration: const InputDecoration(
                  labelText: 'Bank Name',
                  hintText: 'e.g., HDFC Bank',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter bank name';
                  }
                  return null;
                },
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _lastFourDigitsController,
                decoration: const InputDecoration(
                  labelText: 'Last 4 Digits',
                  hintText: '1234',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                maxLength: 4,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter last 4 digits';
                  }
                  if (value.length != 4) {
                    return 'Please enter exactly 4 digits';
                  }
                  return null;
                },
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),

              DropdownButtonFormField<CardNetwork>(
                initialValue: _selectedNetwork,
                decoration: const InputDecoration(
                  labelText: 'Card Network',
                  border: OutlineInputBorder(),
                ),
                items: CardNetwork.values.map((network) {
                  return DropdownMenuItem(
                    value: network,
                    child: Text(network.name.toUpperCase()),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedNetwork = value!;
                  });
                },
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _creditLimitController,
                decoration: const InputDecoration(
                  labelText: 'Credit Limit (₹)',
                  hintText: '500000',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter credit limit';
                  }
                  final limit = double.tryParse(value);
                  if (limit == null || limit <= 0) {
                    return 'Please enter valid credit limit';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              InkWell(
                onTap: _selectExpiryDate,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Expiry Date',
                    border: OutlineInputBorder(),
                  ),
                  child: Text(
                    _expiryDate != null 
                      ? '${_expiryDate!.month.toString().padLeft(2, '0')}/${_expiryDate!.year}'
                      : 'Select expiry date',
                    style: TextStyle(                      color: _expiryDate != null 
                        ? Theme.of(context).colorScheme.onSurface
                        : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ),
              
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Color _getNetworkColor(CardNetwork network) {
    switch (network) {
      case CardNetwork.visa:
        return const Color(0xFF1A1F71);
      case CardNetwork.mastercard:
        return const Color(0xFFEB001B);
      case CardNetwork.rupay:
        return const Color(0xFF0066CC);
      case CardNetwork.amex:
        return const Color(0xFF006FCF);
      case CardNetwork.discover:
        return const Color(0xFFFF6000);
      case CardNetwork.diners:
        return const Color(0xFF0079BE);
    }
  }

  Future<void> _selectExpiryDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year + 2, now.month),
      firstDate: now,
      lastDate: DateTime(now.year + 10),
    );
    
    if (picked != null) {
      setState(() {
        _expiryDate = picked;
      });
    }
  }
  void _saveCard() async {
    if (_formKey.currentState!.validate() && _expiryDate != null) {
      final authState = ref.read(authStateProvider);
      if (!authState.isAuthenticated || authState.user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please log in to add a card'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
        return;
      }

      try {
        // In a real app, this would involve selecting from existing cards in the catalog
        // For now, we'll need to implement proper card addition through the repository
        await ref.read(cardsProvider.notifier).addUserCard(
          userId: authState.user!.id,
          cardId: 'temp_card_id', // This should come from card catalog selection
          lastFourDigits: _lastFourDigitsController.text,
        );
        
        Navigator.of(context).pop();
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Card added successfully!'),
            backgroundColor: AppTheme.successColor,
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error adding card: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } else if (_expiryDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select expiry date'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    }
  }
  Widget _buildQuickAddSuggestions() {
    // Show loading state or empty state if no identified cards
    if (_isLoadingIdentifiedCards) {
      return Container(
        margin: const EdgeInsets.only(bottom: 24),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.blue[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blue[200]!),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, color: Colors.blue[700], size: 20),
                const SizedBox(width: 8),
                Text(
                  'Loading identified cards...',
                  style: TextStyle(
                    color: Colors.blue[700],
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const CircularProgressIndicator(),
          ],
        ),
      );
    }
    
    if (_identifiedCards.isEmpty) {
      return const SizedBox.shrink(); // Don't show anything if no identified cards
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, color: Colors.blue[700], size: 20),
              const SizedBox(width: 8),
              Text(
                'Quick Add - Recently Identified Cards',
                style: TextStyle(
                  color: Colors.blue[700],
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'These cards were identified from your transaction history:',
            style: TextStyle(
              color: Colors.blue[600],
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _identifiedCards.map((card) => _buildQuickAddChip(card)).toList(),
          ),
        ],
      ),
    );
  }
  Widget _buildQuickAddChip(Map<String, dynamic> card) {
    final cardName = card['card_name']?.toString() ?? card['name']?.toString() ?? 'Unknown Card';
    final bankName = card['bank']?.toString() ?? card['bank_name']?.toString() ?? 'Unknown Bank';
    
    return ActionChip(
      avatar: Icon(Icons.credit_card, size: 16, color: Colors.blue[700]),
      label: Text(
        cardName,
        style: TextStyle(
          color: Colors.blue[700],
          fontWeight: FontWeight.w500,
        ),
      ),
      backgroundColor: Colors.white,
      side: BorderSide(color: Colors.blue[300]!),
      onPressed: () => _fillFormWithSuggestion({
        'name': cardName,
        'bank': bankName,
      }),
    );
  }

  void _fillFormWithSuggestion(Map<String, String> card) {
    setState(() {
      _cardNameController.text = card['name']!;
      _bankNameController.text = card['bank']!;
      // You can add more fields as needed
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Pre-filled form with ${card['name']}'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
