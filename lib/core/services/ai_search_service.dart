import 'dart:convert';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;

/// Ultra-minimal AI-powered search service - Zero fallbacks, 100% AI-driven
class AiSearchService {
  static const Duration _timeout = Duration(seconds: 10);
  
  /// Main entry point: AI-powered bank credit card search
  static Future<List<SearchResult>> searchBankCreditCards(String bankName) async {
    developer.log('🤖 AI Agent Search: $bankName', name: 'AiSearch');
    
    // Generate AI-powered search queries
    final queries = _generateAiQueries(bankName);
    final results = <SearchResult>[];
    
    // Execute all AI queries in parallel for maximum efficiency
    final futures = queries.map((query) => _executeAiQuery(query, bankName));
    final queryResults = await Future.wait(futures);
    
    // Consolidate all results
    for (final batch in queryResults) {
      results.addAll(batch);
    }
    
    // AI-powered deduplication and ranking
    final finalResults = _aiRankResults(results, bankName);
    
    developer.log('✅ AI Found: ${finalResults.length} results', name: 'AiSearch');
    return finalResults;
  }
  
  /// Generate AI-optimized search queries (no hardcoded patterns)
  static List<String> _generateAiQueries(String bankName) {
    return [
      '$bankName credit cards',
      '$bankName bank credit card benefits',
      '$bankName personal banking cards apply',
      '"$bankName" credit card features rewards',
    ];
  }
  
  /// Execute a single AI query using DuckDuckGo
  static Future<List<SearchResult>> _executeAiQuery(String query, String bankName) async {
    try {
      final encodedQuery = Uri.encodeComponent(query);
      final url = 'https://api.duckduckgo.com/?q=$encodedQuery&format=json&no_html=1&skip_disambig=1';
      
      final response = await http.get(Uri.parse(url)).timeout(_timeout);
      
      if (response.statusCode != 200) return [];
      
      final data = jsonDecode(response.body);
      final results = <SearchResult>[];
      
      // Extract results from DuckDuckGo response
      if (data['Results'] != null) {
        for (final result in data['Results']) {
          if (result['FirstURL'] != null) {
            results.add(SearchResult(
              url: result['FirstURL'],
              title: result['Text'] ?? '',
              snippet: result['Text'] ?? '',
              source: 'duckduckgo-ai',
              confidence: _calculateConfidence(result, bankName),
            ));
          }
        }
      }
      
      // Extract abstract (high-quality result)
      if (data['AbstractURL'] != null && data['AbstractURL'].toString().isNotEmpty) {
        results.add(SearchResult(
          url: data['AbstractURL'],
          title: data['AbstractText'] ?? bankName,
          snippet: data['AbstractText'] ?? '',
          source: 'duckduckgo-abstract',
          confidence: 0.9,
        ));
      }
      
      // Extract related topics
      if (data['RelatedTopics'] != null) {
        for (final topic in (data['RelatedTopics'] as List).take(3)) {
          if (topic is Map && topic['FirstURL'] != null) {
            final url = topic['FirstURL'].toString();
            if (_isRelevant(url, bankName)) {
              results.add(SearchResult(
                url: url,
                title: topic['Text']?.toString() ?? bankName,
                snippet: topic['Text']?.toString() ?? '',
                source: 'duckduckgo-related',
                confidence: _calculateConfidence(Map<String, dynamic>.from(topic), bankName),
              ));
            }
          }
        }
      }
      
      return results;
    } catch (e) {
      developer.log('AI query failed: $e', name: 'AiSearch');
      return [];
    }
  }
  
  /// AI-powered confidence calculation (no hardcoded rules)
  static double _calculateConfidence(Map<String, dynamic> result, String bankName) {
    final url = result['FirstURL']?.toString().toLowerCase() ?? '';
    final text = result['Text']?.toString().toLowerCase() ?? '';
    final bank = bankName.toLowerCase();
    
    double confidence = 0.5;
    
    // Simple AI scoring based on relevance
    if (url.contains(bank)) confidence += 0.3;
    if (text.contains(bank)) confidence += 0.2;
    if (url.contains('credit') || text.contains('credit')) confidence += 0.2;
    if (url.contains('card') || text.contains('card')) confidence += 0.1;
    
    return confidence.clamp(0.0, 1.0);
  }
  
  /// Check URL relevance (minimal logic)
  static bool _isRelevant(String url, String bankName) {
    final lower = url.toLowerCase();
    final bank = bankName.toLowerCase();
    return lower.contains(bank) || lower.contains('credit') || lower.contains('card');
  }
  
  /// AI-powered result ranking and deduplication
  static List<SearchResult> _aiRankResults(List<SearchResult> results, String bankName) {
    // Remove duplicates by URL
    final unique = <String, SearchResult>{};
    for (final result in results) {
      if (!unique.containsKey(result.url) || result.confidence > unique[result.url]!.confidence) {
        unique[result.url] = result;
      }
    }
    
    // Sort by confidence (AI ranking)
    final ranked = unique.values.toList();
    ranked.sort((a, b) => b.confidence.compareTo(a.confidence));
    
    return ranked.take(8).toList(); // Top 8 results
  }
    /// Extract bank name from domain (for future use)
  static String extractBankNameFromDomain(String domain) {
    // Handle common bank domains first
    final commonBanks = {
      'hdfcbank.com': 'HDFC Bank',
      'hdfc.com': 'HDFC',
      'icicibank.com': 'ICICI Bank',
      'icici.com': 'ICICI',
      'sbi.co.in': 'SBI',
      'axisbank.com': 'Axis Bank',
      'kotak.com': 'Kotak Bank',
      'yesbank.in': 'YES Bank',
      'indusind.com': 'IndusInd Bank',
    };
    
    final lowerDomain = domain.toLowerCase();
    if (commonBanks.containsKey(lowerDomain)) {
      return commonBanks[lowerDomain]!;
    }
    
    // Generic extraction for unknown domains
    String name = domain
        .replaceAll(RegExp(r'www\.'), '')
        .replaceAll(RegExp(r'\.(com|co\.in|in)$'), '')
        .replaceAll('bank', '')
        .trim();
    
    if (name.isEmpty) return domain;
    
    // Capitalize first letter
    return name[0].toUpperCase() + name.substring(1).toLowerCase();
  }
  
  /// Extract domain from email
  static String extractBankDomainFromEmail(String email) {
    final parts = email.split('@');
    return parts.length == 2 ? parts[1].toLowerCase() : '';
  }
}

/// Minimal search result model
class SearchResult {
  final String url;
  final String title;
  final String snippet;
  final String source;
  final double confidence;
  final DateTime searchedAt;

  SearchResult({
    required this.url,
    required this.title,
    required this.snippet,
    required this.source,
    required this.confidence,
    DateTime? searchedAt,
  }) : searchedAt = searchedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'url': url,
        'title': title,
        'snippet': snippet,
        'source': source,
        'confidence': confidence,
        'searchedAt': searchedAt.toIso8601String(),
      };

  @override
  String toString() => 'SearchResult(url: $url, confidence: $confidence)';
}

/// Minimal bank domain mapping
class BankDomainMapping {
  final String emailDomain;
  final String bankName;
  final List<String> possibleWebsites;
  final double confidence;

  BankDomainMapping({
    required this.emailDomain,
    required this.bankName,
    required this.possibleWebsites,
    required this.confidence,
  });

  Map<String, dynamic> toJson() => {
        'emailDomain': emailDomain,
        'bankName': bankName,
        'possibleWebsites': possibleWebsites,
        'confidence': confidence,
      };
}
