/*
 * Copyright (c) 2026 Neeraj Jakhar
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 */

import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class AthleteAnalyticsDashboard extends StatelessWidget {
  final List<dynamic> biometrics;
  final String kidId;
  final List<dynamic> kids;

  const AthleteAnalyticsDashboard({
    super.key,
    required this.biometrics,
    required this.kidId,
    required this.kids,
  });

  List<FlSpot> _getChartSpots(
    String sheetId,
    String columnId,
    String? kidId,
    List<String> xAxisDates,
  ) {
    xAxisDates.clear();
    final records = biometrics
        .where(
          (b) =>
              (kidId == null || b["kid_id"] == kidId) &&
              b["sheet_id"] == sheetId,
        )
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

  Color _color({int index = -1}) {
    if (index == 0) return Colors.orange.shade700;
    if (index == 1) return Colors.blue.shade400;
    if (index == 2) return Colors.green.shade600;
    if (index == 3) return Colors.brown.shade700;
    if (index == 4) return Colors.limeAccent.shade700;

    return Colors.red.shade600;
  }

  Widget _createChart({
    required String title,
    required String subtitle,
    required int fractionDigits,
    required List<(String, String, String)> lines,
    bool useKidId = true,
  }) {
    final List<String> dates = [];
    final rows = useKidId
        ? lines.map((l) => (l.$1, l.$2, l.$3, kidId)).toList()
        : lines
              .expand(
                (l) => kids.map(
                  (k) => (l.$1, l.$2, '${l.$3} for ${k['name']}', k['id']),
                ),
              )
              .toList();

    final data = rows.map((row) {
      final (sheetId, columnId, _, id) = row;
      return _getChartSpots(sheetId, columnId, id, dates);
    }).toList();

    return _buildChartCard(
      title: title,
      subtitle: subtitle,
      chart: LineChart(
        _baseLineChartData(
          spots: data[0],
          bars: data
              .mapIndexed((i, d) => _buildLineStyle(d, _color(index: i)))
              .toList(),
          bottom: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 45,
              getTitlesWidget: (value, meta) =>
                  _buildAxisTitleWidget(value, dates),
            ),
          ),
          fractionDigits: fractionDigits,
        ),
      ),
      legend: Wrap(
        spacing: 16,
        runSpacing: 8,
        alignment: WrapAlignment.start,
        children: rows.mapIndexed((i, row) {
          final (_, _, legendText, _) = row;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: ScrollPhysics(),
            child: _buildLegendIndicator(legendText, _color(index: i)),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16.0),
    children: [
      Text('Daily Analytics'),
      const SizedBox(height: 16),
      _createChart(
        title: 'Daily Wellness, Recovery & Sleep Trends',
        subtitle: 'Tracking physical strain markers and total sleep volumes',
        fractionDigits: 1,
        lines: [
          ('daily', 'RPE', 'RPE (1-10)'),
          ('daily', 'Soreness', 'Soreness (1-10)'),
          ('daily', 'Mood', 'Mood (1-10)'),
          ('daily', 'SleepTotal', 'Total Sleep (Hrs)'),
        ],
      ),
      Text('Weekly Analytics'),
      const SizedBox(height: 16),
      _createChart(
        title: 'Weekly 5m Sprint Acceleration (s)',
        subtitle:
            'Lower values signify improved explosive footwork acceleration',
        fractionDigits: 2,
        lines: [('weekly', 'Sprint5m', '5m Sprint Time (Seconds)')],
        useKidId: false,
      ),
      const SizedBox(height: 16),
      _createChart(
        title: 'Weekly 400m Time (s)',
        subtitle: 'A test of endurance to a test of speed reserve.',
        fractionDigits: 2,
        lines: [('weekly', 'Time400m', '400m Time (s)')],
        useKidId: false,
      ),
      const SizedBox(height: 16),
      _createChart(
        title: 'Weekly Serve Speed Progression',
        subtitle: 'Monitoring serving output velocity and accuracy',
        fractionDigits: 0,
        lines: [
          ('weekly', 'ServeKmh', 'Serve Speed (wall hits)'),
          ('weekly', 'Server20', 'Serve / 20'),
        ],
        useKidId: false,
      ),
      Text('Monthly Analytics'),
      const SizedBox(height: 16),
      _createChart(
        title: 'Monthly Shoulder Internal Rotation Delta (Asymmetry °)',
        subtitle: 'Risk thresholds flag imbalances tracking above 10°',
        fractionDigits: 1,
        lines: [
          (
            'monthly',
            'IntRotationDelta',
            'Shoulder Rotation Asymmetry Delta (°)',
          ),
        ],
        useKidId: false,
      ),
      const SizedBox(height: 16),
      _createChart(
        title: 'Weekly Wall hits and Spider Drill Timings',
        subtitle: 'Monitoring reflexes and agility',
        fractionDigits: 0,
        lines: [
          ('weekly', 'WallHits30s', 'Wall Hits / 30s'),
          ('weekly', 'SpiderDrill', 'Spider Drill (s)'),
        ],
        useKidId: false,
      ),
      Text('Weight Related Analytics'),
      const SizedBox(height: 16),
      _createChart(
        title: 'Body Weight Progression (kg)',
        subtitle: 'Monitoring stable physiological mass variations',
        fractionDigits: 2,
        lines: [('weight', 'Weight', 'Body Weight (kg)')],
        useKidId: false,
      ),
      const SizedBox(height: 16),
      _createChart(
        title: 'Body Fat Ratio Progression (%)',
        subtitle: 'Tracking percentage composition changes across logs',
        fractionDigits: 1,
        lines: [('weight', 'BodyFatRatio', 'Body Fat Ratio %')],
        useKidId: false,
      ),
      _createChart(
        title: 'Visceral and Subcutaneous Fat (%)',
        subtitle: 'Tracking percentage composition changes across logs',
        fractionDigits: 1,
        lines: [
          ('weight', 'VisceralFat', 'Visceral Fat %'),
          ('weight', 'SubcutaneousFat', 'Subcutaneous Fat %'),
        ],
        useKidId: false,
      ),
    ],
  );

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
