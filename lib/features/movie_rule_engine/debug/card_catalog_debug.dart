// Debug helper for movie rule engine issues
// Add this file to the movie_rule_engine directory and import it in the service file

import 'package:flutter/foundation.dart';

/// Utility class for debugging card catalog issues
class CardCatalogDebug {
  /// Log query with details to help identify card_catalog.is_active references
  static void logQuery(String query, {String? method, String? error}) {
    if (kDebugMode) {
      print('=== CARD_CATALOG_DEBUG ===');
      print('Method: $method');
      print('Query: $query');
      if (error != null) {
        print('ERROR: $error');
      }
      print('========================');
    }
  }

  /// Analyze query to detect potential issues
  static bool detectPotentialIssue(String query) {
    // Check for common error patterns
    bool hasPotentialIssue = 
        query.toLowerCase().contains('card_catalog') && 
        query.toLowerCase().contains('is_active');
    
    if (hasPotentialIssue && kDebugMode) {
      print('⚠️ WARNING: Potential card_catalog.is_active reference detected!');
    }
    
    return hasPotentialIssue;
  }

  /// Log PostgreSQL exception with details
  static void logException(Object e, {String? method, String? query}) {
    if (kDebugMode) {
      print('🛑 POSTGRES EXCEPTION');
      print('Method: $method');
      print('Query: $query');
      print('Error: $e');
      print('========================');
      
      // Extract column name from error message if possible
      final errorStr = e.toString();
      if (errorStr.contains('column') && errorStr.contains('does not exist')) {
        final regex = RegExp(r'column\s+([^\s]+)\s+does not exist');
        final match = regex.firstMatch(errorStr);
        if (match != null && match.groupCount >= 1) {
          final columnName = match.group(1);
          print('🔍 Missing column detected: $columnName');
        }
      }
    }
  }
  
  /// Validate benefit configuration schema
  static bool validateBenefitConfigSchema(dynamic config, {String? benefitId}) {
    if (kDebugMode) {
      print('=== VALIDATING BENEFIT CONFIG ===');
      print('Benefit ID: $benefitId');
      
      bool isValid = true;
      
      if (config == null) {
        print('ERROR: Configuration is null');
        return false;
      }
      
      if (config is! Map<String, dynamic>) {
        print('ERROR: Configuration is not a Map<String, dynamic>, found type: ${config.runtimeType}');
        print('VALUE: $config');
        return false;
      }
      
      // Check required fields
      if (!config.containsKey('offer_type') || config['offer_type'] == null) {
        print('ERROR: Missing required field "offer_type"');
        isValid = false;
      }
      
      // Check types for common fields
      if (config.containsKey('discount_percent') && 
          config['discount_percent'] != null && 
          config['discount_percent'] is! num) {
        print('ERROR: Field "discount_percent" should be a number, found type: ${config['discount_percent'].runtimeType}');
        isValid = false;
      }
      
      if (config.containsKey('partner_filter') && 
          config['partner_filter'] != null && 
          config['partner_filter'] is! List) {
        print('ERROR: Field "partner_filter" should be a List, found type: ${config['partner_filter'].runtimeType}');
        isValid = false;
      }
      
      print('Configuration validation result: ${isValid ? "VALID" : "INVALID"}');
      return isValid;
    }
    return true;
  }
}
