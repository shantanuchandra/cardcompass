import 'ambiguous_merchants.dart';

const Set<String> validCategories = {
  'food', 'fuel', 'grocery', 'entertainment', 'travel', 'shopping',
  'utilities', 'insurance', 'medical', 'education', 'investment',
  'transport', 'rental', 'subscription', 'gift', 'other',
};

/// Which tier resolved a transaction's category — persisted in
/// `transactions.metadata['category_source']` (see Task 6) for
/// auditability. `unresolved` means even the keyword-fallback tier found
/// nothing and the category fell to 'other'.
enum CategorizationSource { merchantMap, geminiValidated, keywordFallback, unresolved }

class CategorizationResult {
  final String category;
  final CategorizationSource source;
  const CategorizationResult(this.category, this.source);
}

/// Normalizes a merchant name for lookup: uppercase, trimmed, internal
/// whitespace collapsed to single spaces. Must match how
/// `merchant_category_seed.dart`'s keys are normalized, so lookups hit.
String normalizeMerchantName(String raw) {
  return raw.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
}

/// Whether [category] (case-insensitive) is one of the 16 categories this
/// app recognizes. Used to decide whether to trust Gemini's own per-transaction
/// category guess (see `categorize`) rather than assuming its prompt
/// instructions were followed exactly. Trims incidental whitespace before
/// comparing, since Gemini's raw output may include leading/trailing spaces.
bool isValidCategory(String? category) {
  if (category == null || category.isEmpty) return false;
  return validCategories.contains(category.trim().toLowerCase());
}

/// Keyword phrases that, if found anywhere in a transaction description,
/// indicate a category. Deliberately covers only the 13 categories with
/// deterministic signals — investment, rental, and gift have no reliable
/// universal keyword (spec Taxonomy section: "what generic word reliably
/// signals 'rental' without also matching unrelated transactions?"),
/// so they're intentionally absent here and can only be resolved via
/// Gemini's own value (tier 2).
const List<(String keyword, String category)> _keywordCategoryRules = [
  // Food
  ('SWIGGY', 'food'), ('ZOMATO', 'food'), ('TALABAT', 'food'),
  ('DELIVEROO', 'food'), ('RESTAURANT', 'food'), ('CAFE', 'food'),
  // Grocery
  ('CARREFOUR', 'grocery'), ('LULU', 'grocery'), ('BIGBASKET', 'grocery'),
  ('SUPERMARKET', 'grocery'), ('HYPERMARKET', 'grocery'),
  // Shopping
  ('AMAZON', 'shopping'), ('FLIPKART', 'shopping'), ('NOON', 'shopping'),
  ('MYNTRA', 'shopping'),
  // Transport
  ('OLA', 'transport'), ('UBER', 'transport'), ('CAREEM', 'transport'),
  ('METRO', 'transport'), ('CAB', 'transport'),
  // Fuel
  ('PETROL', 'fuel'), ('FUEL', 'fuel'), ('ADNOC', 'fuel'), ('ENOC', 'fuel'),
  ('INDIAN OIL', 'fuel'), ('HPCL', 'fuel'),
  // Entertainment
  ('NETFLIX', 'entertainment'), ('SPOTIFY', 'entertainment'),
  ('CINEMA', 'entertainment'), ('MOVIE', 'entertainment'),
  // Travel
  ('AIRLINE', 'travel'), ('MAKEMYTRIP', 'travel'), ('EMIRATES', 'travel'),
  ('BOOKING.COM', 'travel'), ('AIRBNB', 'travel'), ('HOTEL', 'travel'),
  // Utilities
  ('ELECTRICITY', 'utilities'), ('DEWA', 'utilities'), ('ETISALAT', 'utilities'),
  ('WATER BILL', 'utilities'),
  // Medical
  ('PHARMACY', 'medical'), ('HOSPITAL', 'medical'), ('CLINIC', 'medical'),
  // Insurance
  ('INSURANCE', 'insurance'), ('PREMIUM', 'insurance'),
  // Education
  ('SCHOOL FEE', 'education'), ('TUITION', 'education'), ('UDEMY', 'education'),
  // Subscription
  ('SUBSCRIPTION', 'subscription'),
];

/// Scans [description] for known keyword phrases (see
/// `_keywordCategoryRules`), returning the first match's category, or null
/// if nothing matches. Case-insensitive.
String? keywordCategoryFor(String description) {
  final upper = description.toUpperCase();
  for (final (keyword, category) in _keywordCategoryRules) {
    if (upper.contains(keyword)) return category;
  }
  return null;
}

/// Resolves a transaction's category through three tiers, in priority
/// order:
/// 1. Merchant lookup ([merchantLookup]) — deterministic, wins even over a
///    Gemini-provided value, since a known merchant is more reliable than a
///    per-call LLM guess. Skipped entirely for a denylisted ambiguous
///    merchant (`ambiguous_merchants.dart`) — those go straight to tier 2.
/// 2. Gemini's own [geminiCategory], trusted only when it's one of the 16
///    valid categories — Gemini's prompt asks for the right vocabulary but
///    isn't guaranteed to comply.
/// 3. Keyword matching against [description] — last resort when neither of
///    the above resolves anything.
///
/// [merchantLookup] is injected (rather than this function querying
/// `merchant_category_map` directly) so this whole decision tree stays pure
/// and unit-testable without a Supabase client. The caller (see
/// `statement_processing_service.dart`, Task 6) supplies a real lookup
/// backed by the seed map. There is NO write-back anywhere in this
/// function or its caller — an earlier design wrote tier-3 results back to
/// the shared table; that leaked private statement data and was removed
/// (spec §1/§3).
CategorizationResult categorize({
  required String merchantName,
  required String description,
  required String? geminiCategory,
  required String? Function(String normalizedMerchantName) merchantLookup,
}) {
  final normalized = normalizeMerchantName(merchantName);

  if (!ambiguousMerchants.contains(normalized)) {
    final mapped = merchantLookup(normalized);
    if (mapped != null) {
      return CategorizationResult(mapped, CategorizationSource.merchantMap);
    }
  }

  if (isValidCategory(geminiCategory)) {
    return CategorizationResult(geminiCategory!.trim().toLowerCase(), CategorizationSource.geminiValidated);
  }

  final keywordMatch = keywordCategoryFor(description);
  if (keywordMatch != null) {
    return CategorizationResult(keywordMatch, CategorizationSource.keywordFallback);
  }

  return const CategorizationResult('other', CategorizationSource.unresolved);
}
