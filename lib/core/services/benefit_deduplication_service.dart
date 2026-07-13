/// Generates the canonical identity used by the database-backed benefit
/// deduplication index. Keep this in lockstep with the SQL migration.
class BenefitDeduplicationService {
  const BenefitDeduplicationService._();

  static String keyFor({
    String? category,
    String? type,
    required String title,
  }) =>
      [category, type, title].map(_normalize).join('|');

  static String _normalize(String? value) =>
      (value ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}
