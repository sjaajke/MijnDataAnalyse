import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/metrel_record.dart';
import '../providers/measurement_provider.dart';
import '../providers/metrel_provider.dart';
import '../services/metrel_catalog.dart';
import '../widgets/chart_wrapper.dart';
import '../services/import_picker.dart';

/// Opent een Metrel-bestand (.pwvx) of recordmap, toont het in het
/// Metrel-scherm en laadt het ook in de analyseschermen.
Future<void> openMetrel(BuildContext context, {bool folder = false}) async {
  final String? path;
  if (folder) {
    path = await pickImportFolder(
      dialogTitle: 'Open Metrel recordmap',
    );
  } else {
    path = await pickImportFile(
      dialogTitle: 'Open Metrel PowerView bestand',
      type: FileType.custom,
      allowedExtensions: ['pwvx'],
    );
  }
  if (path == null || !context.mounted) return;

  final metrel = context.read<MetrelProvider>();
  await metrel.open(path);
  if (context.mounted) _loadIntoAnalysis(context);
}

void _loadIntoAnalysis(BuildContext context) {
  final metrel = context.read<MetrelProvider>();
  final session = metrel.sessionForSelected();
  if (session == null) return;
  final record = metrel.selected!;
  context.read<MeasurementProvider>().loadXlsxSession(
        session,
        metrel.records.length > 1
            ? '${metrel.path} — ${record.name}'
            : metrel.path!,
      );
}

const _channelColors = <String, Color>{
  'L1': Colors.red,
  'L2': Colors.amber,
  'L3': Colors.blue,
  'Ln': Colors.grey,
  'L12': Colors.deepOrange,
  'L23': Colors.lightGreen,
  'L31': Colors.purpleAccent,
  'Tot': Colors.green,
  'RefCh': Colors.teal,
};

final _dateTimeFmt = DateFormat('dd-MM-yyyy HH:mm:ss');
final _eventTimeFmt = DateFormat('dd-MM-yyyy HH:mm:ss.SSS');

String _formatValue(double v) {
  final a = v.abs();
  if (a >= 1000) return v.toStringAsFixed(0);
  if (a >= 100) return v.toStringAsFixed(2);
  if (a >= 1) return v.toStringAsFixed(3);
  return v.toStringAsFixed(4);
}

String _formatDuration(Duration d) {
  final us = d.inMicroseconds;
  if (us < 1000000) return '${(us / 1000).toStringAsFixed(1)} ms';
  if (us < 60000000) return '${(us / 1000000).toStringAsFixed(3)} s';
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

class MetrelScreen extends StatelessWidget {
  const MetrelScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MetrelProvider>();
    final record = provider.selected;

    if (provider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (record == null) {
      return _EmptyState(error: provider.error);
    }

    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          _Header(provider: provider, record: record),
          const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.info_outline), text: 'Overzicht'),
              Tab(icon: Icon(Icons.show_chart), text: 'Trends'),
              Tab(icon: Icon(Icons.warning_amber), text: 'Events'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _OverviewTab(record: record),
                _TrendsTab(key: ObjectKey(record), record: record),
                _EventsTab(key: ObjectKey(record), record: record),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String? error;

  const _EmptyState({this.error});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.electrical_services,
                size: 56, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('Metrel data', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Open een Metrel PowerView-bestand (.pwvx) of een uitgepakte '
              'recordmap van een MI 2892/2893/2992. Meetgrootheden, kanalen '
              'en events worden benoemd met de meetcatalogus van de Metrel '
              'Power SDK.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: () => openMetrel(context),
                  icon: const Icon(Icons.file_open),
                  label: const Text('Open .pwvx bestand'),
                ),
                OutlinedButton.icon(
                  onPressed: () => openMetrel(context, folder: true),
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Open recordmap'),
                ),
              ],
            ),
            if (error != null) ...[
              const SizedBox(height: 16),
              SelectableText(
                error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final MetrelProvider provider;
  final MetrelRecord record;

  const _Header({required this.provider, required this.record});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fileName = provider.path?.split(Platform.pathSeparator).last ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Icon(Icons.electrical_services, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Metrel — ${record.instrumentLabel}',
                    style: theme.textTheme.titleLarge),
                Text(
                  '$fileName · tijden in ${record.utcOffsetLabel} · '
                  'ook geladen in de analyseschermen',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (provider.records.length > 1) ...[
            DropdownButton<int>(
              value: provider.selectedIndex,
              items: [
                for (final (i, r) in provider.records.indexed)
                  DropdownMenuItem(value: i, child: Text(r.name)),
              ],
              onChanged: (i) {
                if (i == null) return;
                provider.select(i);
                _loadIntoAnalysis(context);
              },
            ),
            const SizedBox(width: 12),
          ],
          PopupMenuButton<bool>(
            tooltip: 'Ander bestand openen',
            onSelected: (folder) => openMetrel(context, folder: folder),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: false,
                child: ListTile(
                  leading: Icon(Icons.file_open),
                  title: Text('.pwvx bestand'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: true,
                child: ListTile(
                  leading: Icon(Icons.folder_open),
                  title: Text('Recordmap'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
            child: const Chip(
              avatar: Icon(Icons.upload_file, size: 18),
              label: Text('Openen'),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Overzicht ───────────────────────────────────────────────────────────

class _OverviewTab extends StatelessWidget {
  final MetrelRecord record;

  const _OverviewTab({required this.record});

  @override
  Widget build(BuildContext context) {
    final info = record.instrumentInfo;
    final recordInfo =
        record.recorderSettings['recorderSettings']?['recordInfo'];
    final whatToRecord = record.recorderSettings['recorderSettings']
        ?['whatToRecord'] as Map<String, dynamic>?;
    final recorded = [
      for (final e in (whatToRecord ?? const {}).entries)
        if (e.value is Map && e.value['value'] == true) e.key,
    ];

    final withData = record.streams.where((s) => s.recordCount > 0);
    final start = record.start ??
        (withData.isEmpty ? null : withData.map((s) => s.times.first).reduce(
            (a, b) => a.isBefore(b) ? a : b));
    final end = record.end ??
        (withData.isEmpty ? null : withData.map((s) => s.times.last).reduce(
            (a, b) => a.isAfter(b) ? a : b));
    String time(DateTime? t) =>
        t == null ? '—' : _dateTimeFmt.format(record.toRecordTime(t));

    final eventCounts = <MetrelEventFamily, int>{};
    for (final e in record.events) {
      eventCounts[e.family] = (eventCounts[e.family] ?? 0) + 1;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _InfoCard(title: 'Record', rows: {
                'Naam': record.name,
                'Map': record.folder,
                'Start': time(start),
                'Einde': time(end),
                if (start != null && end != null)
                  'Duur': _formatDuration(end.difference(start)),
                'Tijdzone':
                    '${record.timeZoneId ?? '—'} (${record.utcOffsetLabel})',
              }),
              _InfoCard(title: 'Instrument', rows: {
                'Model': info['model'] ?? '—',
                'Serienummer': info['serialNumber'] ?? '—',
                'Firmware': info['firmwareVersion'] ?? '—',
                'Hardware': info['hardwareVersion'] ?? '—',
                'App-versie': info['appVersion'] ?? '—',
                'Kalibratie': (info['calibrationDate'] as String?)
                            ?.isNotEmpty ==
                        true
                    ? info['calibrationDate']
                    : '—',
                'Bedrijf': info['companyData'] ?? '—',
              }),
              _InfoCard(title: 'Instellingen', rows: {
                'Nominale spanning': record.nominalVoltage == null
                    ? '—'
                    : '${record.nominalVoltage!.toStringAsFixed(0)} V',
                'Locatie': record.location ?? '—',
                'Profiel': recordInfo?['profile']?['value'] ?? '—',
                'Opgenomen': recorded.isEmpty ? '—' : recorded.join(', '),
              }),
              _InfoCard(title: 'Events', rows: {
                for (final f in MetrelEventFamily.values)
                  f.label: '${eventCounts[f] ?? 0}',
              }),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Intervalstromen',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Interval')),
                        DataColumn(label: Text('Intervallen'), numeric: true),
                        DataColumn(label: Text('Kolommen'), numeric: true),
                        DataColumn(label: Text('Van')),
                        DataColumn(label: Text('Tot')),
                        DataColumn(label: Text('Met vlaggen'), numeric: true),
                      ],
                      rows: [
                        for (final s in record.streams)
                          DataRow(cells: [
                            DataCell(Text(s.label)),
                            DataCell(Text('${s.recordCount}')),
                            DataCell(Text('${s.descriptors.length}')),
                            DataCell(Text(s.recordCount == 0
                                ? '—'
                                : time(s.times.first))),
                            DataCell(Text(s.recordCount == 0
                                ? '—'
                                : time(s.times.last))),
                            DataCell(Text(
                                '${s.flags.where((f) => f != 0).length}')),
                          ]),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final Map<String, Object?> rows;

  const _InfoCard({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 340,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final e in rows.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 130,
                        child: Text(e.key,
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant)),
                      ),
                      Expanded(
                        child: SelectableText('${e.value}',
                            style: theme.textTheme.bodyMedium),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Trends ──────────────────────────────────────────────────────────────

/// Alle kolommen van één grootheid binnen een intervalstroom.
class _MeasurementEntry {
  final MetrelMeasurementInfo info;
  final List<MetrelDescriptor> descriptors = [];
  final Set<String> channels = {};
  final Set<String> aggregations = {};
  final Map<String, String> aggregationNames = {};
  final Set<int> harmonics = {};

  _MeasurementEntry(this.info);

  void add(MetrelDescriptor d) {
    final i = d.info!;
    descriptors.add(d);
    channels.add(i.channel);
    aggregations.add(i.aggregation);
    aggregationNames[i.aggregation] = i.aggregationName;
    if (i.harmonic != null) harmonics.add(i.harmonic!);
  }
}

class _TrendsTab extends StatefulWidget {
  final MetrelRecord record;

  const _TrendsTab({super.key, required this.record});

  @override
  State<_TrendsTab> createState() => _TrendsTabState();
}

class _TrendsTabState extends State<_TrendsTab> {
  static const _maxSeries = 12;
  static const _maxPoints = 2000;
  static const _avgAggregations = ['AvgRms', 'AvgAvg', 'AvgOnAvg', 'AvgOnRms'];

  late MetrelStream? _stream;
  Map<String, Map<String, _MeasurementEntry>> _groups = {};
  String? _code;
  Set<String> _channels = {};
  Set<String> _aggregations = {};
  int? _harmonic;
  String _search = '';

  @override
  void initState() {
    super.initState();
    final streams = widget.record.streams;
    _stream = streams
            .where((s) =>
                s.recordCount > 0 && s.find('Urms', 'L1', 'AvgRms') != null)
            .firstOrNull ??
        streams.where((s) => s.recordCount > 0).firstOrNull ??
        streams.firstOrNull;
    _indexStream();
    if (_groups.values.any((g) => g.containsKey('Urms'))) _selectCode('Urms');
  }

  void _indexStream() {
    final groups = <String, Map<String, _MeasurementEntry>>{};
    for (final d in _stream?.descriptors ?? const <MetrelDescriptor>[]) {
      final info = d.info;
      if (info == null) continue;
      groups
          .putIfAbsent(info.group, () => {})
          .putIfAbsent(info.code, () => _MeasurementEntry(info))
          .add(d);
    }
    _groups = groups;
  }

  _MeasurementEntry? get _entry {
    for (final g in _groups.values) {
      final e = g[_code];
      if (e != null) return e;
    }
    return null;
  }

  void _selectCode(String code) {
    _code = code;
    final e = _entry;
    if (e == null) return;
    // Standaard alleen de fasen; lijn-, nul- en totaalkanalen zijn aan te zetten.
    final phases = e.channels.intersection(const {'L1', 'L2', 'L3'});
    _channels = phases.isNotEmpty ? phases : e.channels.toSet();
    final avg = _avgAggregations.where(e.aggregations.contains).firstOrNull;
    _aggregations = {avg ?? e.aggregations.first};
    _harmonic = e.harmonics.isEmpty
        ? null
        : (e.harmonics.contains(3) ? 3 : (e.harmonics.toList()..sort()).first);
  }

  void _selectStream(MetrelStream s) {
    setState(() {
      _stream = s;
      _indexStream();
      final code = _code;
      _code = null;
      if (code != null && _groups.values.any((g) => g.containsKey(code))) {
        _selectCode(code);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final stream = _stream;
    if (stream == null) {
      return const Center(child: Text('Dit record bevat geen intervaldata.'));
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 320, child: _buildPicker(context, stream)),
        const VerticalDivider(width: 1),
        Expanded(child: _buildChartPanel(context, stream)),
      ],
    );
  }

  Widget _buildPicker(BuildContext context, MetrelStream stream) {
    final theme = Theme.of(context);
    final query = _search.toLowerCase();
    final groupNames = _groups.keys.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: DropdownButtonFormField<MetrelStream>(
            initialValue: stream,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Interval',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            items: [
              for (final s in widget.record.streams)
                DropdownMenuItem(
                  value: s,
                  child: Text('${s.label} · ${s.recordCount} intervallen · '
                      '${s.descriptors.length} kolommen'),
                ),
            ],
            onChanged: (s) {
              if (s != null) _selectStream(s);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Zoek grootheid (bv. Urms, THD, P)',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _search = v),
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              for (final group in groupNames)
                if (_groups[group]!.values.where((e) => _matches(e, query))
                    case final entries when entries.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(group,
                        style: theme.textTheme.labelMedium
                            ?.copyWith(color: theme.colorScheme.primary)),
                  ),
                  for (final e in entries.toList()
                    ..sort((a, b) => a.info.code.compareTo(b.info.code)))
                    ListTile(
                      dense: true,
                      selected: e.info.code == _code,
                      title: Text(
                          '${e.info.symbol}${e.info.reference == 'abs' ? '' : ' [${e.info.reference}]'}'),
                      subtitle: Text(
                        '${e.info.longName}'
                        '${e.info.unit.isEmpty ? '' : ' · ${e.info.unit}'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => setState(() => _selectCode(e.info.code)),
                    ),
                ],
            ],
          ),
        ),
      ],
    );
  }

  bool _matches(_MeasurementEntry e, String query) =>
      query.isEmpty ||
      e.info.code.toLowerCase().contains(query) ||
      e.info.symbol.toLowerCase().contains(query) ||
      e.info.longName.toLowerCase().contains(query);

  Widget _buildChartPanel(BuildContext context, MetrelStream stream) {
    final entry = _entry;
    if (entry == null) {
      return const Center(child: Text('Kies links een grootheid.'));
    }
    final info = entry.info;
    final channels = entry.channels.toList()
      ..sort((a, b) => _channelOrder(a).compareTo(_channelOrder(b)));
    final aggregations = entry.aggregations.toList()..sort();
    final harmonics = entry.harmonics.toList()..sort();

    final selected = entry.descriptors
        .where((d) =>
            _channels.contains(d.info!.channel) &&
            _aggregations.contains(d.info!.aggregation) &&
            d.info!.harmonic == _harmonic)
        .take(_maxSeries)
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final ch in channels)
                  FilterChip(
                    label: Text(ch),
                    avatar: CircleAvatar(
                        backgroundColor: _channelColors[ch] ?? Colors.white),
                    selected: _channels.contains(ch),
                    onSelected: (on) => setState(() =>
                        on ? _channels.add(ch) : _channels.remove(ch)),
                  ),
                const SizedBox(width: 12),
                for (final agg in aggregations)
                  FilterChip(
                    label: Text(entry.aggregationNames[agg] ?? agg),
                    selected: _aggregations.contains(agg),
                    onSelected: (on) => setState(() =>
                        on ? _aggregations.add(agg) : _aggregations.remove(agg)),
                  ),
                if (harmonics.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  const Text('Orde'),
                  DropdownButton<int>(
                    value: _harmonic,
                    items: [
                      for (final h in harmonics)
                        DropdownMenuItem(value: h, child: Text('$h')),
                    ],
                    onChanged: (h) => setState(() => _harmonic = h),
                  ),
                ],
              ],
            ),
          ),
          _buildChart(context, stream, info, selected),
        ],
      ),
    );
  }

  static int _channelOrder(String ch) {
    const order = ['L1', 'L2', 'L3', 'Ln', 'L12', 'L23', 'L31', 'Tot', 'RefCh'];
    final i = order.indexOf(ch);
    return i < 0 ? order.length : i;
  }

  Widget _buildChart(BuildContext context, MetrelStream stream,
      MetrelMeasurementInfo info, List<MetrelDescriptor> selected) {
    final record = widget.record;
    final title =
        '${info.symbol}${_harmonic ?? ''} — ${info.longName} (${stream.label})';

    if (stream.recordCount == 0 || selected.isEmpty) {
      return ChartWrapper(
        title: title,
        isEmpty: true,
        emptyMessage: stream.recordCount == 0
            ? 'Dit interval bevat geen opgenomen data.'
            : 'Kies minstens één kanaal en aggregatie.',
        chartData: LineChartData(),
      );
    }

    final xs = [
      for (final t in stream.times)
        record.toRecordTime(t).millisecondsSinceEpoch.toDouble(),
    ];
    final step = math.max(1, (xs.length / _maxPoints).ceil());

    final bars = <LineChartBarData>[];
    final legend = <LegendItem>[];
    final stats = <(String, Color, double, double, double)>[];
    var minY = double.infinity;
    var maxY = double.negativeInfinity;

    for (final d in selected) {
      final i = d.info!;
      final values = stream.values(d.index);
      final color = _channelColors[i.channel] ?? Colors.white;
      final spots = <FlSpot>[
        for (var r = 0; r < values.length; r += step)
          values[r].isNaN ? FlSpot.nullSpot : FlSpot(xs[r], values[r]),
      ];

      final valid = values.where((v) => !v.isNaN);
      if (valid.isNotEmpty) {
        final lo = valid.reduce(math.min);
        final hi = valid.reduce(math.max);
        minY = math.min(minY, lo);
        maxY = math.max(maxY, hi);
        stats.add((
          i.label,
          color,
          lo,
          valid.reduce((a, b) => a + b) / valid.length,
          hi,
        ));
      }

      final dash = switch (i.aggregation) {
        'Min' => [6, 4],
        'Max' => [2, 3],
        _ => null,
      };
      bars.add(LineChartBarData(
        spots: spots,
        color: color,
        barWidth: 1.5,
        dashArray: dash,
        dotData: FlDotData(show: stream.recordCount <= 30),
      ));
      legend.add(LegendItem(label: i.label, color: color));
    }

    if (minY == double.infinity) {
      minY = 0;
      maxY = 1;
    }
    final pad = (maxY - minY).abs() < 1e-9
        ? math.max(1.0, maxY.abs() * 0.05)
        : (maxY - minY) * 0.08;
    minY -= pad;
    maxY += pad;

    final minX = xs.first;
    final maxX = xs.length > 1 ? xs.last : xs.first + 1000;
    final span = Duration(milliseconds: (maxX - minX).round());
    final axisFmt = span > const Duration(days: 2)
        ? DateFormat('d MMM HH:mm')
        : span > const Duration(hours: 2)
            ? DateFormat('HH:mm')
            : DateFormat('HH:mm:ss');
    String xLabel(double v) => axisFmt.format(
        DateTime.fromMillisecondsSinceEpoch(v.toInt(), isUtc: true));
    final unit = info.unit;

    final chartData = LineChartData(
      minX: minX,
      maxX: maxX,
      minY: minY,
      maxY: maxY,
      clipData: const FlClipData.all(),
      gridData: FlGridData(
        show: true,
        getDrawingHorizontalLine: (_) => const FlLine(
            color: Colors.white12, strokeWidth: 1, dashArray: [4, 4]),
        getDrawingVerticalLine: (_) =>
            const FlLine(color: Colors.white10, strokeWidth: 1),
      ),
      borderData: FlBorderData(show: true),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(
          axisNameWidget: Text(unit.isEmpty ? info.symbol : '${info.symbol} ($unit)',
              style: const TextStyle(fontSize: 11)),
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 56,
            interval: (maxY - minY) / 6,
            getTitlesWidget: (value, meta) => SideTitleWidget(
              meta: meta,
              child: Text(_formatValue(value),
                  style: const TextStyle(fontSize: 10)),
            ),
          ),
        ),
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 32,
            interval: math.max(1, (maxX - minX) / 6),
            getTitlesWidget: (value, meta) {
              if (value == meta.min || value == meta.max) {
                return const SizedBox.shrink();
              }
              return SideTitleWidget(
                meta: meta,
                child: Text(xLabel(value), style: const TextStyle(fontSize: 9)),
              );
            },
          ),
        ),
      ),
      lineBarsData: bars,
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => Colors.black87,
          fitInsideHorizontally: true,
          fitInsideVertically: true,
          getTooltipItems: (spots) => [
            for (final (n, s) in spots.indexed)
              LineTooltipItem(
                '${n == 0 ? '${_dateTimeFmt.format(DateTime.fromMillisecondsSinceEpoch(s.x.toInt(), isUtc: true))}\n' : ''}'
                '${legend[s.barIndex].label}: ${_formatValue(s.y)} $unit',
                TextStyle(color: bars[s.barIndex].color, fontSize: 11),
              ),
          ],
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChartWrapper(
          title: title,
          chartData: chartData,
          legendItems: legend,
          height: 360,
        ),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 36,
              dataRowMinHeight: 32,
              dataRowMaxHeight: 36,
              columns: [
                const DataColumn(label: Text('Reeks')),
                DataColumn(label: Text('Min ($unit)'), numeric: true),
                DataColumn(label: Text('Gem ($unit)'), numeric: true),
                DataColumn(label: Text('Max ($unit)'), numeric: true),
              ],
              rows: [
                for (final (label, color, lo, avg, hi) in stats)
                  DataRow(cells: [
                    DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(width: 12, height: 3, color: color),
                      const SizedBox(width: 8),
                      Text(label),
                    ])),
                    DataCell(Text(_formatValue(lo))),
                    DataCell(Text(_formatValue(avg))),
                    DataCell(Text(_formatValue(hi))),
                  ]),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Events ──────────────────────────────────────────────────────────────

class _EventsTab extends StatefulWidget {
  final MetrelRecord record;

  const _EventsTab({super.key, required this.record});

  @override
  State<_EventsTab> createState() => _EventsTabState();
}

class _EventsTabState extends State<_EventsTab> {
  late final Set<MetrelEventFamily> _families =
      widget.record.events.map((e) => e.family).toSet();

  @override
  Widget build(BuildContext context) {
    final record = widget.record;
    if (record.events.isEmpty) {
      return const Center(child: Text('Dit record bevat geen events.'));
    }
    final counts = <MetrelEventFamily, int>{};
    for (final e in record.events) {
      counts[e.family] = (counts[e.family] ?? 0) + 1;
    }
    final shown =
        record.events.where((e) => _families.contains(e.family)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final f in MetrelEventFamily.values)
                if (counts[f] != null)
                  FilterChip(
                    label: Text('${f.label} (${counts[f]})'),
                    selected: _families.contains(f),
                    onSelected: (on) => setState(
                        () => on ? _families.add(f) : _families.remove(f)),
                  ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Card(
              margin: EdgeInsets.zero,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('#'), numeric: true),
                    DataColumn(label: Text('Familie')),
                    DataColumn(label: Text('Begin')),
                    DataColumn(label: Text('Duur'), numeric: true),
                    DataColumn(label: Text('Type')),
                    DataColumn(label: Text('Kanalen')),
                    DataColumn(label: Text('Waarde'), numeric: true),
                    DataColumn(label: Text('Details')),
                  ],
                  rows: [
                    for (final e in shown)
                      DataRow(cells: [
                        DataCell(Text('${e.id}')),
                        DataCell(Text(e.family.label)),
                        DataCell(Text(
                            _eventTimeFmt.format(record.toRecordTime(e.start)))),
                        DataCell(Text(_formatDuration(e.duration))),
                        DataCell(Text(e.type)),
                        DataCell(Text(e.channels)),
                        DataCell(Text(e.magnitude == null
                            ? '—'
                            : '${_formatValue(e.magnitude!)} ${e.unit}')),
                        DataCell(Text(e.details)),
                      ]),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
