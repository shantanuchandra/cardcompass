import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'brand_tokens.dart';

/// Compatibility names for screens still being migrated to semantic tokens.
/// New UI should use [BrandColors] directly.
abstract final class AppColors {
  static const surfaceVoid = BrandColors.ink;
  static const surface1 = BrandColors.inkSoft;
  static const surface2 = Color(0xFF202B31);
  static const surface3 = Color(0xFF2A363B);
  static const surfaceCard = BrandColors.inkSoft;

  static const neonCyan = BrandColors.signal;
  static const neonCyanDim = BrandColors.focusDark;
  static const violet = BrandColors.reward;
  static const violetDim = BrandColors.rewardInk;
  static const neonGreen = BrandColors.successInk;

  static const success = BrandColors.signal;
  static const error = BrandColors.error;
  static const warning = BrandColors.reward;

  static const textPrimary = BrandColors.paper;
  static const textSecondary = BrandColors.mutedPaper;
  static const textMuted = Color(0xFF71807F);
  static const textInverse = BrandColors.ink;

  static const hdfc = Color(0xFF004C8F);
  static const sbi = Color(0xFF22409A);
  static const icici = Color(0xFFB02A37);
  static const axis = Color(0xFF800020);
  static const kotak = Color(0xFFED1C24);
  static const visa = Color(0xFF1A1F71);
  static const mastercard = Color(0xFFEB001B);
  static const rupay = Color(0xFF0066CC);
  static const amex = Color(0xFF006FCF);
}

abstract final class AppSpacing {
  static const xs = BrandSpacing.xs;
  static const sm = BrandSpacing.sm;
  static const md = BrandSpacing.md;
  static const lg = BrandSpacing.lg;
  static const xl = BrandSpacing.xl;
  static const xxl = BrandSpacing.xxl;
}

abstract final class AppRadius {
  static const sm = BrandRadius.control;
  static const md = BrandRadius.card;
  static const lg = BrandRadius.overlay;
  static const xl = BrandRadius.overlay;
  static const xxl = BrandRadius.overlay;
  static const card = BrandRadius.card;
  static const pill = BrandRadius.pill;
}

abstract final class AppTheme {
  static ThemeData get dark => editorial;

  static ThemeData get editorial {
    final base = ThemeData(useMaterial3: true, brightness: Brightness.dark);
    const scheme = ColorScheme.dark(
      primary: BrandColors.signal,
      onPrimary: BrandColors.ink,
      primaryContainer: BrandColors.ledger,
      onPrimaryContainer: BrandColors.ink,
      secondary: BrandColors.reward,
      onSecondary: BrandColors.ink,
      secondaryContainer: BrandColors.paperDeep,
      onSecondaryContainer: BrandColors.ink,
      surface: BrandColors.paper,
      onSurface: BrandColors.ink,
      surfaceContainerLowest: BrandColors.ink,
      surfaceContainerLow: BrandColors.inkSoft,
      surfaceContainer: BrandColors.paper,
      surfaceContainerHigh: BrandColors.paperDeep,
      error: BrandColors.error,
      onError: BrandColors.ink,
      outline: BrandColors.mutedInk,
      outlineVariant: BrandColors.ruleOnPaper,
    );

    final textTheme = base.textTheme
        .apply(fontFamily: 'Manrope')
        .copyWith(
          displayLarge: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 44,
            fontWeight: FontWeight.w700,
            color: BrandColors.paper,
            height: 1.05,
            letterSpacing: -1.4,
          ),
          displayMedium: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 34,
            fontWeight: FontWeight.w700,
            color: BrandColors.paper,
            height: 1.1,
            letterSpacing: -1,
          ),
          displaySmall: TextStyle(
            fontFamily: 'Fraunces',
            fontSize: 28,
            fontWeight: FontWeight.w600,
            color: BrandColors.ink,
            height: 1.1,
          ),
          headlineLarge: TextStyle(
            fontFamily: 'Fraunces',
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: BrandColors.ink,
            height: 1.15,
          ),
          headlineMedium: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: BrandColors.ink,
          ),
          headlineSmall: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: BrandColors.ink,
          ),
          titleLarge: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: BrandColors.ink,
          ),
          titleMedium: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: BrandColors.ink,
          ),
          titleSmall: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: BrandColors.ink,
          ),
          bodyLarge: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 16,
            fontWeight: FontWeight.w400,
            color: BrandColors.ink,
            height: 1.55,
          ),
          bodyMedium: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: BrandColors.ink,
            height: 1.5,
          ),
          bodySmall: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: BrandColors.mutedInk,
            height: 1.45,
          ),
          labelLarge: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: BrandColors.ink,
          ),
          labelMedium: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: BrandColors.mutedInk,
            letterSpacing: .35,
          ),
          labelSmall: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: BrandColors.mutedInk,
            letterSpacing: 1.1,
          ),
        );

    final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(BrandRadius.control),
    );

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: BrandColors.ink,
      textTheme: textTheme,
      splashFactory: NoSplash.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: BrandColors.ink,
        foregroundColor: BrandColors.paper,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        titleTextStyle: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: BrandColors.paper,
        ),
        iconTheme: const IconThemeData(color: BrandColors.paper),
      ),
      cardTheme: CardThemeData(
        color: BrandColors.paper,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BrandRadius.card),
          side: const BorderSide(color: BrandColors.ruleOnPaper),
        ),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: BrandColors.signal,
          foregroundColor: BrandColors.ink,
          minimumSize: const Size(0, 48),
          elevation: 0,
          shape: controlShape,
          textStyle: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: BrandColors.paper,
          minimumSize: const Size(0, 48),
          side: const BorderSide(color: BrandColors.ruleOnInk),
          shape: controlShape,
          textStyle: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: BrandColors.focusDark,
          textStyle: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: BrandColors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: BrandSpacing.md,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BrandRadius.control),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BrandRadius.control),
          borderSide: const BorderSide(color: BrandColors.ruleOnPaper),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BrandRadius.control),
          borderSide: const BorderSide(color: BrandColors.focusDark, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BrandRadius.control),
          borderSide: const BorderSide(color: BrandColors.error),
        ),
        hintStyle: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 14,
          color: BrandColors.mutedInk,
        ),
        labelStyle: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 14,
          color: BrandColors.mutedInk,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: BrandColors.inkSoft,
        selectedItemColor: BrandColors.signal,
        unselectedItemColor: BrandColors.mutedPaper,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: BrandColors.inkSoft,
        indicatorColor: BrandColors.signal,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? BrandColors.ink
                : BrandColors.mutedPaper,
            size: 22,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontFamily: 'Manrope',
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: states.contains(WidgetState.selected)
                ? BrandColors.signal
                : BrandColors.mutedPaper,
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: BrandColors.ruleOnPaper,
        thickness: 1,
        space: 1,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: BrandColors.paperDeep,
        selectedColor: BrandColors.ledger,
        labelStyle: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: BrandColors.ink,
        ),
        side: const BorderSide(color: BrandColors.ruleOnPaper),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BrandRadius.pill),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: BrandSpacing.sm,
          vertical: BrandSpacing.xs,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: BrandColors.paper,
        contentTextStyle: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 14,
          color: BrandColors.ink,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BrandRadius.card),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: BrandColors.paper,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BrandRadius.overlay),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: BrandColors.paper,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(BrandRadius.overlay),
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? BrandColors.ink
              : BrandColors.mutedPaper,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? BrandColors.signal
              : BrandColors.mutedInk,
        ),
      ),
    );
  }

  /// Transitional helpers retained until all feature widgets use surfaces.
  static List<BoxShadow> neonGlow({
    Color color = BrandColors.ink,
    double spread = 8,
  }) => [
    BoxShadow(
      color: BrandColors.ink.withValues(alpha: .12),
      blurRadius: spread,
      offset: const Offset(0, 4),
    ),
  ];

  static const cyanGradient = LinearGradient(
    colors: [BrandColors.signal, BrandColors.focusDark],
  );
  static const cyanFadeGradient = LinearGradient(
    colors: [BrandColors.signal, BrandColors.focusDark],
  );

  static LinearGradient cardGradient(String bankCode) {
    final stops =
        _bankGradients[bankCode.toLowerCase()] ?? _bankGradients['default']!;
    return LinearGradient(
      colors: stops,
      begin: Alignment.bottomLeft,
      end: Alignment.topRight,
    );
  }

  static Color issuerColor(String bankCode) => switch (bankCode.toLowerCase()) {
        'hdfc' => AppColors.hdfc,
        'sbi' => AppColors.sbi,
        'icici' => AppColors.icici,
        'axis' => AppColors.axis,
        'kotak' => AppColors.kotak,
        'amex' => AppColors.amex,
        _ => BrandColors.mutedInk,
      };

  static final _bankGradients = <String, List<Color>>{
    'hdfc': [
      const Color(0xFF0D47A1),
      const Color(0xFF1565C0),
      const Color(0xFF42A5F5),
    ],
    'sbi': [
      const Color(0xFF0D47A1),
      const Color(0xFF1565C0),
      const Color(0xFF42A5F5),
    ],
    'icici': [
      const Color(0xFF7B0000),
      const Color(0xFFB71C1C),
      const Color(0xFFE57373),
    ],
    'axis': [
      const Color(0xFF38006B),
      const Color(0xFF6A1B4D),
      const Color(0xFFCE93D8),
    ],
    'kotak': [
      const Color(0xFF7B0000),
      const Color(0xFFBF360C),
      const Color(0xFFFF7043),
    ],
    'amex': [
      const Color(0xFF01579B),
      const Color(0xFF0277BD),
      const Color(0xFF4FC3F7),
    ],
    'bpcl': [
      const Color(0xFF1B5E20),
      const Color(0xFF2E7D32),
      const Color(0xFF66BB6A),
    ],
    'indusind': [
      const Color(0xFF38006B),
      const Color(0xFF6A1B9A),
      const Color(0xFFBA68C8),
    ],
    'yes': [
      const Color(0xFF1A237E),
      const Color(0xFF283593),
      const Color(0xFF5C6BC0),
    ],
    'rbl': [
      const Color(0xFF880E4F),
      const Color(0xFFAD1457),
      const Color(0xFFF06292),
    ],
    'idfc': [
      const Color(0xFF004D40),
      const Color(0xFF00695C),
      const Color(0xFF26A69A),
    ],
    'bob': [
      const Color(0xFF3E2723),
      const Color(0xFF6D4C41),
      const Color(0xFFA1887F),
    ],
    'default': [BrandColors.inkSoft, BrandColors.focusDark, BrandColors.signal],
  };
}
