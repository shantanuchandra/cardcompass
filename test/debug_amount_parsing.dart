import 'package:cardcompass/core/services/pdf_parsing_service_impl.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Debug amount parsing logic with comma analysis', () {
    final parsingService = PdfParsingServiceImpl();

    // Test cases with their original format (with/without commas)
    final testCases = [
      {'original': '902,761.00', 'cleaned': '902761.00'},
      {'original': '25887.00', 'cleaned': '25887.00'},
      {'original': '30920.00', 'cleaned': '30920.00'},
    ];

    for (final testCase in testCases) {
      final original = testCase['original']!;
      final cleaned = testCase['cleaned']!;
      
      print('\n=== Testing: $original ===');
      
      // Check if original had comma
      final hadComma = original.contains(',');
      print('Had comma: $hadComma');
      
      if (hadComma) {
        // Extract the part after the comma to understand the amount structure
        final afterComma = original.split(',')[1]; // e.g., "761.00"
        final amountDigits = afterComma.split('.')[0].length; // e.g., 3 digits
        print('Digits after comma: $amountDigits');
        
        // For cleaned version, the amount should have: amountDigits + 1 digit before comma
        final expectedAmountLength = amountDigits + 1; // e.g., 4 digits total
        print('Expected amount length: $expectedAmountLength');
        
        final cleanedWithoutDecimal = cleaned.split('.')[0];
        final rewardPointsLength = cleanedWithoutDecimal.length - expectedAmountLength;
        print('Calculated reward points length: $rewardPointsLength');
        
        if (rewardPointsLength > 0 && rewardPointsLength <= 3) {
          final rewardPoints = cleanedWithoutDecimal.substring(0, rewardPointsLength);
          final amount = cleanedWithoutDecimal.substring(rewardPointsLength);
          print('Split: reward=$rewardPoints, amount=$amount.${cleaned.split('.')[1]}');
        }
      } else {
        // No comma - amount should be 3 digits (typical for amounts under 1000)
        final cleanedWithoutDecimal = cleaned.split('.')[0];
        if (cleanedWithoutDecimal.length > 3) {
          final rewardPointsLength = cleanedWithoutDecimal.length - 3;
          final rewardPoints = cleanedWithoutDecimal.substring(0, rewardPointsLength);
          final amount = cleanedWithoutDecimal.substring(rewardPointsLength);
          print('Split: reward=$rewardPoints, amount=$amount.${cleaned.split('.')[1]}');
        }
      }
      
      // Test actual parsing
      final result = parsingService.parseAmount(original);
      print('Actual result: $result');
    }
  });
}
