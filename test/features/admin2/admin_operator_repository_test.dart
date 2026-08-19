import 'package:cardcompass/features/admin2/data/admin_operator_api.dart';
import 'package:cardcompass/features/admin2/data/admin_operator_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

final class FakeAdminOperatorApi implements AdminOperatorApi {
  FakeAdminOperatorApi(this.response, {this.error});

  final AdminOperatorResponse response;
  final Object? error;
  final bodies = <Map<String, dynamic>>[];

  @override
  Future<AdminOperatorResponse> invoke(Map<String, dynamic> body) async {
    bodies.add(body);
    if (error != null) throw error!;
    return response;
  }
}

void main() {
  test('access maps the database-backed response', () async {
    final api = FakeAdminOperatorApi(
      const AdminOperatorResponse(200, {'is_admin': true}),
    );

    final access = await AdminOperatorRepository(api).access();

    expect(access.isAdmin, isTrue);
    expect(api.bodies.single, {'action': 'access'});
  });

  test('access rejects a missing is_admin value', () async {
    final api = FakeAdminOperatorApi(const AdminOperatorResponse(200, {}));

    expect(
      AdminOperatorRepository(api).access(),
      throwsA(
        isA<AdminRequestFailed>().having(
          (error) => error.message,
          'message',
          'request_failed',
        ),
      ),
    );
  });

  test('access rejects a non-boolean is_admin value', () async {
    final api = FakeAdminOperatorApi(
      const AdminOperatorResponse(200, {'is_admin': 'true'}),
    );

    expect(
      AdminOperatorRepository(api).access(),
      throwsA(isA<AdminRequestFailed>()),
    );
  });

  test('401 maps to AdminAuthenticationRequired', () async {
    final api = FakeAdminOperatorApi(const AdminOperatorResponse(401, {}));

    expect(
      AdminOperatorRepository(api).access(),
      throwsA(isA<AdminAuthenticationRequired>()),
    );
  });

  test('403 maps to AdminAccessDenied', () async {
    final api = FakeAdminOperatorApi(
      const AdminOperatorResponse(403, {
        'error': 'administrator_access_required',
      }),
    );

    expect(
      AdminOperatorRepository(api).access(),
      throwsA(isA<AdminAccessDenied>()),
    );
  });

  test('stable server error maps to AdminRequestFailed', () async {
    final api = FakeAdminOperatorApi(
      const AdminOperatorResponse(500, {'error': 'request_failed'}),
    );

    expect(
      AdminOperatorRepository(api).access(),
      throwsA(
        isA<AdminRequestFailed>().having(
          (error) => error.message,
          'message',
          'request_failed',
        ),
      ),
    );
  });

  test('FunctionException authentication error maps to requirement', () async {
    final api = FakeAdminOperatorApi(
      const AdminOperatorResponse(500, {}),
      error: const FunctionException(
        status: 401,
        details: {'error': 'authentication_required'},
      ),
    );

    expect(
      AdminOperatorRepository(api).access(),
      throwsA(isA<AdminAuthenticationRequired>()),
    );
  });

  test('FunctionException access error maps to denial', () async {
    final api = FakeAdminOperatorApi(
      const AdminOperatorResponse(500, {}),
      error: const FunctionException(
        status: 403,
        details: {'error': 'administrator_access_required'},
      ),
    );

    expect(
      AdminOperatorRepository(api).access(),
      throwsA(isA<AdminAccessDenied>()),
    );
  });

  test('FunctionException server error maps to request failure', () async {
    final api = FakeAdminOperatorApi(
      const AdminOperatorResponse(500, {}),
      error: const FunctionException(
        status: 500,
        details: {'error': 'request_failed'},
      ),
    );

    expect(
      AdminOperatorRepository(api).access(),
      throwsA(
        isA<AdminRequestFailed>().having(
          (error) => error.message,
          'message',
          'request_failed',
        ),
      ),
    );
  });

  test('network failure maps to request failure', () async {
    final api = FakeAdminOperatorApi(
      const AdminOperatorResponse(500, {}),
      error: http.ClientException(
        'Failed to fetch',
        Uri.parse('https://example.supabase.co/functions/v1/admin-operator'),
      ),
    );

    expect(
      AdminOperatorRepository(api).access(),
      throwsA(
        isA<AdminRequestFailed>().having(
          (error) => error.message,
          'message',
          'request_failed',
        ),
      ),
    );
  });

  test('malformed invocation response maps to request failure', () async {
    final api = FakeAdminOperatorApi(
      const AdminOperatorResponse(500, {}),
      error: const FormatException('Unexpected end of JSON input'),
    );

    expect(
      AdminOperatorRepository(api).access(),
      throwsA(
        isA<AdminRequestFailed>().having(
          (error) => error.message,
          'message',
          'request_failed',
        ),
      ),
    );
  });
}
