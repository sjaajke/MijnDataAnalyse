import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/measurement_provider.dart';
import '../services/en50160_analysis.dart';
import '../services/en50160_pdf.dart';
import '../widgets/chart_wrapper.dart';

class En50160Screen extends StatelessWidget {
  const En50160Screen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<MeasurementProvider>().session;

    if (session == null) {
      return _EmptyState(
          message: 'Geen data geladen.\nLaad een PQF-map om te beginnen.');
    }

    final analysis = analyzeEn50160(session);

    if (!analysis.hasEnoughData) {
      final days = analysis.dataDuration.inHours / 24.0;
      return _EmptyState(
        message: 'Onvoldoende data voor EN 50160 analyse.\n'
            'Aanwezig: ${days.toStringAsFixed(1)} dag(en) — minimaal 7 dagen vereist.',
        icon: Icons.hourglass_empty,
      );
    }

    return _AnalysisView(analysis: analysis);
  }
}

// ── Main analysis view ───────────────────────────────────────────────────────

class _AnalysisView extends StatelessWidget {
  final En50160Analysis analysis;
  const _AnalysisView({required this.analysis});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fmtPeriod = DateFormat('d MMM yyyy HH:mm');
    final pass = analysis.overallPass;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Overall banner ──────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: pass
                  ? Colors.green.withAlpha(30)
                  : Colors.red.withAlpha(30),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: pass ? Colors.green : Colors.red,
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  pass ? Icons.check_circle : Icons.cancel,
                  color: pass ? Colors.green : Colors.red,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pass
                            ? 'VOLDOET AAN EN 50160'
                            : 'VOLDOET NIET AAN EN 50160',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: pass ? Colors.green : Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${fmtPeriod.format(analysis.periodStart.toLocal())}  –  '
                        '${fmtPeriod.format(analysis.periodEnd.toLocal())}  '
                        '(${(analysis.dataDuration.inHours / 24.0).toStringAsFixed(1)} dagen)',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => exportEn50160Pdf(
                    context: context,
                    analysis: analysis,
                  ),
                  icon: const Icon(Icons.picture_as_pdf, size: 18),
                  label: const Text('PDF'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Summary chips row ───────────────────────────────────────────
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: analysis.allChecks
                .map((c) => _StatusChip(check: c))
                .toList(),
          ),
          const SizedBox(height: 20),

          // ── Parameter cards ─────────────────────────────────────────────
          _SectionHeader(title: 'Netfrequentie'),
          _CheckCard(check: analysis.frequency95, unit: 'Hz', limitLine: 50.5, lowerLimitLine: 49.5),
          const SizedBox(height: 8),
          _CheckCard(check: analysis.frequency100, unit: 'Hz', limitLine: 52.0, lowerLimitLine: 47.0),
          const SizedBox(height: 16),

          _SectionHeader(title: 'Spanningsniveau'),
          _CheckCard(check: analysis.voltageL1, unit: 'V', limitLine: 253, lowerLimitLine: 207),
          const SizedBox(height: 8),
          _CheckCard(check: analysis.voltageL2, unit: 'V', limitLine: 253, lowerLimitLine: 207),
          const SizedBox(height: 8),
          _CheckCard(check: analysis.voltageL3, unit: 'V', limitLine: 253, lowerLimitLine: 207),
          const SizedBox(height: 16),

          _SectionHeader(title: 'Spanningsonbalans'),
          _CheckCard(check: analysis.unbalance, unit: '%', limitLine: 2.0),
          const SizedBox(height: 24),

          // ── Note ────────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'Opmerkingen:\n'
              '- Onbalans berekend als (max-min)/gemiddelde x 100% (benadering).\n'
              '- Frequentie: ${analysis.frequency95.totalSamples} meetwaarden.\n'
              '- Flicker (Plt) en transienten zijn niet opgenomen.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: Colors.white54),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Status chip ──────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  final En50160Check check;
  const _StatusChip({required this.check});

  @override
  Widget build(BuildContext context) {
    final color = switch (check.status) {
      En50160Status.pass => Colors.green,
      En50160Status.fail => Colors.red,
      En50160Status.noData => Colors.grey,
    };
    final label = switch (check.status) {
      En50160Status.pass => 'OK',
      En50160Status.fail => 'FAIL',
      En50160Status.noData => '–',
    };
    return Chip(
      avatar: Icon(
        check.status == En50160Status.pass
            ? Icons.check_circle_outline
            : check.status == En50160Status.fail
                ? Icons.cancel_outlined
                : Icons.remove_circle_outline,
        size: 16,
        color: color,
      ),
      label: Text(
        '${check.name}  $label',
        style: TextStyle(fontSize: 11, color: color),
      ),
      backgroundColor: color.withAlpha(25),
      side: BorderSide(color: color.withAlpha(80)),
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}

// ── Section header ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(title,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(color: Colors.white70)),
      );
}

// ── Check card ───────────────────────────────────────────────────────────────

class _CheckCard extends StatefulWidget {
  final En50160Check check;
  final String unit;
  final double limitLine;
  final double? lowerLimitLine;

  const _CheckCard({
    required this.check,
    required this.unit,
    required this.limitLine,
    this.lowerLimitLine,
  });

  @override
  State<_CheckCard> createState() => _CheckCardState();
}

class _CheckCardState extends State<_CheckCard> {
  bool _showChart = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.check;
    final theme = Theme.of(context);
    final pass = c.status == En50160Status.pass;
    final noData = c.status == En50160Status.noData;

    final statusColor = noData
        ? Colors.grey
        : pass
            ? Colors.green
            : Colors.red;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Title row ───────────────────────────────────────────────
            Row(
              children: [
                Icon(
                  noData
                      ? Icons.remove_circle_outline
                      : pass
                          ? Icons.check_circle_outline
                          : Icons.cancel_outlined,
                  color: statusColor,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(c.name,
                      style: theme.textTheme.titleSmall),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withAlpha(30),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                        color: statusColor.withAlpha(120), width: 1),
                  ),
                  child: Text(
                    noData
                        ? 'GEEN DATA'
                        : pass
                            ? 'VOLDOET'
                            : 'VOLDOET NIET',
                    style: TextStyle(
                        fontSize: 11,
                        color: statusColor,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // ── Limit description ────────────────────────────────────────
            Text(c.limitDescription,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: Colors.white60)),
            const SizedBox(height: 10),

            if (!noData) ...[
              // ── Stats row ────────────────────────────────────────────
              Wrap(
                spacing: 20,
                runSpacing: 6,
                children: [
                  _Stat(
                    label: 'Naleving',
                    value:
                        '${c.compliance.toStringAsFixed(2)}%',
                    highlight: !pass,
                  ),
                  _Stat(
                    label: 'Overschrijdingen',
                    value: '${c.violations} / ${c.totalSamples}',
                    highlight: c.violations > 0,
                  ),
                  if (c.pct95 != null)
                    _Stat(
                        label: '95e percentiel',
                        value:
                            '${c.pct95!.toStringAsFixed(2)} ${widget.unit}'),
                  if (c.maxVal != null)
                    _Stat(
                        label: 'Maximum',
                        value:
                            '${c.maxVal!.toStringAsFixed(2)} ${widget.unit}'),
                  if (c.minVal != null)
                    _Stat(
                        label: 'Minimum',
                        value:
                            '${c.minVal!.toStringAsFixed(2)} ${widget.unit}'),
                ],
              ),
              const SizedBox(height: 10),

              // ── Compliance bar ────────────────────────────────────────
              _ComplianceBar(compliance: c.compliance),
              const SizedBox(height: 10),

              // ── Chart toggle ──────────────────────────────────────────
              if (c.series.isNotEmpty)
                TextButton.icon(
                  onPressed: () =>
                      setState(() => _showChart = !_showChart),
                  icon: Icon(
                      _showChart
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 16),
                  label: Text(
                      _showChart
                          ? 'Grafiek verbergen'
                          : 'Toon tijdreeks',
                      style: const TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 28)),
                ),

              if (_showChart && c.series.isNotEmpty) ...[
                const SizedBox(height: 8),
                _MiniChart(
                  check: c,
                  unit: widget.unit,
                  upperLimit: widget.limitLine,
                  lowerLimit: widget.lowerLimitLine,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

// ── Stat tile ────────────────────────────────────────────────────────────────

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;

  const _Stat(
      {required this.label, required this.value, this.highlight = false});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 10, color: Colors.white54)),
          Text(value,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color:
                      highlight ? Colors.redAccent : Colors.white)),
        ],
      );
}

// ── Compliance bar ───────────────────────────────────────────────────────────

class _ComplianceBar extends StatelessWidget {
  final double compliance;
  const _ComplianceBar({required this.compliance});

  @override
  Widget build(BuildContext context) {
    final pass = compliance >= 95.0;
    final frac = (compliance / 100).clamp(0.0, 1.0);

    return LayoutBuilder(builder: (ctx, constraints) {
      final w = constraints.maxWidth;
      return Stack(
        children: [
          Container(
            height: 10,
            decoration: BoxDecoration(
              color: Colors.white12,
              borderRadius: BorderRadius.circular(5),
            ),
          ),
          // 95% marker
          Positioned(
            left: w * 0.95 - 1,
            child: Container(
                width: 2, height: 10, color: Colors.white38),
          ),
          // Fill
          FractionallySizedBox(
            widthFactor: frac,
            child: Container(
              height: 10,
              decoration: BoxDecoration(
                color: pass ? Colors.green : Colors.red,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          ),
          // 95% label
          Positioned(
            right: w * 0.05 + 4,
            child: Text('95%',
                style: const TextStyle(
                    fontSize: 8, color: Colors.white38)),
          ),
        ],
      );
    });
  }
}

// ── Mini time-series chart ───────────────────────────────────────────────────

class _MiniChart extends StatelessWidget {
  final En50160Check check;
  final String unit;
  final double upperLimit;
  final double? lowerLimit;

  const _MiniChart({
    required this.check,
    required this.unit,
    required this.upperLimit,
    this.lowerLimit,
  });

  @override
  Widget build(BuildContext context) {
    final series = check.series;
    if (series.isEmpty) return const SizedBox.shrink();

    // Downsample to max 500 points
    final step = (series.length / 500).ceil().clamp(1, series.length);
    final sampled = [
      for (int i = 0; i < series.length; i += step) series[i],
    ];

    final spots = sampled
        .map((e) =>
            FlSpot(e.$1.millisecondsSinceEpoch.toDouble(), e.$2))
        .toList();

    final minX = spots.first.x;
    final maxX = spots.last.x;

    final values = sampled.map((e) => e.$2).toList();
    final minVal = values.reduce((a, b) => a < b ? a : b);
    final padding = (upperLimit - (lowerLimit ?? upperLimit * 0.8)).abs() * 0.1;
    final minY = (lowerLimit != null
            ? lowerLimit! - padding
            : minVal - padding)
        .clamp(0.0, double.infinity);
    final maxY = upperLimit + padding;

    return SizedBox(
      height: 160,
      child: ChartWrapper(
        title: '',
        height: 160,
        chartData: LineChartData(
          minX: minX,
          maxX: maxX,
          minY: minY,
          maxY: maxY,
          clipData: const FlClipData.all(),
          gridData: FlGridData(
            show: true,
            getDrawingHorizontalLine: (_) => const FlLine(
                color: Colors.white12,
                strokeWidth: 1,
                dashArray: [4, 4]),
          ),
          borderData: FlBorderData(show: true),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 42,
                getTitlesWidget: (v, m) => SideTitleWidget(
                  meta: m,
                  child: Text(v.toStringAsFixed(1),
                      style: const TextStyle(fontSize: 9)),
                ),
              ),
            ),
            rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: (maxX - minX) / 5,
                getTitlesWidget: (v, m) {
                  if (v == m.min || v == m.max) {
                    return const SizedBox.shrink();
                  }
                  return SideTitleWidget(
                    meta: m,
                    child: Text(
                        formatXAxisLabel(v),
                        style: const TextStyle(fontSize: 8)),
                  );
                },
              ),
            ),
          ),
          extraLinesData: ExtraLinesData(
            horizontalLines: [
              // Upper limit
              HorizontalLine(
                y: upperLimit,
                color: Colors.redAccent,
                strokeWidth: 1.5,
                dashArray: [6, 4],
                label: HorizontalLineLabel(
                  show: true,
                  alignment: Alignment.topRight,
                  style: const TextStyle(
                      fontSize: 9, color: Colors.redAccent),
                  labelResolver: (_) =>
                      ' ${upperLimit.toStringAsFixed(1)} $unit',
                ),
              ),
              // Lower limit (if present)
              if (lowerLimit != null)
                HorizontalLine(
                  y: lowerLimit!,
                  color: Colors.redAccent,
                  strokeWidth: 1.5,
                  dashArray: [6, 4],
                  label: HorizontalLineLabel(
                    show: true,
                    alignment: Alignment.bottomRight,
                    style: const TextStyle(
                        fontSize: 9, color: Colors.redAccent),
                    labelResolver: (_) =>
                        ' ${lowerLimit!.toStringAsFixed(1)} $unit',
                  ),
                ),
            ],
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: false,
              color: check.status == En50160Status.pass
                  ? Colors.green
                  : Colors.orange,
              barWidth: 1,
              dotData: const FlDotData(show: false),
            ),
          ],
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => Colors.black87,
              getTooltipItems: (spots) => spots
                  .map((s) => LineTooltipItem(
                        '${s.y.toStringAsFixed(3)} $unit',
                        const TextStyle(
                            fontSize: 10, color: Colors.white),
                      ))
                  .toList(),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final String message;
  final IconData icon;

  const _EmptyState({
    required this.message,
    this.icon = Icons.analytics_outlined,
  });

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: Colors.white30),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 14, color: Colors.white54, height: 1.6),
            ),
          ],
        ),
      );
}
