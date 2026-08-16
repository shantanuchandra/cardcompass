import 'package:cardcompass/core/repositories/cards_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bank catalog search matches canonical names and aliases', () {
    const entry = {
      'card_name': 'Privilege',
      'card_catalog_aliases': [
        {'alias': 'Amex Privilege', 'normalized_alias': 'privilege'},
      ],
    };

    expect(catalogEntryMatchesQuery(entry, 'privilege'), isTrue);
    expect(catalogEntryMatchesQuery(entry, 'Amex Priv'), isTrue);
    expect(catalogEntryMatchesQuery(entry, 'Magnus'), isFalse);
    expect(catalogEntryMatchesQuery(entry, ''), isTrue);
  });
}
