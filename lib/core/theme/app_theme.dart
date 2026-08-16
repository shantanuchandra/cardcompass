import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'brand_tokens.dart';

abstract final class AppTheme {
  /// The default light workspace theme for authenticated product screens.
  static ThemeData get work => _build(brightness: Brightness.light);

  /// The dark theme reserved for marketing, login, and splash surfaces.
  static ThemeData get marketing => _build(brightness: Brightness.dark);

  /// Temporary compatibility name for established callers.
  @Deprecated('Use AppTheme.work or AppTheme.marketing.')
  static ThemeData get editorial => marketing;

  static ThemeData _build({required Brightness brightness}) {
    final isDark = brightness == Brightness.dark;
    final base = ThemeData(useMaterial3: true, brightness: brightness);
    final scheme = isDark
        ? const ColorScheme.dark(
            primary: BrandColors.signal,
            onPrimary: BrandColors.ink,
            primaryContainer: BrandColors.ledger,
            onPrimaryContainer: BrandColors.ink,
            secondary: BrandColors.reward,
            onSecondary: BrandColors.ink,
            secondaryContainer: BrandColors.paperDeep,
            onSecondaryContainer: BrandColors.ink,
            surface: BrandColors.inkSoft,
            onSurface: BrandColors.paper,
            surfaceContainerLowest: BrandColors.ink,
            surfaceContainerLow: BrandColors.inkSoft,
            surfaceContainer: BrandColors.inkSoft,
            surfaceContainerHigh: BrandColors.inkSoft,
            error: BrandColors.error,
            onError: BrandColors.ink,
            outline: BrandColors.mutedInk,
            outlineVariant: BrandColors.ruleOnPaper,
          )
        : const ColorScheme.light(
            primary: BrandColors.focusDark,
            onPrimary: BrandColors.paper,
            primaryContainer: BrandColors.ledger,
            onPrimaryContainer: BrandColors.ink,
            secondary: BrandColors.rewardInk,
            onSecondary: BrandColors.paper,
            secondaryContainer: BrandColors.paperDeep,
            onSecondaryContainer: BrandColors.ink,
            surface: BrandColors.paper,
            onSurface: BrandColors.ink,
            surfaceContainerLowest: BrandColors.white,
            surfaceContainerLow: BrandColors.paper,
            surfaceContainer: BrandColors.paperDeep,
            surfaceContainerHigh: BrandColors.ledger,
            error: BrandColors.error,
            onError: BrandColors.ink,
            outline: BrandColors.mutedInk,
            outlineVariant: BrandColors.ruleOnPaper,
          );
    final foreground = isDark ? BrandColors.paper : BrandColors.ink;
    final mutedForeground = isDark
        ? BrandColors.mutedPaper
        : BrandColors.mutedInk;
    final background = isDark ? BrandColors.ink : BrandColors.paper;
    final appBarBackground = isDark ? BrandColors.ink : BrandColors.paper;
    final outline = isDark ? BrandColors.ruleOnInk : BrandColors.ruleOnPaper;
    final buttonBackground = isDark
        ? BrandColors.signal
        : BrandColors.focusDark;
    final buttonForeground = isDark ? BrandColors.ink : BrandColors.paper;
    final surface = isDark ? BrandColors.inkSoft : BrandColors.paper;
    final surfaceForeground = isDark ? BrandColors.paper : BrandColors.ink;
    final surfaceOutline = isDark
        ? BrandColors.ruleOnInk
        : BrandColors.ruleOnPaper;
    final textButtonForeground = isDark
        ? BrandColors.signal
        : BrandColors.focusDark;
    final inputEnabledBorder = isDark
        ? BrandColors.mutedPaper
        : BrandColors.ruleOnPaper;
    final inputFocusedBorder = isDark
        ? BrandColors.signal
        : BrandColors.focusDark;
    // The semantic error red exceeds the 3:1 non-text contrast threshold on
    // both input fills, so it remains consistent between themes.
    const inputErrorBorder = BrandColors.error;

    final textTheme = base.textTheme
        .apply(fontFamily: 'Manrope')
        .copyWith(
          displayLarge: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 44,
            fontWeight: FontWeight.w700,
            color: foreground,
            height: 1.05,
            letterSpacing: -1.4,
          ),
          displayMedium: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 34,
            fontWeight: FontWeight.w700,
            color: foreground,
            height: 1.1,
            letterSpacing: -1,
          ),
          displaySmall: TextStyle(
            fontFamily: 'Fraunces',
            fontSize: 28,
            fontWeight: FontWeight.w600,
            color: foreground,
            height: 1.1,
          ),
          headlineLarge: TextStyle(
            fontFamily: 'Fraunces',
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: foreground,
            height: 1.15,
          ),
          headlineMedium: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: foreground,
          ),
          headlineSmall: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: foreground,
          ),
          titleLarge: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: foreground,
          ),
          titleMedium: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: foreground,
          ),
          titleSmall: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: foreground,
          ),
          bodyLarge: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 16,
            fontWeight: FontWeight.w400,
            color: foreground,
            height: 1.55,
          ),
          bodyMedium: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: foreground,
            height: 1.5,
          ),
          bodySmall: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: mutedForeground,
            height: 1.45,
          ),
          labelLarge: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: foreground,
          ),
          labelMedium: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: mutedForeground,
            letterSpacing: .35,
          ),
          labelSmall: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: mutedForeground,
            letterSpacing: 1.1,
          ),
        );

    final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(BrandRadius.control),
    );

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      textTheme: textTheme,
      splashFactory: NoSplash.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: appBarBackground,
        foregroundColor: foreground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        titleTextStyle: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: foreground,
        ),
        iconTheme: IconThemeData(color: foreground),
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BrandRadius.card),
          side: BorderSide(color: surfaceOutline),
        ),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: buttonBackground,
          foregroundColor: buttonForeground,
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
          foregroundColor: foreground,
          minimumSize: const Size(0, 48),
          side: BorderSide(color: outline),
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
          foregroundColor: textButtonForeground,
          textStyle: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? BrandColors.inkSoft : BrandColors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: BrandSpacing.md,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BrandRadius.control),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BrandRadius.control),
          borderSide: BorderSide(color: inputEnabledBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BrandRadius.control),
          borderSide: BorderSide(color: inputFocusedBorder, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BrandRadius.control),
          borderSide: const BorderSide(color: inputErrorBorder),
        ),
        hintStyle: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 14,
          color: mutedForeground,
        ),
        labelStyle: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 14,
          color: mutedForeground,
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
            fontSize: 12,
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
        backgroundColor: surface,
        selectedColor: isDark ? BrandColors.focusDark : BrandColors.ledger,
        labelStyle: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: surfaceForeground,
        ),
        side: BorderSide(color: surfaceOutline),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BrandRadius.pill),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: BrandSpacing.sm,
          vertical: BrandSpacing.xs,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surface,
        contentTextStyle: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 14,
          color: surfaceForeground,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BrandRadius.card),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BrandRadius.overlay),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
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
