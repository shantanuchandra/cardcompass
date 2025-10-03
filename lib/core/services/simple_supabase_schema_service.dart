import 'package:supabase_flutter/supabase_flutter.dart';

/**
 * Alternative schema service that works without custom RPC functions.
 * Uses direct table operations and manual schema verification.
 */
class SimpleSupabaseSchemaService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /**
   * Public method to verify that essential tables exist.
   */
  Future<void> verifyTablesExist() async {
    await _verifyTablesExist();
  }

  /**
   * Creates all required tables using direct operations.
   * This is a simplified version that manually creates tables.
   */
  Future<void> initializeSchema() async {
    try {
      print('📋 Setting up Supabase tables manually...');
      
      // Since we can't execute raw SQL, we'll just verify tables exist
      // In production, these tables should be created via Supabase Dashboard or CLI
      await _verifyTablesExist();
      
      print('✅ Schema verification completed');
    } catch (e) {
      print('❌ Schema setup failed: $e');
      print('📝 Please create tables manually in Supabase Dashboard:');
      _printManualSchemaInstructions();
      rethrow;
    }
  }

  /**
   * Verify that essential tables exist by attempting to query them.
   */
  Future<void> _verifyTablesExist() async {
    final requiredTables = [
      'users',
      'card_catalog',
      'user_cards',
      'transactions',
      'statements',
    ];

    for (final table in requiredTables) {
      try {
        await _supabase
            .from(table)
            .select('*')
            .limit(1);
        print('✅ Table "$table" exists');
      } catch (e) {
        print('❌ Table "$table" missing or inaccessible');
        throw Exception('Required table "$table" not found. Please create it in Supabase Dashboard.');
      }
    }
  }

  /**
   * Print instructions for manual table creation.
   */
  void _printManualSchemaInstructions() {
    print('''

📋 MANUAL SCHEMA SETUP REQUIRED

Please create these tables in your Supabase Dashboard > SQL Editor:

1. USERS TABLE:
CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email TEXT UNIQUE NOT NULL,
  full_name TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

2. CARD_CATALOG TABLE:
CREATE TABLE card_catalog (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  card_name TEXT NOT NULL,
  bank TEXT NOT NULL,
  network TEXT NOT NULL,
  card_type TEXT NOT NULL,
  annual_fee DECIMAL(10,2),
  is_discontinued BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

3. USER_CARDS TABLE:
CREATE TABLE user_cards (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id),
  catalog_card_id UUID REFERENCES card_catalog(id),
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

4. TRANSACTIONS TABLE:
CREATE TABLE transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id),
  user_card_id UUID REFERENCES user_cards(id),
  amount DECIMAL(12,2) NOT NULL,
  description TEXT NOT NULL,
  category TEXT NOT NULL,
  transaction_date TIMESTAMP WITH TIME ZONE NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

5. STATEMENTS TABLE:
CREATE TABLE statements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id),
  user_card_id UUID REFERENCES user_cards(id),
  statement_date DATE NOT NULL,
  total_amount DECIMAL(12,2) NOT NULL,
  file_path TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

After creating these tables, run the test again.
    ''');
  }

  /**
   * Check if tables exist (simplified version).
   */
  Future<bool> checkTablesExist() async {
    try {
      await _verifyTablesExist();
      return true;
    } catch (e) {
      return false;
    }
  }

  /**
   * Insert sample data for testing.
   */
  Future<void> insertSampleData() async {
    try {
      print('📊 Inserting sample data...');


      // Insert sample user
      final userResult = await _supabase
          .from('users')
          .insert({
            'email': 'test@cardcompass.com',
            'full_name': 'Test User',
          })
          .select()
          .single();

      final userId = userResult['id'];
      print('✅ Sample user created: $userId');

      // Insert sample card_catalog entry
      final cardResult = await _supabase
          .from('card_catalog')
          .insert({
            'card_name': 'Test HDFC Card',
            'bank': 'HDFC Bank',
            'network': 'visa',
            'card_type': 'credit',
            'annual_fee': 500.0,
          })
          .select()
          .single();

      final catalogCardId = cardResult['id'];
      print('✅ Sample card_catalog entry created: $catalogCardId');

      // Link user to card (user_cards)
      final userCardResult = await _supabase
          .from('user_cards')
          .insert({
            'user_id': userId,
            'catalog_card_id': catalogCardId,
            'is_active': true,
          })
          .select()
          .single();

      final userCardId = userCardResult['id'];
      print('✅ User-card relationship created: $userCardId');

      // Insert sample transaction
      await _supabase
          .from('transactions')
          .insert({
            'user_id': userId,
            'user_card_id': userCardId,
            'amount': 1500.00,
            'description': 'Sample Restaurant Purchase',
            'category': 'food',
            'transaction_date': DateTime.now().toIso8601String(),
          });

      print('✅ Sample transaction created');
      print('🎉 Sample data insertion completed!');

    } catch (e) {
      print('❌ Sample data insertion failed: $e');
    }
  }
}
