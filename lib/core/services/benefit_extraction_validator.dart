import 'benefit_evidence_segmenter.dart';

class BenefitValidationIssue {
  final String code;
  final String message;
  final int? benefitIndex;
  final String? sourceExcerpt;
  final String? suggestedKind;

  const BenefitValidationIssue(
    this.code,
    this.message, {
    this.benefitIndex,
    this.sourceExcerpt,
    this.suggestedKind,
  });

  Map<String, dynamic> toJson() => {
        'code': code,
        'message': message,
        if (benefitIndex != null) 'benefit_index': benefitIndex,
        if (sourceExcerpt != null) 'source_excerpt': sourceExcerpt,
        if (suggestedKind != null) 'suggested_kind': suggestedKind,
      };
}

class BenefitValidationResult {
  final bool accepted;
  final double confidence;
  final List<BenefitValidationIssue> reasons;
  final List<BenefitValidationIssue> warnings;
  final Map<String, dynamic> normalizedData;

  const BenefitValidationResult({
    required this.accepted,
    required this.confidence,
    required this.reasons,
    required this.warnings,
    required this.normalizedData,
  });

  List<String> get reasonCodes => reasons.map((issue) => issue.code).toList();

  Map<String, dynamic> toJson() => {
        'accepted': accepted,
        'confidence': confidence,
        'reasons': reasons.map((issue) => issue.toJson()).toList(),
        'warnings': warnings.map((issue) => issue.toJson()).toList(),
        'normalized_data': normalizedData,
      };
}

/// Enforces source grounding after AI extraction.
///
/// This validator deliberately contains no network, AI, or database calls. A
/// claim is accepted only when its evidence occurs in the supplied source and
/// every numeric value can be found in that evidence.
class BenefitExtractionValidator {
  static const validationVersion = 'benefit-grounding-v2';

  static final RegExp _nonBenefitPattern = RegExp(
    r'customer support|personal loan|savings account|current account|salary account|wealth management|request a callback|apply now|emi conversion facility|utility services|generic concierge',
    caseSensitive: false,
  );

  static final RegExp _placeholderPattern = RegExp(
    r'^(dining|travel|fuel|shopping|grocery|entertainment|utility|utilities|insurance|lounge(?: access)?|milestone|general) benefits?$',
    caseSensitive: false,
  );

  static BenefitValidationResult validate({
    required Map<String, dynamic> extractedData,
    required String evidenceText,
    required String cardName,
    required String bankName,
    String? sourceUrl,
  }) {
    final reasons = <BenefitValidationIssue>[];
    final warnings = <BenefitValidationIssue>[];
    final normalized = Map<String, dynamic>.from(extractedData);
    final normalizedEvidence = _normalizeText(evidenceText);

    final extractedCard = extractedData['card_name']?.toString() ?? '';
    final extractedBank = extractedData['bank_name']?.toString() ?? '';
    if (!_sameIdentity(extractedCard, cardName)) {
      reasons.add(const BenefitValidationIssue(
        'card_identity_mismatch',
        'The extracted card identity does not match the requested variant.',
      ));
    }
    if (!_sameIdentity(extractedBank, bankName)) {
      reasons.add(const BenefitValidationIssue(
        'bank_identity_mismatch',
        'The extracted bank identity does not match the requested bank.',
      ));
    }

    final rawBenefits = extractedData['benefits'] ??
        extractedData['cashback_benefits'] ??
        const <dynamic>[];
    final benefits = rawBenefits is List
        ? rawBenefits.whereType<Map>().map(Map<String, dynamic>.from).toList()
        : <Map<String, dynamic>>[];
    final specialBenefits = extractedData['special_benefits'] is List
        ? (extractedData['special_benefits'] as List)
            .whereType<Map>()
            .map((raw) {
            final benefit = Map<String, dynamic>.from(raw);
            benefit['category'] ??= benefit['type'] ?? 'GENERAL';
            return benefit;
          }).toList()
        : <Map<String, dynamic>>[];
    final rewardClaims = <Map<String, dynamic>>[];
    final rawRewards = extractedData['reward_points'];
    if (rawRewards is Map) {
      final rewards = Map<String, dynamic>.from(rawRewards);
      final baseRate = rewards['base_rate'];
      final baseEvidence = rewards['evidence_excerpt']?.toString().trim();
      if (baseRate is num && (baseEvidence == null || baseEvidence.isEmpty)) {
        final recoveredEvidence =
            _findBaseRewardEvidence(evidenceText, baseRate);
        if (recoveredEvidence != null) {
          rewards['evidence_excerpt'] = recoveredEvidence;
        }
      }
      normalized['reward_points'] = rewards;
      if (rewards['base_rate'] is num) {
        rewardClaims.add({
          'category': 'REWARDS',
          'rate': rewards['base_rate'],
          'description':
              rewards['description'] ?? 'Base reward points earning rate',
          'evidence_excerpt': rewards['evidence_excerpt'],
        });
      }
      if (rewards['accelerated_categories'] is List) {
        for (final raw in rewards['accelerated_categories'] as List) {
          if (raw is! Map) continue;
          final accelerated = Map<String, dynamic>.from(raw);
          rewardClaims.add({
            'category': accelerated['category'] ?? 'REWARDS',
            'rate': accelerated['rate'],
            'description': accelerated['description'] ??
                _acceleratedRewardDescription(accelerated),
            'evidence_excerpt': accelerated['evidence_excerpt'],
          });
        }
      }
    }
    final repairCandidates = extractedData['repair_candidates'] is List
        ? (extractedData['repair_candidates'] as List)
            .whereType<Map>()
            .map((raw) => Map<String, dynamic>.from(raw))
            .toList()
        : <Map<String, dynamic>>[];
    final claims = [
      ...benefits,
      ...specialBenefits,
      ...rewardClaims,
      ...repairCandidates,
    ];

    if (claims.isEmpty) {
      reasons.add(const BenefitValidationIssue(
        'no_supported_benefits',
        'The extraction contains no benefit claims.',
      ));
    }

    final seenDescriptions = <String, int>{};
    final extractedEvidence = <String>[];
    var groundedClaims = 0;
    for (var index = 0; index < claims.length; index++) {
      final benefit = claims[index];
      final description = benefit['description']?.toString().trim() ?? '';
      final excerpt = benefit['evidence_excerpt']?.toString().trim() ?? '';
      final category =
          benefit['category']?.toString().toUpperCase() ?? 'GENERAL';
      final value = benefit['value'] ?? benefit['rate'];

      if (excerpt.isEmpty) {
        reasons.add(BenefitValidationIssue(
          'missing_evidence',
          'Benefit claim has no evidence excerpt.',
          benefitIndex: index,
        ));
      } else if (!normalizedEvidence.contains(_normalizeText(excerpt))) {
        reasons.add(BenefitValidationIssue(
          'evidence_not_in_source',
          'Benefit evidence does not occur in the scraped source.',
          benefitIndex: index,
        ));
      } else {
        groundedClaims++;
        extractedEvidence.add(_normalizeText(excerpt));
      }

      if (description.isEmpty ||
          _placeholderPattern.hasMatch(description) ||
          (value is num && value == 0)) {
        reasons.add(BenefitValidationIssue(
          'placeholder_benefit',
          'Placeholder or zero-value category rows are not benefits.',
          benefitIndex: index,
        ));
      }

      if (_nonBenefitPattern.hasMatch('$description $excerpt')) {
        reasons.add(BenefitValidationIssue(
          'non_benefit_content',
          'Banking promotion or page chrome was classified as a benefit.',
          benefitIndex: index,
        ));
      }

      if (_hasCategoryConflict(category, description)) {
        reasons.add(BenefitValidationIssue(
          'category_conflict',
          'Benefit description contradicts its assigned category.',
          benefitIndex: index,
        ));
      }

      final descriptionKey = _normalizeText(description);
      if (descriptionKey.isNotEmpty &&
          seenDescriptions.containsKey(descriptionKey)) {
        reasons.add(BenefitValidationIssue(
          'duplicate_benefit',
          'The same benefit was emitted more than once.',
          benefitIndex: index,
        ));
      } else if (descriptionKey.isNotEmpty) {
        seenDescriptions[descriptionKey] = index;
      }

      if (excerpt.isNotEmpty) {
        final unsupported = _unsupportedNumbers(benefit, excerpt);
        if (unsupported.isNotEmpty) {
          reasons.add(BenefitValidationIssue(
            'unsupported_numeric_value',
            'Numeric values ${unsupported.join(', ')} are absent from the evidence.',
            benefitIndex: index,
          ));
        }
      }
    }

    warnings.addAll(_findUnextractedSourceClaims(
      evidenceText: evidenceText,
      extractedEvidence: extractedEvidence,
    ));

    _validateAnnualFee(
        extractedData['annual_fee'], normalizedEvidence, reasons);

    final identityScore = reasons.any((issue) =>
            issue.code == 'card_identity_mismatch' ||
            issue.code == 'bank_identity_mismatch')
        ? 0.0
        : 0.25;
    final evidenceScore =
        claims.isEmpty ? 0.0 : 0.5 * groundedClaims / claims.length;
    final numericScore =
        reasons.any((issue) => issue.code == 'unsupported_numeric_value')
            ? 0.0
            : 0.25;
    final rawConfidence =
        (identityScore + evidenceScore + numericScore).clamp(0.0, 1.0);
    final confidence =
        reasons.isEmpty ? rawConfidence : rawConfidence.clamp(0.0, 0.75);

    normalized['benefits'] = benefits;
    if (repairCandidates.isNotEmpty) {
      normalized['repair_candidates'] = repairCandidates;
    }
    normalized['validation_version'] = validationVersion;
    normalized['calculated_confidence'] = confidence;

    return BenefitValidationResult(
      accepted: reasons.isEmpty && confidence >= 0.8,
      confidence: confidence,
      reasons: reasons,
      warnings: warnings,
      normalizedData: normalized,
    );
  }

  static void _validateAnnualFee(
    dynamic rawAnnualFee,
    String normalizedEvidence,
    List<BenefitValidationIssue> reasons,
  ) {
    if (rawAnnualFee is! Map) return;
    final fee = Map<String, dynamic>.from(rawAnnualFee);
    final numericValues =
        [fee['first_year'], fee['renewal']].whereType<num>().toList();
    if (numericValues.isEmpty) return;
    final excerpt = fee['evidence_excerpt']?.toString().trim() ?? '';
    if (excerpt.isEmpty ||
        !normalizedEvidence.contains(_normalizeText(excerpt))) {
      reasons.add(const BenefitValidationIssue(
        'missing_fee_evidence',
        'A fee value was supplied without source evidence.',
      ));
      return;
    }
    for (final value in numericValues) {
      if (!_containsNumber(excerpt, value)) {
        reasons.add(const BenefitValidationIssue(
          'unsupported_fee_value',
          'A fee value is absent from its evidence excerpt.',
        ));
        return;
      }
    }
  }

  static String _acceleratedRewardDescription(Map<String, dynamic> reward) {
    final rate = reward['rate']?.toString();
    final category = reward['category']?.toString() ?? 'eligible categories';
    final conditions = reward['conditions']?.toString().trim();
    final rateLabel = rate == null || rate.isEmpty
        ? 'Accelerated reward points'
        : '$rate reward points';
    return '$rateLabel${conditions == null || conditions.isEmpty ? '' : ' $conditions'} on $category';
  }

  /// Finds source-backed benefit sentences that were never represented by an
  /// extracted evidence excerpt. These are review warnings, not validation
  /// failures: a human may accept or reject the exact source-backed claim.
  static List<BenefitValidationIssue> _findUnextractedSourceClaims({
    required String evidenceText,
    required List<String> extractedEvidence,
  }) {
    const markers = <String, String>{
      'foreign mark-up': 'FOREX',
      'foreign markup': 'FOREX',
      'concierge': 'CONCIERGE',
      'lounge': 'LOUNGE',
      'reward point': 'REWARDS',
      'fuel surcharge waiver': 'FUEL',
      'air accident': 'INSURANCE',
      'credit shield': 'INSURANCE',
      'purchase protection': 'INSURANCE',
      'itc hotels': 'TRAVEL',
      'elivaas': 'TRAVEL',
      'meet & greet': 'TRAVEL',
      'dine with visa': 'DINING',
    };
    final warnings = <BenefitValidationIssue>[];
    final seen = <String>{};
    final sentences = BenefitEvidenceSegmenter.clauses(evidenceText);

    for (final sentence in sentences) {
      final normalizedSentence = _normalizeText(sentence);
      if (normalizedSentence.isEmpty ||
          _nonBenefitPattern.hasMatch(sentence) ||
          !seen.add(normalizedSentence)) {
        continue;
      }
      final matchedMarker =
          markers.entries.cast<MapEntry<String, String>?>().firstWhere(
                (entry) =>
                    entry != null &&
                    normalizedSentence.contains(_normalizeText(entry.key)),
                orElse: () => null,
              );
      if (matchedMarker == null ||
          extractedEvidence.any(
            (excerpt) => excerpt.contains(normalizedSentence),
          )) {
        continue;
      }
      warnings.add(BenefitValidationIssue(
        'unextracted_source_claim',
        'Source-backed ${matchedMarker.value.toLowerCase()} benefit was not extracted: $sentence',
        sourceExcerpt: sentence,
        suggestedKind: matchedMarker.value,
      ));
    }
    return warnings;
  }

  /// Recovers an omitted model excerpt only when the scraped source contains
  /// both the extracted rate and an explicit reward-points phrase.
  static String? _findBaseRewardEvidence(String evidenceText, num rate) {
    final candidates = BenefitEvidenceSegmenter.clauses(evidenceText);
    for (final candidate in candidates) {
      if (_containsNumber(candidate, rate) &&
          RegExp(r'\breward\s+points?\b', caseSensitive: false)
              .hasMatch(candidate)) {
        return candidate;
      }
    }
    return null;
  }

  static List<String> _unsupportedNumbers(
      Map<String, dynamic> benefit, String excerpt) {
    const numericFields = [
      'value',
      'rate',
      'monthly_cap',
      'annual_cap',
      'min_spend_threshold',
      'max_cap_limit',
      'lounge_count',
    ];
    final unsupported = <String>[];
    for (final field in numericFields) {
      final value = benefit[field];
      if (value is num && value != 0 && !_containsNumber(excerpt, value)) {
        unsupported.add('$field=$value');
      }
    }
    return unsupported;
  }

  static bool _containsNumber(String text, num value) {
    final digits = text.replaceAll(RegExp(r'[^0-9.]'), ' ');
    final candidates = RegExp(r'\d+(?:\.\d+)?')
        .allMatches(digits)
        .map((match) => double.tryParse(match.group(0)!))
        .whereType<double>();
    return candidates
            .any((candidate) => (candidate - value.toDouble()).abs() < 0.001) ||
        text.replaceAll(RegExp(r'[^0-9]'), '').contains(
              value
                  .toStringAsFixed(value is int ? 0 : 2)
                  .replaceAll(RegExp(r'[^0-9]'), ''),
            );
  }

  static bool _hasCategoryConflict(String category, String description) {
    if (const {'OTHER', 'LOUNGE', 'INSURANCE', 'CONCIERGE'}
        .contains(category)) {
      return false;
    }
    final lower = description.toLowerCase();
    if (lower.contains('fuel') && !category.contains('FUEL')) return true;
    if ((lower.contains('dining') || lower.contains('restaurant')) &&
        !category.contains('DINING') &&
        !const {'CASHBACK', 'REWARDS'}.contains(category)) {
      return true;
    }
    return false;
  }

  static bool _sameIdentity(String left, String right) {
    final a = _identityTokens(left);
    final b = _identityTokens(right);
    if (a.isEmpty || b.isEmpty) return false;
    return a.containsAll(b) || b.containsAll(a);
  }

  static Set<String> _identityTokens(String value) {
    const ignored = {'bank', 'credit', 'card', 'the', 'first'};
    return _normalizeText(value)
        .split(' ')
        .where((token) => token.isNotEmpty && !ignored.contains(token))
        .toSet();
  }

  static String _normalizeText(String value) => value
      .toLowerCase()
      .replaceAll('&', ' and ')
      .replaceAll(RegExp(r'[^a-z0-9.%₹]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
