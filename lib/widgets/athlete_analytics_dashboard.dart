/*
 * Copyright (c) 2026 Neeraj Jakhar
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class AthleteAnalyticsDashboard extends StatelessWidget {
  final List<dynamic> biometrics;
  final String kidId;

  const AthleteAnalyticsDashboard({
    super.key,
    required this.biometrics,
    required this.kidId,
  });

  List<FlSpot> _getChartSpots(
    String sheetId,
    String columnId,
    List<String> xAxisDates,
  ) {
    xAxisDates.clear();
    final records = biometrics
        .where((b) => b["kid_id"] == kidId && b["sheet_id"] == sheetId)
        .toList();

    records.sort((a, b) {
      final String dateA = a["Date"] ?? a["WeekStart"] ?? "0000-00-00";
      final String dateB = b["Date"] ?? b["WeekStart"] ?? "0000-00-00";
      return dateA.compareTo(dateB);
    });

    final List<FlSpot> spots = [];
    for (int i = 0; i < records.length; i++) {
      final row = records[i];
      var rawValue = row[columnId];

      if (columnId == "SleepTotal") {
        final double night =
            double.tryParse(row["SleepNight"]?.toString() ?? "0") ?? 0;
        final double afternoon =
            double.tryParse(row["SleepAfternoon"]?.toString() ?? "0") ?? 0;
        rawValue = night + afternoon;
      }

      final double? val = double.tryParse(rawValue?.toString() ?? "");
      if (val != null) {
        spots.add(FlSpot(spots.length.toDouble(), val));
        final String rawDate = row["Date"] ?? row["WeekStart"] ?? "";

        String shortDate = rawDate;
        if (rawDate.length >= 10) {
          final String mm = rawDate.substring(5, 7);
          final String dd = rawDate.substring(8, 10);
          shortDate = "$dd-$mm";
        }
        xAxisDates.add(
          shortDate.isNotEmpty ? shortDate : spots.length.toString(),
        );
      }
    }
    return spots;
  }

  @override
  Widget build(BuildContext context) {
    final List<String> dailyDates = [];
    final List<String> weeklyDates = [];
    final List<String> monthlyDates = [];
    final List<String> weightDates = [];

    final dailySpotsRPE = _getChartSpots("daily", "RPE", dailyDates);
    final dailySpotsSoreness = _getChartSpots("daily", "Soreness", dailyDates);
    final dailySpotsMood = _getChartSpots("daily", "Mood", dailyDates);
    final dailySpotsSleep = _getChartSpots("daily", "SleepTotal", dailyDates);

    final weeklySpotsSprint = _getChartSpots("weekly", "Sprint5m", weeklyDates);
    final weeklySpotsServe = _getChartSpots("weekly", "ServeKmh", weeklyDates);

    final monthlySpotsDelta = _getChartSpots(
      "monthly",
      "IntRotationDelta",
      monthlyDates,
    );

    final List<String> bodyFatDates = [];
    final monthlyFatSpots = _getChartSpots("monthly", "BodyFat", bodyFatDates);
    final weightFatSpots = _getChartSpots(
      "weight",
      "BodyFatRatio",
      bodyFatDates,
    );

    final weightSpots = _getChartSpots("weight", "Weight", weightDates);

    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        _buildChartCard(
          title: "Daily Wellness, Recovery & Sleep Trends",
          subtitle: "Tracking physical strain markers and total sleep volumes",
          chart: LineChart(
            _baseLineChartData(
              spots: dailySpotsSleep,
              bars: [
                _buildLineStyle(dailySpotsRPE, Colors.orange.shade700),
                _buildLineStyle(dailySpotsSoreness, Colors.red.shade600),
                _buildLineStyle(dailySpotsMood, Colors.green.shade600),
                _buildLineStyle(
                  dailySpotsSleep,
                  Colors.teal.shade600,
                ), // Sleep Line path
              ],
              bottom: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 45,
                  getTitlesWidget: (value, meta) =>
                      _buildAxisTitleWidget(value, dailyDates),
                ),
              ),
              fractionDigits: 1,
            ),
          ),
          legend: Wrap(
            spacing: 16,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _buildLegendIndicator("RPE (1-10)", Colors.orange.shade700),
              _buildLegendIndicator("Soreness (1-10)", Colors.red.shade600),
              _buildLegendIndicator("Mood (1-10)", Colors.green.shade600),
              _buildLegendIndicator("Total Sleep (Hrs)", Colors.teal.shade600),
            ],
          ),
        ),
        const SizedBox(height: 16),

        _buildChartCard(
          title: "Weekly 5m Sprint Acceleration (s)",
          subtitle:
              "Lower values signify improved explosive footwork acceleration",
          chart: LineChart(
            _baseLineChartData(
              spots: weeklySpotsSprint,
              fractionDigits: 2,
              bottom: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 45,
                  getTitlesWidget: (value, meta) =>
                      _buildAxisTitleWidget(value, weeklyDates),
                ),
              ),
              bars: [
                _buildLineStyle(weeklySpotsSprint, Colors.deepPurple.shade600),
              ],
            ),
          ),
          legend: _buildLegendIndicator(
            "5m Sprint Time (Seconds)",
            Colors.deepPurple.shade600,
          ),
        ),
        const SizedBox(height: 16),

        _buildChartCard(
          title: "Weekly Serve Speed Progression (Km/h)",
          subtitle: "Monitoring serving output velocity across training cycles",
          chart: LineChart(
            _baseLineChartData(
              bars: [_buildLineStyle(weeklySpotsServe, Colors.blue.shade700)],
              bottom: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 45,
                  getTitlesWidget: (value, meta) =>
                      _buildAxisTitleWidget(value, weeklyDates),
                ),
              ),
              fractionDigits: 0,
              spots: weeklySpotsServe,
            ),
          ),
          legend: _buildLegendIndicator(
            "Serve Speed (Km/h)",
            Colors.blue.shade700,
          ),
        ),
        const SizedBox(height: 16),

        _buildChartCard(
          title: "Athlete Body Weight Progression (kg)",
          subtitle: "Monitoring stable physiological mass variations",
          chart: LineChart(
            _baseLineChartData(
              spots: weightSpots,
              bars: [_buildLineStyle(weightSpots, Colors.pink.shade700)],
              fractionDigits: 1,
              bottom: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 45,
                  getTitlesWidget: (value, meta) =>
                      _buildAxisTitleWidget(value, weightDates),
                ),
              ),
            ),
          ),
          legend: _buildLegendIndicator(
            "Body Weight (kg)",
            Colors.pink.shade700,
          ),
        ),
        const SizedBox(height: 16),

        _buildChartCard(
          title: "Athlete Body Fat Ratio Progression (%)",
          subtitle: "Tracking percentage composition changes across logs",
          chart: LineChart(
            _baseLineChartData(
              spots: weightFatSpots,
              bars: [
                if (monthlyFatSpots.isNotEmpty)
                  _buildLineStyle(monthlyFatSpots, Colors.amber.shade700),
                if (weightFatSpots.isNotEmpty)
                  _buildLineStyle(weightFatSpots, Colors.orange.shade700),
              ],
              fractionDigits: 2,
              bottom: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 45,
                  getTitlesWidget: (value, meta) =>
                      _buildAxisTitleWidget(value, bodyFatDates),
                ),
              ),
            ),
          ),
          legend: Wrap(
            spacing: 16,
            children: [
              _buildLegendIndicator("Monthly Log BF%", Colors.amber.shade700),
              _buildLegendIndicator("Weight Log BF%", Colors.orange.shade700),
            ],
          ),
        ),
        const SizedBox(height: 16),

        _buildChartCard(
          title: "Monthly Shoulder Internal Rotation Delta (Asymmetry °)",
          subtitle: "Risk thresholds flag imbalances tracking above 10°",
          chart: LineChart(
            _baseLineChartData(
              spots: monthlySpotsDelta,
              bars: [
                _buildLineStyle(monthlySpotsDelta, Colors.purple.shade700),
              ],
              fractionDigits: 1,
              bottom: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 45,
                  getTitlesWidget: (value, meta) =>
                      _buildAxisTitleWidget(value, monthlyDates),
                ),
              ),
            ),
          ),
          legend: _buildLegendIndicator(
            "Shoulder Rotation Asymmetry Delta (°)",
            Colors.purple.shade700,
          ),
        ),
      ],
    );
  }

  LineChartData _baseLineChartData({
    required List<FlSpot> spots,
    required List<LineChartBarData> bars,
    required int fractionDigits,
    required AxisTitles bottom,
  }) => LineChartData(
    lineTouchData: LineTouchData(
      touchTooltipData: LineTouchTooltipData(
        getTooltipColor: (touchedSpot) => Colors.white,
        tooltipBorder: BorderSide(color: Colors.grey.shade300),
        getTooltipItems: (t) => t
            .map(
              (s) => LineTooltipItem(
                s.y.toStringAsFixed(2),
                const TextStyle(color: Colors.black87, fontSize: 11),
              ),
            )
            .toList(),
      ),
    ),
    gridData: const FlGridData(show: true, drawVerticalLine: false),
    titlesData: FlTitlesData(
      leftTitles: _buildLeftAxisTitles(
        spots: spots,
        fractionDigits: fractionDigits,
      ),
      bottomTitles: bottom,
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    ),
    borderData: FlBorderData(
      show: true,
      border: Border.all(color: Colors.grey.shade300),
    ),
    lineBarsData: bars,
  );

  Widget _buildAxisTitleWidget(double value, List<String> dateStrings) {
    final int idx = value.toInt();
    if (idx < 0 || idx >= dateStrings.length) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Transform.rotate(
        angle: -45 * (math.pi / 180),
        child: Text(
          dateStrings[idx],
          style: const TextStyle(
            fontSize: 9,
            color: Colors.blueGrey,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }

  double _leftReservedSize(List<FlSpot> spots, int fractionDigits) {
    const style = TextStyle(fontSize: 9, fontWeight: FontWeight.bold);
    double maxW = 0;

    final ys = spots.map((e) => e.y).toList()..sort();
    if (ys.isEmpty) return 32;
    final samples = {ys.first, ys.last, (ys.first + ys.last) / 2};

    for (final v in samples) {
      final txt = v.toStringAsFixed(fractionDigits);
      final tp = TextPainter(
        text: TextSpan(text: txt, style: style),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      maxW = math.max(maxW, tp.width);
    }
    return (maxW + 18).clamp(32, 80);
  }

  AxisTitles _buildLeftAxisTitles({
    required List<FlSpot> spots,
    int fractionDigits = 1,
  }) {
    return AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: _leftReservedSize(spots, fractionDigits),
        interval: null,
        getTitlesWidget: (value, meta) {
          if ((value - meta.max).abs() < 0.0001) return const SizedBox.shrink();

          return Text(
            value.toStringAsFixed(fractionDigits),
            maxLines: 1,
            overflow: TextOverflow.visible,
            style: const TextStyle(
              fontSize: 9,
              color: Colors.blueGrey,
              fontWeight: FontWeight.bold,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          );
        },
      ),
    );
  }

  Widget _buildChartCard({
    required String title,
    required String subtitle,
    required Widget chart,
    required Widget legend,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 10, color: Colors.blueGrey),
            ),
            const SizedBox(height: 24),
            SizedBox(height: 160, child: chart),
            const SizedBox(height: 12),
            Center(child: legend),
          ],
        ),
      ),
    );
  }

  LineChartBarData _buildLineStyle(List<FlSpot> spots, Color color) {
    return LineChartBarData(
      spots: spots.isEmpty ? <FlSpot>[const FlSpot(0, 0)] : spots,
      isCurved: true,
      preventCurveOverShooting: true,
      color: color,
      barWidth: 2.5,
      isStrokeCapRound: true,
      dotData: FlDotData(show: spots.length < 15),
      belowBarData: BarAreaData(
        show: true,
        color: color.withValues(alpha: 0.04),
      ),
    );
  }

  Widget _buildLegendIndicator(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Colors.black54,
          ),
        ),
      ],
    );
  }
}
