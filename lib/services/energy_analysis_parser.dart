import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

class EnergyAnalysisRow {
  final DateTime time;
  final double? pvPower;
  final double? exportPower;
  final double? selfConsumption;
  final double? loadPower;
  final double? importPower;
  final double? selfSufficiency;
  final double? charge;
  final double? discharge;
  final double? soc;

  const EnergyAnalysisRow({
    required this.time,
    this.pvPower,
    this.exportPower,
    this.selfConsumption,
    this.loadPower,
    this.importPower,
    this.selfSufficiency,
    this.charge,
    this.discharge,
    this.soc,
  });
}

/// Parses a solar/battery energy analysis xlsx export.
/// Columns: Time (HH:MM), Photovoltaic Power(W), Export Power(W),
///   Self-Consumption Power(W), Load Power(W), Import Power(W),
///   Self-Sufficiency Power(W), Charge(W), Discharge(W), SOC(%)
/// The date is derived from the filename (regex for YYYY-MM-DD).
class EnergyAnalysisParser {
  static Future<List<EnergyAnalysisRow>> parseFile(String path) async {
    // Extract date from filename (e.g. "2026-06-22-Power-Data.xlsx").
    final filename = path.split('/').last;
    final dateMatch = RegExp(r'(\d{4}-\d{2}-\d{2})').firstMatch(filename);
    final date = dateMatch != null
        ? DateTime.parse(dateMatch.group(1)!)
        : DateTime.now();

    final bytes = Uint8List.fromList(await File(path).readAsBytes());
    final archive = ZipDecoder().decodeBytes(bytes);

    final ssBytes = _entry(archive, 'xl/sharedStrings.xml');
    final ss = ssBytes != null
        ? _parseSharedStrings(utf8.decode(ssBytes))
        : <String>[];

    final sheetBytes = _entry(archive, 'xl/worksheets/sheet1.xml');
    if (sheetBytes == null) return [];

    final rawRows = _parseSheet(utf8.decode(sheetBytes), ss);
    if (rawRows.isEmpty) return [];

    // Build column-index → field mapping from the header row.
    final header = rawRows[0];
    final fieldMap = <int, String>{};
    for (int col = 0; col < header.length; col++) {
      final field = _fieldFor(header[col] ?? '');
      if (field != null) fieldMap[col] = field;
    }

    final result = <EnergyAnalysisRow>[];
    for (int i = 1; i < rawRows.length; i++) {
      final c = rawRows[i];
      final timeStr = c.isNotEmpty ? c[0] : null;
      if (timeStr == null) continue;
      final time = _parseTime(timeStr, date);
      if (time == null) continue;

      double? col(String name) {
        for (final e in fieldMap.entries) {
          if (e.value == name && e.key < c.length) {
            return double.tryParse(c[e.key] ?? '');
          }
        }
        return null;
      }

      result.add(EnergyAnalysisRow(
        time: time,
        pvPower: col('pvPower'),
        exportPower: col('exportPower'),
        selfConsumption: col('selfConsumption'),
        loadPower: col('loadPower'),
        importPower: col('importPower'),
        selfSufficiency: col('selfSufficiency'),
        charge: col('charge'),
        discharge: col('discharge'),
        soc: col('soc'),
      ));
    }

    result.sort((a, b) => a.time.compareTo(b.time));
    return result;
  }

  static String? _fieldFor(String header) {
    final h = header.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (h.contains('photovoltaic') || h == 'pv power(w)') return 'pvPower';
    if (h.contains('export')) return 'exportPower';
    if (h.contains('self-consumption') || h.contains('self consumption')) {
      return 'selfConsumption';
    }
    if (h == 'load power(w)') return 'loadPower';
    if (h.contains('import')) return 'importPower';
    if (h.contains('self-sufficiency') || h.contains('self sufficiency')) {
      return 'selfSufficiency';
    }
    if (h == 'charge(w)') return 'charge';
    if (h == 'discharge(w)') return 'discharge';
    if (h.contains('soc')) return 'soc';
    return null;
  }

  static DateTime? _parseTime(String s, DateTime date) {
    final parts = s.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return DateTime(date.year, date.month, date.day, h, m);
  }

  // ── Archive helpers ────────────────────────────────────────────────────────

  static Uint8List? _entry(Archive archive, String name) {
    for (final f in archive.files) {
      if (f.name == name) return Uint8List.fromList(f.content);
    }
    return null;
  }

  static List<String> _parseSharedStrings(String xml) {
    final strings = <String>[];
    final siRe = RegExp(r'<si>(.*?)</si>', dotAll: true);
    final tRe = RegExp(r'<t[^>]*>(.*?)</t>', dotAll: true);
    for (final si in siRe.allMatches(xml)) {
      final t = tRe.firstMatch(si.group(1)!);
      strings.add(_unesc(t?.group(1) ?? ''));
    }
    return strings;
  }

  static List<List<String?>> _parseSheet(String xml, List<String> ss) {
    final rows = <List<String?>>[];
    final rowRe = RegExp(r'<row\b[^>]*>(.*?)</row>', dotAll: true);
    final cellRe =
        RegExp(r'<c\b([^>]*)>(?:.*?<v>(.*?)</v>.*?)?</c>', dotAll: true);
    final refRe = RegExp(r'\br="([A-Z]+)\d+"');
    final typeStrRe = RegExp(r'\bt="s"');

    for (final rowM in rowRe.allMatches(xml)) {
      final cellMap = <int, String?>{};
      int maxCol = -1;

      for (final cM in cellRe.allMatches(rowM.group(1)!)) {
        final attrs = cM.group(1)!;
        final val = cM.group(2);
        final refM = refRe.firstMatch(attrs);
        if (refM == null) continue;
        final col = _colIdx(refM.group(1)!);

        if (val == null) {
          cellMap[col] = null;
        } else if (typeStrRe.hasMatch(attrs)) {
          final idx = int.tryParse(val);
          cellMap[col] =
              (idx != null && idx < ss.length) ? ss[idx] : val;
        } else {
          cellMap[col] = val;
        }
        if (col > maxCol) maxCol = col;
      }

      if (maxCol >= 0) {
        rows.add(List.generate(maxCol + 1, (i) => cellMap[i]));
      }
    }
    return rows;
  }

  static int _colIdx(String letters) {
    var idx = 0;
    for (final c in letters.codeUnits) {
      idx = idx * 26 + (c - 65 + 1);
    }
    return idx - 1;
  }

  static String _unesc(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'");
}
