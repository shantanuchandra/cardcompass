import 'package:cardcompass/features/dashboard/providers/gmail_sync_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every Gmail sync range maps to its advertised lookback', () {
    expect(gmailSyncLookbackDays, const {
      '7d': 7,
      '30d': 30,
      '60d': 60,
      '90d': 90,
      '8mo': 240,
      '1yr': 365,
    });
  });
}
