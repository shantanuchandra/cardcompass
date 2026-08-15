import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'brand_tokens.dart';

abstract final class AppTheme {
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

  static Color issuerColor(String bankCode) => switch (bankCode.toLowerCase()) {
    'hdfc' => const Color(0xFF004C8F),
    'sbi' => const Color(0xFF22409A),
    'icici' => const Color(0xFFB02A37),
    'axis' => const Color(0xFF800020),
    'kotak' => const Color(0xFFED1C24),
    'amex' => const Color(0xFF006FCF),
    _ => BrandColors.mutedInk,
  };
}
