import 'package:supabase_flutter/supabase_flutter.dart';

class AdminOperatorResponse {
  const AdminOperatorResponse(this.status, this.data);

  final int status;
  final Object? data;
}

abstract interface class AdminOperatorApi {
  Future<AdminOperatorResponse> invoke(Map<String, dynamic> body);
}

class SupabaseAdminOperatorApi implements AdminOperatorApi {
  SupabaseAdminOperatorApi(this._client);

  final SupabaseClient _client;

  @override
  Future<AdminOperatorResponse> invoke(Map<String, dynamic> body) async {
    final response = await _client.functions.invoke(
      'admin-operator',
      body: body,
    );
    return AdminOperatorResponse(response.status, response.data);
  }
}
