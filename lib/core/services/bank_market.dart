/// UAE banks currently recognized by `CardNormalizerService.normalizeBankName`.
/// Kept as its own small list here (rather than exposing internals of
/// CardNormalizerService) so `currencyForBank` has one place to check —
/// takes an already-normalized bank name (the canonical form
/// `normalizeBankName` returns), not a raw sender/subject string.
const Set<String> _uaeBanks = {
  'FAB',
  'Emirates NBD',
  'ADCB',
  'Mashreq',
  'CBD',
  'Dubai Islamic Bank',
  'RAKBANK',
  'Emirates Islamic',
  'HSBC UAE',
  'Citibank UAE',
};

/// Indian banks currently recognized by `CardNormalizerService.normalizeBankName`.
/// A bank name that's neither in this set nor `_uaeBanks` is genuinely
/// unrecognized — `currencyForBank` returns null for it rather than
/// guessing, per spec §4's explicit "must not silently default" requirement.
const Set<String> _indianBanks = {
  'HDFC Bank', 'SBI Card', 'Axis Bank', 'Amazon ICICI Bank', 'ICICI Bank',
  'Kotak Bank', 'IDFC FIRST Bank', 'Yes Bank', 'AU Small Finance Bank',
  'IndusInd Bank', 'Standard Chartered', 'American Express', 'Citibank',
  'HSBC', 'RBL Bank', 'Federal Bank', 'Karur Vysya Bank', 'Bank of Baroda',
  'Canara Bank', 'Punjab National Bank', 'Union Bank of India', 'Indian Bank',
  'Central Bank of India', 'Indian Overseas Bank',
};

/// The currency a bank's statements are denominated in, given its
/// already-normalized name (from `CardNormalizerService.normalizeBankName`).
/// Returns null — not a bare 'INR' default — for a name that's neither a
/// recognized Indian nor UAE bank, so callers can distinguish "resolved to
/// INR" from "couldn't resolve at all" (spec §4, layer 3: silently
/// defaulting to INR here would mask exactly the failure this function
/// exists to catch, e.g. a UAE bank not yet added to the recognized list).
String? currencyForBank(String normalizedBankName) {
  if (_uaeBanks.contains(normalizedBankName)) return 'AED';
  if (_indianBanks.contains(normalizedBankName)) return 'INR';
  return null;
}
