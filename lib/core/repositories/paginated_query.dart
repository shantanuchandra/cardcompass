typedef PageLoader<T> = Future<List<T>> Function(int offset, int limit);

Future<List<T>> collectPaginated<T>({
  required PageLoader<T> loadPage,
  int pageSize = 500,
}) async {
  final rows = <T>[];
  while (true) {
    final page = await loadPage(rows.length, pageSize);
    rows.addAll(page);
    if (page.length < pageSize) return rows;
  }
}
