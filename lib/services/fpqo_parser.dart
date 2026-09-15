import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../models/measurement_data.dart';
import '../models/pqf_record.dart';

/// Parser for Fluke 435-II `.fpqo` binary measurement files.
///
/// File layout:
///   [text/XML header, ~0x412 bytes]
///   [data blocks, each block = 1 minute of data]
///
/// Each block:
///   Group 0 (voltage): [8-byte OLE float64 ts][4-byte uint32 count][records]
///   Group 1..34:       [1-byte prefix][8-byte OLE float64 ts][4-byte uint32 count][records]
///
/// Record format within a group (8 sub-records per group):
///   Data:  01 01 04 00 00 [f32 L1][f32 L2][f32 L3]  = 17 bytes
///   Null:  00 00 00 00 00                             =  5 bytes
///   Sub-record 0 = average, 1 = max (10ms), 2 = min (10ms), 3 = 3-phase total
///
/// Relevant groups (all use sub-record 0 = average):
///   0  → Voltage rms L1/L2/L3 (V)
///   2  → Current rms L1/L2/L3 (A)
///   3  → Frequency (Hz)
///   18 → Active power P L1/L2/L3 (W)
///   20 → Apparent power S L1/L2/L3 (VA)
///   22 → Reactive power Q L1/L2/L3 (VAr)
class FpqoParser {
  static const int _firstBlockOffset = 0x412;

  DateTime _oleToDateTime(double oleDate) {
    final ms = ((oleDate - 25569.0) * 86400000.0).round();
    return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }

  int _skipRecords(Uint8List data, int offset, int count) {
    for (int i = 0; i < count && offset < data.length; i++) {
      offset += (data[offset] == 0x01) ? 17 : 5;
    }
    return offset;
  }

  /// Extracts [L1, L2, L3] from a specific sub-record index (0=avg, 1=max, 2=min).
  List<double?> _extractRecordN(
      Uint8List data, ByteData bd, int offset, int count, int n) {
    int pos = offset;
    for (int i = 0; i < count && pos + 5 <= data.length; i++) {
      final marker = data[pos];
      if (i == n) {
        if (marker == 0x01 && pos + 17 <= data.length) {
          return [
            bd.getFloat32(pos + 5, Endian.little),
            bd.getFloat32(pos + 9, Endian.little),
            bd.getFloat32(pos + 13, Endian.little),
          ];
        }
        return [null, null, null];
      }
      pos += (marker == 0x01) ? 17 : 5;
    }
    return [null, null, null];
  }

  /// Extracts [L1, L2, L3] from the first (average) sub-record only.
  List<double?> _extractFirstRecord(Uint8List data, ByteData bd, int offset) =>
      _extractRecordN(data, bd, offset, 1, 0);

  /// Extracts a single float from the first data sub-record (used for frequency).
  double? _extractSingleFirst(Uint8List data, ByteData bd, int offset) {
    if (offset + 9 > data.length) return null;
    if (data[offset] != 0x01) return null;
    return bd.getFloat32(offset + 5, Endian.little);
  }

  Future<MeasurementSession> parseFile(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    final bd = ByteData.sublistView(bytes);

    // Extract device ID from XML header
    final headerText = String.fromCharCodes(
        bytes.sublist(0, math.min(_firstBlockOffset, bytes.length)));
    String deviceId = 'Fluke 435-II';
    final match = RegExp(r'<measName>([^<]+)<\/measName>').firstMatch(headerText);
    if (match != null) deviceId = match.group(1)!;

    // Determine block size by finding the second timestamp 60s after the first
    if (_firstBlockOffset + 8 > bytes.length) {
      throw const FormatException('FPQO file too small');
    }
    final t1 = bd.getFloat64(_firstBlockOffset, Endian.little);
    final t2Target = t1 + 1.0 / 1440.0; // 1 minute = 1/1440 day
    const tolerance = 0.0003; // ~26 seconds
    int blockSize = 0;

    final searchEnd = math.min(_firstBlockOffset + 100000, bytes.length - 12);
    for (int k = _firstBlockOffset + 5000; k < searchEnd; k++) {
      final val = bd.getFloat64(k, Endian.little);
      if ((val - t2Target).abs() < tolerance) {
        final count = bd.getUint32(k + 8, Endian.little);
        if (count > 0 && count <= 200) {
          blockSize = k - _firstBlockOffset;
          break;
        }
      }
    }

    if (blockSize == 0) {
      throw const FormatException('Could not determine FPQO block size');
    }

    final voltagePoints = <MeasurementPoint>[];
    final currentPoints = <MeasurementPoint>[];
    final freqPoints = <MeasurementPoint>[];
    final activePowerPoints = <MeasurementPoint>[];
    final apparentPowerPoints = <MeasurementPoint>[];
    final reactivePowerPoints = <MeasurementPoint>[];

    int blockStart = _firstBlockOffset;
    while (blockStart < bytes.length) {
      _parseBlock(bytes, bd, blockStart, voltagePoints, currentPoints,
          freqPoints, activePowerPoints, apparentPowerPoints, reactivePowerPoints);
      blockStart += blockSize;
    }

    final allTimes = [
      ...voltagePoints.map((p) => p.time),
      ...currentPoints.map((p) => p.time),
      ...freqPoints.map((p) => p.time),
    ];
    final startTime = allTimes.isEmpty
        ? DateTime.now()
        : allTimes.reduce((a, b) => a.isBefore(b) ? a : b);
    final endTime = allTimes.isEmpty
        ? DateTime.now()
        : allTimes.reduce((a, b) => a.isAfter(b) ? a : b);

    return MeasurementSession(
      deviceId: deviceId,
      startTime: startTime,
      endTime: endTime,
      voltageData: voltagePoints,
      currentData: currentPoints,
      frequencyData10min: freqPoints,
      frequencyData10s: [],
      events: [],
      activePowerData: activePowerPoints,
      apparentPowerData: apparentPowerPoints,
      reactivePowerData: reactivePowerPoints,
    );
  }

  void _parseBlock(
    Uint8List data,
    ByteData bd,
    int blockStart,
    List<MeasurementPoint> voltagePoints,
    List<MeasurementPoint> currentPoints,
    List<MeasurementPoint> freqPoints,
    List<MeasurementPoint> activePowerPoints,
    List<MeasurementPoint> apparentPowerPoints,
    List<MeasurementPoint> reactivePowerPoints,
  ) {
    int pos = blockStart;

    // Group 0: voltage (no prefix byte)
    if (pos + 12 > data.length) return;
    final ts0 = bd.getFloat64(pos, Endian.little);
    final count0 = bd.getUint32(pos + 8, Endian.little);
    pos += 12;
    if (count0 > 1000) return;

    final voltage = _extractFirstRecord(data, bd, pos);
    if (voltage[0] != null) {
      voltagePoints.add(MeasurementPoint(
        time: _oleToDateTime(ts0),
        values: {
          'V_L1': voltage[0]!,
          'V_L2': voltage[1]!,
          'V_L3': voltage[2]!,
        },
      ));
    }
    pos = _skipRecords(data, pos, count0);

    // Groups 1–34: each has a 1-byte prefix before the OLE timestamp
    for (int g = 1; g <= 34; g++) {
      if (pos + 13 > data.length) break;
      pos += 1; // prefix byte
      final ts = bd.getFloat64(pos, Endian.little);
      final count = bd.getUint32(pos + 8, Endian.little);
      pos += 12;
      if (count > 1000) break;

      final time = _oleToDateTime(ts);

      switch (g) {
        case 2: // Current rms L1/L2/L3 — sub-record 0=avg, 1=max, 2=min
          final vAvg = _extractRecordN(data, bd, pos, count, 0);
          final vMax = _extractRecordN(data, bd, pos, count, 1);
          final vMin = _extractRecordN(data, bd, pos, count, 2);
          if (vAvg[0] != null) {
            currentPoints.add(MeasurementPoint(
              time: time,
              values: {
                'I_L1': vAvg[0]!, 'I_L2': vAvg[1]!, 'I_L3': vAvg[2]!,
                if (vMax[0] != null) ...{
                  'I_L1_max': vMax[0]!, 'I_L2_max': vMax[1]!, 'I_L3_max': vMax[2]!,
                },
                if (vMin[0] != null) ...{
                  'I_L1_min': vMin[0]!, 'I_L2_min': vMin[1]!, 'I_L3_min': vMin[2]!,
                },
              },
            ));
          }
        case 3: // Frequency Hz
          final hz = _extractSingleFirst(data, bd, pos);
          if (hz != null) {
            freqPoints.add(MeasurementPoint(time: time, values: {'Hz': hz}));
          }
        case 18: // Active power P (W)
          final v = _extractFirstRecord(data, bd, pos);
          if (v[0] != null) {
            activePowerPoints.add(MeasurementPoint(
              time: time,
              values: {
                'P_L1': v[0]!,
                'P_L2': v[1]!,
                'P_L3': v[2]!,
                'P_total': v[0]! + v[1]! + v[2]!,
              },
            ));
          }
        case 20: // Apparent power S (VA)
          final v = _extractFirstRecord(data, bd, pos);
          if (v[0] != null) {
            apparentPowerPoints.add(MeasurementPoint(
              time: time,
              values: {
                'S_L1': v[0]!,
                'S_L2': v[1]!,
                'S_L3': v[2]!,
                'S_total': v[0]! + v[1]! + v[2]!,
              },
            ));
          }
        case 22: // Reactive power Q (VAr)
          final v = _extractFirstRecord(data, bd, pos);
          if (v[0] != null) {
            reactivePowerPoints.add(MeasurementPoint(
              time: time,
              values: {
                'Q_L1': v[0]!,
                'Q_L2': v[1]!,
                'Q_L3': v[2]!,
                'Q_total': v[0]! + v[1]! + v[2]!,
              },
            ));
          }
      }

      pos = _skipRecords(data, pos, count);
    }
  }
}
