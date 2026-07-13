import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Canonical screen scaffold for CardCompass.
///
/// Every top-level screen was independently reinventing the same
/// `Scaffold` + `AppBar` boilerplate (hardcoded dark background, ad-hoc
/// `GoogleFonts.spaceGrotesk` title styling). This widget centralizes that
/// idiom on theme tokens so screens stay correct in both light and dark
/// mode and inherit any future brand tweaks from [ThemeData] automatically.
///
/// It mirrors the `Scaffold` API it replaces (appBar/body/FAB/etc. plus
/// pass-through `actions`/`bottom` for the app bar) so it's a drop-in swap.
class CardCompassScaffold extends StatelessWidget {
  const CardCompassScaffold({
    super.key,
    this.title,
    this.actions,
    this.bottom,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.showAppBar = true,
    required this.body,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.bottomNavigationBar,
    this.bottomSheet,
    this.drawer,
    this.endDrawer,
    this.extendBodyBehindAppBar = false,
    this.resizeToAvoidBottomInset,
  });

  final String? title;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final Widget? leading;
  final bool automaticallyImplyLeading;

  /// Set false for screens that render their own custom app bar (e.g. a
  /// SliverAppBar inside a CustomScrollView) but still want the themed body.
  final bool showAppBar;

  final Widget body;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final Widget? bottomNavigationBar;
  final Widget? bottomSheet;
  final Widget? drawer;
  final Widget? endDrawer;
  final bool extendBodyBehindAppBar;
  final bool? resizeToAvoidBottomInset;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: extendBodyBehindAppBar,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      appBar: showAppBar
          ? AppBar(
              leading: leading,
              automaticallyImplyLeading: automaticallyImplyLeading,
              title: title != null ? CardCompassTitle(title!) : null,
              actions: actions,
              bottom: bottom,
            )
          : null,
      body: body,
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
      bottomNavigationBar: bottomNavigationBar,
      bottomSheet: bottomSheet,
      drawer: drawer,
      endDrawer: endDrawer,
    );
  }
}

/// The app's standard screen-title style (Space Grotesk, bold, tracked out)
/// as a reusable widget so screens stop redeclaring it inline per AppBar.
class CardCompassTitle extends StatelessWidget {
  const CardCompassTitle(this.text, {super.key, this.fontSize = 18});

  final String text;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: GoogleFonts.spaceGrotesk(
        fontWeight: FontWeight.bold,
        letterSpacing: 1.5,
        fontSize: fontSize,
        color: Theme.of(context).appBarTheme.foregroundColor,
      ),
    );
  }
}
