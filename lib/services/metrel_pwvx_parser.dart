import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../models/measurement_data.dart';
import '../models/pqf_record.dart';

/// Parser for Metrel MI 2890/2892/2992 PowerView (.pwvx) files.
///
/// PWVX files are ZIP archives containing one or more recording directories
/// under `records/`. Each recording has:
///   - `instrumentInfo.json` — device model, serial, firmware
///   - `measurement_settings.json` — connection type, nominal voltage
///   - `recorder_settings.json` — recording profile, timezone
///   - `log.jsonl` — recorder start/stop timestamps
///   - `periodics/` — aggregated measurement data at various intervals
///
/// Periodics data structure (per interval, e.g. 600s = 10 min):
///   `{N}s_meta`       — column descriptors (8 bytes each)
///   `{N}s_data_000`   — float32 array, records × activeColumns
///   `{N}s_timeStamps` — int64 nanoseconds-since-epoch per record
///
/// Meta descriptor format (8 bytes each, starting at offset 22):
///   [nVals:1][dtype:1][vsize:1][marker:1][agg:1][phase:1][channel:2]
///   Descriptors with marker == 0x00 are inactive (no data column).
///   Each active descriptor maps to exactly one float32 in the data.
///
/// Channel IDs (little-endian uint16 in meta descriptors):
///   0x0041–0x0043  U1/U2/U3 phase voltage (V)
///   0x0044         UN neutral voltage (V)
///   0x0045–0x0047  U12/U23/U31 line-line voltage (V)
///   0x0201–0x0204  I1/I2/I3/IN current (mA)
///   0x0dc1–0x0dc3  I1/I2/I3 harmonics h1–h26 (mA)
///   0x1089         Frequency (Hz)
///   0x0249         Frequency 10 s (Hz)
class MetrelPwvxParser {
  // Aggregation types in meta descriptors
  static const int _aggMin = 1;
  static const int _aggMax = 2;
  static const int _aggAvg = 3;

  // Channel IDs
  static const int _chU1 = 0x0041;
  static const int _chU2 = 0x0042;
  static const int _chU3 = 0x0043;
  static const int _chU12 = 0x0045;
  static const int _chU23 = 0x0046;
  static const int _chU31 = 0x0047;
  static const int _chI1 = 0x0201;
  static const int _chI2 = 0x0202;
  static const int _chI3 = 0x0203;
  static const int _chIN = 0x0204;
  static const int _chFreq = 0x1089;
  static const int _chFreq10s = 0x0249;
  static const int _chHarmI1 = 0x0dc1;
  static const int _chHarmI2 = 0x0dc2;
  static const int _chHarmI3 = 0x0dc3;

  Future<MeasurementSession> parseFile(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    // Find the record directory (first directory under records/)
    final recordDir = _findRecordDir(archive);
    if (recordDir == null) {
      throw const FormatException('No recording found in PWVX file');
    }

    // Parse instrument info
    final instrJson = _readJson(archive, '$recordDir/instrumentInfo.json');
    final deviceId = instrJson != null
        ? '${instrJson['model'] ?? 'Metrel'} ${instrJson['serialNumber'] ?? ''}'
            .trim()
        : 'Metrel';

    // Parse recorder settings for timezone
    final recorderJson =
        _readJson(archive, '$recordDir/recorder_settings.json');
    final utcOffsetHours = _parseUtcOffset(recorderJson);

    // Parse log for start/end times
    final logData = _readFile(archive, '$recordDir/log.jsonl');
    DateTime? logStart, logEnd;
    if (logData != null) {
      final lines = utf8.decode(logData).trim().split('\n');
      for (final line in lines) {
        final j = jsonDecode(line) as Map<String, dynamic>;
        final ts = DateTime.parse(j['timestamp'] as String);
        if ((j['message'] as String).contains('start')) logStart = ts;
        if ((j['message'] as String).contains('stop')) logEnd = ts;
      }
    }

    final voltagePoints = <MeasurementPoint>[];
    final currentPoints = <MeasurementPoint>[];
    final freqPoints10min = <MeasurementPoint>[];
    final harmonicPoints = <HarmonicPoint>[];

    // Try intervals in order of preference for main PQ data.
    // Different recorder profiles use different intervals:
    //   EN 50160 profile → 600s (10 min)
    //   Energy Demand    → 300s (5 min) or 60s (1 min)
    // We pick the first interval that contains voltage channels.
    for (final interval in ['600s', '300s', '60s']) {
      final meta = _readFile(archive, '$recordDir/periodics/${interval}_meta');
      final data =
          _readFile(archive, '$recordDir/periodics/${interval}_data_000');
      final tsData = _readFile(
          archive, '$recordDir/periodics/${interval}_timeStamps');
      if (meta == null || data == null || tsData == null) continue;

      final columns = _parseMetaDescriptors(meta);
      // Only use this interval if it has voltage data
      if (_findColumn(columns, _chU1, _aggAvg, phase: 0) == null) continue;

      _extractPeriodicData(
        columns: columns,
        data: data,
        tsData: tsData,
        utcOffsetHours: utcOffsetHours,
        voltagePoints: voltagePoints,
        currentPoints: currentPoints,
        freqPoints: freqPoints10min,
        harmonicPoints: harmonicPoints,
      );
      break; // Use only the first interval that has voltage data
    }

    // Parse 10s periodics — frequency
    final meta10 = _readFile(archive, '$recordDir/periodics/10s_meta');
    final data10 = _readFile(archive, '$recordDir/periodics/10s_data_000');
    final ts10 = _readFile(archive, '$recordDir/periodics/10s_timeStamps');

    final freqPoints10s = <MeasurementPoint>[];

    if (meta10 != null && data10 != null && ts10 != null) {
      final columns10 = _parseMetaDescriptors(meta10);
      final numRecords10 = ts10.length ~/ 8;
      final numCols10 = columns10.length;
      final tsBd10 = ByteData.sublistView(ts10);
      final dataBd10 = ByteData.sublistView(data10);

      // Find frequency column — try multiple agg types
      int? freqCol = _findColumn(columns10, _chFreq10s, _aggAvg, phase: 0);
      freqCol ??= _findColumn(columns10, _chFreq10s, 5, phase: 0);

      if (freqCol != null) {
        for (int r = 0; r < numRecords10; r++) {
          final dataOffset = r * numCols10 * 4;
          if (dataOffset + numCols10 * 4 > data10.length) break;

          final nsEpoch = tsBd10.getInt64(r * 8, Endian.little);
          final time = DateTime.fromMicrosecondsSinceEpoch(
            nsEpoch ~/ 1000,
            isUtc: true,
          ).add(Duration(hours: utcOffsetHours));

          final hz =
              dataBd10.getFloat32(dataOffset + freqCol * 4, Endian.little);
          freqPoints10s.add(MeasurementPoint(time: time, values: {'Hz': hz}));
        }
      }
    }

    // Determine time range
    final allTimes = [
      ...voltagePoints.map((p) => p.time),
      ...currentPoints.map((p) => p.time),
      ...freqPoints10min.map((p) => p.time),
      ...freqPoints10s.map((p) => p.time),
    ];
    final startTime = allTimes.isNotEmpty
        ? allTimes.reduce((a, b) => a.isBefore(b) ? a : b)
        : (logStart ?? DateTime.now());
    final endTime = allTimes.isNotEmpty
        ? allTimes.reduce((a, b) => a.isAfter(b) ? a : b)
        : (logEnd ?? DateTime.now());

    return MeasurementSession(
      deviceId: deviceId,
      startTime: startTime,
      endTime: endTime,
      voltageData: voltagePoints,
      currentData: currentPoints,
      frequencyData10min: freqPoints10min,
      frequencyData10s: freqPoints10s,
      events: [],
      harmonicCurrentData: harmonicPoints,
    );
  }

  void _extractPeriodicData({
    required List<_ColumnDef> columns,
    required Uint8List data,
    required Uint8List tsData,
    required int utcOffsetHours,
    required List<MeasurementPoint> voltagePoints,
    required List<MeasurementPoint> currentPoints,
    required List<MeasurementPoint> freqPoints,
    required List<HarmonicPoint> harmonicPoints,
  }) {
    final numRecords = tsData.length ~/ 8;
    final numCols = columns.length;
    final tsBd = ByteData.sublistView(tsData);
    final dataBd = ByteData.sublistView(data);

    for (int r = 0; r < numRecords; r++) {
      final nsEpoch = tsBd.getInt64(r * 8, Endian.little);
      final time = DateTime.fromMicrosecondsSinceEpoch(
        nsEpoch ~/ 1000,
        isUtc: true,
      ).add(Duration(hours: utcOffsetHours));

      final dataOffset = r * numCols * 4;
      if (dataOffset + numCols * 4 > data.length) break;

      // Voltage
      final vMap = <String, double>{};
      _addValue(vMap, 'V_L1', columns, dataBd, dataOffset, _chU1, _aggAvg);
      _addValue(vMap, 'V_L2', columns, dataBd, dataOffset, _chU2, _aggAvg);
      _addValue(vMap, 'V_L3', columns, dataBd, dataOffset, _chU3, _aggAvg);
      _addValue(vMap, 'V_L1_min', columns, dataBd, dataOffset, _chU1, _aggMin);
      _addValue(vMap, 'V_L1_max', columns, dataBd, dataOffset, _chU1, _aggMax);
      _addValue(vMap, 'V_L2_min', columns, dataBd, dataOffset, _chU2, _aggMin);
      _addValue(vMap, 'V_L2_max', columns, dataBd, dataOffset, _chU2, _aggMax);
      _addValue(vMap, 'V_L3_min', columns, dataBd, dataOffset, _chU3, _aggMin);
      _addValue(vMap, 'V_L3_max', columns, dataBd, dataOffset, _chU3, _aggMax);
      _addValue(vMap, 'V_L12', columns, dataBd, dataOffset, _chU12, _aggAvg);
      _addValue(vMap, 'V_L23', columns, dataBd, dataOffset, _chU23, _aggAvg);
      _addValue(vMap, 'V_L31', columns, dataBd, dataOffset, _chU31, _aggAvg);
      if (vMap.isNotEmpty) {
        voltagePoints.add(MeasurementPoint(time: time, values: vMap));
      }

      // Current (Metrel stores in mA, convert to A)
      final iMap = <String, double>{};
      _addValueScaled(
          iMap, 'I_L1', columns, dataBd, dataOffset, _chI1, _aggAvg, 0.001);
      _addValueScaled(
          iMap, 'I_L2', columns, dataBd, dataOffset, _chI2, _aggAvg, 0.001);
      _addValueScaled(
          iMap, 'I_L3', columns, dataBd, dataOffset, _chI3, _aggAvg, 0.001);
      _addValueScaled(
          iMap, 'I_N', columns, dataBd, dataOffset, _chIN, _aggAvg, 0.001);
      _addValueScaled(
          iMap, 'I_L1_min', columns, dataBd, dataOffset, _chI1, _aggMin, 0.001);
      _addValueScaled(
          iMap, 'I_L1_max', columns, dataBd, dataOffset, _chI1, _aggMax, 0.001);
      _addValueScaled(
          iMap, 'I_L2_min', columns, dataBd, dataOffset, _chI2, _aggMin, 0.001);
      _addValueScaled(
          iMap, 'I_L2_max', columns, dataBd, dataOffset, _chI2, _aggMax, 0.001);
      _addValueScaled(
          iMap, 'I_L3_min', columns, dataBd, dataOffset, _chI3, _aggMin, 0.001);
      _addValueScaled(
          iMap, 'I_L3_max', columns, dataBd, dataOffset, _chI3, _aggMax, 0.001);
      _addValueScaled(
          iMap, 'I_N_min', columns, dataBd, dataOffset, _chIN, _aggMin, 0.001);
      _addValueScaled(
          iMap, 'I_N_max', columns, dataBd, dataOffset, _chIN, _aggMax, 0.001);
      if (iMap.isNotEmpty) {
        currentPoints.add(MeasurementPoint(time: time, values: iMap));
      }

      // Frequency — try agg=avg first, then agg=5 (used by some models)
      int? fCol = _findColumn(columns, _chFreq, _aggAvg, phase: 0);
      fCol ??= _findColumn(columns, _chFreq, 5, phase: 0);
      if (fCol != null) {
        final hz = dataBd.getFloat32(dataOffset + fCol * 4, Endian.little);
        freqPoints.add(MeasurementPoint(time: time, values: {'Hz': hz}));
      }

      // Current harmonics h2..h26 per phase (mA → A)
      final l1h = _extractHarmonics(columns, dataBd, dataOffset, _chHarmI1);
      final l2h = _extractHarmonics(columns, dataBd, dataOffset, _chHarmI2);
      final l3h = _extractHarmonics(columns, dataBd, dataOffset, _chHarmI3);
      if (l1h != null && l2h != null && l3h != null) {
        harmonicPoints.add(HarmonicPoint(
          time: time,
          l1: l1h,
          l2: l2h,
          l3: l3h,
        ));
      }
    }
  }

  /// Finds the first record directory path inside the archive.
  String? _findRecordDir(Archive archive) {
    for (final file in archive.files) {
      if (file.name.contains('/instrumentInfo.json')) {
        return file.name.substring(0, file.name.lastIndexOf('/'));
      }
    }
    return null;
  }

  /// Reads a file from the archive as bytes.
  Uint8List? _readFile(Archive archive, String path) {
    for (final file in archive.files) {
      if (file.name == path) {
        return Uint8List.fromList(file.content);
      }
    }
    return null;
  }

  /// Reads and parses a JSON file from the archive.
  Map<String, dynamic>? _readJson(Archive archive, String path) {
    final data = _readFile(archive, path);
    if (data == null) return null;
    return jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
  }

  /// Extracts the UTC offset in hours from recorder_settings.json.
  int _parseUtcOffset(Map<String, dynamic>? recorderJson) {
    if (recorderJson == null) return 0;
    try {
      final offset = recorderJson['recorderSettings']?['recordInfo']
          ?['utcOffset']?['value'] as String?;
      if (offset == null) return 0;
      // Format: "UTC + 01:00" or "UTC - 05:00"
      final match = RegExp(r'UTC\s*([+-])\s*(\d+):(\d+)').firstMatch(offset);
      if (match == null) return 0;
      final sign = match.group(1) == '+' ? 1 : -1;
      return sign * int.parse(match.group(2)!);
    } catch (_) {
      return 0;
    }
  }

  /// Parses meta descriptors into a list of active column definitions.
  ///
  /// Each descriptor is 8 bytes. Descriptors with marker byte (offset +3)
  /// equal to 0x00 are inactive and do not correspond to a data column.
  /// Only active (non-0x00 marker) descriptors are returned.
  List<_ColumnDef> _parseMetaDescriptors(Uint8List meta) {
    final columns = <_ColumnDef>[];
    final bd = ByteData.sublistView(meta);
    int offset = 22;
    while (offset + 8 <= meta.length) {
      final marker = meta[offset + 3];
      if (marker != 0x00) {
        final agg = meta[offset + 4];
        final phase = meta[offset + 5];
        final channel = bd.getUint16(offset + 6, Endian.little);
        columns.add(_ColumnDef(channel: channel, agg: agg, phase: phase));
      }
      offset += 8;
    }
    return columns;
  }

  /// Finds the column index for a given channel + aggregation type.
  int? _findColumn(List<_ColumnDef> columns, int channel, int agg,
      {int phase = 0}) {
    for (int i = 0; i < columns.length; i++) {
      final c = columns[i];
      if (c.channel == channel && c.agg == agg && c.phase == phase) return i;
    }
    return null;
  }

  /// Reads a float32 value from data and adds it to the map.
  void _addValue(
      Map<String, double> map,
      String key,
      List<_ColumnDef> columns,
      ByteData data,
      int recordOffset,
      int channel,
      int agg) {
    final col = _findColumn(columns, channel, agg, phase: 0);
    if (col == null) return;
    final byteOffset = recordOffset + col * 4;
    if (byteOffset + 4 > data.lengthInBytes) return;
    final value = data.getFloat32(byteOffset, Endian.little);
    if (value.isNaN) return;
    map[key] = value;
  }

  /// Reads a float32 value, applies a scale factor, and adds to the map.
  void _addValueScaled(
      Map<String, double> map,
      String key,
      List<_ColumnDef> columns,
      ByteData data,
      int recordOffset,
      int channel,
      int agg,
      double scale) {
    final col = _findColumn(columns, channel, agg, phase: 0);
    if (col == null) return;
    final byteOffset = recordOffset + col * 4;
    if (byteOffset + 4 > data.lengthInBytes) return;
    final value = data.getFloat32(byteOffset, Endian.little);
    if (value.isNaN) return;
    map[key] = value * scale;
  }

  /// Extracts current harmonics h2..h31 (avg, in A) for one phase channel.
  /// Returns 30 values (h2–h31), with zeros for h27–h31 (not in file).
  List<double>? _extractHarmonics(List<_ColumnDef> columns, ByteData data,
      int recordOffset, int channel) {
    // Harmonic channels use phase 1=h1, 2=h2, ..., 26=h26
    // We need h2..h26 (phases 2–26), pad h27–h31 with 0
    final result = <double>[];
    for (int h = 2; h <= 31; h++) {
      if (h <= 26) {
        final col = _findColumn(columns, channel, _aggAvg, phase: h);
        if (col == null) return null;
        final byteOffset = recordOffset + col * 4;
        if (byteOffset + 4 > data.lengthInBytes) return null;
        // Convert mA to A
        result.add(data.getFloat32(byteOffset, Endian.little) * 0.001);
      } else {
        result.add(0.0);
      }
    }
    return result;
  }
}

/// Describes one active data column in a periodics data file.
class _ColumnDef {
  final int channel;
  final int agg;
  final int phase;

  const _ColumnDef({
    required this.channel,
    required this.agg,
    required this.phase,
  });
}
