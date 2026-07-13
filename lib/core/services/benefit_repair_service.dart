import 'benefit_extraction_validator.dart';

/// A deterministic boundary around the optional second LLM pass. It decides
/// which source clauses are worth repairing and permits only model output
/// backed by the exact clause it was asked to interpret.
class BenefitRepairTarget {
  const BenefitRepairTarget({
    required this.id,
    required this.kind,
    required this.sourceExcerpt,
  });

  final String id;
  final String kind;
  final String sourceExcerpt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'source_excerpt': sourceExcerpt,
      };
}

class BenefitRepairService {
  const BenefitRepairService._();

  static List<BenefitRepairTarget> buildTargets(
    List<BenefitValidationIssue> warnings,
  ) {
    final seen = <String>{};
    final targets = <BenefitRepairTarget>[];

    for (final warning in warnings) {
      if (warning.code != 'unextracted_source_claim') continue;
      final excerpt = warning.sourceExcerpt?.trim() ?? '';
      if (!_isMaterialClaim(excerpt) || !seen.add(_key(excerpt))) continue;
      targets.add(BenefitRepairTarget(
        id: 'repair:${targets.length}',
        kind: warning.suggestedKind?.toUpperCase() ?? 'GENERAL',
        sourceExcerpt: excerpt,
      ));
    }
    return List.unmodifiable(targets);
  }

  /// Adds accepted second-pass items into a separate collection so the review
  /// UI can make their provenance obvious. Existing first-pass extraction data
  /// is never overwritten by this method.
  static Map<String, dynamic> mergeGroundedRepairs({
    required Map<String, dynamic> extractedData,
    required List<BenefitRepairTarget> targets,
    required List<dynamic> rawRepairs,
  }) {
    final merged = Map<String, dynamic>.from(extractedData);
    final targetById = {for (final target in targets) target.id: target};
    final accepted = <Map<String, dynamic>>[];
    final seen = <String>{};

    for (final raw in rawRepairs) {
      if (raw is! Map) continue;
      final repair = Map<String, dynamic>.from(raw);
      final target = targetById[repair['target_id']?.toString()];
      final excerpt = repair['evidence_excerpt']?.toString().trim() ?? '';
      final description = repair['description']?.toString().trim() ?? '';
      if (target == null ||
          description.isEmpty ||
          !_sameVerbatimExcerpt(excerpt, target.sourceExcerpt)) {
        continue;
      }

      final key = '${target.id}:${_key(description)}';
      if (!seen.add(key)) continue;
      repair
        ..['category'] =
            repair['category']?.toString().toUpperCase() ?? target.kind
        ..['type'] = repair['type']?.toString().toUpperCase() ?? target.kind
        ..['evidence_excerpt'] = target.sourceExcerpt
        ..['repair_target_id'] = target.id
        ..['repair_pass'] = true;
      accepted.add(repair);
    }

    merged['repair_candidates'] = accepted;
    merged['repair_metadata'] = {
      'attempted': true,
      'targets': targets.map((target) => target.toJson()).toList(),
      'accepted_count': accepted.length,
    };
    return merged;
  }

  static bool _isMaterialClaim(String excerpt) {
    final compact = excerpt.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.length < 16) return false;
    if (RegExp(r'\d').hasMatch(compact)) return true;
    if (compact.length < 32) return false;
    return RegExp(
      r'\b(dine with visa|itc hotels|elivaas|meet\s*(?:and|&)\s*greet|air accident|credit shield|purchase protection|zero liability|stay for|travel cover)\b',
      caseSensitive: false,
    ).hasMatch(compact);
  }

  static bool _sameVerbatimExcerpt(String left, String right) =>
      _key(left) == _key(right);

  static String _key(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll('“', '"')
      .replaceAll('”', '"')
      .trim();
}
