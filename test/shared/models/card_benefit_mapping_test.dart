import 'package:cardcompass/shared/models/benefit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps a card-benefit relationship without card_benefits fields', () {
    final benefit = CardBenefit.fromMappingJson({
      'mapping_id': 'mapping-1',
      'card_id': 'card-1',
      'benefit_id': 'benefit-1',
      'benefits': {
        'benefit_category': 'fuel',
        'is_active': true,
        'value_config': {'rate': 1.0, 'monthly_cap': 250},
      },
    });

    expect(benefit.id, 'mapping-1');
    expect(benefit.spendingCategories, ['fuel']);
    expect(benefit.monthlyCap, 250);
  });
}
