import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/brand_tokens.dart';
import '../providers/transactions_provider.dart';

class SpendTrendPanel extends StatefulWidget {
  final SpendTrend trend;
  final String caption;

  const SpendTrendPanel({
    super.key,
    required this.trend,
    required this.caption,
  });

  @override
  State<SpendTrendPanel> createState() => _SpendTrendPanelState();
}

class _SpendTrendPanelState extends State<SpendTrendPanel> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.compactCurrency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    );

    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      child: Container(
        decoration: BoxDecoration(
          color: BrandColors.paper,
          borderRadius: BorderRadius.circular(BrandRadius.overlay),
          border: Border.all(
            color: BrandColors.focusDark.withValues(alpha: 0.15),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row — always visible
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(BrandRadius.overlay),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  BrandSpacing.md,
                  BrandSpacing.sm,
                  BrandSpacing.md,
                  BrandSpacing.sm,
                ),
                child: Row(
                  children: [
                    Text(
                      'Spend Trend',
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: BrandColors.mutedInk,
                      ),
                    ),
                    const SizedBox(width: BrandSpacing.xs),
                    Text(
                      widget.caption,
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 11,
                        color: BrandColors.mutedInk,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      _expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 18,
                      color: BrandColors.mutedInk,
                    ),
                  ],
                ),
              ),
            ),

            if (_expanded) ...[
              const Divider(height: 1, color: Color(0xFF1A2236)),
              if (widget.trend.points.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(BrandSpacing.md),
                  child: Center(
                    child: Text(
                      'No spend data for this period',
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 13,
                        color: BrandColors.mutedInk,
                      ),
                    ),
                  ),
                )
              else ...[
                // Quick stats row
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    BrandSpacing.md,
                    BrandSpacing.sm,
                    BrandSpacing.md,
                    0,
                  ),
                  child: Row(
                    children: [
                      _StatChip(
                        label: 'Daily avg',
                        value: fmt.format(widget.trend.dailyAverage),
                        color: BrandColors.focusDark,
                      ),
                      if (widget.trend.peakLabel != null) ...[
                        const SizedBox(width: BrandSpacing.sm),
                        _StatChip(
                          label: 'Peak',
                          value: widget.trend.peakLabel!,
                          color: BrandColors.rewardInk,
                        ),
                      ],
                      if (widget.trend.percentVsPrior != null) ...[
                        const SizedBox(width: BrandSpacing.sm),
                        _StatChip(
                          label: 'vs prior',
                          value:
                              '${widget.trend.percentVsPrior! >= 0 ? '+' : ''}${widget.trend.percentVsPrior!.toStringAsFixed(0)}%',
                          color: widget.trend.percentVsPrior! >= 0
                              ? BrandColors.error
                              : BrandColors.successInk,
                        ),
                      ],
                    ],
                  ),
                ),
                // Line chart
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    BrandSpacing.xs,
                    BrandSpacing.sm,
                    BrandSpacing.md,
                    BrandSpacing.sm,
                  ),
                  child: SizedBox(height: 120, child: _buildChart()),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildChart() {
    final points = widget.trend.points;
    final maxY = points.fold(0.0, (m, p) => p.total > m ? p.total : m);
    final spots = points
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.total))
        .toList();

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: BrandColors.paperDeep, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: points.length <= 14,
              reservedSize: 22,
              interval: points.length <= 7
                  ? 1
                  : (points.length / 5).ceilToDouble(),
              getTitlesWidget: (value, _) {
                final idx = value.toInt();
                if (idx < 0 || idx >= points.length) return const SizedBox();
                final d = points[idx].date;
                return Text(
                  '${d.day}/${d.month}',
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 9,
                    color: BrandColors.mutedInk,
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        minY: 0,
        maxY: maxY * 1.2,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.35,
            color: BrandColors.focusDark,
            barWidth: 2,
            dotData: FlDotData(
              show: points.length <= 10,
              getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                radius: 3,
                color: BrandColors.focusDark,
                strokeWidth: 1.5,
                strokeColor: BrandColors.paper,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  BrandColors.focusDark.withValues(alpha: 0.18),
                  BrandColors.focusDark.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => BrandColors.paperDeep,
            getTooltipItems: (spots) => spots.map((s) {
              final idx = s.spotIndex;
              final p = points[idx];
              return LineTooltipItem(
                '₹${NumberFormat.compact().format(p.total)}',
                TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 11,
                  color: BrandColors.focusDark,
                  fontWeight: FontWeight.w600,
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(BrandRadius.control),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 10,
              color: BrandColors.mutedInk,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
