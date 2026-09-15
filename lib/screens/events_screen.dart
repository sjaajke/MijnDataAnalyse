import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/measurement_data.dart';
import '../models/pqf_record.dart';
import '../providers/measurement_provider.dart';

class EventsScreen extends StatelessWidget {
  const EventsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<MeasurementProvider>().session;
    final theme = Theme.of(context);

    if (session == null) {
      return const Center(child: Text('No data loaded.'));
    }

    final events = session.events;

    if (events.isEmpty) {
      return const Center(child: Text('No power quality events found.'));
    }

    final dateFmt = DateFormat('dd MMM yyyy HH:mm:ss');

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Power Quality Events (${events.length})',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(
                      theme.colorScheme.surfaceContainerHighest,
                    ),
                    columns: const [
                      DataColumn(label: Text('#')),
                      DataColumn(label: Text('Tijdstip (lokaal)')),
                      DataColumn(label: Text('Type')),
                      DataColumn(label: Text('Omschrijving')),
                    ],
                    rows: events.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final event = entry.value;
                      final color = _eventColor(event);
                      return DataRow(
                        color: WidgetStateProperty.resolveWith((states) {
                          if (states.contains(WidgetState.hovered)) {
                            return theme.colorScheme.primary
                                .withValues(alpha: 0.08);
                          }
                          if (idx.isOdd) {
                            return theme.colorScheme.surfaceContainerLow
                                .withValues(alpha: 0.4);
                          }
                          return null;
                        }),
                        onSelectChanged: (_) => _showEventDetail(
                            context, idx + 1, event, session, dateFmt),
                        cells: [
                          DataCell(Text('${idx + 1}')),
                          DataCell(Text(
                            dateFmt.format(event.time.toLocal()),
                            style: const TextStyle(
                                fontFamily: 'monospace', fontSize: 12),
                          )),
                          DataCell(
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: color.withValues(alpha: 0.6)),
                              ),
                              child: Text(
                                '0x${event.typeId.toRadixString(16).padLeft(4, '0').toUpperCase()}',
                                style: TextStyle(
                                    color: color,
                                    fontFamily: 'monospace',
                                    fontSize: 12),
                              ),
                            ),
                          ),
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(event.eventName),
                              ],
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _buildLegend(theme),
        ],
      ),
    );
  }

  void _showEventDetail(BuildContext context, int nr, PqfEvent event,
      MeasurementSession session, DateFormat dateFmt) {
    final color = _eventColor(event);

    // Prefer 10s data for better resolution around the event
    final voltSource = session.voltageData10s.isNotEmpty
        ? session.voltageData10s
        : session.voltageData;
    final currSource = session.currentData10s.isNotEmpty
        ? session.currentData10s
        : session.currentData;

    final voltWindow = _windowAround(voltSource, event.time, 20);
    final currWindow = _windowAround(currSource, event.time, 20);
    final voltSample = _closest(voltSource, event.time);
    final currSample = _closest(currSource, event.time);

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      decoration:
                          BoxDecoration(color: color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Event #$nr — ${event.eventName}',
                        style: Theme.of(ctx)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(ctx).pop(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const Divider(height: 20),

                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Event details
                        _detailSection('Event details', [
                          _row('Tijdstip (lokaal)',
                              dateFmt.format(event.time.toLocal())),
                          _row('Tijdstip (UTC)', dateFmt.format(event.time)),
                          _row('Type ID',
                              '0x${event.typeId.toRadixString(16).padLeft(4, '0').toUpperCase()}'),
                          _row('Categorie',
                              _categoryLabel(event.eventCategory)),
                          _row('Omschrijving', event.eventName),
                        ]),

                        // Voltage chart
                        if (voltWindow.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          _detailSection('Spanning rondom event', []),
                          const SizedBox(height: 6),
                          _EventChart(
                            window: voltWindow,
                            eventTime: event.time,
                            keys: const ['V_L1', 'V_L2', 'V_L3'],
                            colors: const [
                              Colors.red,
                              Colors.amber,
                              Colors.blue
                            ],
                            unit: 'V',
                            eventColor: color,
                          ),
                        ],

                        // Current chart
                        if (currWindow.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          _detailSection('Stroom rondom event', []),
                          const SizedBox(height: 6),
                          _EventChart(
                            window: currWindow,
                            eventTime: event.time,
                            keys: const ['I_L1', 'I_L2', 'I_L3', 'I_N'],
                            colors: const [
                              Colors.red,
                              Colors.amber,
                              Colors.blue,
                              Colors.grey
                            ],
                            unit: 'A',
                            eventColor: color,
                          ),
                        ],

                        // Nearest sample values
                        if (voltSample != null) ...[
                          const SizedBox(height: 16),
                          _detailSection(
                            'Spanning op tijdstip event '
                            '(Δ ${_deltaSeconds(voltSample.time, event.time)})',
                            [
                              for (final entry in voltSample.values.entries
                                  .where((e) => e.key.startsWith('V_')))
                                _row(entry.key,
                                    '${entry.value.toStringAsFixed(1)} V'),
                            ],
                          ),
                        ],
                        if (currSample != null) ...[
                          const SizedBox(height: 12),
                          _detailSection(
                            'Stroom op tijdstip event '
                            '(Δ ${_deltaSeconds(currSample.time, event.time)})',
                            [
                              for (final entry in currSample.values.entries
                                  .where((e) => e.key.startsWith('I_')))
                                _row(entry.key,
                                    '${entry.value.toStringAsFixed(2)} A'),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Sluiten'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<MeasurementPoint> _windowAround(
      List<MeasurementPoint> data, DateTime target, int halfWindow) {
    if (data.isEmpty) return [];
    int idx = 0;
    int bestDiff = (data.first.time.millisecondsSinceEpoch -
            target.millisecondsSinceEpoch)
        .abs();
    for (int i = 1; i < data.length; i++) {
      final diff =
          (data[i].time.millisecondsSinceEpoch - target.millisecondsSinceEpoch)
              .abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        idx = i;
      }
    }
    final from = (idx - halfWindow).clamp(0, data.length - 1);
    final to = (idx + halfWindow).clamp(0, data.length - 1);
    return data.sublist(from, to + 1);
  }

  MeasurementPoint? _closest(
      List<MeasurementPoint> data, DateTime target) {
    if (data.isEmpty) return null;
    MeasurementPoint best = data.first;
    int bestDiff = (best.time.millisecondsSinceEpoch -
            target.millisecondsSinceEpoch)
        .abs();
    for (final p in data) {
      final diff =
          (p.time.millisecondsSinceEpoch - target.millisecondsSinceEpoch)
              .abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        best = p;
      }
      if (diff > bestDiff + 600000) break; // stop when moving away
    }
    return best;
  }

  String _deltaSeconds(DateTime a, DateTime b) {
    final ms = (a.millisecondsSinceEpoch - b.millisecondsSinceEpoch).abs();
    if (ms < 1000) return '${ms}ms';
    return '${(ms / 1000).toStringAsFixed(0)}s';
  }

  String _categoryLabel(String cat) {
    switch (cat) {
      case 'dip':
        return 'Dip';
      case 'swell':
        return 'Swell';
      case 'interruption':
        return 'Onderbreking';
      default:
        return 'Algemeen';
    }
  }

  Widget _detailSection(String title, List<Widget> rows) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.white54)),
          const SizedBox(height: 4),
          ...rows,
        ],
      );

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(
              width: 160,
              child: Text(label,
                  style: const TextStyle(fontSize: 12, color: Colors.white70)),
            ),
            Expanded(
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 12, fontFamily: 'monospace')),
            ),
          ],
        ),
      );

  Color _eventColor(PqfEvent event) {
    switch (event.eventCategory) {
      case 'dip':
        return Colors.orange;
      case 'swell':
        return Colors.blue;
      case 'interruption':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Widget _buildLegend(ThemeData theme) {
    const items = [
      ('Dip', Colors.orange),
      ('Swell', Colors.blue),
      ('Interruption', Colors.red),
      ('General / HF', Colors.grey),
    ];
    return Wrap(
      spacing: 16,
      children: items.map((item) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: item.$2,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(item.$1, style: theme.textTheme.bodySmall),
          ],
        );
      }).toList(),
    );
  }
}

// ── Mini chart shown inside the event detail dialog ───────────────────────────

class _EventChart extends StatelessWidget {
  final List<MeasurementPoint> window;
  final DateTime eventTime;
  final List<String> keys;
  final List<Color> colors;
  final String unit;
  final Color eventColor;

  const _EventChart({
    required this.window,
    required this.eventTime,
    required this.keys,
    required this.colors,
    required this.unit,
    required this.eventColor,
  });

  @override
  Widget build(BuildContext context) {
    final eventX = eventTime.millisecondsSinceEpoch.toDouble();
    final minX = window.first.time.millisecondsSinceEpoch.toDouble();
    final maxX = window.last.time.millisecondsSinceEpoch.toDouble();
    final timeFmt = DateFormat('HH:mm');

    // Build one series per key
    final bars = <LineChartBarData>[];
    double minY = double.infinity;
    double maxY = double.negativeInfinity;

    for (int i = 0; i < keys.length; i++) {
      final key = keys[i];
      final spots = window
          .where((p) => p.values.containsKey(key))
          .map((p) => FlSpot(
                p.time.millisecondsSinceEpoch.toDouble(),
                p.values[key]!,
              ))
          .toList();
      if (spots.isEmpty) continue;
      for (final s in spots) {
        if (s.y < minY) minY = s.y;
        if (s.y > maxY) maxY = s.y;
      }
      bars.add(LineChartBarData(
        spots: spots,
        color: colors[i % colors.length],
        barWidth: 1.5,
        dotData: const FlDotData(show: false),
        isCurved: false,
      ));
    }

    if (bars.isEmpty) return const SizedBox.shrink();

    // Add a little padding to y range
    final yPad = ((maxY - minY) * 0.1).clamp(1.0, double.infinity);
    minY = (minY - yPad).floorToDouble();
    maxY = (maxY + yPad).ceilToDouble();

    final chartData = LineChartData(
      minX: minX,
      maxX: maxX,
      minY: minY,
      maxY: maxY,
      clipData: const FlClipData.all(),
      gridData: FlGridData(
        show: true,
        getDrawingHorizontalLine: (_) =>
            const FlLine(color: Colors.white10, strokeWidth: 1),
        getDrawingVerticalLine: (_) =>
            const FlLine(color: Colors.white10, strokeWidth: 1),
      ),
      borderData: FlBorderData(show: true,
          border: Border.all(color: Colors.white24, width: 0.5)),
      extraLinesData: ExtraLinesData(verticalLines: [
        VerticalLine(
          x: eventX,
          color: eventColor,
          strokeWidth: 1.5,
          dashArray: [6, 4],
          label: VerticalLineLabel(
            show: true,
            labelResolver: (_) => 'event',
            style: TextStyle(fontSize: 9, color: eventColor),
            alignment: Alignment.topRight,
          ),
        ),
      ]),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            getTitlesWidget: (v, meta) => SideTitleWidget(
              meta: meta,
              child: Text(v.toStringAsFixed(0),
                  style: const TextStyle(fontSize: 9, color: Colors.white54)),
            ),
          ),
        ),
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 22,
            interval: (maxX - minX) / 4,
            getTitlesWidget: (v, meta) {
              if (v == meta.min || v == meta.max) {
                return const SizedBox.shrink();
              }
              return SideTitleWidget(
                meta: meta,
                child: Text(
                  timeFmt.format(DateTime.fromMillisecondsSinceEpoch(
                      v.toInt(), isUtc: true).toLocal()),
                  style: const TextStyle(fontSize: 9, color: Colors.white54),
                ),
              );
            },
          ),
        ),
      ),
      lineBarsData: bars,
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => Colors.black87,
          getTooltipItems: (spots) => spots.map((s) {
            final idx = s.barIndex.clamp(0, keys.length - 1);
            return LineTooltipItem(
              '${keys[idx]}: ${s.y.toStringAsFixed(1)} $unit',
              TextStyle(color: colors[idx % colors.length], fontSize: 10),
            );
          }).toList(),
        ),
      ),
    );

    return SizedBox(
      height: 180,
      child: LineChart(chartData),
    );
  }
}
