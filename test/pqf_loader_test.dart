import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mijn_data_analyse/services/measurement_loader.dart';

void main() {
  const folder =
      '/Users/sjaaj/Documents/§2026_MijnNetAnalyseApp/20260702_0948_000';

  test('PQ-Box 150 meting volgens Dateiformat v1.5', () async {
    final s = await MeasurementLoader().loadFolder(folder);
    final v = s.voltageData.first.values;
    final i = s.currentData.first.values;
    final p = s.activePowerData.first.values;
    expect(s.deviceId, 'PQBOX150');
    expect(s.voltageData.first.time, DateTime.utc(2026, 7, 2, 7, 48, 20));
    expect(v['V_L1'], closeTo(232.024, 0.01));
    expect(v['V_L3'], closeTo(231.637, 0.01));
    expect(v['V_L12'], closeTo(401.906, 0.01));
    expect(v['V_L1_min'], closeTo(231.845, 0.01));
    expect(v['V_L1_max'], closeTo(232.237, 0.01));
    expect(i['I_L1'], closeTo(2.567, 0.01));
    expect(i['I_N'], closeTo(3.187, 0.01));
    expect(i['I_L1_max'], closeTo(2.706, 0.01));
    expect(i['I_L1_maxsp'], closeTo(7.298, 0.01));
    expect(p['P_total'], closeTo(1525.032, 0.1));
    expect(s.harmonicCurrentData.first.l1[1], closeTo(0.736, 0.01));
    expect(s.cosPhiData.first.l1, closeTo(-0.951, 0.01));
    expect(s.events.map((e) => e.typeId), containsAll([144, 145]));
  }, skip: !Directory(folder).existsSync());
}
