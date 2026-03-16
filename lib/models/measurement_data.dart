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

class PqfEvent {
  final DateTime time;
  final int typeId;

  const PqfEvent({
    required this.time,
    required this.typeId,
  });

  String get eventName {
    switch (typeId) {
      case 0x0084:
        return 'Dip Start';
      case 0x0085:
        return 'Dip End';
      case 0x002F:
        return 'Swell Start';
      case 0x002D:
        return 'Interruption';
      case 0x03F2:
        return 'General Event';
      case 0x03FD:
        return 'HF Event';
      default:
        return 'Unknown (0x${typeId.toRadixString(16).padLeft(4, '0')})';
    }
  }

  String get eventCategory {
    switch (typeId) {
      case 0x0084:
      case 0x0085:
        return 'dip';
      case 0x002F:
        return 'swell';
      case 0x002D:
        return 'interruption';
      default:
        return 'general';
    }
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
