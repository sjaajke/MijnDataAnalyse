import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart'
    show BuildContext, ScaffoldMessenger, SnackBar, Text;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'capacity_pdf.dart' show ChartPoint;

// ── Data containers ──────────────────────────────────────────────────────────

class OpnameSnapshotData {
  final DateTime time;
  final double iL1, iL2, iL3, iN;
  final double thdL1, thdL2, thdL3;
  final double cL1, cL2, cL3;
  final List<double> l1; // harmonic amplitudes h2..h(n)
  final List<double> l2;
  final List<double> l3;

  const OpnameSnapshotData({
    required this.time,
    required this.iL1,
    required this.iL2,
    required this.iL3,
    required this.iN,
    required this.thdL1,
    required this.thdL2,
    required this.thdL3,
    required this.cL1,
    required this.cL2,
    required this.cL3,
    required this.l1,
    required this.l2,
    required this.l3,
  });
}

// ── Main export function ─────────────────────────────────────────────────────

Future<void> exportOpnamePdf({
  required BuildContext context,
  required String deviceId,
  required DateTime periodStart,
  required DateTime periodEnd,
  required Map<String, List<ChartPoint>> currentSeries,
  required Map<String, List<ChartPoint>> thdSeries,
  required Map<String, List<ChartPoint>> cosPhiSeries,
  required OpnameSnapshotData snapshot,
}) async {
  final now = DateTime.now();
  final fmtGen = DateFormat('d MMM yyyy HH:mm');
  final fmtPeriod = DateFormat('d/M/yyyy HH:mm');
  final dur = periodEnd.difference(periodStart);
  final durStr =
      '${dur.inDays}d ${dur.inHours % 24}h ${dur.inMinutes % 60}m';
  final totalHours = dur.inSeconds / 3600.0;

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
        pw.Text('PQAnalyse — Opname-rapport',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500)),
        pw.Text('Pagina ${ctx.pageNumber} / ${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500)),
      ],
    ),
    build: (ctx) => [
      // ── Header ─────────────────────────────────────────────────────────────
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Opname-rapport',
                    style: pw.TextStyle(
                        fontSize: 22, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 2),
                pw.Text(deviceId,
                    style: const pw.TextStyle(
                        fontSize: 11, color: PdfColors.grey700)),
              ],
            ),
          ),
          pw.Text('Gegenereerd: ${fmtGen.format(now)}',
              style: const pw.TextStyle(
                  fontSize: 8, color: PdfColors.grey500)),
        ],
      ),
      pw.Divider(thickness: 1.5, color: PdfColors.grey400),
      pw.SizedBox(height: 8),

      // ── Meta info ──────────────────────────────────────────────────────────
      pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: PdfColors.grey100,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
          border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
        ),
        child: pw.Row(children: [
          _infoBlock('Periode',
              '${fmtPeriod.format(periodStart.toLocal())}  →  '
                  '${fmtPeriod.format(periodEnd.toLocal())}'),
          pw.SizedBox(width: 24),
          _infoBlock('Duur', durStr),
        ]),
      ),
      pw.SizedBox(height: 16),

      // ── Momentopname ───────────────────────────────────────────────────────
      pw.Text('Momentopname — ${DateFormat('d/M/yyyy HH:mm').format(snapshot.time.toLocal())}',
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 6),
      _snapshotTable(snapshot),
      pw.SizedBox(height: 16),

      // ── Stroom tijdreeks ───────────────────────────────────────────────────
      if (currentSeries.values.any((s) => s.isNotEmpty)) ...[
        pw.Text('Stroom (A) — 10-min gemiddelden',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        _lineChart(
          series: currentSeries,
          colors: {
            'L1': PdfColors.red,
            'L2': PdfColors.amber,
            'L3': PdfColors.blue,
            'N': PdfColors.grey600,
          },
          periodStart: periodStart,
          totalHours: totalHours,
          yLabel: 'A',
          height: 170,
        ),
        _chartLegend({'L1': PdfColors.red, 'L2': PdfColors.amber,
            'L3': PdfColors.blue, 'N': PdfColors.grey600},
            currentSeries),
        pw.SizedBox(height: 14),
      ],

      // ── THD tijdreeks ──────────────────────────────────────────────────────
      if (thdSeries.values.any((s) => s.isNotEmpty)) ...[
        pw.Text('Totale harmonische vervorming stroom THD (%)',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        _lineChart(
          series: thdSeries,
          colors: {
            'L1': PdfColors.red,
            'L2': PdfColors.amber,
            'L3': PdfColors.blue,
          },
          periodStart: periodStart,
          totalHours: totalHours,
          yLabel: '%',
          height: 150,
          extraHLine: 8.0,
          extraHLineLabel: '8 % grens',
        ),
        _chartLegend({'L1': PdfColors.red, 'L2': PdfColors.amber,
            'L3': PdfColors.blue}, thdSeries),
        pw.SizedBox(height: 14),
      ],

      // ── Cos φ tijdreeks ────────────────────────────────────────────────────
      if (cosPhiSeries.values.any((s) => s.isNotEmpty)) ...[
        pw.Text('|cos φ| vermogensfactor',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        _lineChart(
          series: cosPhiSeries,
          colors: {
            'L1': PdfColors.red,
            'L2': PdfColors.amber,
            'L3': PdfColors.blue,
          },
          periodStart: periodStart,
          totalHours: totalHours,
          yLabel: '|cos φ|',
          height: 150,
          fixedMaxY: 1.05,
          extraHLine: 0.85,
          extraHLineLabel: '0.85',
        ),
        _chartLegend({'L1': PdfColors.red, 'L2': PdfColors.amber,
            'L3': PdfColors.blue}, cosPhiSeries),
        pw.SizedBox(height: 14),
      ],

      // ── Harmonisch spectrum tabel ──────────────────────────────────────────
      if (snapshot.l1.isNotEmpty) ...[
        pw.Text('Harmonisch spectrum — momentopname (A)',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        _harmonicTable(snapshot),
      ],
    ],
  ));

  final bytes = await pdf.save();

  if (!context.mounted) return;

  final fileName =
      'opname_${DateFormat('yyyyMMdd_HHmm').format(now)}.pdf';

  final savePath = await FilePicker.platform.saveFile(
    dialogTitle: 'Sla opname-rapport op',
    fileName: fileName,
    type: FileType.custom,
    allowedExtensions: ['pdf'],
  );

  if (savePath != null) {
    await File(savePath).writeAsBytes(bytes);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Rapport opgeslagen: $savePath'),
        duration: const Duration(seconds: 4),
      ));
    }
  }
}

// ── Helpers ──────────────────────────────────────────────────────────────────

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

pw.Widget _snapshotTable(OpnameSnapshotData s) {
  final bold = pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9);
  final cell9 = const pw.TextStyle(fontSize: 9);

  pw.Widget hdr(String t) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: pw.Text(t, style: bold),
      );

  pw.Widget val(String t, {PdfColor? color}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(t,
              style: pw.TextStyle(
                  fontSize: 9,
                  color: color)),
        ),
      );

  String phiLbl(double v) {
    final a = v.abs().toStringAsFixed(3);
    return v >= 0 ? '$a (ind)' : '$a (cap)';
  }

  PdfColor thdColor(double v) =>
      v > 8 ? PdfColors.orange700 : PdfColors.green700;
  PdfColor phiColor(double v) =>
      v.abs() >= 0.85 ? PdfColors.green700 : PdfColors.orange700;

  return pw.Table(
    border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
    columnWidths: const {
      0: pw.FlexColumnWidth(2.2),
      1: pw.FlexColumnWidth(1.8),
      2: pw.FlexColumnWidth(1.8),
      3: pw.FlexColumnWidth(1.8),
      4: pw.FlexColumnWidth(1.8),
    },
    children: [
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
        children: [hdr('Meting'), hdr('L1'), hdr('L2'), hdr('L3'), hdr('N')],
      ),
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.white),
        children: [
          pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: pw.Text('I (A)', style: cell9)),
          val('${s.iL1.toStringAsFixed(2)} A', color: PdfColors.red),
          val('${s.iL2.toStringAsFixed(2)} A', color: PdfColors.amber),
          val('${s.iL3.toStringAsFixed(2)} A', color: PdfColors.blue),
          val('${s.iN.toStringAsFixed(2)} A', color: PdfColors.grey600),
        ],
      ),
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey50),
        children: [
          pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: pw.Text('THD I (%)', style: cell9)),
          val('${s.thdL1.toStringAsFixed(2)} %', color: thdColor(s.thdL1)),
          val('${s.thdL2.toStringAsFixed(2)} %', color: thdColor(s.thdL2)),
          val('${s.thdL3.toStringAsFixed(2)} %', color: thdColor(s.thdL3)),
          val('—'),
        ],
      ),
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.white),
        children: [
          pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: pw.Text('cos φ', style: cell9)),
          val(phiLbl(s.cL1), color: phiColor(s.cL1)),
          val(phiLbl(s.cL2), color: phiColor(s.cL2)),
          val(phiLbl(s.cL3), color: phiColor(s.cL3)),
          val('—'),
        ],
      ),
    ],
  );
}

pw.Widget _lineChart({
  required Map<String, List<ChartPoint>> series,
  required Map<String, PdfColor> colors,
  required DateTime periodStart,
  required double totalHours,
  required String yLabel,
  double height = 160,
  double? fixedMaxY,
  double? extraHLine,
  String? extraHLineLabel,
}) {
  // Y range
  double maxY = fixedMaxY ?? 0;
  if (fixedMaxY == null) {
    for (final pts in series.values) {
      for (final p in pts) {
        if (p.y > maxY) maxY = p.y;
      }
    }
    maxY = (maxY * 1.1).ceilToDouble();
    if (maxY == 0) maxY = 1;
  }
  final yStep = (maxY / 4).ceilToDouble().clamp(0.01, double.infinity);
  final yTicks = <double>[];
  for (var v = 0.0; v <= maxY + yStep * 0.1; v += yStep) {
    yTicks.add(double.parse(v.toStringAsFixed(4)));
  }

  // X axis
  final n = totalHours > 0 ? 6 : 1;
  final xTicks =
      List<double>.generate(n + 1, (i) => totalHours * i / n);
  final xFmt = DateFormat('d/M HH:mm');

  final datasets = <pw.Dataset>[];

  // Extra horizontal reference line
  if (extraHLine != null) {
    final last = xTicks.last;
    datasets.add(pw.LineDataSet<pw.PointChartValue>(
      data: [
        pw.PointChartValue(xTicks.first, extraHLine),
        pw.PointChartValue(last, extraHLine),
      ],
      color: PdfColors.orange700,
      lineWidth: 0.7,
      drawPoints: false,
    ));
  }

  // Data series
  for (final entry in colors.entries) {
    final pts = series[entry.key];
    if (pts == null || pts.isEmpty) continue;
    datasets.add(pw.LineDataSet<pw.PointChartValue>(
      data: pts.map((p) => pw.PointChartValue(p.x, p.y)).toList(),
      color: entry.value,
      lineWidth: 0.9,
      drawPoints: false,
      isCurved: false,
    ));
  }

  if (datasets.isEmpty) return pw.SizedBox();

  return pw.SizedBox(
    height: height,
    child: pw.Chart(
      left: pw.ChartLegend(
        position: const pw.Alignment(-1.2, 0),
        textStyle: pw.TextStyle(
            fontSize: 7, color: PdfColors.grey600,
            fontWeight: pw.FontWeight.bold),
      ),
      grid: pw.CartesianGrid(
        xAxis: pw.FixedAxis<double>(
          xTicks,
          format: (v) {
            final dt = periodStart
                .add(Duration(seconds: (v * 3600).round()));
            return xFmt.format(dt.toLocal());
          },
          textStyle: const pw.TextStyle(fontSize: 6),
          divisions: true,
          divisionsColor: PdfColors.grey200,
        ),
        yAxis: pw.FixedAxis<double>(
          yTicks,
          format: (v) => v.toStringAsFixed(
              v < 10 && v != v.truncateToDouble() ? 1 : 0),
          textStyle: const pw.TextStyle(fontSize: 7),
          divisions: true,
          divisionsColor: PdfColors.grey200,
        ),
      ),
      datasets: datasets,
    ),
  );
}

pw.Widget _chartLegend(
    Map<String, PdfColor> colors, Map<String, List<ChartPoint>> series) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(top: 4),
    child: pw.Row(children: [
      for (final e in colors.entries)
        if (series[e.key] != null && series[e.key]!.isNotEmpty) ...[
          pw.Container(width: 14, height: 3, color: e.value),
          pw.SizedBox(width: 4),
          pw.Text(e.key, style: const pw.TextStyle(fontSize: 8)),
          pw.SizedBox(width: 12),
        ],
    ]),
  );
}

pw.Widget _harmonicTable(OpnameSnapshotData s) {
  final count = math.min(24, math.min(s.l1.length,
      math.min(s.l2.length, s.l3.length)));
  if (count == 0) return pw.SizedBox();

  final bold =
      pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8);
  final cell8 = const pw.TextStyle(fontSize: 8);

  pw.Widget hdr(String t) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: pw.Text(t, style: bold),
      );

  pw.Widget val(double v) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(v.toStringAsFixed(4), style: cell8),
        ),
      );

  // Split into two blocks of 12 to fit on page width
  final half = (count / 2).ceil();

  pw.Widget block(int from, int to) => pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.4),
        columnWidths: const {
          0: pw.FixedColumnWidth(28),
          1: pw.FlexColumnWidth(1),
          2: pw.FlexColumnWidth(1),
          3: pw.FlexColumnWidth(1),
        },
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColors.grey200),
            children: [hdr('Order'), hdr('L1 (A)'), hdr('L2 (A)'), hdr('L3 (A)')],
          ),
          for (int i = from; i < to && i < count; i++)
            pw.TableRow(
              decoration: pw.BoxDecoration(
                  color: i.isEven ? PdfColors.white : PdfColors.grey50),
              children: [
                pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(
                        horizontal: 4, vertical: 3),
                    child: pw.Text('h${i + 2}', style: bold)),
                val(s.l1[i]),
                val(s.l2[i]),
                val(s.l3[i]),
              ],
            ),
        ],
      );

  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(child: block(0, half)),
      pw.SizedBox(width: 8),
      pw.Expanded(child: block(half, count)),
    ],
  );
}
