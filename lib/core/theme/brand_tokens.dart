import 'package:flutter/material.dart';

abstract final class BrandColors {
  static const ink = Color(0xFF0B1015);
  static const inkSoft = Color(0xFF172027);
  static const paper = Color(0xFFF4F0E6);
  static const paperDeep = Color(0xFFE9E3D5);
  static const ledger = Color(0xFFDDE7E1);
  static const signal = Color(0xFF3FE0D0);
  static const reward = Color(0xFFFFB547);
  static const error = Color(0xFFFF7163);
  static const white = Color(0xFFFFFDF7);
  static const mutedInk = Color(0xFF465159);
  static const mutedPaper = Color(0xFF9CA9A8);
  static const focusDark = Color(0xFF006D64);

  static const rewardInk = Color(0xFF8A5000);
  static const successInk = Color(0xFF205E48);
  static const ruleOnInk = Color(0x29F4F0E6);
  static const ruleOnPaper = Color(0x290B1015);
}

abstract final class BrandSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const compact = 12.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;
  static const section = 64.0;
}

abstract final class BrandRadius {
  static const label = 2.0;
  static const control = 4.0;
  static const card = 8.0;
  static const overlay = 12.0;
  static const pill = 999.0;
}

abstract final class BrandMotion {
  static const immediate = Duration(milliseconds: 120);
  static const standard = Duration(milliseconds: 180);
  static const navigation = Duration(milliseconds: 240);
  static const compassEntrance = Duration(milliseconds: 1200);
}
