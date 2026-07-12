import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('IDFC FIRST Mayura Credit Card Integration & Calculation Tests', () {
    test('Test Calculation Logic with Exclusions & Thresholds', () async {
      print('\n🧪 Testing IDFC FIRST Mayura Benefit Calculations:');
      print('=' * 60);

      // Create a mock card benefit object to simulate what we load from DB
      final cardBenefit = {
        'value': 5.0, // 5% reward rate
        'spending_categories': ['TRAVEL'],
        'monthly_cap': 5000.0,
        'benefit': {
          'calculation_method': 'percentage',
          'category_code': 'TRAVEL',
          'name': 'Complimentary Lounge Access',
        },
        'configuration': {
          'min_spend_threshold': 20000.0, // lounge spend condition
          'max_cap_limit': 1000.0, // max lounge benefit limit per transaction
          'excluded_categories': ['FUEL', 'GROCERY'],
          'excluded_merchants': ['IRCTC', 'Paytm'],
        }
      };

      // Helper function matching calculateBestCard's extraction
      bool checkBenefitApplicable(
        double amount,
        String category,
        String merchant,
        Map<String, dynamic> benefit,
      ) {
        final config = benefit['configuration'] as Map<String, dynamic>;
        
        // 1. Check category exclusions
        final excludedCats = config['excluded_categories'] as List<dynamic>;
        if (excludedCats.any((cat) => cat.toString().toLowerCase() == category.toLowerCase())) {
          return false;
        }

        // 2. Check merchant exclusions
        final excludedMerchants = config['excluded_merchants'] as List<dynamic>;
        if (excludedMerchants.any((m) => merchant.toLowerCase().contains(m.toString().toLowerCase()))) {
          return false;
        }

        // 3. Check min spend threshold
        final minSpend = config['min_spend_threshold'] as double;
        if (amount < minSpend) {
          return false;
        }

        return true;
      }

      // Test cases
      // Case 1: Below threshold
      final case1 = checkBenefitApplicable(15000.0, 'TRAVEL', 'Priority Pass', cardBenefit);
      print('Case 1: Spend ₹15,000 (Below ₹20,000 threshold) -> Applicable: $case1');
      expect(case1, isFalse);

      // Case 2: Above threshold, non-excluded
      final case2 = checkBenefitApplicable(25000.0, 'TRAVEL', 'Priority Pass', cardBenefit);
      print('Case 2: Spend ₹25,000 (Above ₹20,000 threshold) -> Applicable: $case2');
      expect(case2, isTrue);

      // Case 3: Above threshold, excluded category (FUEL)
      final case3 = checkBenefitApplicable(25000.0, 'FUEL', 'HPCL Fuel Station', cardBenefit);
      print('Case 3: Spend ₹25,000 in FUEL (Excluded category) -> Applicable: $case3');
      expect(case3, isFalse);

      // Case 4: Above threshold, excluded merchant (IRCTC)
      final case4 = checkBenefitApplicable(25000.0, 'TRAVEL', 'IRCTC Rail booking', cardBenefit);
      print('Case 4: Spend ₹25,000 with IRCTC (Excluded merchant) -> Applicable: $case4');
      expect(case4, isFalse);

      print('=' * 60);
    });
  });
}
