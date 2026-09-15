import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/measurement_provider.dart';
import '../services/systeemcode_analysis.dart';
import '../services/systeemcode_pdf.dart';

class SysteemcodeScreen extends StatefulWidget {
  const SysteemcodeScreen({super.key});

  @override
  State<SysteemcodeScreen> createState() => _SysteemcodeScreenState();
}

class _SysteemcodeScreenState extends State<SysteemcodeScreen> {
  final _unController = TextEditingController(text: '230');
  SysteemcodeRapport? _rapport;

  @override
  void dispose() {
    _unController.dispose();
    super.dispose();
  }

  void _analyseer() {
    final session = context.read<MeasurementProvider>().session;
    if (session == null) return;
    final un = double.tryParse(_unController.text.trim()) ?? 230.0;
    setState(() => _rapport = analyseer(session, un));
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<MeasurementProvider>().session;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Toolbar ──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Text('Systeemcode elektriciteit',
                  style: theme.textTheme.titleLarge),
              const Spacer(),
              SizedBox(
                width: 100,
                child: TextField(
                  controller: _unController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Un',
                    isDense: true,
                    border: OutlineInputBorder(),
                    suffixText: 'V',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: session == null ? null : _analyseer,
                icon: const Icon(Icons.assessment, size: 18),
                label: const Text('Analyseer'),
              ),
              if (_rapport != null) ...[
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () =>
                      exportSysteemcodePdf(context: context, rapport: _rapport!),
                  icon: const Icon(Icons.picture_as_pdf, size: 18),
                  label: const Text('PDF exporteren'),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.clear),
                  tooltip: 'Wis rapport',
                  onPressed: () => setState(() => _rapport = null),
                ),
              ],
            ],
          ),
        ),
        const Divider(height: 1),

        // ── Content ──
        Expanded(
          child: _rapport == null
              ? _EmptyState(hasSession: session != null)
              : _RapportView(rapport: _rapport!),
        ),
      ],
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool hasSession;
  const _EmptyState({required this.hasSession});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.fact_check_outlined,
              size: 64, color: theme.colorScheme.outlineVariant),
          const SizedBox(height: 16),
          Text(
            hasSession
                ? 'Stel Un in en druk op "Analyseer"'
                : 'Laad eerst meetdata via de knop "Importeer"',
            style: theme.textTheme.bodyLarge
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          if (hasSession)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'De analyse toetst aan EN 50160 en IEC 61000-4-30/4-7',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outlineVariant),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Rapport view ──────────────────────────────────────────────────────────────

class _RapportView extends StatelessWidget {
  final SysteemcodeRapport rapport;
  const _RapportView({required this.rapport});

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          _HeaderCard(rapport: rapport),
          const SizedBox(height: 8),
          _MeetkwaliteitCard(mk: rapport.meetkwaliteit),
          const SizedBox(height: 8),
          _SpanningsCard(s: rapport.spanning),
          const SizedBox(height: 8),
          if (rapport.frequentie != null)
            _FrequentieCard(f: rapport.frequentie!),
          if (rapport.frequentie != null) const SizedBox(height: 8),
          _HarmonischenCard(h: rapport.harmonischen),
          const SizedBox(height: 8),
          _EventsCard(e: rapport.events),
          const SizedBox(height: 8),
          if (rapport.flicker != null)
            _FlickerCard(f: rapport.flicker!),
          if (rapport.flicker != null) const SizedBox(height: 8),
          if (rapport.onbalans != null)
            _OnbalansCard(o: rapport.onbalans!),
          if (rapport.onbalans != null) const SizedBox(height: 8),
          _AanbevelingenCard(lijst: rapport.aanbevelingen),
        ],
      ),
    );
  }
}

// ── Header card ───────────────────────────────────────────────────────────────

class _HeaderCard extends StatelessWidget {
  final SysteemcodeRapport rapport;
  const _HeaderCard({required this.rapport});

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd-MM-yyyy HH:mm');
    final status = rapport.eindOordeel;
    return _SectionCard(
      status: status,
      title: 'Eindoordeel netkwaliteit',
      subtitle:
          '${rapport.apparaat}${rapport.locatie != null ? " · ${rapport.locatie}" : ""}  |  '
          '${fmt.format(rapport.periodeStart)} – ${fmt.format(rapport.periodeEinde)}  |  '
          'Un = ${rapport.un.toStringAsFixed(0)} V',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatusBadge(status: status, groot: true),
          const SizedBox(height: 8),
          Text(
            'Gegenereerd: ${fmt.format(rapport.gegenereerd)}  |  '
            'Normen: EN 50160, IEC 61000-4-30, IEC 61000-4-7',
            style: const TextStyle(fontSize: 11),
          ),
        ],
      ),
    );
  }
}

// ── Meetkwaliteit ─────────────────────────────────────────────────────────────

class _MeetkwaliteitCard extends StatelessWidget {
  final MeetKwaliteit mk;
  const _MeetkwaliteitCard({required this.mk});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      status: PqStatus.conform,
      title: 'Stap 0 — Meetkwaliteit en classificatie',
      subtitle: mk.classificatie,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InfoRow('Classificatie', mk.classificatie),
          _InfoRow('Resolutie', mk.resolutie),
          _InfoRow('Meetpunten', mk.aantalPunten.toString()),
          _InfoRow('Meetduur', _durStr(mk.duur)),
          _InfoRow('Tijdstempels', mk.tijdstempelsOk ? 'Aanwezig' : 'Ontbreekt'),
          const SizedBox(height: 8),
          Text(mk.toelichting,
              style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }
}

// ── Spanning ──────────────────────────────────────────────────────────────────

class _SpanningsCard extends StatelessWidget {
  final SpanningsAnalyse s;
  const _SpanningsCard({required this.s});

  @override
  Widget build(BuildContext context) {
    if (!s.heeftData) {
      return _SectionCard(
        status: PqStatus.geenData,
        title: '1. Spanningskwaliteit',
        subtitle: 'EN 50160 §4.3 · ±10% Un · 95%-criterium',
        child: const Text('Geen spanningsdata beschikbaar.'),
      );
    }
    return _SectionCard(
      status: s.status,
      title: '1. Spanningskwaliteit',
      subtitle: 'EN 50160 §4.3 · ±10% Un · 95%-criterium',
      child: Column(
        children: [
          _TableHeader(
              cols: ['Fase', 'Gem (V)', 'Min', 'Max', 'Std', 'P05', 'P95', '% binnen ±10%', 'Oordeel']),
          ...s.fasen.map((f) => _TableRow(cells: [
                f.fase,
                f.gem.toStringAsFixed(1),
                f.min.toStringAsFixed(1),
                f.max.toStringAsFixed(1),
                f.std.toStringAsFixed(2),
                f.p05.toStringAsFixed(1),
                f.p95.toStringAsFixed(1),
                '${f.compliancePct.toStringAsFixed(1)}%',
                f.status == PqStatus.conform ? '✓' : '✗',
              ])),
          const SizedBox(height: 6),
          Text(
            'Limieten: ${(s.un * 0.9).toStringAsFixed(0)} – ${(s.un * 1.1).toStringAsFixed(0)} V  '
            '(±10% van Un = ${s.un.toStringAsFixed(0)} V)',
            style: const TextStyle(fontSize: 11),
          ),
        ],
      ),
    );
  }
}

// ── Frequentie ────────────────────────────────────────────────────────────────

class _FrequentieCard extends StatelessWidget {
  final FrequentieStats f;
  const _FrequentieCard({required this.f});

  @override
  Widget build(BuildContext context) {
    final overall = f.status95 == PqStatus.conform && f.status100 == PqStatus.conform
        ? PqStatus.conform
        : PqStatus.nietConform;
    return _SectionCard(
      status: overall,
      title: '2. Frequentie',
      subtitle: 'EN 50160 §4.2 · IEC 61000-4-30',
      child: Column(
        children: [
          _TableHeader(cols: ['', 'Gemiddeld', 'Min', 'Max', 'Std', 'Meetpunten', '% binnen limiet', 'Oordeel']),
          _TableRow(cells: [
            '95%  [49,5–50,5 Hz]',
            '${f.gem.toStringAsFixed(4)} Hz',
            '${f.min.toStringAsFixed(4)} Hz',
            '${f.max.toStringAsFixed(4)} Hz',
            '${f.std.toStringAsFixed(5)} Hz',
            f.aantalPunten.toString(),
            '${f.compliance95Pct.toStringAsFixed(2)}%',
            f.status95 == PqStatus.conform ? '✓' : '✗',
          ]),
          _TableRow(cells: [
            '100% [47–52 Hz]',
            '—', '—', '—', '—', '—',
            '${f.compliance100Pct.toStringAsFixed(2)}%',
            f.status100 == PqStatus.conform ? '✓' : '✗',
          ]),
        ],
      ),
    );
  }
}

// ── Harmonischen ──────────────────────────────────────────────────────────────

class _HarmonischenCard extends StatelessWidget {
  final HarmonischenAnalyse h;
  const _HarmonischenCard({required this.h});

  @override
  Widget build(BuildContext context) {
    if (!h.heeftSpanningsHarmonischen && !h.heeftStroomHarmonischen) {
      return _SectionCard(
        status: PqStatus.geenData,
        title: '3. Harmonischen',
        subtitle: 'EN 50160 §4.4 · IEC 61000-4-7',
        child: const Text('Geen harmonischendata beschikbaar.'),
      );
    }

    return _SectionCard(
      status: h.status,
      title: '3. Harmonischen',
      subtitle: 'EN 50160 §4.4 · IEC 61000-4-7 · THD ≤ 8%',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (h.heeftSpanningsHarmonischen) ...[
            Text('Spanningsharmonischen (%)',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            _TableHeader(cols: ['Fase', 'THD-U (%)', 'Dominante ordes', 'Overschreden', 'Oordeel']),
            ...h.fasen.map((f) {
              final dom = f.individu.entries
                  .where((e) => e.value >= 0.5)
                  .toList()
                ..sort((a, b) => b.value.compareTo(a.value));
              final domStr = dom.take(5)
                  .map((e) => 'H${e.key}=${e.value.toStringAsFixed(1)}%')
                  .join(', ');
              return _TableRow(cells: [
                f.fase,
                f.thd.toStringAsFixed(2),
                domStr.isEmpty ? '—' : domStr,
                f.overtredingen.isEmpty ? '—' : f.overtredingen.map((o) => 'H$o').join(', '),
                f.status == PqStatus.conform ? '✓' : f.status == PqStatus.geenData ? '—' : '✗',
              ]);
            }),
            const SizedBox(height: 8),
          ],
          if (h.heeftStroomHarmonischen) ...[
            Text('Stroomharmonischen (A gemiddeld, IEC 61000-4-7)',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            _TableHeader(cols: ['Fase', 'THD-I (A rss)', 'H3', 'H5', 'H7', 'H9', 'H11', 'H13']),
            ...h.stroomFasen.map((f) => _TableRow(cells: [
                  f.fase,
                  f.thd.toStringAsFixed(3),
                  ...[3, 5, 7, 9, 11, 13].map((o) =>
                      f.individu[o]?.toStringAsFixed(3) ?? '—'),
                ])),
            const SizedBox(height: 4),
            Text('Opmerking: EN 50160 specificeert geen stroomlimiet — rapportage ter informatie.',
                style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic)),
          ],
        ],
      ),
    );
  }
}

// ── Events ────────────────────────────────────────────────────────────────────

class _EventsCard extends StatelessWidget {
  final EventSamenvatting e;
  const _EventsCard({required this.e});

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd-MM-yyyy HH:mm:ss');
    return _SectionCard(
      status: e.totaal == 0 ? PqStatus.conform : PqStatus.nietConform,
      title: '4. Spanningsdippen en -onderbrekingen',
      subtitle: 'EN 50160 · IEC 61000-4-30',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TableHeader(cols: ['Type', 'Aantal']),
          _TableRow(cells: ['Spanningsdippen', e.dippen.toString()]),
          _TableRow(cells: ['Swells (overspanning)', e.swells.toString()]),
          _TableRow(cells: ['Onderbrekingen', e.onderbrekingen.toString()]),
          _TableRow(cells: ['Overige events', e.overige.toString()]),
          _TableRow(cells: ['Totaal', e.totaal.toString()]),
          if (e.events.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Events (max. 25 getoond)',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            _TableHeader(cols: ['Tijdstip', 'Type']),
            ...e.events.take(25).map((ev) => _TableRow(cells: [
                  fmt.format(ev.time),
                  ev.eventName,
                ])),
            if (e.events.length > 25)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('… en ${e.events.length - 25} meer',
                    style: const TextStyle(fontSize: 11)),
              ),
          ],
        ],
      ),
    );
  }
}

// ── Flicker ───────────────────────────────────────────────────────────────────

class _FlickerCard extends StatelessWidget {
  final FlickerStats f;
  const _FlickerCard({required this.f});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      status: f.status,
      title: '5. Flicker',
      subtitle: 'EN 50160 §4.6 · IEC 61000-4-15  |  Pst ≤ 1,0 · Plt ≤ 0,8',
      child: Column(
        children: [
          _TableHeader(cols: ['Parameter', 'Gemiddeld', 'Maximum', 'Overschrijdingen', 'Limiet', 'Oordeel']),
          _TableRow(cells: [
            'Pst (10 min)',
            f.pstGem.toStringAsFixed(3),
            f.pstMax.toStringAsFixed(3),
            f.overtredingenPst.toString(),
            '1,0',
            f.overtredingenPst == 0 ? '✓' : '✗',
          ]),
          _TableRow(cells: [
            'Plt (2 uur)',
            f.pltGem.toStringAsFixed(3),
            f.pltMax.toStringAsFixed(3),
            f.overtredingenPlt.toString(),
            '0,8',
            f.overtredingenPlt == 0 ? '✓' : '✗',
          ]),
        ],
      ),
    );
  }
}

// ── Onbalans ──────────────────────────────────────────────────────────────────

class _OnbalansCard extends StatelessWidget {
  final OnbalansStats o;
  const _OnbalansCard({required this.o});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      status: o.status,
      title: '6. Spanningsonbalans',
      subtitle: 'EN 50160 §4.5 · ≤ 2% (95%-criterium)',
      child: Column(
        children: [
          _TableHeader(cols: ['Gemiddeld', 'Maximum', 'P95', 'Overschrijdingen', 'Meetpunten', '% ≤ 2%', 'Oordeel']),
          _TableRow(cells: [
            '${o.gem.toStringAsFixed(3)}%',
            '${o.max.toStringAsFixed(3)}%',
            '${o.p95.toStringAsFixed(3)}%',
            o.overtredingen.toString(),
            o.aantalPunten.toString(),
            '${((o.aantalPunten - o.overtredingen) / o.aantalPunten * 100).toStringAsFixed(1)}%',
            o.status == PqStatus.conform ? '✓' : '✗',
          ]),
        ],
      ),
    );
  }
}

// ── Aanbevelingen ─────────────────────────────────────────────────────────────

class _AanbevelingenCard extends StatelessWidget {
  final List<String> lijst;
  const _AanbevelingenCard({required this.lijst});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      status: PqStatus.conform,
      title: '9. Aanbevelingen',
      subtitle: 'Technische maatregelen op basis van analyse',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: lijst
            .map((a) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• ', style: TextStyle(fontSize: 13)),
                      Expanded(child: Text(a, style: const TextStyle(fontSize: 13))),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }
}

// ── Shared UI components ──────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final PqStatus status;
  final String title;
  final String subtitle;
  final Widget child;

  const _SectionCard({
    required this.status,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: Theme.of(context).textTheme.titleMedium),
                      Text(subtitle,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant)),
                    ],
                  ),
                ),
                _StatusBadge(status: status),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final PqStatus status;
  final bool groot;
  const _StatusBadge({required this.status, this.groot = false});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      PqStatus.conform => ('CONFORM', Colors.green),
      PqStatus.nietConform => ('NIET CONFORM', Colors.red),
      PqStatus.geenData => ('GEEN DATA', Colors.grey),
    };
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: groot ? 12 : 8, vertical: groot ? 6 : 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        border: Border.all(color: color.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: groot ? 14 : 11)),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.w500, fontSize: 12)),
          ),
          Text(value, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  final List<String> cols;
  const _TableHeader({required this.cols});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
      ),
      child: _RowLayout(
        cells: cols,
        bold: true,
      ),
    );
  }
}

class _TableRow extends StatelessWidget {
  final List<String> cells;
  const _TableRow({required this.cells});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
              color: Theme.of(context)
                  .colorScheme
                  .outlineVariant
                  .withValues(alpha: 0.4)),
        ),
      ),
      child: _RowLayout(cells: cells),
    );
  }
}

class _RowLayout extends StatelessWidget {
  final List<String> cells;
  final bool bold;
  const _RowLayout({required this.cells, this.bold = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
      child: Row(
        children: cells
            .map((c) => Expanded(
                  child: Text(
                    c,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight:
                            bold ? FontWeight.w600 : FontWeight.normal),
                  ),
                ))
            .toList(),
      ),
    );
  }
}

// ── Utility ───────────────────────────────────────────────────────────────────

String _durStr(Duration d) {
  if (d.inDays >= 1) return '${d.inDays}d ${d.inHours.remainder(24)}h';
  if (d.inHours >= 1) return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
  return '${d.inMinutes}m';
}
