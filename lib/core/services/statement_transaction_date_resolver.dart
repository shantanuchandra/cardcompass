enum TransactionDateSource {
  parser,
  pdfContext,
  statementFallback,
  rejectedFuture,
}

class TransactionDateResolution {
  const TransactionDateResolution({required this.date, required this.source});

  final DateTime? date;
  final TransactionDateSource source;
}

TransactionDateResolution resolveStatementTransactionDate({
  required Object? parsedValue,
  required DateTime statementDate,
  required String pdfText,
  required String description,
}) {
  final parsed = _parseDate(parsedValue);
  if (parsed == null) {
    return TransactionDateResolution(
      date: statementDate,
      source: TransactionDateSource.statementFallback,
    );
  }
  if (!parsed.isAfter(statementDate)) {
    return TransactionDateResolution(
      date: parsed,
      source: TransactionDateSource.parser,
    );
  }

  final recovered = _recoverSplitPdfDate(
    pdfText: pdfText,
    description: description,
    statementDate: statementDate,
  );
  if (recovered != null && !recovered.isAfter(statementDate)) {
    return TransactionDateResolution(
      date: recovered,
      source: TransactionDateSource.pdfContext,
    );
  }

  return const TransactionDateResolution(
    date: null,
    source: TransactionDateSource.rejectedFuture,
  );
}

DateTime? _parseDate(Object? value) {
  if (value is DateTime) return value;
  if (value is! String || value.trim().isEmpty) return null;
  final raw = value.trim();
  final iso = DateTime.tryParse(raw);
  if (iso != null) return DateTime(iso.year, iso.month, iso.day);
  final match = RegExp(
    r'^(\d{1,2})[\-/](\d{1,2})[\-/](\d{4})$',
  ).firstMatch(raw);
  if (match == null) return null;
  return _checkedDate(
    int.parse(match.group(3)!),
    int.parse(match.group(2)!),
    int.parse(match.group(1)!),
  );
}

DateTime? _recoverSplitPdfDate({
  required String pdfText,
  required String description,
  required DateTime statementDate,
}) {
  final words = description
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .take(8)
      .map(RegExp.escape)
      .toList();
  if (words.isEmpty) return null;
  final descriptionPattern = words.join(r'\s+');
  final match = RegExp(
    '(?:^|\\n)\\s*(\\d{1,2})\\s+$descriptionPattern[^\\n]*'
    r'\n\s*([A-Za-z]{3,9})\s+(\d{2}|\d{4})\b',
    caseSensitive: false,
  ).firstMatch(pdfText);
  if (match == null) return null;

  final month = _months[match.group(2)!.substring(0, 3).toLowerCase()];
  if (month == null) return null;
  final rawYear = int.parse(match.group(3)!);
  final year = rawYear < 100 ? 2000 + rawYear : rawYear;
  final recovered = _checkedDate(year, month, int.parse(match.group(1)!));
  if (recovered == null) return null;

  // A statement cycle cannot legitimately reach arbitrarily far backwards.
  // This bound prevents an unrelated merchant occurrence from being used as
  // evidence when the same description appears elsewhere in a long PDF.
  if (statementDate.difference(recovered).inDays > 370) return null;
  return recovered;
}

DateTime? _checkedDate(int year, int month, int day) {
  final value = DateTime(year, month, day);
  return value.year == year && value.month == month && value.day == day
      ? value
      : null;
}

const _months = <String, int>{
  'jan': 1,
  'feb': 2,
  'mar': 3,
  'apr': 4,
  'may': 5,
  'jun': 6,
  'jul': 7,
  'aug': 8,
  'sep': 9,
  'oct': 10,
  'nov': 11,
  'dec': 12,
};
