import 'benefit_extraction_validator.dart';

class BenefitStagingPolicy {
  static Map<String, dynamic> buildInsertPayload({
    required String cardId,
    required String sourceUrl,
    required String sourceEvidence,
    required BenefitValidationResult validation,
    DateTime? now,
  }) {
    final validatedAt = (now ?? DateTime.now()).toUtc().toIso8601String();
    return {
      'card_id': cardId,
      'source_url': sourceUrl,
      'extracted_data': validation.normalizedData,
      'status': validation.accepted ? 'pending' : 'rejected',
      'validation_version': BenefitExtractionValidator.validationVersion,
      'calculated_confidence': validation.confidence,
      'validation_reasons':
          validation.reasons.map((reason) => reason.toJson()).toList(),
      'validation_warnings':
          validation.warnings.map((warning) => warning.toJson()).toList(),
      'source_evidence': {'text': sourceEvidence},
      'validated_at': validatedAt,
      'rejected_at': validation.accepted ? null : validatedAt,
    };
  }

  static bool canApprove(Map<String, dynamic> stagingRecord) {
    final evidence = stagingRecord['source_evidence'];
    final evidenceText = evidence is Map ? evidence['text']?.toString() : null;
    final reasons = stagingRecord['validation_reasons'];
    return stagingRecord['status'] == 'pending' &&
        stagingRecord['validation_version'] ==
            BenefitExtractionValidator.validationVersion &&
        (stagingRecord['calculated_confidence'] as num? ?? 0) >= 0.8 &&
        reasons is List &&
        reasons.isEmpty &&
        evidenceText != null &&
        evidenceText.trim().isNotEmpty;
  }
}
