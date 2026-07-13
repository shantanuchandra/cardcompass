import 'package:cardcompass/core/services/benefit_extraction_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const evidence = '''
Airtel Axis Bank Credit Card
Get 25% cashback on Airtel mobile, broadband, Wi-Fi and DTH bill payments made through the Airtel Thanks app, capped at ₹250 per month.
Get 10% cashback on utility bill payments through the Airtel Thanks app, capped at ₹250 per month.
The annual fee is ₹500. Annual fee waived on annual spends of ₹2,00,000.
''';

  Map<String, dynamic> extraction({
    String cardName = 'Airtel',
    List<Map<String, dynamic>>? benefits,
  }) =>
      {
        'card_name': cardName,
        'bank_name': 'Axis Bank',
        'annual_fee': {
          'renewal': 500,
          'evidence_excerpt': 'The annual fee is ₹500.',
        },
        'benefits': benefits ??
            [
              {
                'category': 'CASHBACK',
                'value': 25,
                'value_type': 'percentage',
                'description': '25% cashback on Airtel bill payments',
                'monthly_cap': 250,
                'evidence_excerpt':
                    'Get 25% cashback on Airtel mobile, broadband, Wi-Fi and DTH bill payments made through the Airtel Thanks app, capped at ₹250 per month.',
              },
            ],
      };

  test('accepts claims whose identity and numeric values occur in evidence',
      () {
    final result = BenefitExtractionValidator.validate(
      extractedData: extraction(),
      evidenceText: evidence,
      cardName: 'Airtel',
      bankName: 'Axis Bank',
      sourceUrl:
          'https://www.axisbank.com/retail/cards/credit-card/airtel-axis-bank-credit-card',
    );

    expect(result.accepted, isTrue);
    expect(result.confidence, greaterThanOrEqualTo(0.8));
    expect(result.reasons, isEmpty);
  });

  test('rejects claims without an evidence excerpt', () {
    final data = extraction();
    (data['benefits'] as List).first.remove('evidence_excerpt');

    final result = BenefitExtractionValidator.validate(
      extractedData: data,
      evidenceText: evidence,
      cardName: 'Airtel',
      bankName: 'Axis Bank',
    );

    expect(result.accepted, isFalse);
    expect(result.reasonCodes, contains('missing_evidence'));
  });

  test('rejects unsupported numeric values even when prose is present', () {
    final data = extraction();
    (data['benefits'] as List).first['value'] = 40;

    final result = BenefitExtractionValidator.validate(
      extractedData: data,
      evidenceText: evidence,
      cardName: 'Airtel',
      bankName: 'Axis Bank',
    );

    expect(result.accepted, isFalse);
    expect(result.confidence, lessThan(0.8));
    expect(result.reasonCodes, contains('unsupported_numeric_value'));
  });

  test('rejects zero-value category placeholders', () {
    final result = BenefitExtractionValidator.validate(
      extractedData: extraction(benefits: [
        {
          'category': 'TRAVEL',
          'value': 0,
          'value_type': 'flat_amount',
          'description': 'Travel benefits',
          'evidence_excerpt': 'Travel benefits',
        }
      ]),
      evidenceText: '$evidence Travel benefits',
      cardName: 'Airtel',
      bankName: 'Axis Bank',
    );

    expect(result.accepted, isFalse);
    expect(result.reasonCodes, contains('placeholder_benefit'));
  });

  test('rejects banking promotions and non-benefits', () {
    const contaminated =
        'Earn up to 6.5% interest on your Savings Account. Apply for Personal Loan Online.';
    final result = BenefitExtractionValidator.validate(
      extractedData: extraction(benefits: [
        {
          'category': 'CASHBACK',
          'value': 6.5,
          'value_type': 'percentage',
          'description': '6.5% interest on your Savings Account',
          'evidence_excerpt':
              'Earn up to 6.5% interest on your Savings Account.',
        }
      ]),
      evidenceText: contaminated,
      cardName: 'Airtel',
      bankName: 'Axis Bank',
    );

    expect(result.accepted, isFalse);
    expect(result.reasonCodes, contains('non_benefit_content'));
  });

  test('rejects category and description conflicts', () {
    const fuelEvidence = 'Get 1% fuel surcharge waiver on fuel transactions.';
    final result = BenefitExtractionValidator.validate(
      extractedData: extraction(benefits: [
        {
          'category': 'DINING',
          'value': 1,
          'value_type': 'percentage',
          'description': '1% fuel surcharge waiver on fuel transactions',
          'evidence_excerpt': fuelEvidence,
        }
      ]),
      evidenceText: '$evidence $fuelEvidence',
      cardName: 'Airtel',
      bankName: 'Axis Bank',
    );

    expect(result.accepted, isFalse);
    expect(result.reasonCodes, contains('category_conflict'));
  });

  test('rejects duplicate claims assigned to different categories', () {
    const fuelEvidence = 'Get 1% fuel surcharge waiver on fuel transactions.';
    final result = BenefitExtractionValidator.validate(
      extractedData: extraction(benefits: [
        {
          'category': 'FUEL',
          'value': 1,
          'value_type': 'percentage',
          'description': '1% fuel surcharge waiver on fuel transactions',
          'evidence_excerpt': fuelEvidence,
        },
        {
          'category': 'GENERAL',
          'value': 1,
          'value_type': 'percentage',
          'description': '1% fuel surcharge waiver on fuel transactions',
          'evidence_excerpt': fuelEvidence,
        },
      ]),
      evidenceText: '$evidence $fuelEvidence',
      cardName: 'Airtel',
      bankName: 'Axis Bank',
    );

    expect(result.accepted, isFalse);
    expect(result.reasonCodes, contains('duplicate_benefit'));
  });

  test('warns when a source-backed hotel offer has no extracted claim', () {
    const hotelEvidence =
        'Experience luxury stay at ITC Hotels. Stay for 3, Pay for 2.';
    final result = BenefitExtractionValidator.validate(
      extractedData: extraction(),
      evidenceText: '$evidence\n$hotelEvidence',
      cardName: 'Airtel',
      bankName: 'Axis Bank',
    );

    expect(
      result.warnings.map((warning) => warning.code),
      contains('unextracted_source_claim'),
    );
    expect(
      result.warnings.map((warning) => warning.message).join(' '),
      contains('ITC Hotels'),
    );
  });

  test('does not warn when an evidence excerpt covers the source claim', () {
    const lounge =
        '8 complimentary domestic lounge access annually, subject to ₹50,000 prior-quarter spend.';
    final data = extraction(benefits: [
      {
        'category': 'LOUNGE',
        'description': '8 complimentary domestic lounge access annually',
        'conditions': 'subject to ₹50,000 prior-quarter spend',
        'evidence_excerpt': lounge,
      },
    ]);
    final result = BenefitExtractionValidator.validate(
      extractedData: data,
      evidenceText: '$evidence\n$lounge',
      cardName: 'Airtel',
      bankName: 'Axis Bank',
    );

    expect(result.warnings, isEmpty);
  });

  test('keeps distinct accelerated reward categories with shared conditions',
      () {
    const rewardEvidence = '''
Earn 3 Reward Points per Rs.100 spent across merchant categories.
Earn 5 Reward Points per Rs.100 spent on Dining and Grocery categories.
Earn 1 Reward Point per Rs.100 spent on Insurance and Utility categories.
''';
    final data = extraction();
    data['reward_points'] = {
      'base_rate': 3,
      'description':
          '3 reward points per Rs.100 spent across merchant categories',
      'evidence_excerpt':
          'Earn 3 Reward Points per Rs.100 spent across merchant categories.',
      'accelerated_categories': [
        {
          'category': 'Dining and Grocery',
          'rate': 5,
          'conditions': 'per Rs.100 spent',
          'evidence_excerpt':
              'Earn 5 Reward Points per Rs.100 spent on Dining and Grocery categories.',
        },
        {
          'category': 'Insurance and Utility',
          'rate': 1,
          'conditions': 'per Rs.100 spent',
          'evidence_excerpt':
              'Earn 1 Reward Point per Rs.100 spent on Insurance and Utility categories.',
        },
      ],
    };

    final result = BenefitExtractionValidator.validate(
      extractedData: data,
      evidenceText: '$evidence$rewardEvidence',
      cardName: 'Airtel',
      bankName: 'Axis Bank',
    );

    expect(result.reasonCodes, isNot(contains('duplicate_benefit')));
    expect(result.reasons, isEmpty, reason: result.reasonCodes.join(', '));
    expect(result.accepted, isTrue);
  });

  test('recovers omitted base reward evidence from an exact source claim', () {
    const rewardEvidence =
        'Earn 3 Reward Points per Rs.100 spent across merchant categories.';
    final data = extraction();
    data['reward_points'] = {
      'base_rate': 3,
      'accelerated_categories': [],
    };

    final result = BenefitExtractionValidator.validate(
      extractedData: data,
      evidenceText: '$evidence$rewardEvidence',
      cardName: 'Airtel',
      bankName: 'Axis Bank',
    );

    expect(result.reasonCodes, isNot(contains('missing_evidence')));
    expect(
      (result.normalizedData['reward_points'] as Map)['evidence_excerpt'],
      rewardEvidence,
    );
    expect(result.accepted, isTrue);
  });

  test('rejects a materially different card identity', () {
    final result = BenefitExtractionValidator.validate(
      extractedData: extraction(cardName: 'Axis ACE'),
      evidenceText: evidence,
      cardName: 'Airtel',
      bankName: 'Axis Bank',
    );

    expect(result.accepted, isFalse);
    expect(result.reasonCodes, contains('card_identity_mismatch'));
  });

  test('rejects unsupported special benefits instead of ignoring them', () {
    final data = extraction();
    data['special_benefits'] = [
      {
        'type': 'LOUNGE',
        'description': 'Complimentary airport lounge access',
        'value': null,
      }
    ];

    final result = BenefitExtractionValidator.validate(
      extractedData: data,
      evidenceText: evidence,
      cardName: 'Airtel',
      bankName: 'Axis Bank',
    );

    expect(result.accepted, isFalse);
    expect(result.reasonCodes, contains('missing_evidence'));
  });

  test('rejects unsupported reward-point claims instead of ignoring them', () {
    final data = extraction();
    data['reward_points'] = {
      'base_rate': 10,
      'description': 'Earn 10 reward points per ₹100 spent',
      'evidence_excerpt': '',
      'accelerated_categories': [],
    };

    final result = BenefitExtractionValidator.validate(
      extractedData: data,
      evidenceText: evidence,
      cardName: 'Airtel',
      bankName: 'Axis Bank',
    );

    expect(result.accepted, isFalse);
    expect(result.reasonCodes, contains('missing_evidence'));
  });

  test('does not impose spend-category conflicts on OTHER special benefits',
      () {
    final data = extraction();
    data['special_benefits'] = [
      {
        'type': 'OTHER',
        'description': '1% fuel surcharge waiver',
        'value': '1% waiver',
        'evidence_excerpt': '1% fuel surcharge waiver',
      }
    ];

    final result = BenefitExtractionValidator.validate(
      extractedData: data,
      evidenceText: '$evidence 1% fuel surcharge waiver',
      cardName: 'Airtel',
      bankName: 'Axis Bank',
    );

    expect(result.reasonCodes, isNot(contains('category_conflict')));
  });

  test('hard fee grounding failures reduce confidence below acceptance', () {
    final data = extraction();
    data['annual_fee'] = {
      'renewal': 499,
      'evidence_excerpt': 'Annual fee is ₹499 after spending ₹2,0,000.',
    };

    final result = BenefitExtractionValidator.validate(
      extractedData: data,
      evidenceText: '$evidence Annual fee is ₹499 after spending ₹2,00,000.',
      cardName: 'Airtel',
      bankName: 'Axis Bank',
    );

    expect(result.accepted, isFalse);
    expect(result.confidence, lessThan(0.8));
  });
}
