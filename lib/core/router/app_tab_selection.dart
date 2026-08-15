import 'package:flutter/widgets.dart';

/// The authenticated destinations managed by the persistent application shell.
enum AppTab { dashboard, cards, transactions, movies, settings }

/// Lets content choose an application tab without rebuilding the router.
///
/// The shell keeps the current hash fragment in sync, so callers should use
/// this instead of routing directly to a tab path.
class AppTabSelection extends InheritedWidget {
  const AppTabSelection({
    super.key,
    required this.onSelect,
    required super.child,
  });

  final ValueChanged<AppTab> onSelect;

  static AppTabSelection of(BuildContext context) {
    final selection = context
        .dependOnInheritedWidgetOfExactType<AppTabSelection>();
    assert(
      selection != null,
      'AppTabSelection is only available inside AppShell.',
    );
    return selection!;
  }

  void select(AppTab tab) => onSelect(tab);

  @override
  bool updateShouldNotify(AppTabSelection oldWidget) =>
      onSelect != oldWidget.onSelect;
}
