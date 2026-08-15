import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CardCompass Design System — Cyberpunk Fintech Dark
// Primary surface: void black (#020810)
// Accent: neon cyan (#00F5FF) + violet (#8B5CF6)
// Typography: Space Grotesk (headings) + Inter (body)
// ─────────────────────────────────────────────────────────────────────────────

class AppColors {
  // Surfaces
  static const surfaceVoid = Color(0xFF020810);
  static const surface1 = Color(0xFF0C152B);
  static const surface2 = Color(0xFF111827);
  static const surface3 = Color(0xFF1E293B);
  static const surfaceCard = Color(0xFF0F172A);

  // Brand accents
  static const neonCyan = Color(0xFF00F5FF);
  static const neonCyanDim = Color(0xFF00C8D4);
  static const violet = Color(0xFF8B5CF6);
  static const violetDim = Color(0xFF6D28D9);
  static const neonGreen = Color(0xFF15803D);

  // Semantic
  static const success = Color(0xFF22C55E);
  static const error = Color(0xFFEF4444);
  static const warning = Color(0xFFF59E0B);

  // Text
  static const textPrimary = Color(0xFFE2E8F0);
  static const textSecondary = Color(0xFF94A3B8);
  static const textMuted = Color(0xFF475569);
  static const textInverse = Color(0xFF020810);

  // Bank brand
  static const hdfc = Color(0xFF004C8F);
  static const sbi = Color(0xFF22409A);
  static const icici = Color(0xFFB02A37);
  static const axis = Color(0xFF800020);
  static const kotak = Color(0xFFED1C24);

  // Network
  static const visa = Color(0xFF1A1F71);
  static const mastercard = Color(0xFFEB001B);
  static const rupay = Color(0xFF0066CC);
  static const amex = Color(0xFF006FCF);
}

class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;
}

class AppRadius {
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
  static const card = 16.0;
  static const pill = 100.0;
}

class AppTheme {
  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    final colorScheme = ColorScheme.dark(
      brightness: Brightness.dark,
      primary: AppColors.neonCyan,
      onPrimary: AppColors.textInverse,
      primaryContainer: AppColors.surface1,
      onPrimaryContainer: AppColors.neonCyan,
      secondary: AppColors.violet,
      onSecondary: AppColors.textPrimary,
      secondaryContainer: AppColors.violetDim.withValues(alpha: 0.2),
      onSecondaryContainer: AppColors.violet,
      surface: AppColors.surface1,
      onSurface: AppColors.textPrimary,
      surfaceContainerLowest: AppColors.surfaceVoid,
      surfaceContainerLow: AppColors.surface2,
      surfaceContainer: AppColors.surface1,
      surfaceContainerHigh: AppColors.surface3,
      error: AppColors.error,
      onError: AppColors.textPrimary,
      outline: AppColors.textMuted.withValues(alpha: 0.3),
      outlineVariant: AppColors.textMuted.withValues(alpha: 0.15),
    );

    final textTheme = GoogleFonts.interTextTheme(base.textTheme).copyWith(
      displayLarge: GoogleFonts.spaceGrotesk(
        fontSize: 36, fontWeight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -1.0,
      ),
      displayMedium: GoogleFonts.spaceGrotesk(
        fontSize: 28, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: -0.5,
      ),
      displaySmall: GoogleFonts.spaceGrotesk(
        fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.textPrimary,
      ),
      headlineLarge: GoogleFonts.spaceGrotesk(
        fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary,
      ),
      headlineMedium: GoogleFonts.spaceGrotesk(
        fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary,
      ),
      headlineSmall: GoogleFonts.spaceGrotesk(
        fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary,
      ),
      titleLarge: GoogleFonts.inter(
        fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary,
      ),
      titleMedium: GoogleFonts.inter(
        fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary, letterSpacing: 0.1,
      ),
      titleSmall: GoogleFonts.inter(
        fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary,
      ),
      bodyLarge: GoogleFonts.inter(
        fontSize: 16, fontWeight: FontWeight.w400, color: AppColors.textPrimary, height: 1.6,
      ),
      bodyMedium: GoogleFonts.inter(
        fontSize: 14, fontWeight: FontWeight.w400, color: AppColors.textPrimary, height: 1.5,
      ),
      bodySmall: GoogleFonts.inter(
        fontSize: 12, fontWeight: FontWeight.w400, color: AppColors.textSecondary, height: 1.4,
      ),
      labelLarge: GoogleFonts.inter(
        fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary, letterSpacing: 0.1,
      ),
      labelMedium: GoogleFonts.inter(
        fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary, letterSpacing: 0.5,
      ),
      labelSmall: GoogleFonts.inter(
        fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textMuted, letterSpacing: 0.5,
      ),
    );

    return base.copyWith(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.surfaceVoid,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surfaceVoid,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        titleTextStyle: GoogleFonts.spaceGrotesk(
          fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary,
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface1,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(color: AppColors.textMuted.withValues(alpha: 0.15), width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.neonCyan,
          foregroundColor: AppColors.textInverse,
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
          textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.neonCyan,
          minimumSize: const Size(0, 48),
          side: const BorderSide(color: AppColors.neonCyan, width: 1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
          textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.neonCyan,
          textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface2,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: AppColors.textMuted.withValues(alpha: 0.3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: AppColors.textMuted.withValues(alpha: 0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.neonCyan, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        hintStyle: GoogleFonts.inter(fontSize: 14, color: AppColors.textMuted),
        labelStyle: GoogleFonts.inter(fontSize: 14, color: AppColors.textSecondary),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.surface1,
        selectedItemColor: AppColors.neonCyan,
        unselectedItemColor: AppColors.textMuted,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface1,
        indicatorColor: AppColors.neonCyan.withValues(alpha: 0.15),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: AppColors.neonCyan, size: 22);
          }
          return const IconThemeData(color: AppColors.textMuted, size: 22);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final base = GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500);
          if (states.contains(WidgetState.selected)) {
            return base.copyWith(color: AppColors.neonCyan);
          }
          return base.copyWith(color: AppColors.textMuted);
        }),
      ),
      dividerTheme: DividerThemeData(
        color: AppColors.textMuted.withValues(alpha: 0.15),
        thickness: 1,
        space: 1,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surface2,
        selectedColor: AppColors.neonCyan.withValues(alpha: 0.15),
        labelStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
        side: BorderSide(color: AppColors.textMuted.withValues(alpha: 0.2)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      ),
      listTileTheme: const ListTileThemeData(
        tileColor: Colors.transparent,
        iconColor: AppColors.textSecondary,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surface3,
        contentTextStyle: GoogleFonts.inter(fontSize: 14, color: AppColors.textPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        behavior: SnackBarBehavior.floating,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface1,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xl)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface1,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xxl)),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.neonCyan;
          return AppColors.textMuted;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.neonCyan.withValues(alpha: 0.3);
          return AppColors.surface3;
        }),
      ),
    );
  }

  // Neon glow box shadow helper
  static List<BoxShadow> neonGlow({Color color = AppColors.neonCyan, double spread = 8}) => [
    BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: spread * 2, spreadRadius: spread / 4),
    BoxShadow(color: color.withValues(alpha: 0.1), blurRadius: spread * 4),
  ];

  // Cyan gradient for hero elements
  static const LinearGradient cyanGradient = LinearGradient(
    colors: [AppColors.neonCyan, AppColors.violet],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const LinearGradient cyanFadeGradient = LinearGradient(
    colors: [AppColors.neonCyan, Color(0xFF00A8B4)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Card gradient for credit card widgets
  static LinearGradient cardGradient(String bankCode) {
    final stops = _bankGradients[bankCode.toLowerCase()] ?? _bankGradients['default']!;
    // top-left dark → bottom-right mid → top-right light shimmer gives a 3D lift on wide cards
    return LinearGradient(
      colors: [stops[0], stops[1], stops[2]],
      stops: const [0.0, 0.6, 1.0],
      begin: Alignment.bottomLeft,
      end: Alignment.topRight,
    );
  }

  // Each entry: [dark base, mid, bright highlight]
  static final _bankGradients = {
    'hdfc':     [const Color(0xFF0D47A1), const Color(0xFF1565C0), const Color(0xFF42A5F5)],
    'sbi':      [const Color(0xFF0D47A1), const Color(0xFF1565C0), const Color(0xFF42A5F5)],
    'icici':    [const Color(0xFF7B0000), const Color(0xFFB71C1C), const Color(0xFFE57373)],
    'axis':     [const Color(0xFF38006B), const Color(0xFF6A1B4D), const Color(0xFFCE93D8)],
    'kotak':    [const Color(0xFF7B0000), const Color(0xFFBF360C), const Color(0xFFFF7043)],
    'amex':     [const Color(0xFF01579B), const Color(0xFF0277BD), const Color(0xFF4FC3F7)],
    'bpcl':     [const Color(0xFF1B5E20), const Color(0xFF2E7D32), const Color(0xFF66BB6A)],
    'indusind': [const Color(0xFF38006B), const Color(0xFF6A1B9A), const Color(0xFFBA68C8)],
    'yes':      [const Color(0xFF1A237E), const Color(0xFF283593), const Color(0xFF5C6BC0)],
    'rbl':      [const Color(0xFF880E4F), const Color(0xFFAD1457), const Color(0xFFF06292)],
    'idfc':     [const Color(0xFF004D40), const Color(0xFF00695C), const Color(0xFF26A69A)],
    'bob':      [const Color(0xFF3E2723), const Color(0xFF6D4C41), const Color(0xFFA1887F)],
    'default':  [const Color(0xFF1A237E), const Color(0xFF283593), const Color(0xFF5C6BC0)],
  };
}
