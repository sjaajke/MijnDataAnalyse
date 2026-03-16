class PqfFileHeader {
  final String deviceId;
  final DateTime startTimestamp;

  const PqfFileHeader({
    required this.deviceId,
    required this.startTimestamp,
  });

  @override
  String toString() =>
      'PqfFileHeader(deviceId: $deviceId, startTimestamp: $startTimestamp)';
}

class PqfRecord {
  final int typeId;
  final DateTime timestamp;
  final List<double> payload;

  const PqfRecord({
    required this.typeId,
    required this.timestamp,
    required this.payload,
  });

  /// Get a data float at index i (after 4-byte timestamp + 4-byte flags).
  /// data[0] = payload bytes 8-11, data[1] = payload bytes 12-15, etc.
  double? dataAt(int index) {
    if (index >= 0 && index < payload.length) {
      return payload[index];
    }
    return null;
  }

  @override
  String toString() =>
      'PqfRecord(typeId: 0x${typeId.toRadixString(16).padLeft(4, '0')}, '
      'timestamp: $timestamp, payload length: ${payload.length})';
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
