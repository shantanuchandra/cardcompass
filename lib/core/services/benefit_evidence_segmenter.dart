/// Splits scraped benefit content into reviewable clauses without breaking
/// monetary abbreviations such as `Rs.` or decimal values.
class BenefitEvidenceSegmenter {
  const BenefitEvidenceSegmenter._();

  static List<String> clauses(String evidenceText) {
    if (evidenceText.trim().isEmpty) return const [];

    final protected = _protectPeriods(evidenceText)
        .replaceAll(RegExp(r'\r\n?'), '\n')
        .replaceAll(RegExp(r'[\t ]+'), ' ');

    return protected
        .split(RegExp(r'(?<=[.!?])\s+|\n+'))
        .map(_restorePeriods)
        .map((clause) => clause.trim())
        .where((clause) => clause.isNotEmpty)
        .toList(growable: false);
  }

  static String _protectPeriods(String value) {
    var protected = value;
    for (final abbreviation in const [
      'Rs.',
      'Mr.',
      'Mrs.',
      'Ms.',
      'Dr.',
      'No.',
      'e.g.',
      'i.e.',
    ]) {
      protected = protected.replaceAll(
        RegExp(RegExp.escape(abbreviation), caseSensitive: false),
        abbreviation.replaceAll('.', '∯'),
      );
    }
    return protected.replaceAllMapped(
      RegExp(r'(\d)\.(\d)'),
      (match) => '${match.group(1)}∯${match.group(2)}',
    );
  }

  static String _restorePeriods(String value) => value.replaceAll('∯', '.');
}
