import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' show BuildContext, ScaffoldMessenger, SnackBar, Text;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:provider/provider.dart';

import '../providers/bedrijfsgegevens_provider.dart';
import 'pdf_branding.dart';
import 'systeemcode_analysis.dart';

Future<void> exportSysteemcodePdf({
  required BuildContext context,
  required SysteemcodeRapport rapport,
}) async {
  final now = DateTime.now();
  final fmt = DateFormat('dd-MM-yyyy HH:mm');
  final fileName =
      'systeemcode_${DateFormat('yyyyMMdd_HHmm').format(now)}.pdf';
  final logo =
      loadCompanyLogo(context.read<BedrijfsgegevensProvider>().bedrijven);

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
        pw.Text('PQAnalyse - Systeemcode Netkwaliteitsrapport',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500)),
        pw.Text('Pagina ${ctx.pageNumber} / ${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500)),
      ],
    ),
    build: (ctx) => [
      // ── Titel ───────────────────────────────────────────────────────────────
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Netkwaliteitsrapport - Systeemcode elektriciteit',
                    style: pw.TextStyle(
                        fontSize: 20, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 2),
                pw.Text(
                  '${rapport.apparaat}'
                  '${rapport.locatie != null ? " - ${rapport.locatie}" : ""}',
                  style: const pw.TextStyle(
                      fontSize: 11, color: PdfColors.grey700),
                ),
              ],
            ),
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              if (logo != null) pw.Image(logo, width: 40, height: 40),
              pw.SizedBox(height: 4),
              pw.Text('Gegenereerd: ${fmt.format(rapport.gegenereerd)}',
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
              '${fmt.format(rapport.periodeStart.toLocal())}  tot  ${fmt.format(rapport.periodeEinde.toLocal())}'),
          pw.SizedBox(width: 24),
          _infoBlock('Nominale spanning (Un)',
              '${rapport.un.toStringAsFixed(0)} V'),
          pw.SizedBox(width: 24),
          _infoBlock('Normen', 'EN 50160, IEC 61000-4-30, IEC 61000-4-7'),
        ]),
      ),
      pw.SizedBox(height: 12),

      // ── Eindoordeel ──────────────────────────────────────────────────────────
      _sectionHeader('Eindoordeel netkwaliteit', rapport.eindOordeel),
      pw.SizedBox(height: 6),
      pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: _statusBgColor(rapport.eindOordeel),
          border: pw.Border.all(
              color: _statusColor(rapport.eindOordeel), width: 0.8),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        ),
        child: pw.Row(children: [
          pw.Container(
            width: 14,
            height: 14,
            decoration: pw.BoxDecoration(
                color: _statusColor(rapport.eindOordeel),
                shape: pw.BoxShape.circle),
          ),
          pw.SizedBox(width: 8),
          pw.Text(
            _statusLabel(rapport.eindOordeel),
            style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 13,
                color: _statusColor(rapport.eindOordeel)),
          ),
          pw.SizedBox(width: 16),
          pw.Text(
            'Meetkwaliteit: ${rapport.meetkwaliteit.classificatie}  |  '
            'Meetpunten: ${rapport.meetkwaliteit.aantalPunten}  |  '
            'Duur: ${_durStr(rapport.meetkwaliteit.duur)}',
            style: const pw.TextStyle(fontSize: 9),
          ),
        ]),
      ),
      pw.SizedBox(height: 16),

      // ── Stap 0: Meetkwaliteit ─────────────────────────────────────────────
      _sectionHeader('Stap 0 - Meetkwaliteit en classificatie',
          PqStatus.conform),
      pw.SizedBox(height: 6),
      _twoColTable([
        ['Classificatie', rapport.meetkwaliteit.classificatie],
        ['Resolutie', rapport.meetkwaliteit.resolutie],
        ['Meetpunten', rapport.meetkwaliteit.aantalPunten.toString()],
        ['Meetduur', _durStr(rapport.meetkwaliteit.duur)],
        ['Tijdstempels', rapport.meetkwaliteit.tijdstempelsOk ? 'Aanwezig' : 'Ontbreekt'],
      ]),
      pw.SizedBox(height: 4),
      pw.Text(rapport.meetkwaliteit.toelichting,
          style: const pw.TextStyle(
              fontSize: 9, color: PdfColors.grey700)),
      pw.SizedBox(height: 16),

      // ── 1. Spanning ───────────────────────────────────────────────────────
      _sectionHeader('1. Spanningskwaliteit  (EN 50160 §4.3, +-10% Un, 95%-criterium)',
          rapport.spanning.status),
      pw.SizedBox(height: 6),
      if (!rapport.spanning.heeftData)
        pw.Text('Geen spanningsdata beschikbaar.',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600))
      else ...[
        _dataTable(
          headers: ['Fase', 'Gem (V)', 'Min', 'Max', 'Std', 'P05', 'P95', '% binnen +-10%', 'Oordeel'],
          rows: rapport.spanning.fasen.map((f) => [
            f.fase,
            f.gem.toStringAsFixed(1),
            f.min.toStringAsFixed(1),
            f.max.toStringAsFixed(1),
            f.std.toStringAsFixed(2),
            f.p05.toStringAsFixed(1),
            f.p95.toStringAsFixed(1),
            '${f.compliancePct.toStringAsFixed(1)}%',
            f.status == PqStatus.conform ? 'OK' : 'NIET OK',
          ]).toList(),
          statusCol: 8,
          statuses: rapport.spanning.fasen.map((f) => f.status).toList(),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Limieten: ${(rapport.spanning.un * 0.9).toStringAsFixed(0)} - '
          '${(rapport.spanning.un * 1.1).toStringAsFixed(0)} V  '
          '(+-10% van Un = ${rapport.spanning.un.toStringAsFixed(0)} V)',
          style: const pw.TextStyle(fontSize: 9),
        ),
      ],
      pw.SizedBox(height: 16),

      // ── 2. Frequentie ─────────────────────────────────────────────────────
      if (rapport.frequentie != null) ...[
        _sectionHeader('2. Frequentie  (EN 50160 §4.2, IEC 61000-4-30)',
            rapport.frequentie!.status95 == PqStatus.conform &&
                    rapport.frequentie!.status100 == PqStatus.conform
                ? PqStatus.conform
                : PqStatus.nietConform),
        pw.SizedBox(height: 6),
        _dataTable(
          headers: ['Criterium', 'Gemiddeld', 'Min', 'Max', 'Std', 'Meetpunten', '% binnen limiet', 'Oordeel'],
          rows: [
            [
              '95% [49,5-50,5 Hz]',
              '${rapport.frequentie!.gem.toStringAsFixed(4)} Hz',
              '${rapport.frequentie!.min.toStringAsFixed(4)} Hz',
              '${rapport.frequentie!.max.toStringAsFixed(4)} Hz',
              '${rapport.frequentie!.std.toStringAsFixed(5)} Hz',
              rapport.frequentie!.aantalPunten.toString(),
              '${rapport.frequentie!.compliance95Pct.toStringAsFixed(2)}%',
              rapport.frequentie!.status95 == PqStatus.conform ? 'OK' : 'NIET OK',
            ],
            [
              '100% [47-52 Hz]',
              '-', '-', '-', '-', '-',
              '${rapport.frequentie!.compliance100Pct.toStringAsFixed(2)}%',
              rapport.frequentie!.status100 == PqStatus.conform ? 'OK' : 'NIET OK',
            ],
          ],
          statusCol: 7,
          statuses: [rapport.frequentie!.status95, rapport.frequentie!.status100],
        ),
        pw.SizedBox(height: 16),
      ],

      // ── 3. Harmonischen ───────────────────────────────────────────────────
      _sectionHeader('3. Harmonischen  (EN 50160 §4.4, IEC 61000-4-7, THD <= 8%)',
          rapport.harmonischen.status),
      pw.SizedBox(height: 6),
      if (!rapport.harmonischen.heeftSpanningsHarmonischen &&
          !rapport.harmonischen.heeftStroomHarmonischen)
        pw.Text('Geen harmonischendata beschikbaar.',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600))
      else ...[
        if (rapport.harmonischen.heeftSpanningsHarmonischen) ...[
          pw.Text('Spanningsharmonischen (%)',
              style:
                  pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
          pw.SizedBox(height: 4),
          _dataTable(
            headers: ['Fase', 'THD-U (%)', 'Dominante ordes', 'Overschreden', 'Oordeel'],
            rows: rapport.harmonischen.fasen.map((f) {
              final dom = f.individu.entries
                  .where((e) => e.value >= 0.5)
                  .toList()
                ..sort((a, b) => b.value.compareTo(a.value));
              final domStr = dom
                  .take(5)
                  .map((e) => 'H${e.key}=${e.value.toStringAsFixed(1)}%')
                  .join(', ');
              return [
                f.fase,
                f.thd.toStringAsFixed(2),
                domStr.isEmpty ? '-' : domStr,
                f.overtredingen.isEmpty
                    ? '-'
                    : f.overtredingen.map((o) => 'H$o').join(', '),
                f.status == PqStatus.conform
                    ? 'OK'
                    : f.status == PqStatus.geenData
                        ? '-'
                        : 'NIET OK',
              ];
            }).toList(),
            statusCol: 4,
            statuses: rapport.harmonischen.fasen.map((f) => f.status).toList(),
          ),
          pw.SizedBox(height: 8),
        ],
        if (rapport.harmonischen.heeftStroomHarmonischen) ...[
          pw.Text('Stroomharmonischen (A gemiddeld, IEC 61000-4-7)',
              style:
                  pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
          pw.SizedBox(height: 4),
          _dataTable(
            headers: ['Fase', 'THD-I (A rss)', 'H3', 'H5', 'H7', 'H9', 'H11', 'H13'],
            rows: rapport.harmonischen.stroomFasen.map((f) => [
              f.fase,
              f.thd.toStringAsFixed(3),
              ...[3, 5, 7, 9, 11, 13]
                  .map((o) => f.individu[o]?.toStringAsFixed(3) ?? '-'),
            ]).toList(),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Opmerking: EN 50160 specificeert geen stroomlimiet - rapportage ter informatie.',
            style: const pw.TextStyle(
                fontSize: 8, color: PdfColors.grey600),
          ),
        ],
      ],
      pw.SizedBox(height: 16),

      // ── 4. Events ─────────────────────────────────────────────────────────
      _sectionHeader(
          '4. Spanningsdippen en -onderbrekingen  (EN 50160, IEC 61000-4-30)',
          rapport.events.status),
      pw.SizedBox(height: 6),
      _twoColTable([
        ['Spanningsdippen', rapport.events.dippen.toString()],
        ['Swells (overspanning)', rapport.events.swells.toString()],
        ['Onderbrekingen', rapport.events.onderbrekingen.toString()],
        ['Overige events', rapport.events.overige.toString()],
        ['Totaal', rapport.events.totaal.toString()],
      ]),
      if (rapport.events.events.isNotEmpty) ...[
        pw.SizedBox(height: 8),
        pw.Text('Events (max. 25 getoond)',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
        pw.SizedBox(height: 4),
        _dataTable(
          headers: ['Tijdstip', 'Type'],
          rows: rapport.events.events.take(25).map((ev) => [
            DateFormat('dd-MM-yyyy HH:mm:ss').format(ev.time),
            ev.eventName,
          ]).toList(),
        ),
        if (rapport.events.events.length > 25)
          pw.Text('... en ${rapport.events.events.length - 25} meer',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
      ],
      pw.SizedBox(height: 16),

      // ── 5. Flicker ────────────────────────────────────────────────────────
      if (rapport.flicker != null) ...[
        _sectionHeader(
            '5. Flicker  (EN 50160 §4.6, IEC 61000-4-15  |  Pst <= 1,0  Plt <= 0,8)',
            rapport.flicker!.status),
        pw.SizedBox(height: 6),
        _dataTable(
          headers: ['Parameter', 'Gemiddeld', 'Maximum', 'Overschrijdingen', 'Limiet', 'Oordeel'],
          rows: [
            [
              'Pst (10 min)',
              rapport.flicker!.pstGem.toStringAsFixed(3),
              rapport.flicker!.pstMax.toStringAsFixed(3),
              rapport.flicker!.overtredingenPst.toString(),
              '1,0',
              rapport.flicker!.overtredingenPst == 0 ? 'OK' : 'NIET OK',
            ],
            [
              'Plt (2 uur)',
              rapport.flicker!.pltGem.toStringAsFixed(3),
              rapport.flicker!.pltMax.toStringAsFixed(3),
              rapport.flicker!.overtredingenPlt.toString(),
              '0,8',
              rapport.flicker!.overtredingenPlt == 0 ? 'OK' : 'NIET OK',
            ],
          ],
          statusCol: 5,
          statuses: [
            rapport.flicker!.overtredingenPst == 0 ? PqStatus.conform : PqStatus.nietConform,
            rapport.flicker!.overtredingenPlt == 0 ? PqStatus.conform : PqStatus.nietConform,
          ],
        ),
        pw.SizedBox(height: 16),
      ],

      // ── 6. Spanningsonbalans ──────────────────────────────────────────────
      if (rapport.onbalans != null) ...[
        _sectionHeader(
            '6. Spanningsonbalans  (EN 50160 §4.5, <= 2%, 95%-criterium)',
            rapport.onbalans!.status),
        pw.SizedBox(height: 6),
        _dataTable(
          headers: ['Gemiddeld', 'Maximum', 'P95', 'Overschrijdingen', 'Meetpunten', '% <= 2%', 'Oordeel'],
          rows: [
            [
              '${rapport.onbalans!.gem.toStringAsFixed(3)}%',
              '${rapport.onbalans!.max.toStringAsFixed(3)}%',
              '${rapport.onbalans!.p95.toStringAsFixed(3)}%',
              rapport.onbalans!.overtredingen.toString(),
              rapport.onbalans!.aantalPunten.toString(),
              '${((rapport.onbalans!.aantalPunten - rapport.onbalans!.overtredingen) / rapport.onbalans!.aantalPunten * 100).toStringAsFixed(1)}%',
              rapport.onbalans!.status == PqStatus.conform ? 'OK' : 'NIET OK',
            ],
          ],
          statusCol: 6,
          statuses: [rapport.onbalans!.status],
        ),
        pw.SizedBox(height: 16),
      ],

      // ── Aanbevelingen ─────────────────────────────────────────────────────
      _sectionHeader('Aanbevelingen', PqStatus.conform),
      pw.SizedBox(height: 6),
      ...rapport.aanbevelingen.map((a) => pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 5),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(
                    width: 5,
                    height: 5,
                    margin: const pw.EdgeInsets.only(top: 3, right: 6),
                    decoration: const pw.BoxDecoration(
                        color: PdfColors.grey700,
                        shape: pw.BoxShape.circle)),
                pw.Expanded(
                    child: pw.Text(a,
                        style: const pw.TextStyle(fontSize: 9))),
              ],
            ),
          )),
    ],
  ));

  final bytes = await pdf.save();

  if (!context.mounted) return;

  final savePath = await FilePicker.platform.saveFile(
    dialogTitle: 'Sla systeemcode rapport op',
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

// ── Helpers ──────────────────────────────────────────────────────────────────

String _statusLabel(PqStatus s) => switch (s) {
      PqStatus.conform => 'CONFORM',
      PqStatus.nietConform => 'NIET CONFORM',
      PqStatus.geenData => 'GEEN DATA',
    };

PdfColor _statusColor(PqStatus s) => switch (s) {
      PqStatus.conform => PdfColors.green700,
      PqStatus.nietConform => PdfColors.red,
      PqStatus.geenData => PdfColors.grey600,
    };

PdfColor _statusBgColor(PqStatus s) => switch (s) {
      PqStatus.conform => PdfColors.green50,
      PqStatus.nietConform => PdfColors.red50,
      PqStatus.geenData => PdfColors.grey100,
    };

pw.Widget _sectionHeader(String title, PqStatus status) => pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey200,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Row(children: [
        pw.Expanded(
            child: pw.Text(title,
                style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold, fontSize: 10))),
        pw.Container(
          padding:
              const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: pw.BoxDecoration(
            color: _statusBgColor(status),
            border: pw.Border.all(color: _statusColor(status), width: 0.5),
            borderRadius:
                const pw.BorderRadius.all(pw.Radius.circular(4)),
          ),
          child: pw.Text(
            _statusLabel(status),
            style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 8,
                color: _statusColor(status)),
          ),
        ),
      ]),
    );

pw.Widget _infoBlock(String label, String value) => pw.Expanded(
      child: pw.Column(
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
      ),
    );

pw.Widget _twoColTable(List<List<String>> rows) {
  final header =
      pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9);
  final cell = const pw.TextStyle(fontSize: 9);

  pw.Widget pad(String t, {pw.TextStyle? style}) => pw.Padding(
        padding:
            const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: pw.Text(t, style: style ?? cell),
      );

  return pw.Table(
    border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
    columnWidths: const {
      0: pw.FlexColumnWidth(1.0),
      1: pw.FlexColumnWidth(2.0),
    },
    children: rows.asMap().entries.map((entry) {
      final isEven = entry.key.isEven;
      return pw.TableRow(
        decoration:
            pw.BoxDecoration(color: isEven ? PdfColors.white : PdfColors.grey50),
        children: [
          pad(entry.value[0], style: header),
          pad(entry.value[1]),
        ],
      );
    }).toList(),
  );
}

pw.Widget _dataTable({
  required List<String> headers,
  required List<List<String>> rows,
  int? statusCol,
  List<PqStatus>? statuses,
}) {
  final headerStyle =
      pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8);
  final cellStyle = const pw.TextStyle(fontSize: 8);
  final n = headers.length;

  pw.Widget pad(String t, {pw.TextStyle? style}) => pw.Padding(
        padding:
            const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: pw.Text(t, style: style ?? cellStyle),
      );

  return pw.Table(
    border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
    columnWidths: {for (int i = 0; i < n; i++) i: const pw.FlexColumnWidth(1)},
    children: [
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
        children: headers.map((h) => pad(h, style: headerStyle)).toList(),
      ),
      ...rows.asMap().entries.map((entry) {
        final rowIdx = entry.key;
        final row = entry.value;
        final status =
            (statusCol != null && statuses != null && rowIdx < statuses.length)
                ? statuses[rowIdx]
                : null;
        return pw.TableRow(
          decoration: pw.BoxDecoration(
              color: rowIdx.isEven ? PdfColors.white : PdfColors.grey50),
          children: row.asMap().entries.map((c) {
            final isStatus = statusCol != null && c.key == statusCol;
            final color = isStatus && status != null
                ? _statusColor(status)
                : null;
            return pad(
              c.value,
              style: isStatus && color != null
                  ? pw.TextStyle(
                      fontSize: 8,
                      color: color,
                      fontWeight: pw.FontWeight.bold)
                  : null,
            );
          }).toList(),
        );
      }),
    ],
  );
}

String _durStr(Duration d) {
  if (d.inDays >= 1) return '${d.inDays}d ${d.inHours.remainder(24)}h';
  if (d.inHours >= 1) return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
  return '${d.inMinutes}m';
}
