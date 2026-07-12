// lib/core/services/merchant_logo_service.dart
// Service to fetch merchant logos using Clearbit Logo API.
// The service provides a method to get a logo URL for a given merchant domain.
// If the logo cannot be fetched, it falls back to a generic placeholder.

import 'package:http/http.dart' as http;
import 'dart:convert';

class MerchantLogoService {
  // Clearbit logo API endpoint pattern.
  static const String _clearbitBaseUrl = 'https://logo.clearbit.com/';

  // Optional API key for higher rate limits. If not set, requests are unauthenticated.
  final String? apiKey;

  MerchantLogoService({this.apiKey});

  /// Returns a URL for the merchant's logo.
  ///
  /// The [domain] should be a valid merchant domain, e.g., "example.com".
  /// If the request fails or the logo is not found, the method returns a
  /// placeholder image URL from the local assets.
  Future<String> fetchLogoUrl(String domain) async {
    final uri = Uri.parse('$_clearbitBaseUrl$domain');
    final headers = <String, String>{};
    if (apiKey != null && apiKey!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $apiKey';
    }
    try {
      final response = await http.get(uri, headers: headers);
      if (response.statusCode == 200) {
        // Clearbit returns the image directly; we can use the URL itself.
        return uri.toString();
      } else {
        // Fallback to placeholder asset.
        return 'assets/images/placeholder_merchant.png';
      }
    } catch (_) {
      // Network error or invalid domain.
      return 'assets/images/placeholder_merchant.png';
    }
  }
}
