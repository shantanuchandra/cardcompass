import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Brand — Cyberpunk Futuristic Neon fintech 2026
  static const Color primaryColor = Color(0xFF00F5FF); // Neon Cyber Cyan
  static const Color secondaryColor = Color(0xFF8B5CF6); // High-Tech Purple
  static const Color accentColor = Color(0xFFFF007F); // Holographic Magenta
  static const Color rewardGold = Color(0xFFFFD700); // Glowing Premium Gold
  static const Color errorColor = Color(0xFFEF4444); // Blazing Neon Red
  static const Color successColor = Color(0xFF10B981); // Neon Green
  static const Color warningColor = Color(0xFFF59E0B); // Neon Amber

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

  // Neon Shadows / Glow Utilities
  static List<BoxShadow> neonGlow({required Color color, double opacity = 0.3, double blurRadius = 15}) {
    return [
      BoxShadow(
        color: color.withValues(alpha: opacity),
        blurRadius: blurRadius,
        spreadRadius: 1,
        offset: Offset.zero,
      ),
    ];
  }

  static TextTheme _buildTextTheme(TextTheme base) {
    return GoogleFonts.plusJakartaSansTextTheme(base);
  }

  static ThemeData get lightTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF2563EB),
      brightness: Brightness.light,
      primary: const Color(0xFF2563EB), // Electric Blue
      secondary: const Color(0xFF8B5CF6), // Purple
      tertiary: const Color(0xFFD946EF), // Cyber Magenta
      error: errorColor,
      surface: Colors.white,
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
        elevation: 2,
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppBorderRadius.xl),
          side: BorderSide(color: Colors.black.withValues(alpha: 0.05), width: 1.2),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 2,
          minimumSize: const Size.fromHeight(48),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppBorderRadius.lg),
          ),
          backgroundColor: const Color(0xFF2563EB),
          foregroundColor: Colors.white,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppBorderRadius.lg),
          ),
          side: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
          foregroundColor: const Color(0xFF2563EB),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF1F5F9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppBorderRadius.md),
          borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppBorderRadius.md),
          borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      dividerTheme: DividerThemeData(color: Colors.black.withValues(alpha: 0.08), thickness: 1),
    );
  }

  static ThemeData get darkTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: secondaryColor,
      brightness: Brightness.dark,
      primary: primaryColor,
      secondary: secondaryColor,
      tertiary: rewardGold,
      error: errorColor,
      surface: const Color(0xFF0C152B),
    );
    final base = ThemeData(useMaterial3: true, colorScheme: colorScheme, brightness: Brightness.dark);
    return base.copyWith(
      textTheme: _buildTextTheme(base.textTheme),
      scaffoldBackgroundColor: const Color(0xFF050B18),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        centerTitle: true,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: const Color(0xFF0C152B),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppBorderRadius.xl),
          side: const BorderSide(color: Color(0xFF1E293B), width: 1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 4,
          shadowColor: primaryColor.withValues(alpha: 0.25),
          minimumSize: const Size.fromHeight(48),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppBorderRadius.lg),
          ),
          backgroundColor: primaryColor,
          foregroundColor: const Color(0xFF050B18),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppBorderRadius.lg),
          ),
          side: const BorderSide(color: primaryColor),
          foregroundColor: Colors.white,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF0F172A),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppBorderRadius.md),
          borderSide: const BorderSide(color: Color(0xFF1E293B)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppBorderRadius.md),
          borderSide: const BorderSide(color: primaryColor, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      dividerTheme: const DividerThemeData(color: Color(0xFF1E293B), thickness: 1),
    );
  }
}

// Text Styles
class AppTextStyles {
  static TextStyle get heading1 => GoogleFonts.spaceGrotesk(fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: -0.5);
  static TextStyle get heading2 => GoogleFonts.spaceGrotesk(fontSize: 24, fontWeight: FontWeight.w600, letterSpacing: -0.25);
  static TextStyle get heading3 => GoogleFonts.spaceGrotesk(fontSize: 18, fontWeight: FontWeight.w600);
  static TextStyle get body1 => GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w400);
  static TextStyle get body2 => GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w400);
  static TextStyle get caption => GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w400);
  static TextStyle get button => GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.w600);
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
  static const double xl = 20.0;
  static const double circle = 50.0;
}
