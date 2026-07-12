import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

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
    final networkColor = _getNetworkColor(_selectedNetwork);
    
    return Scaffold(
      backgroundColor: const Color(0xFF050B18),
      appBar: AppBar(
        title: Text(
          'ADD CREDIT CARD',
          style: GoogleFonts.spaceGrotesk(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
            fontSize: 16,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saveCard,
            child: Text(
              'SAVE',
              style: GoogleFonts.spaceGrotesk(
                color: AppTheme.primaryColor,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
              ),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // High-tech Cyber Card Preview
              Container(
                height: 200,
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 32),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      networkColor.withValues(alpha: 0.8),
                      networkColor,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.15),
                    width: 1.5,
                  ),
                  boxShadow: AppTheme.neonGlow(color: networkColor, opacity: 0.25, blurRadius: 15),
                ),
                child: Stack(
                  children: [
                    // Holographic diagonal sheen overlay
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              stops: const [0.0, 0.4, 0.45, 0.5, 0.55, 0.6, 1.0],
                              colors: [
                                Colors.transparent,
                                Colors.transparent,
                                Colors.white.withValues(alpha: 0.05),
                                Colors.white.withValues(alpha: 0.12),
                                Colors.white.withValues(alpha: 0.05),
                                Colors.transparent,
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    
                    // Card Details Overlay
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _bankNameController.text.isEmpty 
                                  ? 'BANK NAME' 
                                  : _bankNameController.text.toUpperCase(),
                                style: GoogleFonts.spaceGrotesk(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.5,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  _selectedNetwork.name.toUpperCase(),
                                  style: GoogleFonts.spaceGrotesk(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          Text(
                            '••••  ••••  ••••  ${_lastFourDigitsController.text.isEmpty ? '0000' : _lastFourDigitsController.text}',
                            style: GoogleFonts.spaceGrotesk(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _cardNameController.text.isEmpty 
                                  ? 'CARD NAME' 
                                  : _cardNameController.text.toUpperCase(),
                                style: GoogleFonts.spaceGrotesk(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    'VALID THRU',
                                    style: GoogleFonts.spaceGrotesk(
                                      color: Colors.white38,
                                      fontSize: 7,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    _expiryDate != null 
                                      ? '${_expiryDate!.month.toString().padLeft(2, '0')}/${_expiryDate!.year.toString().substring(2)}'
                                      : 'MM/YY',
                                    style: GoogleFonts.spaceGrotesk(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
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
                dropdownColor: const Color(0xFF0C152B),
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
    if (_isLoadingIdentifiedCards) {
      return Container(
        margin: const EdgeInsets.only(bottom: 24),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF0C152B),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.bolt, color: AppTheme.primaryColor, size: 20),
                const SizedBox(width: 8),
                Text(
                  'DETECTING CREDENTIALS...',
                  style: GoogleFonts.spaceGrotesk(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(AppTheme.primaryColor),
            ),
          ],
        ),
      );
    }
    
    if (_identifiedCards.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF0C152B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.secondaryColor.withValues(alpha: 0.25), width: 1.5),
        boxShadow: AppTheme.neonGlow(color: AppTheme.secondaryColor, opacity: 0.1, blurRadius: 10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bolt, color: AppTheme.primaryColor, size: 20),
              const SizedBox(width: 8),
              Text(
                'AUTO-DETECTED PORTFOLIO',
                style: GoogleFonts.spaceGrotesk(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'We identified these credit cards from your transaction history. Tap to pre-fill the form:',
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white70,
              fontSize: 12,
              height: 1.4,
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
      avatar: const Icon(Icons.add, size: 14, color: AppTheme.primaryColor),
      label: Text(
        cardName.toUpperCase(),
        style: GoogleFonts.spaceGrotesk(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 10,
        ),
      ),
      backgroundColor: const Color(0xFF050B18),
      side: const BorderSide(color: AppTheme.primaryColor, width: 1),
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
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Form populated with ${card['name']}.'),
        backgroundColor: AppTheme.successColor,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
