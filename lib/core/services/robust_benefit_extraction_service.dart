import 'package:flutter/foundation.dart';
import 'ai_search_service.dart';
import 'ai_url_classifier.dart';
import 'enhanced_web_scraper.dart';

/// Robust AI-powered credit card benefits extraction pipeline
class RobustBenefitExtractionService {
  static const int maxProductUrls = 10;
  static const int maxCategoryDepth = 2;

  /// Extract benefits for all user's credit cards using the robust pipeline
  static Future<Map<String, dynamic>> extractAllCardBenefits({
    required String userId,
  }) async {
    final results = <String, dynamic>{};
    final timestamp = DateTime.now();
    
    try {
      debugPrint('🚀 Starting robust benefit extraction pipeline');
      
      // Phase 1: Extract bank domains from user emails
      final bankDomains = await _extractBankDomainsFromEmails(userId);
      debugPrint('📧 Found ${bankDomains.length} bank domains from emails');
      
      // Phase 2: Process each bank
      final allResults = <Map<String, dynamic>>[];
      
      for (final bankMapping in bankDomains) {
        final bankResult = await _processBankBenefits(bankMapping);
        if (bankResult['success'] == true) {
          allResults.add(bankResult);
        }
      }
      
      // Phase 3: Consolidate results
      results['pipeline'] = 'robust_ai_extraction';
      results['timestamp'] = timestamp.toIso8601String();
      results['banks_processed'] = bankDomains.length;
      results['successful_extractions'] = allResults.length;
      results['results'] = allResults;
      results['success'] = allResults.isNotEmpty;
      results['summary'] = _generateExtractionSummary(allResults);
      
      debugPrint('✅ Robust extraction completed: ${allResults.length}/${bankDomains.length} banks successful');
      
    } catch (e) {
      debugPrint('❌ Robust extraction pipeline failed: $e');
      results['error'] = e.toString();
      results['success'] = false;
    }
    
    return results;
  }  /// Phase 1: Extract bank domains from user emails
  static Future<List<BankDomainMapping>> _extractBankDomainsFromEmails(String userId) async {
    final mappings = <BankDomainMapping>[];
    
    try {
      // For now, use AI search to find banks dynamically
      // This would be replaced with actual email domain extraction
      final commonBanks = ['HDFC Bank', 'ICICI Bank', 'Axis Bank', 'SBI'];
      
      for (final bankName in commonBanks) {
        mappings.add(BankDomainMapping(
          emailDomain: '${bankName.toLowerCase().replaceAll(' ', '')}.com',
          bankName: bankName,
          possibleWebsites: [], // Will be determined by AI search
          confidence: 0.8,
        ));
      }
      
    } catch (e) {
      debugPrint('Failed to extract bank domains: $e');
    }
    
    return mappings;
  }  /// Phase 2: Process benefits for a specific bank
  static Future<Map<String, dynamic>> _processBankBenefits(BankDomainMapping bankMapping) async {
    final result = <String, dynamic>{
      'bankName': bankMapping.bankName,
      'domain': bankMapping.emailDomain,
      'success': false,
      'timestamp': DateTime.now().toIso8601String(),
    };
    
    try {
      debugPrint('🏦 Processing ${bankMapping.bankName}');
      
      // Step 1: Find main credit card page using AI search
      final searchResults = await AiSearchService.searchBankCreditCards(bankMapping.bankName);
      
      if (searchResults.isEmpty) {
        debugPrint('⚠️ No search results found for ${bankMapping.bankName}');
        result['error'] = 'No search results found';
        return result;
      }
      
      debugPrint('🔍 Found ${searchResults.length} search results for ${bankMapping.bankName}');
      result['searchResults'] = searchResults.length;
      result['searchSources'] = searchResults.map((r) => r.source).toSet().toList();
      
      // Step 2: Get the best search result
      final bestResult = searchResults.first;
      final mainPageUrl = bestResult.url;
      
      debugPrint('🌐 Using main page: $mainPageUrl (confidence: ${bestResult.confidence})');
      result['mainPageUrl'] = mainPageUrl;
      result['mainPageSource'] = bestResult.source;
      result['mainPageConfidence'] = bestResult.confidence;
      
      // Step 3: Scrape main page to extract content and URLs
      final mainPageContent = await EnhancedWebScraper.scrapeUrl(mainPageUrl);
      
      if (mainPageContent.html.isEmpty) {
        debugPrint('⚠️ Main page content is empty for ${bankMapping.bankName}');
        result['error'] = 'Main page content is empty';
        return result;
      }
      
      debugPrint('📄 Scraped main page: ${mainPageContent.html.length} characters');
      result['mainPageSize'] = mainPageContent.html.length;
      
      // Step 4: Extract and classify URLs from main page
      final extractedUrls = AiUrlClassifier.extractUrlsFromHtml(
        mainPageContent.html,
        mainPageUrl,
      );
      
      debugPrint('🔗 Extracted ${extractedUrls.length} URLs from main page');
      result['extractedUrls'] = extractedUrls.length;      if (extractedUrls.isEmpty) {
        debugPrint('⚠️ No URLs extracted from main page for ${bankMapping.bankName}');
        // Try to extract benefits directly from main page
        final mainPageClassified = ClassifiedUrl(
          url: mainPageUrl,
          classification: UrlClassification.product,
          confidence: 0.9,
          bankName: bankMapping.bankName,
          classifiedAt: DateTime.now(),
        );
        final directBenefits = await _extractBenefitsFromSingleUrl(mainPageClassified, bankMapping.bankName);
        result['benefits'] = directBenefits;
        result['success'] = directBenefits.isNotEmpty;
        result['extractionMethod'] = 'direct_main_page';
        return result;
      }
      
      final classifiedUrls = await AiUrlClassifier.classifyUrls(
        extractedUrls,
        bankMapping.bankName,
      );
      
      debugPrint('📊 Classified URLs: ${classifiedUrls.length} relevant');
      result['classifiedUrls'] = classifiedUrls.length;
      
      // Step 5: Process URLs in priority order
      final benefits = await _extractBenefitsFromUrls(classifiedUrls, bankMapping.bankName);
      
      result['benefits'] = benefits;
      result['success'] = benefits.isNotEmpty;
      result['extractionMethod'] = 'url_classification';
      
      debugPrint('✅ ${bankMapping.bankName}: Found ${benefits.length} benefit entries');
      
    } catch (e) {
      debugPrint('❌ Failed to process ${bankMapping.bankName}: $e');
      result['error'] = e.toString();
    }
    
    return result;
  }

  /// Phase 3: Extract benefits from classified URLs
  static Future<List<Map<String, dynamic>>> _extractBenefitsFromUrls(
    List<ClassifiedUrl> classifiedUrls,
    String bankName,
  ) async {
    final benefits = <Map<String, dynamic>>[];
    
    try {      // Process URLs in priority order: products first, then categories
      final urlsByType = UrlClassificationResult.fromClassifiedUrls(classifiedUrls);
      
      // Process product URLs (individual card pages)
      for (final productUrl in urlsByType.productUrls.take(maxProductUrls)) {
        final cardBenefits = await _extractBenefitsFromSingleUrl(productUrl, bankName);
        if (cardBenefits.isNotEmpty) {
          benefits.addAll(cardBenefits);
        }
      }
      
      // Process category URLs (if we need more data)
      if (benefits.length < 5) { // If we have few benefits, explore categories
        for (final categoryUrl in urlsByType.categoryUrls.take(3)) {
          final categoryBenefits = await _processCategoryPage(categoryUrl, bankName);
          benefits.addAll(categoryBenefits);
        }
      }
      
    } catch (e) {
      debugPrint('Failed to extract benefits from URLs: $e');
    }
    
    return benefits;
  }

  /// Extract benefits from a single product URL
  static Future<List<Map<String, dynamic>>> _extractBenefitsFromSingleUrl(
    ClassifiedUrl classifiedUrl,
    String bankName,
  ) async {
    final benefits = <Map<String, dynamic>>[];
      try {
      // Scrape the product page
      final content = await EnhancedWebScraper.scrapeUrl(classifiedUrl.url);
      
      // Use AI to extract structured benefits
      final extractedBenefits = await _extractStructuredBenefits(
        content.html,
        classifiedUrl.url,
        bankName,
      );
      
      benefits.addAll(extractedBenefits);
      
    } catch (e) {
      debugPrint('Failed to extract from ${classifiedUrl.url}: $e');
    }
    
    return benefits;
  }

  /// Process category page to find more product URLs
  static Future<List<Map<String, dynamic>>> _processCategoryPage(
    ClassifiedUrl categoryUrl,
    String bankName,
  ) async {
    final benefits = <Map<String, dynamic>>[];
      try {
      // Scrape category page
      final content = await EnhancedWebScraper.scrapeUrl(categoryUrl.url);
      
      // Extract more product URLs from category page
      final categoryUrls = AiUrlClassifier.extractUrlsFromHtml(
        content.html,
        categoryUrl.url,
      );
      
      final classifiedCategoryUrls = await AiUrlClassifier.classifyUrls(
        categoryUrls,
        bankName,
      );
      
      // Process product URLs found in category
      final productUrls = classifiedCategoryUrls
          .where((url) => url.classification == UrlClassification.product)
          .take(5); // Limit to prevent too much processing
      
      for (final productUrl in productUrls) {
        final productBenefits = await _extractBenefitsFromSingleUrl(productUrl, bankName);
        benefits.addAll(productBenefits);
      }
      
    } catch (e) {
      debugPrint('Failed to process category ${categoryUrl.url}: $e');
    }
    
    return benefits;
  }
  /// Extract structured benefits using AI
  static Future<List<Map<String, dynamic>>> _extractStructuredBenefits(
    String html,
    String url,
    String bankName,
  ) async {
    final benefits = <Map<String, dynamic>>[];
    
    try {
      // For now, create mock structured data based on URL and bank
      // This would be replaced with actual AI extraction using AdvancedBenefitCalculationService
      benefits.add({
        'cardName': _extractCardNameFromUrl(url),
        'bankName': bankName,
        'url': url,
        'rewardRate': 'Variable',
        'category': 'General',
        'description': 'Benefits extracted from $bankName website',
        'extractedAt': DateTime.now().toIso8601String(),
        'confidence': 0.7,
      });
      
    } catch (e) {
      debugPrint('Failed to extract structured benefits: $e');
    }
    
    return benefits;
  }

  /// Extract card name from URL
  static String _extractCardNameFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final segments = uri.pathSegments;
      
      if (segments.isNotEmpty) {
        final lastSegment = segments.last;
        // Clean up the segment to make it readable
        return lastSegment
            .replaceAll('-', ' ')
            .replaceAll('_', ' ')
            .replaceAll('.html', '')
            .split(' ')
            .map((word) => word.isNotEmpty ? word[0].toUpperCase() + word.substring(1) : '')
            .join(' ');
      }
    } catch (e) {
      debugPrint('Failed to extract card name from URL: $e');
    }
    
    return 'Unknown Card';
  }

  /// Generate extraction summary
  static Map<String, dynamic> _generateExtractionSummary(List<Map<String, dynamic>> results) {
    final totalBenefits = results.fold<int>(0, (sum, result) => 
        sum + ((result['benefits'] as List<dynamic>?)?.length ?? 0));
    
    final successfulBanks = results.where((r) => r['success'] == true).length;
    final totalUrls = results.fold<int>(0, (sum, result) => 
        sum + ((result['totalUrls'] as int?) ?? 0));
    
    return {
      'totalBanks': results.length,
      'successfulBanks': successfulBanks,
      'totalBenefits': totalBenefits,
      'totalUrlsProcessed': totalUrls,
      'averageBenefitsPerBank': successfulBanks > 0 ? totalBenefits / successfulBanks : 0,
      'successRate': results.isNotEmpty ? successfulBanks / results.length : 0,
    };
  }
}

/// Result of robust benefit extraction
class RobustExtractionResult {
  final bool success;
  final List<BankBenefitResult> bankResults;
  final Map<String, dynamic> summary;
  final DateTime extractedAt;
  final String? error;

  RobustExtractionResult({
    required this.success,
    required this.bankResults,
    required this.summary,
    required this.extractedAt,
    this.error,
  });

  Map<String, dynamic> toJson() => {
        'success': success,
        'bankResults': bankResults.map((b) => b.toJson()).toList(),
        'summary': summary,
        'extractedAt': extractedAt.toIso8601String(),
        'error': error,
      };
}

/// Result for a single bank
class BankBenefitResult {
  final String bankName;
  final bool success;
  final List<Map<String, dynamic>> benefits;
  final String mainPageUrl;
  final int totalUrls;
  final String? error;

  BankBenefitResult({
    required this.bankName,
    required this.success,
    required this.benefits,
    required this.mainPageUrl,
    required this.totalUrls,
    this.error,
  });

  Map<String, dynamic> toJson() => {
        'bankName': bankName,
        'success': success,
        'benefits': benefits,
        'mainPageUrl': mainPageUrl,
        'totalUrls': totalUrls,
        'error': error,
      };
}
