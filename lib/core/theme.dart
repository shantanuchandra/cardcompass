import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// CARDCOMPASS DESIGN SYSTEM — 2026 Edition
/// Cyberpunk Fintech × Liquid Glass × Intelligent Motion
///
/// This file is the single source of truth for all visual design tokens used
/// across the CardCompass Flutter app. Every value is intentional — see the
/// WHY comments for the research and reasoning behind each decision.
///
/// Web counterpart: /landing/style.css (CSS custom properties)
/// Documentation:   /landing/design-system.html (interactive reference)
/// ═══════════════════════════════════════════════════════════════════════════

class AppTheme {
  // ─── Brand Color Palette ─────────────────────────────────────────────────
  //
  // WHY these specific colors:
  //
  // Primary (Neon Cyber Cyan #00F5FF):
  //   Cyan sits at the intersection of "trustworthy blue" (banks, finance)
  //   and "innovative green" (growth, money). We push it to neon intensity
  //   to signal that CardCompass isn't a traditional bank — it's a cutting-
  //   edge AI tool. High luminance against dark backgrounds creates
  //   immediate visual hierarchy and draws the eye to primary actions.
  //
  // Secondary (High-Tech Purple #8B5CF6):
  //   Purple has centuries of association with luxury and intelligence.
  //   In modern tech (Twitch, Figma, Stripe's gradient), it signals "smart"
  //   and "premium." We use it as a gradient partner for cyan, creating a
  //   spectrum that reads as "intelligent technology."
  //
  // Accent (Holographic Magenta #FF007F):
  //   Creates urgency without the alarm of red. Used sparingly for hover
  //   states, badges, and elements that need to pop. The warmth balances
  //   our cool primary/secondary, preventing the UI from feeling cold.
  //   In cyberpunk aesthetics, magenta is the traditional complement to cyan.
  //
  // Reward Gold (#FFD700):
  //   Universal shorthand for value and achievement. In a rewards optimizer,
  //   it's the color of money saved — earnings, savings numbers, premium tier.
  //
  static const Color primaryColor = Color(0xFF00F5FF);   // Neon Cyber Cyan
  static const Color secondaryColor = Color(0xFF8B5CF6);  // High-Tech Purple
  static const Color accentColor = Color(0xFFFF007F);     // Holographic Magenta
  static const Color rewardGold = Color(0xFFFFD700);      // Glowing Premium Gold

  // ─── Semantic Colors ────────────────────────────────────────────────────
  //
  // WHY: Standard semantic colors for feedback states. Each is chosen for
  // maximum contrast against dark backgrounds while remaining on-brand:
  // - Error red is neon-hot to ensure visibility for critical failures
  // - Success green is emerald-toned (not lime) for sophistication
  // - Warning amber matches the gold family for warmth
  //
  static const Color errorColor = Color(0xFFEF4444);    // Blazing Neon Red
  static const Color successColor = Color(0xFF10B981);   // Neon Emerald
  static const Color warningColor = Color(0xFFF59E0B);   // Neon Amber

  // ─── Card Network Colors ────────────────────────────────────────────────
  //
  // WHY: Official brand colors for card network identification.
  // Used in card list views and detail screens for instant recognition.
  //
  static const Color visaColor = Color(0xFF1A1F71);
  static const Color mastercardColor = Color(0xFFEB001B);
  static const Color rupayColor = Color(0xFF0066CC);
  static const Color amexColor = Color(0xFF006FCF);

  // ─── Bank Brand Colors ──────────────────────────────────────────────────
  //
  // WHY: Official brand colors for Indian bank identification.
  // Applied as card backgrounds and accent bars in the card wallet view.
  //
  static const Color hdfcColor = Color(0xFF004C8F);
  static const Color sbiColor = Color(0xFF22409A);
  static const Color iciciColor = Color(0xFFB02A37);
  static const Color axisColor = Color(0xFF800020);
  static const Color kotakColor = Color(0xFFED1C24);

  // ─── Surface Hierarchy (Dark) ────────────────────────────────────────────
  //
  // WHY 5 levels of darkness:
  //   Creates spatial depth without 3D rendering. Each step is ~10-15
  //   lightness units apart — enough to distinguish layers but close
  //   enough to feel cohesive. Neon colors glow convincingly only
  //   against deep darks; on light backgrounds they look garish.
  //
  //   Void  (#020810) — deepest page background
  //   Base  (#050B18) — primary content canvas
  //   Raised(#0C152B) — cards, panels, elevated surfaces
  //   Overlay(#111D38) — popovers, drawers, sheets
  //   Subtle(#1E293B) — borders, dividers, hairlines
  //
  static const Color surfaceVoid = Color(0xFF020810);
  static const Color surfaceBase = Color(0xFF050B18);
  static const Color surfaceRaised = Color(0xFF0C152B);
  static const Color surfaceOverlay = Color(0xFF111D38);
  static const Color surfaceSubtle = Color(0xFF1E293B);

  // ─── Surface Hierarchy (Light) ───────────────────────────────────────────
  //
  // WHY off-white instead of pure white:
  //   Pure #FFFFFF creates harsh glare on screens, especially in data-heavy
  //   financial interfaces. Off-white (#F5F7FA) reduces eye strain while
  //   maintaining a "clean premium" feel — used by CRED, Jupiter, and most
  //   modern fintech apps in light mode.
  //
  //   Depth in light mode is created via shadows (not lighter surfaces).
  //   Cards are white on off-white background — elevation comes from
  //   soft box-shadows rather than surface-color differentiation.
  //
  static const Color lightSurfaceVoid = Color(0xFFF0F2F5);
  static const Color lightSurfaceBase = Color(0xFFF5F7FA);
  static const Color lightSurfaceRaised = Color(0xFFFFFFFF);
  static const Color lightSurfaceOverlay = Color(0xFFFFFFFF);
  static const Color lightSurfaceSubtle = Color(0xFFE2E8F0);

  // ─── Brand Accents (Light Mode) ─────────────────────────────────────────
  //
  // WHY desaturated/darkened:
  //   Neon colors are designed to "vibrate" against dark backgrounds.
  //   On light surfaces they become garish and illegible. We shift each
  //   accent toward a darker, more saturated variant of the same hue
  //   that maintains 4.5:1+ WCAG AA contrast against white.
  //
  //   Ocean teal (#0891B2) preserves cyan's "tech precision" identity.
  //   Deep violet (#7C3AED) keeps the premium AI feel.
  //   Rose (#DB2777) retains urgency without neon vibration.
  //   Amber (#D97706) preserves the reward/gold metaphor.
  //
  static const Color lightPrimaryColor = Color(0xFF0891B2);    // Ocean Teal
  static const Color lightSecondaryColor = Color(0xFF7C3AED);   // Deep Violet
  static const Color lightAccentColor = Color(0xFFDB2777);      // Rose
  static const Color lightRewardGold = Color(0xFFD97706);       // Amber

  // ─── Light Text Colors ──────────────────────────────────────────────────
  //
  // WHY charcoal instead of pure black:
  //   Pure black on white creates maximum contrast (21:1) which causes
  //   eye strain during extended reading. Slate-900 (#0F172A) achieves
  //   15:1 contrast — well above WCAG AAA (7:1) while feeling softer.
  //
  static const Color lightTextPrimary = Color(0xFF0F172A);    // Slate-900
  static const Color lightTextSecondary = Color(0xFF475569);   // Slate-600
  static const Color lightTextTertiary = Color(0xFF94A3B8);    // Slate-400
  static const Color lightTextDisabled = Color(0xFFCBD5E1);    // Slate-300

  // ─── Semantic Adaptive Helpers ───────────────────────────────────────────
  //
  // Usage: `AppTheme.adaptivePrimary(context)` returns the correct brand
  // accent for the current brightness. Screens that support both themes
  // should use these instead of the raw constants.
  //
  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color adaptivePrimary(BuildContext context) =>
      isDark(context) ? primaryColor : lightPrimaryColor;
  static Color adaptiveSecondary(BuildContext context) =>
      isDark(context) ? secondaryColor : lightSecondaryColor;
  static Color adaptiveAccent(BuildContext context) =>
      isDark(context) ? accentColor : lightAccentColor;
  static Color adaptiveGold(BuildContext context) =>
      isDark(context) ? rewardGold : lightRewardGold;

  static Color adaptiveSurfaceRaised(BuildContext context) =>
      isDark(context) ? surfaceRaised : lightSurfaceRaised;
  static Color adaptiveSurfaceSubtle(BuildContext context) =>
      isDark(context) ? surfaceSubtle : lightSurfaceSubtle;
  static Color adaptiveSurfaceBase(BuildContext context) =>
      isDark(context) ? surfaceBase : lightSurfaceBase;

  static Color adaptiveTextPrimary(BuildContext context) =>
      isDark(context) ? Colors.white : lightTextPrimary;
  static Color adaptiveTextSecondary(BuildContext context) =>
      isDark(context) ? Colors.white70 : lightTextSecondary;
  static Color adaptiveTextTertiary(BuildContext context) =>
      isDark(context) ? Colors.white38 : lightTextTertiary;
  static Color adaptiveTextDisabled(BuildContext context) =>
      isDark(context) ? Colors.white24 : lightTextDisabled;

  // ─── Neon Glow Utilities ────────────────────────────────────────────────
  //
  // WHY multi-layer shadows:
  //   A single box-shadow looks flat. Stacking shadows at different blur
  //   radii creates realistic light diffusion: tight bright core + wide
  //   diffused halo — mimicking how neon tubes actually illuminate.
  //
  //   sm  = subtle indicator glow (badges, active states)
  //   md  = standard element glow (buttons, selected cards)
  //   lg  = dramatic emphasis glow (hero elements, CTAs)
  //   xl  = cinematic ambient glow (backgrounds, decorative)
  //
  static List<BoxShadow> neonGlow({
    required Color color,
    double opacity = 0.3,
    double blurRadius = 15,
  }) {
    return [
      BoxShadow(
        color: color.withValues(alpha: opacity),
        blurRadius: blurRadius,
        spreadRadius: 1,
        offset: Offset.zero,
      ),
    ];
  }

  static List<BoxShadow> neonGlowSm({required Color color}) =>
      neonGlow(color: color, opacity: 0.25, blurRadius: 8);

  static List<BoxShadow> neonGlowMd({required Color color}) =>
      neonGlow(color: color, opacity: 0.3, blurRadius: 15);

  static List<BoxShadow> neonGlowLg({required Color color}) => [
        BoxShadow(
          color: color.withValues(alpha: 0.35),
          blurRadius: 30,
          spreadRadius: 2,
        ),
        BoxShadow(
          color: color.withValues(alpha: 0.1),
          blurRadius: 60,
          spreadRadius: 4,
        ),
      ];

  static List<BoxShadow> neonGlowXl({required Color color}) => [
        BoxShadow(
          color: color.withValues(alpha: 0.4),
          blurRadius: 60,
          spreadRadius: 4,
        ),
        BoxShadow(
          color: color.withValues(alpha: 0.15),
          blurRadius: 120,
          spreadRadius: 8,
        ),
      ];

  // ─── Glass Effect Decoration (Dark) ──────────────────────────────────────
  //
  // WHY frosted glass:
  //   backdrop-filter: blur() creates literal visual depth — content behind
  //   panels stays partially visible, making the UI feel three-dimensional.
  //   20px blur obscures detail while preserving color/light. 0.08 border
  //   opacity catches edge-light to define the panel boundary.
  //
  //   Apple's "Liquid Glass" (2025/2026) validated this aesthetic for
  //   mass-market premium interfaces.
  //
  static BoxDecoration glassDecoration({
    double borderRadius = AppBorderRadius.xl,
    Color? borderColor,
  }) {
    return BoxDecoration(
      color: surfaceRaised.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(
        color: borderColor ?? Colors.white.withValues(alpha: 0.08),
        width: 1,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.3),
          blurRadius: 32,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  // ─── Glass Effect Decoration (Light — "Frosted Pearl") ──────────────────
  //
  // WHY a separate light glass:
  //   In dark mode, glass panels are semi-transparent dark surfaces catching
  //   neon edge-light from borders. In light mode, the physics reverse:
  //   panels are semi-transparent white with subtle shadows creating depth.
  //   This is Apple's Liquid Glass adapted for light backgrounds — the panel
  //   "floats" via shadow rather than glowing via border-light.
  //
  //   The 0.85 white opacity ensures cards feel substantial (not ghostly)
  //   while the soft double-shadow (near + far) creates convincing elevation.
  //
  static BoxDecoration glassDecorationLight({
    double borderRadius = AppBorderRadius.xl,
    Color? borderColor,
  }) {
    return BoxDecoration(
      color: Colors.white.withValues(alpha: 0.85),
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(
        color: borderColor ?? Colors.black.withValues(alpha: 0.06),
        width: 1,
      ),
      boxShadow: [
        // Near shadow — tight, defines the card edge
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
        // Far shadow — diffused, creates floating depth
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  // ─── Adaptive Glass (resolves dark/light automatically) ─────────────────
  static BoxDecoration adaptiveGlass(
    BuildContext context, {
    double borderRadius = AppBorderRadius.xl,
    Color? borderColor,
  }) {
    return isDark(context)
        ? glassDecoration(borderRadius: borderRadius, borderColor: borderColor)
        : glassDecorationLight(borderRadius: borderRadius, borderColor: borderColor);
  }

  // ─── Adaptive Elevation Shadows ─────────────────────────────────────────
  //
  // WHY separate from neonGlow:
  //   In dark mode, elevation is signaled by neon glow (light emission).
  //   In light mode, elevation is signaled by shadow (light blocking).
  //   These return the appropriate depth indicator for the current theme.
  //
  static List<BoxShadow> adaptiveElevation(
    BuildContext context, {
    Color? glowColor,
    double elevation = 1, // 0-3 scale: subtle → dramatic
  }) {
    if (isDark(context)) {
      return neonGlow(
        color: glowColor ?? primaryColor,
        opacity: 0.1 + (elevation * 0.1),
        blurRadius: 8 + (elevation * 8),
      );
    }
    // Light mode: soft material shadows
    final baseOpacity = 0.03 + (elevation * 0.03);
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: baseOpacity),
        blurRadius: 4 + (elevation * 4),
        offset: Offset(0, 1 + elevation),
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: baseOpacity * 0.6),
        blurRadius: 12 + (elevation * 12),
        offset: Offset(0, 4 + (elevation * 4)),
      ),
    ];
  }

  // ─── Gradient Presets (Dark) ─────────────────────────────────────────────
  //
  // WHY these specific gradients:
  //   Primary gradient (cyan → purple) is our brand signature — used for
  //   hero elements, CTAs, and key visual anchors. The 135° angle reads
  //   naturally from top-left to bottom-right (following reading direction).
  //   The accent gradient adds magenta for urgency and visual excitement.
  //
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryColor, secondaryColor],
  );

  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryColor, secondaryColor, accentColor],
  );

  static const LinearGradient surfaceGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [surfaceVoid, surfaceBase, surfaceVoid],
  );

  // ─── Gradient Presets (Light) ───────────────────────────────────────────
  //
  // WHY desaturated gradients for light:
  //   The dark-mode neon gradients would overwhelm a light interface.
  //   Ocean teal → deep violet preserves the brand's "intelligent tech"
  //   signature while sitting harmoniously against white/off-white surfaces.
  //   Used for CTAs, progress bars, and accent elements in light mode.
  //
  static const LinearGradient primaryGradientLight = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [lightPrimaryColor, lightSecondaryColor],
  );

  static const LinearGradient accentGradientLight = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [lightPrimaryColor, lightSecondaryColor, lightAccentColor],
  );

  static const LinearGradient surfaceGradientLight = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [lightSurfaceVoid, lightSurfaceBase, lightSurfaceVoid],
  );

  // ─── Adaptive Gradients ─────────────────────────────────────────────────
  static LinearGradient adaptivePrimaryGradient(BuildContext context) =>
      isDark(context) ? primaryGradient : primaryGradientLight;
  static LinearGradient adaptiveAccentGradient(BuildContext context) =>
      isDark(context) ? accentGradient : accentGradientLight;

  // ─── Typography ─────────────────────────────────────────────────────────
  //
  // WHY these fonts:
  //   Space Grotesk (headings) = geometric sans-serif with monospaced DNA.
  //     The letterforms have the precision of code but the warmth of a
  //     humanist font — mirroring CardCompass's duality of technical AI
  //     and human-friendly UX.
  //
  //   Plus Jakarta Sans (body) = modern humanist sans-serif for screens.
  //     Slightly rounded terminals make data-heavy content feel approachable,
  //     counterbalancing the technical heading font.
  //
  static TextTheme _buildTextTheme(TextTheme base) {
    return GoogleFonts.plusJakartaSansTextTheme(base);
  }

  // ─── Light Theme (Premium Clean — "Frosted Pearl") ───────────────────────
  //
  // WHY "Same Brand, Different Physics":
  //   Dark mode uses light emission (neon glow on dark surfaces).
  //   Light mode uses material depth (shadows on light surfaces).
  //   Both share typography, layout grid, icons, and motion curves.
  //   Only surface colors and accent rendering differ.
  //
  static ThemeData get lightTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: lightPrimaryColor,
      brightness: Brightness.light,
      primary: lightPrimaryColor,
      secondary: lightSecondaryColor,
      tertiary: lightAccentColor,
      error: errorColor,
      surface: lightSurfaceRaised,
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      brightness: Brightness.light,
    );
    return base.copyWith(
      textTheme: _buildTextTheme(base.textTheme),
      scaffoldBackgroundColor: lightSurfaceBase,
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: true,
        backgroundColor: lightSurfaceRaised,
        foregroundColor: lightTextPrimary,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black.withValues(alpha: 0.06),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: lightSurfaceRaised,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppBorderRadius.xl),
          side: BorderSide(
            color: lightSurfaceSubtle.withValues(alpha: 0.6),
            width: 1,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 2,
          shadowColor: lightPrimaryColor.withValues(alpha: 0.2),
          minimumSize: const Size.fromHeight(48),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppBorderRadius.lg),
          ),
          backgroundColor: lightPrimaryColor,
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
          side: BorderSide(color: lightPrimaryColor, width: 1.5),
          foregroundColor: lightPrimaryColor,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: lightSurfaceVoid,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppBorderRadius.md),
          borderSide: BorderSide(color: lightSurfaceSubtle),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppBorderRadius.md),
          borderSide: BorderSide(color: lightPrimaryColor, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      dividerTheme: DividerThemeData(
        color: lightSurfaceSubtle,
        thickness: 1,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return lightPrimaryColor;
          return lightTextTertiary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return lightPrimaryColor.withValues(alpha: 0.3);
          }
          return lightSurfaceSubtle;
        }),
      ),
      listTileTheme: ListTileThemeData(
        textColor: lightTextPrimary,
        iconColor: lightTextSecondary,
      ),
      iconTheme: IconThemeData(
        color: lightTextSecondary,
      ),
    );
  }

  // ─── Dark Theme (Primary — matches landing page aesthetic) ──────────────
  static ThemeData get darkTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: secondaryColor,
      brightness: Brightness.dark,
      primary: primaryColor,
      secondary: secondaryColor,
      tertiary: rewardGold,
      error: errorColor,
      surface: surfaceRaised,
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      brightness: Brightness.dark,
    );
    return base.copyWith(
      textTheme: _buildTextTheme(base.textTheme),
      scaffoldBackgroundColor: surfaceBase,
      appBarTheme: const AppBarTheme(
        elevation: 0,
        centerTitle: true,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surfaceRaised,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppBorderRadius.xl),
          side: const BorderSide(color: surfaceSubtle, width: 1),
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
          foregroundColor: surfaceVoid,
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
          borderSide: const BorderSide(color: surfaceSubtle),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppBorderRadius.md),
          borderSide: const BorderSide(color: primaryColor, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      dividerTheme: const DividerThemeData(
        color: surfaceSubtle,
        thickness: 1,
      ),
    );
  }
}

// ─── Text Styles ────────────────────────────────────────────────────────────
//
// WHY Space Grotesk for headings, Plus Jakarta Sans for body:
//   See AppTheme typography comments above. The tight -0.5 tracking on h1
//   creates confident, assured typographic voice at headline sizes. Body
//   text uses default tracking for maximum readability.
//
class AppTextStyles {
  static TextStyle get heading1 => GoogleFonts.spaceGrotesk(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      );
  static TextStyle get heading2 => GoogleFonts.spaceGrotesk(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.25,
      );
  static TextStyle get heading3 => GoogleFonts.spaceGrotesk(
        fontSize: 18,
        fontWeight: FontWeight.w600,
      );
  static TextStyle get body1 => GoogleFonts.plusJakartaSans(
        fontSize: 16,
        fontWeight: FontWeight.w400,
      );
  static TextStyle get body2 => GoogleFonts.plusJakartaSans(
        fontSize: 14,
        fontWeight: FontWeight.w400,
      );
  static TextStyle get caption => GoogleFonts.plusJakartaSans(
        fontSize: 12,
        fontWeight: FontWeight.w400,
      );
  static TextStyle get button => GoogleFonts.spaceGrotesk(
        fontSize: 16,
        fontWeight: FontWeight.w600,
      );

  /// Monospace style for terminal UI, data labels, and code-like elements.
  ///
  /// WHY JetBrains Mono: Industry-standard monospace with increased x-height
  /// and designed ligatures. Makes data pipelines and technical content feel
  /// premium rather than raw. Used for section labels, badges, and metadata.
  static TextStyle get mono => GoogleFonts.jetBrainsMono(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.5,
      );
}

// ─── Spacing ────────────────────────────────────────────────────────────────
//
// WHY 8px base grid:
//   8px multiplies cleanly at every common screen density (1×, 1.5×, 2×, 3×)
//   without producing sub-pixel values. Each step is a clear perceptual
//   jump — no ambiguity between sizes. The scale follows near-doubling:
//   4 → 8 → 16 → 24 → 32 → 48 → 64 → 96 → 128.
//
class AppSpacing {
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
  static const double xxl = 48.0;
  static const double xxxl = 64.0;
  static const double xxxxl = 96.0;
}

// ─── Border Radius ──────────────────────────────────────────────────────────
//
// WHY progressive rounding:
//   Small elements (badges, inputs) get subtle rounding (4-8px) for precision.
//   Medium elements (cards, panels) get generous curves (12-20px) for
//   approachability. CTAs and pills get full rounding (50px+) for maximum
//   visual prominence. This creates an unconscious reading hierarchy:
//   rounder = more important/interactive.
//
class AppBorderRadius {
  static const double sm = 4.0;
  static const double md = 8.0;
  static const double lg = 12.0;
  static const double xl = 20.0;
  static const double xxl = 28.0;
  static const double circle = 50.0;
}

// ─── Animation Durations ────────────────────────────────────────────────────
//
// WHY these specific durations:
//   Below 100ms, transitions feel instant (good for state, bad for visibility).
//   150ms = minimum where the human eye registers motion.
//   300ms = sweet spot for UI transitions (fast but visible).
//   Beyond 800ms, users perceive the interface as "slow."
//   Every duration above 150ms should use a non-linear curve — linear = cheap.
//
class AppDurations {
  static const Duration micro = Duration(milliseconds: 150);
  static const Duration fast = Duration(milliseconds: 300);
  static const Duration normal = Duration(milliseconds: 500);
  static const Duration slow = Duration(milliseconds: 800);
  static const Duration slower = Duration(milliseconds: 1200);
}

// ─── Animation Curves (Flutter equivalents of CSS easings) ──────────────────
//
// WHY:
//   easeOutExpo = natural deceleration (real-world physics — ball rolling to stop).
//   easeOutBack = slight overshoot for "alive" interactive feedback.
//   spring = precise settle for most standard transitions.
//
class AppCurves {
  static const Curve easeOutExpo = Cubic(0.16, 1, 0.3, 1);
  static const Curve easeOutBack = Cubic(0.34, 1.56, 0.64, 1);
  static const Curve spring = Cubic(0.22, 1, 0.36, 1);
  static const Curve easeInOut = Cubic(0.65, 0, 0.35, 1);
}
