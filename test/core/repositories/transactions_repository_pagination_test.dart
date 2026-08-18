import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cardcompass/core/repositories/transactions_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test(
    'getAllTransactions loads more than 500 rows in deterministic pages',
    () async {
      final rows = List.generate(501, (index) {
        final date = DateTime(2026, 8, 17).subtract(Duration(minutes: index));
        return <String, dynamic>{
          'id': 'txn-${index.toString().padLeft(3, '0')}',
          'user_id': 'user-1',
          'user_card_id': 'card-1',
          'amount': index + 1,
          'currency': 'INR',
          'description': 'Purchase $index',
          'transaction_type': 'debit',
          'transaction_date': date.toIso8601String(),
          'created_at': date.toIso8601String(),
        };
      });
      final requests = <HttpRequest>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = server.listen((request) {
        requests.add(request);
        final start = int.parse(request.uri.queryParameters['offset']!);
        final limit = int.parse(request.uri.queryParameters['limit']!);
        final endExclusive = (start + limit).clamp(0, rows.length);
        final page = start >= rows.length
            ? const <Map<String, dynamic>>[]
            : rows.sublist(start, endExclusive);
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(page));
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

      final transactions = await TransactionsRepository(
        client,
      ).getAllTransactions(userId: 'user-1');

      expect(transactions, hasLength(501));
      expect(transactions.first.id, 'txn-000');
      expect(transactions.last.id, 'txn-500');
      expect(
        requests.map(
          (request) => (
            request.uri.queryParameters['offset'],
            request.uri.queryParameters['limit'],
          ),
        ),
        [('0', '500'), ('500', '500')],
      );
      expect(
        requests.map((request) => request.uri.queryParameters['order']).toSet(),
        {'transaction_date.desc.nullslast,id.asc.nullslast'},
      );
    },
  );

  test(
    'repository reporting queries serialize local bounds as UTC instants',
    () async {
      final requests = <HttpRequest>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = server.listen((incoming) {
        requests.add(incoming);
        incoming.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write('[]');
        unawaited(incoming.response.close());
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
      final from = DateTime(2026, 8, 1);
      final to = DateTime(2026, 8, 31, 12, 30);
      final repository = TransactionsRepository(client);

      await repository.getTransactions(userId: 'user-1', from: from, to: to);
      await repository.getAllTransactionsInRange(
        userId: 'user-1',
        from: from,
        to: to,
      );

      expect(requests, hasLength(2));
      for (final request in requests) {
        expect(request.uri.queryParametersAll['transaction_date'], [
          'gte.${from.toUtc().toIso8601String()}',
          'lte.${to.toUtc().toIso8601String()}',
        ]);
      }
    },
  );

  test('card archive query stays user-scoped and card-scoped', () async {
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

    await TransactionsRepository(
      client,
    ).getAllTransactionsForCard(userId: 'user-1', userCardId: 'card-1');

    expect(requests, hasLength(1));
    expect(requests.single.uri.queryParametersAll['user_id'], ['eq.user-1']);
    expect(requests.single.uri.queryParametersAll['user_card_id'], [
      'eq.card-1',
    ]);
  });
}
