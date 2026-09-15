import 'dart:convert';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/measurement_data.dart';
import '../models/pqf_record.dart';
import '../providers/measurement_provider.dart';
import '../services/energy_analysis_parser.dart';
import '../services/xlsx_meter_parser.dart';
import '../widgets/time_range_selector.dart';

// ── Data definitions ──────────────────────────────────────────────────────────

class _Group {
  final String id;
  final String label;
  final String unit;
  final bool negativeY;
  const _Group(this.id, this.label, this.unit, {this.negativeY = false});
}

class _Series {
  final String id;
  final String label;
  final String groupId;
  final Color color;
  final bool defaultOn;
  final bool dashed;
  const _Series(this.id, this.label, this.groupId, this.color,
      {this.defaultOn = true, this.dashed = false});
}

const _groups = [
  _Group('voltage', 'Spanning', 'V'),
  _Group('current', 'Stroom', 'A'),
  _Group('power', 'Werkelijk vermogen', 'W', negativeY: true),
  _Group('reactive', 'Blindvermogen', 'VAr'),
  _Group('apparent', 'Schijnbaar vermogen', 'VA'),
  _Group('pf', 'Powerfactor', 'PF', negativeY: true),
  _Group('dailyImport', 'Dagelijkse afname', 'kWh'),
  _Group('dailySale', 'Dagelijkse teruglevering', 'kWh'),
  _Group('totalEnergy', 'Totaal energie', 'kWh'),
  _Group('solar', 'Zonnestraling', 'W/m²'),
  _Group('ea_power', 'Energie Analyse', 'W'),
  _Group('ea_soc', 'Accu SOC', '%'),
];

const _allSeries = [
  _Series('V_L1', 'L1', 'voltage', Colors.red),
  _Series('V_L2', 'L2', 'voltage', Colors.amber),
  _Series('V_L3', 'L3', 'voltage', Colors.blue),
  _Series('I_L1', 'L1', 'current', Colors.red),
  _Series('I_L2', 'L2', 'current', Colors.amber),
  _Series('I_L3', 'L3', 'current', Colors.blue),
  _Series('I_N', 'N (berekend)', 'current', Colors.green, dashed: true),
  _Series('P_total', 'Totaal', 'power', Colors.white70),
  _Series('P_L1', 'L1', 'power', Colors.red, defaultOn: false),
  _Series('P_L2', 'L2', 'power', Colors.amber, defaultOn: false),
  _Series('P_L3', 'L3', 'power', Colors.blue, defaultOn: false),
  _Series('Q_total', 'Totaal', 'reactive', Colors.purple),
  _Series('S_L1', 'L1', 'apparent', Colors.red),
  _Series('S_L2', 'L2', 'apparent', Colors.amber),
  _Series('S_L3', 'L3', 'apparent', Colors.blue),
  _Series('S_total', 'Totaal', 'apparent', Colors.white70, dashed: true),
  _Series('PF_L1', 'L1', 'pf', Colors.red),
  _Series('PF_L2', 'L2', 'pf', Colors.amber),
  _Series('PF_L3', 'L3', 'pf', Colors.blue),
  _Series('PF_total', 'Totaal', 'pf', Colors.white70, dashed: true),
  _Series('dayImport', 'Totaal', 'dailyImport', Colors.green, defaultOn: false),
  _Series('dayImportL1', 'L1', 'dailyImport', Colors.red, defaultOn: false),
  _Series('dayImportL2', 'L2', 'dailyImport', Colors.amber, defaultOn: false),
  _Series('dayImportL3', 'L3', 'dailyImport', Colors.blue, defaultOn: false),
  _Series('daySale', 'Totaal', 'dailySale', Colors.teal, defaultOn: false),
  _Series('daySaleL1', 'L1', 'dailySale', Colors.red, defaultOn: false),
  _Series('daySaleL2', 'L2', 'dailySale', Colors.amber, defaultOn: false),
  _Series('daySaleL3', 'L3', 'dailySale', Colors.blue, defaultOn: false),
  _Series('totalImport', 'Import', 'totalEnergy', Colors.green),
  _Series('totalExport', 'Export', 'totalEnergy', Colors.orange),
  _Series('solar_ghi', 'Globale straling', 'solar', Color(0xFFFFB300)),
  _Series('ea_pv', 'PV productie', 'ea_power', Color(0xFFFFB300)),
  _Series('ea_export', 'Export', 'ea_power', Colors.green),
  _Series('ea_selfCons', 'Eigen gebruik', 'ea_power', Color(0xFF8BC34A)),
  _Series('ea_load', 'Belasting', 'ea_power', Colors.orange),
  _Series('ea_import', 'Import', 'ea_power', Colors.red),
  _Series('ea_selfSuff', 'Zelfvz.', 'ea_power', Colors.teal, defaultOn: false),
  _Series('ea_charge', 'Laden', 'ea_power', Colors.blue, defaultOn: false),
  _Series('ea_discharge', 'Ontladen', 'ea_power', Colors.purple, defaultOn: false),
  _Series('ea_soc', 'SOC', 'ea_soc', Colors.cyan),
];

// Phasor-optelling: I_Lx lags V_Lx by φ_x = arccos(P_x/(V_x·I_x)); sin(φ) ≥ 0 altijd (φ ∈ [0°,180°]).
double? _calcNeutral(XlsxMeterRow row) {
  final i1 = row.iL1, i2 = row.iL2, i3 = row.iL3;
  final v1 = row.vL1, v2 = row.vL2, v3 = row.vL3;
  final p1 = row.pL1, p2 = row.pL2, p3 = row.pL3;

  if (i1 == null || i2 == null || i3 == null ||
      v1 == null || v2 == null || v3 == null ||
      p1 == null || p2 == null || p3 == null) {
    return null;
  }

  final s1 = v1 * i1, s2 = v2 * i2, s3 = v3 * i3;
  if (s1 == 0 || s2 == 0 || s3 == 0) {
    return null;
  }

  final c1 = (p1 / s1).clamp(-1.0, 1.0);
  final c2 = (p2 / s2).clamp(-1.0, 1.0);
  final c3 = (p3 / s3).clamp(-1.0, 1.0);

  final sin1 = sqrt(max(0.0, 1 - c1 * c1));
  final sin2 = sqrt(max(0.0, 1 - c2 * c2));
  final sin3 = sqrt(max(0.0, 1 - c3 * c3));

  const s3h = 0.8660254037844387; // √3/2

  // I_L1=I1·exp(−jφ1), I_L2=I2·exp(−j(120°+φ2)), I_L3=I3·exp(+j(120°−φ3))
  final re = i1 * c1 + i2 * (-c2 / 2 - s3h * sin2) + i3 * (-c3 / 2 + s3h * sin3);
  final im = i1 * (-sin1) + i2 * (-s3h * c2 + sin2 / 2) + i3 * (s3h * c3 + sin3 / 2);

  return sqrt(re * re + im * im);
}

double? _calcS(double? v, double? i) {
  if (v == null || i == null) return null;
  return v * i;
}

double? _calcSTotal(XlsxMeterRow row) {
  final s1 = _calcS(row.vL1, row.iL1);
  final s2 = _calcS(row.vL2, row.iL2);
  final s3 = _calcS(row.vL3, row.iL3);
  if (s1 == null || s2 == null || s3 == null) return null;
  return s1 + s2 + s3;
}

double? _calcPF(double? p, double? v, double? i) {
  if (p == null) return null;
  final s = _calcS(v, i);
  if (s == null || s == 0) return null;
  return (p / s).clamp(-1.0, 1.0);
}

double? _calcPFTotal(XlsxMeterRow row) {
  if (row.pTotal == null) return null;
  final s = _calcSTotal(row);
  if (s == null || s == 0) return null;
  return (row.pTotal! / s).clamp(-1.0, 1.0);
}

double? _getValue(XlsxMeterRow row, String id) => switch (id) {
      'V_L1' => row.vL1,
      'V_L2' => row.vL2,
      'V_L3' => row.vL3,
      'I_L1' => row.iL1,
      'I_L2' => row.iL2,
      'I_L3' => row.iL3,
      'P_total' => row.pTotal,
      'P_L1' => row.pL1,
      'P_L2' => row.pL2,
      'P_L3' => row.pL3,
      'Q_total' => row.qTotal,
      'dayImport' => row.dailyImport,
      'dayImportL1' => row.dailyImportL1,
      'dayImportL2' => row.dailyImportL2,
      'dayImportL3' => row.dailyImportL3,
      'daySale' => row.dailySale,
      'daySaleL1' => row.dailySaleL1,
      'daySaleL2' => row.dailySaleL2,
      'daySaleL3' => row.dailySaleL3,
      'totalImport' => row.totalImport,
      'totalExport' => row.totalExport,
      'I_N' => _calcNeutral(row),
      'S_L1' => _calcS(row.vL1, row.iL1),
      'S_L2' => _calcS(row.vL2, row.iL2),
      'S_L3' => _calcS(row.vL3, row.iL3),
      'S_total' => _calcSTotal(row),
      'PF_L1' => _calcPF(row.pL1, row.vL1, row.iL1),
      'PF_L2' => _calcPF(row.pL2, row.vL2, row.iL2),
      'PF_L3' => _calcPF(row.pL3, row.vL3, row.iL3),
      'PF_total' => _calcPFTotal(row),
      _ => null,
    };

double? _getEaValue(EnergyAnalysisRow row, String id) => switch (id) {
      'ea_pv' => row.pvPower,
      'ea_export' => row.exportPower,
      'ea_selfCons' => row.selfConsumption,
      'ea_load' => row.loadPower,
      'ea_import' => row.importPower,
      'ea_selfSuff' => row.selfSufficiency,
      'ea_charge' => row.charge,
      'ea_discharge' => row.discharge,
      'ea_soc' => row.soc,
      _ => null,
    };

// ── Screen ────────────────────────────────────────────────────────────────────

class MeterExcelScreen extends StatefulWidget {
  const MeterExcelScreen({super.key});

  @override
  State<MeterExcelScreen> createState() => _MeterExcelScreenState();
}

class _MeterExcelScreenState extends State<MeterExcelScreen> {
  List<XlsxMeterRow> _rows = [];
  bool _loading = false;
  String? _error;
  List<String> _fileNames = [];
  String? _lastDirectory;
  double _filterMinMs = 0;
  double _filterMaxMs = double.infinity;

  // ── Energy Analysis ──
  List<EnergyAnalysisRow> _eaRows = [];
  List<String> _eaFileNames = [];

  List<EnergyAnalysisRow> get _filteredEaRows => _eaRows.where((r) {
        final ms = r.time.millisecondsSinceEpoch.toDouble();
        return ms >= _filterMinMs && ms <= _filterMaxMs;
      }).toList();

  // ── Zonnestraling ──
  final _cityController = TextEditingController();
  List<(DateTime, double)>? _solarData;
  String? _solarLocation;
  bool _solarFetching = false;
  String? _solarError;

  List<XlsxMeterRow> get _filteredRows => _rows.where((r) {
        final ms = r.time.millisecondsSinceEpoch.toDouble();
        return ms >= _filterMinMs && ms <= _filterMaxMs;
      }).toList();

  late Map<String, bool> _enabled;

  @override
  void initState() {
    super.initState();
    _enabled = {
      for (final s in _allSeries) s.id: s.defaultOn,
    };
  }

  @override
  void dispose() {
    _cityController.dispose();
    super.dispose();
  }

  // ── Zonnestraling (Open-Meteo) ─────────────────────────────────────────────

  Future<void> _fetchSolar() async {
    final city = _cityController.text.trim();
    if (city.isEmpty || _rows.isEmpty) return;
    setState(() { _solarFetching = true; _solarError = null; });
    try {
      // 1. Geocoding
      final geoUri = Uri.parse(
        'https://geocoding-api.open-meteo.com/v1/search'
        '?name=${Uri.encodeComponent(city)}&count=1&language=nl&format=json',
      );
      final geoResp = await http.get(geoUri);
      if (geoResp.statusCode != 200) throw Exception('Geocoding mislukt (${geoResp.statusCode})');
      final geoJson = jsonDecode(geoResp.body) as Map<String, dynamic>;
      final results = geoJson['results'] as List?;
      if (results == null || results.isEmpty) throw Exception('Locatie "$city" niet gevonden');
      final lat = (results[0]['latitude'] as num).toDouble();
      final lon = (results[0]['longitude'] as num).toDouble();
      final foundName = '${results[0]['name']}, ${results[0]['country'] ?? ''}';

      // 2. Ophalen uurlijkse zonnestraling
      final fmt = DateFormat('yyyy-MM-dd');
      final startDate = fmt.format(_rows.first.time);
      final endDate   = fmt.format(_rows.last.time);
      final weatherUri = Uri.parse(
        'https://archive-api.open-meteo.com/v1/archive'
        '?latitude=$lat&longitude=$lon'
        '&start_date=$startDate&end_date=$endDate'
        '&hourly=shortwave_radiation'
        '&timezone=Europe%2FAmsterdam',
      );
      final wResp = await http.get(weatherUri);
      if (wResp.statusCode != 200) throw Exception('Stralingsdata mislukt (${wResp.statusCode})');
      final wJson = jsonDecode(wResp.body) as Map<String, dynamic>;
      final hourly    = wJson['hourly'] as Map<String, dynamic>;
      final times     = (hourly['time'] as List).cast<String>();
      final radiation = (hourly['shortwave_radiation'] as List)
          .map((v) => v == null ? 0.0 : (v as num).toDouble())
          .toList();

      final data = <(DateTime, double)>[
        for (int i = 0; i < times.length; i++)
          (DateTime.parse(times[i]), radiation[i]),
      ];
      setState(() {
        _solarData     = data;
        _solarLocation = foundName;
      });
    } catch (e) {
      setState(() => _solarError = e.toString());
    } finally {
      setState(() => _solarFetching = false);
    }
  }

  /// Lineaire interpolatie tussen uurswaarden van Open-Meteo.
  double? _interpolateSolar(DateTime time) {
    final data = _solarData;
    if (data == null || data.isEmpty) return null;
    final ms = time.millisecondsSinceEpoch;
    final idx = data.indexWhere((e) => e.$1.millisecondsSinceEpoch >= ms);
    if (idx < 0)  return data.last.$2;
    if (idx == 0) return data.first.$2;
    final t0 = data[idx - 1].$1.millisecondsSinceEpoch.toDouble();
    final t1 = data[idx].$1.millisecondsSinceEpoch.toDouble();
    if (t1 <= t0) return data[idx - 1].$2;
    final frac = (ms - t0) / (t1 - t0);
    return data[idx - 1].$2 + frac * (data[idx].$2 - data[idx - 1].$2);
  }

  // ── File picking ────────────────────────────────────────────────────────────

  Future<void> _pickEaFile({bool replace = true}) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: replace
          ? 'Open Energie Analyse Excel-export'
          : 'Voeg Energie Analyse bestand toe',
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      allowMultiple: true,
      initialDirectory: _lastDirectory,
    );
    if (result == null || result.files.isEmpty) return;

    final firstPath = result.files.first.path;
    if (firstPath != null) {
      final sep = firstPath.lastIndexOf('/');
      if (sep > 0) _lastDirectory = firstPath.substring(0, sep);
    }

    setState(() { _loading = true; _error = null; });
    try {
      final newRows = <EnergyAnalysisRow>[];
      for (final file in result.files) {
        if (file.path == null) continue;
        newRows.addAll(await EnergyAnalysisParser.parseFile(file.path!));
      }

      final combined = replace ? newRows : [..._eaRows, ...newRows];
      combined.sort((a, b) => a.time.compareTo(b.time));

      final seen = <DateTime>{};
      final deduped = [for (final r in combined) if (seen.add(r.time)) r];

      final newNames = result.files.map((f) => f.name).toList();

      setState(() {
        _eaRows = deduped;
        _eaFileNames = replace ? newNames : [..._eaFileNames, ...newNames];
        if (deduped.isNotEmpty) {
          final eaMin = deduped.first.time.millisecondsSinceEpoch.toDouble();
          final eaMax = deduped.last.time.millisecondsSinceEpoch.toDouble();
          if (_rows.isEmpty) {
            _filterMinMs = eaMin;
            _filterMaxMs = eaMax;
          } else {
            _filterMinMs = min(_filterMinMs, eaMin);
            _filterMaxMs = max(_filterMaxMs, eaMax);
          }
        }
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  // ── Conversie xlsx → MeasurementSession ────────────────────────────────────

  MeasurementSession _convertToSession() {
    MeasurementPoint toPoint(XlsxMeterRow r, Map<String, double?> kv) {
      final vals = <String, double>{};
      kv.forEach((k, v) { if (v != null) vals[k] = v; });
      return MeasurementPoint(time: r.time, values: vals);
    }

    final voltageData = _rows
        .map((r) => toPoint(r, {'V_L1': r.vL1, 'V_L2': r.vL2, 'V_L3': r.vL3}))
        .where((p) => p.values.isNotEmpty).toList();

    final currentData = _rows.map((r) => toPoint(r, {
          'I_L1': r.iL1, 'I_L2': r.iL2, 'I_L3': r.iL3,
          'I_N': _calcNeutral(r),
        })).where((p) => p.values.isNotEmpty).toList();

    final activePowerData = _rows
        .map((r) => toPoint(r, {
              'P_L1': r.pL1, 'P_L2': r.pL2, 'P_L3': r.pL3, 'P_total': r.pTotal,
            }))
        .where((p) => p.values.isNotEmpty).toList();

    final apparentPowerData = _rows
        .map((r) => toPoint(r, {
              'S_L1': _calcS(r.vL1, r.iL1),
              'S_L2': _calcS(r.vL2, r.iL2),
              'S_L3': _calcS(r.vL3, r.iL3),
              'S_total': _calcSTotal(r),
            }))
        .where((p) => p.values.isNotEmpty).toList();

    final reactivePowerData = _rows
        .map((r) => toPoint(r, {'Q_total': r.qTotal}))
        .where((p) => p.values.isNotEmpty).toList();

    final cosPhiData = _rows.map((r) {
      final pf1 = _calcPF(r.pL1, r.vL1, r.iL1);
      final pf2 = _calcPF(r.pL2, r.vL2, r.iL2);
      final pf3 = _calcPF(r.pL3, r.vL3, r.iL3);
      if (pf1 == null || pf2 == null || pf3 == null) return null;
      return CosPhiPoint(time: r.time, l1: pf1, l2: pf2, l3: pf3);
    }).whereType<CosPhiPoint>().toList();

    // Frequentie: xlsx-meter meet geen Hz → neem 50 Hz aan voor EN 50160.
    final frequencyData = _rows
        .map((r) => MeasurementPoint(time: r.time, values: {'Hz': 50.0}))
        .toList();

    final label = _fileNames.length == 1
        ? _fileNames.first
        : '${_fileNames.first} +${_fileNames.length - 1} meer';

    return MeasurementSession(
      deviceId: 'Energiemeter (xlsx)',
      location: label,
      startTime: _rows.first.time,
      endTime: _rows.last.time,
      voltageData: voltageData,
      currentData: currentData,
      frequencyData10min: frequencyData,
      frequencyData10s: const [],
      events: const [],
      cosPhiData: cosPhiData,
      activePowerData: activePowerData,
      apparentPowerData: apparentPowerData,
      reactivePowerData: reactivePowerData,
    );
  }

  Future<void> _pickFile({bool replace = true}) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: replace
          ? 'Open energiemeter Excel-export'
          : 'Voeg Excel-export toe',
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      allowMultiple: true,
      initialDirectory: _lastDirectory,
    );
    if (result == null || result.files.isEmpty) return;

    final firstPath = result.files.first.path;
    if (firstPath != null) {
      final sep = firstPath.lastIndexOf('/');
      if (sep > 0) _lastDirectory = firstPath.substring(0, sep);
    }

    setState(() { _loading = true; _error = null; });

    try {
      final newRows = <XlsxMeterRow>[];
      for (final file in result.files) {
        if (file.path == null) continue;
        newRows.addAll(await XlsxMeterParser.parseFile(file.path!));
      }

      final combined = replace ? newRows : [..._rows, ...newRows];
      combined.sort((a, b) => a.time.compareTo(b.time));

      // Deduplicate: bij gelijke timestamp de eerste rij bewaren.
      final seen = <DateTime>{};
      final deduped = [for (final r in combined) if (seen.add(r.time)) r];

      final newNames = result.files.map((f) => f.name).toList();

      setState(() {
        _rows = deduped;
        _fileNames = replace ? newNames : [..._fileNames, ...newNames];
        if (deduped.isNotEmpty) {
          _filterMinMs = deduped.first.time.millisecondsSinceEpoch.toDouble();
          _filterMaxMs = deduped.last.time.millisecondsSinceEpoch.toDouble();
        }
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        // ── Top bar ──
        Container(
          color: theme.colorScheme.surfaceContainer,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Icon(Icons.table_chart,
                  color: theme.colorScheme.primary, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _fileNames.isEmpty
                      ? 'Geen bestand geladen'
                      : _fileNames.length == 1
                          ? _fileNames.first
                          : '${_fileNames.first}  +${_fileNames.length - 1} meer  (${_rows.length} metingen)',
                  style: theme.textTheme.bodyMedium?.copyWith(
                      fontStyle: _fileNames.isEmpty
                          ? FontStyle.italic
                          : FontStyle.normal),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              if (_loading)
                const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 8),
              if (_rows.isNotEmpty) ...[
                OutlinedButton.icon(
                  onPressed: _loading ? null : () => _pickFile(replace: false),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Toevoegen'),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: _loading
                      ? null
                      : () {
                          final session = _convertToSession();
                          context
                              .read<MeasurementProvider>()
                              .loadXlsxSession(session, _fileNames.join(', '));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Data geladen in meetpagina\'s — '
                                'Spanning, Stroom en Cosφ zijn nu beschikbaar.',
                              ),
                              duration: Duration(seconds: 4),
                            ),
                          );
                        },
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.sync_alt, size: 18),
                      SizedBox(width: 6),
                      Text('Laad in meetpagina\'s'),
                    ],
                  ),
                ),
              ],
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _loading ? null : () => _pickFile(),
                icon: const Icon(Icons.upload_file, size: 18),
                label: const Text('Open xlsx'),
              ),
            ],
          ),
        ),
        // ── EA top bar ──
        Container(
          color: theme.colorScheme.surfaceContainerLow,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              Icon(Icons.solar_power_outlined,
                  color: theme.colorScheme.secondary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _eaFileNames.isEmpty
                      ? 'Geen Energie Analyse bestand geladen'
                      : _eaFileNames.length == 1
                          ? 'EA: ${_eaFileNames.first}  (${_eaRows.length} metingen)'
                          : 'EA: ${_eaFileNames.first}  +${_eaFileNames.length - 1} meer  (${_eaRows.length} metingen)',
                  style: theme.textTheme.bodySmall?.copyWith(
                      fontStyle: _eaFileNames.isEmpty
                          ? FontStyle.italic
                          : FontStyle.normal),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              if (_eaFileNames.isNotEmpty) ...[
                OutlinedButton.icon(
                  onPressed: _loading ? null : () => _pickEaFile(replace: false),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Toevoegen'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              FilledButton.tonal(
                onPressed: _loading ? null : () => _pickEaFile(),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontSize: 12),
                ),
                child: Text(_eaFileNames.isEmpty ? 'Open EA xlsx' : 'Vervangen'),
              ),
            ],
          ),
        ),
        if (_error != null)
          MaterialBanner(
            content: Text(_error!, style: const TextStyle(color: Colors.white)),
            backgroundColor: Colors.red.shade800,
            actions: [
              TextButton(
                onPressed: () => setState(() => _error = null),
                child: const Text('Sluiten',
                    style: TextStyle(color: Colors.white)),
              )
            ],
          ),

        // ── Content ──
        Expanded(
          child: (_rows.isEmpty && _eaRows.isEmpty)
              ? _buildEmpty(theme)
              : _buildContent(theme),
        ),
      ],
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.table_chart_outlined,
              size: 64, color: theme.colorScheme.outline),
          const SizedBox(height: 16),
          Text('Open een energiemeter Excel-export (.xlsx)',
              style: theme.textTheme.bodyLarge),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _pickFile,
            icon: const Icon(Icons.upload_file),
            label: const Text('Open xlsx'),
          ),
        ],
      ),
    );
  }

  // ── Content (met data) ─────────────────────────────────────────────────────

  Widget _buildContent(ThemeData theme) {
    // Determine overall time range across both datasets.
    final allMins = [
      if (_rows.isNotEmpty) _rows.first.time.millisecondsSinceEpoch.toDouble(),
      if (_eaRows.isNotEmpty) _eaRows.first.time.millisecondsSinceEpoch.toDouble(),
    ];
    final allMaxs = [
      if (_rows.isNotEmpty) _rows.last.time.millisecondsSinceEpoch.toDouble(),
      if (_eaRows.isNotEmpty) _eaRows.last.time.millisecondsSinceEpoch.toDouble(),
    ];
    final totalMinMs = allMins.reduce(min);
    final totalMaxMs = allMaxs.reduce(max);
    final fMin = _filterMinMs.clamp(totalMinMs, totalMaxMs);
    final fMax = _filterMaxMs.clamp(totalMinMs, totalMaxMs);

    return Column(
      children: [
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
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSolarCard(theme),
                const SizedBox(height: 12),
                _buildToggles(theme),
                const SizedBox(height: 16),
                ..._buildCharts(theme, fMin, fMax),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Toggle panel ───────────────────────────────────────────────────────────

  Widget _buildToggles(ThemeData theme) {
    return Card(
      child: ExpansionTile(
        initiallyExpanded: true,
        title: const Text('Grootheden'),
        leading: const Icon(Icons.tune),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _groups.map((g) {
                final seriesForGroup = _allSeries
                    .where((s) => s.groupId == g.id)
                    .toList();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 180,
                        child: Text(
                          '${g.label} (${g.unit})',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Expanded(
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: seriesForGroup.map((s) {
                            final on = _enabled[s.id] ?? false;
                            return FilterChip(
                              label: Text(s.label),
                              selected: on,
                              onSelected: (v) =>
                                  setState(() => _enabled[s.id] = v),
                              selectedColor: s.color.withValues(alpha: 0.25),
                              checkmarkColor: s.color,
                              labelStyle: TextStyle(
                                color: on ? s.color : null,
                                fontSize: 12,
                              ),
                              side: BorderSide(
                                color: on
                                    ? s.color
                                    : theme.colorScheme.outline
                                        .withValues(alpha: 0.4),
                              ),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              visualDensity: VisualDensity.compact,
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // ── Zonnestraling UI ───────────────────────────────────────────────────────

  Widget _buildSolarCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: [
            Icon(Icons.wb_sunny_outlined,
                size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _cityController,
                decoration: InputDecoration(
                  labelText: 'Locatie voor zonnestraling',
                  hintText: 'bijv. Maastricht',
                  helperText: _solarLocation != null
                      ? 'Geladen: $_solarLocation'
                      : null,
                  helperStyle: TextStyle(color: theme.colorScheme.primary),
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => _fetchSolar(),
              ),
            ),
            const SizedBox(width: 8),
            if (_solarFetching)
              const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
            else
              FilledButton.tonal(
                onPressed: _rows.isNotEmpty ? _fetchSolar : null,
                child: const Text('Ophalen'),
              ),
            if (_solarError != null) ...[
              const SizedBox(width: 8),
              Tooltip(
                message: _solarError!,
                child: const Icon(Icons.error_outline, color: Colors.redAccent),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Charts ─────────────────────────────────────────────────────────────────

  List<Widget> _buildCharts(ThemeData theme, double xMin, double xMax) {
    final rows = _filteredRows;
    final eaRows = _filteredEaRows;
    if (rows.isEmpty && eaRows.isEmpty) return [];
    final charts = <Widget>[];
    for (final g in _groups) {
      final active = _allSeries
          .where((s) => s.groupId == g.id && (_enabled[s.id] ?? false))
          .toList();
      if (active.isEmpty) continue;

      final isEaGroup = g.id == 'ea_power' || g.id == 'ea_soc';
      if (isEaGroup && eaRows.isEmpty) continue;
      if (!isEaGroup && rows.isEmpty) continue;

      // Build spot lists
      final lineBars = <LineChartBarData>[];
      double minY = double.infinity;
      double maxY = double.negativeInfinity;

      for (final s in active) {
        final spots = <FlSpot>[];
        if (isEaGroup) {
          for (final eaRow in eaRows) {
            final v = _getEaValue(eaRow, s.id);
            if (v != null && v.isFinite) {
              spots.add(FlSpot(eaRow.time.millisecondsSinceEpoch.toDouble(), v));
              if (v < minY) minY = v;
              if (v > maxY) maxY = v;
            }
          }
        } else {
          for (final row in rows) {
            final v = s.id == 'solar_ghi'
                ? _interpolateSolar(row.time)
                : _getValue(row, s.id);
            if (v != null && v.isFinite) {
              spots.add(FlSpot(row.time.millisecondsSinceEpoch.toDouble(), v));
              if (v < minY) minY = v;
              if (v > maxY) maxY = v;
            }
          }
        }
        if (spots.isEmpty) continue;
        lineBars.add(LineChartBarData(
          spots: spots,
          color: s.color,
          barWidth: 1.5,
          dotData: const FlDotData(show: false),
          isCurved: true,
          curveSmoothness: 0.1,
          dashArray: s.dashed ? [8, 5] : null,
        ));
      }

      if (lineBars.isEmpty) continue;

      // Y-axis range
      final double chartMinY;
      final double chartMaxY;
      if (g.id == 'pf') {
        chartMinY = -1.1;
        chartMaxY = 1.1;
      } else if (g.id == 'ea_soc') {
        chartMinY = 0;
        chartMaxY = 105;
      } else {
        final yPad = max(1.0, (maxY - minY) * 0.1);
        chartMinY = g.negativeY ? minY - yPad : 0.0;
        chartMaxY = maxY + yPad;
      }

      final xSpan = xMax - xMin;
      final xInterval = xSpan / 6;

      final labels = active.map((s) => (s.label, s.color, s.dashed)).toList();

      charts.add(Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 24, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${g.label} (${g.unit})',
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              // Legend
              Wrap(
                spacing: 16,
                runSpacing: 4,
                children: labels
                    .map((l) => Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CustomPaint(
                              size: const Size(20, 3),
                              painter: _LegendLinePainter(
                                  color: l.$2, dashed: l.$3),
                            ),
                            const SizedBox(width: 4),
                            Text(l.$1,
                                style: const TextStyle(fontSize: 12)),
                          ],
                        ))
                    .toList(),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 280,
                child: LineChart(
                  LineChartData(
                    lineBarsData: lineBars,
                    minY: chartMinY,
                    maxY: chartMaxY,
                    minX: xMin,
                    maxX: xMax,
                    clipData: const FlClipData.all(),
                    gridData: const FlGridData(show: true),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(
                      leftTitles: AxisTitles(
                        axisNameWidget: Text(g.unit,
                            style: const TextStyle(fontSize: 11)),
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 56,
                          getTitlesWidget: (v, meta) => SideTitleWidget(
                            meta: meta,
                            child: Text(
                              _formatY(v, g.unit),
                              style: const TextStyle(fontSize: 9),
                            ),
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
                          reservedSize: 32,
                          interval:
                              xInterval > 0 ? xInterval : 1,
                          getTitlesWidget: (v, meta) => SideTitleWidget(
                            meta: meta,
                            child: Text(
                              DateFormat('HH:mm').format(
                                  DateTime.fromMillisecondsSinceEpoch(
                                      v.toInt())),
                              style: const TextStyle(fontSize: 9),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                    ),
                    lineTouchData: LineTouchData(
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipColor: (_) => Colors.black87,
                        getTooltipItems: (spots) {
                          return spots.map((s) {
                            final lbl = s.barIndex < labels.length
                                ? labels[s.barIndex].$1
                                : '?';
                            final col = s.barIndex < labels.length
                                ? labels[s.barIndex].$2
                                : Colors.white;
                            return LineTooltipItem(
                              '$lbl: ${_formatY(s.y, g.unit)} ${g.unit}',
                              TextStyle(color: col, fontSize: 11),
                            );
                          }).toList();
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ));

      charts.add(const SizedBox(height: 12));
    }
    return charts;
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _formatY(double v, String unit) {
    if (unit == 'kWh') return v.toStringAsFixed(2);
    if (unit == 'VAr' || unit == 'W' || unit == 'VA') return v.toStringAsFixed(0);
    if (unit == 'PF') return v.toStringAsFixed(3);
    return v.toStringAsFixed(2);
  }
}

class _LegendLinePainter extends CustomPainter {
  final Color color;
  final bool dashed;
  const _LegendLinePainter({required this.color, required this.dashed});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final y = size.height / 2;
    if (!dashed) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    } else {
      const dash = 5.0, gap = 4.0;
      var x = 0.0;
      while (x < size.width) {
        canvas.drawLine(
            Offset(x, y), Offset((x + dash).clamp(0, size.width), y), paint);
        x += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_LegendLinePainter old) =>
      old.color != color || old.dashed != dashed;
}
