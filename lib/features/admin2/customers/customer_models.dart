enum CustomerOperationStatus {
  queued('queued'),
  claimed('claimed'),
  completed('completed'),
  failed('failed');

  const CustomerOperationStatus(this.wireValue);
  final String wireValue;
  static CustomerOperationStatus? parseNullable(Object? value) =>
      switch (value) {
        null => null,
        'queued' => queued,
        'claimed' => claimed,
        'completed' => completed,
        'failed' => failed,
        _ => throw const FormatException('Invalid operation status'),
      };
}

enum CustomerFailure {
  reauthenticationRequired(
    'reauthentication_required',
    'Reauthentication required',
  ),
  gmailUnavailable('gmail_unavailable', 'Gmail unavailable'),
  processingFailed('processing_failed', 'Processing failed');

  const CustomerFailure(this.wireValue, this.label);
  final String wireValue;
  final String label;
  static CustomerFailure? parseNullable(Object? value) => switch (value) {
    null => null,
    'reauthentication_required' => reauthenticationRequired,
    'gmail_unavailable' => gmailUnavailable,
    'processing_failed' => processingFailed,
    _ => throw const FormatException('Invalid failure category'),
  };
}

enum DeletionStatus {
  requested('requested'),
  verified('verified'),
  scheduled('scheduled'),
  completed('completed'),
  cancelled('cancelled');

  const DeletionStatus(this.wireValue);
  final String wireValue;
  String get label => switch (this) {
    requested => 'Requested',
    verified => 'Verified',
    scheduled => 'Scheduled',
    completed => 'Completed',
    cancelled => 'Cancelled',
  };
  static DeletionStatus? parseNullable(Object? value) => switch (value) {
    null => null,
    'requested' => requested,
    'verified' => verified,
    'scheduled' => scheduled,
    'completed' => completed,
    'cancelled' => cancelled,
    _ => throw const FormatException('Invalid deletion status'),
  };
}

enum AuthBanStatus {
  pending,
  processing,
  completed,
  failed;

  static AuthBanStatus? parseNullable(Object? value) => switch (value) {
    null => null,
    'pending' => pending,
    'processing' => processing,
    'completed' => completed,
    'failed' => failed,
    _ => throw const FormatException('Invalid Auth ban status'),
  };
}

final class CustomerSummary {
  const CustomerSummary({
    required this.id,
    required this.email,
    required this.createdAt,
    required this.lastActivityAt,
    required this.isActive,
  });
  final String id;
  final String email;
  final DateTime createdAt;
  final DateTime lastActivityAt;
  final bool isActive;
  factory CustomerSummary.fromJson(Map<String, dynamic> json) {
    _exact(json, const {
      'id',
      'email',
      'created_at',
      'last_activity_at',
      'is_active',
    });
    final id = _uuid(json['id']);
    final email = json['email'];
    if (email is! String ||
        email.isEmpty ||
        email.length > 320 ||
        email != email.trim().toLowerCase() ||
        json['is_active'] is! bool) {
      throw const FormatException('Invalid customer');
    }
    return CustomerSummary(
      id: id,
      email: email,
      createdAt: _date(json['created_at']),
      lastActivityAt: _date(json['last_activity_at']),
      isActive: json['is_active'] as bool,
    );
  }
}

final class CustomerDetail {
  const CustomerDetail({
    required this.summary,
    required this.gmailConnected,
    required this.gmailStatus,
    required this.gmailFailure,
    required this.gmailUpdatedAt,
    required this.ownedCardCount,
    required this.statementCount,
    required this.processedStatementCount,
    required this.emailCount,
    required this.processedEmailCount,
    required this.latestStatementAt,
    required this.latestEmailAt,
    required this.deletionStatus,
    required this.deletionUpdatedAt,
    this.authBanStatus,
    this.authBanUpdatedAt,
  });
  final CustomerSummary summary;
  final bool gmailConnected;
  final CustomerOperationStatus? gmailStatus;
  final CustomerFailure? gmailFailure;
  final DateTime? gmailUpdatedAt;
  final int ownedCardCount,
      statementCount,
      processedStatementCount,
      emailCount,
      processedEmailCount;
  final DateTime? latestStatementAt, latestEmailAt;
  final DeletionStatus? deletionStatus;
  final DateTime? deletionUpdatedAt;
  final AuthBanStatus? authBanStatus;
  final DateTime? authBanUpdatedAt;
  factory CustomerDetail.fromJson(Map<String, dynamic> json) {
    _exact(json, const {
      'id',
      'email',
      'created_at',
      'last_activity_at',
      'is_active',
      'gmail_connected',
      'gmail_last_status',
      'gmail_last_failure_category',
      'gmail_last_updated_at',
      'owned_card_count',
      'statement_count',
      'processed_statement_count',
      'email_count',
      'processed_email_count',
      'latest_statement_at',
      'latest_email_at',
      'deletion_status',
      'deletion_updated_at',
      'auth_ban_status',
      'auth_ban_updated_at',
    });
    if (json['gmail_connected'] is! bool) {
      throw const FormatException('Invalid customer detail');
    }
    final summaryJson = <String, dynamic>{
      for (final key in [
        'id',
        'email',
        'created_at',
        'last_activity_at',
        'is_active',
      ])
        key: json[key],
    };
    final counts = [
      'owned_card_count',
      'statement_count',
      'processed_statement_count',
      'email_count',
      'processed_email_count',
    ].map((key) => _count(json[key])).toList();
    if (counts[2] > counts[1] || counts[4] > counts[3]) {
      throw const FormatException('Invalid customer counts');
    }
    final status = CustomerOperationStatus.parseNullable(
      json['gmail_last_status'],
    );
    final failure = CustomerFailure.parseNullable(
      json['gmail_last_failure_category'],
    );
    if (failure != null && status != CustomerOperationStatus.failed) {
      throw const FormatException('Contradictory failure');
    }
    return CustomerDetail(
      summary: CustomerSummary.fromJson(summaryJson),
      gmailConnected: json['gmail_connected'] as bool,
      gmailStatus: status,
      gmailFailure: failure,
      gmailUpdatedAt: _nullableDate(json['gmail_last_updated_at']),
      ownedCardCount: counts[0],
      statementCount: counts[1],
      processedStatementCount: counts[2],
      emailCount: counts[3],
      processedEmailCount: counts[4],
      latestStatementAt: _nullableDate(json['latest_statement_at']),
      latestEmailAt: _nullableDate(json['latest_email_at']),
      deletionStatus: DeletionStatus.parseNullable(json['deletion_status']),
      deletionUpdatedAt: _nullableDate(json['deletion_updated_at']),
      authBanStatus: AuthBanStatus.parseNullable(json['auth_ban_status']),
      authBanUpdatedAt: _nullableDate(json['auth_ban_updated_at']),
    );
  }
  bool get retryEligible =>
      summary.isActive &&
      gmailConnected &&
      gmailStatus == CustomerOperationStatus.failed &&
      gmailFailure != null;
}

final class RetryCustomerAuthBan extends CustomerOperation {
  const RetryCustomerAuthBan({
    required super.requestId,
    required super.targetId,
    required super.observedUpdatedAt,
  });
}

sealed class CustomerOperation {
  const CustomerOperation({
    required this.requestId,
    required this.targetId,
    required this.observedUpdatedAt,
  });
  final String requestId;
  final String targetId;
  final String observedUpdatedAt;
}

typedef CustomerMutation = CustomerOperation;

final class QueueGmailRetry extends CustomerOperation {
  const QueueGmailRetry({
    required super.requestId,
    required super.targetId,
    required super.observedUpdatedAt,
  });
}

sealed class ConfirmedCustomerMutation extends CustomerOperation {
  const ConfirmedCustomerMutation({
    required super.requestId,
    required super.targetId,
    required super.observedUpdatedAt,
    required this.reason,
    required this.confirmationUserId,
  });
  final String reason;
  final String confirmationUserId;
}

final class DisableCustomer extends ConfirmedCustomerMutation {
  const DisableCustomer({
    required super.requestId,
    required super.targetId,
    required super.observedUpdatedAt,
    required super.reason,
    required super.confirmationUserId,
  });
}

final class SetCustomerDeletionStatus extends ConfirmedCustomerMutation {
  const SetCustomerDeletionStatus({
    required super.requestId,
    required super.targetId,
    required super.observedUpdatedAt,
    required super.reason,
    required super.confirmationUserId,
    required this.status,
  });
  final DeletionStatus status;
}

sealed class CustomerReceipt {
  const CustomerReceipt();
}

final class GmailRetryReceipt extends CustomerReceipt {
  const GmailRetryReceipt({required this.requestId, required this.status});
  final String requestId;
  final CustomerOperationStatus status;
}

final class DisableCustomerReceipt extends CustomerReceipt {
  const DisableCustomerReceipt({
    required this.userId,
    required this.authBanned,
  });
  final String userId;
  final bool authBanned;
}

final class CustomerDeletionReceipt extends CustomerReceipt {
  const CustomerDeletionReceipt({
    required this.userId,
    required this.status,
    required this.updatedAt,
  });
  final String userId;
  final DeletionStatus status;
  final DateTime updatedAt;
}

final _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);
String _uuid(Object? value) {
  if (value is! String || !_uuidPattern.hasMatch(value)) {
    throw const FormatException('Invalid UUID');
  }
  return value;
}

DateTime _date(Object? value) {
  if (value is! String) throw const FormatException('Invalid timestamp');
  final parsed = DateTime.tryParse(value);
  if (parsed == null) throw const FormatException('Invalid timestamp');
  return parsed.toUtc();
}

DateTime? _nullableDate(Object? value) => value == null ? null : _date(value);
int _count(Object? value) {
  if (value is! int || value < 0) throw const FormatException('Invalid count');
  return value;
}

void _exact(Map<String, dynamic> json, Set<String> keys) {
  if (json.length != keys.length || !json.keys.toSet().containsAll(keys)) {
    throw const FormatException('Invalid response');
  }
}
