class CatalogEntryFields {
  const CatalogEntryFields({
    required this.bankName,
    required this.cardName,
    required this.sourceUrl,
  });

  final String bankName;
  final String cardName;
  final String sourceUrl;
}

class CatalogEntryStagingPolicy {
  static bool isPendingCatalogEntry(Map<String, dynamic> row) {
    final extracted = row['extracted_data'];
    final requestType =
        extracted is Map ? extracted['request_type']?.toString() : null;
    return row['status'] == 'pending' &&
        row['card_id'] == null &&
        requestType == 'catalog_entry';
  }

  static CatalogEntryFields parseFields(Map<String, dynamic> row) {
    final extracted = row['extracted_data'] is Map
        ? Map<String, dynamic>.from(row['extracted_data'] as Map)
        : <String, dynamic>{};
    return CatalogEntryFields(
      bankName: extracted['bank_name']?.toString().trim() ?? '',
      cardName: extracted['card_name']?.toString().trim() ?? '',
      sourceUrl: row['source_url']?.toString().trim() ?? '',
    );
  }

  static bool canApprove(Map<String, dynamic> row) {
    if (!isPendingCatalogEntry(row)) {
      return false;
    }
    final fields = parseFields(row);
    return fields.bankName.length >= 2 &&
        fields.cardName.length >= 2 &&
        fields.sourceUrl.isNotEmpty;
  }
}
