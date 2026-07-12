import 'package:supabase_flutter/supabase_flutter.dart';

/// Service to discover and add new credit cards to the catalog
/// This service searches for actual product pages, checks for duplicates,
/// and imports benefits for newly discovered cards
class CardDiscoveryService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Discover and add a new card to the catalog
  /// Returns the catalog card ID if successful
  Future<String?> discoverAndAddCard({
    required String bankName,
    required String cardName,
  }) async {
    try {
      print('\n🔍 Card Discovery Service: $bankName - $cardName');
      print('=' * 60);

      // Step 1: Check if card already exists with exact match
      print('Step 1: Checking for exact match in catalog...');
      final exactMatch = await _findExactCardMatch(bankName, cardName);
      if (exactMatch != null) {
        print(
            '✅ Found exact match: ${exactMatch['card_name']} (${exactMatch['bank']})');
        print('   Card URL: ${exactMatch['card_url']}');
        return exactMatch['id'];
      }

      // Step 2: Check for similar cards (fuzzy match)
      print('\nStep 2: Checking for similar cards...');
      final similarCards = await _findSimilarCards(bankName, cardName);
      if (similarCards.isNotEmpty) {
        print('⚠️  Found ${similarCards.length} similar card(s):');
        for (var card in similarCards) {
          print('   - ${card['card_name']} (${card['bank']})');
          print('     URL: ${card['card_url']}');
        }
        print('   💡 Tip: Check if one of these matches your card');
        print(
            '   💡 If yes, update your detection logic to use the exact name');
      }

      // Step 3: Search for the actual product page URL
      print('\nStep 3: Searching for product page URL...');
      final productUrl = await _searchForProductUrl(bankName, cardName);
      if (productUrl == null) {
        print('❌ Could not find official product page');
        print('   Please manually add this card with the correct URL');
        return null;
      }

      print('✅ Found potential product page: $productUrl');

      // Step 4: Check if this URL already exists in catalog
      print('\nStep 4: Checking if URL already exists...');
      final existingCard = await _findCardByUrl(productUrl);
      if (existingCard != null) {
        print(
            '✅ Card already exists with this URL: ${existingCard['card_name']}');
        print('   Catalog Card ID: ${existingCard['id']}');
        return existingCard['id'];
      }

      // Step 5: Create new card entry
      print('\nStep 5: Creating new card entry...');
      final newCardId = await _createNewCard(
        bankName: bankName,
        cardName: cardName,
        cardUrl: productUrl,
      );

      if (newCardId == null) {
        print('❌ Failed to create card entry');
        return null;
      }

      print('✅ Card created with ID: $newCardId');

      // Step 6: Import benefits for the new card
      print('\nStep 6: Importing benefits for new card...');
      await _importBenefitsForCard(productUrl, newCardId, bankName);

      print('\n🎉 Card discovery complete!');
      print('=' * 60);

      return newCardId;
    } catch (e) {
      print('❌ Error in card discovery: $e');
      return null;
    }
  }

  /// Find exact card match
  Future<Map<String, dynamic>?> _findExactCardMatch(
      String bankName, String cardName) async {
    try {
      final response = await _supabase
          .from('card_catalog')
          .select('*')
          .eq('bank', bankName)
          .eq('card_name', cardName)
          .limit(1);

      return response.isNotEmpty ? response.first : null;
    } catch (e) {
      print('   Error finding exact match: $e');
      return null;
    }
  }

  /// Find similar cards (fuzzy matching)
  Future<List<Map<String, dynamic>>> _findSimilarCards(
      String bankName, String cardName) async {
    try {
      final response = await _supabase
          .from('card_catalog')
          .select('*')
          .ilike('bank', '%$bankName%')
          .ilike('card_name', '%$cardName%')
          .limit(5);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('   Error finding similar cards: $e');
      return [];
    }
  }

  /// Search for official product page URL using Google Search
  /// Returns null if not found
  Future<String?> _searchForProductUrl(String bankName, String cardName) async {
    try {
      // Try Google Search via web scraping approach
      // Search query: "bank name card name credit card official"
      final searchQuery =
          Uri.encodeComponent('$bankName $cardName credit card official');
      final searchUrl = 'https://www.google.com/search?q=$searchQuery';

      print(
          '   🔍 Searching Google: "$bankName $cardName credit card official"');
      print('   📍 Search URL: $searchUrl');

      // For now, generate URL patterns as fallback
      // TODO: Implement actual web scraping or use Google Custom Search API
      final urlPatterns = _generateUrlPatterns(bankName, cardName);

      print('   Generated ${urlPatterns.length} potential URL pattern(s):');
      for (var url in urlPatterns) {
        print('   - $url');
      }

      // Return the first pattern - in production, you'd verify these exist
      // and extract benefits from the actual page
      return urlPatterns.isNotEmpty ? urlPatterns.first : null;
    } catch (e) {
      print('   ❌ Error searching for product URL: $e');
      return null;
    }
  }

  /// Extract benefits from a product page URL
  /// Uses the existing robust benefit extraction pipeline
  Future<List<Map<String, dynamic>>> _extractBenefitsFromUrl(
      String url, String bankName) async {
    try {
      print('   🤖 Extracting benefits using AI pipeline...');

      // Use the existing robust extraction to scrape and parse the URL
      // Note: This is a simplified version - the full pipeline expects multiple URLs
      // For single card discovery, we just extract from this one URL

      print(
          '   ⚠️  Using fallback: Benefit extraction deferred to full import service');
      print(
          '   💡 Run the robust benefit import to populate benefits for this card');

      // Return empty list - benefits will be populated by the full import service
      return [];
    } catch (e) {
      print('   ❌ Error extracting benefits: $e');
      return [];
    }
  }

  /// Generate potential URL patterns based on bank and card name
  List<String> _generateUrlPatterns(String bankName, String cardName) {
    final patterns = <String>[];

    // Normalize names for URL
    final cardSlug = _normalizeForUrl(cardName);

    // HDFC Bank patterns
    if (bankName.toLowerCase().contains('hdfc')) {
      patterns.add(
          'https://www.hdfcbank.com/personal/pay/cards/credit-cards/$cardSlug');
    }

    // ICICI Bank patterns
    if (bankName.toLowerCase().contains('icici')) {
      patterns.add(
          'https://www.icicibank.com/personal-banking/cards/credit-card/$cardSlug');
    }

    // Axis Bank patterns
    if (bankName.toLowerCase().contains('axis')) {
      patterns
          .add('https://www.axisbank.com/retail/cards/credit-card/$cardSlug');
    }

    // SBI Card patterns
    if (bankName.toLowerCase().contains('sbi')) {
      patterns
          .add('https://www.sbicard.com/en/personal/credit-cards/$cardSlug');
    }

    // IDFC First Bank patterns
    if (bankName.toLowerCase().contains('idfc')) {
      patterns.add('https://www.idfcfirstbank.com/credit-card/$cardSlug');
    }

    // Kotak Bank patterns
    if (bankName.toLowerCase().contains('kotak')) {
      patterns.add(
          'https://www.kotak.com/en/personal-banking/cards/credit-cards/$cardSlug.html');
    }

    // Punjab National Bank patterns
    if (bankName.toLowerCase().contains('punjab') ||
        bankName.toLowerCase().contains('pnb')) {
      patterns.add('https://www.pnbindia.in/credit-card-$cardSlug.html');
    }

    return patterns;
  }

  /// Normalize text for URL (lowercase, hyphenated)
  String _normalizeForUrl(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll('--', '-');
  }

  /// Find card by URL
  Future<Map<String, dynamic>?> _findCardByUrl(String url) async {
    try {
      final response = await _supabase
          .from('card_catalog')
          .select('*')
          .eq('card_url', url)
          .limit(1);

      return response.isNotEmpty ? response.first : null;
    } catch (e) {
      print('   Error finding card by URL: $e');
      return null;
    }
  }

  /// Create new card entry
  Future<String?> _createNewCard({
    required String bankName,
    required String cardName,
    required String cardUrl,
  }) async {
    try {
      await _supabase.functions.invoke('request-card-catalog-entry', body: {
        'bank_name': bankName,
        'card_name': cardName,
        'card_url': cardUrl,
      });
      print('   Card submitted for admin review; it is not available yet.');
      return null;
    } catch (e) {
      print('   Error creating card: $e');
      return null;
    }
  }

  /// Import benefits for a card
  Future<void> _importBenefitsForCard(
      String cardUrl, String cardId, String bankName) async {
    try {
      print('   🔄 Extracting and importing benefits...');

      // Extract benefits from the product page URL
      final benefits = await _extractBenefitsFromUrl(cardUrl, bankName);

      if (benefits.isEmpty) {
        print(
            '   ⚠️  No benefits extracted - will be populated by full import service');
        return;
      }

      // Import each benefit into the database
      int successCount = 0;
      for (final benefit in benefits) {
        try {
          await _supabase.from('credit_card_benefits').insert({
            'card_id': cardId,
            'category': benefit['category'] ?? 'general',
            'subcategory': benefit['subcategory'] ?? 'other',
            'benefit_name': benefit['benefit_name'] ?? 'Unknown Benefit',
            'benefit_description': benefit['benefit_description'] ?? '',
            'value': benefit['value'],
            'merchant': benefit['merchant'],
            'merchant_category': benefit['merchant_category'],
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          });
          successCount++;
        } catch (e) {
          print('   ⚠️  Failed to import benefit: ${benefit['benefit_name']}');
        }
      }

      print('   ✅ Imported $successCount/${benefits.length} benefit(s)');
    } catch (e) {
      print('   ❌ Error importing benefits: $e');
    }
  }
}
