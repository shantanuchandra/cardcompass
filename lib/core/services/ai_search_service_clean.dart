import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

/// AI-powered search service for finding credit card pages
class AiSearchService {
  static const Duration _defaultTimeout = Duration(seconds: 15);
  static const Map<String, String> _defaultHeaders = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': 'application/json,text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.5',
  };

  /// Search for a bank's main credit card page using DuckDuckGo instant answers
  static Future<List<SearchResult>> searchBankCreditCards(String bankName) async {
    try {
      final query = Uri.encodeComponent('$bankName credit cards');
      final url = 'https://api.duckduckgo.com/?q=$query&format=json&no_html=1&skip_disambig=1';
      
      final response = await http.get(
        Uri.parse(url),
        headers: _defaultHeaders,
      ).timeout(_defaultTimeout);

      if (response.statusCode == 200) {
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
                source: 'duckduckgo',
                confidence: 0.8,
              ));
            }
          }
        }
        
        // Extract abstract if available
        if (data['AbstractURL'] != null && data['AbstractURL'].toString().isNotEmpty) {
          results.add(SearchResult(
            url: data['AbstractURL'],
            title: data['AbstractText'] ?? '',
            snippet: data['AbstractText'] ?? '',
            source: 'duckduckgo',
            confidence: 0.9,
          ));
        }
        
        debugPrint('🔍 Found ${results.length} search results for $bankName');
        return results;
      }
    } catch (e) {
      debugPrint('❌ Search failed for $bankName: $e');
    }
    return [];
  }

  /// Extract domain from email for bank identification
  static String extractBankDomainFromEmail(String email) {
    try {
      final parts = email.split('@');
      if (parts.length == 2) {
        return parts[1].toLowerCase();
      }
    } catch (e) {
      debugPrint('Failed to extract domain from email: $e');
    }
    return '';
  }

  /// Extract bank name from domain using heuristics
  static String extractBankNameFromDomain(String domain) {
    // Remove common suffixes and extract base name
    String name = domain
        .replaceAll('.com', '')
        .replaceAll('.co.in', '')
        .replaceAll('.in', '')
        .replaceAll('www.', '');
    
    // Capitalize first letter
    if (name.isNotEmpty) {
      name = name[0].toUpperCase() + name.substring(1);
    }
    
    return name;
  }
}

/// Search result from AI search
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
  String toString() => 'SearchResult(url: $url, confidence: $confidence, source: $source)';
}

/// Bank domain mapping result
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
