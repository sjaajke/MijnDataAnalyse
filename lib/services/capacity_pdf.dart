import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' show BuildContext, ScaffoldMessenger, SnackBar, Text;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:provider/provider.dart';

import '../providers/bedrijfsgegevens_provider.dart';
import 'pdf_branding.dart';

/// Eén datapunt voor de grafiek: x in uren na start, y in ampère.
class ChartPoint {
  final double x;
  final double y;
  const ChartPoint(this.x, this.y);
}

/// Eén grafiek in het rapport — bijv. één per geïmporteerd CSV-bestand
/// (gemiddeld/RMS, min, max, max-200ms, max-sp, ...), elk met een lijn per
/// fase (L1/L2/L3/N). Standaard is dit een stroomgrafiek (A) met een
/// maximumdrempel; voor andere grootheden (bv. vermogen) kunnen [unit],
/// [showRatedLine] en [neutralLabel] worden aangepast.
class CapacityChartSection {
  final String title;
  final Map<String, List<ChartPoint>> series;
  final String unit;
  final bool showRatedLine;
  final String neutralLabel;
  const CapacityChartSection({
    required this.title,
    required this.series,
    this.unit = 'A',
    this.showRatedLine = true,
    this.neutralLabel = 'N',
  });
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

/// A single Titel/Tekst/Afbeelding note block in the report.
class CapacityNote {
  final String? title;
  final String? bodyText;
  final File? image;

  const CapacityNote({this.title, this.bodyText, this.image});
}

/// Algemene gegevens: opdrachtgever, inspectieadres en inspectiebedrijf.
class GeneralInfo {
  final String clientCompany;
  final String clientAddress;
  final String clientPostalCity;
  final String clientContact;
  final String clientPhone;
  final String clientEmail;

  final String inspectionName;
  final String inspectionAddress;
  final String inspectionPostalCity;
  final String inspectionContact;
  final String inspectionPhone;
  final String inspectionEmail;

  final String inspectorCompany;
  final String inspectorAddress;
  final String inspectorPostalCity;
  final String inspectorPhone;
  final String inspectorEmail;
  final String inspectorContact;
  final String inspectorResponsible;

  const GeneralInfo({
    this.clientCompany = '',
    this.clientAddress = '',
    this.clientPostalCity = '',
    this.clientContact = '',
    this.clientPhone = '',
    this.clientEmail = '',
    this.inspectionName = '',
    this.inspectionAddress = '',
    this.inspectionPostalCity = '',
    this.inspectionContact = '',
    this.inspectionPhone = '',
    this.inspectionEmail = '',
    this.inspectorCompany = '',
    this.inspectorAddress = '',
    this.inspectorPostalCity = '',
    this.inspectorPhone = '',
    this.inspectorEmail = '',
    this.inspectorContact = '',
    this.inspectorResponsible = '',
  });

  bool get isEmpty =>
      clientCompany.trim().isEmpty &&
      clientAddress.trim().isEmpty &&
      clientPostalCity.trim().isEmpty &&
      clientContact.trim().isEmpty &&
      clientPhone.trim().isEmpty &&
      clientEmail.trim().isEmpty &&
      inspectionName.trim().isEmpty &&
      inspectionAddress.trim().isEmpty &&
      inspectionPostalCity.trim().isEmpty &&
      inspectionContact.trim().isEmpty &&
      inspectionPhone.trim().isEmpty &&
      inspectionEmail.trim().isEmpty &&
      inspectorCompany.trim().isEmpty &&
      inspectorAddress.trim().isEmpty &&
      inspectorPostalCity.trim().isEmpty &&
      inspectorPhone.trim().isEmpty &&
      inspectorEmail.trim().isEmpty &&
      inspectorContact.trim().isEmpty &&
      inspectorResponsible.trim().isEmpty;
}

/// Generates and saves a PDF capacity report.
Future<void> exportCapacityPdf({
  required BuildContext context,
  required String deviceId,
  required double ratedA,
  required DateTime periodStart,
  required DateTime periodEnd,
  required List<PhaseReportData> phases,
  List<CapacityChartSection>? chartSections,
  List<CapacityNote>? notes,
  GeneralInfo? generalInfo,
  String? introText,
}) async {
  final now = DateTime.now();
  final fmt = DateFormat('d MMM yyyy HH:mm');
  final fmtPeriod = DateFormat('d/M/yyyy HH:mm');
  final logo =
      loadCompanyLogo(context.read<BedrijfsgegevensProvider>().bedrijven);
  final noteImageBytes = [
    for (final n in notes ?? const <CapacityNote>[])
      n.image != null ? await n.image!.readAsBytes() : null,
  ];
  bool hasNoteContent(int i) {
    final n = notes![i];
    return (n.title != null && n.title!.trim().isNotEmpty) ||
        (n.bodyText != null && n.bodyText!.trim().isNotEmpty) ||
        noteImageBytes[i] != null;
  }

  final firstRenderedNoteIndex = notes == null
      ? -1
      : List<int>.generate(notes.length, (i) => i)
          .firstWhere((i) => hasNoteContent(i), orElse: () => -1);

  final totalHours = periodEnd.difference(periodStart).inSeconds / 3600.0;
  final renderedSections = (chartSections ?? const <CapacityChartSection>[])
      .where((s) => s.series.values.any((v) => v.isNotEmpty))
      .toList();

  // De eerste grafiek staat direct onder de Bezettingsgrafiek-sectie (geen
  // nieuwe pagina); daarna telkens twee grafieken per pagina.
  final chartWidgets = <pw.Widget>[];
  for (var i = 0; i < renderedSections.length; i++) {
    if (i >= 1 && (i - 1) % 2 == 0) chartWidgets.add(pw.NewPage());
    chartWidgets.add(_chartSectionWidget(
      title: renderedSections[i].title,
      series: renderedSections[i].series,
      unit: renderedSections[i].unit,
      showRatedLine: renderedSections[i].showRatedLine,
      neutralLabel: renderedSections[i].neutralLabel,
      ratedA: ratedA,
      periodStart: periodStart,
      totalHours: totalHours,
    ));
  }

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
      // ── Algemene gegevens ────────────────────────────────────────────────────
      if (generalInfo != null && !generalInfo.isEmpty) ...[
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Text('Stroom Capaciteitsrapport',
                  style: pw.TextStyle(
                      fontSize: 22, fontWeight: pw.FontWeight.bold)),
            ),
            if (logo != null) pw.Image(logo, width: 40, height: 40),
          ],
        ),
        pw.Divider(thickness: 1.5, color: PdfColors.grey400),
        pw.SizedBox(height: 12),
        pw.Text('Algemene gegevens',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        _generalInfoSection('Opdrachtgever', [
          ('Naam bedrijf', generalInfo.clientCompany),
          ('Adres', generalInfo.clientAddress),
          ('Postcode plaats', generalInfo.clientPostalCity),
          ('Contactpersoon', generalInfo.clientContact),
          ('Telefoonnummer', generalInfo.clientPhone),
          ('Mail', generalInfo.clientEmail),
        ]),
        pw.SizedBox(height: 16),
        _generalInfoSection('Inspectieadres', [
          ('Naam', generalInfo.inspectionName),
          ('Adres', generalInfo.inspectionAddress),
          ('Postcode plaats', generalInfo.inspectionPostalCity),
          ('Contactpersoon', generalInfo.inspectionContact),
          ('Telefoonnummer', generalInfo.inspectionPhone),
          ('Mail', generalInfo.inspectionEmail),
        ]),
        pw.SizedBox(height: 16),
        _generalInfoSection('Inspectiebedrijf', [
          ('Naam bedrijf', generalInfo.inspectorCompany),
          ('Adres', generalInfo.inspectorAddress),
          ('Postcode plaats', generalInfo.inspectorPostalCity),
          ('Telefoon', generalInfo.inspectorPhone),
          ('Mail', generalInfo.inspectorEmail),
          ('Contactpersoon', generalInfo.inspectorContact),
          ('Auteur', generalInfo.inspectorResponsible),
        ]),
        pw.NewPage(),
      ],

      // ── Inleiding ────────────────────────────────────────────────────────────
      if (introText != null && introText.trim().isNotEmpty) ...[
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Text('Inleiding',
                  style: pw.TextStyle(
                      fontSize: 22, fontWeight: pw.FontWeight.bold)),
            ),
            if (logo != null) pw.Image(logo, width: 40, height: 40),
          ],
        ),
        pw.Divider(thickness: 1.5, color: PdfColors.grey400),
        pw.SizedBox(height: 8),
        pw.Text(introText.trim(), style: const pw.TextStyle(fontSize: 10)),
        pw.NewPage(),
      ],

      // ── Header ──────────────────────────────────────────────────────────────
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
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
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              if (logo != null) pw.Image(logo, width: 40, height: 40),
              pw.SizedBox(height: 4),
              pw.Text('Gegenereerd: ${fmt.format(now)}',
                  style: const pw.TextStyle(
                      fontSize: 8, color: PdfColors.grey500)),
            ],
          ),
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

      // ── Stroomgrafieken (één per aggregatievariant / CSV-bestand) ────────────
      ...chartWidgets,

      // ── Aanvullende notities (titel/tekst/afbeelding) ────────────────────────
      // De bijlage begint op een nieuwe pagina (ongeacht of de eerste
      // notitie een afbeelding heeft). Een notitie mét afbeelding krijgt
      // daarna steeds zijn eigen pagina; notities zonder afbeelding worden
      // gewoon direct onder elkaar geplaatst, zonder paginascheiding.
      if (notes != null)
        for (var i = 0; i < notes.length; i++)
          if (hasNoteContent(i)) ...[
            if (i == firstRenderedNoteIndex) ...[
              pw.NewPage(),
              pw.Text('Bijlage',
                  style: pw.TextStyle(
                      fontSize: 22, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 2),
            ] else if (noteImageBytes[i] != null) ...[
              pw.NewPage(),
            ] else ...[
              pw.Divider(thickness: 1, color: PdfColors.grey300),
              pw.SizedBox(height: 8),
            ],
            if (notes[i].title != null && notes[i].title!.trim().isNotEmpty)
              pw.Text(notes[i].title!.trim(),
                  style: pw.TextStyle(
                      fontSize: 14, fontWeight: pw.FontWeight.bold)),
            if (notes[i].bodyText != null &&
                notes[i].bodyText!.trim().isNotEmpty) ...[
              pw.SizedBox(height: 6),
              pw.Text(notes[i].bodyText!.trim(),
                  style: const pw.TextStyle(fontSize: 10)),
            ],
            if (noteImageBytes[i] != null) ...[
              pw.SizedBox(height: 10),
              pw.Image(pw.MemoryImage(noteImageBytes[i]!),
                  fit: pw.BoxFit.contain, height: 260),
            ],
            pw.SizedBox(height: 16),
          ],
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

pw.Widget _generalInfoSection(String title, List<(String, String)> rows) {
  final visibleRows = rows.where((r) => r.$2.trim().isNotEmpty).toList();
  if (visibleRows.isEmpty) return pw.SizedBox();

  return pw.Container(
    padding: const pw.EdgeInsets.all(10),
    decoration: pw.BoxDecoration(
      color: PdfColors.grey100,
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(title,
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        pw.Table(
          columnWidths: const {
            0: pw.FlexColumnWidth(1.1),
            1: pw.FlexColumnWidth(2.4),
          },
          children: [
            for (final (label, value) in visibleRows)
              pw.TableRow(children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 3),
                  child: pw.Text(label,
                      style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.grey700)),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 3),
                  child: pw.Text(value, style: const pw.TextStyle(fontSize: 10)),
                ),
              ]),
          ],
        ),
      ],
    ),
  );
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

/// Titel + grafiek + legenda voor één [CapacityChartSection]. Wanneer
/// [showRatedLine] false is (bv. voor vermogen, dat geen ingestelde limiet
/// kent) worden de max/70%/90%-referentielijnen weggelaten.
pw.Widget _chartSectionWidget({
  required String title,
  required Map<String, List<ChartPoint>> series,
  required double ratedA,
  required DateTime periodStart,
  required double totalHours,
  String unit = 'A',
  bool showRatedLine = true,
  String neutralLabel = 'N',
}) {
  const phaseColors = <String, PdfColor>{
    'L1': PdfColors.red,
    'L2': PdfColors.amber,
    'L3': PdfColors.blue,
    'N': PdfColors.grey600,
  };

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(title,
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 6),
      _buildLineChart(
        series: series,
        ratedA: ratedA,
        periodStart: periodStart,
        totalHours: totalHours,
        unit: unit,
        showRatedLine: showRatedLine,
      ),
      pw.SizedBox(height: 6),
      // Legenda
      pw.Row(children: [
        for (final entry in phaseColors.entries)
          if (series.containsKey(entry.key) &&
              series[entry.key]!.isNotEmpty) ...[
            pw.Container(width: 12, height: 3, color: entry.value),
            pw.SizedBox(width: 4),
            pw.Text(entry.key == 'N' ? neutralLabel : entry.key,
                style: const pw.TextStyle(fontSize: 8)),
            pw.SizedBox(width: 12),
          ],
        if (showRatedLine) ...[
          pw.Container(width: 12, height: 3, color: PdfColors.grey400),
          pw.SizedBox(width: 4),
          pw.Text('Max (${ratedA.toStringAsFixed(0)} $unit)',
              style: const pw.TextStyle(fontSize: 8)),
          pw.SizedBox(width: 12),
          pw.Container(width: 12, height: 2, color: PdfColors.green700),
          pw.SizedBox(width: 4),
          pw.Text('70% (${(ratedA * 0.70).toStringAsFixed(0)} $unit)',
              style: const pw.TextStyle(fontSize: 8)),
          pw.SizedBox(width: 12),
          pw.Container(width: 12, height: 2, color: PdfColors.red),
          pw.SizedBox(width: 4),
          pw.Text('90% (${(ratedA * 0.90).toStringAsFixed(0)} $unit)',
              style: const pw.TextStyle(fontSize: 8)),
        ],
      ]),
      pw.SizedBox(height: 16),
    ],
  );
}

pw.Widget _buildLineChart({
  required Map<String, List<ChartPoint>> series,
  required double ratedA,
  required DateTime periodStart,
  required double totalHours,
  String unit = 'A',
  bool showRatedLine = true,
}) {
  // Y-axis: 0 to max(ratedA, highest measured) with 5 ticks
  double maxY = showRatedLine ? ratedA : 0;
  for (final pts in series.values) {
    for (final p in pts) {
      if (p.y > maxY) maxY = p.y;
    }
  }
  maxY = (maxY * 1.05).ceilToDouble();
  if (maxY <= 0) maxY = 1;
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
          format: (v) => '${v.toStringAsFixed(0)} $unit',
          textStyle: const pw.TextStyle(fontSize: 7),
          divisions: true,
          divisionsColor: PdfColors.grey200,
        ),
      ),
      datasets: [
        if (showRatedLine) ...[
          // 70%-grens (groen/oranje)
          pw.LineDataSet<pw.PointChartValue>(
            data: [
              pw.PointChartValue(xTicks.first, ratedA * 0.70),
              pw.PointChartValue(xTicks.last, ratedA * 0.70),
            ],
            color: PdfColors.green700,
            lineWidth: 0.6,
            drawPoints: false,
          ),
          // 90%-grens (oranje/rood)
          pw.LineDataSet<pw.PointChartValue>(
            data: [
              pw.PointChartValue(xTicks.first, ratedA * 0.90),
              pw.PointChartValue(xTicks.last, ratedA * 0.90),
            ],
            color: PdfColors.red,
            lineWidth: 0.6,
            drawPoints: false,
          ),
          // Maximale stroom
          pw.LineDataSet<pw.PointChartValue>(
            data: [
              pw.PointChartValue(xTicks.first, ratedA),
              pw.PointChartValue(xTicks.last, ratedA),
            ],
            color: PdfColors.grey400,
            lineWidth: 0.8,
            drawPoints: false,
          ),
        ],
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
