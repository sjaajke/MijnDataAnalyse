import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/measurement_data.dart';
import '../models/pqf_record.dart';
import '../providers/measurement_provider.dart';
import '../services/capacity_pdf.dart' show ChartPoint;
import '../services/opname_pdf.dart';
import '../widgets/chart_wrapper.dart';
import '../widgets/time_range_selector.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Main screen
// ─────────────────────────────────────────────────────────────────────────────

class OpnameScreen extends StatefulWidget {
  const OpnameScreen({super.key});

  @override
  State<OpnameScreen> createState() => _OpnameScreenState();
}

class _OpnameScreenState extends State<OpnameScreen> {
  /// Index into harmonicCurrentData for the detail snapshot panel
  int _snapIndex = 0;

  MeasurementSession? _lastSession;
  double _filterMinMs = 0;
  double _filterMaxMs = double.infinity;

  bool _showThd = true;
  bool _showCosPhi = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = context.read<MeasurementProvider>().session;
    if (session != _lastSession) {
      _lastSession = session;
      _resetFilter(session);
    }
  }

  void _resetFilter(MeasurementSession? session) {
    if (session == null) return;
    final (xMin, xMax) = _xRange(session);
    setState(() {
      _filterMinMs = xMin;
      _filterMaxMs = xMax;
    });
  }

  Future<void> _exportPdf(BuildContext context) async {
    final session = _lastSession;
    if (session == null) return;

    final (totalMin, totalMax) = _xRange(session);
    final fMin = _filterMinMs.clamp(totalMin, totalMax);
    final fMax = _filterMaxMs.clamp(totalMin, totalMax);

    bool inRange(DateTime t) {
      final ms = t.millisecondsSinceEpoch.toDouble();
      return ms >= fMin && ms <= fMax;
    }

    final currentFiltered =
        session.currentData.where((p) => inRange(p.time)).toList();
    final harmonicsFiltered =
        session.harmonicCurrentData.where((p) => inRange(p.time)).toList();
    final cosPhiFiltered =
        session.cosPhiData.where((p) => inRange(p.time)).toList();

    final periodStart =
        DateTime.fromMillisecondsSinceEpoch(fMin.toInt(), isUtc: true);
    final periodEnd =
        DateTime.fromMillisecondsSinceEpoch(fMax.toInt(), isUtc: true);
    final t0 = fMin;

    // ── Chart series (sampled, x = uren na start) ──
    final step =
        (currentFiltered.length / 300).ceil().clamp(1, max(currentFiltered.length, 1)) as int;
    final sampledCurrent = [
      for (int i = 0; i < currentFiltered.length; i += step) currentFiltered[i]
    ];

    Map<String, List<ChartPoint>> toSeries(
            List<MeasurementPoint> pts, List<String> keys) =>
        {
          for (final k in keys)
            k.split('_').last: pts // 'I_L1' -> 'L1'
                .where((p) => p.values.containsKey(k))
                .map((p) => ChartPoint(
                      (p.time.millisecondsSinceEpoch - t0) / 3600000.0,
                      p.values[k]!,
                    ))
                .toList(),
        };

    final currentSeries =
        toSeries(sampledCurrent, ['I_L1', 'I_L2', 'I_L3', 'I_N']);

    // THD series: berekend uit harmonischen + dichtstbijzijnde stroom
    double thd(List<double> h, double fund) {
      if (fund <= 0) return 0;
      return 100.0 * sqrt(h.fold<double>(0, (s, v) => s + v * v)) / fund;
    }

    MeasurementPoint? nearestCurrent(DateTime t) {
      if (currentFiltered.isEmpty) return null;
      return currentFiltered.reduce((a, b) =>
          a.time.difference(t).inSeconds.abs() <
                  b.time.difference(t).inSeconds.abs()
              ? a
              : b);
    }

    final hStep =
        (harmonicsFiltered.length / 300).ceil().clamp(1, max(harmonicsFiltered.length, 1)) as int;
    final sampledHarmonics = [
      for (int i = 0; i < harmonicsFiltered.length; i += hStep)
        harmonicsFiltered[i]
    ];

    final thdSeries = <String, List<ChartPoint>>{
      'L1': [],
      'L2': [],
      'L3': [],
    };
    for (final h in sampledHarmonics) {
      final x = (h.time.millisecondsSinceEpoch - t0) / 3600000.0;
      final c = nearestCurrent(h.time);
      thdSeries['L1']!.add(ChartPoint(x, thd(h.l1, c?.values['I_L1'] ?? 1)));
      thdSeries['L2']!.add(ChartPoint(x, thd(h.l2, c?.values['I_L2'] ?? 1)));
      thdSeries['L3']!.add(ChartPoint(x, thd(h.l3, c?.values['I_L3'] ?? 1)));
    }

    // Cos φ series
    final cStep =
        (cosPhiFiltered.length / 300).ceil().clamp(1, max(cosPhiFiltered.length, 1)) as int;
    final cosPhiSeries = <String, List<ChartPoint>>{
      'L1': [
        for (int i = 0; i < cosPhiFiltered.length; i += cStep)
          ChartPoint(
              (cosPhiFiltered[i].time.millisecondsSinceEpoch - t0) / 3600000.0,
              cosPhiFiltered[i].l1.abs())
      ],
      'L2': [
        for (int i = 0; i < cosPhiFiltered.length; i += cStep)
          ChartPoint(
              (cosPhiFiltered[i].time.millisecondsSinceEpoch - t0) / 3600000.0,
              cosPhiFiltered[i].l2.abs())
      ],
      'L3': [
        for (int i = 0; i < cosPhiFiltered.length; i += cStep)
          ChartPoint(
              (cosPhiFiltered[i].time.millisecondsSinceEpoch - t0) / 3600000.0,
              cosPhiFiltered[i].l3.abs())
      ],
    };

    // ── Snapshot ──
    final snapIdx = _snapIndex.clamp(0, max(harmonicsFiltered.length - 1, 0)) as int;
    OpnameSnapshotData snapshotData;
    if (harmonicsFiltered.isNotEmpty) {
      final snap = harmonicsFiltered[snapIdx];
      final c = nearestCurrent(snap.time);
      final cp = cosPhiFiltered.isEmpty
          ? null
          : cosPhiFiltered.reduce((a, b) =>
              a.time.difference(snap.time).inSeconds.abs() <
                      b.time.difference(snap.time).inSeconds.abs()
                  ? a
                  : b);
      final iL1 = c?.values['I_L1'] ?? 0;
      final iL2 = c?.values['I_L2'] ?? 0;
      final iL3 = c?.values['I_L3'] ?? 0;
      snapshotData = OpnameSnapshotData(
        time: snap.time,
        iL1: iL1, iL2: iL2, iL3: iL3,
        iN: c?.values['I_N'] ?? 0,
        thdL1: thd(snap.l1, iL1),
        thdL2: thd(snap.l2, iL2),
        thdL3: thd(snap.l3, iL3),
        cL1: cp?.l1 ?? 0, cL2: cp?.l2 ?? 0, cL3: cp?.l3 ?? 0,
        l1: snap.l1, l2: snap.l2, l3: snap.l3,
      );
    } else {
      snapshotData = OpnameSnapshotData(
        time: periodStart,
        iL1: 0, iL2: 0, iL3: 0, iN: 0,
        thdL1: 0, thdL2: 0, thdL3: 0,
        cL1: 0, cL2: 0, cL3: 0,
        l1: [], l2: [], l3: [],
      );
    }

    await exportOpnamePdf(
      context: context,
      deviceId: session.deviceId,
      periodStart: periodStart,
      periodEnd: periodEnd,
      currentSeries: currentSeries,
      thdSeries: thdSeries,
      cosPhiSeries: cosPhiSeries,
      snapshot: snapshotData,
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<MeasurementProvider>().session;

    if (session == null) {
      return const Center(child: Text('Open een meetmap om data te laden.'));
    }

    final hasCurrent = session.currentData.isNotEmpty;
    final hasHarmonics = session.harmonicCurrentData.isNotEmpty;
    final hasCosPhi = session.cosPhiData.isNotEmpty;

    if (!hasCurrent && !hasHarmonics && !hasCosPhi) {
      return const Center(child: Text('Geen meetdata beschikbaar.'));
    }

    // Total X range (for the slider)
    final (totalMin, totalMax) = _xRange(session);
    final fMin = _filterMinMs.clamp(totalMin, totalMax);
    final fMax = _filterMaxMs.clamp(totalMin, totalMax);

    // Filtered data
    bool inRange(DateTime t) {
      final ms = t.millisecondsSinceEpoch.toDouble();
      return ms >= fMin && ms <= fMax;
    }

    final currentFiltered =
        session.currentData.where((p) => inRange(p.time)).toList();
    final harmonicsFiltered =
        session.harmonicCurrentData.where((p) => inRange(p.time)).toList();
    final cosPhiFiltered =
        session.cosPhiData.where((p) => inRange(p.time)).toList();

    // Clamp snapshot index to filtered harmonics
    final snapMax =
        harmonicsFiltered.isEmpty ? 0 : harmonicsFiltered.length - 1;
    if (_snapIndex > snapMax) _snapIndex = snapMax;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header info bar + PDF-knop ───────────────────────────────────
          Row(
            children: [
              Expanded(child: _InfoBar(session: session)),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () => _exportPdf(context),
                icon: const Icon(Icons.picture_as_pdf, size: 18),
                label: const Text('PDF exporteren'),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // ── Grafiek-toggles ──────────────────────────────────────────────
          Wrap(
            spacing: 6,
            children: [
              if (hasHarmonics && hasCurrent)
                FilterChip(
                  label: const Text('THD stroom'),
                  selected: _showThd,
                  onSelected: (v) => setState(() => _showThd = v),
                ),
              if (hasCosPhi)
                FilterChip(
                  label: const Text('Vermogensfactor'),
                  selected: _showCosPhi,
                  onSelected: (v) => setState(() => _showCosPhi = v),
                ),
            ],
          ),

          // ── Time range selector ──────────────────────────────────────────
          TimeRangeSelector(
            totalMinMs: totalMin,
            totalMaxMs: totalMax,
            filterMinMs: fMin,
            filterMaxMs: fMax,
            onChanged: (s, e) => setState(() {
              _filterMinMs = s;
              _filterMaxMs = e;
            }),
            onReset: () => setState(() {
              _filterMinMs = totalMin;
              _filterMaxMs = totalMax;
            }),
          ),
          const SizedBox(height: 4),

          // ── Stroom ───────────────────────────────────────────────────────
          if (hasCurrent)
            _CurrentTimeSeriesChart(
              data: currentFiltered,
              xMin: fMin,
              xMax: fMax,
            ),

          // ── THD % per fase (afgeleid van harmonischen) ───────────────────
          if (hasHarmonics && hasCurrent && _showThd)
            _ThdTimeSeriesChart(
              harmonics: harmonicsFiltered,
              currents: currentFiltered,
              xMin: fMin,
              xMax: fMax,
            ),

          // ── Cos φ ─────────────────────────────────────────────────────────
          if (hasCosPhi && _showCosPhi)
            _CosPhiTimeSeriesChart(
              data: cosPhiFiltered,
              xMin: fMin,
              xMax: fMax,
            ),

          // ── Momentopname panel ────────────────────────────────────────────
          if (hasHarmonics && harmonicsFiltered.isNotEmpty)
            _SnapshotPanel(
              harmonics: harmonicsFiltered,
              currentData: currentFiltered,
              cosPhiData: cosPhiFiltered,
              snapIndex: _snapIndex,
              onIndexChanged: (i) => setState(() => _snapIndex = i),
            ),
        ],
      ),
    );
  }

  (double, double) _xRange(MeasurementSession s) {
    double xMin = double.infinity, xMax = double.negativeInfinity;
    void check(DateTime t) {
      final ms = t.millisecondsSinceEpoch.toDouble();
      if (ms < xMin) xMin = ms;
      if (ms > xMax) xMax = ms;
    }

    for (final p in s.currentData) { check(p.time); }
    for (final p in s.harmonicCurrentData) { check(p.time); }
    for (final p in s.cosPhiData) { check(p.time); }

    if (xMin == double.infinity) {
      xMin = DateTime.now().millisecondsSinceEpoch.toDouble();
      xMax = xMin + 1;
    }
    return (xMin, xMax);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Info bar
// ─────────────────────────────────────────────────────────────────────────────

class _InfoBar extends StatelessWidget {
  final MeasurementSession session;
  const _InfoBar({required this.session});

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('EEE d MMM yyyy  HH:mm');
    final dur = session.duration;
    final durStr = '${dur.inDays}d ${dur.inHours % 24}h ${dur.inMinutes % 60}m';

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.bolt,
                color: Theme.of(context).colorScheme.primary, size: 20),
            const SizedBox(width: 8),
            Text(session.deviceId,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(width: 16),
            const Icon(Icons.schedule, size: 16),
            const SizedBox(width: 4),
            Text(
              '${fmt.format(session.startTime.toLocal())}  →  '
              '${fmt.format(session.endTime.toLocal())}',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(width: 12),
            Chip(
              label: Text(durStr, style: const TextStyle(fontSize: 11)),
              padding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared helpers
// ─────────────────────────────────────────────────────────────────────────────

FlTitlesData _sharedTitles(double xMin, double xMax,
    {required String yLabel,
    required double Function(double) yFormatter,
    String Function(double)? yLabelFn}) {
  final span = xMax - xMin;
  return FlTitlesData(
    leftTitles: AxisTitles(
      axisNameWidget:
          Text(yLabel, style: const TextStyle(fontSize: 11)),
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 48,
        getTitlesWidget: (v, meta) => SideTitleWidget(
          meta: meta,
          child: Text(
            yLabelFn != null ? yLabelFn(v) : v.toStringAsFixed(1),
            style: const TextStyle(fontSize: 9),
          ),
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
        reservedSize: 36,
        interval: span / 6,
        getTitlesWidget: (v, meta) {
          if (v == meta.min || v == meta.max) return const SizedBox.shrink();
          return SideTitleWidget(
            meta: meta,
            child: Text(
              DateFormat('d/M\nHH:mm').format(
                  DateTime.fromMillisecondsSinceEpoch(v.toInt(), isUtc: true)
                      .toLocal()),
              style: const TextStyle(fontSize: 9),
              textAlign: TextAlign.center,
            ),
          );
        },
      ),
    ),
  );
}

LineTouchData _touchData(
    List<String> labels, List<Color> colors, String unit) {
  return LineTouchData(
    touchTooltipData: LineTouchTooltipData(
      getTooltipColor: (_) => Colors.black87,
      getTooltipItems: (spots) => spots.map((s) {
        final i = s.barIndex.clamp(0, labels.length - 1);
        return LineTooltipItem(
          '${labels[i]}: ${s.y.toStringAsFixed(3)} $unit',
          TextStyle(color: colors[i], fontSize: 11),
        );
      }).toList(),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// 1. Stroom tijdreeks
// ─────────────────────────────────────────────────────────────────────────────

class _CurrentTimeSeriesChart extends StatefulWidget {
  final List<MeasurementPoint> data;
  final double xMin, xMax;

  const _CurrentTimeSeriesChart({
    required this.data,
    required this.xMin,
    required this.xMax,
  });

  @override
  State<_CurrentTimeSeriesChart> createState() =>
      _CurrentTimeSeriesChartState();
}

class _CurrentTimeSeriesChartState extends State<_CurrentTimeSeriesChart> {
  final _visiblePhases = <String>{'L1', 'L2', 'L3', 'N'};
  bool _showAvg = false;
  bool _showPeak = false;
  bool _showMin = false;

  @override
  Widget build(BuildContext context) {
    const phaseConfig = [
      ('L1', Colors.red),
      ('L2', Colors.amber),
      ('L3', Colors.blue),
      ('N',  Colors.grey),
    ];

    List<FlSpot> spots(String key) => widget.data
        .where((p) => p.values.containsKey(key))
        .map((p) =>
            FlSpot(p.time.millisecondsSinceEpoch.toDouble(), p.values[key]!))
        .toList();

    // Per-fase statistieken berekenen
    final stats = <String, ({double avg, double peak, double min})>{};
    for (final (phase, _) in phaseConfig) {
      final vals = widget.data
          .map((p) => p.values['I_$phase'])
          .whereType<double>()
          .toList();
      if (vals.isEmpty) continue;
      stats[phase] = (
        avg: vals.reduce((a, b) => a + b) / vals.length,
        peak: vals.reduce((a, b) => a > b ? a : b),
        min: vals.reduce((a, b) => a < b ? a : b),
      );
    }

    final visibleConfig =
        phaseConfig.where((e) => _visiblePhases.contains(e.$1)).toList();

    // Referentielijnen
    final refLines = <HorizontalLine>[];
    for (final (phase, color) in visibleConfig) {
      final st = stats[phase];
      if (st == null) continue;
      if (_showAvg) {
        refLines.add(HorizontalLine(
          y: st.avg,
          color: color.withValues(alpha: 0.8),
          strokeWidth: 1.2,
          label: HorizontalLineLabel(
            show: true,
            labelResolver: (_) =>
                '$phase gem ${st.avg.toStringAsFixed(1)} A',
            style: TextStyle(fontSize: 9, color: color.withValues(alpha: 0.8)),
            alignment: Alignment.bottomLeft,
          ),
        ));
      }
      if (_showPeak) {
        refLines.add(HorizontalLine(
          y: st.peak,
          color: color,
          strokeWidth: 1.5,
          dashArray: [6, 3],
          label: HorizontalLineLabel(
            show: true,
            labelResolver: (_) =>
                '$phase piek ${st.peak.toStringAsFixed(1)} A',
            style: TextStyle(fontSize: 9, color: color),
            alignment: Alignment.topLeft,
          ),
        ));
      }
      if (_showMin) {
        refLines.add(HorizontalLine(
          y: st.min,
          color: color.withValues(alpha: 0.5),
          strokeWidth: 1.0,
          dashArray: [2, 4],
          label: HorizontalLineLabel(
            show: true,
            labelResolver: (_) =>
                '$phase min ${st.min.toStringAsFixed(1)} A',
            style: TextStyle(fontSize: 9, color: color.withValues(alpha: 0.6)),
            alignment: Alignment.bottomRight,
          ),
        ));
      }
    }

    // Lijn-series
    final seriesMeta = <(String, Color)>[];
    final lineBarsData = <LineChartBarData>[];
    for (final (phase, color) in visibleConfig) {
      final s = spots('I_$phase');
      if (s.isEmpty) continue;
      seriesMeta.add((phase, color));
      lineBarsData.add(_line(s, color));
    }

    double maxY = 0;
    for (final bar in lineBarsData) {
      for (final s in bar.spots) {
        if (s.y > maxY) maxY = s.y;
      }
    }

    final chartData = LineChartData(
      minX: widget.xMin,
      maxX: widget.xMax,
      minY: 0,
      maxY: maxY * 1.15,
      clipData: const FlClipData.all(),
      gridData: const FlGridData(show: true),
      borderData: FlBorderData(show: false),
      extraLinesData: ExtraLinesData(horizontalLines: refLines),
      titlesData: _sharedTitles(widget.xMin, widget.xMax,
          yLabel: 'A', yFormatter: (v) => v.roundToDouble()),
      lineBarsData: lineBarsData,
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => Colors.black87,
          getTooltipItems: (touchedSpots) => touchedSpots.map((s) {
            final idx = s.barIndex.clamp(0, seriesMeta.length - 1);
            final (phase, color) = seriesMeta[idx];
            return LineTooltipItem(
              '$phase: ${s.y.toStringAsFixed(3)} A',
              TextStyle(color: color, fontSize: 11),
            );
          }).toList(),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Toggles
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final (phase, color) in phaseConfig)
                FilterChip(
                  label: Text(phase),
                  selected: _visiblePhases.contains(phase),
                  selectedColor: color.withValues(alpha: 0.25),
                  checkmarkColor: color,
                  side: BorderSide(
                    color: _visiblePhases.contains(phase)
                        ? color
                        : Colors.grey.shade600,
                  ),
                  onSelected: (on) => setState(() {
                    if (on) {
                      _visiblePhases.add(phase);
                    } else if (_visiblePhases.length > 1) {
                      _visiblePhases.remove(phase);
                    }
                  }),
                ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('Gemiddeld'),
                selected: _showAvg,
                onSelected: (v) => setState(() => _showAvg = v),
              ),
              FilterChip(
                label: const Text('Piek'),
                selected: _showPeak,
                onSelected: (v) => setState(() => _showPeak = v),
              ),
              FilterChip(
                label: const Text('Minimum'),
                selected: _showMin,
                onSelected: (v) => setState(() => _showMin = v),
              ),
            ],
          ),
        ),
        ChartWrapper(
          title: 'Stroom (A) — 10-min gemiddelden',
          chartData: chartData,
          height: 280,
          legendItems: [
            for (final (phase, color) in seriesMeta)
              LegendItem(label: phase, color: color),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. THD % tijdreeks (afgeleid)
// ─────────────────────────────────────────────────────────────────────────────

class _ThdTimeSeriesChart extends StatelessWidget {
  final List<HarmonicPoint> harmonics;
  final List<MeasurementPoint> currents;
  final double xMin, xMax;

  const _ThdTimeSeriesChart({
    required this.harmonics,
    required this.currents,
    required this.xMin,
    required this.xMax,
  });

  double _thd(List<double> harmonics, double fundamental) {
    if (fundamental <= 0) return 0;
    final sumSq = harmonics.fold<double>(0, (s, v) => s + v * v);
    return 100.0 * sqrt(sumSq) / fundamental;
  }

  MeasurementPoint? _nearestCurrent(DateTime t) {
    if (currents.isEmpty) return null;
    return currents.reduce((a, b) =>
        (a.time.difference(t).inSeconds.abs() <
                b.time.difference(t).inSeconds.abs())
            ? a
            : b);
  }

  @override
  Widget build(BuildContext context) {
    final spotsL1 = <FlSpot>[];
    final spotsL2 = <FlSpot>[];
    final spotsL3 = <FlSpot>[];

    for (final h in harmonics) {
      final x = h.time.millisecondsSinceEpoch.toDouble();
      final c = _nearestCurrent(h.time);
      final iL1 = c?.values['I_L1'] ?? 1.0;
      final iL2 = c?.values['I_L2'] ?? 1.0;
      final iL3 = c?.values['I_L3'] ?? 1.0;
      spotsL1.add(FlSpot(x, _thd(h.l1, iL1)));
      spotsL2.add(FlSpot(x, _thd(h.l2, iL2)));
      spotsL3.add(FlSpot(x, _thd(h.l3, iL3)));
    }

    double maxY = 0;
    for (final s in [...spotsL1, ...spotsL2, ...spotsL3]) {
      if (s.y > maxY) maxY = s.y;
    }
    maxY = max(maxY * 1.2, 10.0);

    final chartData = LineChartData(
      minX: xMin,
      maxX: xMax,
      minY: 0,
      maxY: maxY,
      clipData: const FlClipData.all(),
      gridData: const FlGridData(show: true),
      borderData: FlBorderData(show: false),
      titlesData: _sharedTitles(xMin, xMax,
          yLabel: 'THD %', yFormatter: (v) => v.roundToDouble()),
      extraLinesData: ExtraLinesData(horizontalLines: [
        HorizontalLine(
          y: 8,
          color: Colors.orange.withValues(alpha: 0.7),
          strokeWidth: 1,
          dashArray: [6, 4],
          label: HorizontalLineLabel(
            show: true,
            labelResolver: (_) => '8 % grens',
            style:
                const TextStyle(fontSize: 10, color: Colors.orange),
            alignment: Alignment.topRight,
          ),
        ),
      ]),
      lineBarsData: [
        _line(spotsL1, Colors.red),
        _line(spotsL2, Colors.amber),
        _line(spotsL3, Colors.blue),
      ],
      lineTouchData: _touchData(
          ['THD L1', 'THD L2', 'THD L3'],
          [Colors.red, Colors.amber, Colors.blue],
          '%'),
    );

    return ChartWrapper(
      title: 'Totale harmonische vervorming stroom THD (%) — 10-min',
      chartData: chartData,
      height: 260,
      legendItems: const [
        LegendItem(label: 'L1', color: Colors.red),
        LegendItem(label: 'L2', color: Colors.amber),
        LegendItem(label: 'L3', color: Colors.blue),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. Cos φ tijdreeks
// ─────────────────────────────────────────────────────────────────────────────

class _CosPhiTimeSeriesChart extends StatelessWidget {
  final List<CosPhiPoint> data;
  final double xMin, xMax;

  const _CosPhiTimeSeriesChart({
    required this.data,
    required this.xMin,
    required this.xMax,
  });

  @override
  Widget build(BuildContext context) {
    final spotsL1 =
        data.map((p) => FlSpot(p.time.millisecondsSinceEpoch.toDouble(), p.l1.abs())).toList();
    final spotsL2 =
        data.map((p) => FlSpot(p.time.millisecondsSinceEpoch.toDouble(), p.l2.abs())).toList();
    final spotsL3 =
        data.map((p) => FlSpot(p.time.millisecondsSinceEpoch.toDouble(), p.l3.abs())).toList();

    final chartData = LineChartData(
      minX: xMin,
      maxX: xMax,
      minY: 0,
      maxY: 1.05,
      clipData: const FlClipData.all(),
      gridData: const FlGridData(show: true),
      borderData: FlBorderData(show: false),
      titlesData: _sharedTitles(xMin, xMax,
          yLabel: '|cos φ|', yFormatter: (v) => v),
      extraLinesData: ExtraLinesData(horizontalLines: [
        HorizontalLine(
          y: 0.85,
          color: Colors.green.withValues(alpha: 0.7),
          strokeWidth: 1,
          dashArray: [6, 4],
          label: HorizontalLineLabel(
            show: true,
            labelResolver: (_) => '0.85',
            style:
                const TextStyle(fontSize: 10, color: Colors.green),
            alignment: Alignment.bottomRight,
          ),
        ),
      ]),
      lineBarsData: [
        _line(spotsL1, Colors.red),
        _line(spotsL2, Colors.amber),
        _line(spotsL3, Colors.blue),
      ],
      lineTouchData: _touchData(
          ['|cos φ| L1', '|cos φ| L2', '|cos φ| L3'],
          [Colors.red, Colors.amber, Colors.blue],
          ''),
    );

    return ChartWrapper(
      title: '|cos φ| vermogensfactor — 10-min gemiddelden',
      chartData: chartData,
      height: 260,
      legendItems: const [
        LegendItem(label: 'L1', color: Colors.red),
        LegendItem(label: 'L2', color: Colors.amber),
        LegendItem(label: 'L3', color: Colors.blue),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 4. Momentopname — slider + waarden + harmonisch spectrum
// ─────────────────────────────────────────────────────────────────────────────

class _SnapshotPanel extends StatelessWidget {
  final List<HarmonicPoint> harmonics;
  final List<MeasurementPoint> currentData;
  final List<CosPhiPoint> cosPhiData;
  final int snapIndex;
  final ValueChanged<int> onIndexChanged;

  const _SnapshotPanel({
    required this.harmonics,
    required this.currentData,
    required this.cosPhiData,
    required this.snapIndex,
    required this.onIndexChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final snap = harmonics[snapIndex];

    // Nearest current and cos phi at this time
    MeasurementPoint? nearestCurrent;
    CosPhiPoint? nearestCosPhi;
    if (currentData.isNotEmpty) {
      nearestCurrent = currentData.reduce((a, b) =>
          a.time.difference(snap.time).inSeconds.abs() <
                  b.time.difference(snap.time).inSeconds.abs()
              ? a
              : b);
    }
    if (cosPhiData.isNotEmpty) {
      nearestCosPhi = cosPhiData.reduce((a, b) =>
          a.time.difference(snap.time).inSeconds.abs() <
                  b.time.difference(snap.time).inSeconds.abs()
              ? a
              : b);
    }

    double thd(List<double> h, double fund) {
      if (fund <= 0) return 0;
      return 100.0 * sqrt(h.fold<double>(0, (s, v) => s + v * v)) / fund;
    }

    final iL1 = nearestCurrent?.values['I_L1'] ?? 0;
    final iL2 = nearestCurrent?.values['I_L2'] ?? 0;
    final iL3 = nearestCurrent?.values['I_L3'] ?? 0;
    final iN = nearestCurrent?.values['I_N'] ?? 0;
    final thdL1 = thd(snap.l1, iL1);
    final thdL2 = thd(snap.l2, iL2);
    final thdL3 = thd(snap.l3, iL3);
    final cL1 = nearestCosPhi?.l1 ?? 0;
    final cL2 = nearestCosPhi?.l2 ?? 0;
    final cL3 = nearestCosPhi?.l3 ?? 0;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title + time slider
            Row(
              children: [
                Icon(Icons.camera_alt_outlined,
                    size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Momentopname',
                    style: theme.textTheme.titleLarge),
                const Spacer(),
                Text(
                  DateFormat('EEE d/M/yyyy  HH:mm')
                      .format(snap.time.toLocal()),
                  style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.primary),
                ),
              ],
            ),
            Slider(
              value: snapIndex.toDouble(),
              min: 0,
              max: (harmonics.length - 1).toDouble(),
              divisions: harmonics.length - 1,
              onChanged: (v) => onIndexChanged(v.round()),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                    DateFormat('d/M HH:mm')
                        .format(harmonics.first.time.toLocal()),
                    style: theme.textTheme.bodySmall),
                Text(
                    DateFormat('d/M HH:mm')
                        .format(harmonics.last.time.toLocal()),
                    style: theme.textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 16),

            // Value summary table
            _ValueTable(
              iL1: iL1, iL2: iL2, iL3: iL3, iN: iN,
              thdL1: thdL1, thdL2: thdL2, thdL3: thdL3,
              cL1: cL1, cL2: cL2, cL3: cL3,
            ),
            const SizedBox(height: 16),

            // Harmonic spectrum bar chart
            Text('Harmonisch spectrum (A)',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                _barLegend(Colors.red, 'L1'),
                const SizedBox(width: 16),
                _barLegend(Colors.amber, 'L2'),
                const SizedBox(width: 16),
                _barLegend(Colors.blue, 'L3'),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 320,
              child: _HarmonicSpectrumChart(
                snap: snap,
                fundL1: iL1,
                fundL2: iL2,
                fundL3: iL3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _barLegend(Color color, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 14, height: 14, color: color),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Value summary table
// ─────────────────────────────────────────────────────────────────────────────

class _ValueTable extends StatelessWidget {
  final double iL1, iL2, iL3, iN;
  final double thdL1, thdL2, thdL3;
  final double cL1, cL2, cL3;

  const _ValueTable({
    required this.iL1, required this.iL2, required this.iL3, required this.iN,
    required this.thdL1, required this.thdL2, required this.thdL3,
    required this.cL1, required this.cL2, required this.cL3,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final headerStyle = theme.textTheme.bodySmall
        ?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.primary);
    final valueStyle = theme.textTheme.bodyMedium;

    Widget cell(String text, {Color? color, FontWeight? weight}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Text(
            text,
            style: valueStyle?.copyWith(color: color, fontWeight: weight),
            textAlign: TextAlign.right,
          ),
        );

    String phiLabel(double v) {
      final abs = v.abs().toStringAsFixed(3);
      return v >= 0 ? '$abs (ind)' : '$abs (cap)';
    }

    return Table(
      columnWidths: const {
        0: FlexColumnWidth(2),
        1: FlexColumnWidth(2),
        2: FlexColumnWidth(2),
        3: FlexColumnWidth(2),
        4: FlexColumnWidth(2),
      },
      border: TableBorder(
        horizontalInside: BorderSide(color: theme.dividerColor, width: 0.5),
      ),
      children: [
        // Header row
        TableRow(
          decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest),
          children: [
            Padding(padding: const EdgeInsets.all(6),
                child: Text('Meting', style: headerStyle)),
            Padding(padding: const EdgeInsets.all(6),
                child: Text('L1', style: headerStyle, textAlign: TextAlign.right)),
            Padding(padding: const EdgeInsets.all(6),
                child: Text('L2', style: headerStyle, textAlign: TextAlign.right)),
            Padding(padding: const EdgeInsets.all(6),
                child: Text('L3', style: headerStyle, textAlign: TextAlign.right)),
            Padding(padding: const EdgeInsets.all(6),
                child: Text('N', style: headerStyle, textAlign: TextAlign.right)),
          ],
        ),
        // Current row
        TableRow(children: [
          Padding(padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              child: Text('I (A)', style: valueStyle?.copyWith(fontWeight: FontWeight.w500))),
          cell('${iL1.toStringAsFixed(2)} A', color: Colors.red),
          cell('${iL2.toStringAsFixed(2)} A', color: Colors.amber),
          cell('${iL3.toStringAsFixed(2)} A', color: Colors.blue),
          cell('${iN.toStringAsFixed(2)} A', color: Colors.grey),
        ]),
        // THD row
        TableRow(children: [
          Padding(padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              child: Text('THD I (%)', style: valueStyle?.copyWith(fontWeight: FontWeight.w500))),
          cell('${thdL1.toStringAsFixed(2)} %',
              color: thdL1 > 8 ? Colors.orange : Colors.green),
          cell('${thdL2.toStringAsFixed(2)} %',
              color: thdL2 > 8 ? Colors.orange : Colors.green),
          cell('${thdL3.toStringAsFixed(2)} %',
              color: thdL3 > 8 ? Colors.orange : Colors.green),
          cell('—'),
        ]),
        // Cos phi row
        TableRow(children: [
          Padding(padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              child: Text('cos φ', style: valueStyle?.copyWith(fontWeight: FontWeight.w500))),
          cell(phiLabel(cL1),
              color: cL1.abs() >= 0.85 ? Colors.green : Colors.orange),
          cell(phiLabel(cL2),
              color: cL2.abs() >= 0.85 ? Colors.green : Colors.orange),
          cell(phiLabel(cL3),
              color: cL3.abs() >= 0.85 ? Colors.green : Colors.orange),
          cell('—'),
        ]),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Harmonic spectrum bar chart for a single snapshot
// ─────────────────────────────────────────────────────────────────────────────

enum _HarmFilter { both, odd, even }

class _HarmonicSpectrumChart extends StatefulWidget {
  final HarmonicPoint snap;
  final double fundL1, fundL2, fundL3;

  const _HarmonicSpectrumChart({
    required this.snap,
    required this.fundL1,
    required this.fundL2,
    required this.fundL3,
  });

  @override
  State<_HarmonicSpectrumChart> createState() => _HarmonicSpectrumChartState();
}

class _HarmonicSpectrumChartState extends State<_HarmonicSpectrumChart> {
  int _maxOrder = 25;
  _HarmFilter _filter = _HarmFilter.both;
  bool _showH1 = false;

  @override
  Widget build(BuildContext context) {
    // Bepaal welke ordes getoond worden
    final orders = <int>[];
    for (int h = 1; h <= _maxOrder; h++) {
      if (h == 1 && !_showH1) continue;
      final isOdd = h % 2 != 0;
      if (_filter == _HarmFilter.odd && !isOdd) continue;
      if (_filter == _HarmFilter.even && isOdd) continue;
      orders.add(h);
    }

    // Bouw bar-groepen
    final groups = <BarChartGroupData>[];
    for (final h in orders) {
      double v1, v2, v3;
      if (h == 1) {
        v1 = widget.fundL1;
        v2 = widget.fundL2;
        v3 = widget.fundL3;
      } else {
        final idx = h - 2; // h2 = index 0
        if (idx >= widget.snap.l1.length) continue;
        v1 = widget.snap.l1[idx];
        v2 = widget.snap.l2[idx];
        v3 = widget.snap.l3[idx];
      }
      final barWidth = _maxOrder <= 10 ? 6.0 : _maxOrder <= 15 ? 4.5 : 3.0;
      groups.add(BarChartGroupData(
        x: h,
        barRods: [
          BarChartRodData(toY: v1, color: Colors.red,   width: barWidth, borderRadius: BorderRadius.zero),
          BarChartRodData(toY: v2, color: Colors.amber, width: barWidth, borderRadius: BorderRadius.zero),
          BarChartRodData(toY: v3, color: Colors.blue,  width: barWidth, borderRadius: BorderRadius.zero),
        ],
        barsSpace: 1,
      ));
    }

    final maxY = groups
        .expand((g) => g.barRods.map((r) => r.toY))
        .fold<double>(0.001, (a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Bedieningselementen
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            // Bereik
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 10,  label: Text('h1–10')),
                ButtonSegment(value: 15,  label: Text('h1–15')),
                ButtonSegment(value: 25,  label: Text('h1–25')),
              ],
              selected: {_maxOrder},
              onSelectionChanged: (v) => setState(() => _maxOrder = v.first),
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
            ),
            FilterChip(
              label: const Text('h1'),
              selected: _showH1,
              onSelected: (v) => setState(() => _showH1 = v),
            ),
            const SizedBox(width: 8),
            // Oneven / even / beide
            SegmentedButton<_HarmFilter>(
              segments: const [
                ButtonSegment(value: _HarmFilter.both, label: Text('Beide')),
                ButtonSegment(value: _HarmFilter.odd,  label: Text('Oneven')),
                ButtonSegment(value: _HarmFilter.even, label: Text('Even')),
              ],
              selected: {_filter},
              onSelectionChanged: (v) => setState(() => _filter = v.first),
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Grafiek
        Expanded(
          child: BarChart(
            BarChartData(
              barGroups: groups,
              maxY: maxY * 1.2,
              minY: 0,
              gridData: FlGridData(
                drawVerticalLine: false,
                horizontalInterval: maxY / 4,
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  axisNameWidget:
                      const Text('A', style: TextStyle(fontSize: 11)),
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 44,
                    getTitlesWidget: (v, meta) => SideTitleWidget(
                      meta: meta,
                      child: Text(v.toStringAsFixed(3),
                          style: const TextStyle(fontSize: 8)),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (v, meta) => SideTitleWidget(
                      meta: meta,
                      child: Text('h${v.toInt()}',
                          style: const TextStyle(fontSize: 9)),
                    ),
                  ),
                ),
                topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, _, rod, rodIndex) {
                    final phase = ['L1', 'L2', 'L3'][rodIndex];
                    return BarTooltipItem(
                      'h${group.x} $phase\n${rod.toY.toStringAsFixed(4)} A',
                      const TextStyle(fontSize: 11),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared line style
// ─────────────────────────────────────────────────────────────────────────────

LineChartBarData _line(List<FlSpot> spots, Color color) => LineChartBarData(
      spots: spots,
      color: color,
      barWidth: 1.8,
      dotData: const FlDotData(show: false),
      isCurved: true,
      curveSmoothness: 0.2,
    );
