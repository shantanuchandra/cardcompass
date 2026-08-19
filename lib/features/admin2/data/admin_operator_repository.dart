import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/admin_access.dart';
import 'admin_operator_api.dart';

class AdminAuthenticationRequired implements Exception {}

class AdminAccessDenied implements Exception {}

class AdminRequestFailed implements Exception {
  const AdminRequestFailed(this.message);

  final String message;

  @override
  String toString() => message;
}

class AdminOperatorRepository {
  const AdminOperatorRepository(this._api);

  final AdminOperatorApi _api;

  Future<AdminAccess> access() async {
    final AdminOperatorResponse response;
    try {
      response = await _api.invoke(const {'action': 'access'});
    } catch (error) {
      _throwInvocationError(error);
    }

    if (response.status == 401) throw AdminAuthenticationRequired();
    if (response.status == 403) throw AdminAccessDenied();
    if (response.status != 200 || response.data is! Map) {
      throw const AdminRequestFailed('request_failed');
    }

    try {
      return AdminAccess.fromJson(
        Map<String, dynamic>.from(response.data! as Map),
      );
    } on FormatException {
      throw const AdminRequestFailed('request_failed');
    }
  }

  Never _throwInvocationError(Object error) {
    if (error is FunctionException) {
      if (error.status == 401) throw AdminAuthenticationRequired();
      if (error.status == 403) throw AdminAccessDenied();
      throw const AdminRequestFailed('request_failed');
    }
    if (error is http.ClientException) {
      throw const AdminRequestFailed('request_failed');
    }
    throw error;
  }
}
