import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cardcompass/features/evals/models/eval_metric.dart';

// ─── Score Chip ───────────────────────────────────────────────────────────────

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
    if (widget.score >= 80) return const Color(0xFF10B981);
    if (widget.score >= 50) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  @override
  Widget build(BuildContext context) {
    final double fontSize;
    final double px;
    final double py;
    switch (widget.size) {
      case EvalChipSize.small:
        fontSize = 11;
        px = 7;
        py = 3;
      case EvalChipSize.large:
        fontSize = 24;
        px = 16;
        py = 8;
      default:
        fontSize = 13;
        px = 10;
        py = 5;
    }

    return AnimatedBuilder(
      animation: _glow,
      builder: (context, _) {
        final glowOpacity = 0.12 + _glow.value * 0.22;
        return Container(
          padding: EdgeInsets.symmetric(horizontal: px, vertical: py),
          decoration: BoxDecoration(
            color: _chipColor.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: _chipColor.withValues(alpha: 0.55), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: _chipColor.withValues(alpha: glowOpacity),
                blurRadius: 14,
                spreadRadius: 0,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.score.toStringAsFixed(
                    widget.size == EvalChipSize.large ? 1 : 0),
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
                    fontSize: fontSize * 0.8,
                    color: _chipColor.withValues(alpha: 0.7),
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

// ─── Metric Card ──────────────────────────────────────────────────────────────

class EvalMetricCard extends StatelessWidget {
  const EvalMetricCard({super.key, required this.metric, this.onTap});

  final EvalMetric metric;
  final VoidCallback? onTap;

  Color get _valueColor {
    switch (metric.bucket) {
      case EvalHealthBucket.good: return const Color(0xFF10B981);
      case EvalHealthBucket.warn: return const Color(0xFFF59E0B);
      case EvalHealthBucket.bad:  return const Color(0xFFEF4444);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1B2A),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _valueColor.withValues(alpha: 0.2), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(metric.name,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 10,
                        color: Colors.white54,
                        fontWeight: FontWeight.w500,
                      )),
                ),
                if (metric.trend != null) _TrendBadge(trend: metric.trend!),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              metric.displayValue,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: _valueColor,
              ),
            ),
            if (metric.sampleSize != null)
              Text('n = ${metric.sampleSize}',
                  style: GoogleFonts.jetBrainsMono(
                      fontSize: 9, color: Colors.white24)),
            if (metric.description != null) ...[
              const SizedBox(height: 4),
              Text(metric.description!,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 9, color: Colors.white38),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ],
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
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
      'up'   => ('▲', const Color(0xFF10B981)),
      'down' => ('▼', const Color(0xFFEF4444)),
      _      => ('●', Colors.white38),
    };
    return Text(icon, style: TextStyle(fontSize: 10, color: color));
  }
}

// ─── Panel Shell ──────────────────────────────────────────────────────────────

/// Shared scaffold for all 7 eval panels.
/// On wide screens (≥ 900 px): metrics column (left) + detail scroll (right).
/// On narrow screens: metrics stacked above detail.
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
    return LayoutBuilder(builder: (ctx, constraints) {
      final wide = constraints.maxWidth >= 900;

      if (wide) {
        return Column(
          children: [
            _buildHeader(),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Metrics sidebar
                  SizedBox(
                    width: 280,
                    child: Container(
                      decoration: const BoxDecoration(
                        border: Border(
                          right: BorderSide(color: Color(0xFF1E293B)),
                        ),
                      ),
                      child: _buildMetricsList(),
                    ),
                  ),
                  // Detail
                  Expanded(child: detail),
                ],
              ),
            ),
          ],
        );
      }

      // Narrow layout
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          _buildMetricsGrid(),
          Expanded(child: detail),
        ],
      );
    });
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      decoration: const BoxDecoration(
        color: Color(0xFF071225),
        border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
      ),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(subsystemName,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                )),
          ),
          EvalScoreChip(score: score.score * 100),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }

  // Vertical list for sidebar (wide layout)
  Widget _buildMetricsList() {
    if (metrics.isEmpty) return const _NoMetricsHint();
    return ListView.separated(
      padding: const EdgeInsets.all(14),
      itemCount: metrics.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => EvalMetricCard(metric: metrics[i]),
    );
  }

  // Compact grid for narrow layout
  Widget _buildMetricsGrid() {
    if (metrics.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 1.6,
        ),
        itemCount: metrics.length,
        itemBuilder: (_, i) => EvalMetricCard(metric: metrics[i]),
      ),
    );
  }
}

class _NoMetricsHint extends StatelessWidget {
  const _NoMetricsHint();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text('No metrics available.\nRun the pipeline to collect eval data.',
          style: GoogleFonts.plusJakartaSans(fontSize: 12, color: Colors.white24)),
    );
  }
}

// ─── Shared empty state ───────────────────────────────────────────────────────

class EvalEmptyState extends StatelessWidget {
  const EvalEmptyState({
    super.key,
    required this.emoji,
    required this.title,
    required this.subtitle,
    this.action,
    this.actionLabel,
  });

  final String emoji;
  final String title;
  final String subtitle;
  final VoidCallback? action;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white12),
            ),
            child: Center(
              child: Text(emoji, style: const TextStyle(fontSize: 32)),
            ),
          ),
          const SizedBox(height: 16),
          Text(title,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white60)),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Text(subtitle,
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12, color: Colors.white30)),
          ),
          if (action != null && actionLabel != null) ...[
            const SizedBox(height: 20),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF00F5FF), width: 1),
                foregroundColor: const Color(0xFF00F5FF),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
              icon: const Icon(Icons.play_arrow, size: 14),
              label: Text(actionLabel!,
                  style: GoogleFonts.plusJakartaSans(fontSize: 12)),
              onPressed: action,
            ),
          ],
        ],
      ),
    );
  }
}
