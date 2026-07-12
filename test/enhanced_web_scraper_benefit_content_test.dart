import 'package:cardcompass/core/services/enhanced_web_scraper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps concrete card evidence and removes banking promotions', () {
    const html = '''
      <html><body>
        <nav>Personal Loan Savings Account Customer Support</nav>
        <main>
          <h1>Airtel Axis Bank Credit Card</h1>
          <section><p>Get 25% cashback on Airtel &amp; utility payments capped at ₹250 per month.</p></section>
          <section><p>Apply for Personal Loan Online. Earn 6.5% on your Savings Account.</p></section>
        </main>
        <footer>Contact customer support</footer>
      </body></html>
    ''';

    final content = EnhancedWebScraper.extractBenefitContent(html);

    expect(content, contains('25% cashback'));
    expect(content, contains('Airtel & utility'));
    expect(content, isNot(contains('&amp;')));
    expect(content.toLowerCase(), isNot(contains('personal loan')));
    expect(content.toLowerCase(), isNot(contains('savings account')));
    expect(content.toLowerCase(), isNot(contains('customer support')));
  });

  test('accepts an official matching card product source', () {
    final result = EnhancedWebScraper.validateCardSource(
      url:
          'https://www.axisbank.com/retail/cards/credit-card/airtel-axis-bank-credit-card',
      content:
          'Airtel Axis Bank Credit Card. Get 25% cashback capped at ₹250 per month.',
      bankName: 'Axis Bank',
      cardName: 'Airtel',
    );

    expect(result.isValid, isTrue);
    expect(result.reasons, isEmpty);
  });

  test('rejects unofficial, generic, and wrong-card sources', () {
    final unofficial = EnhancedWebScraper.validateCardSource(
      url: 'https://example.com/airtel-axis-card',
      content: 'Airtel Axis Bank Credit Card cashback details.',
      bankName: 'Axis Bank',
      cardName: 'Airtel',
    );
    final generic = EnhancedWebScraper.validateCardSource(
      url: 'https://www.axisbank.com/retail/cards/credit-card',
      content: 'Explore all Axis Bank credit cards and personal loans.',
      bankName: 'Axis Bank',
      cardName: 'Airtel',
    );
    final wrongCard = EnhancedWebScraper.validateCardSource(
      url:
          'https://www.axisbank.com/retail/cards/credit-card/axis-bank-ace-credit-card',
      content: 'Axis Bank ACE Credit Card. Get cashback on bill payments.',
      bankName: 'Axis Bank',
      cardName: 'Airtel',
    );

    expect(unofficial.reasonCodes, contains('unofficial_domain'));
    expect(generic.reasonCodes, contains('card_identity_not_found'));
    expect(wrongCard.reasonCodes, contains('card_identity_not_found'));
  });
}
