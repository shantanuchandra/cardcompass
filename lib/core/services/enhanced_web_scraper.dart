import 'package:http/http.dart' as http;
import 'parsing_logger.dart';
import 'ai_search_service.dart';

/// Enhanced web scraping service for real bank card pages
class EnhancedWebScraper {
  static const Duration _defaultTimeout = Duration(seconds: 30);
  static const Map<String, String> _defaultHeaders = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.5',
    'Accept-Encoding': 'gzip, deflate, br',
    'Connection': 'keep-alive',
    'Upgrade-Insecure-Requests': '1',
  };
  /// Scrape card benefit information from bank website
  static Future<ScrapedContent> scrapeCardPage({
    required String bankName,
    required String cardName,
  }) async {
    try {
      ParsingLogger.summary('🔍 Searching credit card page for $bankName $cardName...');
      final results = await AiSearchService.searchCardPage(bankName, cardName);
      if (results.isEmpty) {
        throw Exception('No credit card pages found in search results');
      }
      
      final bestUrl = results.first.url;
      ParsingLogger.summary('🌐 Found credit card URL: $bestUrl');
      return await scrapeUrl(bestUrl);
    } catch (e) {
      ParsingLogger.warning('scrapeCardPage search failed, trying fallback URL generation: $e');
      // Try generating potential URL patterns as a fallback
      final patterns = _generateUrlPatterns(bankName, cardName);
      for (final url in patterns) {
        try {
          ParsingLogger.summary('🌐 Trying fallback URL pattern: $url');
          final content = await scrapeUrl(url);
          if (content.isSuccess && content.html.length > 500) {
            return content;
          }
        } catch (_) {
          continue;
        }
      }
      throw Exception('Failed to scrape $bankName $cardName: $e');
    }
  }

  /// Generate potential URL patterns based on bank and card name
  static List<String> _generateUrlPatterns(String bankName, String cardName) {
    final patterns = <String>[];
    final bank = bankName.toLowerCase();
    final card = cardName.toLowerCase().replaceAll(RegExp(r'[^\w\s-]'), '').replaceAll(RegExp(r'\s+'), '-');
    
    if (bank.contains('hdfc')) {
      patterns.add('https://www.hdfcbank.com/personal/pay/cards/credit-cards/$card');
    } else if (bank.contains('icici')) {
      patterns.add('https://www.icicibank.com/personal-banking/cards/credit-card/$card');
      patterns.add('https://www.icicibank.com/credit-card/$card');
    } else if (bank.contains('sbi')) {
      patterns.add('https://www.sbicard.com/en/personal/credit-cards/$card.page');
      patterns.add('https://www.sbicard.com/personal/credit-cards/$card');
    } else if (bank.contains('axis')) {
      patterns.add('https://www.axisbank.com/personal/cards/credit-cards/$card');
    } else if (bank.contains('kotak')) {
      patterns.add('https://www.kotak.com/en/personal-banking/cards/credit-cards/$card.html');
    } else if (bank.contains('idfc')) {
      patterns.add('https://www.idfcfirstbank.com/credit-card/$card');
    }
    return patterns;
  }

  /// Scrape a specific URL
  static Future<ScrapedContent> scrapeUrl(String url) async {
    try {
      ParsingLogger.summary('🌐 Attempting to scrape: $url');
      
      // Try multiple scraping strategies
      ScrapedContent? content = await _scrapeWithSimpleHttp(url);
      content ??= await _scrapeWithMobileUserAgent(url);
      
      if (content != null && content.html.length > 1000) {
        ParsingLogger.summary('✅ Successfully scraped ${content.html.length} chars from $url');
        return content;
      }
      
      throw Exception('Failed to get valid content from $url');
    } catch (e) {
      ParsingLogger.warning('Failed to scrape $url: $e');
      rethrow;
    }
  }
  /// Simple HTTP scraping
  static Future<ScrapedContent?> _scrapeWithSimpleHttp(String url) async {
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: _defaultHeaders,
      ).timeout(_defaultTimeout);

      if (response.statusCode == 200) {
        return ScrapedContent(
          url: url,
          html: response.body,
          statusCode: response.statusCode,
          scrapedAt: DateTime.now(),
        );
      }
    } catch (e) {
      ParsingLogger.warning('HTTP scraping failed for $url: $e');
    }
    return null;
  }

  /// Mobile user agent scraping
  static Future<ScrapedContent?> _scrapeWithMobileUserAgent(String url) async {
    try {
      final mobileHeaders = Map<String, String>.from(_defaultHeaders);
      mobileHeaders['User-Agent'] = 'Mozilla/5.0 (iPhone; CPU iPhone OS 14_7_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.1.2 Mobile/15E148 Safari/604.1';

      final response = await http.get(
        Uri.parse(url),
        headers: mobileHeaders,
      ).timeout(_defaultTimeout);

      if (response.statusCode == 200) {
        return ScrapedContent(
          url: url,
          html: response.body,
          statusCode: response.statusCode,
          scrapedAt: DateTime.now(),
          userAgent: 'mobile',
        );
      }
    } catch (e) {
      ParsingLogger.warning('Mobile scraping failed for $url: $e');
    }
    return null;
  }
  /// Extract benefit-related content from HTML
  static String extractBenefitContent(String html) {
    // Look for benefit-related sections
    final benefitKeywords = [
      'benefit', 'reward', 'cashback', 'points', 'lounge', 'insurance',
      'dining', 'travel', 'fuel', 'shopping', 'entertainment', 'utility',
      'annual fee', 'joining fee', 'milestone', 'tier', 'accelerated'
    ];

    final lines = html.split('\n');
    final benefitLines = <String>[];

    for (final line in lines) {
      final lowerLine = line.toLowerCase();
      if (benefitKeywords.any((keyword) => lowerLine.contains(keyword))) {
        benefitLines.add(line.trim());
      }
    }

    // Remove HTML tags and clean up
    String benefitContent = benefitLines.join('\n');
    benefitContent = _removeHtmlTags(benefitContent);
    benefitContent = _cleanWhitespace(benefitContent);

    return benefitContent;
  }

  /// Remove HTML tags
  static String _removeHtmlTags(String html) {
    return html.replaceAll(RegExp(r'<[^>]*>'), ' ');
  }

  /// Clean whitespace
  static String _cleanWhitespace(String text) {
    return text
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'\n\s*\n'), '\n')
        .trim();
  }

  /// Check if content appears to be valid benefit information
  static bool isValidBenefitContent(String content) {
    if (content.length < 100) return false;

    final benefitIndicators = [
      'reward points', 'cashback', '% on', 'per rupee', 'per rs',
      'annual fee', 'lounge access', 'insurance cover', 'milestone'
    ];

    final lowerContent = content.toLowerCase();
    final matchCount = benefitIndicators
        .where((indicator) => lowerContent.contains(indicator))
        .length;

    return matchCount >= 2; // At least 2 benefit indicators
  }
}

/// Scraped content data structure
class ScrapedContent {
  final String url;
  final String html;
  final int statusCode;
  final DateTime scrapedAt;
  final String? userAgent;
  final String? error;

  ScrapedContent({
    required this.url,
    required this.html,
    required this.statusCode,
    required this.scrapedAt,
    this.userAgent,
    this.error,
  });

  /// Get benefit-specific content
  String get benefitContent => EnhancedWebScraper.extractBenefitContent(html);

  /// Check if scraping was successful
  bool get isSuccess => statusCode == 200 && html.isNotEmpty;

  /// Get content summary
  Map<String, dynamic> toSummary() => {
    'url': url,
    'status_code': statusCode,
    'content_length': html.length,
    'scraped_at': scrapedAt.toIso8601String(),
    'user_agent': userAgent ?? 'desktop',
    'has_benefit_content': EnhancedWebScraper.isValidBenefitContent(benefitContent),
    'benefit_content_length': benefitContent.length,
  };
}
