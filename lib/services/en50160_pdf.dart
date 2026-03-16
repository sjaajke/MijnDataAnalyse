import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart'
    show BuildContext, ScaffoldMessenger, SnackBar, Text;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'en50160_analysis.dart';

Future<void> exportEn50160Pdf({
  required BuildContext context,
  required En50160Analysis analysis,
}) async {
  final now = DateTime.now();
  final fmtDate = DateFormat('d MMM yyyy HH:mm');
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
        pw.Text('PQAnalyse - EN 50160 Rapport',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500)),
        pw.Text('Pagina ${ctx.pageNumber} / ${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500)),
      ],
    ),
    build: (ctx) => [
      // Header
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('EN 50160 Spanningskwaliteitsrapport',
                    style: pw.TextStyle(
                        fontSize: 20, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 2),
                pw.Text(
                    analysis.location != null
                        ? '${analysis.deviceId}  |  ${analysis.location}'
                        : analysis.deviceId,
                    style: const pw.TextStyle(
                        fontSize: 10, color: PdfColors.grey700)),
              ],
            ),
          ),
          pw.Text('Gegenereerd: ${fmtDate.format(now)}',
              style:
                  const pw.TextStyle(fontSize: 8, color: PdfColors.grey500)),
        ],
      ),
      pw.Divider(thickness: 1.5, color: PdfColors.grey400),
      pw.SizedBox(height: 8),

      // Overall result banner
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: pw.BoxDecoration(
          color: analysis.overallPass ? PdfColors.green50 : PdfColors.red50,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
          border: pw.Border.all(
            color: analysis.overallPass ? PdfColors.green700 : PdfColors.red700,
            width: 1,
          ),
        ),
        child: pw.Row(
          children: [
            pw.Text(
              analysis.overallPass
                  ? 'VOLDOET AAN EN 50160'
                  : 'VOLDOET NIET AAN EN 50160',
              style: pw.TextStyle(
                fontSize: 13,
                fontWeight: pw.FontWeight.bold,
                color: analysis.overallPass
                    ? PdfColors.green800
                    : PdfColors.red800,
              ),
            ),
            pw.Spacer(),
            pw.Text(
              '${_daysLabel(analysis.dataDuration)} data',
              style: const pw.TextStyle(
                  fontSize: 9, color: PdfColors.grey700),
            ),
          ],
        ),
      ),
      pw.SizedBox(height: 10),

      // Meta info
      pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: PdfColors.grey100,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
          border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
        ),
        child: pw.Row(children: [
          _infoBlock('Meetperiode',
              '${fmtPeriod.format(analysis.periodStart.toLocal())}  ->  ${fmtPeriod.format(analysis.periodEnd.toLocal())}'),
          pw.SizedBox(width: 24),
          _infoBlock('Nominale spanning', '230 V L-N  /  400 V L-L'),
          pw.SizedBox(width: 24),
          _infoBlock('Norm', 'EN 50160:2010+A1+A2+A3'),
        ]),
      ),
      pw.SizedBox(height: 16),

      // Results table
      pw.Text('Resultaten per parameter',
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 6),
      _resultsTable(analysis),
      pw.SizedBox(height: 16),

      // Per-check detail blocks
      pw.Text('Detail per parameter',
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 8),
      ...analysis.allChecks.map((c) => _checkDetail(c)),

      // Notes
      pw.SizedBox(height: 8),
      pw.Container(
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          color: PdfColors.grey100,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Opmerkingen',
                style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold, fontSize: 9)),
            pw.SizedBox(height: 4),
            pw.Text(
              '- Spanningsonbalans berekend als (max-min)/gemiddelde x 100% (benadering van negatieve-symmetrische component).\n'
              '- Frequentieanalyse gebruikt 10-s waarden indien beschikbaar, anders 10-min waarden.\n'
              '- Flicker (Plt) en transienten zijn niet opgenomen in dit rapport.',
              style: const pw.TextStyle(
                  fontSize: 8, color: PdfColors.grey700),
            ),
          ],
        ),
      ),
    ],
  ));

  final bytes = await pdf.save();

  if (!context.mounted) return;

  final fileName =
      'en50160_${DateFormat('yyyyMMdd_HHmm').format(now)}.pdf';

  final savePath = await FilePicker.platform.saveFile(
    dialogTitle: 'Sla EN 50160 rapport op',
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

// ── Helpers ─────────────────────────────────────────────────────────────────

String _daysLabel(Duration d) {
  final days = d.inHours / 24.0;
  return '${days.toStringAsFixed(1)} dagen';
}

pw.Widget _infoBlock(String label, String value) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label,
            style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 8,
                color: PdfColors.grey600)),
        pw.SizedBox(height: 2),
        pw.Text(value, style: const pw.TextStyle(fontSize: 9)),
      ],
    );

pw.Widget _resultsTable(En50160Analysis analysis) {
  final headerStyle = pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8);
  final cellStyle = const pw.TextStyle(fontSize: 8);

  pw.Widget cell(String text,
          {pw.TextStyle? style,
          pw.Alignment align = pw.Alignment.centerLeft}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: pw.Align(
            alignment: align,
            child: pw.Text(text, style: style ?? cellStyle)),
      );

  pw.Widget statusCell(En50160Check c) {
    final color = c.status == En50160Status.pass
        ? PdfColors.green700
        : c.status == En50160Status.fail
            ? PdfColors.red700
            : PdfColors.grey500;
    final label = c.status == En50160Status.pass
        ? 'VOLDOET'
        : c.status == En50160Status.fail
            ? 'VOLDOET NIET'
            : 'GEEN DATA';
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: pw.Text(label,
          style: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              color: color)),
    );
  }

  String fmt1(double? v) => v != null ? v.toStringAsFixed(1) : '-';

  return pw.Table(
    border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
    columnWidths: const {
      0: pw.FlexColumnWidth(2.0),
      1: pw.FlexColumnWidth(2.2),
      2: pw.FlexColumnWidth(0.8),
      3: pw.FlexColumnWidth(0.8),
      4: pw.FlexColumnWidth(0.8),
      5: pw.FlexColumnWidth(1.2),
    },
    children: [
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
        children: [
          cell('Parameter', style: headerStyle),
          cell('Grenswaarde', style: headerStyle),
          cell('95%-waarde', style: headerStyle),
          cell('Maximum', style: headerStyle),
          cell('Naleving', style: headerStyle),
          cell('Status', style: headerStyle),
        ],
      ),
      for (final (i, c) in analysis.allChecks.indexed)
        pw.TableRow(
          decoration: pw.BoxDecoration(
            color: i.isEven ? PdfColors.white : PdfColors.grey50,
          ),
          children: [
            cell(c.name),
            cell(_shortLimit(c)),
            cell(fmt1(c.pct95)),
            cell(fmt1(c.maxVal)),
            cell('${c.compliance.toStringAsFixed(1)}%'),
            statusCell(c),
          ],
        ),
    ],
  );
}

String _shortLimit(En50160Check c) {
  // Extract first line of limitDescription
  return c.limitDescription.split('\n').first;
}

pw.Widget _checkDetail(En50160Check c) {
  if (c.status == En50160Status.noData) return pw.SizedBox(height: 0);

  final color = c.status == En50160Status.pass
      ? PdfColors.green700
      : PdfColors.red700;
  final bgColor = c.status == En50160Status.pass
      ? PdfColors.green50
      : PdfColors.red50;

  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 8),
    child: pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(children: [
            pw.Text(c.name,
                style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold, fontSize: 9)),
            pw.Spacer(),
            pw.Container(
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: pw.BoxDecoration(
                color: bgColor,
                borderRadius:
                    const pw.BorderRadius.all(pw.Radius.circular(3)),
              ),
              child: pw.Text(
                c.status == En50160Status.pass ? 'VOLDOET' : 'VOLDOET NIET',
                style: pw.TextStyle(
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                    color: color),
              ),
            ),
          ]),
          pw.SizedBox(height: 4),
          pw.Text(c.limitDescription,
              style: const pw.TextStyle(
                  fontSize: 8, color: PdfColors.grey600)),
          pw.SizedBox(height: 6),
          // Stats row
          pw.Row(children: [
            _statBox('Naleving', '${c.compliance.toStringAsFixed(2)}%'),
            pw.SizedBox(width: 12),
            _statBox('Overschrijdingen', '${c.violations}/${c.totalSamples}'),
            pw.SizedBox(width: 12),
            if (c.pct95 != null)
              _statBox('95e percentiel', c.pct95!.toStringAsFixed(2)),
            if (c.pct95 != null) pw.SizedBox(width: 12),
            if (c.maxVal != null)
              _statBox('Maximum', c.maxVal!.toStringAsFixed(2)),
            if (c.maxVal != null) pw.SizedBox(width: 12),
            if (c.minVal != null)
              _statBox('Minimum', c.minVal!.toStringAsFixed(2)),
          ]),
          pw.SizedBox(height: 6),
          // Compliance bar
          _complianceBar(c.compliance),
        ],
      ),
    ),
  );
}

pw.Widget _statBox(String label, String value) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label,
            style: const pw.TextStyle(
                fontSize: 7, color: PdfColors.grey600)),
        pw.Text(value,
            style: pw.TextStyle(
                fontSize: 9, fontWeight: pw.FontWeight.bold)),
      ],
    );

pw.Widget _complianceBar(double compliance) {
  const w = 400.0;
  final frac = (compliance / 100).clamp(0.0, 1.0);
  final pass = compliance >= 95.0;

  return pw.Stack(
    children: [
      pw.Container(
          width: w,
          height: 10,
          decoration: pw.BoxDecoration(
              color: PdfColors.grey200,
              borderRadius:
                  const pw.BorderRadius.all(pw.Radius.circular(3)))),
      // 95% marker
      pw.Positioned(
        left: w * 0.95 - 0.5,
        child: pw.Container(
            width: 1, height: 10, color: PdfColors.grey500),
      ),
      // Fill
      pw.Container(
          width: w * frac,
          height: 10,
          decoration: pw.BoxDecoration(
              color: pass ? PdfColors.green700 : PdfColors.red700,
              borderRadius:
                  const pw.BorderRadius.all(pw.Radius.circular(3)))),
    ],
  );
}
