import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/measurement_data.dart';
import '../models/pqf_record.dart';
import '../providers/measurement_provider.dart';
import '../widgets/chart_wrapper.dart';
import '../widgets/time_range_selector.dart';

enum _CurrentView { avg, max, min }

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

  static String _labelFor(_CurrentView v) => switch (v) {
        _CurrentView.avg => 'gemiddeld',
        _CurrentView.max => 'piek',
        _CurrentView.min => 'minimum',
      };

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

    // Check whether max/min sub-records are available (FPQO only)
    final hasMaxMin = rawData.any((p) => p.values.containsKey('I_L1_max'));

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
    // (view, suffix, lijnbreedte, opaciteit)
    const viewStyle = [
      (_CurrentView.avg, '',     1.5, 1.0),
      (_CurrentView.max, '_max', 2.0, 0.85),
      (_CurrentView.min, '_min', 1.0, 0.5),
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
      for (final (view, suffix, width, opacity) in viewStyle) {
        if (!_activeViews.contains(view)) continue;
        final spots = spotsFor(phase, suffix);
        if (spots.isEmpty) continue;
        final color = baseColor.withValues(alpha: opacity);
        seriesMeta.add((phase, view, color));
        lineBarsData.add(LineChartBarData(
          spots: spots,
          isCurved: false,
          color: color,
          barWidth: width,
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
              '$phase ${_labelFor(view)}: ${s.y.toStringAsFixed(2)} A',
              TextStyle(color: color, fontSize: 11),
            );
          }).toList(),
        ),
      ),
    );

    final viewLabels = _activeViews
        .map(_labelFor)
        .join(' + ');

    return Column(
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
              FilterChip(
                label: const Text('Gemiddeld'),
                selected: _activeViews.contains(_CurrentView.avg),
                onSelected: (on) => setState(() {
                  if (on) {
                    _activeViews.add(_CurrentView.avg);
                  } else if (_activeViews.length > 1) {
                    _activeViews.remove(_CurrentView.avg);
                  }
                }),
              ),
              FilterChip(
                label: const Text('Piek'),
                selected: _activeViews.contains(_CurrentView.max),
                onSelected: hasMaxMin
                    ? (on) => setState(() {
                          if (on) {
                            _activeViews.add(_CurrentView.max);
                          } else if (_activeViews.length > 1) {
                            _activeViews.remove(_CurrentView.max);
                          }
                        })
                    : null,
              ),
              FilterChip(
                label: const Text('Minimum'),
                selected: _activeViews.contains(_CurrentView.min),
                onSelected: hasMaxMin
                    ? (on) => setState(() {
                          if (on) {
                            _activeViews.add(_CurrentView.min);
                          } else if (_activeViews.length > 1) {
                            _activeViews.remove(_CurrentView.min);
                          }
                        })
                    : null,
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
                    ? '$phase ${_labelFor(view)}'
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
            hasMaxMin: hasMaxMin,
            onClose: () => setState(() => _showExtraChart = false),
          ),
      ],
    );
  }
}

// ── Extra grafiek ─────────────────────────────────────────────────────────────

class _ExtraCurrentChart extends StatefulWidget {
  const _ExtraCurrentChart({
    required this.rawData,
    required this.totalMinMs,
    required this.totalMaxMs,
    required this.hasMaxMin,
    required this.onClose,
  });

  final List<MeasurementPoint> rawData;
  final double totalMinMs;
  final double totalMaxMs;
  final bool hasMaxMin;
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

  static String _labelFor(_CurrentView v) => switch (v) {
        _CurrentView.avg => 'gemiddeld',
        _CurrentView.max => 'piek',
        _CurrentView.min => 'minimum',
      };

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
    const viewStyle = [
      (_CurrentView.avg, '',     1.5, 1.0),
      (_CurrentView.max, '_max', 2.0, 0.85),
      (_CurrentView.min, '_min', 1.0, 0.5),
    ];

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
      for (final (view, suffix, width, opacity) in viewStyle) {
        if (!_activeViews.contains(view)) continue;
        final spots = spotsFor(phase, suffix);
        if (spots.isEmpty) continue;
        final color = baseColor.withValues(alpha: opacity);
        seriesMeta.add((phase, view, color));
        lineBarsData.add(LineChartBarData(
          spots: spots,
          isCurved: false,
          color: color,
          barWidth: width,
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
              '$phase ${_labelFor(view)}: ${s.y.toStringAsFixed(2)} A',
              TextStyle(color: color, fontSize: 11),
            );
          }).toList(),
        ),
      ),
    );

    final chartTitle = _title ?? 'Grafiek 2';
    final viewLabels = _activeViews.map(_labelFor).join(' + ');

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
              FilterChip(
                label: const Text('Gemiddeld'),
                selected: _activeViews.contains(_CurrentView.avg),
                onSelected: (on) => setState(() {
                  if (on) {
                    _activeViews.add(_CurrentView.avg);
                  } else if (_activeViews.length > 1) {
                    _activeViews.remove(_CurrentView.avg);
                  }
                }),
              ),
              FilterChip(
                label: const Text('Piek'),
                selected: _activeViews.contains(_CurrentView.max),
                onSelected: widget.hasMaxMin
                    ? (on) => setState(() {
                          if (on) {
                            _activeViews.add(_CurrentView.max);
                          } else if (_activeViews.length > 1) {
                            _activeViews.remove(_CurrentView.max);
                          }
                        })
                    : null,
              ),
              FilterChip(
                label: const Text('Minimum'),
                selected: _activeViews.contains(_CurrentView.min),
                onSelected: widget.hasMaxMin
                    ? (on) => setState(() {
                          if (on) {
                            _activeViews.add(_CurrentView.min);
                          } else if (_activeViews.length > 1) {
                            _activeViews.remove(_CurrentView.min);
                          }
                        })
                    : null,
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
                    ? '$phase ${_labelFor(view)}'
                    : phase,
                color: color,
              ),
          ],
        ),
      ],
    );
  }
}
