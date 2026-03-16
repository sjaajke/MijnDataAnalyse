import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/measurement_data.dart';
import '../models/pqf_record.dart';
import '../providers/measurement_provider.dart';

class TransientsScreen extends StatelessWidget {
  const TransientsScreen({super.key});

  // Transient type IDs: HF (high-frequency impulse) and General
  static const _transientIds = {0x03FD, 0x03F2};

  @override
  Widget build(BuildContext context) {
    final session = context.watch<MeasurementProvider>().session;
    final theme = Theme.of(context);

    if (session == null) {
      return const Center(child: Text('Open een meetmap om data te laden.'));
    }

    final transients = session.events
        .where((e) => _transientIds.contains(e.typeId))
        .toList();

    if (transients.isEmpty) {
      return const Center(
          child: Text('Geen transiënten gevonden in de meetdata.'));
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title + stats row
          Row(
            children: [
              Expanded(
                child: Text('Transiënten',
                    style: theme.textTheme.titleLarge),
              ),
              _StatChip(
                icon: Icons.bolt,
                label: '${transients.length} totaal',
                color: Colors.deepPurple,
              ),
              const SizedBox(width: 8),
              _StatChip(
                icon: Icons.high_quality,
                label:
                    '${transients.where((e) => e.typeId == 0x03FD).length} HF',
                color: Colors.teal,
              ),
              const SizedBox(width: 8),
              _StatChip(
                icon: Icons.info_outline,
                label:
                    '${transients.where((e) => e.typeId == 0x03F2).length} Algemeen',
                color: Colors.blueGrey,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Timeline chart
          _TransientTimeline(
              transients: transients, session: session, theme: theme),
          const SizedBox(height: 12),

          // List
          Expanded(
            child: _TransientList(transients: transients, session: session),
          ),
        ],
      ),
    );
  }
}

// ── Stat chip ─────────────────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StatChip(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontSize: 12, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ── Timeline bar chart ────────────────────────────────────────────────────────

class _TransientTimeline extends StatelessWidget {
  final List<PqfEvent> transients;
  final MeasurementSession session;
  final ThemeData theme;

  const _TransientTimeline(
      {required this.transients,
      required this.session,
      required this.theme});

  @override
  Widget build(BuildContext context) {
    // Bucket transients into ~20 time bins
    final start = session.startTime;
    final end = session.endTime;
    final totalMs = end.difference(start).inMilliseconds;
    if (totalMs <= 0) return const SizedBox.shrink();

    const bins = 24;
    final binMs = totalMs / bins;
    final counts = List.filled(bins, 0);
    final hfCounts = List.filled(bins, 0);

    for (final t in transients) {
      final ms = t.time.difference(start).inMilliseconds;
      final bin = (ms / binMs).floor().clamp(0, bins - 1);
      counts[bin]++;
      if (t.typeId == 0x03FD) hfCounts[bin]++;
    }

    final maxCount = counts.reduce((a, b) => a > b ? a : b);

    // X-axis label formatter
    final dateFmt = DateFormat('d/M HH:mm');

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Verdeling over de meetperiode',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: Colors.white54)),
            const SizedBox(height: 8),
            SizedBox(
              height: 140,
              child: BarChart(
                BarChartData(
                  maxY: (maxCount + 1).toDouble(),
                  minY: 0,
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) => Colors.black87,
                      getTooltipItem: (group, _, rod, r) {
                        final binStart = start
                            .add(Duration(milliseconds: (group.x * binMs).round()));
                        return BarTooltipItem(
                          '${dateFmt.format(binStart.toLocal())}\n'
                          '${counts[group.x]} transiënt(en)',
                          const TextStyle(fontSize: 10, color: Colors.white),
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        interval: (maxCount / 4).ceilToDouble().clamp(1, double.infinity),
                        getTitlesWidget: (v, meta) => SideTitleWidget(
                          meta: meta,
                          child: Text(v.toInt().toString(),
                              style: const TextStyle(
                                  fontSize: 9, color: Colors.white54)),
                        ),
                      ),
                    ),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        interval: (bins / 4).ceilToDouble(),
                        getTitlesWidget: (v, meta) {
                          if (v == meta.min || v == meta.max) {
                            return const SizedBox.shrink();
                          }
                          final binStart = start.add(Duration(
                              milliseconds: (v * binMs).round()));
                          return SideTitleWidget(
                            meta: meta,
                            child: Text(
                              dateFmt.format(binStart.toLocal()),
                              style: const TextStyle(
                                  fontSize: 8, color: Colors.white54),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  gridData: FlGridData(
                    show: true,
                    getDrawingHorizontalLine: (_) => const FlLine(
                        color: Colors.white10, strokeWidth: 1),
                    drawVerticalLine: false,
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: List.generate(bins, (i) {
                    final total = counts[i].toDouble();
                    final hf = hfCounts[i].toDouble();
                    final general = total - hf;
                    return BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: total,
                          width: 10,
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(2)),
                          rodStackItems: [
                            BarChartRodStackItem(0, general, Colors.blueGrey),
                            BarChartRodStackItem(general, total, Colors.teal),
                          ],
                        ),
                      ],
                    );
                  }),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                _dot(Colors.teal, 'HF-transiënt'),
                const SizedBox(width: 12),
                _dot(Colors.blueGrey, 'Algemeen'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _dot(Color color, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(fontSize: 10, color: Colors.white54)),
        ],
      );
}

// ── Scrollable list ───────────────────────────────────────────────────────────

class _TransientList extends StatelessWidget {
  final List<PqfEvent> transients;
  final MeasurementSession session;

  const _TransientList(
      {required this.transients, required this.session});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFmt = DateFormat('dd MMM yyyy HH:mm:ss');

    return Card(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(
                theme.colorScheme.surfaceContainerHighest),
            columns: const [
              DataColumn(label: Text('#')),
              DataColumn(label: Text('Tijdstip (lokaal)')),
              DataColumn(label: Text('Type')),
              DataColumn(label: Text('Omschrijving')),
            ],
            rows: transients.asMap().entries.map((entry) {
              final idx = entry.key;
              final event = entry.value;
              final isHf = event.typeId == 0x03FD;
              final color = isHf ? Colors.teal : Colors.blueGrey;

              return DataRow(
                color: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.hovered)) {
                    return theme.colorScheme.primary.withValues(alpha: 0.08);
                  }
                  if (idx.isOdd) {
                    return theme.colorScheme.surfaceContainerLow
                        .withValues(alpha: 0.4);
                  }
                  return null;
                }),
                onSelectChanged: (_) => _showDetail(
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
                        border:
                            Border.all(color: color.withValues(alpha: 0.6)),
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
                  DataCell(Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(isHf ? Icons.bolt : Icons.info_outline,
                          size: 14, color: color),
                      const SizedBox(width: 6),
                      Text(event.eventName),
                    ],
                  )),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  void _showDetail(BuildContext context, int nr, PqfEvent event,
      MeasurementSession session, DateFormat dateFmt) {
    // Reuse the detail dialog from EventsScreen via the static helper
    _TransientDetail.show(context, nr, event, session, dateFmt);
  }
}

// ── Detail popup (reuses logic from EventsScreen) ────────────────────────────

class _TransientDetail {
  static void show(BuildContext context, int nr, PqfEvent event,
      MeasurementSession session, DateFormat dateFmt) {
    final color = event.typeId == 0x03FD ? Colors.teal : Colors.blueGrey;

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
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(event.typeId == 0x03FD ? Icons.bolt : Icons.info,
                        color: color, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Transiënt #$nr — ${event.eventName}',
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
                        _section('Details', [
                          _row('Tijdstip (lokaal)',
                              dateFmt.format(event.time.toLocal())),
                          _row('Tijdstip (UTC)',
                              dateFmt.format(event.time)),
                          _row('Type ID',
                              '0x${event.typeId.toRadixString(16).padLeft(4, '0').toUpperCase()}'),
                          _row('Type', event.eventName),
                        ]),
                        if (voltWindow.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          _section('Spanning rondom transiënt', []),
                          const SizedBox(height: 6),
                          _MiniChart(
                            window: voltWindow,
                            eventTime: event.time,
                            keys: const ['V_L1', 'V_L2', 'V_L3'],
                            colors: const [
                              Colors.red,
                              Colors.amber,
                              Colors.blue
                            ],
                            unit: 'V',
                            markerColor: color,
                          ),
                        ],
                        if (currWindow.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          _section('Stroom rondom transiënt', []),
                          const SizedBox(height: 6),
                          _MiniChart(
                            window: currWindow,
                            eventTime: event.time,
                            keys: const [
                              'I_L1',
                              'I_L2',
                              'I_L3',
                              'I_N'
                            ],
                            colors: const [
                              Colors.red,
                              Colors.amber,
                              Colors.blue,
                              Colors.grey
                            ],
                            unit: 'A',
                            markerColor: color,
                          ),
                        ],
                        if (voltSample != null) ...[
                          const SizedBox(height: 16),
                          _section(
                            'Spanning op tijdstip transiënt '
                            '(Δ ${_deltaStr(voltSample.time, event.time)})',
                            [
                              for (final e in voltSample.values.entries
                                  .where((e) => e.key.startsWith('V_')))
                                _row(e.key,
                                    '${e.value.toStringAsFixed(1)} V'),
                            ],
                          ),
                        ],
                        if (currSample != null) ...[
                          const SizedBox(height: 12),
                          _section(
                            'Stroom op tijdstip transiënt '
                            '(Δ ${_deltaStr(currSample.time, event.time)})',
                            [
                              for (final e in currSample.values.entries
                                  .where((e) => e.key.startsWith('I_')))
                                _row(e.key,
                                    '${e.value.toStringAsFixed(2)} A'),
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

  static List<MeasurementPoint> _windowAround(
      List<MeasurementPoint> data, DateTime target, int half) {
    if (data.isEmpty) return [];
    int idx = 0;
    int best = (data.first.time.millisecondsSinceEpoch -
            target.millisecondsSinceEpoch)
        .abs();
    for (int i = 1; i < data.length; i++) {
      final d = (data[i].time.millisecondsSinceEpoch -
              target.millisecondsSinceEpoch)
          .abs();
      if (d < best) {
        best = d;
        idx = i;
      }
    }
    final from = (idx - half).clamp(0, data.length - 1);
    final to = (idx + half).clamp(0, data.length - 1);
    return data.sublist(from, to + 1);
  }

  static MeasurementPoint? _closest(
      List<MeasurementPoint> data, DateTime target) {
    if (data.isEmpty) return null;
    MeasurementPoint best = data.first;
    int bestD = (best.time.millisecondsSinceEpoch -
            target.millisecondsSinceEpoch)
        .abs();
    for (final p in data) {
      final d = (p.time.millisecondsSinceEpoch -
              target.millisecondsSinceEpoch)
          .abs();
      if (d < bestD) {
        bestD = d;
        best = p;
      }
    }
    return best;
  }

  static String _deltaStr(DateTime a, DateTime b) {
    final ms = (a.millisecondsSinceEpoch - b.millisecondsSinceEpoch).abs();
    return ms < 1000 ? '${ms}ms' : '${(ms / 1000).toStringAsFixed(0)}s';
  }

  static Widget _section(String title, List<Widget> rows) => Column(
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

  static Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(
              width: 160,
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 12, color: Colors.white70)),
            ),
            Expanded(
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 12, fontFamily: 'monospace')),
            ),
          ],
        ),
      );
}

// ── Mini line chart ───────────────────────────────────────────────────────────

class _MiniChart extends StatelessWidget {
  final List<MeasurementPoint> window;
  final DateTime eventTime;
  final List<String> keys;
  final List<Color> colors;
  final String unit;
  final Color markerColor;

  const _MiniChart({
    required this.window,
    required this.eventTime,
    required this.keys,
    required this.colors,
    required this.unit,
    required this.markerColor,
  });

  @override
  Widget build(BuildContext context) {
    final eventX = eventTime.millisecondsSinceEpoch.toDouble();
    final minX = window.first.time.millisecondsSinceEpoch.toDouble();
    final maxX = window.last.time.millisecondsSinceEpoch.toDouble();
    final timeFmt = DateFormat('HH:mm');

    final bars = <LineChartBarData>[];
    double minY = double.infinity;
    double maxY = double.negativeInfinity;

    for (int i = 0; i < keys.length; i++) {
      final spots = window
          .where((p) => p.values.containsKey(keys[i]))
          .map((p) => FlSpot(
                p.time.millisecondsSinceEpoch.toDouble(),
                p.values[keys[i]]!,
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

    final yPad = ((maxY - minY) * 0.1).clamp(1.0, double.infinity);
    minY = (minY - yPad).floorToDouble();
    maxY = (maxY + yPad).ceilToDouble();

    return SizedBox(
      height: 180,
      child: LineChart(
        LineChartData(
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
          borderData: FlBorderData(
              show: true,
              border: Border.all(color: Colors.white24, width: 0.5)),
          extraLinesData: ExtraLinesData(verticalLines: [
            VerticalLine(
              x: eventX,
              color: markerColor,
              strokeWidth: 1.5,
              dashArray: [6, 4],
              label: VerticalLineLabel(
                show: true,
                labelResolver: (_) => 'transiënt',
                style: TextStyle(fontSize: 9, color: markerColor),
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
                      style: const TextStyle(
                          fontSize: 9, color: Colors.white54)),
                ),
              ),
            ),
            rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
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
                              v.toInt(), isUtc: true)
                          .toLocal()),
                      style: const TextStyle(
                          fontSize: 9, color: Colors.white54),
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
                  TextStyle(
                      color: colors[idx % colors.length], fontSize: 10),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }
}
