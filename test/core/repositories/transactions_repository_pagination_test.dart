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
}
