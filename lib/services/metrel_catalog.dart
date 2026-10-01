import 'dart:io';

import 'package:flutter/services.dart';
import 'package:sqlite3/sqlite3.dart';

/// Wat één kolom (descriptor) in een Metrel-record betekent, opgezocht in de
/// meetcatalogus van de Metrel Power SDK.
class MetrelMeasurementInfo {
  /// SDK-naam van de grootheid, bv. `Urms`, `Irms`, `Ih_A`.
  final String code;
  final String symbol;
  final String longName;
  final String unit;

  /// SDK-kanaal, bv. `L1`, `L12`, `Ln`, `Tot`, `RefCh`.
  final String channel;

  /// Harmonische orde, of null als de grootheid geen harmonische is.
  final int? harmonic;

  /// SDK-aggregatie, bv. `Min`, `Max`, `AvgRms`, `AvgAvg`.
  final String aggregation;
  final String aggregationName;

  /// Hoofdgroep uit de meetboom van het instrument, bv. `U,I,F`.
  final String group;

  /// `abs`, `%f`, `%r` of `%n` — onderscheidt absolute en relatieve kolommen.
  final String reference;

  const MetrelMeasurementInfo({
    required this.code,
    required this.symbol,
    required this.longName,
    required this.unit,
    required this.channel,
    required this.harmonic,
    required this.aggregation,
    required this.aggregationName,
    required this.group,
    required this.reference,
  });

  /// Korte label voor een grafieklegenda, bv. `Urms L1 (Min)` of `Ih5 L2`.
  String get label {
    final h = harmonic != null ? '$harmonic' : '';
    final ch = channel == 'RefCh' ? '' : ' $channel';
    return '$symbol$h$ch ($aggregationName)';
  }
}

/// Meetcatalogus van de Metrel Power SDK (`powerdisplay.db` uit het
/// NuGet-pakket Power.SDK.PowerDisplay).
///
/// Een record slaat per kolom een 8-byte descriptor op. Gelezen als
/// little-endian uint64 is dat precies de sleutel van de SDK-tabel
/// `v1.0.0_recorder_measurement`, die naar grootheid, kanaal, harmonische en
/// aggregatie verwijst. De rest van de tabellen levert namen voor
/// event-typen, kanalen en intervalvlaggen.
class MetrelCatalog {
  static const String assetPath = 'assets/metrel/powerdisplay.db';

  final Map<int, MetrelMeasurementInfo> _recorder;

  /// Event-meting (alarm) → (grootheid, kanaal, harmonische).
  final Map<int, MetrelMeasurementInfo> _eventMeasurements;

  /// channel.id → naam (L1, L2, …).
  final Map<int, String> channelNames;

  /// channel.flag_value → naam, voor kanaal-bitmaskers in events.
  final Map<int, String> channelFlags;

  /// voltage_event_type.flag_value → naam (Dip, Swell, Interrupt).
  final Map<int, String> voltageEventTypes;

  /// online_channel.id → naam (U1, I2, …), voor transiënten.
  final Map<int, String> onlineChannels;

  /// flag.flag_value → naam, voor de per-interval vlaggen.
  final Map<int, String> intervalFlags;

  MetrelCatalog._({
    required Map<int, MetrelMeasurementInfo> recorder,
    required Map<int, MetrelMeasurementInfo> eventMeasurements,
    required this.channelNames,
    required this.channelFlags,
    required this.voltageEventTypes,
    required this.onlineChannels,
    required this.intervalFlags,
  })  : _recorder = recorder,
        _eventMeasurements = eventMeasurements;

  static Future<MetrelCatalog>? _instance;

  /// Laadt de catalogus eenmalig uit de app-assets.
  static Future<MetrelCatalog> load() => _instance ??= _loadFromAsset();

  static Future<MetrelCatalog> _loadFromAsset() async {
    final data = await rootBundle.load(assetPath);
    final dir = await Directory.systemTemp.createTemp('metrel_catalog_');
    final file = File('${dir.path}/powerdisplay.db');
    await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
    try {
      return fromFile(file.path);
    } finally {
      await dir.delete(recursive: true);
    }
  }

  /// Leest de catalogus uit een `powerdisplay.db` op schijf.
  static MetrelCatalog fromFile(String path) {
    final db = sqlite3.open(path, mode: OpenMode.readOnly);
    try {
      return _read(db);
    } finally {
      db.close();
    }
  }

  MetrelMeasurementInfo? recorderMeasurement(int descriptor) =>
      _recorder[descriptor];

  MetrelMeasurementInfo? eventMeasurement(int id) => _eventMeasurements[id];

  /// Zet een kanaal-bitmasker om naar namen, bv. `L1, L3`.
  String channelsFromMask(int mask) => _namesFromMask(channelFlags, mask);

  /// Zet een voltage-event-type-bitmasker om naar namen, bv. `Dip, Interrupt`.
  String voltageTypesFromMask(int mask) =>
      _namesFromMask(voltageEventTypes, mask);

  /// Namen van de vlaggen die in een interval gezet zijn.
  List<String> intervalFlagNames(int mask) => [
        for (final e in intervalFlags.entries)
          if (mask & e.key != 0) e.value,
      ];

  static String _namesFromMask(Map<int, String> names, int mask) => [
        for (final e in names.entries)
          if (e.key != 0 && mask & e.key != 0) e.value,
      ].join(', ');

  static MetrelCatalog _read(Database db) {
    final groupNames = <int, String>{};
    final groupParents = <int, int?>{};
    for (final r in db.select(
        'SELECT id, name, parent_id FROM measurement_group')) {
      groupNames[r['id'] as int] = r['name'] as String;
      groupParents[r['id'] as int] = r['parent_id'] as int?;
    }
    String topGroup(int? id, String code, bool isHarmonic) {
      if (id == null) {
        if (!isHarmonic) return 'Other';
        return code.contains('ih') ? 'Interharmonics & IHD' : 'Harmonics & THD';
      }
      var current = id;
      while (groupParents[current] != null) {
        current = groupParents[current]!;
      }
      return groupNames[current] ?? 'Other';
    }

    MetrelMeasurementInfo info(Row r, {bool withAggregation = true}) {
      final code = r['code'] as String;
      final harmonic = r['harmonic'] as int?;
      return MetrelMeasurementInfo(
        code: code,
        symbol: (r['symbol'] as String?) ?? code,
        longName: (r['long_name'] as String?) ?? code,
        unit: (r['unit'] as String?) ?? '',
        channel: r['channel'] as String,
        harmonic: harmonic,
        aggregation: withAggregation ? r['agg'] as String : '',
        aggregationName: withAggregation ? r['agg_name'] as String : '',
        group: topGroup(
            r['group_id'] as int?, code.toLowerCase(), harmonic != null),
        reference: (r['reference'] as String?) ?? 'abs',
      );
    }

    const measurementJoin = '''
      JOIN measurement_channel_property mcp
        ON mcp.id = x.measurement_channel_property_id
      JOIN measurement m ON m.id = mcp.measurement_id
      JOIN channel_property cp ON cp.id = mcp.channel_property_id
      JOIN channel c ON c.id = cp.channel_id
      JOIN si_unit u ON u.id = m.si_unit_id
      LEFT JOIN harmonic h ON h.id = x.harmonic_id AND x.harmonic_id != 0
      LEFT JOIN measurement_reference mr ON mr.id = m.measurement_reference_id
    ''';
    const measurementColumns = '''
      m.code_friendly_name AS code, m.symbol_ascii AS symbol,
      m.long_name AS long_name, u.short_name AS unit,
      c.code_friendly_name AS channel, h.number AS harmonic,
      m.measurement_group_id AS group_id, mr.name AS reference
    ''';

    final recorder = <int, MetrelMeasurementInfo>{};
    for (final r in db.select('''
      SELECT x.id AS id, $measurementColumns,
             a.code_friendly_name AS agg, a.interval_name AS agg_name
      FROM "v1.0.0_recorder_measurement" x
      $measurementJoin
      JOIN aggregation_method a ON a.id = x.aggregation_method_id
    ''')) {
      recorder[r['id'] as int] = info(r);
    }

    final eventMeasurements = <int, MetrelMeasurementInfo>{};
    for (final r in db.select('''
      SELECT x.id AS id, $measurementColumns
      FROM "v1.0.0_event_measurement" x
      $measurementJoin
    ''')) {
      eventMeasurements[r['id'] as int] = info(r, withAggregation: false);
    }

    Map<int, String> pairs(String sql) => {
          for (final r in db.select(sql)) r['k'] as int: r['v'] as String,
        };

    return MetrelCatalog._(
      recorder: recorder,
      eventMeasurements: eventMeasurements,
      channelNames: pairs('SELECT id AS k, name AS v FROM channel'),
      channelFlags: pairs('SELECT flag_value AS k, name AS v FROM channel'),
      voltageEventTypes:
          pairs('SELECT flag_value AS k, name AS v FROM voltage_event_type'),
      onlineChannels: pairs('SELECT id AS k, name AS v FROM online_channel'),
      intervalFlags: pairs('SELECT flag_value AS k, name AS v FROM flag'),
    );
  }
}
