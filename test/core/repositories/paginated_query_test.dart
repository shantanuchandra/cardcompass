import 'package:cardcompass/core/repositories/paginated_query.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('collects every page after a full server-sized first page', () async {
    final requests = <(int, int)>[];

    final rows = await collectPaginated<int>(
      pageSize: 2,
      loadPage: (offset, limit) async {
        requests.add((offset, limit));
        return switch (offset) {
          0 => [1, 2],
          2 => [3],
          _ => const [],
        };
      },
    );

    expect(rows, [1, 2, 3]);
    expect(requests, [(0, 2), (2, 2)]);
  });

  test('stops after one empty page', () async {
    var calls = 0;

    final rows = await collectPaginated<int>(
      pageSize: 500,
      loadPage: (offset, limit) async {
        calls++;
        return const [];
      },
    );

    expect(rows, isEmpty);
    expect(calls, 1);
  });
}
