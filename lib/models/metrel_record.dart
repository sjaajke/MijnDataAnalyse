import 'dart:typed_data';

import '../services/metrel_catalog.dart';

/// Eén kolom in een intervalstroom: de ruwe descriptor plus de betekenis
/// volgens de SDK-catalogus (null als de catalogus hem niet kent).
class MetrelDescriptor {
  final int index;
  final int key;
  final MetrelMeasurementInfo? info;

  const MetrelDescriptor({
    required this.index,
    required this.key,
    required this.info,
  });

  String get label =>
      info?.label ?? '0x${key.toRadixString(16).padLeft(16, '0')}';
}

/// Eén geaggregeerde intervalstroom (`periodics/{N}s_*`) van een record.
///
/// Data staat kolomgewijs in blokken van [blockSize] intervallen:
/// per blok eerst alle waarden van descriptor 0, dan descriptor 1, enz.
/// Een databestand (`{N}s_data_000`, `_001`, …) bevat [recordsPerFile]
/// intervallen.
class MetrelStream {
  final int intervalSeconds;
  final int blockSize;
  final int recordsPerFile;
  final List<MetrelDescriptor> descriptors;

  /// Tijdstip per interval (UTC).
  final List<DateTime> times;

  /// Vlaggen-bitmasker per interval (zie [MetrelCatalog.intervalFlagNames]).
  final List<int> flags;

  final Uint8List? Function(int fileIndex) _readDataFile;
  final Map<int, ByteData?> _dataFiles = {};

  MetrelStream({
    required this.intervalSeconds,
    required this.blockSize,
    required this.recordsPerFile,
    required this.descriptors,
    required this.times,
    required this.flags,
    required Uint8List? Function(int fileIndex) readDataFile,
  }) : _readDataFile = readDataFile;

  int get recordCount => times.length;

  String get label => formatInterval(intervalSeconds);

  static String formatInterval(int seconds) {
    if (seconds % 3600 == 0) return '${seconds ~/ 3600} h';
    if (seconds % 60 == 0) return '${seconds ~/ 60} min';
    return '$seconds s';
  }

  /// Zoekt de kolom voor een grootheid/kanaal/aggregatie (en harmonische).
  MetrelDescriptor? find(String code, String channel, String aggregation,
      {int? harmonic}) {
    for (final d in descriptors) {
      final i = d.info;
      if (i != null &&
          i.code == code &&
          i.channel == channel &&
          i.aggregation == aggregation &&
          i.harmonic == harmonic) {
        return d;
      }
    }
    return null;
  }

  /// Alle waarden van één kolom, index-gelijk met [times].
  List<double> values(int descriptorIndex) {
    final n = descriptors.length;
    final result = List<double>.filled(recordCount, double.nan);
    for (var r = 0; r < recordCount; r++) {
      final fileIndex = recordsPerFile > 0 ? r ~/ recordsPerFile : 0;
      final inFile = recordsPerFile > 0 ? r % recordsPerFile : r;
      final data = _dataFiles.putIfAbsent(fileIndex, () {
        final bytes = _readDataFile(fileIndex);
        return bytes == null ? null : ByteData.sublistView(bytes);
      });
      if (data == null) continue;
      final block = inFile ~/ blockSize;
      final row = inFile % blockSize;
      final offset = ((block * n + descriptorIndex) * blockSize + row) * 4;
      if (offset + 4 > data.lengthInBytes) continue;
      result[r] = data.getFloat32(offset, Endian.little);
    }
    return result;
  }
}

/// De zes event-families die een Metrel-instrument vastlegt.
enum MetrelEventFamily {
  voltage('Spanning'),
  rvc('RVC'),
  inrush('Inschakelstroom'),
  signalling('Signalering'),
  alarm('Alarm'),
  transient('Transiënt');

  final String label;
  const MetrelEventFamily(this.label);
}

class MetrelEvent {
  final MetrelEventFamily family;
  final int id;

  /// Begin van het event (UTC).
  final DateTime start;
  final Duration duration;

  /// Type, bv. `Dip, Interrupt`, of de grootheid bij een alarm.
  final String type;
  final String channels;

  /// Kenmerkende waarde (restspanning, piek, extreme waarde…), of null.
  final double? magnitude;
  final String unit;
  final String details;

  /// Voor spanningsevents: bitmasker uit voltage_event_type (1 swell,
  /// 2 interrupt, 4 dip).
  final int typeMask;

  const MetrelEvent({
    required this.family,
    required this.id,
    required this.start,
    required this.duration,
    required this.type,
    required this.channels,
    required this.magnitude,
    required this.unit,
    this.details = '',
    this.typeMask = 0,
  });
}

class MetrelRecord {
  /// Naam zoals het instrument hem toont, bv. `22.11.2024 15:10:44`.
  final String name;

  /// Mapnaam in het archief, bv. `record_22_11_2024-15_10_44`.
  final String folder;
  final String? timeZoneId;

  /// UTC-offset van het instrument tijdens de opname, indien bekend.
  final Duration? utcOffset;
  final DateTime? start;
  final DateTime? end;

  final Map<String, dynamic> instrumentInfo;
  final Map<String, dynamic> measurementSettings;
  final Map<String, dynamic> recorderSettings;

  final List<MetrelStream> streams;
  final List<MetrelEvent> events;

  const MetrelRecord({
    required this.name,
    required this.folder,
    required this.timeZoneId,
    required this.utcOffset,
    required this.start,
    required this.end,
    required this.instrumentInfo,
    required this.measurementSettings,
    required this.recorderSettings,
    required this.streams,
    required this.events,
  });

  String get instrumentLabel {
    final model = instrumentInfo['model'] as String? ?? 'Metrel';
    final serial = instrumentInfo['serialNumber'] as String? ?? '';
    return '$model $serial'.trim();
  }

  double? get nominalVoltage => (measurementSettings['connectionSettings']
          ?['nominalVoltage']?['value'] as num?)
      ?.toDouble();

  String? get location {
    final v = recorderSettings['recorderSettings']?['recordInfo']?['location']
        ?['value'] as String?;
    return (v == null || v.isEmpty) ? null : v;
  }

  /// Tijdstip omgezet naar de wandkloktijd van het instrument (als
  /// UTC-DateTime, zodat formatteren geen lokale offset toevoegt).
  DateTime toRecordTime(DateTime utc) =>
      utcOffset == null ? utc.toLocal() : utc.toUtc().add(utcOffset!);

  String get utcOffsetLabel {
    final o = utcOffset;
    if (o == null) return 'lokale tijd';
    final sign = o.isNegative ? '−' : '+';
    final m = o.inMinutes.abs();
    return 'UTC$sign${(m ~/ 60).toString().padLeft(2, '0')}:'
        '${(m % 60).toString().padLeft(2, '0')}';
  }
}
