import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

class XlsxMeterRow {
  final DateTime time;
  final double? vL1, vL2, vL3;
  final double? iL1, iL2, iL3;
  final double? qTotal;
  final double? pTotal, pL1, pL2, pL3;
  final double? dailyImport, dailyImportL1, dailyImportL2, dailyImportL3;
  final double? dailySale, dailySaleL1, dailySaleL2, dailySaleL3;
  final double? totalImport, totalExport;

  const XlsxMeterRow({
    required this.time,
    this.vL1,
    this.vL2,
    this.vL3,
    this.iL1,
    this.iL2,
    this.iL3,
    this.qTotal,
    this.pTotal,
    this.pL1,
    this.pL2,
    this.pL3,
    this.dailyImport,
    this.dailyImportL1,
    this.dailyImportL2,
    this.dailyImportL3,
    this.dailySale,
    this.dailySaleL1,
    this.dailySaleL2,
    this.dailySaleL3,
    this.totalImport,
    this.totalExport,
  });
}

/// Reads the first sheet of an xlsx file produced by the electric meter
/// export tool. Column layout (fixed):
///   A=Time  B=V_L1  C=V_L2  D=V_L3  E=I_L1  F=I_L2  G=I_L3
///   H=Q_total  I=P_total  J=P_L1  K=P_L2  L=P_L3
///   M=dayImport  N=dayImport_L1  O=dayImport_L2  P=dayImport_L3
///   Q=daySale  R=daySale_L1  S=daySale_L2  T=daySale_L3
///   U=totalImport  V=totalExport
class XlsxMeterParser {
  static Future<List<XlsxMeterRow>> parseFile(String path) async {
    final bytes = Uint8List.fromList(await File(path).readAsBytes());
    final archive = ZipDecoder().decodeBytes(bytes);

    final ssBytes = _entry(archive, 'xl/sharedStrings.xml');
    final ss = ssBytes != null
        ? _parseSharedStrings(utf8.decode(ssBytes))
        : <String>[];

    final sheetBytes = _entry(archive, 'xl/worksheets/sheet1.xml');
    if (sheetBytes == null) return [];

    final rawRows = _parseSheet(utf8.decode(sheetBytes), ss);

    // Row 0 is the header row — skip it.
    final result = <XlsxMeterRow>[];
    for (int i = 1; i < rawRows.length; i++) {
      final c = rawRows[i];
      final time = _excelDate(_num(c, 0));
      if (time == null) continue;
      result.add(XlsxMeterRow(
        time: time,
        vL1: _num(c, 1),
        vL2: _num(c, 2),
        vL3: _num(c, 3),
        iL1: _num(c, 4),
        iL2: _num(c, 5),
        iL3: _num(c, 6),
        qTotal: _num(c, 7),
        pTotal: _num(c, 8),
        pL1: _num(c, 9),
        pL2: _num(c, 10),
        pL3: _num(c, 11),
        dailyImport: _num(c, 12),
        dailyImportL1: _num(c, 13),
        dailyImportL2: _num(c, 14),
        dailyImportL3: _num(c, 15),
        dailySale: _num(c, 16),
        dailySaleL1: _num(c, 17),
        dailySaleL2: _num(c, 18),
        dailySaleL3: _num(c, 19),
        totalImport: _num(c, 20),
        totalExport: _num(c, 21),
      ));
    }

    result.sort((a, b) => a.time.compareTo(b.time));
    return result;
  }

  // ── Archive helpers ────────────────────────────────────────────────────────

  static Uint8List? _entry(Archive archive, String name) {
    for (final f in archive.files) {
      if (f.name == name) return Uint8List.fromList(f.content);
    }
    return null;
  }

  // ── Shared-strings parser ──────────────────────────────────────────────────

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

  // ── Sheet parser ───────────────────────────────────────────────────────────

  static List<List<String?>> _parseSheet(String xml, List<String> ss) {
    final rows = <List<String?>>[];
    final rowRe = RegExp(r'<row\b[^>]*>(.*?)</row>', dotAll: true);
    // Matches <c ...> with optional <v>...</v> child.
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

  // ── Utilities ──────────────────────────────────────────────────────────────

  // Column letters → 0-based index (A=0, B=1, ..., Z=25, AA=26, ...).
  static int _colIdx(String letters) {
    var idx = 0;
    for (final c in letters.codeUnits) {
      idx = idx * 26 + (c - 65 + 1);
    }
    return idx - 1;
  }

  static double? _num(List<String?> cells, int col) {
    if (col >= cells.length) return null;
    return double.tryParse(cells[col] ?? '');
  }

  // Excel serial date (days since 1899-12-30) → DateTime.
  static DateTime? _excelDate(double? serial) {
    if (serial == null) return null;
    final days = serial.floor();
    final frac = serial - days;
    final secs = (frac * 86400).round();
    final base = DateTime.utc(1899, 12, 30).add(Duration(days: days));
    return DateTime(
        base.year, base.month, base.day,
        secs ~/ 3600, (secs % 3600) ~/ 60, secs % 60);
  }

  static String _unesc(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'");
}
