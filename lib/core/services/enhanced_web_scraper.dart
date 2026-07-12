import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kIsWeb;
import '../env.dart';
import 'parsing_logger.dart';
import 'ai_search_service.dart';

/// Enhanced web scraping service for real bank card pages.
///
/// On Flutter Web, uses a Supabase Edge Function (`scrape-card`) as a
/// server-side proxy to bypass CORS restrictions. On mobile/desktop,
/// makes direct HTTP requests.
class EnhancedWebScraper {
  static const Duration _defaultTimeout = Duration(seconds: 30);
  static const Map<String, String> _defaultHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept':
        'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.5',
    'Accept-Encoding': 'gzip, deflate, br',
    'Connection': 'keep-alive',
    'Upgrade-Insecure-Requests': '1',
  };

  /// The Supabase Edge Function URL for server-side scraping (CORS bypass).
  static String get _proxyUrl => '${Env.supabaseUrl}/functions/v1/scrape-card';

  /// Scrape card benefit information from bank website
  static Future<ScrapedContent> scrapeCardPage({
    required String bankName,
    required String cardName,
  }) async {
    try {
      ParsingLogger.summary(
          '🔍 Searching credit card page for $bankName $cardName...');
      final results = await AiSearchService.searchCardPage(bankName, cardName);
      if (results.isEmpty) {
        throw Exception('No credit card pages found in search results');
      }

      final bestUrl = results.first.url;
      ParsingLogger.summary('🌐 Found credit card URL: $bestUrl');
      return await scrapeUrl(bestUrl);
    } catch (e) {
      ParsingLogger.warning(
          'scrapeCardPage search failed, trying fallback URL generation: $e');
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
    final card = cardName
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '-');

    if (bank.contains('hdfc')) {
      patterns.add(
          'https://www.hdfcbank.com/personal/pay/cards/credit-cards/$card');
    } else if (bank.contains('icici')) {
      patterns.add(
          'https://www.icicibank.com/personal-banking/cards/credit-card/$card');
      patterns.add('https://www.icicibank.com/credit-card/$card');
    } else if (bank.contains('sbi')) {
      patterns
          .add('https://www.sbicard.com/en/personal/credit-cards/$card.page');
      patterns.add('https://www.sbicard.com/personal/credit-cards/$card');
    } else if (bank.contains('axis')) {
      patterns
          .add('https://www.axisbank.com/personal/cards/credit-cards/$card');
    } else if (bank.contains('kotak')) {
      patterns.add(
          'https://www.kotak.com/en/personal-banking/cards/credit-cards/$card.html');
    } else if (bank.contains('idfc')) {
      patterns.add('https://www.idfcfirstbank.com/credit-card/$card');
    }
    return patterns;
  }

  /// Scrape a specific URL.
  ///
  /// On **web**: routes through the Supabase Edge Function proxy to bypass CORS.
  /// On **mobile/desktop**: makes direct HTTP requests.
  static Future<ScrapedContent> scrapeUrl(String url) async {
    try {
      ParsingLogger.summary(
          '🌐 Attempting to scrape: $url (platform: ${kIsWeb ? "web" : "native"})');

      ScrapedContent? content;

      if (kIsWeb) {
        // ── WEB: Use server-side proxy to bypass CORS ──
        content = await _scrapeViaProxy(url);
      } else {
        // ── NATIVE: Direct HTTP (no CORS issues) ──
        content = await _scrapeWithSimpleHttp(url);
        content ??= await _scrapeWithMobileUserAgent(url);
      }

      if (content != null && content.html.length > 1000) {
        ParsingLogger.summary(
            '✅ Successfully scraped ${content.html.length} chars from $url');
        return content;
      }

      throw Exception(
          'Failed to get valid content from $url (got ${content?.html.length ?? 0} chars)');
    } catch (e) {
      ParsingLogger.warning('Failed to scrape $url: $e');
      rethrow;
    }
  }

  /// Scrape via Supabase Edge Function proxy (for Flutter Web CORS bypass).
  static Future<ScrapedContent?> _scrapeViaProxy(String url) async {
    try {
      ParsingLogger.summary(
          '🔀 PROXY: Routing through Edge Function for CORS bypass...');

      final response = await http
          .post(
            Uri.parse(_proxyUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${Env.supabaseAnonKey}',
            },
            body: jsonEncode({'url': url}),
          )
          .timeout(const Duration(seconds: 45));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == true && data['html'] != null) {
          final html = data['html'] as String;
          final statusCode = data['status_code'] as int? ?? 200;
          final finalUrl = data['final_url'] as String? ?? url;

          ParsingLogger.summary(
              '✅ PROXY: Successfully fetched ${html.length} chars (status: $statusCode, final URL: $finalUrl)');

          return ScrapedContent(
            url: finalUrl,
            html: html,
            statusCode: statusCode,
            scrapedAt: DateTime.now(),
            userAgent: 'proxy',
          );
        } else {
          ParsingLogger.warning(
              'PROXY: Server returned success=false: ${data['error']}');
        }
      } else {
        ParsingLogger.warning(
            'PROXY: Edge Function returned status ${response.statusCode}: ${response.body.length > 200 ? response.body.substring(0, 200) : response.body}');
      }
    } catch (e) {
      ParsingLogger.error('PROXY: Edge Function call failed: $e');
    }
    return null;
  }

  /// Simple HTTP scraping (native platforms only)
  static Future<ScrapedContent?> _scrapeWithSimpleHttp(String url) async {
    try {
      final response = await http
          .get(
            Uri.parse(url),
            headers: _defaultHeaders,
          )
          .timeout(_defaultTimeout);

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

  /// Mobile user agent scraping (native platforms only)
  static Future<ScrapedContent?> _scrapeWithMobileUserAgent(String url) async {
    try {
      final mobileHeaders = Map<String, String>.from(_defaultHeaders);
      mobileHeaders['User-Agent'] =
          'Mozilla/5.0 (iPhone; CPU iPhone OS 14_7_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.1.2 Mobile/15E148 Safari/604.1';

      final response = await http
          .get(
            Uri.parse(url),
            headers: mobileHeaders,
          )
          .timeout(_defaultTimeout);

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
    var scopedHtml = html
        .replaceAll(
          RegExp(r'<(script|style|nav|footer)[^>]*>.*?</\1>',
              caseSensitive: false, dotAll: true),
          ' ',
        )
        .replaceAll(
          RegExp(r'</?(?:p|div|section|article|li|h[1-6]|tr|br)[^>]*>',
              caseSensitive: false),
          '\n',
        );

    // Look for benefit-related sections
    final benefitKeywords = [
      'benefit',
      'reward',
      'cashback',
      'points',
      'lounge',
      'insurance',
      'dining',
      'travel',
      'fuel',
      'shopping',
      'entertainment',
      'utility',
      'annual fee',
      'joining fee',
      'milestone',
      'tier',
      'accelerated'
    ];

    final contamination = RegExp(
      r'personal loan|savings account|current account|salary account|wealth management|customer support|request a callback|apply now',
      caseSensitive: false,
    );
    final lines = scopedHtml.split('\n');
    final benefitLines = <String>[];

    for (final line in lines) {
      final cleanLine = _cleanWhitespace(_removeHtmlTags(line));
      final lowerLine = cleanLine.toLowerCase();
      if (cleanLine.isNotEmpty &&
          !contamination.hasMatch(cleanLine) &&
          benefitKeywords.any((keyword) => lowerLine.contains(keyword))) {
        benefitLines.add(cleanLine);
      }
    }

    return benefitLines.toSet().join('\n');
  }

  static SourceValidationResult validateCardSource({
    required String url,
    required String content,
    required String bankName,
    required String cardName,
  }) {
    final reasons = <SourceValidationIssue>[];
    final uri = Uri.tryParse(url);
    final domains = _officialDomainsForBank(bankName);
    if (uri == null || uri.scheme != 'https') {
      reasons.add(const SourceValidationIssue(
        'invalid_source_url',
        'The source URL must be a valid HTTPS URL.',
      ));
    } else if (!domains
        .any((domain) => uri.host == domain || uri.host.endsWith('.$domain'))) {
      reasons.add(const SourceValidationIssue(
        'unofficial_domain',
        'The source host is not an official domain for the selected bank.',
      ));
    }

    final normalizedHaystack = _identityText('${uri?.path ?? ''} $content');
    final cardTokens = _identityTokens(cardName);
    if (cardTokens.isEmpty ||
        !cardTokens.every((token) => normalizedHaystack.contains(token))) {
      reasons.add(const SourceValidationIssue(
        'card_identity_not_found',
        'The source does not identify the requested card variant.',
      ));
    }

    final lower = content.toLowerCase();
    if (!lower.contains('credit card') ||
        !RegExp(r'cashback|reward|annual fee|joining fee|lounge|waiver|points')
            .hasMatch(lower)) {
      reasons.add(const SourceValidationIssue(
        'not_a_card_product_page',
        'The source lacks card-product and benefit evidence.',
      ));
    }

    return SourceValidationResult(reasons);
  }

  static Set<String> _officialDomainsForBank(String bankName) {
    final bank = bankName.toLowerCase();
    if (bank.contains('axis')) return {'axisbank.com'};
    if (bank.contains('hdfc')) return {'hdfcbank.com'};
    if (bank.contains('icici')) return {'icicibank.com'};
    if (bank.contains('idfc')) return {'idfcfirstbank.com'};
    if (bank.contains('kotak')) return {'kotak.com'};
    if (bank.contains('sbi')) return {'sbicard.com'};
    if (bank.contains('au small')) return {'aubank.in'};
    if (bank.contains('punjab national')) return {'pnbcsl.in', 'pnbindia.in'};
    return const {};
  }

  static Set<String> _identityTokens(String value) {
    const ignored = {'bank', 'credit', 'card', 'the'};
    return _identityText(value)
        .split(' ')
        .where((token) => token.isNotEmpty && !ignored.contains(token))
        .toSet();
  }

  static String _identityText(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Remove HTML tags
  static String _removeHtmlTags(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&#39;', "'")
        .replaceAll('&quot;', '"');
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
      'reward points',
      'cashback',
      '% on',
      'per rupee',
      'per rs',
      'annual fee',
      'lounge access',
      'insurance cover',
      'milestone'
    ];

    final lowerContent = content.toLowerCase();
    final matchCount = benefitIndicators
        .where((indicator) => lowerContent.contains(indicator))
        .length;

    return matchCount >= 2; // At least 2 benefit indicators
  }
}

class SourceValidationIssue {
  final String code;
  final String message;

  const SourceValidationIssue(this.code, this.message);

  Map<String, dynamic> toJson() => {'code': code, 'message': message};
}

class SourceValidationResult {
  final List<SourceValidationIssue> reasons;

  const SourceValidationResult(this.reasons);

  bool get isValid => reasons.isEmpty;
  List<String> get reasonCodes => reasons.map((reason) => reason.code).toList();
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
        'has_benefit_content':
            EnhancedWebScraper.isValidBenefitContent(benefitContent),
        'benefit_content_length': benefitContent.length,
      };
}
