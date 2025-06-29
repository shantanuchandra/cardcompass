import 'package:cardcompass/core/repositories/supabase_statement_repository.dart';

/// Debug utility to test statements functionality
class StatementsDebug {
  static Future<void> testStatementsFlow() async {
    print('🔍 Testing statements flow...');
    
    try {
      final repo = SupabaseStatementRepository();
      
      // Test with a demo user ID
      const testUserId = 'demo-user-123';
      
      print('📋 Fetching statements for user: $testUserId');
      final statements = await repo.getStatements(testUserId);
      
      print('✅ Found ${statements.length} statements');
      for (final statement in statements) {
        print('   - ${statement.fileName} (${statement.totalAmount})');
      }
      
      if (statements.isEmpty) {
        print('⚠️ No statements found. Creating a test statement...');
        await _createTestStatement(repo, testUserId);
      }
      
    } catch (e) {
      print('❌ Error testing statements: $e');
    }
  }
  
  static Future<void> _createTestStatement(SupabaseStatementRepository repo, String userId) async {
    try {
      final testData = {
        'statement_date': DateTime.now().toIso8601String(),
        'due_date': DateTime.now().add(const Duration(days: 30)).toIso8601String(),
        'total_amount': 25000.0,
        'minimum_payment': 2500.0,
        'closing_balance': 20000.0,
        'available_credit': 15000.0,
        'interest_charged': 500.0,
        'fees_charged': 100.0,
        'rewards_earned': 250,
        'file_name': 'test_statement.pdf',
        'transaction_count': 15,
        'processed': true,
      };
      
      final statement = await repo.createStatement(
        userId: userId,
        userCardId: 'test-card-123',
        statementData: testData,
        filePath: '/test/statement.pdf',
      );
      
      print('✅ Created test statement: ${statement.id}');
    } catch (e) {
      print('❌ Error creating test statement: $e');
    }
  }
}
