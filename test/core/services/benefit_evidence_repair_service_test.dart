import 'package:cardcompass/core/services/benefit_evidence_segmenter.dart';
import 'package:cardcompass/core/services/benefit_repair_service.dart';
import 'package:cardcompass/core/services/benefit_extraction_validator.dart';
import 'package:cardcompass/core/services/gemini_transaction_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('evidence segmentation preserves Rupee abbreviations in a claim', () {
    const source =
        'Earn 1,000 Bonus Reward Points on achieving minimum spending of Rs. 50,000 or more within a statement cycle.\n'
        'Other content.';

    expect(
        BenefitEvidenceSegmenter.clauses(source),
        contains(
          'Earn 1,000 Bonus Reward Points on achieving minimum spending of Rs. 50,000 or more within a statement cycle.',
        ));
  });

  test('repair targets retain material source claims and discard headings', () {
    const warnings = [
      BenefitValidationIssue(
        'unextracted_source_claim',
        'Missing fuel claim.',
        sourceExcerpt: 'Fuel Surcharge Waiver',
        suggestedKind: 'FUEL',
      ),
      BenefitValidationIssue(
        'unextracted_source_claim',
        'Missing rewards claim.',
        sourceExcerpt:
            'Earn 3 Reward Points per Rs.100 spent across merchant categories.',
        suggestedKind: 'REWARDS',
      ),
      BenefitValidationIssue(
        'unextracted_source_claim',
        'Missing concierge claim.',
        sourceExcerpt: '24x7 Global Concierge Service',
        suggestedKind: 'CONCIERGE',
      ),
    ];

    final targets = BenefitRepairService.buildTargets(warnings);

    expect(targets, hasLength(2));
    expect(targets.map((target) => target.kind),
        containsAll(['REWARDS', 'CONCIERGE']));
    expect(targets.first.sourceExcerpt, contains('3 Reward Points'));
  });

  test('merges only repair output whose verbatim evidence matches its target',
      () {
    const target = BenefitRepairTarget(
      id: 'repair:0',
      kind: 'FUEL',
      sourceExcerpt:
          'Enjoy 1% Fuel Surcharge Waiver (up to ₹1000) for transactions between ₹400 and ₹5,000.',
    );
    final merged = BenefitRepairService.mergeGroundedRepairs(
      extractedData: const {'card_name': 'Zenith', 'bank_name': 'AU Bank'},
      targets: const [target],
      rawRepairs: const [
        {
          'target_id': 'repair:0',
          'category': 'FUEL',
          'type': 'FUEL_SURCHARGE_WAIVER',
          'description': '1% fuel surcharge waiver',
          'rate': 1,
          'rate_type': 'percentage',
          'max_cap_limit': 1000,
          'conditions': 'Transactions between ₹400 and ₹5,000.',
          'evidence_excerpt':
              'Enjoy 1% Fuel Surcharge Waiver (up to ₹1000) for transactions between ₹400 and ₹5,000.',
        },
        {
          'target_id': 'repair:0',
          'category': 'FUEL',
          'description': 'Ungrounded duplicate',
          'evidence_excerpt': 'A different sentence.',
        },
      ],
    );

    final repairs = merged['repair_candidates'] as List;
    expect(repairs, hasLength(1));
    expect(repairs.single['repair_pass'], isTrue);
    expect(repairs.single['max_cap_limit'], 1000);
  });

  test('validator keeps a complete monetary clause as a repair target', () {
    const source = 'AU Zenith Credit Card\n'
        'Earn 1,000 Bonus Reward Points on achieving minimum spending of Rs. 50,000 or more within a statement cycle.';
    final result = BenefitExtractionValidator.validate(
      extractedData: const {
        'card_name': 'Zenith',
        'bank_name': 'AU',
        'special_benefits': [
          {
            'type': 'CONCIERGE',
            'description': '24x7 Global Concierge Service',
            'evidence_excerpt': '24x7 Global Concierge Service',
          },
        ],
      },
      evidenceText: source,
      cardName: 'Zenith',
      bankName: 'AU',
    );

    final target = BenefitRepairService.buildTargets(result.warnings).single;
    expect(target.sourceExcerpt, contains('Rs. 50,000 or more'));
  });

  test('repair prompt requires target identifiers and verbatim evidence', () {
    const target = BenefitRepairTarget(
      id: 'repair:0',
      kind: 'REWARDS',
      sourceExcerpt: 'Earn 3 Reward Points per Rs.100 spent.',
    );

    final prompt = GeminiTransactionParser.buildBenefitRepairPrompt(
      cardName: 'Zenith',
      bankName: 'AU Bank',
      targets: const [target],
    );

    expect(prompt, contains('repair:0'));
    expect(prompt, contains('evidence_excerpt'));
    expect(prompt, contains('exactly as supplied'));
  });
}
