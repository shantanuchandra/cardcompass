import 'package:cardcompass/core/services/benefit_category_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('splits a compound reward category into searchable category ids', () {
    expect(
      BenefitCategoryNormalizer.idsFor({
        'category':
            'Dining at standalone restaurants, International spends, Grocery & Departmental Stores',
      }),
      ['DINING', 'GROCERY', 'SHOPPING'],
    );
  });

  test('uses the explicit single category before falling back to general', () {
    expect(
      BenefitCategoryNormalizer.idsFor({'category': 'FUEL'}),
      ['FUEL'],
    );
    expect(
      BenefitCategoryNormalizer.idsFor({'description': 'Card protection'}),
      ['GENERAL'],
    );
  });
}
