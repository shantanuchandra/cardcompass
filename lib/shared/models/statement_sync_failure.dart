/// Records that a single statement's data could not be stored during a sync
/// (card association, PDF parsing, or DB write all surface here) so the
/// failure can be reported to the user instead of silently dropped.
class StatementSyncFailure {
  StatementSyncFailure({
    required this.bankName,
    required this.statementDate,
    required this.reason,
  });

  final String bankName;
  final DateTime statementDate;
  final String reason;
}

const _monthAbbreviations = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _formatMonthYear(DateTime date) =>
    '${_monthAbbreviations[date.month - 1]} ${date.year}';

/// Builds a user-facing summary of statements that failed to sync, or `null`
/// if [failures] is empty. Lists up to the first 3 by bank and month/year,
/// then counts any remainder.
String? buildSyncFailureMessage(List<StatementSyncFailure> failures) {
  if (failures.isEmpty) return null;

  final shown = failures.take(3).map((f) =>
      '${f.bankName} (${_formatMonthYear(f.statementDate)})');
  final remaining = failures.length - 3;

  final list = remaining > 0
      ? '${shown.join(', ')}, and $remaining more'
      : shown.join(', ');

  final noun = failures.length == 1 ? 'statement' : 'statements';
  return '${failures.length} $noun could not be saved: $list. Try syncing again.';
}
