import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' show BuildContext, ScaffoldMessenger, SnackBar, Text;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Eén datapunt voor de grafiek: x in uren na start, y in ampère.
class ChartPoint {
  final double x;
  final double y;
  const ChartPoint(this.x, this.y);
}

/// Data needed to render one phase in the report.
class PhaseReportData {
  final String phase;
  final double avg;
  final double peak;
  final double rated;

  const PhaseReportData({
    required this.phase,
    required this.avg,
    required this.peak,
    required this.rated,
  });

  double get avgPct => rated > 0 ? avg / rated * 100 : 0;
  double get peakPct => rated > 0 ? peak / rated * 100 : 0;
  double get headroomAvg => rated - avg;
  double get headroomPeak => rated - peak;

  PdfColor get statusColor =>
      peakPct >= 90 ? PdfColors.red : peakPct >= 70 ? PdfColors.orange700 : PdfColors.green700;

  String get statusText =>
      peakPct >= 90 ? 'Kritiek' : peakPct >= 70 ? 'Let op' : 'OK';
}

/// Generates and saves a PDF capacity report.
Future<void> exportCapacityPdf({
  required BuildContext context,
  required String deviceId,
  required double ratedA,
  required DateTime periodStart,
  required DateTime periodEnd,
  required List<PhaseReportData> phases,
  Map<String, List<ChartPoint>>? chartSeries,
}) async {
  final now = DateTime.now();
  final fmt = DateFormat('d MMM yyyy HH:mm');
  final fmtPeriod = DateFormat('d/M/yyyy HH:mm');

  final pdf = pw.Document(
    theme: pw.ThemeData.withFont(
      base: pw.Font.helvetica(),
      bold: pw.Font.helveticaBold(),
    ),
  );

  pdf.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 36),
    footer: (ctx) => pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text('PQAnalyse - Stroom Capaciteitsrapport',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500)),
        pw.Text('Pagina ${ctx.pageNumber} / ${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500)),
      ],
    ),
    build: (ctx) => [
      // ── Header ──────────────────────────────────────────────────────────────
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Stroom Capaciteitsrapport',
                    style: pw.TextStyle(
                        fontSize: 22, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 2),
                pw.Text(deviceId,
                    style: const pw.TextStyle(
                        fontSize: 11, color: PdfColors.grey700)),
              ],
            ),
          ),
          pw.Text('Gegenereerd: ${fmt.format(now)}',
              style: const pw.TextStyle(
                  fontSize: 8, color: PdfColors.grey500)),
        ],
      ),
      pw.Divider(thickness: 1.5, color: PdfColors.grey400),
      pw.SizedBox(height: 8),

      // ── Meta info ────────────────────────────────────────────────────────────
      pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: PdfColors.grey100,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
          border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
        ),
        child: pw.Row(children: [
          _infoBlock('Analyseperiode',
              '${fmtPeriod.format(periodStart.toLocal())}  ->  ${fmtPeriod.format(periodEnd.toLocal())}'),
          pw.SizedBox(width: 24),
          _infoBlock('Maximale stroom (ingesteld)',
              '${ratedA.toStringAsFixed(0)} A'),
          pw.SizedBox(width: 24),
          _infoBlock('Aantal fasen', '${phases.length}'),
        ]),
      ),
      pw.SizedBox(height: 16),

      // ── Summary table ────────────────────────────────────────────────────────
      pw.Text('Resultaten per fase',
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 6),
      _summaryTable(phases, ratedA),
      pw.SizedBox(height: 16),

      // ── Per-phase utilization bars ───────────────────────────────────────────
      pw.Text('Bezettingsgrafiek',
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 8),
      ...phases.map((p) => _phaseBar(p)),
      pw.SizedBox(height: 16),

      // ── Stroomgrafiek ────────────────────────────────────────────────────────
      if (chartSeries != null && chartSeries.values.any((s) => s.isNotEmpty)) ...[
        pw.Text('Stroom over tijd',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        _buildLineChart(
          series: chartSeries,
          ratedA: ratedA,
          periodStart: periodStart,
          totalHours:
              periodEnd.difference(periodStart).inSeconds / 3600.0,
        ),
        pw.SizedBox(height: 6),
        // Legenda
        pw.Row(children: [
          for (final entry in {
            'L1': PdfColors.red,
            'L2': PdfColors.amber,
            'L3': PdfColors.blue,
            'N': PdfColors.grey600,
          }.entries)
            if (chartSeries.containsKey(entry.key) &&
                chartSeries[entry.key]!.isNotEmpty) ...[
              pw.Container(
                  width: 12,
                  height: 3,
                  color: entry.value),
              pw.SizedBox(width: 4),
              pw.Text(entry.key,
                  style: const pw.TextStyle(fontSize: 8)),
              pw.SizedBox(width: 12),
            ],
          pw.Container(width: 12, height: 3, color: PdfColors.grey400),
          pw.SizedBox(width: 4),
          pw.Text('Max (${ratedA.toStringAsFixed(0)} A)',
              style: const pw.TextStyle(fontSize: 8)),
        ]),
        pw.SizedBox(height: 16),
      ],

      // ── Legend ───────────────────────────────────────────────────────────────
      pw.Container(
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          color: PdfColors.grey100,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        ),
        child: pw.Row(children: [
          pw.Text('Status: ',
              style:
                  pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
          _legendItem(PdfColors.green700, 'OK  (piek < 70%)'),
          pw.SizedBox(width: 16),
          _legendItem(PdfColors.orange700, 'Let op  (70 - 90%)'),
          pw.SizedBox(width: 16),
          _legendItem(PdfColors.red, 'Kritiek  (>= 90%)'),
          pw.Spacer(),
          pw.Text('De piekstroom bepaalt de status.',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
        ]),
      ),
    ],
  ));

  final bytes = await pdf.save();

  if (!context.mounted) return;

  final fileName =
      'capaciteitsrapport_${DateFormat('yyyyMMdd_HHmm').format(now)}.pdf';

  final savePath = await FilePicker.platform.saveFile(
    dialogTitle: 'Sla PDF rapport op',
    fileName: fileName,
    type: FileType.custom,
    allowedExtensions: ['pdf'],
  );

  if (savePath != null) {
    await File(savePath).writeAsBytes(bytes);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Rapport opgeslagen: $savePath'),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }
}

// ── Helper widgets ──────────────────────────────────────────────────────────

pw.Widget _infoBlock(String label, String value) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label,
            style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 8,
                color: PdfColors.grey600)),
        pw.SizedBox(height: 2),
        pw.Text(value, style: const pw.TextStyle(fontSize: 10)),
      ],
    );

pw.Widget _legendItem(PdfColor color, String label) => pw.Row(children: [
      pw.Container(
          width: 10,
          height: 10,
          decoration: pw.BoxDecoration(color: color, shape: pw.BoxShape.circle)),
      pw.SizedBox(width: 4),
      pw.Text(label, style: const pw.TextStyle(fontSize: 9)),
    ]);

pw.Widget _summaryTable(List<PhaseReportData> phases, double ratedA) {
  final headerStyle =
      pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9);
  final cellStyle = const pw.TextStyle(fontSize: 9);

  pw.Widget cell(String text,
          {pw.TextStyle? style, pw.Alignment align = pw.Alignment.centerLeft}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: pw.Align(
            alignment: align,
            child: pw.Text(text, style: style ?? cellStyle)),
      );

  return pw.Table(
    border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
    columnWidths: const {
      0: pw.FlexColumnWidth(0.6),
      1: pw.FlexColumnWidth(1.0),
      2: pw.FlexColumnWidth(0.8),
      3: pw.FlexColumnWidth(1.0),
      4: pw.FlexColumnWidth(0.8),
      5: pw.FlexColumnWidth(1.1),
      6: pw.FlexColumnWidth(1.1),
      7: pw.FlexColumnWidth(0.9),
    },
    children: [
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
        children: [
          cell('Fase', style: headerStyle),
          cell('Gem. (A)', style: headerStyle),
          cell('Gem. (%)', style: headerStyle),
          cell('Piek (A)', style: headerStyle),
          cell('Piek (%)', style: headerStyle),
          cell('Ruimte gem.', style: headerStyle),
          cell('Ruimte piek', style: headerStyle),
          cell('Status', style: headerStyle),
        ],
      ),
      for (final p in phases)
        pw.TableRow(
          decoration: pw.BoxDecoration(
            color: phases.indexOf(p).isEven ? PdfColors.white : PdfColors.grey50,
          ),
          children: [
            cell(p.phase, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
            cell(p.avg.toStringAsFixed(1)),
            cell('${p.avgPct.toStringAsFixed(0)}%'),
            cell(p.peak.toStringAsFixed(1)),
            cell('${p.peakPct.toStringAsFixed(0)}%'),
            cell('${p.headroomAvg >= 0 ? '+' : ''}${p.headroomAvg.toStringAsFixed(1)} A'),
            cell(
              '${p.headroomPeak >= 0 ? '+' : ''}${p.headroomPeak.toStringAsFixed(1)} A',
              style: pw.TextStyle(
                  fontSize: 9,
                  color: p.headroomPeak < 0 ? PdfColors.red : null,
                  fontWeight: p.headroomPeak < 0 ? pw.FontWeight.bold : null),
            ),
            cell(p.statusText,
                style: pw.TextStyle(
                    fontSize: 9,
                    color: p.statusColor,
                    fontWeight: pw.FontWeight.bold)),
          ],
        ),
    ],
  );
}

pw.Widget _phaseBar(PhaseReportData p) {
  const barWidth = 300.0;
  const barHeight = 14.0;
  final avgFrac = (p.avgPct / 100).clamp(0.0, 1.0);
  final peakFrac = (p.peakPct / 100).clamp(0.0, 1.0);

  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 8),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.SizedBox(
          width: 20,
          child: pw.Text(p.phase,
              style:
                  pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
        ),
        pw.SizedBox(width: 8),
        pw.Stack(
          children: [
            // Background
            pw.Container(
                width: barWidth,
                height: barHeight,
                decoration: pw.BoxDecoration(
                    color: PdfColors.grey200,
                    borderRadius:
                        const pw.BorderRadius.all(pw.Radius.circular(3)))),
            // 70% zone line
            pw.Positioned(
              left: barWidth * 0.70 - 0.5,
              child: pw.Container(
                  width: 1,
                  height: barHeight,
                  color: PdfColors.grey400),
            ),
            // 90% zone line
            pw.Positioned(
              left: barWidth * 0.90 - 0.5,
              child: pw.Container(
                  width: 1,
                  height: barHeight,
                  color: PdfColors.grey400),
            ),
            // Average fill
            pw.Container(
                width: barWidth * avgFrac,
                height: barHeight,
                decoration: pw.BoxDecoration(
                    color: p.statusColor.shade(0.5),
                    borderRadius:
                        const pw.BorderRadius.all(pw.Radius.circular(3)))),
            // Peak marker (2px wide)
            pw.Positioned(
              left: (barWidth * peakFrac - 2).clamp(0.0, barWidth - 2),
              child: pw.Container(
                  width: 2,
                  height: barHeight,
                  color: p.statusColor),
            ),
          ],
        ),
        pw.SizedBox(width: 8),
        pw.SizedBox(
          width: 110,
          child: pw.Text(
            'gem. ${p.avg.toStringAsFixed(1)} A (${p.avgPct.toStringAsFixed(0)}%)   '
            'piek ${p.peak.toStringAsFixed(1)} A (${p.peakPct.toStringAsFixed(0)}%)',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ),
        pw.Spacer(),
        pw.Text(p.statusText,
            style: pw.TextStyle(
                fontSize: 9,
                color: p.statusColor,
                fontWeight: pw.FontWeight.bold)),
      ],
    ),
  );
}

pw.Widget _buildLineChart({
  required Map<String, List<ChartPoint>> series,
  required double ratedA,
  required DateTime periodStart,
  required double totalHours,
}) {
  // Y-axis: 0 to max(ratedA, highest measured) with 5 ticks
  double maxY = ratedA;
  for (final pts in series.values) {
    for (final p in pts) {
      if (p.y > maxY) maxY = p.y;
    }
  }
  maxY = (maxY * 1.05).ceilToDouble();
  final yStep = (maxY / 4).ceilToDouble();
  final yTicks = <double>[];
  for (var v = 0.0; v <= maxY + yStep * 0.1; v += yStep) {
    yTicks.add(v);
  }

  // X-axis: 0..totalHours with 6 ticks
  final n = totalHours > 0 ? 6 : 1;
  final xTicks = List<double>.generate(
      n + 1, (i) => totalHours * i / n);
  final fmt = DateFormat('d/M HH:mm');

  const phaseColors = <String, PdfColor>{
    'L1': PdfColors.red,
    'L2': PdfColors.amber,
    'L3': PdfColors.blue,
    'N': PdfColors.grey600,
  };

  return pw.SizedBox(
    height: 200,
    child: pw.Chart(
      grid: pw.CartesianGrid(
        xAxis: pw.FixedAxis<double>(
          xTicks,
          format: (v) {
            final dt = periodStart.add(
                Duration(seconds: (v * 3600).round()));
            return fmt.format(dt.toLocal());
          },
          textStyle: const pw.TextStyle(fontSize: 7),
          divisions: true,
          divisionsColor: PdfColors.grey200,
          angle: 0.4,
        ),
        yAxis: pw.FixedAxis<double>(
          yTicks,
          format: (v) => '${v.toStringAsFixed(0)} A',
          textStyle: const pw.TextStyle(fontSize: 7),
          divisions: true,
          divisionsColor: PdfColors.grey200,
        ),
      ),
      datasets: [
        // Maximale stroom als stippellijn
        pw.LineDataSet<pw.PointChartValue>(
          data: [
            pw.PointChartValue(xTicks.first, ratedA),
            pw.PointChartValue(xTicks.last, ratedA),
          ],
          color: PdfColors.grey400,
          lineWidth: 0.8,
          drawPoints: false,
        ),
        // Fase-lijnen
        for (final entry in phaseColors.entries)
          if (series[entry.key] != null && series[entry.key]!.isNotEmpty)
            pw.LineDataSet<pw.PointChartValue>(
              data: series[entry.key]!
                  .map((p) => pw.PointChartValue(p.x, p.y))
                  .toList(),
              color: entry.value,
              lineWidth: 1.0,
              drawPoints: false,
              isCurved: false,
            ),
      ],
    ),
  );
}
