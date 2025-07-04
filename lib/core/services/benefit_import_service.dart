import 'dart:io';
import 'package:csv/csv.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cardcompass/core/services/gemini_transaction_parser.dart';

/// Service for importing card benefits from CSV files
class BenefitImportService {
  final SupabaseClient _supabase = Supabase.instance.client;  /// Import benefits from the enhanced_credit_cards.csv file
  Future<Map<String, dynamic>> importFromEnhancedCsv() async {
    try {
      print('🔄 Starting benefit import from enhanced_credit_cards.csv...');

      // Check if required tables exist
      bool tablesExist = await _checkTablesExist();
      if (!tablesExist) {
        return {
          'success': false,
          'message': 'Database tables missing. Please run database setup first.',
          'error': 'Required tables (benefit_categories, benefits, card_benefits) do not exist',
          'cards_processed': 0,
          'benefits_created': 0,
          'total_csv_records': 0,
        };
      }

      // First, create default benefit categories if they don't exist
      await _createDefaultBenefitCategories();

      // Then create default benefits
      await _createDefaultBenefits();      // Load and parse the CSV data
      String csvData;
      try {
        print('📂 Attempting to load CSV from assets...');
        csvData = await rootBundle.loadString('assets/enhanced_credit_cards.csv');
        print('✅ CSV loaded from assets: ${csvData.length} characters');
      } catch (e) {
        print('⚠️ Failed to load from assets: $e');
        print('📂 Trying to load from project root...');
        // If asset not found, try reading from project root
        final file = File('enhanced_credit_cards.csv');
        if (await file.exists()) {
          csvData = await file.readAsString();
          print('✅ CSV loaded from project root: ${csvData.length} characters');
        } else {
          print('❌ CSV file not found in project root either');
          throw Exception('enhanced_credit_cards.csv not found in assets or project root');
        }
      }      List<List<dynamic>> rows = const CsvToListConverter().convert(csvData);
      
      print('📊 CSV parsed: ${rows.length} total rows');
      
      if (rows.isEmpty) {
        throw Exception('CSV file is empty');
      }
      
      // Debug: Show first few characters to check format
      print('📝 CSV first 200 characters: ${csvData.substring(0, csvData.length > 200 ? 200 : csvData.length)}');
      
      // If we only got 1 row, try different parsing approach
      if (rows.length == 1) {
        print('⚠️ Only 1 row detected, trying alternative parsing...');
        
        // Try splitting by newlines first
        List<String> lines = csvData.split('\n');
        if (lines.length == 1) {
          lines = csvData.split('\r\n'); // Try Windows line endings
        }
        if (lines.length == 1) {
          lines = csvData.split('\r'); // Try Mac line endings
        }
        
        print('📊 Found ${lines.length} lines after manual split');
        
        if (lines.length > 1) {
          // Parse each line as CSV
          rows = [];
          for (String line in lines) {
            if (line.trim().isNotEmpty) {
              List<dynamic> row = line.split(',');
              rows.add(row);
            }
          }
          print('📊 Manual parsing resulted in ${rows.length} rows');
        }
      }

      // Extract headers and remove them from rows
      List<String> headers = rows.first.map((e) => e.toString()).toList();
      rows.removeAt(0);
      
      print('📋 Headers: ${headers.join(', ')}');
      print('📊 Processing ${rows.length} card records from CSV...');

      // Get all cards from database to match with CSV data
      final existingCards = await _getAllCardsFromDatabase();
      
      int cardsProcessed = 0;
      int benefitsCreated = 0;      // Process each row and create card benefits
      for (var row in rows) {
        final Map<String, dynamic> rowMap = _rowToMap(row, headers);
        final rawCardName = rowMap['Card Name']?.toString() ?? '';
        final rawBankName = rowMap['Bank']?.toString() ?? '';        if (rawCardName.isNotEmpty && rawBankName.isNotEmpty) {
          // Apply name normalization
          final normalizedBankName = GeminiTransactionParser.normalizeBankName(rawBankName);
          final cardVariantName = GeminiTransactionParser.normalizeCardName(rawCardName, normalizedBankName);
          
          print('🔄 Processing: $rawCardName ($rawBankName) -> $cardVariantName ($normalizedBankName)');
          
          // First try to find matching card in database
          final matchingCards = existingCards.where((card) => 
            card['card_name'].toString().toLowerCase().contains(cardVariantName.toLowerCase()) ||
            cardVariantName.toLowerCase().contains(card['card_name'].toString().toLowerCase()) ||
            card['card_name'].toString().toLowerCase().contains(rawCardName.toLowerCase()) ||
            rawCardName.toLowerCase().contains(card['card_name'].toString().toLowerCase())
          ).toList();

          String cardId;
          
          if (matchingCards.isNotEmpty) {
            cardId = matchingCards.first['id'];
            print('✅ Found existing card: $cardVariantName');
          } else {
            // Create new card if not found
            print('🆕 Creating new card: $cardVariantName ($normalizedBankName)');
            final newCard = await _createCard(cardVariantName, normalizedBankName);
            if (newCard != null) {
              cardId = newCard['id'];
              existingCards.add(newCard); // Add to list for future matches
            } else {
              print('❌ Failed to create card: $cardVariantName');
              continue;
            }
          }
          
          // Create benefits for this card
          final benefitsCount = await _createCardBenefits(cardId, cardVariantName, normalizedBankName);
          benefitsCreated += benefitsCount;
          cardsProcessed++;
        }
      }

      final result = {
        'success': true,
        'message': 'Benefit import completed successfully',
        'cards_processed': cardsProcessed,
        'benefits_created': benefitsCreated,
        'total_csv_records': rows.length,
      };

      print('✅ Import completed: $result');
      return result;

    } catch (e) {
      final errorResult = {
        'success': false,
        'message': 'Import failed: ${e.toString()}',
        'error': e.toString(),
      };
      print('❌ Import failed: $e');
      return errorResult;
    }
  }

  /// Create default benefit categories
  Future<void> _createDefaultBenefitCategories() async {
    final categories = [
      {'code': 'DINING', 'name': 'Dining & Food', 'description': 'Restaurants, food delivery, and dining'},
      {'code': 'TRAVEL', 'name': 'Travel & Transportation', 'description': 'Flights, hotels, cab rides, and travel'},
      {'code': 'FUEL', 'name': 'Fuel & Petrol', 'description': 'Petrol pumps and fuel stations'},
      {'code': 'SHOPPING', 'name': 'Shopping & E-commerce', 'description': 'Online and offline shopping'},
      {'code': 'GROCERY', 'name': 'Grocery & Supermarket', 'description': 'Grocery stores and supermarkets'},
      {'code': 'ENTERTAINMENT', 'name': 'Entertainment', 'description': 'Movies, streaming, and entertainment'},
      {'code': 'UTILITIES', 'name': 'Utilities & Bills', 'description': 'Electricity, mobile, and utility bills'},
      {'code': 'HEALTHCARE', 'name': 'Healthcare', 'description': 'Medical expenses and healthcare'},
      {'code': 'GENERAL', 'name': 'General Purchases', 'description': 'All other purchases'},
    ];

    for (final categoryData in categories) {
      try {        // Check if category already exists
        final existing = await _supabase
            .from('benefit_categories')
            .select('category_code')
            .eq('category_code', categoryData['code'] as String)
            .maybeSingle();

        if (existing == null) {
          await _supabase.from('benefit_categories').insert({
            'category_code': categoryData['code'],
            'name': categoryData['name'],
            'description': categoryData['description'],
            'is_active': true,
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          });
          print('✅ Created category: ${categoryData['name']}');
        }
      } catch (e) {
        print('⚠️ Error creating category ${categoryData['name']}: $e');
      }
    }
  }

  /// Create default benefits
  Future<void> _createDefaultBenefits() async {
    final benefits = [
      {'category': 'DINING', 'name': 'Dining Cashback', 'method': 'percentage', 'value': 5.0},
      {'category': 'DINING', 'name': 'Food Delivery Rewards', 'method': 'percentage', 'value': 4.0},
      {'category': 'TRAVEL', 'name': 'Travel Miles', 'method': 'points', 'value': 2.0},
      {'category': 'TRAVEL', 'name': 'Airport Lounge Access', 'method': 'boolean', 'value': 1.0},
      {'category': 'FUEL', 'name': 'Fuel Surcharge Waiver', 'method': 'percentage', 'value': 1.0},
      {'category': 'FUEL', 'name': 'Fuel Rewards', 'method': 'percentage', 'value': 2.5},
      {'category': 'SHOPPING', 'name': 'Shopping Cashback', 'method': 'percentage', 'value': 2.0},
      {'category': 'SHOPPING', 'name': 'E-commerce Rewards', 'method': 'percentage', 'value': 3.0},
      {'category': 'GROCERY', 'name': 'Grocery Cashback', 'method': 'percentage', 'value': 2.5},
      {'category': 'ENTERTAINMENT', 'name': 'Movie Ticket Discount', 'method': 'percentage', 'value': 15.0},
      {'category': 'UTILITIES', 'name': 'Bill Payment Cashback', 'method': 'percentage', 'value': 1.0},
      {'category': 'HEALTHCARE', 'name': 'Healthcare Benefits', 'method': 'percentage', 'value': 1.5},
      {'category': 'GENERAL', 'name': 'General Purchase Rewards', 'method': 'percentage', 'value': 1.0},
    ];

    for (final benefitData in benefits) {
      try {        // Check if benefit already exists
        final existing = await _supabase
            .from('benefits')
            .select('id')
            .eq('category_code', benefitData['category'] as String)
            .eq('name', benefitData['name'] as String)
            .maybeSingle();

        if (existing == null) {
          await _supabase.from('benefits').insert({
            'category_code': benefitData['category'],
            'name': benefitData['name'],
            'description': 'Earn ${benefitData['value']}% on ${benefitData['category']?.toString().toLowerCase()} purchases',
            'calculation_method': benefitData['method'],
            'default_value': benefitData['value'],
            'is_active': true,
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          });
          print('✅ Created benefit: ${benefitData['name']}');
        }
      } catch (e) {
        print('⚠️ Error creating benefit ${benefitData['name']}: $e');
      }
    }
  }

  /// Get all cards from database
  Future<List<Map<String, dynamic>>> _getAllCardsFromDatabase() async {
    try {
      // Try to get from card_catalog first (new schema)
      final catalogResponse = await _supabase
          .from('card_catalog')
          .select('id, card_name, bank');
      
      if (catalogResponse.isNotEmpty) {
        return List<Map<String, dynamic>>.from(catalogResponse);
      }

      // Use card_catalog table
      final cardsResponse = await _supabase
          .from('card_catalog')
          .select('id, card_name, bank_name');
      
      return List<Map<String, dynamic>>.from(cardsResponse);
    } catch (e) {
      print('⚠️ Error fetching cards: $e');
      return [];
    }
  }

  /// Create card benefits for a specific card
  Future<int> _createCardBenefits(String cardId, String cardName, String bankName) async {
    int benefitsCreated = 0;

    // Define benefit mapping based on card characteristics
    final benefitMappings = _getBenefitMappingsForCard(cardName, bankName);

    for (final mapping in benefitMappings) {
      try {
        // Get benefit ID
        final benefitResponse = await _supabase
            .from('benefits')
            .select('id')
            .eq('category_code', mapping['category'])
            .eq('name', mapping['benefit_name'])
            .maybeSingle();

        if (benefitResponse != null) {
          final benefitId = benefitResponse['id'];

          // Check if card benefit already exists
          final existingCardBenefit = await _supabase
              .from('card_benefits')
              .select('id')
              .eq('card_id', cardId)
              .eq('benefit_id', benefitId)
              .maybeSingle();

          if (existingCardBenefit == null) {
            await _supabase.from('card_benefits').insert({
              'card_id': cardId,
              'benefit_id': benefitId,
              'value': mapping['value'],
              'spending_categories': mapping['categories'],
              'monthly_cap': mapping['monthly_cap'],
              'annual_cap': mapping['annual_cap'],
              'is_active': true,
            });
            benefitsCreated++;
            print('✅ Created card benefit: ${mapping['benefit_name']} for $cardName');
          }
        }
      } catch (e) {
        print('⚠️ Error creating card benefit for $cardName: $e');
      }
    }

    return benefitsCreated;
  }
  /// Get benefit mappings for a card based on its name and bank
  List<Map<String, dynamic>> _getBenefitMappingsForCard(String cardName, String bankName) {
    final cardLower = cardName.toLowerCase();
    
    List<Map<String, dynamic>> mappings = [];

    // General benefits for all cards
    mappings.add({
      'category': 'GENERAL',
      'benefit_name': 'General Purchase Rewards',
      'value': 1.0,
      'categories': ['all'],
      'monthly_cap': null,
      'annual_cap': null,
    });

    // Dining benefits
    if (cardLower.contains('dining') || cardLower.contains('food') || 
        cardLower.contains('zomato') || cardLower.contains('swiggy')) {
      mappings.add({
        'category': 'DINING',
        'benefit_name': 'Dining Cashback',
        'value': 5.0,
        'categories': ['dining', 'food'],
        'monthly_cap': 2000.0,
        'annual_cap': null,
      });
    } else {
      mappings.add({
        'category': 'DINING',
        'benefit_name': 'Dining Cashback',
        'value': 2.0,
        'categories': ['dining'],
        'monthly_cap': 1000.0,
        'annual_cap': null,
      });
    }

    // Travel benefits
    if (cardLower.contains('travel') || cardLower.contains('miles') || 
        cardLower.contains('vistara') || cardLower.contains('air')) {
      mappings.addAll([
        {
          'category': 'TRAVEL',
          'benefit_name': 'Travel Miles',
          'value': 4.0,
          'categories': ['travel', 'flights'],
          'monthly_cap': null,
          'annual_cap': 50000.0,
        },
        {
          'category': 'TRAVEL',
          'benefit_name': 'Airport Lounge Access',
          'value': 1.0,
          'categories': ['travel'],
          'monthly_cap': null,
          'annual_cap': null,
        },
      ]);
    }

    // Fuel benefits
    if (cardLower.contains('fuel') || cardLower.contains('petrol') || 
        cardLower.contains('hpcl') || cardLower.contains('iocl')) {
      mappings.add({
        'category': 'FUEL',
        'benefit_name': 'Fuel Rewards',
        'value': 2.5,
        'categories': ['fuel'],
        'monthly_cap': 1500.0,
        'annual_cap': null,
      });
    } else {
      mappings.add({
        'category': 'FUEL',
        'benefit_name': 'Fuel Surcharge Waiver',
        'value': 1.0,
        'categories': ['fuel'],
        'monthly_cap': 500.0,
        'annual_cap': null,
      });
    }

    // Shopping benefits
    if (cardLower.contains('shopping') || cardLower.contains('amazon') || 
        cardLower.contains('flipkart') || cardLower.contains('e-commerce')) {
      mappings.add({
        'category': 'SHOPPING',
        'benefit_name': 'E-commerce Rewards',
        'value': 3.0,
        'categories': ['shopping', 'e-commerce'],
        'monthly_cap': 2500.0,
        'annual_cap': null,
      });
    } else {
      mappings.add({
        'category': 'SHOPPING',
        'benefit_name': 'Shopping Cashback',
        'value': 2.0,
        'categories': ['shopping'],
        'monthly_cap': 1500.0,
        'annual_cap': null,
      });
    }

    // Premium card benefits
    if (cardLower.contains('premium') || cardLower.contains('infinite') || 
        cardLower.contains('signature') || cardLower.contains('elite') ||
        cardLower.contains('platinum') || cardLower.contains('black')) {
      mappings.add({
        'category': 'ENTERTAINMENT',
        'benefit_name': 'Movie Ticket Discount',
        'value': 25.0,
        'categories': ['entertainment'],
        'monthly_cap': 1000.0,
        'annual_cap': null,
      });
    }

    return mappings;
  }

  /// Helper to convert CSV row to map
  Map<String, dynamic> _rowToMap(List<dynamic> row, List<String> headers) {
    Map<String, dynamic> map = {};
    for (int i = 0; i < headers.length; i++) {
      if (i < row.length) {
        map[headers[i]] = row[i];
      } else {
        map[headers[i]] = null;
      }
    }
    return map;
  }
  
  /// Test the import service with a small subset
  Future<Map<String, dynamic>> testImport() async {
    try {
      print('🧪 Testing benefit import service...');
      
      // Ensure database tables exist
      await _ensureDatabaseTables();
      
      // Test category creation
      await _createDefaultBenefitCategories();
      
      // Test benefit creation
      await _createDefaultBenefits();
      
      return {
        'success': true,
        'message': 'Test completed successfully',
        'test_mode': true,
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Test failed: ${e.toString()}',
        'error': e.toString(),
      };
    }
  }  /// Ensure all required database tables exist
  Future<void> _ensureDatabaseTables() async {
    try {
      print('🔧 Checking database tables exist...');
      
      // Simply verify tables exist - they should already be created manually
      bool tablesExist = await _checkTablesExist();
      if (!tablesExist) {
        throw Exception('Required database tables missing. Please run the setup_benefit_tables.sql script in Supabase first.');
      }
      
      print('✅ Database tables verified successfully');
    } catch (e) {
      print('⚠️ Error checking database tables: $e');
      // Don't throw error here, let the import continue and handle individual table errors
    }
  }

  /// Check if required database tables exist
  Future<bool> _checkTablesExist() async {
    try {
      // Try to query each required table
      await _supabase.from('benefit_categories').select('category_code').limit(1);
      await _supabase.from('benefits').select('id').limit(1);
      await _supabase.from('card_benefits').select('id').limit(1);
      
      // If we get here, all tables exist
      return true;
    } catch (e) {
      // If any query fails, tables don't exist      print('❌ Database tables missing: $e');
      return false;
    }
  }

  /// Create a new card in the card_catalog table
  Future<Map<String, dynamic>?> _createCard(String cardName, String bankName) async {
    try {
      final response = await _supabase.from('card_catalog').insert({
        'card_name': cardName,
        'bank': bankName,
        'card_type': 'credit',
        'network': 'visa',
        'annual_fee': 0,
        'joining_fee': 0,
        'apr': 0,
        'is_discontinued': false,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      }).select().single();
      
      return response;
    } catch (e) {
      print('❌ Error creating card $cardName: $e');
      return null;
    }
  }
}
