import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cardcompass/shared/widgets/credit_card_widget.dart';
import 'package:cardcompass/features/cards/providers/cards_provider.dart';
import 'package:cardcompass/shared/widgets/state_widgets.dart';
import 'package:cardcompass/config/routes.dart';
import 'package:cardcompass/core/services/card_identification_service.dart';
import 'package:cardcompass/features/auth/providers/auth_provider.dart';

/// Screen to display all user's credit cards with filtering and search
class CardsListScreen extends ConsumerStatefulWidget {
  const CardsListScreen({super.key});

  @override
  ConsumerState<CardsListScreen> createState() => _CardsListScreenState();
}

class _CardsListScreenState extends ConsumerState<CardsListScreen> {
  String _searchQuery = '';
  String _selectedBankFilter = 'All';
  String _selectedTypeFilter = 'All';
  final CardIdentificationService _cardIdService = CardIdentificationService();
  List<String> _suggestedCardNames = [];
  @override
  void initState() {
    super.initState();
    _loadSuggestedCards();
    // Load user cards when screen initializes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadUserCards();
    });
  }

  Future<void> _loadUserCards() async {
    final authState = ref.read(authStateProvider);
    if (authState.isAuthenticated && authState.user != null) {
      await ref.read(cardsProvider.notifier).loadUserCards(authState.user!.id);
    }
  }

  Future<void> _loadSuggestedCards() async {
    final authState = ref.read(authStateProvider);
    if (authState.isAuthenticated && authState.user != null) {
      try {
        final suggestions = await _cardIdService.getCardNamesFromTransactions(authState.user!.id);
        if (mounted) {
          setState(() {
            _suggestedCardNames = suggestions;
          });
        }
      } catch (e) {
        // Handle error silently
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cards = ref.watch(cardsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Cards'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () {
              Navigator.pushNamed(context, AppRoutes.addCard);
            },
          ),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: _showSearchDialog,
          ),
        ],
      ),      body: Column(
        children: [
          // Filters
          _buildFilters(),
          
          // Card Suggestions Section
          if (_suggestedCardNames.isNotEmpty) _buildCardSuggestions(),
          
          // Cards List
          Expanded(child: cards.isEmpty
                ? const EmptyState(
                    title: 'No credit cards found',
                    message: 'Add your first credit card to get started',
                    icon: Icons.credit_card,
                  )
                : Builder(
                    builder: (context) {
                      // Apply filters
                      final filteredCards = cards.where((card) {
                        final matchesSearch = card.cardName
                            .toLowerCase()
                            .contains(_searchQuery.toLowerCase()) ||
                            card.bankName
                                .toLowerCase()
                                .contains(_searchQuery.toLowerCase());
                        
                        final matchesBank = _selectedBankFilter == 'All' ||
                            card.bankName == _selectedBankFilter;
                        
                        final matchesType = _selectedTypeFilter == 'All' ||
                            card.type.name == _selectedTypeFilter.toLowerCase();

                        return matchesSearch && matchesBank && matchesType;
                      }).toList();

                      if (filteredCards.isEmpty) {                        return const EmptyState(
                          title: 'No cards match your filters',
                          message: 'Try adjusting your search or filters',
                          icon: Icons.filter_list_off,
                        );
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: filteredCards.length,
                        itemBuilder: (context, index) {
                          final card = filteredCards[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: GestureDetector(
                              onTap: () {
                                Navigator.pushNamed(
                                  context,
                                  AppRoutes.cardDetails,
                                  arguments: card.id,
                                );
                              },
                              child: Hero(
                                tag: 'card_${card.id}',                                child: CreditCardWidget(
                                  cardName: card.cardName,
                                  bankName: card.bankName,
                                  lastFourDigits: card.cardNumber ?? '****',
                                  expiryDate: card.expiryDate != null 
                                      ? '${card.expiryDate!.month.toString().padLeft(2, '0')}/${card.expiryDate!.year.toString().substring(2)}'
                                      : 'XX/XX',
                                  cardType: card.network.name.toUpperCase(),
                                  gradientColors: _getCardGradient(card.network.name),
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.pushNamed(context, AppRoutes.addCard);
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildFilters() {
    final cards = ref.watch(cardsProvider);
    
    if (cards.isEmpty) return const SizedBox.shrink();

    // Get unique banks and types
    final banks = {'All', ...cards.map((c) => c.bankName).toSet()};
    final types = {'All', ...cards.map((c) => c.type.name.toUpperCase()).toSet()};

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Search bar
          if (_searchQuery.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.search,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Search: $_searchQuery',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.clear, size: 16),
                    onPressed: () {
                      setState(() {
                        _searchQuery = '';
                      });
                    },
                  ),
                ],
              ),
            ),
          
          // Filter chips
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      // Bank filter
                      DropdownButton<String>(
                        value: _selectedBankFilter,
                        onChanged: (value) {
                          setState(() {
                            _selectedBankFilter = value ?? 'All';
                          });
                        },
                        items: banks.map((bank) {
                          return DropdownMenuItem<String>(
                            value: bank,
                            child: Text(bank),
                          );
                        }).toList(),
                      ),
                      
                      const SizedBox(width: 16),
                      
                      // Type filter
                      DropdownButton<String>(
                        value: _selectedTypeFilter,
                        onChanged: (value) {
                          setState(() {
                            _selectedTypeFilter = value ?? 'All';
                          });
                        },
                        items: types.map((type) {
                          return DropdownMenuItem<String>(
                            value: type,
                            child: Text(type),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),
              
              // Clear filters
              if (_selectedBankFilter != 'All' || _selectedTypeFilter != 'All')
                TextButton(
                  onPressed: () {
                    setState(() {
                      _selectedBankFilter = 'All';
                      _selectedTypeFilter = 'All';
                    });
                  },
                  child: const Text('Clear'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _showSearchDialog() {
    showDialog(
      context: context,
      builder: (context) {
        String query = _searchQuery;
        return AlertDialog(
          title: const Text('Search Cards'),
          content: TextField(
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Enter card or bank name...',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (value) {
              query = value;
            },
            controller: TextEditingController(text: _searchQuery),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  _searchQuery = query;
                });
                Navigator.pop(context);
              },
              child: const Text('Search'),
            ),
          ],
        );
      },
    );
  }

  /// Build card suggestions section
  Widget _buildCardSuggestions() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
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
              Icon(Icons.lightbulb_outline, color: Colors.blue[700], size: 20),
              const SizedBox(width: 8),
              Text(
                'Cards Found in Your Transactions',
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
            'We found these cards mentioned in your transaction history. Add them to track rewards and benefits:',
            style: TextStyle(
              color: Colors.blue[600],
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _suggestedCardNames.map((cardName) => _buildSuggestionChip(cardName)).toList(),
          ),
        ],
      ),
    );
  }

  /// Build a suggestion chip for a card
  Widget _buildSuggestionChip(String cardName) {
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
      onPressed: () => _showAddCardDialog(cardName),
    );
  }

  /// Show dialog to add suggested card
  void _showAddCardDialog(String cardName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Card'),
        content: Text('Would you like to add "$cardName" to your cards?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _addSuggestedCard(cardName);
            },
            child: const Text('Add Card'),
          ),
        ],
      ),
    );
  }

  /// Add suggested card to user's account
  Future<void> _addSuggestedCard(String cardName) async {
    final authState = ref.read(authStateProvider);
    if (!authState.isAuthenticated || authState.user == null) return;

    try {
      await _cardIdService.autoAssociateCard(
        userId: authState.user!.id,
        cardName: cardName,
      );

      // Refresh cards list
      await ref.read(cardsProvider.notifier).loadUserCards(authState.user!.id);
      
      // Remove from suggestions
      setState(() {
        _suggestedCardNames.remove(cardName);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$cardName added successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add card: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  List<Color> _getCardGradient(String network) {
    switch (network.toLowerCase()) {
      case 'visa':
        return [Colors.blue.shade400, Colors.blue.shade600];
      case 'mastercard':
        return [Colors.orange.shade400, Colors.red.shade500];
      case 'rupay':
        return [Colors.green.shade400, Colors.green.shade600];
      case 'amex':
        return [Colors.grey.shade600, Colors.grey.shade800];
      default:
        return [Colors.purple.shade400, Colors.purple.shade600];
    }
  }
}
