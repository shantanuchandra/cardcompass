import 'package:flutter/foundation.dart';
import 'advanced_benefit_calculation_service.dart';

/// AI-powered URL classifier for credit card pages
class AiUrlClassifier {
  
  /// Classify URLs extracted from a webpage
  static Future<List<ClassifiedUrl>> classifyUrls(
    List<String> urls, 
    String contextBankName,
  ) async {
    final results = <ClassifiedUrl>[];
    
    try {
      // Filter and clean URLs first
      final cleanUrls = _filterAndCleanUrls(urls, contextBankName);
      debugPrint('🔗 Processing ${cleanUrls.length} URLs for classification');
      
      // Batch classify URLs using AI
      final classifications = await _batchClassifyWithAI(cleanUrls, contextBankName);
      
      for (int i = 0; i < cleanUrls.length; i++) {
        if (i < classifications.length) {
          results.add(ClassifiedUrl(
            url: cleanUrls[i],
            classification: classifications[i],
            confidence: _calculateConfidence(cleanUrls[i], classifications[i]),
            bankName: contextBankName,
            classifiedAt: DateTime.now(),
          ));
        }
      }
      
      // Sort by relevance (product pages first, then categories)
      results.sort((a, b) {
        if (a.classification != b.classification) {
          return _getClassificationPriority(a.classification)
              .compareTo(_getClassificationPriority(b.classification));
        }
        return b.confidence.compareTo(a.confidence);
      });
      
      debugPrint('✅ Classified ${results.length} URLs');
      return results;
      
    } catch (e) {
      debugPrint('❌ URL classification failed: $e');
      return [];
    }
  }

  /// Filter and clean URLs for classification
  static List<String> _filterAndCleanUrls(List<String> urls, String bankName) {
    final cleanUrls = <String>[];
    final seen = <String>{};
    
    for (final url in urls) {
      try {
        final uri = Uri.parse(url);
        
        // Skip invalid URLs
        if (!uri.hasScheme || (!uri.scheme.startsWith('http'))) continue;
        
        // Skip non-relevant domains
        if (!_isRelevantDomain(uri.host, bankName)) continue;
        
        // Skip common non-product URLs
        if (_isNonProductUrl(uri.path)) continue;
        
        // Normalize URL
        final normalized = _normalizeUrl(url);
        
        // Deduplicate
        if (!seen.contains(normalized)) {
          seen.add(normalized);
          cleanUrls.add(url);
        }
        
      } catch (e) {
        // Skip malformed URLs
        continue;
      }
    }
    
    return cleanUrls;
  }

  /// Check if domain is relevant for the bank
  static bool _isRelevantDomain(String host, String bankName) {
    final hostLower = host.toLowerCase();
    final bankLower = bankName.toLowerCase();
    
    // Should contain bank name or be main domain
    return hostLower.contains(bankLower) || 
           hostLower.contains('hdfc') || 
           hostLower.contains('icici') || 
           hostLower.contains('axis') || 
           hostLower.contains('sbi') || 
           hostLower.contains('kotak');
  }

  /// Check if URL path suggests non-product content
  static bool _isNonProductUrl(String path) {
    final pathLower = path.toLowerCase();
    
    final nonProductPatterns = [
      '/login', '/signin', '/register', '/signup',
      '/support', '/help', '/faq', '/contact',
      '/about', '/careers', '/investor',
      '/terms', '/privacy', '/policy',
      '/blog', '/news', '/press',
      '/download', '/mobile-app',
      '.pdf', '.doc', '.jpg', '.png', '.gif',
    ];
    
    return nonProductPatterns.any((pattern) => pathLower.contains(pattern));
  }

  /// Normalize URL for comparison
  static String _normalizeUrl(String url) {
    try {
      final uri = Uri.parse(url);
      // Remove query parameters and fragment
      return '${uri.scheme}://${uri.host}${uri.path}'.toLowerCase();
    } catch (e) {
      return url.toLowerCase();
    }
  }
  /// Batch classify URLs using Gemini AI
  static Future<List<UrlClassification>> _batchClassifyWithAI(
    List<String> urls, 
    String bankName,
  ) async {
    try {
      // Create classification prompt
      final prompt = _createClassificationPrompt(urls, bankName);
      
      // Use AdvancedBenefitCalculationService for AI classification
      final service = AdvancedBenefitCalculationService();
      final response = await service.classifyUrlsWithAI(prompt);
      
      // Parse AI response
      return _parseClassificationResponse(response, urls.length);
      
    } catch (e) {
      debugPrint('AI classification failed, using fallback: $e');
      return _fallbackClassification(urls);
    }
  }

  /// Create prompt for URL classification
  static String _createClassificationPrompt(List<String> urls, String bankName) {
    final urlList = urls.asMap().entries.map((entry) => 
      '${entry.key + 1}. ${entry.value}'
    ).join('\n');
    
    return '''
Classify these URLs from $bankName's website into categories. For each URL, respond with exactly one word:
- PRODUCT: Individual credit card product pages
- CATEGORY: Credit card category/listing pages  
- OTHER: General pages, non-credit card content

URLs to classify:
$urlList

Respond with only the classifications in order, one per line:
1. [PRODUCT/CATEGORY/OTHER]
2. [PRODUCT/CATEGORY/OTHER]
...

Focus on identifying individual credit card product pages vs category pages vs irrelevant content.
''';
  }

  /// Parse AI classification response
  static List<UrlClassification> _parseClassificationResponse(
    String response, 
    int expectedCount,
  ) {
    final classifications = <UrlClassification>[];
    final lines = response.split('\n');
    
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      
      // Extract classification from line (handle numbered format)
      UrlClassification classification = UrlClassification.other;
      
      if (trimmed.toUpperCase().contains('PRODUCT')) {
        classification = UrlClassification.product;
      } else if (trimmed.toUpperCase().contains('CATEGORY')) {
        classification = UrlClassification.category;
      } else if (trimmed.toUpperCase().contains('OTHER')) {
        classification = UrlClassification.other;
      }
      
      classifications.add(classification);
      
      if (classifications.length >= expectedCount) break;
    }
    
    // Fill remaining with fallback if needed
    while (classifications.length < expectedCount) {
      classifications.add(UrlClassification.other);
    }
    
    return classifications;
  }

  /// Fallback classification using URL patterns
  static List<UrlClassification> _fallbackClassification(List<String> urls) {
    return urls.map((url) => _classifyUrlByPattern(url)).toList();
  }

  /// Classify URL by pattern matching
  static UrlClassification _classifyUrlByPattern(String url) {
    try {
      final uri = Uri.parse(url);
      final pathLower = uri.path.toLowerCase();
      
      // Product page patterns
      final productPatterns = [
        RegExp(r'/credit-cards/[^/]+$'),
        RegExp(r'/cards/[^/]+$'),
        RegExp(r'/[^/]+-card$'),
        RegExp(r'/[^/]+-credit-card$'),
      ];
      
      for (final pattern in productPatterns) {
        if (pattern.hasMatch(pathLower)) {
          return UrlClassification.product;
        }
      }
      
      // Category page patterns
      final categoryPatterns = [
        'credit-cards',
        'cards/credit',
        'personal-banking/cards',
        'cards/credit-cards',
      ];
      
      for (final pattern in categoryPatterns) {
        if (pathLower.contains(pattern) && !pathLower.endsWith(pattern)) {
          return UrlClassification.category;
        }
      }
      
      return UrlClassification.other;
      
    } catch (e) {
      return UrlClassification.other;
    }
  }

  /// Calculate confidence score for classification
  static double _calculateConfidence(String url, UrlClassification classification) {
    double confidence = 0.5; // Base confidence
    
    try {
      final uri = Uri.parse(url);
      final pathLower = uri.path.toLowerCase();
      
      // Higher confidence for clear patterns
      switch (classification) {
        case UrlClassification.product:
          if (pathLower.contains('-card') || pathLower.contains('-credit-card')) {
            confidence = 0.9;
          } else if (pathLower.split('/').length > 3) {
            confidence = 0.7;
          }
          break;
          
        case UrlClassification.category:
          if (pathLower.contains('credit-cards') || pathLower.contains('cards/credit')) {
            confidence = 0.8;
          }
          break;
          
        case UrlClassification.other:
          confidence = 0.6;
          break;
      }
      
    } catch (e) {
      confidence = 0.3;
    }
    
    return confidence;
  }

  /// Get priority for sorting (lower = higher priority)
  static int _getClassificationPriority(UrlClassification classification) {
    switch (classification) {
      case UrlClassification.product:
        return 1;
      case UrlClassification.category:
        return 2;
      case UrlClassification.other:
        return 3;
    }
  }  /// Extract all URLs from HTML content
  static List<String> extractUrlsFromHtml(String html, String baseUrl) {
    final urls = <String>[];
    
    try {
      // Use a simpler approach - find href= patterns
      final pattern = 'href=';
      final indices = <int>[];
      
      // Find all href= occurrences
      var index = html.indexOf(pattern);
      while (index != -1) {
        indices.add(index);
        index = html.indexOf(pattern, index + 1);
      }
      
      // Extract URLs from each href= occurrence
      for (final idx in indices) {
        final start = idx + pattern.length;
        if (start < html.length) {
          final char = html[start];
          String quote;
          int urlStart;
          
          if (char == '"' || char == "'") {
            quote = char;
            urlStart = start + 1;
          } else {
            continue; // Skip malformed href
          }
          
          final urlEnd = html.indexOf(quote, urlStart);
          if (urlEnd != -1) {
            final url = html.substring(urlStart, urlEnd);
            final absoluteUrl = _makeAbsoluteUrl(url, baseUrl);
            if (absoluteUrl != null) {
              urls.add(absoluteUrl);
            }
          }
        }
      }
      
    } catch (e) {
      debugPrint('Failed to extract URLs from HTML: $e');
    }
    
    return urls;
  }

  /// Convert relative URL to absolute
  static String? _makeAbsoluteUrl(String url, String baseUrl) {
    try {
      final uri = Uri.parse(url);
      if (uri.hasScheme) {
        return url; // Already absolute
      }
      
      final baseUri = Uri.parse(baseUrl);
      final absoluteUri = baseUri.resolveUri(uri);
      return absoluteUri.toString();
      
    } catch (e) {
      return null;
    }
  }
}

/// URL classification types
enum UrlClassification {
  product,   // Individual credit card product pages
  category,  // Credit card category/listing pages
  other,     // Other pages (non-credit card content)
}

/// Classified URL with metadata
class ClassifiedUrl {
  final String url;
  final UrlClassification classification;
  final double confidence;
  final String bankName;
  final DateTime classifiedAt;

  ClassifiedUrl({
    required this.url,
    required this.classification,
    required this.confidence,
    required this.bankName,
    required this.classifiedAt,
  });

  Map<String, dynamic> toJson() => {
        'url': url,
        'classification': classification.name,
        'confidence': confidence,
        'bankName': bankName,
        'classifiedAt': classifiedAt.toIso8601String(),
      };

  @override
  String toString() => 'ClassifiedUrl(url: $url, type: ${classification.name}, confidence: $confidence)';
}

/// URL classification batch result
class UrlClassificationResult {
  final List<ClassifiedUrl> productUrls;
  final List<ClassifiedUrl> categoryUrls;
  final List<ClassifiedUrl> otherUrls;
  final int totalProcessed;

  UrlClassificationResult({
    required this.productUrls,
    required this.categoryUrls,
    required this.otherUrls,
    required this.totalProcessed,
  });

  factory UrlClassificationResult.fromClassifiedUrls(List<ClassifiedUrl> classifiedUrls) {
    final productUrls = classifiedUrls.where((u) => u.classification == UrlClassification.product).toList();
    final categoryUrls = classifiedUrls.where((u) => u.classification == UrlClassification.category).toList();
    final otherUrls = classifiedUrls.where((u) => u.classification == UrlClassification.other).toList();
    
    return UrlClassificationResult(
      productUrls: productUrls,
      categoryUrls: categoryUrls,
      otherUrls: otherUrls,
      totalProcessed: classifiedUrls.length,
    );
  }

  Map<String, dynamic> toJson() => {
        'productUrls': productUrls.map((u) => u.toJson()).toList(),
        'categoryUrls': categoryUrls.map((u) => u.toJson()).toList(),
        'otherUrls': otherUrls.map((u) => u.toJson()).toList(),
        'totalProcessed': totalProcessed,
        'summary': {
          'productCount': productUrls.length,
          'categoryCount': categoryUrls.length,
          'otherCount': otherUrls.length,
        },
      };
}
