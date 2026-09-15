import 'dart:math';
import '../models/measurement_data.dart';

// ── Status ────────────────────────────────────────────────────────────────────

enum PqStatus { conform, nietConform, geenData }

// ── EN 50160 harmonics voltage limits (§ 4.4, Table 1) ───────────────────────

const Map<int, double> _en50160VoltHarmonics = {
  3: 5.0, 5: 6.0, 7: 5.0, 9: 1.5, 11: 3.5, 13: 3.0,
  15: 0.5, 17: 2.0, 19: 1.5, 21: 0.5, 23: 1.5, 25: 1.5,
};

// ── Sub-results ───────────────────────────────────────────────────────────────

class MeetKwaliteit {
  final String resolutie;
  final String classificatie; // Class A / S / Onbekend
  final int aantalPunten;
  final Duration duur;
  final bool tijdstempelsOk;
  final String toelichting;

  const MeetKwaliteit({
    required this.resolutie,
    required this.classificatie,
    required this.aantalPunten,
    required this.duur,
    required this.tijdstempelsOk,
    required this.toelichting,
  });
}

class FaseStats {
  final String fase;
  final double gem;
  final double min;
  final double max;
  final double std;
  final double p05;
  final double p95;
  final double compliancePct; // % binnen limiet
  final int aantalPunten;
  final int overtredingen;
  final PqStatus status;

  const FaseStats({
    required this.fase,
    required this.gem,
    required this.min,
    required this.max,
    required this.std,
    required this.p05,
    required this.p95,
    required this.compliancePct,
    required this.aantalPunten,
    required this.overtredingen,
    required this.status,
  });
}

class SpanningsAnalyse {
  final double un;
  final List<FaseStats> fasen;
  final PqStatus status;

  const SpanningsAnalyse({
    required this.un,
    required this.fasen,
    required this.status,
  });

  bool get heeftData => fasen.any((f) => f.aantalPunten > 0);
}

class FrequentieStats {
  final double gem;
  final double min;
  final double max;
  final double std;
  final double compliance95Pct;
  final double compliance100Pct;
  final int aantalPunten;
  final PqStatus status95;
  final PqStatus status100;

  const FrequentieStats({
    required this.gem,
    required this.min,
    required this.max,
    required this.std,
    required this.compliance95Pct,
    required this.compliance100Pct,
    required this.aantalPunten,
    required this.status95,
    required this.status100,
  });
}

class HarmonischeFase {
  final String fase;
  final double thd; // %
  final Map<int, double> individu; // orde → %
  final List<int> overtredingen; // ordes boven EN 50160 limiet
  final PqStatus status;

  const HarmonischeFase({
    required this.fase,
    required this.thd,
    required this.individu,
    required this.overtredingen,
    required this.status,
  });
}

class HarmonischenAnalyse {
  final List<HarmonischeFase> fasen; // voltage harmonics (%)
  final List<HarmonischeFase> stroomFasen; // current harmonics (A)
  final bool heeftSpanningsHarmonischen;
  final bool heeftStroomHarmonischen;
  final PqStatus status;

  const HarmonischenAnalyse({
    required this.fasen,
    required this.stroomFasen,
    required this.heeftSpanningsHarmonischen,
    required this.heeftStroomHarmonischen,
    required this.status,
  });
}

class EventSamenvatting {
  final int dippen;
  final int swells;
  final int onderbrekingen;
  final int overige;
  final List<PqfEvent> events;

  const EventSamenvatting({
    required this.dippen,
    required this.swells,
    required this.onderbrekingen,
    required this.overige,
    required this.events,
  });

  int get totaal => dippen + swells + onderbrekingen + overige;
  PqStatus get status => totaal == 0 ? PqStatus.conform : PqStatus.nietConform;
}

class FlickerStats {
  final double pstGem;
  final double pstMax;
  final double pltGem;
  final double pltMax;
  final int overtredingenPst;
  final int overtredingenPlt;
  final int aantalPunten;
  final PqStatus status;

  const FlickerStats({
    required this.pstGem,
    required this.pstMax,
    required this.pltGem,
    required this.pltMax,
    required this.overtredingenPst,
    required this.overtredingenPlt,
    required this.aantalPunten,
    required this.status,
  });
}

class OnbalansStats {
  final double gem; // %
  final double max; // %
  final double p95; // %
  final int overtredingen;
  final int aantalPunten;
  final PqStatus status;

  const OnbalansStats({
    required this.gem,
    required this.max,
    required this.p95,
    required this.overtredingen,
    required this.aantalPunten,
    required this.status,
  });
}

// ── Top-level report ──────────────────────────────────────────────────────────

class SysteemcodeRapport {
  final DateTime gegenereerd;
  final String apparaat;
  final String? locatie;
  final DateTime periodeStart;
  final DateTime periodeEinde;
  final double un;

  final MeetKwaliteit meetkwaliteit;
  final SpanningsAnalyse spanning;
  final FrequentieStats? frequentie;
  final HarmonischenAnalyse harmonischen;
  final EventSamenvatting events;
  final FlickerStats? flicker;
  final OnbalansStats? onbalans;
  final List<String> aanbevelingen;

  const SysteemcodeRapport({
    required this.gegenereerd,
    required this.apparaat,
    this.locatie,
    required this.periodeStart,
    required this.periodeEinde,
    required this.un,
    required this.meetkwaliteit,
    required this.spanning,
    required this.frequentie,
    required this.harmonischen,
    required this.events,
    required this.flicker,
    required this.onbalans,
    required this.aanbevelingen,
  });

  PqStatus get eindOordeel {
    final checks = [
      spanning.status,
      if (frequentie != null) frequentie!.status95,
      if (frequentie != null) frequentie!.status100,
      harmonischen.status,
      if (onbalans != null) onbalans!.status,
      if (flicker != null) flicker!.status,
    ];
    if (checks.any((s) => s == PqStatus.nietConform)) return PqStatus.nietConform;
    if (checks.every((s) => s == PqStatus.geenData)) return PqStatus.geenData;
    return PqStatus.conform;
  }
}

// ── Analysis engine ───────────────────────────────────────────────────────────

SysteemcodeRapport analyseer(MeasurementSession session, double un) {
  final meetkwal = _meetKwaliteit(session);
  final spanning = _spanningsAnalyse(session, un);
  final freq = _frequentieAnalyse(session);
  final harm = _harmonischenAnalyse(session);
  final evts = _eventAnalyse(session);
  final flick = _flickerAnalyse(session);
  final onbal = _onbalansAnalyse(session, un);
  final aanbev = _aanbevelingen(spanning, freq, harm, evts, flick, onbal);

  return SysteemcodeRapport(
    gegenereerd: DateTime.now(),
    apparaat: session.deviceId,
    locatie: session.location,
    periodeStart: session.startTime,
    periodeEinde: session.endTime,
    un: un,
    meetkwaliteit: meetkwal,
    spanning: spanning,
    frequentie: freq,
    harmonischen: harm,
    events: evts,
    flicker: flick,
    onbalans: onbal,
    aanbevelingen: aanbev,
  );
}

// ── Section helpers ───────────────────────────────────────────────────────────

MeetKwaliteit _meetKwaliteit(MeasurementSession session) {
  final has10min = session.voltageData.isNotEmpty;
  final has10s = session.voltageData10s.isNotEmpty || session.frequencyData10s.isNotEmpty;
  final total = has10min ? session.voltageData.length : session.currentData.length;
  final duur = session.duration;

  String resolutie;
  String classificatie;
  String toelichting;

  if (has10min) {
    resolutie = '10-minuten aggregatie';
    classificatie = 'Class S (screening)';
    toelichting =
        '10-min waarden beschikbaar. Voldoet aan IEC 61000-4-30 Class S '
        'voor trendanalyse. Voor Class A zijn ook tijdstempel-synchronisatie '
        'en meetonzekerheidsverificatie vereist.';
  } else if (has10s) {
    resolutie = '10-seconden';
    classificatie = 'Class S/A (indicatief)';
    toelichting = '10-s frequentiewaarden beschikbaar. '
        'Zonder 10-min aggregatie is Class A niet verifieerbaar vanuit exportdata.';
  } else {
    resolutie = 'Onbekend';
    classificatie = 'Onbekend';
    toelichting = 'Onvoldoende metadata voor meetkwalificatie.';
  }

  return MeetKwaliteit(
    resolutie: resolutie,
    classificatie: classificatie,
    aantalPunten: total,
    duur: duur,
    tijdstempelsOk: true,
    toelichting: toelichting,
  );
}

SpanningsAnalyse _spanningsAnalyse(MeasurementSession session, double un) {
  final fasen = <FaseStats>[];
  for (final (fase, key) in [
    ('L1', 'V_L1'),
    ('L2', 'V_L2'),
    ('L3', 'V_L3'),
  ]) {
    final vals = session.voltageData
        .map((p) => p.values[key])
        .whereType<double>()
        .toList();
    if (vals.isEmpty) continue;
    final s = _statsOf(vals);
    final low = un * 0.90;
    final high = un * 1.10;
    final ov = vals.where((v) => v < low || v > high).length;
    final compl = (vals.length - ov) / vals.length * 100;
    fasen.add(FaseStats(
      fase: fase,
      gem: s.mean,
      min: s.min,
      max: s.max,
      std: s.std,
      p05: s.p05,
      p95: s.p95,
      compliancePct: compl,
      aantalPunten: vals.length,
      overtredingen: ov,
      status: compl >= 95 ? PqStatus.conform : PqStatus.nietConform,
    ));
  }

  final overall = fasen.isEmpty
      ? PqStatus.geenData
      : fasen.any((f) => f.status == PqStatus.nietConform)
          ? PqStatus.nietConform
          : PqStatus.conform;

  return SpanningsAnalyse(un: un, fasen: fasen, status: overall);
}

FrequentieStats? _frequentieAnalyse(MeasurementSession session) {
  final raw = session.frequencyData10s.isNotEmpty
      ? session.frequencyData10s
      : session.frequencyData10min;
  if (raw.isEmpty) return null;

  final vals = raw.map((p) => p.values['Hz']).whereType<double>().toList();
  if (vals.isEmpty) return null;

  final s = _statsOf(vals);
  final ov95 = vals.where((v) => v < 49.5 || v > 50.5).length;
  final ov100 = vals.where((v) => v < 47.0 || v > 52.0).length;
  final c95 = (vals.length - ov95) / vals.length * 100;
  final c100 = (vals.length - ov100) / vals.length * 100;

  return FrequentieStats(
    gem: s.mean,
    min: s.min,
    max: s.max,
    std: s.std,
    compliance95Pct: c95,
    compliance100Pct: c100,
    aantalPunten: vals.length,
    status95: c95 >= 95 ? PqStatus.conform : PqStatus.nietConform,
    status100: ov100 == 0 ? PqStatus.conform : PqStatus.nietConform,
  );
}

HarmonischenAnalyse _harmonischenAnalyse(MeasurementSession session) {
  // ── Voltage harmonics from channel data (DVB files: Vh2, Vh3, ...) ──
  final vHarm = <HarmonischeFase>[];
  for (final (fase, prefix) in [
    ('L1', 'Vh_L1_'),
    ('L2', 'Vh_L2_'),
    ('L3', 'Vh_L3_'),
    ('', 'Vh'), // single-phase / unphased: Vh2, Vh3, ...
  ]) {
    final individu = <int, double>{};
    for (int ord = 2; ord <= 40; ord++) {
      final key = prefix.endsWith('_') ? '$prefix$ord' : '$prefix$ord';
      final vals = session.voltageData
          .map((p) => p.values[key])
          .whereType<double>()
          .toList();
      if (vals.isNotEmpty) {
        individu[ord] = vals.reduce((a, b) => a + b) / vals.length;
      }
    }
    if (individu.isEmpty) continue;

    final thdKey = fase.isEmpty ? 'Vthd' : 'Vthd_$fase';
    final thdVals = session.voltageData
        .map((p) => p.values[thdKey])
        .whereType<double>()
        .toList();
    final thd = thdVals.isNotEmpty
        ? thdVals.reduce((a, b) => a + b) / thdVals.length
        : _calcThd(individu.values.toList());

    final overd = individu.entries
        .where((e) {
          final lim = _en50160VoltHarmonics[e.key];
          return lim != null && e.value > lim;
        })
        .map((e) => e.key)
        .toList();

    vHarm.add(HarmonischeFase(
      fase: fase.isEmpty ? 'L1' : fase,
      thd: thd,
      individu: individu,
      overtredingen: overd,
      status: overd.isEmpty && thd <= 8.0
          ? PqStatus.conform
          : PqStatus.nietConform,
    ));
    break; // single-phase first match is enough for unphased data
  }

  // Also look for simple 'Vthd' single-phase key
  if (vHarm.isEmpty) {
    for (final (fase, thdKey) in [('L1', 'Vthd'), ('L1', 'V_thd_L1')]) {
      final vals = session.voltageData
          .map((p) => p.values[thdKey])
          .whereType<double>()
          .toList();
      if (vals.isNotEmpty) {
        final thd = vals.reduce((a, b) => a + b) / vals.length;
        vHarm.add(HarmonischeFase(
          fase: fase,
          thd: thd,
          individu: const {},
          overtredingen: const [],
          status: thd <= 8.0 ? PqStatus.conform : PqStatus.nietConform,
        ));
        break;
      }
    }
  }

  // ── Current harmonics from HarmonicPoint data (PQF / FPQO) ──
  final iHarm = <HarmonischeFase>[];
  if (session.harmonicCurrentData.isNotEmpty) {
    final hd = session.harmonicCurrentData;
    for (final (fase, getter) in <(String, List<double> Function(HarmonicPoint))>[
      ('L1', (h) => h.l1),
      ('L2', (h) => h.l2),
      ('L3', (h) => h.l3),
    ]) {
      final lists = hd.map(getter).where((l) => l.isNotEmpty).toList();
      if (lists.isEmpty) continue;
      final nOrd = lists[0].length;
      final individu = <int, double>{};
      for (int i = 0; i < nOrd; i++) {
        final ord = i + 2;
        final avg = lists.map((l) => l[i]).reduce((a, b) => a + b) / lists.length;
        individu[ord] = avg;
      }
      final thd = _calcThd(individu.values.toList());
      iHarm.add(HarmonischeFase(
        fase: fase,
        thd: thd,
        individu: individu,
        overtredingen: const [], // no EN 50160 current limits
        status: PqStatus.geenData, // EN 50160 heeft geen stroomlimiet
      ));
    }
  }

  final heeftV = vHarm.isNotEmpty;
  final heeftI = iHarm.isNotEmpty;
  PqStatus overall;
  if (!heeftV && !heeftI) {
    overall = PqStatus.geenData;
  } else if (heeftV && vHarm.any((f) => f.status == PqStatus.nietConform)) {
    overall = PqStatus.nietConform;
  } else if (heeftV) {
    overall = PqStatus.conform;
  } else {
    overall = PqStatus.geenData; // only current data, can't judge
  }

  return HarmonischenAnalyse(
    fasen: vHarm,
    stroomFasen: iHarm,
    heeftSpanningsHarmonischen: heeftV,
    heeftStroomHarmonischen: heeftI,
    status: overall,
  );
}

EventSamenvatting _eventAnalyse(MeasurementSession session) {
  int dippen = 0, swells = 0, onderb = 0, overig = 0;
  for (final e in session.events) {
    switch (e.eventCategory) {
      case 'dip':
        dippen++;
      case 'swell':
        swells++;
      case 'interruption':
        onderb++;
      default:
        overig++;
    }
  }
  return EventSamenvatting(
    dippen: dippen,
    swells: swells,
    onderbrekingen: onderb,
    overige: overig,
    events: session.events,
  );
}

FlickerStats? _flickerAnalyse(MeasurementSession session) {
  // Look for Pst / Plt keys in voltage data
  final pstKeys = ['Pst', 'Pst_L1', 'Vflk', 'flicker_pst'];
  final pltKeys = ['Plt', 'Plt_L1', 'LongTermFlicker', 'flicker_plt'];

  List<double> findVals(List<String> keys) {
    for (final k in keys) {
      final vals = session.voltageData
          .map((p) => p.values[k])
          .whereType<double>()
          .toList();
      if (vals.isNotEmpty) return vals;
    }
    return [];
  }

  final pst = findVals(pstKeys);
  final plt = findVals(pltKeys);
  if (pst.isEmpty && plt.isEmpty) return null;

  final pstGem = pst.isNotEmpty ? pst.reduce((a, b) => a + b) / pst.length : 0.0;
  final pstMax = pst.isNotEmpty ? pst.reduce(max) : 0.0;
  final pltGem = plt.isNotEmpty ? plt.reduce((a, b) => a + b) / plt.length : 0.0;
  final pltMax = plt.isNotEmpty ? plt.reduce(max) : 0.0;
  final ovPst = pst.where((v) => v > 1.0).length;
  final ovPlt = plt.where((v) => v > 0.8).length;

  return FlickerStats(
    pstGem: pstGem,
    pstMax: pstMax,
    pltGem: pltGem,
    pltMax: pltMax,
    overtredingenPst: ovPst,
    overtredingenPlt: ovPlt,
    aantalPunten: max(pst.length, plt.length),
    status: (ovPst == 0 && ovPlt == 0) ? PqStatus.conform : PqStatus.nietConform,
  );
}

OnbalansStats? _onbalansAnalyse(MeasurementSession session, double un) {
  final data = session.voltageData;
  if (data.isEmpty) return null;

  final vals = <double>[];
  for (final p in data) {
    final l1 = p.values['V_L1'];
    final l2 = p.values['V_L2'];
    final l3 = p.values['V_L3'];
    if (l1 == null || l2 == null || l3 == null) continue;
    final avg = (l1 + l2 + l3) / 3;
    if (avg <= 0) continue;
    final unbal = ([l1, l2, l3].map((v) => (v - avg).abs()).reduce(max)) / avg * 100;
    vals.add(unbal);
  }
  if (vals.isEmpty) return null;

  final s = _statsOf(vals);
  final ov = vals.where((v) => v > 2.0).length;
  final compl = (vals.length - ov) / vals.length * 100;

  return OnbalansStats(
    gem: s.mean,
    max: s.max,
    p95: s.p95,
    overtredingen: ov,
    aantalPunten: vals.length,
    status: compl >= 95 ? PqStatus.conform : PqStatus.nietConform,
  );
}

List<String> _aanbevelingen(
  SpanningsAnalyse spanning,
  FrequentieStats? freq,
  HarmonischenAnalyse harm,
  EventSamenvatting events,
  FlickerStats? flicker,
  OnbalansStats? onbalans,
) {
  final list = <String>[];

  if (spanning.status == PqStatus.nietConform) {
    list.add('Spanning buiten ±10% Un: overweeg tap-instelling transformator te controleren of netverzwaring te raadplegen.');
  }
  if (freq != null && freq.status95 == PqStatus.nietConform) {
    list.add('Frequentieafwijkingen > ±0,5 Hz gedetecteerd: controleer netbelasting en regulatie van de netbeheerder.');
  }
  if (harm.status == PqStatus.nietConform) {
    list.add('Harmonische overschrijdingen aanwezig: overweeg passief of actief harmonisch filter (bijv. bij 5e of 7e orde als gevolg van vermogenselektronica).');
  }
  if (harm.heeftStroomHarmonischen && !harm.heeftSpanningsHarmonischen) {
    list.add('Stroom-harmonischen aanwezig (geen spanningsharmonischen gemeten): voer aanvullende THD-U meting uit ter beoordeling van netimpact.');
  }
  if (events.dippen > 10) {
    list.add('Hoog aantal spanningsdippen (${events.dippen}x): onderzoek oorzaak (bijv. motorstarten, kortsluitingen) en overweeg Dynamic Voltage Restorer (DVR) of UPS.');
  }
  if (events.onderbrekingen > 0) {
    list.add('Onderbrekingen gedetecteerd (${events.onderbrekingen}x): evalueer betrouwbaarheid van de voeding en overweeg redundante netaansluiting of UPS.');
  }
  if (flicker != null && flicker.status == PqStatus.nietConform) {
    list.add('Flicker overschreden (Pst > 1,0 of Plt > 0,8): identificeer de flickerbron (lassen, motoren) en overweeg flicker-compensatie.');
  }
  if (onbalans != null && onbalans.status == PqStatus.nietConform) {
    list.add('Spanningsonbalans > 2%: herbalanceer enkelfasige belastingen over de drie fasen of overweeg onbalanscompensator.');
  }
  if (list.isEmpty) {
    list.add('Geen directe maatregelen vereist op basis van beschikbare meetdata.');
  }
  return list;
}

// ── Math helpers ──────────────────────────────────────────────────────────────

class _Stats {
  final double mean, min, max, std, p05, p95;
  const _Stats(this.mean, this.min, this.max, this.std, this.p05, this.p95);
}

_Stats _statsOf(List<double> raw) {
  final vals = [...raw]..sort();
  final mean = vals.reduce((a, b) => a + b) / vals.length;
  final variance =
      vals.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) /
          vals.length;
  final p05 = vals[((vals.length - 1) * 0.05).round()];
  final p95 = vals[((vals.length - 1) * 0.95).round()];
  return _Stats(mean, vals.first, vals.last, sqrt(variance), p05, p95);
}

double _calcThd(List<double> harmonics) {
  if (harmonics.isEmpty) return 0;
  final sumSq = harmonics.fold<double>(0, (s, v) => s + v * v);
  // Return rss as %, assuming values already in % or A
  return sqrt(sumSq);
}
