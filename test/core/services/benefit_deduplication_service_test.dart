import 'package:cardcompass/core/services/benefit_deduplication_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('creates a stable key despite case and whitespace differences', () {
    expect(
      BenefitDeduplicationService.keyFor(
        category: '  Travel ',
        type: ' Airport   lounge ',
        title: '  Domestic Lounge Access  ',
      ),
      'travel|airport lounge|domestic lounge access',
    );
  });

  test('uses empty segments for absent category or type', () {
    expect(
      BenefitDeduplicationService.keyFor(title: 'Reward points'),
      '||reward points',
    );
  });
}
