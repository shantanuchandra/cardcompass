import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:cardcompass/core/services/gemini_transaction_parser.dart';

void main() {
  late Directory hiveDir;

  setUp(() async {
    hiveDir = await Directory.systemTemp.createTemp('gemini_text_pruning_test_');
    Hive.init(hiveDir.path);
  });

  tearDown(() async {
    // _pruneAndCleanText fires PruningAuditService().logPruning() without awaiting it;
    // give that detached future a chance to finish before we delete its target directory.
    await Future.delayed(const Duration(milliseconds: 50));
    await Hive.deleteFromDisk();
    if (await hiveDir.exists()) {
      await hiveDir.delete(recursive: true);
    }
  });

  group('GeminiTransactionParser text pruning', () {
    test('retains transaction table when a boilerplate marker appears before it (HDFC Tata Neu Infinity layout)', () {
      // Mirrors the real-world HDFC "Tata Neu Infinity" layout: a rewards/NeuCoins
      // summary section containing "Important Information" boilerplate appears
      // BEFORE the itemized transaction table, not after it.
      final rewardsSummary = List.generate(
        60,
        (i) => 'NeuCoins with Bank: Base tier reward line $i for account summary purposes only.',
      ).join('\n');

      final text = '''
HDFC BANK TATA NEU INFINITY CREDIT CARD
Statement Period: 15-Jun-2026 to 14-Jul-2026
Total Amount Due: Rs. 42,500.00

NeuCoins Summary
$rewardsSummary
NeuCoins Earned(Base+Bonus): 1250
Important Information
Please review your NeuCoins balance above.

Domestic Transactions:
16 Jun 26  SWIGGY BANGALORE         650.00
18 Jun 26  AMAZON.IN               3499.00
22 Jun 26  BIGBASKET ONLINE        1249.00
25 Jun 26  PAYMENT RECEIVED BY NET -5000.00 Cr

MOST IMPORTANT TERMS & CONDITIONS (MITC)
1. Late Payment Charges apply as per standard schedule.
2. Interest is calculated from the date of transaction.
''';

      final result = GeminiTransactionParser.pruneAndCleanTextForTesting(text, 'HDFC Bank');

      expect(result, contains('SWIGGY BANGALORE'),
          reason: 'Transaction table must survive pruning even when a boilerplate marker precedes it');
      expect(result, contains('AMAZON.IN'));
      expect(result, contains('PAYMENT RECEIVED BY NET'));
    });

    test('still prunes trailing boilerplate when marker legitimately comes after all transactions', () {
      final text = '''
SBI CARD BPCL MONTHLY STATEMENT
Statement Date: 12-Jul-2026

Transactions:
05 Jul 26  SWIGGY BANGALORE         450.00 D
07 Jul 26  AMAZON.IN               1200.00 D
${'padding line to exceed safe cut threshold ' * 100}

MOST IMPORTANT TERMS & CONDITIONS (MITC)
1. Late Payment Charges:
${'Nil for amount due up to Rs 100. ' * 50}
''';

      final result = GeminiTransactionParser.pruneAndCleanTextForTesting(text, 'SBI Card');

      expect(result, isNot(contains('Late Payment Charges')),
          reason: 'Trailing boilerplate after all transactions should still be pruned');
      expect(result, contains('SWIGGY BANGALORE'));
    });
  });
}
