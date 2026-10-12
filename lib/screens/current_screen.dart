import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/measurement_data.dart';
import '../models/pqf_record.dart';
import '../providers/measurement_provider.dart';
import '../widgets/chart_wrapper.dart';
import '../widgets/time_range_selector.dart';

enum _CurrentView { avg, maxSample, max, max200ms, min }

typedef _ViewSpec = ({
  _CurrentView view,
  String suffix,
  String label,
  double width,
  double opacity,
  List<int>? dash,
});

/// Weergaven per bron. Bij A-Eberle (PQ-Box, "PQ-Box Dateiformat" v1.5 /
/// structures.h) volgen de suffixen de velden uit MeasurementLoader en
/// PqBoxCsvParser:
///   ''          StructI (ID 104)             — I TRMS (intervalwaarde)
///   '_maxsp'    StructIExtrX1 (ID 148)       — hoogste 40/20 kHz-sample
///   '_max'      StructIExtr 10 ms (ID 105)   — I TRMS max
///   '_max200ms' StructIExtr 200 ms (ID 112)  — I eff max
///   '_min'      StructIExtr 10 ms (ID 105)   — I TRMS min
List<_ViewSpec> _viewSpecs(bool aEberle) => aEberle
    ? const [
        (view: _CurrentView.avg,       suffix: '',          label: 'I TRMS',               width: 1.5, opacity: 1.0,  dash: null),
        (view: _CurrentView.maxSample, suffix: '_maxsp',    label: 'I eff max (meetpunt)', width: 1.2, opacity: 0.6,  dash: [2, 3]),
        (view: _CurrentView.max,       suffix: '_max',      label: 'I TRMS max (10 ms)',   width: 2.0, opacity: 0.85, dash: null),
        (view: _CurrentView.max200ms,  suffix: '_max200ms', label: 'I eff max (200 ms)',   width: 1.5, opacity: 0.7,  dash: [6, 3]),
        (view: _CurrentView.min,       suffix: '_min',      label: 'I TRMS min (10 ms)',   width: 1.0, opacity: 0.5,  dash: null),
      ]
    : const [
        (view: _CurrentView.avg, suffix: '',     label: 'Gemiddeld', width: 1.5, opacity: 1.0,  dash: null),
        (view: _CurrentView.max, suffix: '_max', label: 'Piek',      width: 2.0, opacity: 0.85, dash: null),
        (view: _CurrentView.min, suffix: '_min', label: 'Minimum',   width: 1.0, opacity: 0.5,  dash: null),
      ];

/// A-Eberle-data herkennen aan de 200 ms- of samplewaarden, die alleen de
/// PQ-Box levert (zowel uit .pqf als uit de CSV-export).
bool _isAEberle(List<MeasurementPoint> data) => data.any((p) => p.values.keys
    .any((k) => k.endsWith('_max200ms') || k.endsWith('_maxsp')));

bool _hasSuffix(List<MeasurementPoint> data, String suffix) => data.any((p) =>
    const ['L1', 'L2', 'L3', 'N'].any((ph) => p.values.containsKey('I_$ph$suffix')));

String _labelFor(List<_ViewSpec> specs, _CurrentView view) =>
    specs.firstWhere((v) => v.view == view).label;

/// Chips om weergaven aan/uit te zetten; minstens één blijft actief.
List<Widget> _viewChips({
  required List<_ViewSpec> specs,
  required Set<_CurrentView> active,
  required Set<_CurrentView> available,
  required void Function(VoidCallback) setState,
}) => [
      for (final v in specs)
        FilterChip(
          label: Text(v.label),
          selected: active.contains(v.view),
          onSelected: available.contains(v.view)
              ? (on) => setState(() {
                    if (on) {
                      active.add(v.view);
                    } else if (active.length > 1) {
                      active.remove(v.view);
                    }
                  })
              : null,
        ),
    ];

class CurrentScreen extends StatefulWidget {
  const CurrentScreen({super.key});

  @override
  State<CurrentScreen> createState() => _CurrentScreenState();
}

class _CurrentScreenState extends State<CurrentScreen> {
  bool _use10s = false;
  final _activeViews = <_CurrentView>{_CurrentView.avg};
  final _visiblePhases = <String>{'L1', 'L2', 'L3', 'N'};
  MeasurementSession? _lastSession;
  double _filterMinMs = 0;
  double _filterMaxMs = double.infinity;
  String? _noteTitle;
  String? _noteText;
  bool _showExtraChart = false;

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
    final data = session?.currentData ?? [];
    if (data.isEmpty) return;
    setState(() {
      _filterMinMs = data.first.time.millisecondsSinceEpoch.toDouble();
      _filterMaxMs = data.last.time.millisecondsSinceEpoch.toDouble();
    });
  }

  List<MeasurementPoint> _filtered(List<MeasurementPoint> data) => data
      .where((p) =>
          p.time.millisecondsSinceEpoch >= _filterMinMs &&
          p.time.millisecondsSinceEpoch <= _filterMaxMs)
      .toList();

  Future<void> _openNoteDialog() async {
    final titleCtrl = TextEditingController(text: _noteTitle ?? '');
    final textCtrl = TextEditingController(text: _noteText ?? '');
    final result = await showDialog<({String title, String text})>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_noteTitle == null ? 'Aantekening toevoegen' : 'Aantekening bewerken'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Titel',
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: textCtrl,
                decoration: const InputDecoration(
                  labelText: 'Toelichting',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                minLines: 4,
                maxLines: 8,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuleren'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              ctx,
              (title: titleCtrl.text.trim(), text: textCtrl.text.trim()),
            ),
            child: const Text('Opslaan'),
          ),
        ],
      ),
    );
    if (result != null) {
      setState(() {
        _noteTitle = result.title.isEmpty ? null : result.title;
        _noteText = result.text.isEmpty ? null : result.text;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<MeasurementProvider>().session;

    if (session == null) {
      return ChartWrapper(
        title: 'Stroom (L1, L2, L3)',
        isEmpty: true,
        emptyMessage: 'No data loaded.',
        chartData: LineChartData(),
      );
    }

    final has10s = session.currentData10s.isNotEmpty;
    final rawData =
        (_use10s && has10s) ? session.currentData10s : session.currentData;
    final resolution = (_use10s && has10s) ? '10-sec' : '10-min';

    if (rawData.isEmpty) {
      return ChartWrapper(
        title: 'Stroom (L1, L2, L3)',
        isEmpty: true,
        emptyMessage: 'No current data found.',
        chartData: LineChartData(),
      );
    }

    // A-Eberle: vijf stroomgrootheden; overige bronnen: gem./piek/min.
    final aEberle = _isAEberle(rawData);
    final specs = _viewSpecs(aEberle);
    final available = {
      for (final v in specs)
        if (_hasSuffix(rawData, v.suffix)) v.view
    };
    // Weergaven die bij deze bron niet bestaan niet actief laten staan.
    _activeViews.retainWhere((v) => specs.any((s) => s.view == v));
    if (_activeViews.isEmpty) _activeViews.add(_CurrentView.avg);

    final totalMinMs = rawData.first.time.millisecondsSinceEpoch.toDouble();
    final totalMaxMs = rawData.last.time.millisecondsSinceEpoch.toDouble();
    final fMin = _filterMinMs.clamp(totalMinMs, totalMaxMs);
    final fMax = _filterMaxMs.clamp(totalMinMs, totalMaxMs);

    final data = _filtered(rawData);
    final step = (data.length / 500).ceil().clamp(1, data.length);
    final sampled = [for (int i = 0; i < data.length; i += step) data[i]];

    // Fase- en view-configuratie
    const phaseConfig = [
      ('L1', Colors.red),
      ('L2', Colors.amber),
      ('L3', Colors.blue),
      ('N',  Colors.grey),
    ];

    List<FlSpot> spotsFor(String phase, String suffix) => sampled
        .where((p) => p.values.containsKey('I_$phase$suffix'))
        .map((p) => FlSpot(
              p.time.millisecondsSinceEpoch.toDouble(),
              p.values['I_$phase$suffix']!,
            ))
        .toList();

    // Bouw series op voor zichtbare fasen × actieve views
    final seriesMeta = <(String, _CurrentView, Color)>[];
    final lineBarsData = <LineChartBarData>[];

    for (final (phase, baseColor) in phaseConfig) {
      if (!_visiblePhases.contains(phase)) continue;
      for (final v in specs) {
        if (!_activeViews.contains(v.view)) continue;
        final spots = spotsFor(phase, v.suffix);
        if (spots.isEmpty) continue;
        final color = baseColor.withValues(alpha: v.opacity);
        seriesMeta.add((phase, v.view, color));
        lineBarsData.add(LineChartBarData(
          spots: spots,
          isCurved: false,
          color: color,
          barWidth: v.width,
          dashArray: v.dash,
          dotData: const FlDotData(show: false),
        ));
      }
    }

    double maxVal = 0;
    for (final bar in lineBarsData) {
      for (final s in bar.spots) {
        if (s.y > maxVal) maxVal = s.y;
      }
    }
    final maxY = (maxVal * 1.1).ceilToDouble().clamp(10.0, double.infinity);

    final chartData = LineChartData(
      minY: 0,
      maxY: maxY,
      minX: fMin,
      maxX: fMax,
      clipData: const FlClipData.all(),
      gridData: FlGridData(
        show: true,
        drawHorizontalLine: true,
        getDrawingHorizontalLine: (_) =>
            const FlLine(color: Colors.white12, strokeWidth: 1, dashArray: [4, 4]),
      ),
      borderData: FlBorderData(show: true),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(
          axisNameWidget:
              const Text('Stroom (A)', style: TextStyle(fontSize: 11)),
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 48,
            getTitlesWidget: (value, meta) => SideTitleWidget(
              meta: meta,
              child: Text(value.toStringAsFixed(0),
                  style: const TextStyle(fontSize: 10)),
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
            interval: (fMax - fMin) / 6,
            getTitlesWidget: (value, meta) {
              if (value == meta.min || value == meta.max) {
                return const SizedBox.shrink();
              }
              return SideTitleWidget(
                meta: meta,
                child: Text(formatXAxisLabel(value),
                    style: const TextStyle(fontSize: 9)),
              );
            },
          ),
        ),
      ),
      lineBarsData: lineBarsData,
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => Colors.black87,
          getTooltipItems: (spots) => spots.map((s) {
            final idx = s.barIndex.clamp(0, seriesMeta.length - 1);
            final (phase, view, color) = seriesMeta[idx];
            return LineTooltipItem(
              '$phase ${_labelFor(specs, view)}: ${s.y.toStringAsFixed(2)} A',
              TextStyle(color: color, fontSize: 11),
            );
          }).toList(),
        ),
      ),
    );

    final viewLabels = specs
        .where((v) => _activeViews.contains(v.view))
        .map((v) => v.label)
        .join(' + ');

    return SingleChildScrollView(
      child: Column(
        children: [
          // Toolbar: aantekening + grafiek toevoegen + resolutie-toggle
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: _openNoteDialog,
                  icon: Icon(_noteTitle == null ? Icons.note_add_outlined : Icons.edit_note),
                  label: Text(_noteTitle == null ? 'Aantekening' : 'Bewerken'),
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _showExtraChart
                      ? null
                      : () => setState(() => _showExtraChart = true),
                  icon: const Icon(Icons.add_chart),
                  label: const Text('Grafiek toevoegen'),
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                ),
                const SizedBox(width: 12),
                SegmentedButton<bool>(
                  segments: [
                    const ButtonSegment(value: false, label: Text('10 min')),
                    ButtonSegment(
                      value: true,
                      label: const Text('10 sec'),
                      enabled: has10s,
                    ),
                  ],
                  selected: {_use10s},
                  onSelectionChanged: (val) =>
                      setState(() => _use10s = val.first),
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                ),
              ],
            ),
          ),

          // Fase- en view-toggles
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
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
                ..._viewChips(
                  specs: specs,
                  active: _activeViews,
                  available: available,
                  setState: setState,
                ),
              ],
            ),
          ),

          TimeRangeSelector(
            totalMinMs: totalMinMs,
            totalMaxMs: totalMaxMs,
            filterMinMs: fMin,
            filterMaxMs: fMax,
            onChanged: (s, e) => setState(() {
              _filterMinMs = s;
              _filterMaxMs = e;
            }),
            onReset: () => setState(() {
              _filterMinMs = totalMinMs;
              _filterMaxMs = totalMaxMs;
            }),
          ),
          ChartWrapper(
            title: 'Stroom ($resolution) — $viewLabels',
            chartData: chartData,
            height: 420,
            legendItems: [
              for (final (phase, view, color) in seriesMeta)
                LegendItem(
                  label: _activeViews.length > 1
                      ? '$phase ${_labelFor(specs, view)}'
                      : phase,
                  color: color,
                ),
            ],
          ),

          // Aantekening
          if (_noteTitle != null || _noteText != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.notes, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_noteTitle != null)
                            Text(_noteTitle!,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 13)),
                          if (_noteTitle != null && _noteText != null)
                            const SizedBox(height: 4),
                          if (_noteText != null)
                            Text(_noteText!,
                                style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Bewerken',
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      onPressed: _openNoteDialog,
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      tooltip: 'Verwijderen',
                      icon: const Icon(Icons.delete_outline, size: 18),
                      onPressed: () =>
                          setState(() { _noteTitle = null; _noteText = null; }),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),
            ),

          // Extra grafiek
          if (_showExtraChart)
            _ExtraCurrentChart(
              rawData: rawData,
              totalMinMs: totalMinMs,
              totalMaxMs: totalMaxMs,
              aEberle: aEberle,
              onClose: () => setState(() => _showExtraChart = false),
            ),
        ],
      ),
    );
  }
}

// ── Extra grafiek ─────────────────────────────────────────────────────────────

class _ExtraCurrentChart extends StatefulWidget {
  const _ExtraCurrentChart({
    required this.rawData,
    required this.totalMinMs,
    required this.totalMaxMs,
    required this.aEberle,
    required this.onClose,
  });

  final List<MeasurementPoint> rawData;
  final double totalMinMs;
  final double totalMaxMs;
  final bool aEberle;
  final VoidCallback onClose;

  @override
  State<_ExtraCurrentChart> createState() => _ExtraCurrentChartState();
}

class _ExtraCurrentChartState extends State<_ExtraCurrentChart> {
  late double _filterMinMs = widget.totalMinMs;
  late double _filterMaxMs = widget.totalMaxMs;
  final _activeViews = <_CurrentView>{_CurrentView.avg};
  final _visiblePhases = <String>{'L1', 'L2', 'L3', 'N'};
  String? _title;
  String? _description;


  Future<void> _openTitleDialog() async {
    final titleCtrl = TextEditingController(text: _title ?? '');
    final descCtrl = TextEditingController(text: _description ?? '');
    final result = await showDialog<({String title, String desc})>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Grafiek instellen'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Titel',
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                decoration: const InputDecoration(
                  labelText: 'Toelichting (optioneel)',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                minLines: 3,
                maxLines: 6,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuleren'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              ctx,
              (title: titleCtrl.text.trim(), desc: descCtrl.text.trim()),
            ),
            child: const Text('Opslaan'),
          ),
        ],
      ),
    );
    if (result != null) {
      setState(() {
        _title = result.title.isEmpty ? null : result.title;
        _description = result.desc.isEmpty ? null : result.desc;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const phaseConfig = [
      ('L1', Colors.red),
      ('L2', Colors.amber),
      ('L3', Colors.blue),
      ('N',  Colors.grey),
    ];
    final specs = _viewSpecs(widget.aEberle);
    final available = {
      for (final v in specs)
        if (_hasSuffix(widget.rawData, v.suffix)) v.view
    };
    _activeViews.retainWhere((v) => specs.any((s) => s.view == v));
    if (_activeViews.isEmpty) _activeViews.add(_CurrentView.avg);

    final fMin = _filterMinMs.clamp(widget.totalMinMs, widget.totalMaxMs);
    final fMax = _filterMaxMs.clamp(widget.totalMinMs, widget.totalMaxMs);

    final filtered = widget.rawData
        .where((p) =>
            p.time.millisecondsSinceEpoch >= fMin &&
            p.time.millisecondsSinceEpoch <= fMax)
        .toList();
    final step = (filtered.length / 500).ceil().clamp(1, filtered.length);
    final sampled = [for (int i = 0; i < filtered.length; i += step) filtered[i]];

    List<FlSpot> spotsFor(String phase, String suffix) => sampled
        .where((p) => p.values.containsKey('I_$phase$suffix'))
        .map((p) => FlSpot(
              p.time.millisecondsSinceEpoch.toDouble(),
              p.values['I_$phase$suffix']!,
            ))
        .toList();

    final seriesMeta = <(String, _CurrentView, Color)>[];
    final lineBarsData = <LineChartBarData>[];

    for (final (phase, baseColor) in phaseConfig) {
      if (!_visiblePhases.contains(phase)) continue;
      for (final v in specs) {
        if (!_activeViews.contains(v.view)) continue;
        final spots = spotsFor(phase, v.suffix);
        if (spots.isEmpty) continue;
        final color = baseColor.withValues(alpha: v.opacity);
        seriesMeta.add((phase, v.view, color));
        lineBarsData.add(LineChartBarData(
          spots: spots,
          isCurved: false,
          color: color,
          barWidth: v.width,
          dashArray: v.dash,
          dotData: const FlDotData(show: false),
        ));
      }
    }

    double maxVal = 0;
    for (final bar in lineBarsData) {
      for (final s in bar.spots) {
        if (s.y > maxVal) maxVal = s.y;
      }
    }
    final maxY = (maxVal * 1.1).ceilToDouble().clamp(10.0, double.infinity);

    final chartData = LineChartData(
      minY: 0,
      maxY: maxY,
      minX: fMin,
      maxX: fMax,
      clipData: const FlClipData.all(),
      gridData: FlGridData(
        show: true,
        drawHorizontalLine: true,
        getDrawingHorizontalLine: (_) =>
            const FlLine(color: Colors.white12, strokeWidth: 1, dashArray: [4, 4]),
      ),
      borderData: FlBorderData(show: true),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(
          axisNameWidget:
              const Text('Stroom (A)', style: TextStyle(fontSize: 11)),
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 48,
            getTitlesWidget: (value, meta) => SideTitleWidget(
              meta: meta,
              child: Text(value.toStringAsFixed(0),
                  style: const TextStyle(fontSize: 10)),
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
            interval: (fMax - fMin) / 6,
            getTitlesWidget: (value, meta) {
              if (value == meta.min || value == meta.max) {
                return const SizedBox.shrink();
              }
              return SideTitleWidget(
                meta: meta,
                child: Text(formatXAxisLabel(value),
                    style: const TextStyle(fontSize: 9)),
              );
            },
          ),
        ),
      ),
      lineBarsData: lineBarsData,
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => Colors.black87,
          getTooltipItems: (spots) => spots.map((s) {
            final idx = s.barIndex.clamp(0, seriesMeta.length - 1);
            final (phase, view, color) = seriesMeta[idx];
            return LineTooltipItem(
              '$phase ${_labelFor(specs, view)}: ${s.y.toStringAsFixed(2)} A',
              TextStyle(color: color, fontSize: 11),
            );
          }).toList(),
        ),
      ),
    );

    final chartTitle = _title ?? 'Grafiek 2';
    final viewLabels = specs
        .where((v) => _activeViews.contains(v.view))
        .map((v) => v.label)
        .join(' + ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Scheidingslijn
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Divider(color: Theme.of(context).dividerColor),
        ),

        // Toolbar extra grafiek
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(chartTitle,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14)),
                    if (_description != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(_description!,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey)),
                      ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: _openTitleDialog,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Instellen'),
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Grafiek verwijderen',
                icon: const Icon(Icons.close),
                onPressed: widget.onClose,
              ),
            ],
          ),
        ),

        // Fase- en view-toggles
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
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
              ..._viewChips(
                specs: specs,
                active: _activeViews,
                available: available,
                setState: setState,
              ),
            ],
          ),
        ),

        TimeRangeSelector(
          totalMinMs: widget.totalMinMs,
          totalMaxMs: widget.totalMaxMs,
          filterMinMs: fMin,
          filterMaxMs: fMax,
          onChanged: (s, e) => setState(() {
            _filterMinMs = s;
            _filterMaxMs = e;
          }),
          onReset: () => setState(() {
            _filterMinMs = widget.totalMinMs;
            _filterMaxMs = widget.totalMaxMs;
          }),
        ),

        ChartWrapper(
          title: '$chartTitle — $viewLabels',
          chartData: chartData,
          height: 380,
          legendItems: [
            for (final (phase, view, color) in seriesMeta)
              LegendItem(
                label: _activeViews.length > 1
                    ? '$phase ${_labelFor(specs, view)}'
                    : phase,
                color: color,
              ),
          ],
        ),
      ],
    );
  }
}
