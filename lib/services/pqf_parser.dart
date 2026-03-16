import 'dart:io';
import 'dart:typed_data';
import '../models/pqf_record.dart';

class PqfParser {
  static const int timestampOffset = 631152000;
  // Header is 48 bytes (0x30)
  static const int headerSize = 0x30;

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
    // Bytes 0-15: device ID (ASCII, null/space padded)
    final deviceIdBytes = data.sublist(0, 16);
    final deviceId = String.fromCharCodes(deviceIdBytes).trim();

    // Bytes 18-31: ASCII timestamp YYYYMMDDHHMMSS (14 chars)
    final tsBytes = data.sublist(18, 32);
    final tsString = String.fromCharCodes(tsBytes).trim();

    DateTime startTimestamp;
    try {
      // Parse YYYYMMDDHHMMSS
      final year = int.parse(tsString.substring(0, 4));
      final month = int.parse(tsString.substring(4, 6));
      final day = int.parse(tsString.substring(6, 8));
      final hour = int.parse(tsString.substring(8, 10));
      final minute = int.parse(tsString.substring(10, 12));
      final second = int.parse(tsString.substring(12, 14));
      startTimestamp = DateTime(year, month, day, hour, minute, second);
    } catch (_) {
      startTimestamp = DateTime.fromMillisecondsSinceEpoch(0);
    }

    return PqfFileHeader(deviceId: deviceId, startTimestamp: startTimestamp);
  }

  List<PqfRecord> parseRecords(Uint8List data) {
    final records = <PqfRecord>[];
    int offset = headerSize;

    while (offset + 4 <= data.length) {
      final bd = ByteData.sublistView(data);

      // Type: uint16 big-endian
      final typeId = bd.getUint16(offset, Endian.big);
      offset += 2;

      // Length: uint16 big-endian
      final length = bd.getUint16(offset, Endian.big);
      offset += 2;

      if (length == 0 || offset + length > data.length) {
        break;
      }

      final payloadStart = offset;
      final payloadEnd = offset + length;

      // Parse timestamp from first 4 bytes of payload as uint32 LE
      final rawTs = bd.getUint32(payloadStart, Endian.little);
      final correctedTs = rawTs + timestampOffset;
      final timestamp =
          DateTime.fromMillisecondsSinceEpoch(correctedTs * 1000, isUtc: true);

      // Parse all remaining floats from byte 8 onward (after ts + flags)
      final dataStart = payloadStart + 8;
      final dataFloatCount = (payloadEnd - dataStart) ~/ 4;
      final payloadFloats = <double>[];
      for (int i = 0; i < dataFloatCount; i++) {
        final floatOffset = dataStart + i * 4;
        if (floatOffset + 4 <= payloadEnd) {
          payloadFloats.add(bd.getFloat32(floatOffset, Endian.little));
        }
      }

      records.add(PqfRecord(
        typeId: typeId,
        timestamp: timestamp,
        payload: payloadFloats,
      ));

      offset = payloadEnd;
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
