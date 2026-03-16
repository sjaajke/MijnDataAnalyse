import 'dart:math';

import '../models/measurement_data.dart';
import '../models/pqf_record.dart';
import 'pqf_parser.dart';

class MeasurementLoader {
  final PqfParser _parser = PqfParser();

  Future<MeasurementSession> loadFolder(String folderPath) async {
    final results = await _parser.parseMeasurementFolder(folderPath);

    final cycResult = results['cyc.pqf'];
    final cyc10sResult = results['cyc10s.pqf'];
    final eventResult = results['event.pqf'];

    // Extract header info from cyc.pqf or whichever is available
    final header = cycResult?.header ??
        cyc10sResult?.header ??
        eventResult?.header;

    final deviceId = header?.deviceId ?? 'Unknown Device';

    // --- cyc.pqf: voltage (102), current (104), frequency (902),
    //             harmonics (917), cos phi (115) ---
    final voltageMap = <DateTime, Map<String, double>>{};
    final currentMap = <DateTime, Map<String, double>>{};
    final freqPoints10min = <MeasurementPoint>[];
    final harmonicPoints = <HarmonicPoint>[];
    // New-format harmonics: separate record per phase with complex pairs
    final harmonicMap = <DateTime, Map<String, List<double>>>{};
    final cosPhiPoints = <CosPhiPoint>[];
    final activePowerPoints = <MeasurementPoint>[];
    final reactivePowerPoints = <MeasurementPoint>[];

    if (cycResult != null) {
      for (final record in cycResult.records) {
        switch (record.typeId) {
          case 0x0066: // 102 — Voltage avg
            if (record.payload.length >= 3) {
              final m = voltageMap.putIfAbsent(record.timestamp, () => {});
              if (record.payload.length >= 10) {
                // New format (33 floats): [?, V_L1, V_L2, V_N, V_L3, V_L12, ...]
                m['V_L1'] = record.payload[1];
                m['V_L2'] = record.payload[2];
                m['V_L3'] = record.payload[4];
                if (record.payload.length >= 6) m['V_L12'] = record.payload[5];
              } else {
                // Old format (≤8 floats): [V_L1, V_L2, V_L3, ?, V_L12, V_L23, V_L31]
                m['V_L1'] = record.payload[0];
                m['V_L2'] = record.payload[1];
                m['V_L3'] = record.payload[2];
                if (record.payload.length >= 6) m['V_L12'] = record.payload[4];
                if (record.payload.length >= 7) m['V_L23'] = record.payload[5];
                if (record.payload.length >= 8) m['V_L31'] = record.payload[6];
              }
            }
          case 0x0067: // 103 — Voltage min/max per phase
            if (record.payload.length >= 3) {
              final m = voltageMap.putIfAbsent(record.timestamp, () => {});
              if (record.payload.length >= 30) {
                // New format (60 floats): groups of 3 [crest, 0, value]
                // order: V_N_min, V_N_max, V_L1_min, V_L1_max, V_L2_min, V_L2_max,
                //        V_N2_min, V_N2_max, V_L3_min, V_L3_max, ...
                m['V_L1_min'] = record.payload[8];
                m['V_L1_max'] = record.payload[11];
                m['V_L2_min'] = record.payload[14];
                m['V_L2_max'] = record.payload[17];
                m['V_L3_min'] = record.payload[26];
                m['V_L3_max'] = record.payload[29];
              } else {
                // Old format (≤8 floats): [L1_max, L2_max, L3_max, ?, L1_min, L2_min, L3_min]
                m['V_L1_max'] = record.payload[0];
                m['V_L2_max'] = record.payload[1];
                m['V_L3_max'] = record.payload[2];
                if (record.payload.length >= 7) {
                  m['V_L1_min'] = record.payload[4];
                  m['V_L2_min'] = record.payload[5];
                  m['V_L3_min'] = record.payload[6];
                }
              }
            }
          case 0x0068: // 104 — Current avg
            if (record.payload.isNotEmpty) {
              final m = currentMap.putIfAbsent(record.timestamp, () => {});
              m['I_L1'] = record.payload[0];
              if (record.payload.length >= 2) m['I_L2'] = record.payload[1];
              if (record.payload.length >= 3) m['I_L3'] = record.payload[2];
              if (record.payload.length >= 4) m['I_N'] = record.payload[3];
            }
          case 0x0094: // 148 — Current peak (groups of 3: [~Vpeak, 0.0, Ipeak] for L1/L2/L3/N)
            if (record.payload.length >= 12) {
              final m = currentMap.putIfAbsent(record.timestamp, () => {});
              m['I_L1_max'] = record.payload[2];
              m['I_L2_max'] = record.payload[5];
              m['I_L3_max'] = record.payload[8];
              m['I_N_max'] = record.payload[11];
            }
          case 0x006d: // 109 — Current minimum (L1/L2/L3/N)
            if (record.payload.length >= 4) {
              final m = currentMap.putIfAbsent(record.timestamp, () => {});
              m['I_L1_min'] = record.payload[0];
              m['I_L2_min'] = record.payload[1];
              m['I_L3_min'] = record.payload[2];
              m['I_N_min'] = record.payload[3];
            }
          case 0x0386: // 902 — Frequency 10min
            if (record.payload.isNotEmpty) {
              freqPoints10min.add(MeasurementPoint(
                time: record.timestamp,
                values: {'Hz': record.payload[0]},
              ));
            }
          case 0x0395: // 917 — Harmonic current (avg), interleaved L1/L2/L3, h2..h31
            // payload = 90 data floats: [h2_L1, h2_L2, h2_L3, h3_L1, ...]
            if (record.payload.length >= 90) {
              final l1 = <double>[], l2 = <double>[], l3 = <double>[];
              for (int h = 0; h < 30; h++) {
                l1.add(record.payload[h * 3]);
                l2.add(record.payload[h * 3 + 1]);
                l3.add(record.payload[h * 3 + 2]);
              }
              harmonicPoints.add(HarmonicPoint(
                time: record.timestamp,
                l1: l1,
                l2: l2,
                l3: l3,
              ));
            }
          // New-format harmonic current: one record per phase, complex pairs
          // Layout: [dc, h1_re, h1_im, h2_re, h2_im, ..., h25_re, h25_im] (51 floats)
          case 0x008C: // 140 — Current harmonics L1
          case 0x008D: // 141 — Current harmonics L2
          case 0x008E: // 142 — Current harmonics L3
            if (record.payload.length >= 51) {
              final key = switch (record.typeId) {
                0x008C => 'l1',
                0x008D => 'l2',
                _ => 'l3',
              };
              final m = harmonicMap.putIfAbsent(record.timestamp, () => {});
              // Extract amplitudes h2..h31 (h26..h31 = 0 if not in record)
              m[key] = [
                for (int h = 2; h <= 31; h++)
                  h <= 25
                      ? sqrt(pow(record.payload[h * 2 - 1], 2) +
                            pow(record.payload[h * 2], 2))
                      : 0.0,
              ];
            }
          case 0x0073: // 115 — Displacement power factor per phase
            // payload[0]=cos_phi_L1, [1]=cos_phi_L2, [2]=cos_phi_L3
            if (record.payload.length >= 3) {
              cosPhiPoints.add(CosPhiPoint(
                time: record.timestamp,
                l1: record.payload[0],
                l2: record.payload[1],
                l3: record.payload[2],
              ));
            }
          case 0x006a: // Active power P (W) per phase + total
            if (record.payload.length >= 4) {
              activePowerPoints.add(MeasurementPoint(
                time: record.timestamp,
                values: {
                  'P_L1': record.payload[0],
                  'P_L2': record.payload[1],
                  'P_L3': record.payload[2],
                  'P_total': record.payload[3],
                },
              ));
            }
          case 0x0074: // Reactive power Q (VAr) per phase
            if (record.payload.length >= 3) {
              reactivePowerPoints.add(MeasurementPoint(
                time: record.timestamp,
                values: {
                  'Q_L1': record.payload[0],
                  'Q_L2': record.payload[1],
                  'Q_L3': record.payload[2],
                  'Q_total': record.payload[0] + record.payload[1] + record.payload[2],
                },
              ));
            }
        }
      }
    }

    // Convert new-format harmonic map to HarmonicPoints (merged with old-format)
    for (final e in harmonicMap.entries) {
      final l1 = e.value['l1'];
      final l2 = e.value['l2'];
      final l3 = e.value['l3'];
      if (l1 != null && l2 != null && l3 != null) {
        harmonicPoints.add(HarmonicPoint(
          time: e.key,
          l1: l1,
          l2: l2,
          l3: l3,
        ));
      }
    }
    harmonicPoints.sort((a, b) => a.time.compareTo(b.time));

    // Convert voltage/current maps to sorted lists
    final voltagePoints = voltageMap.entries
        .map((e) => MeasurementPoint(time: e.key, values: e.value))
        .toList()
      ..sort((a, b) => a.time.compareTo(b.time));

    final currentPoints = currentMap.entries
        .map((e) => MeasurementPoint(time: e.key, values: e.value))
        .toList()
      ..sort((a, b) => a.time.compareTo(b.time));

    // --- cyc10s.pqf: frequency 10s, and optionally voltage/current 10s ---
    final freqPoints10s = <MeasurementPoint>[];
    final voltageMap10s = <DateTime, Map<String, double>>{};
    final currentPoints10s = <MeasurementPoint>[];

    if (cyc10sResult != null) {
      for (final record in cyc10sResult.records) {
        switch (record.typeId) {
          case 0x0321: // Frequency 10s
            if (record.payload.isNotEmpty) {
              freqPoints10s.add(MeasurementPoint(
                time: record.timestamp,
                values: {'Hz': record.payload[0]},
              ));
            }
          case 0x0066: // Voltage 10s avg
            if (record.payload.length >= 3) {
              final m = voltageMap10s.putIfAbsent(record.timestamp, () => {});
              if (record.payload.length >= 10) {
                m['V_L1'] = record.payload[1];
                m['V_L2'] = record.payload[2];
                m['V_L3'] = record.payload[4];
                if (record.payload.length >= 6) m['V_L12'] = record.payload[5];
              } else {
                m['V_L1'] = record.payload[0];
                m['V_L2'] = record.payload[1];
                m['V_L3'] = record.payload[2];
                if (record.payload.length >= 6) m['V_L12'] = record.payload[4];
                if (record.payload.length >= 7) m['V_L23'] = record.payload[5];
                if (record.payload.length >= 8) m['V_L31'] = record.payload[6];
              }
            }
          case 0x0067: // Voltage 10s max/min
            if (record.payload.length >= 3) {
              final m = voltageMap10s.putIfAbsent(record.timestamp, () => {});
              if (record.payload.length >= 30) {
                m['V_L1_min'] = record.payload[8];
                m['V_L1_max'] = record.payload[11];
                m['V_L2_min'] = record.payload[14];
                m['V_L2_max'] = record.payload[17];
                m['V_L3_min'] = record.payload[26];
                m['V_L3_max'] = record.payload[29];
              } else {
                m['V_L1_max'] = record.payload[0];
                m['V_L2_max'] = record.payload[1];
                m['V_L3_max'] = record.payload[2];
                if (record.payload.length >= 7) {
                  m['V_L1_min'] = record.payload[4];
                  m['V_L2_min'] = record.payload[5];
                  m['V_L3_min'] = record.payload[6];
                }
              }
            }
          case 0x0068: // Current 10s (same format as cyc.pqf)
            if (record.payload.isNotEmpty) {
              currentPoints10s.add(MeasurementPoint(
                time: record.timestamp,
                values: {
                  'I_L1': record.payload[0],
                  if (record.payload.length >= 2) 'I_L2': record.payload[1],
                  if (record.payload.length >= 3) 'I_L3': record.payload[2],
                  if (record.payload.length >= 4) 'I_N': record.payload[3],
                },
              ));
            }
        }
      }
    }

    final voltagePoints10s = voltageMap10s.entries
        .map((e) => MeasurementPoint(time: e.key, values: e.value))
        .toList()
      ..sort((a, b) => a.time.compareTo(b.time));

    // --- event.pqf: events ---
    final events = <PqfEvent>[];

    if (eventResult != null) {
      for (final record in eventResult.records) {
        switch (record.typeId) {
          case 0x0084:
          case 0x0085:
          case 0x002F:
          case 0x002D:
          case 0x03F2:
          case 0x03FD:
            events.add(PqfEvent(time: record.timestamp, typeId: record.typeId));
        }
      }
    }

    // Determine overall time range
    final allTimes = [
      ...voltagePoints.map((p) => p.time),
      ...currentPoints.map((p) => p.time),
      ...freqPoints10min.map((p) => p.time),
      ...freqPoints10s.map((p) => p.time),
      ...events.map((e) => e.time),
    ];

    final startTime = allTimes.isNotEmpty
        ? allTimes.reduce((a, b) => a.isBefore(b) ? a : b)
        : DateTime.now();
    final endTime = allTimes.isNotEmpty
        ? allTimes.reduce((a, b) => a.isAfter(b) ? a : b)
        : DateTime.now();

    return MeasurementSession(
      deviceId: deviceId,
      startTime: startTime,
      endTime: endTime,
      voltageData: voltagePoints,
      voltageData10s: voltagePoints10s,
      currentData: currentPoints,
      currentData10s: currentPoints10s,
      frequencyData10min: freqPoints10min,
      frequencyData10s: freqPoints10s,
      events: events,
      harmonicCurrentData: harmonicPoints,
      cosPhiData: cosPhiPoints,
      activePowerData: activePowerPoints,
      reactivePowerData: reactivePowerPoints,
    );
  }
}
