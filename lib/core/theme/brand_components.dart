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
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        eyebrow.toUpperCase(),
        style: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 10,
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
                      fontSize: 9,
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
                  fontSize: 11,
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
