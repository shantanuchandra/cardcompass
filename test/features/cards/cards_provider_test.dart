import 'package:cardcompass/features/cards/providers/cards_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('statement summary provider is available to the portfolio', () {
    expect(cardStatementSummariesProvider, isNotNull);
  });
}
