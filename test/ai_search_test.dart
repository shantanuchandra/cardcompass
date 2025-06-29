import 'package:flutter_test/flutter_test.dart';
import 'package:cardcompass/core/services/ai_search_service.dart';

void main() {
  group('Minimal AI Search Service Tests', () {
    test('should search for HDFC credit cards using AI agent', () async {
      // Test the minimalist AI-powered search
      final results = await AiSearchService.searchBankCreditCards('HDFC');
      
      // Verify we get results
      expect(results, isNotNull);
      expect(results, isA<List<SearchResult>>());
      
      // Print results for verification
      print('🤖 AI Search Results for HDFC:');
      for (final result in results) {
        print('  URL: ${result.url}');
        print('  Title: ${result.title}');
        print('  Confidence: ${result.confidence}');
        print('  Source: ${result.source}');
        print('---');
      }
      
      // If we have results, verify they contain relevant keywords
      if (results.isNotEmpty) {
        final firstResult = results.first;
        final urlLower = firstResult.url.toLowerCase();
        final titleLower = firstResult.title.toLowerCase();
        
        // Should contain bank name or credit card related terms
        final isRelevant = urlLower.contains('hdfc') || 
                          urlLower.contains('credit') || 
                          urlLower.contains('card') ||
                          titleLower.contains('hdfc') ||
                          titleLower.contains('credit') ||
                          titleLower.contains('card');
        
        expect(isRelevant, true, reason: 'Results should be relevant to HDFC credit cards');
      }
    });
    
    test('should extract bank name from domain', () {
      expect(AiSearchService.extractBankNameFromDomain('hdfcbank.com'), contains('HDFC'));
      expect(AiSearchService.extractBankNameFromDomain('icicibank.com'), contains('ICICI'));
      expect(AiSearchService.extractBankNameFromDomain('unknown.com'), contains('Unknown'));
    });
    
    test('should extract domain from email', () {
      expect(AiSearchService.extractBankDomainFromEmail('user@hdfcbank.com'), equals('hdfcbank.com'));
      expect(AiSearchService.extractBankDomainFromEmail('test@icici.com'), equals('icici.com'));
      expect(AiSearchService.extractBankDomainFromEmail('invalid-email'), equals(''));
    });
    
    test('should search for multiple banks', () async {
      final banks = ['HDFC', 'ICICI', 'SBI'];
      
      for (final bank in banks) {
        print('🔍 Testing AI search for: $bank');
        
        final results = await AiSearchService.searchBankCreditCards(bank);
        
        print('  Found ${results.length} results');
        
        // Verify search completes without errors
        expect(results, isA<List<SearchResult>>());
        
        // If results exist, verify they have required fields
        for (final result in results.take(2)) {
          expect(result.url, isNotEmpty);
          expect(result.confidence, greaterThan(0.0));
          expect(result.confidence, lessThanOrEqualTo(1.0));
          expect(result.source, isNotEmpty);
        }
      }
    });
  });
}
