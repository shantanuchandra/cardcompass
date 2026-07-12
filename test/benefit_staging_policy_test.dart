import 'package:cardcompass/core/services/benefit_extraction_validator.dart';
import 'package:cardcompass/core/services/benefit_staging_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  BenefitValidationResult result(bool accepted) => BenefitValidationResult(
        accepted: accepted,
        confidence: accepted ? 0.9 : 0.3,
        reasons: accepted
            ? const []
            : const [
                BenefitValidationIssue(
                  'missing_evidence',
                  'A claim has no source evidence.',
                )
              ],
        warnings: const [],
        normalizedData: const {
          'card_name': 'Airtel',
          'bank_name': 'Axis Bank',
          'benefits': [],
        },
      );

  test('accepted extraction is staged as pending with validation metadata', () {
    final payload = BenefitStagingPolicy.buildInsertPayload(
      cardId: 'card-id',
      sourceUrl: 'https://www.axisbank.com/card',
      sourceEvidence: '25% cashback on Airtel payments.',
      validation: result(true),
      now: DateTime.utc(2026, 7, 12),
    );

    expect(payload['status'], 'pending');
    expect(payload['rejected_at'], isNull);
    expect(payload['validation_version'],
        BenefitExtractionValidator.validationVersion);
    expect(payload['calculated_confidence'], 0.9);
  });

  test('invalid extraction is retained as rejected with reasons', () {
    final now = DateTime.utc(2026, 7, 12);
    final payload = BenefitStagingPolicy.buildInsertPayload(
      cardId: 'card-id',
      sourceUrl: 'https://www.axisbank.com/card',
      sourceEvidence: 'Travel benefits',
      validation: result(false),
      now: now,
    );

    expect(payload['status'], 'rejected');
    expect(payload['rejected_at'], now.toIso8601String());
    expect(payload['validation_reasons'], isNotEmpty);
  });

  test('approval requires pending accepted current-version validation', () {
    expect(
      BenefitStagingPolicy.canApprove({
        'status': 'pending',
        'validation_version': BenefitExtractionValidator.validationVersion,
        'calculated_confidence': 0.9,
        'validation_reasons': [],
        'source_evidence': {'text': 'grounded evidence'},
      }),
      isTrue,
    );
    expect(
      BenefitStagingPolicy.canApprove({
        'status': 'rejected',
        'validation_version': BenefitExtractionValidator.validationVersion,
        'calculated_confidence': 0.9,
        'validation_reasons': [],
        'source_evidence': {'text': 'grounded evidence'},
      }),
      isFalse,
    );
    expect(
      BenefitStagingPolicy.canApprove({
        'status': 'pending',
        'validation_version': 'old-validator',
        'calculated_confidence': 0.9,
        'validation_reasons': [],
        'source_evidence': {'text': 'grounded evidence'},
      }),
      isFalse,
    );
  });
}
