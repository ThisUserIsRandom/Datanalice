import 'package:flutter/material.dart';
import 'package:cristalyse/cristalyse.dart';

class ChartCard extends StatelessWidget {
  final Map<String, dynamic> data;

  const ChartCard({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final type = data['chart_type'] as String? ?? 'bar';
    return Container(
      height: 260,
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.2)),
      ),
      child: _buildChart(type),
    );
  }

  Widget _buildChart(String type) {
    if (type == 'pie') return _buildPie();
    if (type == 'scatter') return _buildScatter();
    return _buildCartesian(type);
  }

  Widget _buildCartesian(String type) {
    final labels = List<String>.from(data['labels'] ?? data['bins'] ?? []);
    final values = List<dynamic>.from(data['values'] ?? data['counts'] ?? []);

    if (labels.isEmpty || values.isEmpty) {
      return const Center(child: Text('No data to display', style: TextStyle(color: Colors.grey)));
    }

    final chartData = List.generate(labels.length, (i) => <String, dynamic>{
      'label': labels[i],
      'value': (values[i] as num).toDouble(),
    });

    final isBar = type == 'bar' || type == 'histogram';
    final shortLabels = labels.every((l) => l.length <= 8);

    var chart = CristalyseChart()
      .data(chartData)
      .mapping(x: 'label', y: 'value')
      .theme(ChartTheme.darkTheme().copyWith(
        colorPalette: [Colors.cyanAccent],
        padding: const EdgeInsets.fromLTRB(50, 10, 10, 45),
        axisTextStyle: TextStyle(
          color: Colors.white54,
          fontSize: shortLabels ? 9 : 7,
        ),
      ))
      .animate(duration: const Duration(milliseconds: 600));

    if (isBar) {
      final bw = (labels.length > 20 ? 8.0 : labels.length > 10 ? 12.0 : 18.0);
      chart = chart.geomBar(width: bw, alpha: 0.85)
          .scaleXOrdinal()
          .scaleYContinuous(min: 0);
    } else {
      chart = chart
          .geomLine(strokeWidth: 2.0, color: Colors.cyanAccent)
          .geomPoint(size: 4.0, color: Colors.cyanAccent)
          .scaleXOrdinal()
          .scaleYContinuous();
    }

    return chart.build();
  }

  Widget _buildPie() {
    final labels = List<String>.from(data['labels'] ?? []);
    final values = List<dynamic>.from(data['values'] ?? []);

    if (labels.isEmpty || values.isEmpty) {
      return const Center(child: Text('No data to display', style: TextStyle(color: Colors.grey)));
    }

    final chartData = List.generate(labels.length, (i) => <String, dynamic>{
      'label': labels[i],
      'value': (values[i] as num).toDouble(),
    });

    return Column(
      children: [
        Expanded(
          child: CristalyseChart()
            .data(chartData)
            .mappingPie(value: 'value', category: 'label')
            .geomPie(
              outerRadius: 130,
              innerRadius: 40,
              showLabels: true,
              showPercentages: true,
              labelRadius: 160,
              labelStyle: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w600),
            )
            .theme(ChartTheme.darkTheme())
            .animate(duration: const Duration(milliseconds: 600))
            .build(),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: SingleChildScrollView(
            child: Wrap(
              spacing: 8,
              runSpacing: 2,
              children: List.generate(labels.length, (i) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 8, height: 8, color: Colors.cyanAccent.withValues(alpha: 0.6)),
                    const SizedBox(width: 3),
                    Text(
                      '${labels[i]} (${values[i]})',
                      style: const TextStyle(color: Colors.white70, fontSize: 9),
                    ),
                  ],
                );
              }),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildScatter() {
    final points = List<dynamic>.from(data['points'] ?? []);

    if (points.isEmpty) {
      return const Center(child: Text('No data to display', style: TextStyle(color: Colors.grey)));
    }

    final chartData = points.map((p) {
      final pt = List<dynamic>.from(p);
      return <String, dynamic>{
        'x': (pt[0] as num).toDouble(),
        'y': (pt[1] as num).toDouble(),
      };
    }).toList();

    return CristalyseChart()
      .data(chartData)
      .mapping(x: 'x', y: 'y')
      .geomPoint(size: 6.0, alpha: 0.8, color: Colors.cyanAccent)
      .scaleXContinuous()
      .scaleYContinuous()
      .theme(ChartTheme.darkTheme().copyWith(
        padding: const EdgeInsets.fromLTRB(50, 10, 10, 30),
      ))
      .animate(duration: const Duration(milliseconds: 600))
      .build();
  }
}
