import 'dart:io';

import 'package:fl_chart/fl_chart.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/measurement_data.dart';
import '../models/pqf_record.dart';
import '../models/standaard.dart';
import '../providers/measurement_provider.dart';
import '../providers/standaarden_provider.dart';
import '../services/capacity_pdf.dart'
    show
        exportCapacityPdf,
        PhaseReportData,
        ChartPoint,
        CapacityChartSection,
        CapacityNote,
        GeneralInfo;
import '../widgets/chart_wrapper.dart';
import '../widgets/time_range_selector.dart';

class CurrentCapacityScreen extends StatefulWidget {
  const CurrentCapacityScreen({super.key});

  @override
  State<CurrentCapacityScreen> createState() => _CurrentCapacityScreenState();
}

class _CurrentCapacityScreenState extends State<CurrentCapacityScreen> {
  final _ratedController = TextEditingController(text: '63');
  final _notes = List.generate(4, (_) => _NoteEntry());
  final _generalInfo = _GeneralInfoEntry();
  final _introTextController = TextEditingController();
  String? _introStandaardId;
  bool _introExpanded = false;
  double _ratedA = 63.0;
  MeasurementSession? _lastSession;
  double _filterMinMs = 0;
  double _filterMaxMs = double.infinity;

  /// Per grafiek (sleutel = "stroom"/"vermogen" + aggregatievariant, bv.
  /// "stroom_max" of "vermogen") of deze wordt meegenomen in de PDF-export.
  /// Standaard aan.
  final Map<String, bool> _chartIncludedInPdf = {};

  bool _isChartIncluded(String key) => _chartIncludedInPdf[key] ?? true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = context.read<MeasurementProvider>().session;
    if (session != _lastSession) {
      _lastSession = session;
      _resetFilter(session);
    }
  }

  @override
  void dispose() {
    _ratedController.dispose();
    for (final note in _notes) {
      note.titleController.dispose();
      note.textController.dispose();
    }
    _generalInfo.dispose();
    _introTextController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(int index) async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    final path = result?.files.single.path;
    if (path != null) {
      setState(() => _notes[index].image = File(path));
    }
  }

  Widget _buildImageField(int index) {
    final theme = Theme.of(context);
    final image = _notes[index].image;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Afbeelding',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        if (image != null)
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.file(
                  image,
                  height: 160,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 18),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black54,
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => setState(() => _notes[index].image = null),
                ),
              ),
            ],
          )
        else
          OutlinedButton.icon(
            onPressed: () => _pickImage(index),
            icon: const Icon(Icons.image_outlined, size: 18),
            label: const Text('Afbeelding kiezen'),
          ),
      ],
    );
  }

  LineChartData _buildChartData(
    List<List<FlSpot>> phaseSpots,
    double fMin,
    double fMax,
  ) {
    return _buildLineChartData(
      phaseSpots: phaseSpots,
      fMin: fMin,
      fMax: fMax,
      labels: const ['L1', 'L2', 'L3', 'N'],
      unit: 'A',
      yAxisLabel: 'Stroom (A)',
      showThreshold: true,
      thresholdValue: _ratedA,
    );
  }

  static const _phaseLegendColors = [
    Colors.red,
    Colors.amber,
    Colors.blue,
    Colors.grey,
  ];

  /// Vertaalt de interne aggregatievariant-suffix (bv. "_max200ms",
  /// "_maxsp", zoals gebruikt in [PqBoxCsvParser]) terug naar het
  /// aggregatietoken zoals dat in de originele PQ-Box CSV-kolomkop staat
  /// (bv. "max-200ms", "max-sp").
  static const Map<String, String> _variantHeaderAgg = {
    '': '',
    '_min': 'min',
    '_max': 'max',
    '_max200ms': 'max-200ms',
    '_maxsp': 'max-sp',
  };

  String _headerAgg(String variant) =>
      _variantHeaderAgg[variant] ?? (variant.isEmpty ? '' : variant.substring(1));

  /// Legenda-items met de originele PQ-Box CSV-kolomkoppen (bv.
  /// "IL1_max-sp_[A]", "I_Neutral_[A]"), alleen voor de fases die na het
  /// inladen daadwerkelijk data bevatten.
  List<LegendItem> _currentHeaderLegend(
    List<List<FlSpot>> phaseSpots,
    String variant,
  ) {
    final suffix = _headerAgg(variant).isEmpty ? '' : '_${_headerAgg(variant)}';
    final headers = [
      'IL1${suffix}_[A]',
      'IL2${suffix}_[A]',
      'IL3${suffix}_[A]',
      'I_Neutral${suffix}_[A]',
    ];
    return [
      for (var i = 0; i < headers.length; i++)
        if (phaseSpots[i].isNotEmpty)
          LegendItem(label: headers[i], color: _phaseLegendColors[i]),
    ];
  }

  /// Zelfde als [_currentHeaderLegend], maar voor de vermogenkolomkoppen
  /// (bv. "P_L1_[W]", "P_total_max_[W]").
  List<LegendItem> _powerHeaderLegend(
    List<List<FlSpot>> phaseSpots,
    String variant,
  ) {
    final suffix = _headerAgg(variant).isEmpty ? '' : '_${_headerAgg(variant)}';
    final headers = [
      'P_L1${suffix}_[W]',
      'P_L2${suffix}_[W]',
      'P_L3${suffix}_[W]',
      'P_total${suffix}_[W]',
    ];
    return [
      for (var i = 0; i < headers.length; i++)
        if (phaseSpots[i].isNotEmpty)
          LegendItem(label: headers[i], color: _phaseLegendColors[i]),
    ];
  }

  Widget _buildCurrentChart(
    String variant,
    double fMin,
    double fMax,
    List<FlSpot> Function(String key) spotsFor,
  ) {
    final phaseSpots = [
      spotsFor('I_L1$variant'),
      spotsFor('I_L2$variant'),
      spotsFor('I_L3$variant'),
      spotsFor('I_N$variant'),
    ];
    return ChartWrapper(
      title:
          '${_variantTitle('stroom', variant)} vs. maximale stroom '
          '(${_ratedA.toStringAsFixed(0)} A)',
      trailing: _PdfIncludeSwitch(
        included: _isChartIncluded('stroom$variant'),
        onChanged: (v) =>
            setState(() => _chartIncludedInPdf['stroom$variant'] = v),
      ),
      chartData: _buildChartData(phaseSpots, fMin, fMax),
      height: 380,
      legendItems: [
        ..._currentHeaderLegend(phaseSpots, variant),
        const LegendItem(label: 'Maximum', color: Colors.white60),
      ],
    );
  }

  Widget _buildPowerChart(
    String variant,
    double fMin,
    double fMax,
    List<FlSpot> Function(String key) powerSpotsFor,
  ) {
    final phaseSpots = [
      powerSpotsFor('P_L1$variant'),
      powerSpotsFor('P_L2$variant'),
      powerSpotsFor('P_L3$variant'),
      powerSpotsFor('P_total$variant'),
    ];
    return ChartWrapper(
      title: '${_variantTitle('vermogen', variant)} over tijd',
      trailing: _PdfIncludeSwitch(
        included: _isChartIncluded('vermogen$variant'),
        onChanged: (v) =>
            setState(() => _chartIncludedInPdf['vermogen$variant'] = v),
      ),
      chartData: _buildLineChartData(
        phaseSpots: phaseSpots,
        fMin: fMin,
        fMax: fMax,
        labels: const ['L1', 'L2', 'L3', 'Totaal'],
        unit: 'W',
        yAxisLabel: 'Vermogen (W)',
      ),
      height: 380,
      legendItems: _powerHeaderLegend(phaseSpots, variant),
    );
  }

  /// Generieke lijngrafiek voor stroom- of vermogendata. Wanneer
  /// [showThreshold] true is wordt een horizontale maximumlijn getoond
  /// (op [thresholdValue]) en het percentage daarvan in de tooltip; voor
  /// grootheden zonder ingestelde limiet (zoals vermogen) staat die uit.
  LineChartData _buildLineChartData({
    required List<List<FlSpot>> phaseSpots,
    required double fMin,
    required double fMax,
    required List<String> labels,
    required String unit,
    required String yAxisLabel,
    bool showThreshold = false,
    double thresholdValue = 0,
  }) {
    double maxMeasured = 0;
    for (final spots in phaseSpots) {
      for (final s in spots) {
        if (s.y > maxMeasured) maxMeasured = s.y;
      }
    }
    final maxY = showThreshold
        ? (maxMeasured.clamp(thresholdValue, double.infinity) * 1.1)
              .ceilToDouble()
        : (maxMeasured * 1.1).ceilToDouble().clamp(1.0, double.infinity);
    const colors = [Colors.red, Colors.amber, Colors.blue, Colors.grey];

    return LineChartData(
      minY: 0,
      maxY: maxY,
      minX: fMin,
      maxX: fMax,
      clipData: const FlClipData.all(),
      gridData: FlGridData(
        show: true,
        getDrawingHorizontalLine: (_) => const FlLine(
          color: Colors.white12,
          strokeWidth: 1,
          dashArray: [4, 4],
        ),
      ),
      borderData: FlBorderData(show: true),
      extraLinesData: showThreshold
          ? ExtraLinesData(
              horizontalLines: [
                HorizontalLine(
                  y: thresholdValue,
                  color: Colors.white60,
                  strokeWidth: 1.5,
                  dashArray: [8, 4],
                  label: HorizontalLineLabel(
                    show: true,
                    labelResolver: (_) =>
                        '${thresholdValue.toStringAsFixed(0)} $unit (max)',
                    style: const TextStyle(fontSize: 10, color: Colors.white60),
                    alignment: Alignment.topRight,
                  ),
                ),
              ],
            )
          : const ExtraLinesData(),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(
          axisNameWidget: Text(
            yAxisLabel,
            style: const TextStyle(fontSize: 11),
          ),
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 48,
            getTitlesWidget: (v, meta) => SideTitleWidget(
              meta: meta,
              child: Text(
                v.toStringAsFixed(0),
                style: const TextStyle(fontSize: 10),
              ),
            ),
          ),
        ),
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 36,
            interval: (fMax - fMin) / 6,
            getTitlesWidget: (v, meta) {
              if (v == meta.min || v == meta.max) {
                return const SizedBox.shrink();
              }
              return SideTitleWidget(
                meta: meta,
                child: Text(
                  formatXAxisLabel(v),
                  style: const TextStyle(fontSize: 9),
                ),
              );
            },
          ),
        ),
      ),
      lineBarsData: [
        for (int i = 0; i < phaseSpots.length; i++)
          LineChartBarData(
            spots: phaseSpots[i],
            color: colors[i],
            barWidth: 1.5,
            dotData: const FlDotData(show: false),
            isCurved: false,
          ),
      ],
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => Colors.black87,
          getTooltipItems: (spots) {
            return spots.map((s) {
              final idx = s.barIndex.clamp(0, labels.length - 1);
              final pct = showThreshold && thresholdValue > 0
                  ? ' (${(s.y / thresholdValue * 100).toStringAsFixed(0)}%)'
                  : '';
              return LineTooltipItem(
                '${labels[idx]}: ${s.y.toStringAsFixed(2)} $unit$pct',
                TextStyle(color: colors[idx], fontSize: 11),
              );
            }).toList();
          },
        ),
      ),
    );
  }

  static const _currentFieldPrefixes = ['I_L1', 'I_L2', 'I_L3', 'I_N'];
  static const _powerFieldPrefixes = ['P_L1', 'P_L2', 'P_L3', 'P_total'];

  String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  /// Leesbare titel voor een aggregatievariant-suffix (bv. "", "_min",
  /// "_max", "_max200ms", "_maxsp") zoals die uit een PQ-Box 150 CSV-map
  /// wordt ingelezen — elk bestand levert daarbij zijn eigen suffix.
  /// [noun] is de grootheid in kleine letters, bv. "stroom" of "vermogen".
  String _variantTitle(String noun, String variant) {
    switch (variant) {
      case '':
        return '${_capitalize(noun)} (gemiddeld/RMS)';
      case '_min':
        return 'Minimum$noun';
      case '_max':
        return 'Maximum$noun';
      case '_max200ms':
        return 'Maximum$noun (200 ms)';
      case '_maxsp':
        return 'Maximum$noun (piekwaarde)';
      default:
        final label = variant.startsWith('_') ? variant.substring(1) : variant;
        return '${_capitalize(noun)} ($label)';
    }
  }

  /// Vindt de aggregatievariant-suffixen (bv. "", "_min", "_max",
  /// "_max200ms", "_maxsp") die aanwezig zijn op de gegeven veldprefixen
  /// (bv. I_L1/I_L2/I_L3/I_N of P_L1/P_L2/P_L3/P_total) — elk geïmporteerd
  /// PQ-Box 150 CSV-bestand levert zijn eigen suffix.
  Set<String> _detectVariants(
    List<MeasurementPoint> points,
    List<String> prefixes,
  ) {
    final variants = <String>{};
    for (final p in points) {
      for (final key in p.values.keys) {
        for (final prefix in prefixes) {
          if (key.startsWith(prefix)) {
            variants.add(key.substring(prefix.length));
          }
        }
      }
    }
    return variants;
  }

  List<String> _orderVariants(Set<String> variants) {
    const variantOrder = ['', '_min', '_max'];
    return variants.toList()..sort((a, b) {
      final ia = variantOrder.indexOf(a);
      final ib = variantOrder.indexOf(b);
      if (ia != -1 || ib != -1) {
        return (ia == -1 ? variantOrder.length : ia).compareTo(
          ib == -1 ? variantOrder.length : ib,
        );
      }
      return a.compareTo(b);
    });
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
      .where(
        (p) =>
            p.time.millisecondsSinceEpoch >= _filterMinMs &&
            p.time.millisecondsSinceEpoch <= _filterMaxMs,
      )
      .toList();

  Future<void> _exportPdf(BuildContext context) async {
    final session = _lastSession;
    if (session == null) return;
    final data = _filtered(session.currentData);
    final phases = <PhaseReportData>[];
    for (final phase in ['L1', 'L2', 'L3', 'N']) {
      final vals = data
          .map((p) => p.values['I_$phase'])
          .whereType<double>()
          .toList();
      if (vals.isEmpty) continue;
      phases.add(
        PhaseReportData(
          phase: phase,
          avg: vals.reduce((a, b) => a + b) / vals.length,
          peak: vals.reduce((a, b) => a > b ? a : b),
          rated: _ratedA,
        ),
      );
    }

    // Grafiekdata: gesamplede punten, x = uren na start
    final t0 = _filterMinMs;
    final step = (data.length / 300).ceil().clamp(1, data.length);
    final sampled = [for (int i = 0; i < data.length; i += step) data[i]];

    final powerData = _filtered(session.activePowerData);
    final powerStep = powerData.isEmpty
        ? 1
        : (powerData.length / 300).ceil().clamp(1, powerData.length);
    final sampledPower = [
      for (int i = 0; i < powerData.length; i += powerStep) powerData[i],
    ];

    // Eén grafiek per aggregatievariant (= per geïmporteerd CSV-bestand)
    final orderedVariants = _orderVariants(
      _detectVariants(sampled, _currentFieldPrefixes),
    );
    final orderedPowerVariants = _orderVariants(
      _detectVariants(sampledPower, _powerFieldPrefixes),
    );
    final chartSections = [
      for (final variant in orderedVariants)
        if (_isChartIncluded('stroom$variant'))
          CapacityChartSection(
            title: '${_variantTitle('stroom', variant)} over tijd',
            series: {
              for (final phase in ['L1', 'L2', 'L3', 'N'])
                phase: sampled
                    .where((p) => p.values.containsKey('I_$phase$variant'))
                    .map(
                      (p) => ChartPoint(
                        (p.time.millisecondsSinceEpoch - t0) / 3600000.0,
                        p.values['I_$phase$variant']!,
                      ),
                    )
                    .toList(),
            },
          ),
      // Vermogen: geen ingestelde limiet, dus zonder maximumdrempel.
      for (final variant in orderedPowerVariants)
        if (_isChartIncluded('vermogen$variant'))
          CapacityChartSection(
            title: '${_variantTitle('vermogen', variant)} over tijd',
            unit: 'W',
            showRatedLine: false,
            neutralLabel: 'Totaal',
            series: {
              for (final phase in ['L1', 'L2', 'L3'])
                phase: sampledPower
                    .where((p) => p.values.containsKey('P_$phase$variant'))
                    .map(
                      (p) => ChartPoint(
                        (p.time.millisecondsSinceEpoch - t0) / 3600000.0,
                        p.values['P_$phase$variant']!,
                      ),
                    )
                    .toList(),
              'N': sampledPower
                  .where((p) => p.values.containsKey('P_total$variant'))
                  .map(
                    (p) => ChartPoint(
                      (p.time.millisecondsSinceEpoch - t0) / 3600000.0,
                      p.values['P_total$variant']!,
                    ),
                  )
                  .toList(),
            },
          ),
    ];

    await exportCapacityPdf(
      context: context,
      deviceId: session.deviceId,
      ratedA: _ratedA,
      periodStart: DateTime.fromMillisecondsSinceEpoch(
        _filterMinMs.toInt(),
        isUtc: true,
      ),
      periodEnd: DateTime.fromMillisecondsSinceEpoch(
        _filterMaxMs.toInt(),
        isUtc: true,
      ),
      phases: phases,
      chartSections: chartSections,
      notes: [
        for (final note in _notes)
          CapacityNote(
            title: note.titleController.text,
            bodyText: note.textController.text,
            image: note.image,
          ),
      ],
      generalInfo: _generalInfo.toGeneralInfo(),
      introText: _introTextController.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<MeasurementProvider>().session;
    final standaarden = context.watch<StandaardenProvider>().standaarden;

    if (session == null) {
      return const Center(child: Text('Open een meetmap om data te laden.'));
    }

    final rawData = session.currentData;
    if (rawData.isEmpty) {
      return const Center(child: Text('Geen stroomdata beschikbaar.'));
    }

    final totalMinMs = rawData.first.time.millisecondsSinceEpoch.toDouble();
    final totalMaxMs = rawData.last.time.millisecondsSinceEpoch.toDouble();
    final fMin = _filterMinMs.clamp(totalMinMs, totalMaxMs);
    final fMax = _filterMaxMs.clamp(totalMinMs, totalMaxMs);

    final data = _filtered(rawData);

    // Per-phase statistics
    const phases = ['L1', 'L2', 'L3', 'N'];
    const phaseColors = <Color>[
      Colors.red,
      Colors.amber,
      Colors.blue,
      Colors.grey,
    ];
    final stats = <String, _PhaseStats>{};
    for (final phase in phases) {
      final key = 'I_$phase';
      final vals = data.map((p) => p.values[key]).whereType<double>().toList();
      if (vals.isEmpty) continue;
      final avg = vals.reduce((a, b) => a + b) / vals.length;
      final peak = vals.reduce((a, b) => a > b ? a : b);
      stats[phase] = _PhaseStats(avg: avg, peak: peak, rated: _ratedA);
    }

    // Chart spots
    final step = (data.length / 500).ceil().clamp(1, data.length);
    final sampled = [for (int i = 0; i < data.length; i += step) data[i]];

    List<FlSpot> spotsForIn(List<MeasurementPoint> src, String key) => src
        .where((p) => p.values.containsKey(key))
        .map(
          (p) =>
              FlSpot(p.time.millisecondsSinceEpoch.toDouble(), p.values[key]!),
        )
        .toList();
    List<FlSpot> spotsFor(String key) => spotsForIn(sampled, key);

    // Elke CSV-import (PQ-Box 150) levert een eigen aggregatievariant
    // (gemiddeld/RMS, min, max, max-200ms, max-sp, ...) als suffix op de
    // I_L1/I_L2/I_L3/I_N-velden. Elke variant krijgt hier zijn eigen grafiek.
    final orderedVariants = _orderVariants(
      _detectVariants(sampled, _currentFieldPrefixes),
    );

    // Vermogen (P_L1/P_L2/P_L3/P_total), indien meegenomen bij de CSV-import.
    final powerData = _filtered(session.activePowerData);
    final powerStep = powerData.isEmpty
        ? 1
        : (powerData.length / 500).ceil().clamp(1, powerData.length);
    final sampledPower = [
      for (int i = 0; i < powerData.length; i += powerStep) powerData[i],
    ];
    List<FlSpot> powerSpotsFor(String key) => spotsForIn(sampledPower, key);
    final orderedPowerVariants = _orderVariants(
      _detectVariants(sampledPower, _powerFieldPrefixes),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Inleiding
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListTile(
                  leading: Icon(
                    Icons.description_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: const Text('Inleiding'),
                  trailing: Icon(
                    _introExpanded ? Icons.expand_less : Icons.expand_more,
                  ),
                  onTap: () => setState(() => _introExpanded = !_introExpanded),
                ),
                if (_introExpanded)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _StandaardTitleDropdown(
                          selectedId: _introStandaardId,
                          standaarden: standaarden,
                          onSelected: (standaard) => setState(() {
                            _introStandaardId = standaard.id;
                            _introTextController.text = standaard.tekst;
                          }),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _introTextController,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            labelText: 'Tekst',
                            border: OutlineInputBorder(),
                            alignLabelWithHint: true,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Algemene gegevens
          _GeneralInfoCard(entry: _generalInfo),
          const SizedBox(height: 12),

          // Rated current input + PDF export
          Row(
            children: [
              Expanded(
                child: _RatedCurrentInput(
                  controller: _ratedController,
                  onChanged: (v) => setState(() => _ratedA = v),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: () => _exportPdf(context),
                icon: const Icon(Icons.picture_as_pdf, size: 18),
                label: const Text('PDF exporteren'),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Phase cards
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (int i = 0; i < phases.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: stats.containsKey(phases[i])
                      ? _PhaseCard(
                          phase: phases[i],
                          color: phaseColors[i],
                          stats: stats[phases[i]]!,
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),

          // Time range selector
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

          // Eén grafiek per aggregatievariant (= per geïmporteerd CSV-bestand)
          for (final variant in orderedVariants) ...[
            _buildCurrentChart(variant, fMin, fMax, spotsFor),
            const SizedBox(height: 12),
          ],

          // Vermogen (P_L1/P_L2/P_L3/P_total), indien meegenomen bij de
          // CSV-import — puur ter informatie, zonder maximumdrempel.
          if (orderedPowerVariants.isNotEmpty) ...[
            Text(
              'Vermogen',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            for (final variant in orderedPowerVariants) ...[
              _buildPowerChart(variant, fMin, fMax, powerSpotsFor),
              const SizedBox(height: 12),
            ],
          ],

          // Titel / Tekst / Afbeelding (x4)
          for (int i = 0; i < _notes.length; i++) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _StandaardTitleDropdown(
                      selectedId: _notes[i].standaardId,
                      standaarden: standaarden,
                      onSelected: (standaard) => setState(() {
                        _notes[i].standaardId = standaard.id;
                        _notes[i].titleController.text = standaard.titel;
                        _notes[i].textController.text = standaard.tekst;
                      }),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _notes[i].textController,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Tekst',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _buildImageField(i),
                  ],
                ),
              ),
            ),
            if (i < _notes.length - 1) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

// ── Titel dropdown (gekozen uit standaarden) ────────────────────────────────────

class _StandaardTitleDropdown extends StatelessWidget {
  final String? selectedId;
  final List<Standaard> standaarden;
  final void Function(Standaard standaard) onSelected;

  const _StandaardTitleDropdown({
    required this.selectedId,
    required this.standaarden,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final hasSelection = standaarden.any((s) => s.id == selectedId);
    return DropdownButtonFormField<String>(
      initialValue: hasSelection ? selectedId : null,
      decoration: const InputDecoration(
        labelText: 'Titel',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      hint: Text(
        standaarden.isEmpty ? 'Geen standaarden beschikbaar' : 'Kies een titel',
      ),
      items: [
        for (final standaard in standaarden)
          DropdownMenuItem(
            value: standaard.id,
            child: Text(standaard.titel, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: standaarden.isEmpty
          ? null
          : (id) {
              final standaard = standaarden.firstWhere((s) => s.id == id);
              onSelected(standaard);
            },
    );
  }
}

// ── Note entry (Titel / Tekst / Afbeelding) ─────────────────────────────────────

class _NoteEntry {
  final titleController = TextEditingController();
  final textController = TextEditingController();
  String? standaardId;
  File? image;
}

// ── Algemene gegevens ────────────────────────────────────────────────────────

class _GeneralInfoEntry {
  // Opdrachtgever
  final clientCompany = TextEditingController(text: 'THUIS');
  final clientAddress = TextEditingController(text: 'Bergerstraat 87');
  final clientPostalCity = TextEditingController(text: '6226 BB Maastricht');
  final clientContact = TextEditingController(text: 'BE van Reijswoud');
  final clientPhone = TextEditingController(text: '0633374741');
  final clientEmail = TextEditingController(text: 'Appeltaartje@gmail.com');

  // Inspectieadres
  final inspectionName = TextEditingController(text: 'THUIS');
  final inspectionAddress = TextEditingController(text: 'Bergerstraat 87');
  final inspectionPostalCity = TextEditingController(
    text: '6226 BB Maastricht',
  );
  final inspectionContact = TextEditingController(text: 'BE van Reijswoud');
  final inspectionPhone = TextEditingController(text: '067474651');
  final inspectionEmail = TextEditingController(text: 'appeltaartje@gmail.com');

  // Inspectiebedrijf
  final inspectorCompany = TextEditingController(text: 'EPM');
  final inspectorAddress = TextEditingController(
    text: 'Business Park Stein 408',
  );
  final inspectorPostalCity = TextEditingController(text: '6181 MD Elsloo');
  final inspectorPhone = TextEditingController(text: '043-364 28 23');
  final inspectorEmail = TextEditingController(text: 'Inspectie@epm.nl');
  final inspectorContact = TextEditingController(text: 'Vivianne Feron');
  final inspectorResponsible = TextEditingController(text: 'Erwin Hermans');

  List<TextEditingController> get _all => [
    clientCompany,
    clientAddress,
    clientPostalCity,
    clientContact,
    clientPhone,
    clientEmail,
    inspectionName,
    inspectionAddress,
    inspectionPostalCity,
    inspectionContact,
    inspectionPhone,
    inspectionEmail,
    inspectorCompany,
    inspectorAddress,
    inspectorPostalCity,
    inspectorPhone,
    inspectorEmail,
    inspectorContact,
    inspectorResponsible,
  ];

  void dispose() {
    for (final c in _all) {
      c.dispose();
    }
  }

  GeneralInfo toGeneralInfo() => GeneralInfo(
    clientCompany: clientCompany.text,
    clientAddress: clientAddress.text,
    clientPostalCity: clientPostalCity.text,
    clientContact: clientContact.text,
    clientPhone: clientPhone.text,
    clientEmail: clientEmail.text,
    inspectionName: inspectionName.text,
    inspectionAddress: inspectionAddress.text,
    inspectionPostalCity: inspectionPostalCity.text,
    inspectionContact: inspectionContact.text,
    inspectionPhone: inspectionPhone.text,
    inspectionEmail: inspectionEmail.text,
    inspectorCompany: inspectorCompany.text,
    inspectorAddress: inspectorAddress.text,
    inspectorPostalCity: inspectorPostalCity.text,
    inspectorPhone: inspectorPhone.text,
    inspectorEmail: inspectorEmail.text,
    inspectorContact: inspectorContact.text,
    inspectorResponsible: inspectorResponsible.text,
  );
}

class _GeneralInfoCard extends StatefulWidget {
  final _GeneralInfoEntry entry;
  const _GeneralInfoCard({required this.entry});

  @override
  State<_GeneralInfoCard> createState() => _GeneralInfoCardState();
}

class _GeneralInfoCardState extends State<_GeneralInfoCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final e = widget.entry;

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: Icon(
              Icons.badge_outlined,
              color: theme.colorScheme.primary,
            ),
            title: const Text('Algemene Gegevens'),
            subtitle: const Text(
              'Opdrachtgever, inspectieadres en inspectiebedrijf',
            ),
            trailing: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
            onTap: () => setState(() => _expanded = !_expanded),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _GeneralInfoGroup(
                    title: 'Opdrachtgever',
                    fields: [
                      ('Naam bedrijf', e.clientCompany),
                      ('Adres', e.clientAddress),
                      ('Postcode plaats', e.clientPostalCity),
                      ('Contactpersoon', e.clientContact),
                      ('Telefoonnummer', e.clientPhone),
                      ('Mail', e.clientEmail),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _GeneralInfoGroup(
                    title: 'Inspectieadres',
                    fields: [
                      ('Naam', e.inspectionName),
                      ('Adres', e.inspectionAddress),
                      ('Postcode plaats', e.inspectionPostalCity),
                      ('Contactpersoon', e.inspectionContact),
                      ('Telefoonnummer', e.inspectionPhone),
                      ('Mail', e.inspectionEmail),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _GeneralInfoGroup(
                    title: 'Inspectiebedrijf',
                    fields: [
                      ('Naam bedrijf', e.inspectorCompany),
                      ('Adres', e.inspectorAddress),
                      ('Postcode plaats', e.inspectorPostalCity),
                      ('Telefoon', e.inspectorPhone),
                      ('Mail', e.inspectorEmail),
                      ('Contactpersoon', e.inspectorContact),
                      ('Auteur', e.inspectorResponsible),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _GeneralInfoGroup extends StatelessWidget {
  final String title;
  final List<(String, TextEditingController)> fields;

  const _GeneralInfoGroup({required this.title, required this.fields});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            for (final (label, controller) in fields)
              SizedBox(
                width: 280,
                child: TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    labelText: label,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

// ── Data class ────────────────────────────────────────────────────────────────

class _PhaseStats {
  final double avg;
  final double peak;
  final double rated;

  const _PhaseStats({
    required this.avg,
    required this.peak,
    required this.rated,
  });

  double get avgPct => rated > 0 ? avg / rated * 100 : 0;
  double get peakPct => rated > 0 ? peak / rated * 100 : 0;
  double get headroomAvg => rated - avg;
  double get headroomPeak => rated - peak;

  Color get statusColor {
    if (peakPct >= 90) return Colors.red;
    if (peakPct >= 70) return Colors.orange;
    return Colors.green;
  }

  IconData get statusIcon {
    if (peakPct >= 90) return Icons.warning;
    if (peakPct >= 70) return Icons.warning_amber;
    return Icons.check_circle;
  }
}

// ── Phase summary card ────────────────────────────────────────────────────────

class _PhaseCard extends StatelessWidget {
  final String phase;
  final Color color;
  final _PhaseStats stats;

  const _PhaseCard({
    required this.phase,
    required this.color,
    required this.stats,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: color.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: color.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  phase,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Icon(stats.statusIcon, color: stats.statusColor, size: 18),
              ],
            ),
            const SizedBox(height: 6),
            const Divider(height: 1),
            const SizedBox(height: 6),
            _statRow('gem.', stats.avg, stats.avgPct, theme),
            _statRow('piek', stats.peak, stats.peakPct, theme),
            const SizedBox(height: 4),
            const Divider(height: 1),
            const SizedBox(height: 4),
            _headroomRow('ruimte gem.', stats.headroomAvg, theme),
            _headroomRow('ruimte piek', stats.headroomPeak, theme),
            const SizedBox(height: 8),
            _UtilizationBar(peakPct: stats.peakPct, avgPct: stats.avgPct),
          ],
        ),
      ),
    );
  }

  Widget _statRow(String label, double val, double pct, ThemeData theme) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          children: [
            Text(label, style: theme.textTheme.bodySmall),
            const Spacer(),
            Text(
              '${val.toStringAsFixed(1)} A',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 36,
              child: Text(
                '${pct.toStringAsFixed(0)}%',
                textAlign: TextAlign.right,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ),
          ],
        ),
      );

  Widget _headroomRow(String label, double val, ThemeData theme) {
    final isNegative = val < 0;
    final color = isNegative ? Colors.red : Colors.green.shade300;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          Text(label, style: theme.textTheme.bodySmall),
          const Spacer(),
          Text(
            isNegative
                ? '${val.toStringAsFixed(1)} A !'
                : '+${val.toStringAsFixed(1)} A',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Schakelaar: grafiek wel/niet meenemen in PDF-export ─────────────────────

class _PdfIncludeSwitch extends StatelessWidget {
  final bool included;
  final ValueChanged<bool> onChanged;

  const _PdfIncludeSwitch({required this.included, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: included
          ? 'Wordt meegenomen in de PDF — klik om uit te sluiten'
          : 'Wordt niet meegenomen in de PDF — klik om toe te voegen',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            included ? Icons.picture_as_pdf : Icons.picture_as_pdf_outlined,
            size: 16,
            color: included
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          Switch(value: included, onChanged: onChanged),
        ],
      ),
    );
  }
}

// ── Utilization bar ───────────────────────────────────────────────────────────

class _UtilizationBar extends StatelessWidget {
  final double peakPct;
  final double avgPct;

  const _UtilizationBar({required this.peakPct, required this.avgPct});

  Color _color(double pct) {
    if (pct >= 90) return Colors.red;
    if (pct >= 70) return Colors.orange;
    return Colors.green;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Bezetting', style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 3),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: Stack(
            children: [
              Container(height: 10, color: Colors.white12),
              FractionallySizedBox(
                widthFactor: (avgPct / 100).clamp(0.0, 1.0),
                child: Container(
                  height: 10,
                  color: _color(avgPct).withValues(alpha: 0.45),
                ),
              ),
              FractionallySizedBox(
                widthFactor: (peakPct / 100).clamp(0.0, 1.0),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    width: 2,
                    height: 10,
                    color: _color(peakPct),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'gem. ${avgPct.toStringAsFixed(0)}%',
              style: const TextStyle(fontSize: 9, color: Colors.white54),
            ),
            Text(
              'piek ${peakPct.toStringAsFixed(0)}%',
              style: const TextStyle(fontSize: 9, color: Colors.white54),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Rated current input ───────────────────────────────────────────────────────

class _RatedCurrentInput extends StatelessWidget {
  final TextEditingController controller;
  final void Function(double) onChanged;

  const _RatedCurrentInput({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text('Maximale stroom:', style: TextStyle(fontSize: 14)),
        const SizedBox(width: 12),
        SizedBox(
          width: 90,
          child: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            decoration: const InputDecoration(
              suffixText: 'A',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              isDense: true,
            ),
            onChanged: (v) {
              final parsed = double.tryParse(v);
              if (parsed != null && parsed > 0) onChanged(parsed);
            },
          ),
        ),
        const SizedBox(width: 10),
        Wrap(
          spacing: 6,
          children: [25, 40, 63, 80, 100, 125]
              .map(
                (a) => ActionChip(
                  label: Text('$a A', style: const TextStyle(fontSize: 11)),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    controller.text = a.toString();
                    onChanged(a.toDouble());
                  },
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}
