typedef ReportingLocalizer = DateTime Function(DateTime instant);

/// Converts an instant to the calendar timezone used by on-device reports.
DateTime toReportingLocalTime(DateTime instant) => instant.toLocal();

/// Serializes a reporting boundary as an unambiguous UTC instant for
/// `timestamptz` comparisons.
String reportingBoundaryIso(DateTime boundary) =>
    boundary.toUtc().toIso8601String();
