import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final sources =
      ['cards_screen.dart', 'card_detail_screen.dart', 'add_card_screen.dart']
          .map(
            (name) =>
                File('lib/features/cards/screens/$name').readAsStringSync(),
          )
          .join('\n');
  test('wallet flows use neutral editorial surfaces', () {
    expect(sources, contains('BrandColors.paper'));
    expect(sources, contains('BrandColors.paperDeep'));
    expect(sources, isNot(contains('AppTheme.cardGradient')));
    expect(sources, isNot(contains('GoogleFonts.spaceGrotesk')));
  });
}
