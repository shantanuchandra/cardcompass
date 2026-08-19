import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../data/admin_operator_repository.dart';
import 'customer_models.dart';

typedef CustomerRequestIdFactory = String Function();

abstract interface class CustomerDataSource {
  String newRequestId();
  Future<List<CustomerSummary>> search(String query);
  Future<CustomerDetail> detail(String targetId);
  Future<CustomerReceipt> mutate(CustomerMutation mutation);
}

final class CustomerRepository implements CustomerDataSource {
  CustomerRepository(this._operator, {CustomerRequestIdFactory? requestIds})
    : _requestIds = requestIds ?? const Uuid().v4;
  final AdminOperatorRepository _operator;
  final CustomerRequestIdFactory _requestIds;
  @override
  String newRequestId() {
    final value = _requestIds();
    if (!_uuid.hasMatch(value)) _invalid();
    return value;
  }

  @override
  Future<List<CustomerSummary>> search(String query) async {
    final normalized = query.trim().toLowerCase();
    if ((!_uuid.hasMatch(normalized) && normalized.length < 3) ||
        normalized.length > 320) {
      _invalid();
    }
    try {
      final response = await _invoke('customer-search', newRequestId(), {
        'query': normalized,
        'limit': 25,
      });
      _exact(response, const {'items'});
      final items = response['items'];
      if (items is! List) throw const FormatException();
      return List.unmodifiable(
        items.map((item) => CustomerSummary.fromJson(_map(item))),
      );
    } on FormatException {
      throw const AdminRequestFailed('request_failed');
    } catch (error) {
      if (error is TypeError) throw const AdminRequestFailed('request_failed');
      rethrow;
    }
  }

  @override
  Future<CustomerDetail> detail(String targetId) async {
    if (!_uuid.hasMatch(targetId)) _invalid();
    try {
      final response = await _invoke('customer-detail', newRequestId(), {
        'target_id': targetId,
      });
      _exact(response, const {'customer'});
      final detail = CustomerDetail.fromJson(_map(response['customer']));
      if (detail.summary.id != targetId) throw const FormatException();
      return detail;
    } on FormatException {
      throw const AdminRequestFailed('request_failed');
    } catch (error) {
      if (error is TypeError) throw const AdminRequestFailed('request_failed');
      rethrow;
    }
  }

  @override
  Future<CustomerReceipt> mutate(CustomerMutation mutation) async {
    if (!_uuid.hasMatch(mutation.targetId) ||
        DateTime.tryParse(mutation.observedUpdatedAt) == null) {
      _invalid();
    }
    String action;
    final body = <String, dynamic>{
      'target_id': mutation.targetId,
      'observed_updated_at': mutation.observedUpdatedAt,
    };
    switch (mutation) {
      case RetryCustomerAuthBan():
        action = 'customer-auth-ban-retry';
        body.remove('observed_updated_at');
      case QueueGmailRetry():
        action = 'customer-retry';
      case ConfirmedCustomerMutation(:final reason, :final confirmationUserId):
        final normalizedReason = reason.trim();
        if (confirmationUserId != mutation.targetId ||
            normalizedReason.length < 2 ||
            normalizedReason.length > 1000) {
          _invalid();
        }
        body['confirmation_user_id'] = confirmationUserId;
        body['reason'] = normalizedReason;
        if (mutation case SetCustomerDeletionStatus(:final status)) {
          action = 'customer-deletion-status';
          body['status'] = status.wireValue;
        } else {
          action = 'customer-disable';
        }
    }
    if (!_uuid.hasMatch(mutation.requestId)) _invalid();
    final Map<String, dynamic> response;
    try {
      response = await _invoke(action, mutation.requestId, body);
    } on AdminRequestFailed catch (error) {
      if (error.message == 'auth_ban_pending' &&
          (mutation is DisableCustomer || mutation is RetryCustomerAuthBan)) {
        throw CustomerAuthBanPending(mutation);
      }
      rethrow;
    }
    try {
      _exact(response, const {'result'});
      final result = _map(response['result']);
      return switch (mutation) {
        QueueGmailRetry() => _retryReceipt(result),
        DisableCustomer() => _disableReceipt(result, mutation.targetId),
        SetCustomerDeletionStatus(:final status) => _deletionReceipt(
          result,
          mutation.targetId,
          status,
        ),
        RetryCustomerAuthBan() => _disableReceipt(result, mutation.targetId),
      };
    } on FormatException {
      throw const AdminRequestFailed('request_failed');
    } catch (error) {
      if (error is TypeError) throw const AdminRequestFailed('request_failed');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _invoke(
    String action,
    String requestId,
    Map<String, dynamic> body,
  ) {
    if (!_uuid.hasMatch(requestId)) _invalid();
    final request = {...body, 'request_id': requestId};
    if (utf8.encode(jsonEncode({'action': action, ...request})).length >
        32768) {
      _invalid();
    }
    return _operator.invoke(action, request);
  }
}

final class CustomerAuthBanPending implements Exception {
  const CustomerAuthBanPending(this.operation);
  final CustomerOperation operation;
}

GmailRetryReceipt _retryReceipt(Map<String, dynamic> json) {
  _exact(json, const {'request_id', 'status'});
  final id = json['request_id'];
  final status = CustomerOperationStatus.parseNullable(json['status']);
  if (id is! String ||
      !_uuid.hasMatch(id) ||
      (status != CustomerOperationStatus.queued &&
          status != CustomerOperationStatus.claimed)) {
    throw const FormatException();
  }
  return GmailRetryReceipt(requestId: id, status: status!);
}

DisableCustomerReceipt _disableReceipt(
  Map<String, dynamic> json,
  String target,
) {
  _exact(json, const {'user_id', 'is_active', 'auth_banned'});
  if (json['user_id'] != target ||
      json['is_active'] != false ||
      json['auth_banned'] != true) {
    throw const FormatException();
  }
  return DisableCustomerReceipt(userId: target, authBanned: true);
}

CustomerDeletionReceipt _deletionReceipt(
  Map<String, dynamic> json,
  String target,
  DeletionStatus expected,
) {
  _exact(json, const {'user_id', 'status', 'updated_at'});
  final status = DeletionStatus.parseNullable(json['status']);
  if (json['user_id'] != target ||
      status != expected ||
      json['updated_at'] is! String ||
      DateTime.tryParse(json['updated_at'] as String) == null) {
    throw const FormatException();
  }
  return CustomerDeletionReceipt(
    userId: target,
    status: status!,
    updatedAt: DateTime.parse(json['updated_at'] as String).toUtc(),
  );
}

Map<String, dynamic> _map(Object? value) {
  if (value is! Map) throw const FormatException();
  return Map<String, dynamic>.from(value);
}

void _exact(Map<String, dynamic> json, Set<String> keys) {
  if (json.length != keys.length || !json.keys.toSet().containsAll(keys)) {
    throw const FormatException();
  }
}

Never _invalid() => throw const AdminRequestFailed('invalid_request');
final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);
