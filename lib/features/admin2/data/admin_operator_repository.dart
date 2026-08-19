import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/admin_access.dart';
import 'admin_operator_api.dart';

class AdminAuthenticationRequired implements Exception {}

class AdminAccessDenied implements Exception {}

class AdminStateConflict implements Exception {}

class AdminRequestFailed implements Exception {
  const AdminRequestFailed(this.message);

  final String message;

  @override
  String toString() => message;
}

class AdminOperatorRepository {
  const AdminOperatorRepository(this._api);

  final AdminOperatorApi _api;

  Future<Map<String, dynamic>> invoke(
    String action, [
    Map<String, dynamic> body = const {},
  ]) async {
    final AdminOperatorResponse response;
    try {
      response = await _api.invoke({...body, 'action': action});
    } catch (error) {
      _throwInvocationError(error);
    }

    if (response.status == 401) throw AdminAuthenticationRequired();
    if (response.status == 403) throw AdminAccessDenied();
    final data = response.data;
    if (response.status == 409 &&
        data is Map &&
        data['error'] == 'state_conflict') {
      throw AdminStateConflict();
    }
    if (response.status != 200 || data is! Map) {
      final code = data is Map && data['error'] is String
          ? data['error'] as String
          : 'request_failed';
      const safeCodes = {
        'invalid_request',
        'not_found',
        'operation_in_progress',
        'reason_required',
        'request_failed',
      };
      throw AdminRequestFailed(
        safeCodes.contains(code) ? code : 'request_failed',
      );
    }
    try {
      return Map<String, dynamic>.from(data);
    } on TypeError {
      throw const AdminRequestFailed('request_failed');
    }
  }

  Future<AdminAccess> access() async {
    try {
      return AdminAccess.fromJson(await invoke('access'));
    } on FormatException {
      throw const AdminRequestFailed('request_failed');
    }
  }

  Never _throwInvocationError(Object error) {
    if (error is AdminAuthenticationRequired) throw error;
    if (error is AdminAccessDenied) throw error;
    if (error is AdminStateConflict) throw error;
    if (error is AdminRequestFailed) throw error;
    if (error is FunctionException) {
      if (error.status == 401) throw AdminAuthenticationRequired();
      if (error.status == 403) throw AdminAccessDenied();
      if (error.status == 409) throw AdminStateConflict();
      throw const AdminRequestFailed('request_failed');
    }
    if (error is http.ClientException) {
      throw const AdminRequestFailed('request_failed');
    }
    if (error is FormatException) {
      throw const AdminRequestFailed('request_failed');
    }
    throw const AdminRequestFailed('request_failed');
  }
}
