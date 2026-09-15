import 'dart:io';

import '../models/measurement_data.dart';
import '../models/pqf_record.dart';

/// Parser voor Chauvin Arnoux DataView (.dvb) bestanden.
///
/// Vereist mdbtools op het systeem:  brew install mdbtools
///
/// De DVB-bestanden zijn Microsoft Access (Jet 4) databases met drie tabellen:
///   Sessions   – sessie-metadata (starttijd, instrument-ID)
///   ChannelData – kanaaldata (naam, eenheid, starttijd, N samples, binary blob)
///   RevIndex   – versie-index (niet gebruikt)
///
/// Elke kanaalrij bevat:
///   SamplePoints  – aaneengesloten reeks van int32-LE waarden (hex-gecodeerd)
///   SampleMultiplier – schaalfactor: fysieke waarde = rawInt32 × multiplier
///   RecordDuration   – interval tussen samples in seconden
///   NumberOfSamples  – aantal samples
///   StartTime        – begintijdstip van de reeks
class QualistarDvbParser {
  /// Probeert mdb-export te vinden op gangbare locaties.
  static String? _findMdbExport() {
    const candidates = [
      '/opt/homebrew/bin/mdb-export', // Homebrew Apple Silicon
      '/usr/local/bin/mdb-export', // Homebrew Intel
      '/opt/local/bin/mdb-export', // MacPorts
      'mdb-export', // PATH
    ];
    for (final path in candidates) {
      final f = File(path);
      if (f.existsSync()) return path;
    }
    return null;
  }

  /// Parst een .dvb-bestand en retourneert een [MeasurementSession].
  Future<MeasurementSession> parseFile(String filePath) async {
    final mdbExport = _findMdbExport();
    if (mdbExport == null) {
      throw const FormatException(
        'mdbtools niet gevonden. Installeer via: brew install mdbtools',
      );
    }

    // --- Sessie-metadata ophalen ---
    final sessionResult = await Process.run(
      mdbExport,
      [filePath, 'Sessions'],
      stdoutEncoding: const SystemEncoding(),
    );
    final sessionRows = _parseCsv(sessionResult.stdout as String);
    String deviceId = 'C.A Qualistar+';
    DateTime? sessionStart;

    if (sessionRows.isNotEmpty) {
      final h = sessionRows[0];
      final rows = sessionRows.sublist(1);
      if (rows.isNotEmpty) {
        final r = _rowToMap(h, rows[0]);
        deviceId = (r['InstrumentID'] ?? 'C.A Qualistar+').split(' - ').first.trim();
        sessionStart = _parseDateTime(r['StartTime'] ?? '');
      }
    }

    // --- Kanaaldata ophalen (hex binary mode) ---
    final chanResult = await Process.run(
      mdbExport,
      ['-b', 'hex', filePath, 'ChannelData'],
      stdoutEncoding: const SystemEncoding(),
    );
    final chanRows = _parseCsv(chanResult.stdout as String);
    if (chanRows.length < 2) {
      throw const FormatException('Geen kanaaldata gevonden in DVB-bestand.');
    }

    final chanHeader = chanRows[0];
    final channels = <_Channel>[];

    for (final row in chanRows.sublist(1)) {
      final c = _parseChannel(_rowToMap(chanHeader, row));
      if (c != null) channels.add(c);
    }

    // --- Kanalen mappen op meettypes ---
    // Kanalen worden per meting-type gegroepeerd op timestamp.
    final voltageMap = <DateTime, Map<String, double>>{};
    final currentMap = <DateTime, Map<String, double>>{};
    final freqList = <MeasurementPoint>[];
    final powerActMap = <DateTime, Map<String, double>>{};
    final powerReacMap = <DateTime, Map<String, double>>{};
    final powerAppMap = <DateTime, Map<String, double>>{};
    final cosPhiMap = <DateTime, Map<String, double>>{};

    for (final ch in channels) {
      final key = ch.name;
      // Voltage kanalen: U1/U2/U3 (fase-fase) of V1/V2/V3 (fase-nul)
      // We gebruiken de eerste beschikbare naamgeving.
      final voltKey = _voltKey(key);
      final currKey = _currKey(key);

      if (voltKey != null) {
        _fillTimeMap(voltageMap, ch, voltKey);
      } else if (currKey != null) {
        _fillTimeMap(currentMap, ch, currKey);
      } else if (key == 'Frequency') {
        for (int i = 0; i < ch.samples.length; i++) {
          freqList.add(MeasurementPoint(
            time: ch.startTime.add(Duration(
              milliseconds: (i * ch.recordDurationSec * 1000).round(),
            )),
            values: {'Hz': ch.samples[i]},
          ));
        }
      } else if (_powerActKey(key) != null) {
        _fillTimeMap(powerActMap, ch, _powerActKey(key)!);
      } else if (_powerReacKey(key) != null) {
        _fillTimeMap(powerReacMap, ch, _powerReacKey(key)!);
      } else if (_powerAppKey(key) != null) {
        _fillTimeMap(powerAppMap, ch, _powerAppKey(key)!);
      } else if (_cosPhiKey(key) != null) {
        _fillTimeMap(cosPhiMap, ch, _cosPhiKey(key)!);
      }
    }

    // --- MeasurementPoints opbouwen ---
    final voltagePoints = _mapToPointsSorted(voltageMap);
    final currentPoints = _mapToPointsSorted(currentMap);
    final activePowerPoints = _buildPowerWithTotal(powerActMap, 'P_total');
    final reactivePowerPoints = _buildPowerWithTotal(powerReacMap, 'Q_total');
    final apparentPowerPoints = _buildPowerWithTotal(powerAppMap, 'S_total');

    // Cos phi → CosPhiPoint
    final cosPhiPoints = <CosPhiPoint>[];
    for (final entry in cosPhiMap.entries) {
      final v = entry.value;
      if (v.containsKey('L1') && v.containsKey('L2') && v.containsKey('L3')) {
        cosPhiPoints.add(CosPhiPoint(
          time: entry.key,
          l1: v['L1']!,
          l2: v['L2']!,
          l3: v['L3']!,
        ));
      }
    }
    cosPhiPoints.sort((a, b) => a.time.compareTo(b.time));

    // Tijdbereik bepalen
    final allTimes = [
      ...voltagePoints.map((p) => p.time),
      ...currentPoints.map((p) => p.time),
      ...freqList.map((p) => p.time),
    ];
    final startTime = sessionStart ??
        (allTimes.isNotEmpty
            ? allTimes.reduce((a, b) => a.isBefore(b) ? a : b)
            : DateTime.now());
    final endTime = allTimes.isNotEmpty
        ? allTimes.reduce((a, b) => a.isAfter(b) ? a : b)
        : startTime;

    return MeasurementSession(
      deviceId: deviceId,
      startTime: startTime,
      endTime: endTime,
      voltageData: voltagePoints,
      currentData: currentPoints,
      frequencyData10min: freqList,
      frequencyData10s: const [],
      events: const [],
      harmonicCurrentData: const [],
      cosPhiData: cosPhiPoints,
      activePowerData: activePowerPoints,
      reactivePowerData: reactivePowerPoints,
      apparentPowerData: apparentPowerPoints,
    );
  }

  // ---------------------------------------------------------------------------
  // Kanaalnaam → veldnaam mappings
  // ---------------------------------------------------------------------------

  static String? _voltKey(String name) => const {
        'U1 RMS': 'V_L1',
        'U2 RMS': 'V_L2',
        'U3 RMS': 'V_L3',
        'UN RMS': 'V_N',
        // Alternatieve naamgeving (Wattmeter / oudere firmware):
        'V1 RMS': 'V_L1',
        'V2 RMS': 'V_L2',
        'V3 RMS': 'V_L3',
        'VN RMS': 'V_N',
        'U1 RMS Max': 'V_L1_max',
        'U2 RMS Max': 'V_L2_max',
        'U3 RMS Max': 'V_L3_max',
        'U1 RMS Min': 'V_L1_min',
        'U2 RMS Min': 'V_L2_min',
        'U3 RMS Min': 'V_L3_min',
      }[name];

  static String? _currKey(String name) => const {
        'A1 RMS': 'I_L1',
        'A2 RMS': 'I_L2',
        'A3 RMS': 'I_L3',
        'AN RMS': 'I_N',
        'A1 RMS Max': 'I_L1_max',
        'A2 RMS Max': 'I_L2_max',
        'A3 RMS Max': 'I_L3_max',
        'A1 RMS Min': 'I_L1_min',
        'A2 RMS Min': 'I_L2_min',
        'A3 RMS Min': 'I_L3_min',
      }[name];

  static String? _powerActKey(String name) => const {
        'W1': 'P_L1',
        'W2': 'P_L2',
        'W3': 'P_L3',
        'W Total': 'P_total',
      }[name];

  static String? _powerReacKey(String name) => const {
        'VAR1': 'Q_L1',
        'VAR2': 'Q_L2',
        'VAR3': 'Q_L3',
        'VAR Total': 'Q_total',
      }[name];

  static String? _powerAppKey(String name) => const {
        'VA1': 'S_L1',
        'VA2': 'S_L2',
        'VA3': 'S_L3',
        'VA Total': 'S_total',
      }[name];

  static String? _cosPhiKey(String name) => const {
        'DPF1': 'L1',
        'DPF2': 'L2',
        'DPF3': 'L3',
        'PF1': 'L1',
        'PF2': 'L2',
        'PF3': 'L3',
      }[name];

  // ---------------------------------------------------------------------------
  // Hulpfuncties voor opbouwen tijdmappen
  // ---------------------------------------------------------------------------

  void _fillTimeMap(
    Map<DateTime, Map<String, double>> map,
    _Channel ch,
    String fieldKey,
  ) {
    for (int i = 0; i < ch.samples.length; i++) {
      final t = ch.startTime.add(Duration(
        milliseconds: (i * ch.recordDurationSec * 1000).round(),
      ));
      map.putIfAbsent(t, () => {})[fieldKey] = ch.samples[i];
    }
  }

  List<MeasurementPoint> _mapToPointsSorted(
      Map<DateTime, Map<String, double>> map) {
    return map.entries
        .map((e) => MeasurementPoint(time: e.key, values: e.value))
        .toList()
      ..sort((a, b) => a.time.compareTo(b.time));
  }

  /// Berekent P_total / Q_total / S_total als die niet als kanaal aanwezig zijn.
  List<MeasurementPoint> _buildPowerWithTotal(
    Map<DateTime, Map<String, double>> map,
    String totalKey,
  ) {
    return map.entries.map((e) {
      final v = Map<String, double>.from(e.value);
      if (!v.containsKey(totalKey)) {
        final l1 = v['${totalKey[0]}_L1'];
        final l2 = v['${totalKey[0]}_L2'];
        final l3 = v['${totalKey[0]}_L3'];
        if (l1 != null && l2 != null && l3 != null) {
          v[totalKey] = l1 + l2 + l3;
        }
      }
      return MeasurementPoint(time: e.key, values: v);
    }).toList()
      ..sort((a, b) => a.time.compareTo(b.time));
  }

  // ---------------------------------------------------------------------------
  // CSV parser (minimaal: behandelt geciteerde velden en komma's)
  // ---------------------------------------------------------------------------

  List<List<String>> _parseCsv(String text) {
    final rows = <List<String>>[];
    final lines = text.split('\n');
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      rows.add(_parseCsvRow(trimmed));
    }
    return rows;
  }

  List<String> _parseCsvRow(String line) {
    final fields = <String>[];
    final buf = StringBuffer();
    bool inQuote = false;
    for (int i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        if (inQuote && i + 1 < line.length && line[i + 1] == '"') {
          buf.write('"');
          i++;
        } else {
          inQuote = !inQuote;
        }
      } else if (ch == ',' && !inQuote) {
        fields.add(buf.toString());
        buf.clear();
      } else {
        buf.write(ch);
      }
    }
    fields.add(buf.toString());
    return fields;
  }

  Map<String, String> _rowToMap(List<String> header, List<String> row) {
    final m = <String, String>{};
    for (int i = 0; i < header.length && i < row.length; i++) {
      m[header[i]] = row[i];
    }
    return m;
  }

  // ---------------------------------------------------------------------------
  // Kanaalparsing
  // ---------------------------------------------------------------------------

  _Channel? _parseChannel(Map<String, String> r) {
    final name = r['ChannelName']?.trim() ?? '';
    if (name.isEmpty) return null;

    final nStr = r['NumberOfSamples']?.trim() ?? '0';
    final n = int.tryParse(nStr) ?? 0;
    if (n == 0) return null;

    final multStr = r['SampleMultiplier']?.trim() ?? '1';
    final mult = double.tryParse(multStr) ?? 1.0;

    final durStr = r['RecordDuration']?.trim() ?? '0';
    final dur = double.tryParse(durStr) ?? 0.0;

    final startStr = r['StartTime']?.trim() ?? '';
    final startTime = _parseDateTime(startStr) ?? DateTime.now();

    final spHex = r['SamplePoints']?.trim() ?? '';
    if (spHex.isEmpty) return null;

    final sizeStr = r['SampleSize']?.trim() ?? '4';
    final sampleSize = int.tryParse(sizeStr) ?? 4;

    final samples = _decodeSamples(spHex, n, sampleSize, mult);
    if (samples.isEmpty) return null;

    return _Channel(
      name: name,
      samples: samples,
      startTime: startTime,
      recordDurationSec: dur,
    );
  }

  List<double> _decodeSamples(
    String hexStr,
    int n,
    int sampleSize,
    double multiplier,
  ) {
    // mdb-export -b hex levert "0x<hexbytes>" op
    final raw = hexStr.startsWith('0x')
        ? hexStr.substring(2).toLowerCase()
        : hexStr.toLowerCase();

    if (raw.length < n * sampleSize * 2) return const [];

    final result = <double>[];
    for (int i = 0; i < n; i++) {
      final offset = i * sampleSize * 2;
      if (offset + sampleSize * 2 > raw.length) break;

      if (sampleSize == 4) {
        // int32 little-endian
        final b0 = int.parse(raw.substring(offset, offset + 2), radix: 16);
        final b1 = int.parse(raw.substring(offset + 2, offset + 4), radix: 16);
        final b2 = int.parse(raw.substring(offset + 4, offset + 6), radix: 16);
        final b3 = int.parse(raw.substring(offset + 6, offset + 8), radix: 16);
        int val = b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
        // Signed interpretatie
        if (val >= 0x80000000) val -= 0x100000000;
        result.add(val * multiplier);
      } else if (sampleSize == 2) {
        // int16 little-endian
        final b0 = int.parse(raw.substring(offset, offset + 2), radix: 16);
        final b1 = int.parse(raw.substring(offset + 2, offset + 4), radix: 16);
        int val = b0 | (b1 << 8);
        if (val >= 0x8000) val -= 0x10000;
        result.add(val * multiplier);
      }
    }
    return result;
  }

  // ---------------------------------------------------------------------------
  // Datum/tijd parsing: "MM/DD/YY HH:MM:SS" of "MM/DD/YYYY HH:MM:SS"
  // ---------------------------------------------------------------------------

  DateTime? _parseDateTime(String s) {
    if (s.isEmpty) return null;
    try {
      // Formaat: MM/DD/YY HH:MM:SS of MM/DD/YYYY HH:MM:SS
      final parts = s.split(' ');
      if (parts.length < 2) return null;
      final dateParts = parts[0].split('/');
      final timeParts = parts[1].split(':');
      if (dateParts.length < 3 || timeParts.length < 3) return null;

      final month = int.parse(dateParts[0]);
      final day = int.parse(dateParts[1]);
      int year = int.parse(dateParts[2]);
      if (year < 100) year += (year >= 70 ? 1900 : 2000);

      final hour = int.parse(timeParts[0]);
      final minute = int.parse(timeParts[1]);
      final second = int.parse(timeParts[2]);

      return DateTime(year, month, day, hour, minute, second);
    } catch (_) {
      return null;
    }
  }
}

/// Interne kanaalbeschrijving
class _Channel {
  final String name;
  final List<double> samples;
  final DateTime startTime;
  final double recordDurationSec;

  const _Channel({
    required this.name,
    required this.samples,
    required this.startTime,
    required this.recordDurationSec,
  });
}
