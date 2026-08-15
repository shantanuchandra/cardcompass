import 'package:cardcompass/core/theme/brand_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Flutter primitives match the approved editorial brand values', () {
    expect(BrandColors.ink, const Color(0xFF0B1015));
    expect(BrandColors.paper, const Color(0xFFF4F0E6));
    expect(BrandColors.ledger, const Color(0xFFDDE7E1));
    expect(BrandColors.signal, const Color(0xFF3FE0D0));
    expect(BrandColors.reward, const Color(0xFFFFB547));
    expect(BrandColors.error, const Color(0xFFFF7163));
  });

  test('shape and motion primitives use the approved scales', () {
    expect(BrandRadius.label, 2);
    expect(BrandRadius.control, 4);
    expect(BrandRadius.card, 8);
    expect(BrandRadius.overlay, 12);
    expect(BrandMotion.immediate, const Duration(milliseconds: 120));
    expect(BrandMotion.standard, const Duration(milliseconds: 180));
    expect(BrandMotion.navigation, const Duration(milliseconds: 240));
    expect(BrandMotion.compassEntrance, const Duration(milliseconds: 1200));
  });
}
