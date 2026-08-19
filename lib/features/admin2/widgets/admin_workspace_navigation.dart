import 'package:flutter/material.dart';

import '../../../core/theme/brand_components.dart';
import '../../../core/theme/brand_tokens.dart';

enum AdminWorkspaceSection { inbox, customers, cardData, system }

extension AdminWorkspaceSectionPresentation on AdminWorkspaceSection {
  String get label => switch (this) {
    AdminWorkspaceSection.inbox => 'Action Inbox',
    AdminWorkspaceSection.customers => 'Customers',
    AdminWorkspaceSection.cardData => 'Card Data',
    AdminWorkspaceSection.system => 'System',
  };

  IconData get icon => switch (this) {
    AdminWorkspaceSection.inbox => Icons.inbox_outlined,
    AdminWorkspaceSection.customers => Icons.people_outline,
    AdminWorkspaceSection.cardData => Icons.credit_card_outlined,
    AdminWorkspaceSection.system => Icons.settings_outlined,
  };
}

class AdminWorkspaceNavigation extends StatelessWidget {
  const AdminWorkspaceNavigation({
    super.key,
    required this.selected,
    required this.onSelected,
    required this.child,
  });

  static const desktopBreakpoint = 1024.0;

  final AdminWorkspaceSection selected;
  final ValueChanged<AdminWorkspaceSection> onSelected;
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= desktopBreakpoint) {
            return Row(
              key: const Key('admin-wide-navigation'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 248,
                  child: _WideNavigation(
                    selected: selected,
                    onSelected: onSelected,
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: child),
              ],
            );
          }

          return Column(
            key: const Key('admin-compact-navigation'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _CompactNavigation(selected: selected, onSelected: onSelected),
              const Divider(height: 1),
              Expanded(child: child),
            ],
          );
        },
      ),
    ),
  );
}

class _WideNavigation extends StatelessWidget {
  const _WideNavigation({required this.selected, required this.onSelected});

  final AdminWorkspaceSection selected;
  final ValueChanged<AdminWorkspaceSection> onSelected;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: BrandColors.inkSoft,
    child: Padding(
      padding: const EdgeInsets.all(BrandSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(
              BrandSpacing.sm,
              BrandSpacing.sm,
              BrandSpacing.sm,
              BrandSpacing.lg,
            ),
            child: Row(
              children: [
                BrandCompassMark(size: 28),
                SizedBox(width: BrandSpacing.sm),
                Expanded(
                  child: Text(
                    'Operator workspace',
                    style: TextStyle(
                      color: BrandColors.paper,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (final section in AdminWorkspaceSection.values)
            Padding(
              padding: const EdgeInsets.only(bottom: BrandSpacing.xs),
              child: _SectionControl(
                section: section,
                selected: selected == section,
                onSelected: onSelected,
                dark: true,
              ),
            ),
        ],
      ),
    ),
  );
}

class _CompactNavigation extends StatelessWidget {
  const _CompactNavigation({required this.selected, required this.onSelected});

  final AdminWorkspaceSection selected;
  final ValueChanged<AdminWorkspaceSection> onSelected;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(BrandSpacing.md),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 600 ? 4 : 2;
        const gap = BrandSpacing.sm;
        final width = (constraints.maxWidth - (columns - 1) * gap) / columns;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Operator workspace',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: BrandSpacing.compact),
            Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final section in AdminWorkspaceSection.values)
                  SizedBox(
                    width: width,
                    child: _SectionControl(
                      section: section,
                      selected: selected == section,
                      onSelected: onSelected,
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    ),
  );
}

class _SectionControl extends StatelessWidget {
  const _SectionControl({
    required this.section,
    required this.selected,
    required this.onSelected,
    this.dark = false,
  });

  final AdminWorkspaceSection section;
  final bool selected;
  final ValueChanged<AdminWorkspaceSection> onSelected;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final foreground = dark
        ? selected
              ? BrandColors.ink
              : BrandColors.paper
        : null;
    final background = dark && selected ? BrandColors.signal : null;

    return Semantics(
      key: Key('admin-section-${section.name}'),
      label: 'Admin section: ${section.label}',
      button: true,
      selected: selected,
      onTap: () => onSelected(section),
      excludeSemantics: true,
      child: OutlinedButton.icon(
        onPressed: () => onSelected(section),
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          foregroundColor: foreground,
          backgroundColor: background,
          minimumSize: const Size(44, 48),
          padding: const EdgeInsets.symmetric(
            horizontal: BrandSpacing.compact,
            vertical: BrandSpacing.sm,
          ),
          side: BorderSide(
            color: dark ? BrandColors.ruleOnInk : BrandColors.ruleOnPaper,
          ),
        ),
        icon: Icon(section.icon, size: 20),
        label: Text(section.label),
      ),
    );
  }
}
