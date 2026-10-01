/// Bestandsheader van een PQ-Box .pqf-bestand (48 bytes), volgens
/// "PQ-Box Dateiformat" v1.5, hoofdstuk 5.1.
class PqfFileHeader {
  /// Apparaattype, bv. "PQBOX150" / "PQBOX300".
  final String deviceId;

  /// MCU-firmwareversie, bv. "V4.708".
  final String firmwareVersion;

  /// File-ID (bv. 0x0001 = cyc.pqf, 0x0004 = cyc10s.pqf, 0x0021 = event.pqf).
  final int fileId;

  /// Starttijd van de meting (lokale tijd van het apparaat).
  final DateTime startTimestamp;

  const PqfFileHeader({
    required this.deviceId,
    this.firmwareVersion = '',
    this.fileId = -1,
    required this.startTimestamp,
  });

  @override
  String toString() =>
      'PqfFileHeader(deviceId: $deviceId, fw: $firmwareVersion, '
      'fileId: 0x${fileId.toRadixString(16)}, startTimestamp: $startTimestamp)';
}

class PqfRecord {
  final int typeId;

  /// Tijdstempel van de structuur (TIME), in UTC.
  final DateTime timestamp;

  /// Alle 32-bit velden ná de 8-byte TIME-structuur, als float32 (LE)
  /// gelezen. Let op: extreme-waardestructuren (StructUExtr, StructIExtr, …)
  /// bevatten per waarde een eigen TIME-veld (= 2 "floats"), zodat de
  /// eigenlijke waarden op index 2, 5, 8, … staan.
  final List<double> payload;

  const PqfRecord({
    required this.typeId,
    required this.timestamp,
    required this.payload,
  });

  /// Get a data float at index i (after the 8-byte TIME structure).
  double? dataAt(int index) {
    if (index >= 0 && index < payload.length) {
      return payload[index];
    }
    return null;
  }

  @override
  String toString() =>
      'PqfRecord(typeId: $typeId, timestamp: $timestamp, '
      'payload length: ${payload.length})';
}

class MeasurementPoint {
  final DateTime time;
  final Map<String, double> values;

  const MeasurementPoint({
    required this.time,
    required this.values,
  });
}

class PqfParseResult {
  final PqfFileHeader header;
  final List<PqfRecord> records;

  const PqfParseResult({
    required this.header,
    required this.records,
  });
}
