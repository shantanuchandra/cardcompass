import 'package:flutter/material.dart';

import 'brand_tokens.dart';

class BrandCompassMark extends StatelessWidget {
  const BrandCompassMark({super.key, this.size = 28});
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'CardCompass',
    image: true,
    child: ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: const _BrandCompassPainter()),
      ),
    ),
  );
}

class _BrandCompassPainter extends CustomPainter {
  const _BrandCompassPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(size.width * .24),
      ),
      Paint()..color = BrandColors.ink,
    );
    canvas.drawCircle(
      center,
      size.width * .3,
      Paint()..color = BrandColors.signal,
    );
    final needle = Path()
      ..moveTo(center.dx + size.width * .2, center.dy - size.height * .27)
      ..lineTo(center.dx + size.width * .06, center.dy + size.height * .08)
      ..lineTo(center.dx - size.width * .2, center.dy + size.height * .27)
      ..lineTo(center.dx - size.width * .06, center.dy - size.height * .08)
      ..close();
    canvas.drawPath(needle, Paint()..color = BrandColors.ink);
    canvas.drawCircle(
      center,
      size.width * .045,
      Paint()..color = BrandColors.paper,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

enum BrandSurfaceTone { paper, ledger, evidence }

class BrandSurface extends StatelessWidget {
  const BrandSurface({
    super.key,
    required this.child,
    this.tone = BrandSurfaceTone.paper,
    this.padding = const EdgeInsets.all(BrandSpacing.lg),
  });

  final Widget child;
  final BrandSurfaceTone tone;
  final EdgeInsetsGeometry padding;

  Color get _background => switch (tone) {
    BrandSurfaceTone.paper => BrandColors.paper,
    BrandSurfaceTone.ledger => BrandColors.ledger,
    BrandSurfaceTone.evidence => BrandColors.inkSoft,
  };

  Color get _foreground =>
      tone == BrandSurfaceTone.evidence ? BrandColors.paper : BrandColors.ink;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: _background,
      borderRadius: BorderRadius.circular(BrandRadius.card),
      border: Border.all(
        color: tone == BrandSurfaceTone.evidence
            ? BrandColors.ruleOnInk
            : BrandColors.ruleOnPaper,
      ),
    ),
    child: DefaultTextStyle.merge(
      style: TextStyle(color: _foreground),
      child: child,
    ),
  );
}

class BrandSectionHeader extends StatelessWidget {
  const BrandSectionHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    this.description,
    this.editorial = true,
  });

  final String eyebrow;
  final String title;
  final String? description;
  final bool editorial;

  @override
  Widget build(BuildContext context) => SelectionArea(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          eyebrow.toUpperCase(),
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.3,
            color: BrandColors.mutedInk,
          ),
        ),
        const SizedBox(height: BrandSpacing.sm),
        Text(
          title,
          style: editorial
              ? TextStyle(
                  fontFamily: 'Fraunces',
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                  height: 1.08,
                  color: BrandColors.ink,
                )
              : TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                  color: BrandColors.ink,
                ),
        ),
        if (description != null) ...[
          const SizedBox(height: BrandSpacing.sm),
          Text(
            description!,
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 14,
              height: 1.5,
              color: BrandColors.mutedInk,
            ),
          ),
        ],
      ],
    ),
  );
}

/// Keeps prose and forms comfortably readable while permitting wider data
/// layouts where comparison and tabular views need it.
enum BrandContentMode { constrained, fullWidthData }

class BrandContentFrame extends StatelessWidget {
  const BrandContentFrame({
    super.key,
    required this.child,
    this.mode = BrandContentMode.constrained,
  });

  final Widget child;
  final BrandContentMode mode;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final horizontalPadding = constraints.maxWidth >= 768
          ? BrandSpacing.xl
          : BrandSpacing.md;
      final contentWidth = switch (mode) {
        BrandContentMode.constrained => 960.0,
        BrandContentMode.fullWidthData => 1440.0,
      };
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: contentWidth),
            child: child,
          ),
        ),
      );
    },
  );
}

class BrandPageHeader extends StatelessWidget {
  const BrandPageHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.description,
    this.trailing,
  });

  final String title;
  final String? eyebrow;
  final String? description;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (eyebrow != null) ...[
          Text(
            eyebrow!.toUpperCase(),
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: BrandSpacing.sm),
        ],
        Text(title, style: theme.textTheme.displaySmall),
        if (description != null) ...[
          const SizedBox(height: BrandSpacing.sm),
          Text(description!, style: theme.textTheme.bodyLarge),
        ],
      ],
    );
    if (trailing == null) return SelectionArea(child: text);

    return SelectionArea(
      child: ResponsiveValueRow(
        spacing: BrandSpacing.lg,
        children: [text, trailing!],
      ),
    );
  }
}

class BrandMetric extends StatelessWidget {
  const BrandMetric({
    super.key,
    required this.label,
    required this.value,
    this.supportingText,
  });

  final String label;
  final String value;
  final String? supportingText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: '$label: $value',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: theme.textTheme.labelMedium),
            const SizedBox(height: BrandSpacing.xs),
            Text(
              value,
              style: theme.textTheme.headlineLarge?.copyWith(
                fontFamily: 'IBM Plex Mono',
              ),
            ),
            if (supportingText != null) ...[
              const SizedBox(height: BrandSpacing.xs),
              Text(supportingText!, style: theme.textTheme.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }
}

class ResponsiveValueRow extends StatelessWidget {
  const ResponsiveValueRow({
    super.key,
    required this.children,
    this.spacing = BrandSpacing.md,
  });

  final List<Widget> children;
  final double spacing;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final usesLargeText = MediaQuery.textScalerOf(context).scale(14) >= 21;
      final stack = constraints.maxWidth < 600 || usesLargeText;
      if (stack) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: _childrenWithSpacing(vertical: true),
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: _childrenWithSpacing(),
      );
    },
  );

  List<Widget> _childrenWithSpacing({bool vertical = false}) => [
    for (var index = 0; index < children.length; index++) ...[
      if (index > 0)
        vertical ? SizedBox(height: spacing) : SizedBox(width: spacing),
      children[index],
    ],
  ];
}

class BrandActionRow extends StatelessWidget {
  const BrandActionRow({
    super.key,
    required this.title,
    this.description,
    this.leading,
    this.onTap,
    this.unavailable = false,
  }) : assert(
         (onTap != null) != unavailable,
         'Provide either onTap or unavailable: true.',
       );

  final String title;
  final String? description;
  final Widget? leading;
  final VoidCallback? onTap;
  final bool unavailable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = unavailable
        ? theme.colorScheme.onSurface.withValues(alpha: .65)
        : theme.colorScheme.onSurface;
    final content = Row(
      children: [
        if (leading != null) ...[
          IconTheme(
            data: IconThemeData(color: foreground),
            child: leading!,
          ),
          const SizedBox(width: BrandSpacing.compact),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(color: foreground),
              ),
              if (description != null) ...[
                const SizedBox(height: BrandSpacing.xs),
                Text(
                  description!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: foreground,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (unavailable)
          Text('Coming soon', style: theme.textTheme.labelMedium)
        else
          Icon(Icons.chevron_right_rounded, color: foreground),
      ],
    );

    return Semantics(
      label: unavailable ? '$title, unavailable' : title,
      button: true,
      enabled: !unavailable,
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(BrandRadius.control),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: BrandSpacing.sm,
                  vertical: BrandSpacing.compact,
                ),
                child: content,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class BrandStateView extends StatelessWidget {
  const BrandStateView({
    super.key,
    required this.title,
    required this.message,
    required this.icon,
    this.actionLabel,
    this.onAction,
  }) : assert(
         (actionLabel == null) == (onAction == null),
         'Provide both actionLabel and onAction, or neither.',
       );

  final String title;
  final String message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 40, color: theme.colorScheme.primary),
              const SizedBox(height: BrandSpacing.md),
              Text(
                title,
                style: theme.textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: BrandSpacing.sm),
              Text(
                message,
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              if (actionLabel != null) ...[
                const SizedBox(height: BrandSpacing.lg),
                OutlinedButton(
                  onPressed: onAction,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(44, 44),
                  ),
                  child: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A deterministic loading placeholder that preserves the page's content
/// footprint while data is in flight. It intentionally avoids animation so
/// reduced-motion users and tests receive the same stable structure.
class BrandLoadingSkeleton extends StatelessWidget {
  const BrandLoadingSkeleton({
    super.key,
    required this.semanticLabel,
    this.minHeight = 280,
    this.itemCount = 3,
  });

  final String semanticLabel;
  final double minHeight;
  final int itemCount;

  @override
  Widget build(BuildContext context) => Semantics(
    label: semanticLabel,
    liveRegion: true,
    child: ExcludeSemantics(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: minHeight),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: const EdgeInsets.all(BrandSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SkeletonBar(widthFactor: .42, height: 20),
                  const SizedBox(height: BrandSpacing.lg),
                  for (var index = 0; index < itemCount; index++) ...[
                    const _SkeletonBar(height: 64),
                    if (index + 1 < itemCount)
                      const SizedBox(height: BrandSpacing.sm),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _SkeletonBar extends StatelessWidget {
  const _SkeletonBar({required this.height, this.widthFactor = 1});

  final double height;
  final double widthFactor;

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    alignment: Alignment.centerLeft,
    widthFactor: widthFactor,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: BrandColors.ledger,
        borderRadius: BorderRadius.circular(BrandRadius.control),
        border: Border.all(color: BrandColors.ruleOnPaper),
      ),
      child: SizedBox(height: height),
    ),
  );
}

class BrandEvidence {
  const BrandEvidence({required this.label, required this.value});
  final String label;
  final String value;
}

class BrandEvidenceStrip extends StatelessWidget {
  const BrandEvidenceStrip({super.key, required this.rows});
  final List<BrandEvidence> rows;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: BrandColors.inkSoft,
      borderRadius: BorderRadius.circular(BrandRadius.control),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: BrandSpacing.md,
        vertical: BrandSpacing.compact,
      ),
      child: Wrap(
        spacing: BrandSpacing.xl,
        runSpacing: BrandSpacing.compact,
        children: rows
            .map(
              (row) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    row.label.toUpperCase(),
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                      color: BrandColors.mutedPaper,
                    ),
                  ),
                  const SizedBox(height: BrandSpacing.xs),
                  Text(
                    row.value,
                    style: TextStyle(
                      fontFamily: 'IBM Plex Mono',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: BrandColors.paper,
                    ),
                  ),
                ],
              ),
            )
            .toList(growable: false),
      ),
    ),
  );
}

enum BrandStatusTone { neutral, success, reward, error }

class BrandStatusChip extends StatelessWidget {
  const BrandStatusChip({
    super.key,
    required this.label,
    this.tone = BrandStatusTone.neutral,
    this.icon,
  });
  final String label;
  final BrandStatusTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (tone) {
      BrandStatusTone.success => (BrandColors.ledger, BrandColors.successInk),
      BrandStatusTone.reward => (BrandColors.reward, BrandColors.ink),
      BrandStatusTone.error => (BrandColors.error, BrandColors.ink),
      BrandStatusTone.neutral => (BrandColors.paperDeep, BrandColors.mutedInk),
    };
    return Semantics(
      label: label,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(BrandRadius.pill),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: BrandSpacing.compact,
            vertical: BrandSpacing.xs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 13, color: foreground),
                const SizedBox(width: BrandSpacing.xs),
              ],
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
