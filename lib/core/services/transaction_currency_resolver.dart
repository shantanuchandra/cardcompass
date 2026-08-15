/// Resolves the currency to store for one transaction, given what Gemini
/// reported ([geminiCurrency], from `txn['currency']` in its per-transaction
/// JSON) and the issuing bank's known market currency ([bankMarketCurrency],
/// from `currencyForBank` — null if the bank is unrecognized).
///
/// A bare "INR" from Gemini is NOT trusted as automatically authoritative:
/// the Gemini prompt instructs Gemini to assume INR only when no currency
/// marker is visible on a line, which means a genuinely-unmarked UAE
/// transaction can legitimately come back as "INR" — indistinguishable
/// from a line where an actual Rs./₹ marker was observed. So: any non-INR
/// value is trusted directly (Gemini has no ambiguous assumption for
/// anything other than INR), but a bare "INR" or missing value is
/// cross-checked against the bank's market and overridden if the bank
/// resolves to something else.
///
/// Trade-off accepted explicitly: a genuinely correct, explicitly-marked
/// INR line item on a UAE statement would be incorrectly overridden to
/// the bank's market currency by this logic, since there's no way to
/// distinguish "Gemini assumed INR" from "Gemini correctly read an INR
/// marker" from the string alone.
String resolveTransactionCurrency({
  required String? geminiCurrency,
  required String? bankMarketCurrency,
}) {
  final trimmed = geminiCurrency?.trim();
  if (trimmed != null && trimmed.isNotEmpty && trimmed.toUpperCase() != 'INR') {
    return trimmed.toUpperCase();
  }

  if (bankMarketCurrency != null) {
    return bankMarketCurrency;
  }

  return 'INR';
}
