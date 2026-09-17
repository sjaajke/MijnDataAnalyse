import 'dart:io';

import 'package:excel/excel.dart' as xls;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' show BuildContext, ScaffoldMessenger, SnackBar, Text;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/standaard.dart';
import '../providers/standaarden_provider.dart';

Future<void> exportStandaardenExcel({
  required BuildContext context,
  required List<Standaard> standaarden,
}) async {
  final now = DateTime.now();
  final fileName = 'standaarden_${DateFormat('yyyyMMdd_HHmm').format(now)}.xlsx';

  final workbook = xls.Excel.createExcel();
  final sheetName = workbook.getDefaultSheet()!;
  final sheet = workbook[sheetName];

  sheet.appendRow([
    xls.TextCellValue('Titel'),
    xls.TextCellValue('Tekst'),
  ]);
  for (final standaard in standaarden) {
    sheet.appendRow([
      xls.TextCellValue(standaard.titel),
      xls.TextCellValue(standaard.tekst),
    ]);
  }
  sheet.setColumnWidth(0, 30);
  sheet.setColumnWidth(1, 80);

  final bytes = workbook.encode();
  if (bytes == null) return;

  if (!context.mounted) return;

  final savePath = await FilePicker.platform.saveFile(
    dialogTitle: 'Sla standaarden op',
    fileName: fileName,
    type: FileType.custom,
    allowedExtensions: ['xlsx'],
  );

  if (savePath != null) {
    await File(savePath).writeAsBytes(bytes);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Standaarden opgeslagen: $savePath'),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }
}

Future<void> importStandaardenExcel({required BuildContext context}) async {
  final result = await FilePicker.platform.pickFiles(
    dialogTitle: 'Open standaarden Excel-bestand',
    type: FileType.custom,
    allowedExtensions: ['xlsx'],
  );
  final path = result?.files.single.path;
  if (path == null) return;

  final bytes = await File(path).readAsBytes();
  final workbook = xls.Excel.decodeBytes(bytes);
  if (workbook.tables.isEmpty) return;
  final sheet = workbook.tables[workbook.tables.keys.first]!;

  if (!context.mounted) return;
  final provider = context.read<StandaardenProvider>();

  var imported = 0;
  for (var i = 0; i < sheet.rows.length; i++) {
    final row = sheet.rows[i];
    final titel = row.isNotEmpty ? _cellText(row[0]) : '';
    final tekst = row.length > 1 ? _cellText(row[1]) : '';
    if (titel.isEmpty) continue;
    if (i == 0 && titel.toLowerCase() == 'titel') continue;
    await provider.addStandaard(titel, tekst);
    imported++;
  }

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(imported == 0
            ? 'Geen standaarden gevonden in het bestand'
            : '$imported standaard${imported == 1 ? '' : 'en'} geimporteerd'),
        duration: const Duration(seconds: 4),
      ),
    );
  }
}

String _cellText(xls.Data? cell) => (cell?.value?.toString() ?? '').trim();
