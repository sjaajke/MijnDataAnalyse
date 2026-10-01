import 'dart:io';
import 'dart:typed_data';
import '../models/pqf_record.dart';

/// Parser voor A-Eberle PQ-Box .pqf-bestanden, volgens de officiële
/// documentatie "PQ-Box Dateiformat" v1.5 (+ structures.h).
///
/// Opbouw van elk bestand:
///   - 48-byte header: Device-ID (8, ASCII), FW-versie (8, ASCII),
///     File-ID (2, big-endian), datum "YYYYMMDD" (8), tijd "HHMMSS" (6),
///     setup-flags (1), reserve (15).
///   - data-gebied: herhaling van ID (uint16 BE), Size (uint16 BE) en
///     Size bytes structuurdata (little-endian). Iedere structuur begint met
///     een TIME-structuur (8 bytes, zie [readTime]).
class PqfParser {
  /// Seconden tussen 1970-01-01 en 1990-01-01 (TIME::seconds-epoch).
  static const int timestampOffset = 631152000;

  /// Header is 48 bytes (0x30)
  static const int headerSize = 0x30;

  /// Grootte van de TIME-structuur aan het begin van elke datastructuur.
  static const int timeSize = 8;

  Future<PqfParseResult> parseFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('File not found', filePath);
    }
    final data = await file.readAsBytes();
    final header = parseHeader(data);
    final records = parseRecords(data);
    return PqfParseResult(header: header, records: records);
  }

  PqfFileHeader parseHeader(Uint8List data) {
    if (data.length < headerSize) {
      throw const FormatException('PQF-bestand te kort voor header.');
    }
    final bd = ByteData.sublistView(data);

    String ascii(int start, int len) => String.fromCharCodes(
            data.sublist(start, start + len).where((b) => b >= 0x20 && b < 0x7f))
        .trim();

    final deviceId = ascii(0, 8);
    final firmwareVersion = ascii(8, 8);
    final fileId = bd.getUint16(16, Endian.big);

    // Datum "YYYYMMDD" (18..25) + tijd "HHMMSS" (26..31), lokale tijd.
    DateTime startTimestamp;
    try {
      final ts = String.fromCharCodes(data.sublist(18, 32));
      startTimestamp = DateTime(
        int.parse(ts.substring(0, 4)),
        int.parse(ts.substring(4, 6)),
        int.parse(ts.substring(6, 8)),
        int.parse(ts.substring(8, 10)),
        int.parse(ts.substring(10, 12)),
        int.parse(ts.substring(12, 14)),
      );
    } catch (_) {
      startTimestamp = DateTime.fromMillisecondsSinceEpoch(0);
    }

    return PqfFileHeader(
      deviceId: deviceId,
      firmwareVersion: firmwareVersion,
      fileId: fileId,
      startTimestamp: startTimestamp,
    );
  }

  /// Leest een TIME-structuur:
  ///   uint32 seconds      — seconden sinds 01.01.1990 00:00:00 UTC
  ///   uint16 subsec_100u  — subseconden in eenheden van 100 µs
  ///   int8   tz_dev       — tijdzone-offset in eenheden van 15 minuten
  ///   uint8  dst_dev      — bit 0: zomertijd actief (bit 7: DCF-sync)
  /// en geeft het tijdstip als UTC-[DateTime] terug; de schermen tonen het
  /// met `.toLocal()`. tz_dev/dst_dev zijn alleen informatief.
  static DateTime readTime(ByteData bd, int offset) {
    final seconds = bd.getUint32(offset, Endian.little);
    final subsec = bd.getUint16(offset + 4, Endian.little);
    return DateTime.fromMillisecondsSinceEpoch(
      (seconds + timestampOffset) * 1000 + subsec ~/ 10,
      isUtc: true,
    );
  }

  List<PqfRecord> parseRecords(Uint8List data) {
    final records = <PqfRecord>[];
    final bd = ByteData.sublistView(data);
    int offset = headerSize;

    while (offset + 4 <= data.length) {
      // ID en Size: uint16 big-endian
      final typeId = bd.getUint16(offset, Endian.big);
      final length = bd.getUint16(offset + 2, Endian.big);
      offset += 4;

      if (length == 0 || offset + length > data.length) {
        break;
      }

      final payloadStart = offset;
      final payloadEnd = offset + length;
      offset = payloadEnd;

      if (length < timeSize) continue;

      final timestamp = readTime(bd, payloadStart);

      // Structuurvelden na de TIME-structuur als float32 LE
      final dataStart = payloadStart + timeSize;
      final dataFloatCount = (payloadEnd - dataStart) ~/ 4;
      final payloadFloats = List<double>.generate(
        dataFloatCount,
        (i) => bd.getFloat32(dataStart + i * 4, Endian.little),
        growable: false,
      );

      records.add(PqfRecord(
        typeId: typeId,
        timestamp: timestamp,
        payload: payloadFloats,
      ));
    }

    return records;
  }

  Future<Map<String, PqfParseResult?>> parseMeasurementFolder(
      String folderPath) async {
    final results = <String, PqfParseResult?>{};

    for (final name in ['cyc.pqf', 'cyc10s.pqf', 'event.pqf']) {
      final path = '$folderPath/$name';
      try {
        results[name] = await parseFile(path);
      } catch (_) {
        results[name] = null;
      }
    }

    return results;
  }
}
