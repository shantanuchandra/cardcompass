/// Converts scraped category prose into the stable category identifiers used
/// by benefit_category_mapping.
class BenefitCategoryNormalizer {
  const BenefitCategoryNormalizer._();

  static const _knownIds = {
    'CASHBACK',
    'CONCIERGE',
    'DINING',
    'ENTERTAINMENT',
    'FUEL',
    'GENERAL',
    'GOLF',
    'GROCERY',
    'HEALTHCARE',
    'INSURANCE',
    'LOUNGE',
    'MILES',
    'OTHER',
    'POINTS',
    'SHOPPING',
    'TRAVEL',
    'UTILITIES',
  };

  static List<String> idsFor(Map<String, dynamic> source) {
    final category = source['category']?.toString().trim().toUpperCase();
    final type = source['type']?.toString().trim().toUpperCase();
    for (final explicit in [category, type]) {
      if (explicit != null && _knownIds.contains(explicit)) return [explicit];
    }

    final text = [
      source['category'],
      source['type'],
      source['description'],
      source['conditions'],
    ].whereType<Object>().join(' ').toLowerCase();
    final ids = <String>[];

    void addIf(bool matches, String id) {
      if (matches && !ids.contains(id)) ids.add(id);
    }

    addIf(text.contains('fuel'), 'FUEL');
    addIf(text.contains('dining') || text.contains('restaurant'), 'DINING');
    addIf(text.contains('grocery') || text.contains('supermarket'), 'GROCERY');
    addIf(
        text.contains('departmental') || text.contains('shopping'), 'SHOPPING');
    addIf(text.contains('lounge'), 'LOUNGE');
    addIf(text.contains('concierge'), 'CONCIERGE');
    addIf(text.contains('insurance'), 'INSURANCE');
    addIf(text.contains('utility') || text.contains('telecom'), 'UTILITIES');
    addIf(text.contains('travel'), 'TRAVEL');
    addIf(text.contains('entertainment'), 'ENTERTAINMENT');
    addIf(text.contains('cashback'), 'CASHBACK');
    addIf(text.contains('golf'), 'GOLF');
    addIf(text.contains('health'), 'HEALTHCARE');
    addIf(text.contains('mile'), 'MILES');

    return ids.isEmpty ? ['GENERAL'] : ids;
  }
}
