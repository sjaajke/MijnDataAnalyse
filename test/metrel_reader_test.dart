import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mijn_data_analyse/models/metrel_record.dart';
import 'package:mijn_data_analyse/services/metrel_catalog.dart';
import 'package:mijn_data_analyse/services/metrel_pwvx_parser.dart';
import 'package:mijn_data_analyse/services/metrel_record_reader.dart';

/// Voorbeeldrecords uit de Metrel Power SDK-showcase. De verwachte waarden
/// komen uit de README van de SDK. Zonder de SDK-map worden de tests
/// overgeslagen.
const _testData =
    '/Users/sjaaj/Developer/SDK Metrel analyser packages/Power.SDK.Showcase/TestData';

void main() {
  final poly = '$_testData/poly_interrupt.pwvx';
  final generated = '$_testData/generated_trends.pwvx';
  final skip = File(poly).existsSync() ? false : 'SDK-testdata niet gevonden';

  late MetrelCatalog catalog;
  late MetrelRecordReader reader;

  setUpAll(() {
    catalog = MetrelCatalog.fromFile('assets/metrel/powerdisplay.db');
    reader = MetrelRecordReader(catalog);
  });

  test('poly_interrupt: record, instrument en instellingen', () async {
    final records = await reader.open(poly);
    expect(records, hasLength(1));
    final r = records.single;
    expect(r.name, '22.11.2024 15:10:44');
    expect(r.folder, 'record_22_11_2024-15_10_44');
    expect(r.instrumentLabel, 'MI 2992 123uros');
    expect(r.nominalVoltage, 230);
    expect(r.utcOffset, const Duration(hours: 2));
  }, skip: skip);

  test('poly_interrupt: eerste 5 s Urms L1 min = 230.07 V', () async {
    final r = (await reader.open(poly)).single;
    final s5 = r.streams.firstWhere((s) => s.intervalSeconds == 5);
    expect(s5.descriptors, hasLength(15972));
    expect(s5.descriptors.where((d) => d.info == null), isEmpty);

    final first = s5.descriptors.first;
    expect(first.info!.code, 'Urms');
    expect(first.info!.channel, 'L1');
    expect(first.info!.aggregation, 'Min');
    expect(s5.values(first.index).first, closeTo(230.07, 0.005));

    // Het lege 2 h-interval levert geen data op, geen nullen.
    final s7200 = r.streams.firstWhere((s) => s.intervalSeconds == 7200);
    expect(s7200.recordCount, 0);
  }, skip: skip);

  test('poly_interrupt: spanningsevents 4 en 10', () async {
    final r = (await reader.open(poly)).single;
    final voltage =
        r.events.where((e) => e.family == MetrelEventFamily.voltage).toList();
    final byId = {for (final e in voltage) e.id: e};
    expect(byId.keys, containsAll([4, 10]));
    final e10 = byId[10]!;
    expect(e10.type, 'Interrupt, Dip');
    expect(e10.channels, contains('L1'));
    expect(e10.duration.inMicroseconds / 1000, closeTo(116.726, 0.001));
  }, skip: skip);

  test('generated_trends: 1 s stroom en alle zes event-families', () async {
    final r = (await reader.open(generated)).single;
    final s1 = r.streams.first;
    expect(s1.intervalSeconds, 1);
    expect(s1.times[1].difference(s1.times[0]), const Duration(seconds: 1));
    expect(s1.descriptors.first.label, 'Urms L1 (Minimal)');
    expect(
      r.events.map((e) => e.family).toSet(),
      MetrelEventFamily.values.toSet(),
    );
  }, skip: skip);

  test('pwvx-parser vult de sessie voor de analyseschermen', () async {
    final session = await MetrelPwvxParser(catalog: catalog).parseFile(poly);
    expect(session.deviceId, 'MI 2992 123uros');
    expect(session.voltageData, isNotEmpty);
    expect(session.voltageData.first.values['V_L1_min'],
        closeTo(230.07, 0.005));
    expect(session.currentData, isNotEmpty);
    expect(session.events, isNotEmpty);
  }, skip: skip);
}
