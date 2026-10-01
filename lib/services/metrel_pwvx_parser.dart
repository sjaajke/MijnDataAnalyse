import '../models/measurement_data.dart';
import '../models/metrel_record.dart';
import '../models/pqf_record.dart';
import 'metrel_catalog.dart';
import 'metrel_record_reader.dart';

/// Zet een Metrel PowerView-record (.pwvx) om naar een [MeasurementSession]
/// voor de gewone analyseschermen.
///
/// Het uitlezen gebeurt door [MetrelRecordReader]; kolommen worden gekozen op
/// hun betekenis in de Metrel SDK-catalogus (grootheid, kanaal, aggregatie),
/// niet op positie.
class MetrelPwvxParser {
  final MetrelCatalog? catalog;

  MetrelPwvxParser({this.catalog});

  Future<MeasurementSession> parseFile(String filePath) async {
    final cat = catalog ?? await MetrelCatalog.load();
    final records = await MetrelRecordReader(cat).open(filePath);
    return sessionFromRecord(records.first);
  }

  static const _phases = ['L1', 'L2', 'L3'];

  static MeasurementSession sessionFromRecord(MetrelRecord record) {
    bool hasVoltage(MetrelStream s) =>
        s.recordCount > 0 && s.find('Urms', 'L1', 'AvgRms') != null;
    final withVoltage = record.streams.where(hasVoltage).toList();

    // Hoofdstroom: 10 min als die er is, anders het langste interval met
    // spanningsdata (de schermen zijn ingericht op 10-minuutwaarden).
    final main = withVoltage.isEmpty
        ? null
        : withVoltage.firstWhere((s) => s.intervalSeconds == 600,
            orElse: () => withVoltage.last);
    final short =
        withVoltage.where((s) => s.intervalSeconds <= 10).firstOrNull;
    final freq10s = record.streams.firstWhere(
        (s) => s.intervalSeconds == 10 && _findAny(s, 'Freq10s') != null,
        orElse: () => record.streams.firstWhere(
            (s) => s.recordCount > 0 && _findAny(s, 'Freq10s') != null,
            orElse: () => _emptyStream));

    final voltage = main == null ? <MeasurementPoint>[] : _voltage(main);
    final current = main == null ? <MeasurementPoint>[] : _current(main);

    final allTimes = [
      if (main != null) ...main.times,
      ...freq10s.times,
      ...record.events.map((e) => e.start),
    ]..sort();

    return MeasurementSession(
      deviceId: record.instrumentLabel,
      location: record.location,
      startTime: allTimes.isNotEmpty
          ? allTimes.first
          : (record.start ?? DateTime.now().toUtc()),
      endTime: allTimes.isNotEmpty
          ? allTimes.last
          : (record.end ?? DateTime.now().toUtc()),
      voltageData: voltage,
      voltageData10s: short == null
          ? const []
          : (identical(short, main) ? voltage : _voltage(short)),
      currentData: current,
      currentData10s: short == null
          ? const []
          : (identical(short, main) ? current : _current(short)),
      frequencyData10min: main == null ? const [] : _frequency(main),
      frequencyData10s: _frequency(freq10s),
      events: _events(record.events),
      harmonicCurrentData: main == null ? const [] : _harmonics(main),
      cosPhiData: main == null ? const [] : _cosPhi(main),
      activePowerData: main == null ? const [] : _activePower(main),
      apparentPowerData: main == null ? const [] : _apparentPower(main),
      reactivePowerData: main == null ? const [] : _reactivePower(main),
    );
  }

  static final _emptyStream = MetrelStream(
    intervalSeconds: 0,
    blockSize: 1,
    recordsPerFile: 0,
    descriptors: const [],
    times: const [],
    flags: const [],
    readDataFile: (_) => null,
  );

  /// Eerste kolom van [code] met een gemiddelde-aggregatie, op elk kanaal.
  static MetrelDescriptor? _findAny(MetrelStream s, String code) {
    for (final agg in const ['AvgAvg', 'AvgOnAvg', 'AvgRms']) {
      for (final d in s.descriptors) {
        if (d.info?.code == code && d.info?.aggregation == agg) return d;
      }
    }
    return null;
  }

  /// Bouwt meetpunten uit kolommen; NaN-waarden en lege punten vallen weg.
  static List<MeasurementPoint> _points(
      MetrelStream s, Map<String, MetrelDescriptor?> columns) {
    final series = <String, List<double>>{
      for (final e in columns.entries)
        if (e.value != null) e.key: s.values(e.value!.index),
    };
    if (series.isEmpty) return [];
    return [
      for (var r = 0; r < s.recordCount; r++)
        if (_row(series, r) case final values when values.isNotEmpty)
          MeasurementPoint(time: s.times[r], values: values),
    ];
  }

  static Map<String, double> _row(Map<String, List<double>> series, int r) => {
        for (final e in series.entries)
          if (!e.value[r].isNaN) e.key: e.value[r],
      };

  static List<MeasurementPoint> _voltage(MetrelStream s) => _points(s, {
        for (final (i, ch) in _phases.indexed) ...{
          'V_L${i + 1}': s.find('Urms', ch, 'AvgRms'),
          'V_L${i + 1}_min': s.find('Urms', ch, 'Min'),
          'V_L${i + 1}_max': s.find('Urms', ch, 'Max'),
        },
        'V_L12': s.find('Urms', 'L12', 'AvgRms'),
        'V_L23': s.find('Urms', 'L23', 'AvgRms'),
        'V_L31': s.find('Urms', 'L31', 'AvgRms'),
      });

  static List<MeasurementPoint> _current(MetrelStream s) => _points(s, {
        for (final (key, ch) in const [
          ('I_L1', 'L1'),
          ('I_L2', 'L2'),
          ('I_L3', 'L3'),
          ('I_N', 'Ln'),
        ]) ...{
          key: s.find('Irms', ch, 'AvgRms'),
          '${key}_min': s.find('Irms', ch, 'Min'),
          '${key}_max': s.find('Irms', ch, 'Max'),
        },
      });

  static List<MeasurementPoint> _frequency(MetrelStream s) {
    final col = _findAny(s, 'Freq10s') ?? _findAny(s, 'Freq200ms');
    return _points(s, {'Hz': col});
  }

  static MetrelDescriptor? _avg(MetrelStream s, String code, String ch) =>
      s.find(code, ch, 'AvgAvg') ?? s.find(code, ch, 'AvgOnAvg');

  static List<MeasurementPoint> _activePower(MetrelStream s) => _points(s, {
        'P_L1': _avg(s, 'P', 'L1'),
        'P_L2': _avg(s, 'P', 'L2'),
        'P_L3': _avg(s, 'P', 'L3'),
        'P_total': _avg(s, 'P', 'Tot'),
        'PF_L1': _avg(s, 'PF', 'L1'),
        'PF_L2': _avg(s, 'PF', 'L2'),
        'PF_L3': _avg(s, 'PF', 'L3'),
      });

  static List<MeasurementPoint> _apparentPower(MetrelStream s) =>
      _withTotal(_points(s, {
        'S_L1': _avg(s, 'S', 'L1'),
        'S_L2': _avg(s, 'S', 'L2'),
        'S_L3': _avg(s, 'S', 'L3'),
        'S_total': _avg(s, 'S', 'Tot'),
      }), 'S');

  static List<MeasurementPoint> _reactivePower(MetrelStream s) =>
      _withTotal(_points(s, {
        'Q_L1': _avg(s, 'Qfund', 'L1'),
        'Q_L2': _avg(s, 'Qfund', 'L2'),
        'Q_L3': _avg(s, 'Qfund', 'L3'),
        'Q_total': _avg(s, 'Qfund', 'Tot'),
      }), 'Q');

  /// Vult `{prefix}_total` aan als som van de fasen wanneer het instrument
  /// geen totaal registreert.
  static List<MeasurementPoint> _withTotal(
      List<MeasurementPoint> points, String prefix) {
    for (final p in points) {
      if (p.values.containsKey('${prefix}_total')) continue;
      final phases = [
        for (var i = 1; i <= 3; i++) p.values['${prefix}_L$i'],
      ].whereType<double>();
      if (phases.isNotEmpty) {
        p.values['${prefix}_total'] = phases.fold(0.0, (a, b) => a + b);
      }
    }
    return points;
  }

  static List<CosPhiPoint> _cosPhi(MetrelStream s) {
    final cols = [for (final ch in _phases) _avg(s, 'DPF', ch)];
    if (cols.any((c) => c == null)) return [];
    final v = [for (final c in cols) s.values(c!.index)];
    return [
      for (var r = 0; r < s.recordCount; r++)
        if (!v[0][r].isNaN && !v[1][r].isNaN && !v[2][r].isNaN)
          CosPhiPoint(time: s.times[r], l1: v[0][r], l2: v[1][r], l3: v[2][r]),
    ];
  }

  /// Stroomharmonischen h2..h31 per fase (A), zoals [HarmonicPoint] verwacht.
  static List<HarmonicPoint> _harmonics(MetrelStream s) {
    final perPhase = <List<List<double>?>>[];
    for (final ch in _phases) {
      final orders = <List<double>?>[
        for (var h = 2; h <= 31; h++)
          switch (s.find('Ih_A', ch, 'AvgRms', harmonic: h)) {
            final d? => s.values(d.index),
            null => null,
          },
      ];
      if (orders.every((o) => o == null)) return [];
      perPhase.add(orders);
    }
    List<double> at(List<List<double>?> orders, int r) => [
          for (final o in orders)
            o == null || o[r].isNaN ? 0.0 : o[r],
        ];
    return [
      for (var r = 0; r < s.recordCount; r++)
        HarmonicPoint(
          time: s.times[r],
          l1: at(perPhase[0], r),
          l2: at(perPhase[1], r),
          l3: at(perPhase[2], r),
        ),
    ];
  }

  /// Vertaalt Metrel-events naar de eventcodes die de Events-schermen kennen.
  static List<PqfEvent> _events(List<MetrelEvent> events) {
    final result = <PqfEvent>[];
    for (final e in events) {
      switch (e.family) {
        case MetrelEventFamily.voltage:
          if (e.typeMask & 2 != 0) {
            result.add(PqfEvent(time: e.start, typeId: 0x002D));
          }
          if (e.typeMask & 4 != 0) {
            result.add(PqfEvent(time: e.start, typeId: 0x0084));
            result.add(PqfEvent(time: e.start.add(e.duration), typeId: 0x0085));
          }
          if (e.typeMask & 1 != 0) {
            result.add(PqfEvent(time: e.start, typeId: 0x002F));
          }
        case MetrelEventFamily.transient:
          result.add(PqfEvent(time: e.start, typeId: 0x03FD));
        default:
          result.add(PqfEvent(time: e.start, typeId: 0x03F2));
      }
    }
    result.sort((a, b) => a.time.compareTo(b.time));
    return result;
  }
}
