import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

enum PQBoxNetState { idle, scanning, connecting, probing, connected, error }

class MeasurementFolder {
  final String name;
  final String fullPath;
  final DateTime? date;
  final int fileCount;
  final int sizeBytes;
  bool selected;
  bool alreadySynced;

  MeasurementFolder({
    required this.name,
    required this.fullPath,
    this.date,
    this.fileCount = 0,
    this.sizeBytes = 0,
    this.selected = false,
    this.alreadySynced = false,
  });

  String get sizeLabel {
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(0)} KB';
    return '${(sizeBytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}

class PQBoxConnector extends ChangeNotifier {
  // ── Netwerk ──────────────────────────────────────────────────────────────
  String host = '192.168.2.4';
  int port = 5001;

  PQBoxNetState _netState = PQBoxNetState.idle;
  String? _netError;
  final StringBuffer _probeLog = StringBuffer();
  Socket? _socket;

  PQBoxNetState get netState => _netState;
  String? get netError => _netError;
  String get probeLog => _probeLog.toString();

  /// Scan bekende standaard-IP-adressen voor een PQBox op TCP/5001.
  Future<String?> discoverDevice() async {
    _netState = PQBoxNetState.scanning;
    _netError = null;
    notifyListeners();

    final candidates = <String>{
      '192.168.2.4', // WiFi AP standaard
      '172.168.2.4', // LAN / TOSIBOX standaard
      host,
    };

    for (final ip in candidates) {
      try {
        final socket = await Socket.connect(ip, port,
            timeout: const Duration(seconds: 2));
        socket.destroy();
        host = ip;
        _netState = PQBoxNetState.idle;
        notifyListeners();
        return ip;
      } catch (_) {}
    }

    _netError = 'Geen PQBox gevonden op bekende adressen '
        '(192.168.2.4, 172.168.2.4).';
    _netState = PQBoxNetState.error;
    notifyListeners();
    return null;
  }

  /// Verbind met de PQBox en log de ruwe bytes voor protocol-analyse.
  Future<void> connectAndProbe() async {
    _netState = PQBoxNetState.connecting;
    _netError = null;
    _probeLog.clear();
    notifyListeners();

    try {
      _socket = await Socket.connect(host, port,
          timeout: const Duration(seconds: 5));
      _log('Verbonden met $host:$port');
      _netState = PQBoxNetState.probing;
      notifyListeners();

      final received = <int>[];
      final done = Completer<void>();

      _socket!.listen(
        (data) {
          received.addAll(data);
          _log('← [${data.length} bytes] ${_hex(data)}');
          final ascii = String.fromCharCodes(
              data.where((b) => b >= 0x20 && b < 0x7F));
          if (ascii.trim().isNotEmpty) _log('  tekst: "$ascii"');
          notifyListeners();
        },
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
        onError: (e) {
          if (!done.isCompleted) done.completeError(e);
        },
        cancelOnError: false,
      );

      // Wacht 2 seconden op een banner van het apparaat
      await Future.any([
        done.future.catchError((_) {}),
        Future.delayed(const Duration(seconds: 2)),
      ]);

      if (received.isEmpty) {
        _log('Geen banner ontvangen — apparaat wacht op commando.');
        _log('Stuur probe-commando\'s...');
        await _sendProbes();
      }

      _netState = PQBoxNetState.connected;
      notifyListeners();
    } catch (e) {
      _netError = 'Verbinding mislukt: $e';
      _netState = PQBoxNetState.error;
      notifyListeners();
    }
  }

  Future<void> _sendProbes() async {
    // Het TCP/5001-protocol van A-Eberle is niet publiek gedocumenteerd.
    // We sturen een aantal veelgebruikte patronen en loggen wat het apparaat
    // teruggeeft, zodat het protocol verder geanalyseerd kan worden.
    final probes = <Uint8List>[
      Uint8List.fromList([0x01, 0x00, 0x00, 0x00]),
      Uint8List.fromList([0xAE, 0x50, 0x51, 0x00]), // "AE PQ"
      Uint8List.fromList([0x50, 0x51, 0x42, 0x00]), // "PQB"
      Uint8List.fromList([0x00, 0x00, 0x00, 0x01]),
    ];

    for (final p in probes) {
      _log('→ ${_hex(p)}');
      notifyListeners();
      try {
        _socket?.add(p);
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 700));
    }
    _log('Probe klaar. Controleer de log voor apparaat-reacties.');
  }

  void disconnectNet() {
    _socket?.destroy();
    _socket = null;
    _netState = PQBoxNetState.idle;
    notifyListeners();
  }

  void _log(String msg) {
    final t = DateTime.now().toIso8601String().substring(11, 19);
    _probeLog.writeln('[$t] $msg');
  }

  String _hex(List<int> data) => data
      .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join(' ');

  // ── USB / Lokale map sync ─────────────────────────────────────────────────
  String? sourcePath;
  String? destinationPath;
  List<MeasurementFolder> _sourceFolders = [];
  bool _isScanning = false;
  bool _isSyncing = false;
  String? _syncError;
  int _syncProgress = 0;
  int _syncTotal = 0;

  List<MeasurementFolder> get sourceFolders =>
      List.unmodifiable(_sourceFolders);
  bool get isScanning => _isScanning;
  bool get isSyncing => _isSyncing;
  String? get syncError => _syncError;
  int get syncProgress => _syncProgress;
  int get syncTotal => _syncTotal;

  int get selectedCount =>
      _sourceFolders.where((f) => f.selected && !f.alreadySynced).length;

  /// Scan de bronmap voor meetmappen (mappen met .pqf-bestanden).
  Future<void> scanSource() async {
    if (sourcePath == null) return;
    _isScanning = true;
    _syncError = null;
    _sourceFolders = [];
    notifyListeners();

    try {
      final existing = destinationPath != null
          ? Directory(destinationPath!)
              .listSync()
              .whereType<Directory>()
              .map((d) => d.path.split(Platform.pathSeparator).last)
              .toSet()
          : <String>{};

      final folders = <MeasurementFolder>[];
      final dir = Directory(sourcePath!);

      await for (final entity in dir.list()) {
        if (entity is! Directory) continue;
        final name = entity.path.split(Platform.pathSeparator).last;
        if (name.startsWith('.')) continue;

        final files = entity.listSync().whereType<File>().toList();
        final pqfFiles =
            files.where((f) => f.path.toLowerCase().endsWith('.pqf')).toList();
        if (pqfFiles.isEmpty) continue;

        final sizeBytes =
            pqfFiles.fold<int>(0, (s, f) => s + f.lengthSync());

        DateTime? date;
        final m = RegExp(r'^(\d{4})(\d{2})(\d{2})_(\d{2})(\d{2})')
            .firstMatch(name);
        if (m != null) {
          date = DateTime(
            int.parse(m.group(1)!),
            int.parse(m.group(2)!),
            int.parse(m.group(3)!),
            int.parse(m.group(4)!),
            int.parse(m.group(5)!),
          );
        }

        final synced = existing.contains(name);
        folders.add(MeasurementFolder(
          name: name,
          fullPath: entity.path,
          date: date,
          fileCount: pqfFiles.length,
          sizeBytes: sizeBytes,
          selected: !synced, // nieuwe mappen standaard aangevinkt
          alreadySynced: synced,
        ));
      }

      folders.sort((a, b) {
        if (a.date != null && b.date != null) return b.date!.compareTo(a.date!);
        return b.name.compareTo(a.name);
      });

      _sourceFolders = folders;
    } catch (e) {
      _syncError = 'Scan mislukt: $e';
    }

    _isScanning = false;
    notifyListeners();
  }

  /// Kopieer alle geselecteerde (niet-gesynchroniseerde) mappen naar het doel.
  Future<void> syncSelected() async {
    if (destinationPath == null) return;
    final toSync =
        _sourceFolders.where((f) => f.selected && !f.alreadySynced).toList();
    if (toSync.isEmpty) return;

    _isSyncing = true;
    _syncProgress = 0;
    _syncTotal = toSync.length;
    _syncError = null;
    notifyListeners();

    for (final folder in toSync) {
      try {
        final sep = Platform.pathSeparator;
        final dest = Directory('$destinationPath$sep${folder.name}');
        await dest.create(recursive: true);

        await for (final entity
            in Directory(folder.fullPath).list(recursive: true)) {
          if (entity is! File) continue;
          final rel = entity.path.substring(folder.fullPath.length);
          final destFile = File('${dest.path}$rel');
          await destFile.parent.create(recursive: true);
          await entity.copy(destFile.path);
        }

        folder.alreadySynced = true;
        folder.selected = false;
        _syncProgress++;
        notifyListeners();
      } catch (e) {
        _syncError = 'Fout bij kopiëren van ${folder.name}: $e';
        notifyListeners();
      }
    }

    _isSyncing = false;
    notifyListeners();
  }

  void toggleFolder(int index) {
    if (!_sourceFolders[index].alreadySynced) {
      _sourceFolders[index].selected = !_sourceFolders[index].selected;
      notifyListeners();
    }
  }

  void selectAll() {
    for (final f in _sourceFolders) {
      if (!f.alreadySynced) f.selected = true;
    }
    notifyListeners();
  }

  void selectNone() {
    for (final f in _sourceFolders) {
      f.selected = false;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _socket?.destroy();
    super.dispose();
  }
}
