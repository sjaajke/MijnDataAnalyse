import 'dart:io';

import '../models/measurement_data.dart';
import '../models/pqf_record.dart';

/// Parser voor een map met PQ-Box 150 CSV-exports.
///
/// Een meting wordt door de PQ-Box software geëxporteerd als meerdere losse
/// CSV-bestanden in één map — bijv. `ITRMS_<meting>_IL1.csv` (stroom) of
/// `URTRM_<meting>_UL1.csv` (spanning). Elk bestand heeft een headerblok
/// gevolgd door een datablok met kolommen `Datum;Tijd;<kolom>;...`, waarbij
/// elke kolomnaam de fase en, indien van toepassing, de aggregatie bevat:
/// `IL1_[A]` (gemiddelde/RMS), `IL1_min_[A]`, `IL1_max_[A]`,
/// `IL1_max-200ms_[A]`, `IL1_max-sp_[A]`, `I_Neutral_[A]`, `UL1_max_[V]`,
/// `P_L1_[W]`, `P_total_max_[W]`, enz.
/// Eén bestand kan meerdere kolommen (en dus aggregaties) tegelijk bevatten.
///
/// Deze parser leest alle .csv-bestanden in de map, herkent de grootheden
/// aan de kolomkoppen en voegt alles samen tot één [MeasurementSession] op
/// basis van tijdstip. Onherkende kolommen/bestanden worden genegeerd.
class PqBoxCsvParser {
  Future<MeasurementSession> parseFolder(String folderPath) async {
    final dir = Directory(folderPath);
    if (!dir.existsSync()) {
      throw FormatException('Map niet gevonden: $folderPath');
    }

    final csvFiles = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.csv'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    if (csvFiles.isEmpty) {
      throw const FormatException(
          'Geen CSV-bestanden gevonden in de gekozen map.');
    }

    final voltageMap = <DateTime, Map<String, double>>{};
    final currentMap = <DateTime, Map<String, double>>{};
    final freqMap = <DateTime, Map<String, double>>{};
    final powerMap = <DateTime, Map<String, double>>{};

    String? deviceId;
    int filesUsed = 0;

    for (final file in csvFiles) {
      final lines = await file.readAsLines();

      String? serial;
      int headerIndex = -1;
      List<String>? columns;
      String delimiter = ';';

      for (int i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;
        if (serial == null) {
          final m = RegExp(r'Serienummer:\s*(.+)$').firstMatch(line);
          if (m != null) serial = m.group(1)!.trim();
        }
        final lower = line.toLowerCase();
        if (lower.startsWith('datum;tijd') || lower.startsWith('datum\ttijd')) {
          delimiter = lower.startsWith('datum\ttijd') ? '\t' : ';';
          columns = line.split(delimiter);
          headerIndex = i;
          break;
        }
      }

      if (columns == null) continue; // onherkend bestand, overslaan

      // Kolomindex → grootheid + veldnaam
      final mappings = <int, _ColumnMapping>{};
      for (int c = 2; c < columns.length; c++) {
        final mapping = _mapColumn(columns[c]);
        if (mapping != null) mappings[c] = mapping;
      }
      if (mappings.isEmpty) continue; // geen herkende grootheden

      deviceId ??= serial;
      filesUsed++;

      for (int i = headerIndex + 1; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;
        final fields = line.split(delimiter);
        if (fields.length < 3) continue;
        final time = _parseDateTime(fields[0], fields[1]);
        if (time == null) continue;

        for (final entry in mappings.entries) {
          if (entry.key >= fields.length) continue;
          final value =
              double.tryParse(fields[entry.key].trim().replaceAll(',', '.'));
          if (value == null) continue;
          final bucket = switch (entry.value.quantity) {
            _Quantity.current => currentMap,
            _Quantity.voltage => voltageMap,
            _Quantity.frequency => freqMap,
            _Quantity.power => powerMap,
          };
          bucket.putIfAbsent(time, () => {})[entry.value.fieldKey] = value;
        }
      }
    }

    if (filesUsed == 0) {
      throw const FormatException(
          'Geen herkende PQ-Box 150 CSV-bestanden gevonden in deze map.');
    }

    final voltagePoints = _mapToPoints(voltageMap);
    final currentPoints = _mapToPoints(currentMap);
    final freqPoints = _mapToPoints(freqMap);
    final powerPoints = _mapToPoints(powerMap);

    final allTimes = [
      ...voltagePoints.map((p) => p.time),
      ...currentPoints.map((p) => p.time),
      ...freqPoints.map((p) => p.time),
      ...powerPoints.map((p) => p.time),
    ];
    final startTime = allTimes.isNotEmpty
        ? allTimes.reduce((a, b) => a.isBefore(b) ? a : b)
        : DateTime.now();
    final endTime = allTimes.isNotEmpty
        ? allTimes.reduce((a, b) => a.isAfter(b) ? a : b)
        : startTime;

    return MeasurementSession(
      deviceId: deviceId ?? 'PQ-Box 150',
      startTime: startTime,
      endTime: endTime,
      voltageData: voltagePoints,
      currentData: currentPoints,
      frequencyData10min: const [],
      frequencyData10s: freqPoints,
      events: const [],
      activePowerData: powerPoints,
    );
  }

  // ---------------------------------------------------------------------
  // Kolomnaam → grootheid + veldnaam
  // ---------------------------------------------------------------------

  /// Herkent kolomkoppen als "IL1_[A]", "IL1_min_[A]", "IL1_max-200ms_[A]",
  /// "I_Neutral_[A]", "UL1_max_[V]", "F_[Hz]", enz. De aggregatie (min/max/
  /// max-200ms/max-sp/...) zit als suffix ín de kolomnaam zelf, vóór de
  /// eenheid, en verschilt dus per kolom — niet per bestand.
  _ColumnMapping? _mapColumn(String header) {
    // Strip eenheid, bv. "IL1_max_[A]" → "IL1_max"
    var base = header.trim();
    final unitIdx = base.indexOf('_[');
    if (unitIdx != -1) base = base.substring(0, unitIdx);

    final upper = base.toUpperCase();
    if (upper == 'F' || upper == 'FREQ' || upper == 'FREQUENTIE') {
      return _ColumnMapping(_Quantity.frequency, 'Hz');
    }

    final phase = RegExp(r'^([IU])_?L?(12|23|31|1|2|3)(?:_(.+))?$',
            caseSensitive: false)
        .firstMatch(base);
    if (phase != null) {
      final isCurrent = phase.group(1)!.toUpperCase() == 'I';
      final quantity = isCurrent ? _Quantity.current : _Quantity.voltage;
      final prefix = isCurrent ? 'I' : 'V';
      final agg = _aggSuffix(phase.group(3));
      return _ColumnMapping(quantity, '${prefix}_L${phase.group(2)}$agg');
    }

    final neutral =
        RegExp(r'^([IU])_?Neutral(?:_(.+))?$', caseSensitive: false)
            .firstMatch(base);
    if (neutral != null) {
      final isCurrent = neutral.group(1)!.toUpperCase() == 'I';
      final quantity = isCurrent ? _Quantity.current : _Quantity.voltage;
      final prefix = isCurrent ? 'I' : 'V';
      final agg = _aggSuffix(neutral.group(2));
      return _ColumnMapping(quantity, '${prefix}_N$agg');
    }

    // Vermogen: "P_L1_[W]", "P_total_[W]", "P_L1_max_[W]", "P_total_min_[W]".
    // De absolute-waarde kolommen "|P_L1|_[W]" e.d. matchen hier bewust niet
    // (ze zouden dezelfde tijd/veldnaam overschrijven met de |.|-waarde).
    final power = RegExp(r'^P_(L1|L2|L3|total)(?:_(.+))?$', caseSensitive: false)
        .firstMatch(base);
    if (power != null) {
      final phase = power.group(1)!.toLowerCase() == 'total'
          ? 'total'
          : power.group(1)!.toUpperCase();
      final agg = _aggSuffix(power.group(2));
      return _ColumnMapping(_Quantity.power, 'P_$phase$agg');
    }

    return null;
  }

  /// Geeft "" voor de gemiddelde/RMS-waarde, anders "_min", "_max",
  /// "_max200ms", "_maxsp", enz.
  String _aggSuffix(String? token) {
    if (token == null || token.isEmpty) return '';
    return '_${token.toLowerCase().replaceAll('-', '')}';
  }

  // ---------------------------------------------------------------------
  // Datum/tijd: "02.07.2026" + "09:48:20.000"
  // ---------------------------------------------------------------------

  DateTime? _parseDateTime(String datePart, String timePart) {
    final d = datePart.trim().split(RegExp(r'[.\-]'));
    if (d.length != 3) return null;
    final t = timePart.trim().split(':');
    if (t.length != 3) return null;
    try {
      final day = int.parse(d[0]);
      final month = int.parse(d[1]);
      final year = int.parse(d[2]);
      final hour = int.parse(t[0]);
      final minute = int.parse(t[1]);
      final secParts = t[2].split('.');
      final second = int.parse(secParts[0]);
      final ms = secParts.length > 1
          ? int.parse(secParts[1].padRight(3, '0').substring(0, 3))
          : 0;
      return DateTime(year, month, day, hour, minute, second, ms);
    } catch (_) {
      return null;
    }
  }

  List<MeasurementPoint> _mapToPoints(Map<DateTime, Map<String, double>> map) {
    return map.entries
        .map((e) => MeasurementPoint(time: e.key, values: e.value))
        .toList()
      ..sort((a, b) => a.time.compareTo(b.time));
  }
}

enum _Quantity { current, voltage, frequency, power }

class _ColumnMapping {
  final _Quantity quantity;
  final String fieldKey;
  const _ColumnMapping(this.quantity, this.fieldKey);
}
