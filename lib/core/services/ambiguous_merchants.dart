/// Merchants known to genuinely span multiple spend categories, where no
/// single fixed category is correct for every transaction (spec §1). These
/// must never appear as a key in `merchant_category_seed.dart` — seeding
/// one of them with any single category would give the same wrong answer,
/// every time, for every purchase type that isn't the one seeded category.
/// Checked before the merchant-lookup tier of the categorizer runs;
/// a denylisted merchant always falls through to Gemini's own value or
/// keyword matching, both of which can react to per-transaction context
/// (e.g. "AMAZON PRIME MEMBERSHIP" vs. "AMAZON.IN PURCHASE") that a bare
/// merchant name can't.
const Set<String> ambiguousMerchants = {
  'AMAZON',
  'PAYPAL',
};
