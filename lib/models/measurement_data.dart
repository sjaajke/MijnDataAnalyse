import 'pqf_record.dart';

/// One 10-minute snapshot of current harmonic content.
/// [l1], [l2], [l3] each hold 30 values: orders h2..h31 in Ampères.
class HarmonicPoint {
  final DateTime time;
  final List<double> l1;
  final List<double> l2;
  final List<double> l3;

  const HarmonicPoint({
    required this.time,
    required this.l1,
    required this.l2,
    required this.l3,
  });

  /// Total Harmonic Distortion as % of fundamental [fundL1, fundL2, fundL3].
  double thdPercent(List<double> harmonics, double fundamental) {
    if (fundamental <= 0) return 0;
    final sumSq = harmonics.fold<double>(0, (s, v) => s + v * v);
    return 100.0 * (sumSq == 0 ? 0 : (sumSq / (fundamental * fundamental)));
  }
}

/// One 10-minute sample of displacement power factor per phase.
/// Positive = lagging (inductive), negative = leading (capacitive).
class CosPhiPoint {
  final DateTime time;
  final double l1;
  final double l2;
  final double l3;

  const CosPhiPoint({
    required this.time,
    required this.l1,
    required this.l2,
    required this.l3,
  });
}

/// Event uit een A-Eberle PQ-Box "event.pqf" (ID's volgens structures.h /
/// "PQ-Box Dateiformat" v1.5, Appendix J). Events met een even ID markeren
/// het begin, het direct volgende oneven ID (suffix "_S") het einde van een
/// eventconditie.
class PqfEvent {
  final DateTime time;
  final int typeId;

  /// Eventwaarde (float32): bij start de triggerwaarde, bij einde de
  /// extreme waarde tijdens het event.
  final double? value;

  const PqfEvent({
    required this.time,
    required this.typeId,
    this.value,
  });

  // Recorder-triggers
  static const idRecA = 31; // oscilloscoop-recorder
  static const idRecB = 32; // RMS-recorder
  static const idRecS = 33; // rimpelspanningsrecorder
  static const idRecTrans = 36; // transiëntenrecorder
  static const idRecHf = 39; // HF-analyser recorder

  /// Kanaalnamen in de volgorde waarin ze in de ID-blokken voorkomen.
  static const _voltChannels6 = ['L1-N', 'L2-N', 'L3-N', 'L1-L2', 'L2-L3', 'L3-L1'];
  static const _overvoltChannels = ['L1-N', 'L2-N', 'L3-N', 'N-PE'];

  /// Filtert interne notificaties ("nieuwe data beschikbaar", 10s-frequentie,
  /// diagnose-events van de firmware/HF-kaart) weg.
  static bool isRelevant(int id) {
    if (id >= 16 && id <= 28) return false; // ID_NEW_*_VALID/INVALID
    if (id == 1 || id == 2) return false; // tijdsync / frame-sync
    if (id >= 10 && id <= 15) return false; // interne timeouts
    if (id == 40 || (id >= 42 && id <= 44)) return false; // 10s-freq, flicker
    if (id >= 410 && id <= 449) return false; // HF-diagnose
    if (id >= 1000) return false; // diagnose-events
    return true;
  }

  static bool _isStartStopId(int id) =>
      (id >= 50 && id <= 121) || (id >= 130 && id <= 151);

  String get eventName {
    final id = typeId;
    final suffix = _isStartStopId(id) ? (id.isOdd ? ' (einde)' : ' (start)') : '';
    final base = id - (_isStartStopId(id) && id.isOdd ? 1 : 0);

    String? ch6(int start) {
      final i = (base - start) ~/ 2;
      return (i >= 0 && i < 6) ? _voltChannels6[i] : null;
    }

    String? name;
    if (base == 50) {
      name = 'Frequentieafwijking (smal)';
    } else if (base == 52) {
      name = 'Frequentieafwijking (breed)';
    } else if (base >= 54 && base <= 60) {
      name = 'Overspanning ${_overvoltChannels[(base - 54) ~/ 2]}';
    } else if (base >= 62 && base <= 72) {
      name = 'Swell ${ch6(62)}';
    } else if (base >= 74 && base <= 84) {
      name = 'Dip ${ch6(74)}';
    } else if (base >= 86 && base <= 96) {
      name = 'Diepe dip ${ch6(86)}';
    } else if (base >= 98 && base <= 108) {
      name = 'Onderbreking ${ch6(98)}';
    } else if (base >= 110 && base <= 120) {
      name = 'Rimpelspanning ${ch6(110)}';
    } else if (base == 130) {
      name = 'Voedingsspanning weggevallen';
    } else if (base == 132) {
      name = 'Meting actief';
    } else if (base >= 140 && base <= 150) {
      name = 'Snelle spanningsverandering (RVC) ${ch6(140)}';
    } else if (id >= 300 && id <= 305) {
      name = 'Langzame spanningsverandering ${_voltChannels6[id - 300]}';
    } else if (id >= 306 && id <= 311) {
      name = 'Overschrijding Plt ${_voltChannels6[id - 306]}';
    } else if (id == 312) {
      name = 'Overschrijding spanningsasymmetrie';
    } else if (id >= 313 && id <= 318) {
      name = 'Overschrijding THD ${_voltChannels6[id - 313]}';
    } else if (id >= 319 && id <= 324) {
      name = 'Overschrijding harmonischen ${_voltChannels6[id - 319]}';
    } else if (id >= 325 && id <= 330) {
      name = 'Overschrijding Pst ${_voltChannels6[id - 325]}';
    } else if (id >= 400 && id <= 403) {
      name = 'HF-omhullendetrigger U${id - 399}';
    } else {
      name = switch (id) {
        30 => 'Oscilloscoop-trigger',
        idRecA => 'Trigger oscilloscoop-recorder',
        idRecB => 'Trigger RMS-recorder',
        idRecS => 'Trigger rimpelspanningsrecorder',
        idRecTrans => 'Transiënt (transiëntenrecorder)',
        idRecHf => 'Transiënt (HF-analyser)',
        41 => 'Herstart apparaat',
        45 => 'Status binaire ingang',
        46 => 'Wijziging binaire ingang',
        47 => 'Energietellers geïnitialiseerd',
        404 => 'HF cross-trigger',
        405 => 'HF handmatige trigger',
        406 => 'HF intervaltrigger',
        _ => null,
      };
    }
    return name == null ? 'Onbekend event ($id)' : '$name$suffix';
  }

  String get eventCategory {
    final base = typeId - (_isStartStopId(typeId) && typeId.isOdd ? 1 : 0);
    if (base >= 74 && base <= 96) return 'dip';
    if (base >= 62 && base <= 72) return 'swell';
    if (base >= 98 && base <= 108) return 'interruption';
    if (base == 130) return 'interruption';
    return 'general';
  }
}

class MeasurementSession {
  final String deviceId;
  final String? location;
  final DateTime startTime;
  final DateTime endTime;
  final List<MeasurementPoint> voltageData;
  final List<MeasurementPoint> voltageData10s;
  final List<MeasurementPoint> currentData;
  final List<MeasurementPoint> currentData10s;
  final List<MeasurementPoint> frequencyData10min;
  final List<MeasurementPoint> frequencyData10s;
  final List<PqfEvent> events;
  final List<HarmonicPoint> harmonicCurrentData;
  final List<CosPhiPoint> cosPhiData;
  final List<MeasurementPoint> activePowerData;
  final List<MeasurementPoint> apparentPowerData;
  final List<MeasurementPoint> reactivePowerData;

  const MeasurementSession({
    required this.deviceId,
    this.location,
    required this.startTime,
    required this.endTime,
    required this.voltageData,
    required this.currentData,
    required this.frequencyData10min,
    required this.frequencyData10s,
    required this.events,
    this.voltageData10s = const [],
    this.currentData10s = const [],
    this.harmonicCurrentData = const [],
    this.cosPhiData = const [],
    this.activePowerData = const [],
    this.apparentPowerData = const [],
    this.reactivePowerData = const [],
  });

  Duration get duration => endTime.difference(startTime);

  double? get avgVoltageL1 {
    if (voltageData.isEmpty) return null;
    final vals = voltageData
        .map((p) => p.values['V_L1'])
        .whereType<double>()
        .toList();
    if (vals.isEmpty) return null;
    return vals.reduce((a, b) => a + b) / vals.length;
  }

  double? get avgVoltageL2 {
    if (voltageData.isEmpty) return null;
    final vals = voltageData
        .map((p) => p.values['V_L2'])
        .whereType<double>()
        .toList();
    if (vals.isEmpty) return null;
    return vals.reduce((a, b) => a + b) / vals.length;
  }

  double? get avgVoltageL3 {
    if (voltageData.isEmpty) return null;
    final vals = voltageData
        .map((p) => p.values['V_L3'])
        .whereType<double>()
        .toList();
    if (vals.isEmpty) return null;
    return vals.reduce((a, b) => a + b) / vals.length;
  }

  double? get avgFrequency {
    final data = frequencyData10s.isNotEmpty
        ? frequencyData10s
        : frequencyData10min;
    if (data.isEmpty) return null;
    final vals = data
        .map((p) => p.values['Hz'])
        .whereType<double>()
        .toList();
    if (vals.isEmpty) return null;
    return vals.reduce((a, b) => a + b) / vals.length;
  }
}
