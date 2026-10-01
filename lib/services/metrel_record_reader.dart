import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:sqlite3/sqlite3.dart';

import '../models/metrel_record.dart';
import 'metrel_catalog.dart';

/// Leest Metrel-records (MI 2892/2893/2992…) uit een `.pwvx`-archief of een
/// uitgepakte map, met de meetcatalogus van de Metrel Power SDK om kolommen
/// en events te benoemen.
///
/// De SDK zelf leest meetdata via een Windows-only native reader; dit is een
/// platformonafhankelijke Dart-implementatie van hetzelfde recordformaat,
/// gecontroleerd tegen de voorbeeldrecords en verwachte uitkomsten van de
/// SDK-showcase.
///
/// Opbouw van een record (`records/<map>/`):
///   - `meta` — naam, tijdzone, start/einde (ns sinds epoch, UTC)
///   - `instrumentInfo.json`, `measurement_settings.json`,
///     `recorder_settings.json`
///   - `periodics/{N}s_meta` — header + 8-byte descriptors
///   - `periodics/{N}s_data_###` — float32, kolomgewijs per blok
///   - `periodics/{N}s_timeStamps` / `_flags` — int64 per interval
///   - `events/events.db` — SQLite met de zes event-families
///
/// Header van `{N}s_meta` (little-endian):
///   [0] u32 interval (s)   [4] u32 aantal intervallen
///   [8] u32 blokgrootte    [12] u32 intervallen per databestand
///   [16] u16 —             [18] u32 aantal descriptors, gevolgd door
///   de descriptors (8 bytes = sleutel in de SDK-catalogus).
class MetrelRecordReader {
  final MetrelCatalog catalog;

  MetrelRecordReader(this.catalog);

  /// Opent een `.pwvx`-bestand of een map met één of meer records.
  Future<List<MetrelRecord>> open(String path) async {
    final source = await FileSystemEntity.isDirectory(path)
        ? _DirectorySource(Directory(path))
        : _ArchiveSource(ZipDecoder().decodeBytes(await File(path).readAsBytes()));

    final recordDirs = source.recordDirs();
    if (recordDirs.isEmpty) {
      throw const FormatException('Geen Metrel-record gevonden in dit bestand');
    }
    return [for (final dir in recordDirs) await _readRecord(source, dir)];
  }

  Future<MetrelRecord> _readRecord(_Source source, String dir) async {
    final meta = source.read('$dir/meta');
    final header = meta != null ? _parseRecordMeta(meta) : null;
    final recorderSettings = _json(source.read('$dir/recorder_settings.json'));
    final recordInfo = recorderSettings['recorderSettings']?['recordInfo'];
    final timeZoneId = header?.timeZoneId ??
        recordInfo?['timezone']?['value'] as String?;
    final folder = dir.split('/').last;

    return MetrelRecord(
      name: header?.name ?? folder,
      folder: folder,
      timeZoneId: timeZoneId,
      utcOffset: _parseUtcOffset(
              recordInfo?['utcOffset']?['value'] as String?) ??
          _parseEtcGmt(timeZoneId),
      start: header?.start,
      end: header?.end,
      instrumentInfo: _json(source.read('$dir/instrumentInfo.json')),
      measurementSettings:
          _json(source.read('$dir/measurement_settings.json')),
      recorderSettings: recorderSettings,
      streams: _readStreams(source, dir),
      events: await _readEvents(source, dir),
    );
  }

  List<MetrelStream> _readStreams(_Source source, String dir) {
    final streams = <MetrelStream>[];
    final metaName = RegExp(r'^(\d+)s_meta$');
    for (final name in source.list('$dir/periodics')) {
      final match = metaName.firstMatch(name);
      if (match == null) continue;
      final prefix = '$dir/periodics/${match.group(1)}s';
      final meta = source.read('${prefix}_meta');
      if (meta == null || meta.length < 22) continue;

      final bd = ByteData.sublistView(meta);
      final interval = bd.getUint32(0, Endian.little);
      final headerCount = bd.getUint32(4, Endian.little);
      final blockSize = bd.getUint32(8, Endian.little);
      final recordsPerFile = bd.getUint32(12, Endian.little);
      final descriptorCount = bd.getUint32(18, Endian.little);
      if (blockSize == 0 || 22 + descriptorCount * 8 > meta.length) continue;

      final descriptors = [
        for (var i = 0; i < descriptorCount; i++)
          () {
            final key = bd.getUint64(22 + i * 8, Endian.little);
            return MetrelDescriptor(
              index: i,
              key: key,
              info: catalog.recorderMeasurement(key),
            );
          }(),
      ];

      final timestamps = _int64s(source.read('${prefix}_timeStamps'));
      final count =
          headerCount < timestamps.length ? headerCount : timestamps.length;
      final flags = _int64s(source.read('${prefix}_flags'));

      streams.add(MetrelStream(
        intervalSeconds: interval,
        blockSize: blockSize,
        recordsPerFile: recordsPerFile,
        descriptors: descriptors,
        times: [for (var i = 0; i < count; i++) _nsToUtc(timestamps[i])],
        flags: [for (var i = 0; i < count; i++) i < flags.length ? flags[i] : 0],
        readDataFile: (fileIndex) => source.read(
            '${prefix}_data_${fileIndex.toString().padLeft(3, '0')}'),
      ));
    }
    streams.sort((a, b) => a.intervalSeconds.compareTo(b.intervalSeconds));
    return streams;
  }

  // ── Events ────────────────────────────────────────────────────────────

  Future<List<MetrelEvent>> _readEvents(_Source source, String dir) async {
    final dbBytes = source.read('$dir/events/events.db');
    if (dbBytes == null || dbBytes.isEmpty) return [];

    // Altijd op een kopie werken: bij openen verwerkt SQLite het WAL-bestand,
    // en dat mag het origineel van de gebruiker niet wijzigen.
    final tmp = await Directory.systemTemp.createTemp('metrel_events_');
    try {
      final dbFile = File('${tmp.path}/events.db');
      await dbFile.writeAsBytes(dbBytes);
      final wal = source.read('$dir/events/events.db-wal');
      if (wal != null && wal.isNotEmpty) {
        await File('${tmp.path}/events.db-wal').writeAsBytes(wal);
      }
      final db = sqlite3.open(dbFile.path);
      try {
        final events = <MetrelEvent>[
          ..._voltageEvents(db),
          ..._rvcEvents(db),
          ..._inrushEvents(db),
          ..._signallingEvents(db),
          ..._alarmEvents(db),
          ..._transientEvents(db),
        ];
        events.sort((a, b) => a.start.compareTo(b.start));
        return events;
      } finally {
        db.close();
      }
    } finally {
      await tmp.delete(recursive: true);
    }
  }

  Iterable<Row> _rows(Database db, String table) {
    try {
      return db.select('SELECT * FROM $table ORDER BY id');
    } on SqliteException {
      return const [];
    }
  }

  Iterable<MetrelEvent> _voltageEvents(Database db) sync* {
    for (final r in _rows(db, 'voltage_events')) {
      final types = r['types'] as int;
      final dip = _validFloat(r['dip_min']);
      final swell = _validFloat(r['swell_max']);
      final interrupt = _validFloat(r['interrupt_min']);
      // Restspanning: bij onderbreking de laagste waarde, anders dip/swell.
      final magnitude = (types & 2 != 0 ? interrupt : null) ??
          (types & 4 != 0 ? dip : null) ??
          (types & 1 != 0 ? swell : null);
      yield MetrelEvent(
        family: MetrelEventFamily.voltage,
        id: r['id'] as int,
        start: _nsToUtc(r['start_time'] as int),
        duration: _nsToDuration(r['duration'] as int),
        type: catalog.voltageTypesFromMask(types),
        channels: _channels(r['channels'] as int, r['is_total'] as int),
        magnitude: magnitude,
        unit: 'V',
        details: [
          if (dip != null) 'dip min ${dip.toStringAsFixed(2)} V',
          if (swell != null) 'swell max ${swell.toStringAsFixed(2)} V',
          if (interrupt != null)
            'onderbreking min ${interrupt.toStringAsFixed(2)} V',
        ].join(' · '),
        typeMask: types,
      );
    }
  }

  Iterable<MetrelEvent> _rvcEvents(Database db) sync* {
    for (final r in _rows(db, 'rvc_events')) {
      final duMax = _validFloat(r['duMax']);
      final dUss = _validFloat(r['dUss']);
      yield MetrelEvent(
        family: MetrelEventFamily.rvc,
        id: r['id'] as int,
        start: _nsToUtc(r['start_time'] as int),
        duration: _nsToDuration(r['duration'] as int),
        type: 'RVC',
        channels: _channels(r['channels'] as int, r['is_total'] as int),
        magnitude: duMax,
        unit: 'V',
        details: dUss != null ? 'ΔUss ${dUss.toStringAsFixed(2)} V' : '',
      );
    }
  }

  Iterable<MetrelEvent> _inrushEvents(Database db) sync* {
    for (final r in _rows(db, 'inrush_events')) {
      yield MetrelEvent(
        family: MetrelEventFamily.inrush,
        id: r['id'] as int,
        start: _nsToUtc(r['start_time'] as int),
        duration: _nsToDuration(r['duration'] as int),
        type: 'Inrush',
        channels: catalog.channelNames[r['channel_id'] as int] ?? '',
        magnitude: _validFloat(r['inrush_max']),
        unit: 'A',
      );
    }
  }

  Iterable<MetrelEvent> _signallingEvents(Database db) sync* {
    for (final r in _rows(db, 'signalling_events')) {
      final freq = _validFloat(r['sig_freq']);
      final threshold = _validFloat(r['threshold']);
      yield MetrelEvent(
        family: MetrelEventFamily.signalling,
        id: r['id'] as int,
        start: _nsToUtc(r['start_time'] as int),
        duration: _nsToDuration(r['duration'] as int),
        type: freq != null ? 'Signalering ${freq.toStringAsFixed(0)} Hz' : 'Signalering',
        channels: catalog.channelNames[r['channel_id'] as int] ?? '',
        magnitude: _validFloat(r['sig_max']),
        unit: 'V',
        details: threshold != null ? 'drempel ${threshold.toStringAsFixed(2)} V' : '',
      );
    }
  }

  Iterable<MetrelEvent> _alarmEvents(Database db) sync* {
    for (final r in _rows(db, 'alarm_events')) {
      final m = catalog.eventMeasurement(r['event_meas_index'] as int);
      yield MetrelEvent(
        family: MetrelEventFamily.alarm,
        id: r['id'] as int,
        start: _nsToUtc(r['start_time'] as int),
        duration: _nsToDuration(r['duration'] as int),
        type: m != null
            ? '${m.symbol}${m.harmonic ?? ''} — ${m.longName}'
            : 'Alarm',
        channels: m?.channel ??
            catalog.channelNames[r['channel_id'] as int] ??
            '',
        magnitude: _validFloat(r['extreme_value']),
        unit: m?.unit ?? '',
      );
    }
  }

  Iterable<MetrelEvent> _transientEvents(Database db) sync* {
    for (final r in _rows(db, 'transient_events')) {
      final channel = catalog.onlineChannels[r['online_channel_id'] as int];
      yield MetrelEvent(
        family: MetrelEventFamily.transient,
        id: r['id'] as int,
        start: _nsToUtc(r['start_time'] as int),
        duration: _nsToDuration(r['duration'] as int),
        type: 'Transiënt',
        channels: channel ?? '',
        magnitude: _validFloat(r['peak_value']),
        unit: (channel ?? 'U').startsWith('I') ? 'A' : 'V',
      );
    }
  }

  String _channels(int mask, int isTotal) {
    final names = catalog.channelsFromMask(mask);
    return isTotal != 0 ? (names.isEmpty ? 'Totaal' : '$names (totaal)') : names;
  }

  // ── Helpers ───────────────────────────────────────────────────────────

  static DateTime _nsToUtc(int ns) =>
      DateTime.fromMicrosecondsSinceEpoch(ns ~/ 1000, isUtc: true);

  static Duration _nsToDuration(int ns) => Duration(microseconds: ns ~/ 1000);

  /// Het instrument gebruikt FLT_MAX / FLT_MIN als "geen waarde".
  static double? _validFloat(Object? v) {
    if (v is! num) return null;
    final d = v.toDouble();
    if (d.isNaN || d.abs() > 3.0e38 || (d != 0 && d.abs() < 1.0e-37)) {
      return null;
    }
    return d;
  }

  static List<int> _int64s(Uint8List? bytes) {
    if (bytes == null) return const [];
    final bd = ByteData.sublistView(bytes);
    return [
      for (var i = 0; i + 8 <= bytes.length; i += 8)
        bd.getInt64(i, Endian.little),
    ];
  }

  static Map<String, dynamic> _json(Uint8List? bytes) {
    if (bytes == null) return const {};
    try {
      final v = jsonDecode(utf8.decode(bytes));
      return v is Map<String, dynamic> ? v : const {};
    } on FormatException {
      return const {};
    }
  }

  /// `meta`: u32 versie, u32+tekst naam, u32+tekst tijdzone, i64 start,
  /// i64 einde (ns sinds epoch; -1 = onbekend).
  static _RecordHeader? _parseRecordMeta(Uint8List meta) {
    try {
      final bd = ByteData.sublistView(meta);
      var offset = 4;
      String readString() {
        final len = bd.getUint32(offset, Endian.little);
        final s = utf8.decode(meta.sublist(offset + 4, offset + 4 + len));
        offset += 4 + len;
        return s;
      }

      final name = readString();
      final tz = readString();
      DateTime? readTime() {
        if (offset + 8 > meta.length) return null;
        final ns = bd.getInt64(offset, Endian.little);
        offset += 8;
        return ns > 0 ? _nsToUtc(ns) : null;
      }

      return _RecordHeader(name, tz.isEmpty ? null : tz, readTime(), readTime());
    } on RangeError {
      return null;
    }
  }

  /// `UTC + 02:00` → 2 uur.
  static Duration? _parseUtcOffset(String? value) {
    if (value == null) return null;
    final m = RegExp(r'UTC\s*([+-])\s*(\d+):(\d+)').firstMatch(value);
    if (m == null) return null;
    final minutes = int.parse(m.group(2)!) * 60 + int.parse(m.group(3)!);
    return Duration(minutes: m.group(1) == '-' ? -minutes : minutes);
  }

  /// `Etc/GMT-2` betekent UTC+2 (POSIX-tekenconventie is omgekeerd).
  static Duration? _parseEtcGmt(String? tz) {
    if (tz == null) return null;
    final m = RegExp(r'^Etc/GMT([+-])(\d+)$').firstMatch(tz);
    if (m == null) return tz == 'Etc/GMT' || tz == 'Etc/UTC' ? Duration.zero : null;
    final hours = int.parse(m.group(2)!);
    return Duration(hours: m.group(1) == '-' ? hours : -hours);
  }
}

class _RecordHeader {
  final String name;
  final String? timeZoneId;
  final DateTime? start;
  final DateTime? end;
  const _RecordHeader(this.name, this.timeZoneId, this.start, this.end);
}

/// Bestanden in een archief of map, met paden gescheiden door `/`.
abstract class _Source {
  Uint8List? read(String path);

  /// Bestandsnamen direct onder [dir].
  Iterable<String> list(String dir);

  /// Mappen die een record bevatten (herkenbaar aan `meta` +
  /// `periodics/` of `instrumentInfo.json`).
  List<String> recordDirs();
}

class _ArchiveSource implements _Source {
  final Map<String, ArchiveFile> _files;

  _ArchiveSource(Archive archive)
      : _files = {
          for (final f in archive.files)
            if (f.isFile) f.name.replaceAll('\\', '/'): f,
        };

  @override
  Uint8List? read(String path) {
    final f = _files[path];
    if (f == null) return null;
    final content = f.content;
    return content is Uint8List ? content : Uint8List.fromList(content as List<int>);
  }

  @override
  Iterable<String> list(String dir) sync* {
    final prefix = '$dir/';
    for (final name in _files.keys) {
      if (name.startsWith(prefix) && !name.substring(prefix.length).contains('/')) {
        yield name.substring(prefix.length);
      }
    }
  }

  @override
  List<String> recordDirs() {
    final dirs = <String>{};
    for (final name in _files.keys) {
      for (final marker in const ['/instrumentInfo.json', '/periodics/meta']) {
        if (name.endsWith(marker)) {
          dirs.add(name.substring(0, name.length - marker.length));
        }
      }
    }
    return dirs.toList()..sort();
  }
}

class _DirectorySource implements _Source {
  final Directory root;

  _DirectorySource(this.root);

  String _abs(String path) =>
      path.isEmpty ? root.path : '${root.path}/$path';

  @override
  Uint8List? read(String path) {
    final f = File(_abs(path));
    return f.existsSync() ? f.readAsBytesSync() : null;
  }

  @override
  Iterable<String> list(String dir) {
    final d = Directory(_abs(dir));
    if (!d.existsSync()) return const [];
    return d
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last);
  }

  @override
  List<String> recordDirs() {
    final dirs = <String>{};
    void visit(Directory d, String rel, int depth) {
      if (File('${d.path}/instrumentInfo.json').existsSync() ||
          File('${d.path}/periodics/meta').existsSync()) {
        dirs.add(rel);
        return;
      }
      if (depth >= 3) return;
      for (final child in d.listSync().whereType<Directory>()) {
        final name = child.uri.pathSegments.where((s) => s.isNotEmpty).last;
        visit(child, rel.isEmpty ? name : '$rel/$name', depth + 1);
      }
    }

    visit(root, '', 0);
    return dirs.toList()..sort();
  }
}
