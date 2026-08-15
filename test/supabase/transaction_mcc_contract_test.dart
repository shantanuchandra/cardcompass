import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('MCC migration contains fields and bounded source constraints', () {
    final sql = File(
      'supabase/migrations/20260817000000_transaction_mcc_enrichment.sql',
    ).readAsStringSync();

    for (final field in const [
      'mcc_code',
      'mcc_description',
      'mcc_source',
      'mcc_confidence',
      'mcc_verified_at',
    ]) {
      expect(sql, contains(field));
    }
    for (final source in const [
      'bank_statement',
      'verified_provider',
      'merchant_registry',
      'inferred',
      'unknown',
    ]) {
      expect(sql, contains(source));
    }
    expect(sql, contains('transactions_mcc_source_check'));
    expect(sql, contains('transactions_mcc_confidence_check'));
  });
}
