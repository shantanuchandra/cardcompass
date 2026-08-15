import 'package:flutter_test/flutter_test.dart';
import 'package:cardcompass/core/services/category_backfill_service.dart';

void main() {
  group('recategorize', () {
    test('resolves a known merchant via the categorizer', () {
      final result = recategorize(
        merchantName: 'Carrefour',
        description: 'CARREFOUR HYPERMARKET DUBAI',
        merchantLookup: (normalized) => normalized == 'CARREFOUR' ? 'grocery' : null,
      );
      expect(result.category, 'grocery');
    });

    test('falls through to keyword matching for an unmapped merchant', () {
      final result = recategorize(
        merchantName: 'Some Petrol Station',
        description: 'PETROL PUMP PAYMENT',
        merchantLookup: (_) => null,
      );
      expect(result.category, 'fuel');
    });

    test('returns other with unresolved source when nothing resolves, '
        'same as a fresh transaction would', () {
      final result = recategorize(
        merchantName: 'XYZ Corp',
        description: 'XYZ CORP TRANSACTION 998271',
        merchantLookup: (_) => null,
      );
      expect(result.category, 'other');
    });
  });
}
