import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Brand — Trust Navy + Gold (modern fintech)
  static const Color primaryColor = Color(0xFF0F172A);
  static const Color secondaryColor = Color(0xFF1E3A8A);
  static const Color accentColor = Color(0xFFA16207);
  static const Color errorColor = Color(0xFFDC2626);
  static const Color successColor = Color(0xFF16A34A);
  static const Color warningColor = Color(0xFFD97706);

  // Card Network Colors
  static const Color visaColor = Color(0xFF1A1F71);
  static const Color mastercardColor = Color(0xFFEB001B);
  static const Color rupayColor = Color(0xFF0066CC);
  static const Color amexColor = Color(0xFF006FCF);

  // Bank Brand Colors
  static const Color hdfcColor = Color(0xFF004C8F);
  static const Color sbiColor = Color(0xFF22409A);
  static const Color iciciColor = Color(0xFFB02A37);
  static const Color axisColor = Color(0xFF800020);
  static const Color kotakColor = Color(0xFFED1C24);

  static TextTheme _buildTextTheme(TextTheme base) {
    return GoogleFonts.interTextTheme(base);
  }

  static ThemeData get lightTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primaryColor,
      brightness: Brightness.light,
      secondary: secondaryColor,
      tertiary: accentColor,
      error: errorColor,
    );
    final base = ThemeData(useMaterial3: true, colorScheme: colorScheme, brightness: Brightness.light);
    return base.copyWith(
      textTheme: _buildTextTheme(base.textTheme),
      scaffoldBackgroundColor: const Color(0xFFF8FAFC),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        centerTitle: true,
        backgroundColor: Colors.transparent,
        foregroundColor: Color(0xFF0F172A),
      ),
      cardTheme: CardThemeData(
        elevation: 1,
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppBorderRadius.xl),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          minimumSize: const Size.fromHeight(48),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppBorderRadius.md),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppBorderRadius.md),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF1F5F9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppBorderRadius.md),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      dividerTheme: const DividerThemeData(color: Color(0xFFE2E8F0), thickness: 1),
    );
  }

  static ThemeData get darkTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primaryColor,
      brightness: Brightness.dark,
      secondary: secondaryColor,
      tertiary: accentColor,
      error: errorColor,
    );
    final base = ThemeData(useMaterial3: true, colorScheme: colorScheme, brightness: Brightness.dark);
    return base.copyWith(
      textTheme: _buildTextTheme(base.textTheme),
      scaffoldBackgroundColor: const Color(0xFF0B1220),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        centerTitle: true,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: const Color(0xFF161E2E),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppBorderRadius.xl),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          minimumSize: const Size.fromHeight(48),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppBorderRadius.md),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppBorderRadius.md),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF1E293B),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppBorderRadius.md),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      dividerTheme: const DividerThemeData(color: Color(0xFF283548), thickness: 1),
    );
  }
}

// Text Styles
class AppTextStyles {
  static TextStyle get heading1 => GoogleFonts.inter(fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: -0.5);
  static TextStyle get heading2 => GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w600, letterSpacing: -0.25);
  static TextStyle get heading3 => GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w600);
  static TextStyle get body1 => GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w400);
  static TextStyle get body2 => GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w400);
  static TextStyle get caption => GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w400);
  static TextStyle get button => GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600);
}

// Spacing
class AppSpacing {
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
  static const double xxl = 48.0;
}

// Border Radius
class AppBorderRadius {
  static const double sm = 4.0;
  static const double md = 8.0;
  static const double lg = 12.0;
  static const double xl = 16.0;
  static const double circle = 50.0;
}
