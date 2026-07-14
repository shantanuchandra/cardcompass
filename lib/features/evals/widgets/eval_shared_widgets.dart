import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cardcompass/features/evals/models/eval_metric.dart';

// ─── Score Chip ──────────────────────────────────────────────────────────────

/// Animated neon score chip used in the app bar and panel headers.
class EvalScoreChip extends StatefulWidget {
  const EvalScoreChip({
    super.key,
    required this.score,
    this.label,
    this.size = EvalChipSize.medium,
  });

  final double score; // 0–100
  final String? label;
  final EvalChipSize size;

  @override
  State<EvalScoreChip> createState() => _EvalScoreChipState();
}

enum EvalChipSize { small, medium, large }

class _EvalScoreChipState extends State<EvalScoreChip>
    with SingleTickerProviderStateMixin {
  late AnimationController _glow;

  @override
  void initState() {
    super.initState();
    _glow = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  Color get _chipColor {
    if (widget.score >= 80) return const Color(0xFF10B981); // green
    if (widget.score >= 50) return const Color(0xFFF59E0B); // amber
    return const Color(0xFFEF4444); // red
  }

  @override
  Widget build(BuildContext context) {
    final double fontSize;
    final double padding;
    switch (widget.size) {
      case EvalChipSize.small:
        fontSize = 11;
        padding = 6;
      case EvalChipSize.large:
        fontSize = 22;
        padding = 14;
      default:
        fontSize = 14;
        padding = 10;
    }

    return AnimatedBuilder(
      animation: _glow,
      builder: (context, _) {
        final glowOpacity = 0.15 + _glow.value * 0.25;
        return Container(
          padding: EdgeInsets.symmetric(horizontal: padding, vertical: padding / 2),
          decoration: BoxDecoration(
            color: _chipColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: _chipColor.withValues(alpha: 0.6), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: _chipColor.withValues(alpha: glowOpacity),
                blurRadius: 12,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${widget.score.toStringAsFixed(widget.size == EvalChipSize.large ? 1 : 0)}',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: fontSize,
                  fontWeight: FontWeight.bold,
                  color: _chipColor,
                ),
              ),
              if (widget.label != null) ...[
                const SizedBox(width: 4),
                Text(
                  widget.label!,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: fontSize * 0.85,
                    color: _chipColor.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ─── Metric Card ─────────────────────────────────────────────────────────────

class EvalMetricCard extends StatelessWidget {
  const EvalMetricCard({
    super.key,
    required this.metric,
    this.onTap,
  });

  final EvalMetric metric;
  final VoidCallback? onTap;

  Color get _valueColor {
    switch (metric.bucket) {
      case EvalHealthBucket.good:
        return const Color(0xFF10B981);
      case EvalHealthBucket.warn:
        return const Color(0xFFF59E0B);
      case EvalHealthBucket.bad:
        return const Color(0xFFEF4444);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1B2A),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _valueColor.withValues(alpha: 0.25),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    metric.name,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      color: Colors.white54,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (metric.trend != null)
                  _TrendBadge(trend: metric.trend!),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              metric.displayValue,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: _valueColor,
              ),
            ),
            if (metric.sampleSize != null) ...[
              const SizedBox(height: 4),
              Text(
                'n = ${metric.sampleSize}',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  color: Colors.white24,
                ),
              ),
            ],
            if (metric.description != null) ...[
              const SizedBox(height: 6),
              Text(
                metric.description!,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  color: Colors.white38,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: metric.value.clamp(0.0, 1.0),
                minHeight: 3,
                backgroundColor: Colors.white10,
                valueColor: AlwaysStoppedAnimation<Color>(_valueColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrendBadge extends StatelessWidget {
  const _TrendBadge({required this.trend});
  final String trend;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (trend) {
      'up' => ('▲', const Color(0xFF10B981)),
      'down' => ('▼', const Color(0xFFEF4444)),
      _ => ('●', Colors.white38),
    };
    return Text(icon,
        style: TextStyle(fontSize: 10, color: color));
  }
}

// ─── Shared Panel Shell ───────────────────────────────────────────────────────

class EvalPanelShell extends StatelessWidget {
  const EvalPanelShell({
    super.key,
    required this.score,
    required this.subsystemName,
    required this.icon,
    required this.metrics,
    required this.detail,
    this.trailing,
  });

  final SubsystemScore score;
  final String subsystemName;
  final String icon;
  final List<EvalMetric> metrics;
  final Widget detail;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Row(
            children: [
              Text(icon, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  subsystemName,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              EvalScoreChip(score: score.score * 100),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
              ],
            ],
          ),
        ),
        // Metrics grid
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: LayoutBuilder(builder: (context, constraints) {
            final cols = constraints.maxWidth > 600 ? 3 : 2;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1.7,
              ),
              itemCount: metrics.length,
              itemBuilder: (_, i) => EvalMetricCard(metric: metrics[i]),
            );
          }),
        ),
        const SizedBox(height: 16),
        // Detail section
        Expanded(child: detail),
      ],
    );
  }
}
