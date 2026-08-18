import 'dart:async';
import 'dart:io';

import 'package:cardcompass/core/repositories/statements_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('statement history query stays user-scoped and card-scoped', () async {
    final requests = <HttpRequest>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen((request) {
      requests.add(request);
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write('[]');
      unawaited(request.response.close());
    });
    final client = SupabaseClient(
      'http://${server.address.address}:${server.port}',
      'test-anon-key',
    );
    addTearDown(() async {
      await client.dispose();
      await subscription.cancel();
      await server.close(force: true);
    });

    await StatementsRepository(
      client,
    ).getStatementsForCard(userId: 'user-1', userCardId: 'card-1');

    expect(requests, hasLength(1));
    expect(requests.single.uri.queryParametersAll['user_id'], ['eq.user-1']);
    expect(requests.single.uri.queryParametersAll['user_card_id'], [
      'eq.card-1',
    ]);
    expect(
      requests.single.uri.queryParameters['order'],
      contains('statement_date.desc'),
    );
  });
}
