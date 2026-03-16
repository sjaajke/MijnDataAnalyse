import 'dart:math';
import '../models/measurement_data.dart';

// ── EN 50160 limits (LV, synchronous network) ──────────────────────────────
class En50160Limits {
  static const double uNom = 230.0;

  // § 4.2 Power frequency (10-s intervals)
  static const double freq95Min = 49.5;
  static const double freq95Max = 50.5;
  static const double freq100Min = 47.0;
  static const double freq100Max = 52.0;

  // § 4.3 Voltage magnitude (10-min intervals)
  static const double volt95Min = uNom * 0.90; // 207 V
  static const double volt95Max = uNom * 1.10; // 253 V
  static const double volt100Min = uNom * 0.85; // 195.5 V
  static const double volt100Max = uNom * 1.10; // 253 V

  // § 4.5 Voltage unbalance (simplified: (max-min)/avg × 100)
  static const double unbalance95 = 2.0; // %
}

enum En50160Status { pass, fail, noData }

class En50160Check {
  final String name;
  final String limitDescription;
  final En50160Status status;
  final double compliance; // % of samples within limit
  final double? pct95; // 95th-percentile of the measured quantity
  final double? maxVal;
  final double? minVal;
  final double limitValue; // EN 50160 threshold for the compliance criterion
  final int totalSamples;
  final int violations;

  /// Paired (timestamp, value) for the time-series chart.
  final List<(DateTime, double)> series;

  const En50160Check({
    required this.name,
    required this.limitDescription,
    required this.status,
    required this.compliance,
    required this.limitValue,
    required this.totalSamples,
    required this.violations,
    required this.series,
    this.pct95,
    this.maxVal,
    this.minVal,
  });
}

class En50160Analysis {
  final bool hasEnoughData;
  final Duration dataDuration;
  final DateTime periodStart;
  final DateTime periodEnd;
  final String deviceId;
  final String? location;

  // Individual checks
  final En50160Check frequency95;
  final En50160Check frequency100;
  final En50160Check voltageL1;
  final En50160Check voltageL2;
  final En50160Check voltageL3;
  final En50160Check unbalance;

  const En50160Analysis({
    required this.hasEnoughData,
    required this.dataDuration,
    required this.periodStart,
    required this.periodEnd,
    required this.deviceId,
    this.location,
    required this.frequency95,
    required this.frequency100,
    required this.voltageL1,
    required this.voltageL2,
    required this.voltageL3,
    required this.unbalance,
  });

  List<En50160Check> get allChecks =>
      [frequency95, frequency100, voltageL1, voltageL2, voltageL3, unbalance];

  bool get overallPass =>
      hasEnoughData &&
      allChecks.every((c) =>
          c.status == En50160Status.pass || c.status == En50160Status.noData);
}

// ── Analysis engine ─────────────────────────────────────────────────────────

En50160Analysis analyzeEn50160(MeasurementSession session) {
  final duration = session.duration;
  final hasEnough = duration.inDays >= 7;

  final freqCheck95 = _checkFrequency95(session);
  final freqCheck100 = _checkFrequency100(session);
  final voltL1 = _checkVoltage(session, 'L1', 'V_L1');
  final voltL2 = _checkVoltage(session, 'L2', 'V_L2');
  final voltL3 = _checkVoltage(session, 'L3', 'V_L3');
  final unbal = _checkUnbalance(session);

  return En50160Analysis(
    hasEnoughData: hasEnough,
    dataDuration: duration,
    periodStart: session.startTime,
    periodEnd: session.endTime,
    deviceId: session.deviceId,
    location: session.location,
    frequency95: freqCheck95,
    frequency100: freqCheck100,
    voltageL1: voltL1,
    voltageL2: voltL2,
    voltageL3: voltL3,
    unbalance: unbal,
  );
}

// ── Helpers ─────────────────────────────────────────────────────────────────

double _pct(List<double> sorted, double p) {
  if (sorted.isEmpty) return 0;
  final idx = ((sorted.length - 1) * p / 100.0).round().clamp(0, sorted.length - 1);
  return sorted[idx];
}

En50160Check _checkFrequency95(MeasurementSession session) {
  final raw = session.frequencyData10s.isNotEmpty
      ? session.frequencyData10s
      : session.frequencyData10min;

  if (raw.isEmpty) {
    return En50160Check(
      name: 'Netfrequentie (95%)',
      limitDescription: '95% van de 10-s waarden binnen 49,5 – 50,5 Hz',
      status: En50160Status.noData,
      compliance: 0,
      limitValue: En50160Limits.freq95Max,
      totalSamples: 0,
      violations: 0,
      series: [],
    );
  }

  final series = raw
      .map((p) => p.values['Hz'])
      .whereType<double>()
      .toList();
  final pairs = <(DateTime, double)>[];
  for (final p in raw) {
    final v = p.values['Hz'];
    if (v != null) pairs.add((p.time, v));
  }

  final sorted = [...series]..sort();
  final violations = series
      .where((v) => v < En50160Limits.freq95Min || v > En50160Limits.freq95Max)
      .length;
  final compliance = series.isEmpty ? 0.0 : (series.length - violations) / series.length * 100;
  final pass = compliance >= 95.0;

  return En50160Check(
    name: 'Netfrequentie (95%-criterium)',
    limitDescription: '95% van 10-s waarden in [49,5 ; 50,5] Hz',
    status: pass ? En50160Status.pass : En50160Status.fail,
    compliance: compliance,
    limitValue: En50160Limits.freq95Max,
    totalSamples: series.length,
    violations: violations,
    series: pairs,
    pct95: _pct(sorted, 97.5), // spread around median
    maxVal: sorted.last,
    minVal: sorted.first,
  );
}

En50160Check _checkFrequency100(MeasurementSession session) {
  final raw = session.frequencyData10s.isNotEmpty
      ? session.frequencyData10s
      : session.frequencyData10min;

  if (raw.isEmpty) {
    return En50160Check(
      name: 'Netfrequentie (100%)',
      limitDescription: '100% van de waarden binnen 47 – 52 Hz',
      status: En50160Status.noData,
      compliance: 0,
      limitValue: En50160Limits.freq100Max,
      totalSamples: 0,
      violations: 0,
      series: [],
    );
  }

  final series = raw
      .map((p) => p.values['Hz'])
      .whereType<double>()
      .toList();
  final pairs = <(DateTime, double)>[];
  for (final p in raw) {
    final v = p.values['Hz'];
    if (v != null) pairs.add((p.time, v));
  }

  final sorted = [...series]..sort();
  final violations = series
      .where((v) => v < En50160Limits.freq100Min || v > En50160Limits.freq100Max)
      .length;
  final compliance = series.isEmpty ? 0.0 : (series.length - violations) / series.length * 100;

  return En50160Check(
    name: 'Netfrequentie (100%-criterium)',
    limitDescription: '100% van de waarden in [47 ; 52] Hz',
    status: violations == 0 ? En50160Status.pass : En50160Status.fail,
    compliance: compliance,
    limitValue: En50160Limits.freq100Max,
    totalSamples: series.length,
    violations: violations,
    series: pairs,
    maxVal: sorted.last,
    minVal: sorted.first,
  );
}

En50160Check _checkVoltage(
    MeasurementSession session, String phase, String key) {
  final raw = session.voltageData;

  if (raw.isEmpty) {
    return En50160Check(
      name: 'Spanning $phase (95%)',
      limitDescription: '95% van 10-min waarden in [207 ; 253] V',
      status: En50160Status.noData,
      compliance: 0,
      limitValue: En50160Limits.volt95Max,
      totalSamples: 0,
      violations: 0,
      series: [],
    );
  }

  final pairs = <(DateTime, double)>[];
  for (final p in raw) {
    final v = p.values[key];
    if (v != null) pairs.add((p.time, v));
  }
  final series = pairs.map((e) => e.$2).toList();
  final sorted = [...series]..sort();

  // 95% criterion: within ±10%
  final viol95 = series
      .where((v) => v < En50160Limits.volt95Min || v > En50160Limits.volt95Max)
      .length;
  final compliance = series.isEmpty ? 0.0 : (series.length - viol95) / series.length * 100;
  final pass = compliance >= 95.0;

  // 100% criterion: within +10%/-15% (additional info)
  final viol100 = series
      .where((v) => v < En50160Limits.volt100Min || v > En50160Limits.volt100Max)
      .length;

  return En50160Check(
    name: 'Spanning $phase',
    limitDescription:
        '95% van 10-min waarden in [207 ; 253] V  |  100% in [195,5 ; 253] V\n'
        '100%-criterium: ${viol100 == 0 ? "OK" : "$viol100 overschrijdingen"}',
    status: pass ? En50160Status.pass : En50160Status.fail,
    compliance: compliance,
    limitValue: En50160Limits.volt95Max,
    totalSamples: series.length,
    violations: viol95,
    series: pairs,
    pct95: _pct(sorted, 95),
    maxVal: sorted.last,
    minVal: sorted.first,
  );
}

En50160Check _checkUnbalance(MeasurementSession session) {
  final raw = session.voltageData;

  if (raw.isEmpty) {
    return En50160Check(
      name: 'Spanningsonbalans',
      limitDescription: '95% van 10-min waarden <= 2%',
      status: En50160Status.noData,
      compliance: 0,
      limitValue: En50160Limits.unbalance95,
      totalSamples: 0,
      violations: 0,
      series: [],
    );
  }

  final pairs = <(DateTime, double)>[];
  for (final p in raw) {
    final l1 = p.values['V_L1'];
    final l2 = p.values['V_L2'];
    final l3 = p.values['V_L3'];
    if (l1 == null || l2 == null || l3 == null) continue;
    final avg = (l1 + l2 + l3) / 3;
    if (avg <= 0) continue;
    final maxV = max(l1, max(l2, l3));
    final minV = min(l1, min(l2, l3));
    final unbal = (maxV - minV) / avg * 100;
    pairs.add((p.time, unbal));
  }

  if (pairs.isEmpty) {
    return En50160Check(
      name: 'Spanningsonbalans',
      limitDescription: '95% van 10-min waarden <= 2%',
      status: En50160Status.noData,
      compliance: 0,
      limitValue: En50160Limits.unbalance95,
      totalSamples: 0,
      violations: 0,
      series: [],
    );
  }

  final series = pairs.map((e) => e.$2).toList();
  final sorted = [...series]..sort();
  final violations = series.where((v) => v > En50160Limits.unbalance95).length;
  final compliance = (series.length - violations) / series.length * 100;

  return En50160Check(
    name: 'Spanningsonbalans (vereenvoudigd)',
    limitDescription: '95% van 10-min waarden <= 2%  [(max-min)/gem x 100%]',
    status: compliance >= 95.0 ? En50160Status.pass : En50160Status.fail,
    compliance: compliance,
    limitValue: En50160Limits.unbalance95,
    totalSamples: series.length,
    violations: violations,
    series: pairs,
    pct95: _pct(sorted, 95),
    maxVal: sorted.last,
    minVal: sorted.first,
  );
}
