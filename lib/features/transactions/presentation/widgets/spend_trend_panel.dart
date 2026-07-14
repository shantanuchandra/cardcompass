import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme.dart';
import '../../viewmodels/transactions_viewmodel.dart';

/// Collapsible spend-trend chart panel for the Ledger Txns page. Starts
/// collapsed; tapping the pill expands it in place. Renders nothing if
/// [state.spendTrend()] has no data to show.
class SpendTrendPanel extends StatefulWidget {
  final TransactionsViewState state;
  final String filterScopeCaption;

  const SpendTrendPanel({
    super.key,
    required this.state,
    required this.filterScopeCaption,
  });

  @override
  State<SpendTrendPanel> createState() => _SpendTrendPanelState();
}

class _SpendTrendPanelState extends State<SpendTrendPanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final trend = widget.state.spendTrend();
    if (trend == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: const Color(0xFF0C152B),
        borderRadius: BorderRadius.circular(AppBorderRadius.xl),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          if (_expanded) ...[
            const SizedBox(height: AppSpacing.md),
            _buildChart(trend),
            const SizedBox(height: AppSpacing.md),
            _buildStatsRow(trend),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return InkWell(
      onTap: () => setState(() => _expanded = !_expanded),
      borderRadius: BorderRadius.circular(AppBorderRadius.md),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Icon(Icons.show_chart, color: AppTheme.primaryColor, size: 18),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'SPEND TREND',
                style: GoogleFonts.spaceGrotesk(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                widget.filterScopeCaption,
                style: GoogleFonts.spaceGrotesk(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
          Icon(
            _expanded ? Icons.expand_less : Icons.expand_more,
            color: AppTheme.primaryColor,
            size: 20,
          ),
        ],
      ),
    );
  }

  Widget _buildChart(SpendTrendSummary trend) {
    final spots = [
      for (var i = 0; i < trend.points.length; i++)
        FlSpot(i.toDouble(), trend.points[i].total),
    ];

    return SizedBox(
      height: 140,
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (value) => FlLine(
              color: Colors.white.withValues(alpha: 0.08),
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: (trend.points.length / 3).ceilToDouble().clamp(1, 100.0),
                getTitlesWidget: (value, meta) {
                  final index = value.round();
                  if (index < 0 || index >= trend.points.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      trend.points[index].label,
                      style: GoogleFonts.spaceGrotesk(color: Colors.white38, fontSize: 9),
                    ),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: AppTheme.primaryColor,
              barWidth: 2.5,
              dotData: FlDotData(
                show: true,
                checkToShowDot: (spot, barData) => spot.x == (spots.length - 1).toDouble(),
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppTheme.primaryColor.withValues(alpha: 0.3),
                    AppTheme.primaryColor.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsRow(SpendTrendSummary trend) {
    final percent = trend.percentVsPriorPeriod;
    final isIncrease = (percent ?? 0) > 0;
    final isFlat = percent != null && percent == 0.0;

    return Row(
      children: [
        Expanded(
          child: _stat(
            'DAILY AVG',
            '₹${trend.dailyAverage.toStringAsFixed(0)}',
            AppTheme.primaryColor,
          ),
        ),
        Expanded(
          child: _stat(
            'VS LAST PERIOD',
            percent == null
                ? '—'
                : isFlat
                    ? '→ 0%'
                    : '${isIncrease ? '↑' : '↓'} ${percent.abs().toStringAsFixed(0)}%',
            percent == null || isFlat
                ? Colors.white54
                : (isIncrease ? AppTheme.errorColor : AppTheme.successColor),
          ),
        ),
        Expanded(
          child: _stat('PEAK DAY', trend.peakLabel, Colors.white),
        ),
      ],
    );
  }

  Widget _stat(String label, String value, Color valueColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.spaceGrotesk(
            color: Colors.white38,
            fontSize: 10,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: GoogleFonts.spaceGrotesk(
            color: valueColor,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}
