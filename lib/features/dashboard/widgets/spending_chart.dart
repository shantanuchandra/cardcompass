import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cardcompass/shared/models/analytics.dart';
import 'package:cardcompass/core/theme.dart';

/// Widget for displaying spending trend chart with cyber-fintech neon lines
class SpendingChart extends StatelessWidget {
  final List<MonthlySpending> monthlyData;

  const SpendingChart({
    super.key,
    required this.monthlyData,
  });

  @override
  Widget build(BuildContext context) {
    if (monthlyData.isEmpty) {
      return Center(
        child: Text(
          'NO SPENDING DATA RECORDED',
          style: GoogleFonts.spaceGrotesk(
            color: Colors.white30,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
          ),
        ),
      );
    }

    final interval = _calculateInterval();

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: interval,
          getDrawingHorizontalLine: (value) {
            return const FlLine(
              color: Colors.white10,
              strokeWidth: 1,
            );
          },
        ),
        titlesData: FlTitlesData(
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              interval: 1,
              getTitlesWidget: (value, meta) {
                if (value.toInt() >= 0 && value.toInt() < monthlyData.length) {
                  final month = monthlyData[value.toInt()].month;
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      month.length > 5 ? month.substring(5) : month, // Show only MM part
                      style: GoogleFonts.spaceGrotesk(
                        color: Colors.white38,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  );
                }
                return const Text('');
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 46,
              interval: interval,
              getTitlesWidget: (value, meta) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: Text(
                    '₹${(value / 1000).toStringAsFixed(0)}K',
                    style: GoogleFonts.spaceGrotesk(
                      color: Colors.white38,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(
          show: true,
          border: const Border(
            bottom: BorderSide(color: Colors.white10, width: 1.5),
            left: BorderSide(color: Colors.white10, width: 1.5),
          ),
        ),
        minX: 0,
        maxX: (monthlyData.length - 1).toDouble(),
        minY: 0,
        maxY: _getMaxValue() * 1.15,
        lineBarsData: [
          // Spending line: Cyan gradient
          LineChartBarData(
            spots: monthlyData.asMap().entries.map((entry) {
              return FlSpot(
                entry.key.toDouble(),
                entry.value.totalSpending,
              );
            }).toList(),
            isCurved: true,
            gradient: const LinearGradient(
              colors: [AppTheme.primaryColor, Color(0xFF00A2FF)],
            ),
            barWidth: 4,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) {
                return FlDotCirclePainter(
                  radius: 5,
                  color: AppTheme.primaryColor,
                  strokeWidth: 2,
                  strokeColor: const Color(0xFF050B18),
                );
              },
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  AppTheme.primaryColor.withValues(alpha: 0.15),
                  AppTheme.primaryColor.withValues(alpha: 0.0),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          // Rewards line: Magenta/Gold gradient
          LineChartBarData(
            spots: monthlyData.asMap().entries.map((entry) {
              return FlSpot(
                entry.key.toDouble(),
                entry.value.rewardsEarned,
              );
            }).toList(),
            isCurved: true,
            gradient: const LinearGradient(
              colors: [AppTheme.accentColor, AppTheme.rewardGold],
            ),
            barWidth: 2.5,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) {
                return FlDotCirclePainter(
                  radius: 4,
                  color: AppTheme.rewardGold,
                  strokeWidth: 2.5,
                  strokeColor: const Color(0xFF050B18),
                );
              },
            ),
            belowBarData: BarAreaData(show: false),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (touchedSpot) => const Color(0xFF0C152B),
            tooltipBorder: const BorderSide(color: Color(0xFF1E293B), width: 1.5),
            getTooltipItems: (List<LineBarSpot> touchedSpots) {
              return touchedSpots.map((spot) {
                final isSpending = spot.barIndex == 0;
                return LineTooltipItem(
                  '${isSpending ? 'SPENDING' : 'REWARDS'}\n₹${spot.y.toStringAsFixed(0)}',
                  GoogleFonts.spaceGrotesk(
                    color: isSpending ? AppTheme.primaryColor : AppTheme.rewardGold,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                );
              }).toList();
            },
          ),
        ),
      ),
    );
  }

  /// Calculate appropriate interval for Y-axis
  double _calculateInterval() {
    final maxValue = _getMaxValue();
    if (maxValue <= 1000) return 200;
    if (maxValue <= 5000) return 1000;
    if (maxValue <= 10000) return 2000;
    if (maxValue <= 50000) return 10000;
    return 20000;
  }

  /// Get maximum value from data
  double _getMaxValue() {
    if (monthlyData.isEmpty) return 1000;
    
    double maxSpending = monthlyData
        .map((data) => data.totalSpending)
        .where((spending) => spending > 0)
        .fold(0.0, (a, b) => a > b ? a : b);
    
    return maxSpending > 0 ? maxSpending : 1000;
  }
}
