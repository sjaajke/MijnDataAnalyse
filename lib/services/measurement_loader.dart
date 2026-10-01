import '../models/measurement_data.dart';
import '../models/pqf_record.dart';
import 'pqf_parser.dart';

/// Structuur-ID's uit "PQ-Box Dateiformat" v1.5 (Appendix B/C) en
/// structures.h. Alleen de ID's die deze app gebruikt staan hier.
abstract final class PqfId {
  // cyc.pqf — cyclische data met instelbaar interval (Nsec)
  static const fNsec = 100; //         StructF
  static const fExtrNsec = 101; //     StructFExtr
  static const uNsec = 102; //         StructU
  static const uExtrNsec = 103; //     StructUExtr (10 ms)
  static const iNsec = 104; //         StructI
  static const iExtrNsec = 105; //     StructIExtr (10 ms)
  static const pNsec = 106; //         StructP
  static const pExtrNsec = 107; //     StructPExtr
  static const uExtr200Nsec = 111; //  StructUExtrX1 (200 ms)
  static const iExtr200Nsec = 112; //  StructIExtr (200 ms)
  static const px2Nsec = 115; //       StructPX2 (cos φ, …)
  static const px3Nsec = 116; //       StructPX3 (QV1..QV3)
  static const i1HrmNsec = 140; //     StructHarm I1
  static const i2HrmNsec = 141; //     StructHarm I2
  static const i3HrmNsec = 142; //     StructHarm I3
  static const iMaxSampleNsec = 148; // StructIExtrX1 (sample-piekwaarde)
  static const fx2Nsec = 902; //       StructF (niet median-gefilterd)

  // cyc10s.pqf
  static const f10s = 801; //          StructF
}

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

    // --- cyc.pqf ---
    final voltageMap = <DateTime, Map<String, double>>{};
    final currentMap = <DateTime, Map<String, double>>{};
    final activePowerMap = <DateTime, Map<String, double>>{};
    final freqPoints = <MeasurementPoint>[];
    final freqPointsFx2 = <MeasurementPoint>[];
    // Harmonischen: één record per fase (140/141/142)
    final harmonicMap = <DateTime, Map<String, List<double>>>{};
    final cosPhiPoints = <CosPhiPoint>[];
    final reactivePowerPoints = <MeasurementPoint>[];
    final reactivePowerFallback = <MeasurementPoint>[];
    final apparentPowerPoints = <MeasurementPoint>[];

    if (cycResult != null) {
      for (final record in cycResult.records) {
        final p = record.payload;
        switch (record.typeId) {
          case PqfId.uNsec:
            // StructU: U1, U2, U3, UNE, U12, U23, U31, THD1..THD31 (7..13),
            // PH1..PH31 (14..20), PST1, PST2, PST3, PST12, PST23, PST31
            // (21..26), UU (27), UPS, UNS, UZS, U0, UREF
            if (p.length >= 7) {
              final m = voltageMap.putIfAbsent(record.timestamp, () => {});
              m['V_L1'] = p[0];
              m['V_L2'] = p[1];
              m['V_L3'] = p[2];
              m['V_N'] = p[3];
              m['V_L12'] = p[4];
              m['V_L23'] = p[5];
              m['V_L31'] = p[6];
              if (p.length >= 10) {
                m['V_thd_L1'] = p[7];
                m['V_thd_L2'] = p[8];
                m['V_thd_L3'] = p[9];
              }
              if (p.length >= 24) {
                m['Pst_L1'] = p[21];
                m['Pst_L2'] = p[22];
                m['Pst_L3'] = p[23];
              }
              if (p.length >= 28) m['V_unb'] = p[27];
            }
          case PqfId.uExtrNsec:
            // StructUExtr (10 ms): per waarde [TIME(2), value(1)],
            // volgorde U1MIN, U1MAX, U2MIN, U2MAX, U3MIN, U3MAX, …
            if (p.length >= 18) {
              final m = voltageMap.putIfAbsent(record.timestamp, () => {});
              _putExtremes(m, p, const ['V_L1', 'V_L2', 'V_L3'], '');
            }
          case PqfId.uExtr200Nsec:
            // StructUExtrX1 (200 ms): zelfde opbouw als StructUExtr
            if (p.length >= 18) {
              final m = voltageMap.putIfAbsent(record.timestamp, () => {});
              _putExtremes(m, p, const ['V_L1', 'V_L2', 'V_L3'], '200ms');
            }
          case PqfId.iNsec:
            // StructI: I1, I2, I3, IS/N, IM, THD1, THD2, THD3, THDS
            if (p.length >= 4) {
              final m = currentMap.putIfAbsent(record.timestamp, () => {});
              m['I_L1'] = p[0];
              m['I_L2'] = p[1];
              m['I_L3'] = p[2];
              m['I_N'] = p[3];
              if (p.length >= 9) {
                m['I_thd_L1'] = p[5];
                m['I_thd_L2'] = p[6];
                m['I_thd_L3'] = p[7];
                m['I_thd_N'] = p[8];
              }
            }
          case PqfId.iExtrNsec:
            // StructIExtr (10 ms): I1MIN, I1MAX, …, ISMIN, ISMAX
            if (p.length >= 24) {
              final m = currentMap.putIfAbsent(record.timestamp, () => {});
              _putExtremes(m, p, const ['I_L1', 'I_L2', 'I_L3', 'I_N'], '');
            }
          case PqfId.iExtr200Nsec:
            // StructIExtr (200 ms)
            if (p.length >= 24) {
              final m = currentMap.putIfAbsent(record.timestamp, () => {});
              _putExtremes(
                  m, p, const ['I_L1', 'I_L2', 'I_L3', 'I_N'], '200ms');
            }
          case PqfId.iMaxSampleNsec:
            // StructIExtrX1: hoogste stroom-samplewaarde (piek) per interval,
            // per waarde [TIME(2), value(1)]: I1MAX, I2MAX, I3MAX, INMAX
            if (p.length >= 12) {
              final m = currentMap.putIfAbsent(record.timestamp, () => {});
              m['I_L1_maxsp'] = p[2];
              m['I_L2_maxsp'] = p[5];
              m['I_L3_maxsp'] = p[8];
              m['I_N_maxsp'] = p[11];
            }
          case PqfId.fNsec:
            if (p.isNotEmpty) {
              freqPoints.add(MeasurementPoint(
                time: record.timestamp,
                values: {'Hz': p[0]},
              ));
            }
          case PqfId.fx2Nsec:
            if (p.isNotEmpty) {
              freqPointsFx2.add(MeasurementPoint(
                time: record.timestamp,
                values: {'Hz': p[0]},
              ));
            }
          case PqfId.i1HrmNsec:
          case PqfId.i2HrmNsec:
          case PqfId.i3HrmNsec:
            // StructHarm: Cn[0..50]; 0 = DC, 1 = grondgolf, 2..50 = harmonischen
            // (bij stromen in Ampère). HarmonicPoint verwacht h2..h31.
            if (p.length >= 32) {
              final key = switch (record.typeId) {
                PqfId.i1HrmNsec => 'l1',
                PqfId.i2HrmNsec => 'l2',
                _ => 'l3',
              };
              final m = harmonicMap.putIfAbsent(record.timestamp, () => {});
              m[key] = p.sublist(2, 32);
            }
          case PqfId.px2Nsec:
            // StructPX2: COSPHI1..3 (0..2), COSPHI (3), SINPHI (4..7),
            // TANPHI (8..11), PG, SG, QV, PHI (12..15),
            // COSPHV1..3 (16..18, met teken: induct. +, capac. −), COSPHV (19)
            if (p.length >= 19) {
              cosPhiPoints.add(CosPhiPoint(
                time: record.timestamp,
                l1: p[16],
                l2: p[17],
                l3: p[18],
              ));
            } else if (p.length >= 3) {
              cosPhiPoints.add(CosPhiPoint(
                time: record.timestamp,
                l1: p[0],
                l2: p[1],
                l3: p[2],
              ));
            }
          case PqfId.pNsec:
            // StructP: P1, P2, P3, P (0..3), S1, S2, S3, S (4..7),
            // Q1, Q2, Q3, Q (8..11), PH1..3 (12..14), PF1, PF2, PF3, PF (15..18)
            if (p.length >= 4) {
              final m = activePowerMap.putIfAbsent(record.timestamp, () => {});
              m['P_L1'] = p[0];
              m['P_L2'] = p[1];
              m['P_L3'] = p[2];
              m['P_total'] = p[3];
              if (p.length >= 19) {
                m['PF_L1'] = p[15];
                m['PF_L2'] = p[16];
                m['PF_L3'] = p[17];
                m['PF_total'] = p[18];
              }
            }
            if (p.length >= 12) {
              apparentPowerPoints.add(MeasurementPoint(
                time: record.timestamp,
                values: {
                  'S_L1': p[4],
                  'S_L2': p[5],
                  'S_L3': p[6],
                  'S_total': p[7],
                },
              ));
              reactivePowerFallback.add(MeasurementPoint(
                time: record.timestamp,
                values: {
                  'Q_L1': p[8],
                  'Q_L2': p[9],
                  'Q_L3': p[10],
                  'Q_total': p[11],
                },
              ));
            }
          case PqfId.pExtrNsec:
            // StructPExtr: P1MIN, P1MAX, …, PMIN, PMAX
            if (p.length >= 24) {
              final m = activePowerMap.putIfAbsent(record.timestamp, () => {});
              _putExtremes(
                  m, p, const ['P_L1', 'P_L2', 'P_L3', 'P_total'], '');
            }
          case PqfId.px3Nsec:
            // StructPX3: QV1..QV3 — grondgolf-verschuivingsblindvermogen,
            // met teken (in tegenstelling tot Q uit StructP).
            if (p.length >= 3) {
              reactivePowerPoints.add(MeasurementPoint(
                time: record.timestamp,
                values: {
                  'Q_L1': p[0],
                  'Q_L2': p[1],
                  'Q_L3': p[2],
                  'Q_total': p[0] + p[1] + p[2],
                },
              ));
            }
        }
      }
    }

    // Harmonischen samenvoegen tot HarmonicPoints (alle drie fasen nodig)
    final harmonicPoints = <HarmonicPoint>[];
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

    final voltagePoints = _mapToPoints(voltageMap);
    final currentPoints = _mapToPoints(currentMap);
    final activePowerPoints = _mapToPoints(activePowerMap);

    // Voorkeur: gemedianfilterde netfrequentie (100), anders FX2 (902).
    final freqPointsNsec = freqPoints.isNotEmpty ? freqPoints : freqPointsFx2;

    // --- cyc10s.pqf: frequentie 10 s (Appendix C: alleen 800/801) ---
    final freqPoints10s = <MeasurementPoint>[];

    if (cyc10sResult != null) {
      for (final record in cyc10sResult.records) {
        if (record.typeId == PqfId.f10s && record.payload.isNotEmpty) {
          freqPoints10s.add(MeasurementPoint(
            time: record.timestamp,
            values: {'Hz': record.payload[0]},
          ));
        }
      }
    }

    // --- event.pqf: events ---
    // Structuur: ID, Size, TIME, 4-byte waarde (float32/uint32, event-afhankelijk)
    final events = <PqfEvent>[];

    if (eventResult != null) {
      for (final record in eventResult.records) {
        if (!PqfEvent.isRelevant(record.typeId)) continue;
        events.add(PqfEvent(
          time: record.timestamp,
          typeId: record.typeId,
          value: record.payload.isNotEmpty ? record.payload[0] : null,
        ));
      }
      events.sort((a, b) => a.time.compareTo(b.time));
    }

    // Determine overall time range
    final allTimes = [
      ...voltagePoints.map((p) => p.time),
      ...currentPoints.map((p) => p.time),
      ...freqPointsNsec.map((p) => p.time),
      ...freqPoints10s.map((p) => p.time),
      ...events.map((e) => e.time),
    ];

    final startTime = allTimes.isNotEmpty
        ? allTimes.reduce((a, b) => a.isBefore(b) ? a : b)
        : (header?.startTimestamp ?? DateTime.now());
    final endTime = allTimes.isNotEmpty
        ? allTimes.reduce((a, b) => a.isAfter(b) ? a : b)
        : startTime;

    return MeasurementSession(
      deviceId: deviceId,
      startTime: startTime,
      endTime: endTime,
      voltageData: voltagePoints,
      currentData: currentPoints,
      // cyc.pqf bevat de stroom al op het ingestelde (vaak 10 s) interval;
      // cyc10s.pqf bevat geen stroomdata.
      currentData10s: currentPoints,
      frequencyData10min: freqPointsNsec,
      frequencyData10s: freqPoints10s,
      events: events,
      harmonicCurrentData: harmonicPoints,
      cosPhiData: cosPhiPoints,
      activePowerData: activePowerPoints,
      reactivePowerData: reactivePowerPoints.isNotEmpty
          ? reactivePowerPoints
          : reactivePowerFallback,
      apparentPowerData: apparentPowerPoints,
    );
  }

  /// Leest min/max-paren uit een extreme-waardestructuur (StructUExtr,
  /// StructIExtr, StructPExtr, …). Elke waarde wordt voorafgegaan door een
  /// eigen TIME-veld (8 bytes = 2 floats), dus per kanaal:
  /// [TIME, MIN, TIME, MAX] → MIN op index 6k+2, MAX op index 6k+5.
  /// [suffix] wordt achter "_min"/"_max" geplakt (bv. "200ms").
  static void _putExtremes(
    Map<String, double> m,
    List<double> p,
    List<String> keys,
    String suffix,
  ) {
    for (int k = 0; k < keys.length; k++) {
      final minIdx = k * 6 + 2;
      final maxIdx = k * 6 + 5;
      if (maxIdx >= p.length) break;
      m['${keys[k]}_min$suffix'] = p[minIdx];
      m['${keys[k]}_max$suffix'] = p[maxIdx];
    }
  }

  static List<MeasurementPoint> _mapToPoints(
      Map<DateTime, Map<String, double>> map) {
    return map.entries
        .map((e) => MeasurementPoint(time: e.key, values: e.value))
        .toList()
      ..sort((a, b) => a.time.compareTo(b.time));
  }
}
