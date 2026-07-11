import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cardcompass/shared/widgets/credit_card_widget.dart';
import 'package:cardcompass/features/cards/providers/cards_provider.dart';
import 'package:cardcompass/shared/widgets/state_widgets.dart';
import 'package:cardcompass/config/routes.dart';
import 'package:cardcompass/core/services/card_identification_service.dart';
import 'package:cardcompass/features/auth/providers/auth_provider.dart';
import 'package:cardcompass/core/theme.dart';

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
      backgroundColor: const Color(0xFF050B18),
      appBar: AppBar(
        title: Text(
          'MY PORTFOLIO',
          style: GoogleFonts.spaceGrotesk(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline, color: AppTheme.primaryColor),
            onPressed: () {
              Navigator.pushNamed(context, AppRoutes.addCard);
            },
          ),
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white70),
            onPressed: _showSearchDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          // Filters
          _buildFilters(),
          
          // Card Suggestions Section
          if (_suggestedCardNames.isNotEmpty) _buildCardSuggestions(),
          
          // Cards List
          Expanded(
            child: cards.isEmpty
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

                      if (filteredCards.isEmpty) {
                        return const EmptyState(
                          title: 'No cards match filters',
                          message: 'Try adjusting your search or filter tags',
                          icon: Icons.filter_list_off,
                        );
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                        itemCount: filteredCards.length,
                        itemBuilder: (context, index) {
                          final card = filteredCards[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 20),
                            child: GestureDetector(
                              onTap: () {
                                Navigator.pushNamed(
                                  context,
                                  AppRoutes.cardDetails,
                                  arguments: card.id,
                                );
                              },
                              child: Hero(
                                tag: 'card_${card.id}',
                                child: CreditCardWidget(
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
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 80), // Space above dock
        child: FloatingActionButton(
          onPressed: () {
            Navigator.pushNamed(context, AppRoutes.addCard);
          },
          backgroundColor: AppTheme.primaryColor,
          foregroundColor: const Color(0xFF050B18),
          elevation: 6,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: const Icon(Icons.add, size: 28),
        ),
      ),
    );
  }

  Widget _buildFilters() {
    final cards = ref.watch(cardsProvider);
    if (cards.isEmpty) return const SizedBox.shrink();

    final banks = {'All', ...cards.map((c) => c.bankName).toSet()};
    final types = {'All', ...cards.map((c) => c.type.name.toUpperCase()).toSet()};

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0C152B).withValues(alpha: 0.5),
        border: const Border(bottom: BorderSide(color: Color(0xFF1E293B), width: 1)),
      ),
      child: Column(
        children: [
          // Active Search Chip
          if (_searchQuery.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, size: 14, color: AppTheme.primaryColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Search: $_searchQuery',
                      style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 12),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _searchQuery = ''),
                    child: const Icon(Icons.clear, size: 14, color: Colors.white60),
                  ),
                ],
              ),
            ),
          
          // Capsule Dropdown Filter selectors
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      // Bank Dropdown
                      _buildDropdownWrapper(
                        icon: Icons.account_balance,
                        child: DropdownButton<String>(
                          value: _selectedBankFilter,
                          dropdownColor: const Color(0xFF0C152B),
                          underline: const SizedBox.shrink(),
                          icon: const Icon(Icons.arrow_drop_down, color: AppTheme.primaryColor, size: 16),
                          style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                          onChanged: (value) {
                            setState(() {
                              _selectedBankFilter = value ?? 'All';
                            });
                          },
                          items: banks.map((bank) {
                            return DropdownMenuItem<String>(
                              value: bank,
                              child: Text(bank.toUpperCase()),
                            );
                          }).toList(),
                        ),
                      ),
                      
                      const SizedBox(width: 12),
                      
                      // Type Dropdown
                      _buildDropdownWrapper(
                        icon: Icons.credit_card,
                        child: DropdownButton<String>(
                          value: _selectedTypeFilter,
                          dropdownColor: const Color(0xFF0C152B),
                          underline: const SizedBox.shrink(),
                          icon: const Icon(Icons.arrow_drop_down, color: AppTheme.primaryColor, size: 16),
                          style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
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
                      ),
                    ],
                  ),
                ),
              ),
              
              if (_selectedBankFilter != 'All' || _selectedTypeFilter != 'All') ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _selectedBankFilter = 'All';
                      _selectedTypeFilter = 'All';
                    });
                  },
                  child: Text(
                    'RESET',
                    style: GoogleFonts.spaceGrotesk(
                      color: AppTheme.accentColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownWrapper({required IconData icon, required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0C152B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.primaryColor),
          const SizedBox(width: 6),
          child,
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
          backgroundColor: const Color(0xFF0C152B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFF1E293B)),
          ),
          title: Text(
            'SEARCH PORTFOLIO',
            style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          content: TextField(
            autofocus: true,
            style: GoogleFonts.plusJakartaSans(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Enter card or bank...',
              hintStyle: GoogleFonts.plusJakartaSans(color: Colors.white30),
              prefixIcon: const Icon(Icons.search, color: AppTheme.primaryColor),
            ),
            onChanged: (value) {
              query = value;
            },
            controller: TextEditingController(text: _searchQuery),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('CANCEL', style: GoogleFonts.spaceGrotesk(color: Colors.white70)),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  _searchQuery = query;
                });
                Navigator.pop(context);
              },
              child: Text('SEARCH', style: GoogleFonts.spaceGrotesk(color: AppTheme.primaryColor, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCardSuggestions() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
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
            'We identified credit cards from your bank statements. Tap to add them to your tracking center:',
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
            children: _suggestedCardNames.map((cardName) => _buildSuggestionChip(cardName)).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionChip(String cardName) {
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
      onPressed: () => _showAddCardDialog(cardName),
    );
  }

  void _showAddCardDialog(String cardName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0C152B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFF1E293B)),
        ),
        title: Text(
          'IMPORT DETECTED CARD',
          style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: Text(
          'Do you want to import "$cardName" into your active portfolio?',
          style: GoogleFonts.plusJakartaSans(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('CANCEL', style: GoogleFonts.spaceGrotesk(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _addSuggestedCard(cardName);
            },
            child: Text('IMPORT', style: GoogleFonts.spaceGrotesk(color: AppTheme.primaryColor, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _addSuggestedCard(String cardName) async {
    final authState = ref.read(authStateProvider);
    if (!authState.isAuthenticated || authState.user == null) return;

    try {
      await _cardIdService.autoAssociateCard(
        userId: authState.user!.id,
        cardName: cardName,
      );

      await ref.read(cardsProvider.notifier).loadUserCards(authState.user!.id);
      
      setState(() {
        _suggestedCardNames.remove(cardName);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$cardName imported successfully!'),
            backgroundColor: AppTheme.successColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to import card: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  List<Color> _getCardGradient(String network) {
    switch (network.toLowerCase()) {
      case 'visa':
        return [const Color(0xFF1A1F71), const Color(0xFF3D4ED8)];
      case 'mastercard':
        return [const Color(0xFFEB001B), const Color(0xFFF79E1B)];
      case 'rupay':
        return [const Color(0xFF00A851), const Color(0xFF6CBF2F)];
      case 'amex':
        return [const Color(0xFF006FCF), const Color(0xFF016FD0)];
      default:
        return [const Color(0xFF6366F1), const Color(0xFF8B5CF6)];
    }
  }
}
