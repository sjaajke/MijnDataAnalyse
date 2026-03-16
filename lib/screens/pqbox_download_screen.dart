import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../services/pqbox_connector.dart';

class PQBoxDownloadScreen extends StatelessWidget {
  const PQBoxDownloadScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => PQBoxConnector(),
      child: const _Content(),
    );
  }
}

class _Content extends StatefulWidget {
  const _Content();

  @override
  State<_Content> createState() => _ContentState();
}

class _ContentState extends State<_Content>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PQBox — data downloaden'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.wifi), text: 'Netwerk (TCP/5001)'),
            Tab(icon: Icon(Icons.usb), text: 'USB / Lokale map'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          _NetworkTab(),
          _UsbTab(),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Netwerk tab
// ─────────────────────────────────────────────────────────────────────────────

class _NetworkTab extends StatefulWidget {
  const _NetworkTab();

  @override
  State<_NetworkTab> createState() => _NetworkTabState();
}

class _NetworkTabState extends State<_NetworkTab> {
  late final TextEditingController _ipCtrl;
  late final TextEditingController _portCtrl;
  final _logScrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    final conn = context.read<PQBoxConnector>();
    _ipCtrl = TextEditingController(text: conn.host);
    _portCtrl = TextEditingController(text: conn.port.toString());
  }

  @override
  void dispose() {
    _ipCtrl.dispose();
    _portCtrl.dispose();
    _logScrollCtrl.dispose();
    super.dispose();
  }

  void _applySettings() {
    final conn = context.read<PQBoxConnector>();
    conn.host = _ipCtrl.text.trim();
    conn.port = int.tryParse(_portCtrl.text.trim()) ?? 5001;
  }

  @override
  Widget build(BuildContext context) {
    final conn = context.watch<PQBoxConnector>();
    final busy = conn.netState == PQBoxNetState.scanning ||
        conn.netState == PQBoxNetState.connecting ||
        conn.netState == PQBoxNetState.probing;

    // Auto-scroll log naar beneden als er nieuwe regels komen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollCtrl.hasClients) {
        _logScrollCtrl.animateTo(
          _logScrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Uitleg ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'De PQBox communiceert via een proprietary TCP-protocol op poort 5001. '
                      'Verbind eerst met het WiFi-netwerk van de PQBox '
                      '(SSID: PQBox300AP_XXXX-XXX op het apparaat) of via LAN. '
                      'De probe-log toont ruwe bytes voor protocol-analyse.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── IP / poort ──
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _ipCtrl,
                  enabled: !busy,
                  decoration: const InputDecoration(
                    labelText: 'IP-adres',
                    hintText: '192.168.2.4',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 100,
                child: TextField(
                  controller: _portCtrl,
                  enabled: !busy,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Poort',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: busy
                    ? null
                    : () async {
                        _applySettings();
                        final messenger = ScaffoldMessenger.of(context);
                        final found = await conn.discoverDevice();
                        if (found == null) return;
                        _ipCtrl.text = found;
                        messenger.showSnackBar(
                          SnackBar(content: Text('PQBox gevonden op $found')),
                        );
                      },
                child: const Text('Zoeken'),
              ),
              const SizedBox(width: 8),
              if (conn.netState == PQBoxNetState.idle ||
                  conn.netState == PQBoxNetState.error)
                FilledButton(
                  onPressed: busy
                      ? null
                      : () {
                          _applySettings();
                          conn.connectAndProbe();
                        },
                  child: const Text('Verbinden & probe'),
                )
              else if (conn.netState == PQBoxNetState.connected)
                OutlinedButton(
                  onPressed: conn.disconnectNet,
                  child: const Text('Verbreken'),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // ── Status ──
          _StatusChip(state: conn.netState, error: conn.netError),
          const SizedBox(height: 16),

          // ── Probe-log ──
          Text('Protocol-log',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Stack(
                children: [
                  SingleChildScrollView(
                    controller: _logScrollCtrl,
                    padding: const EdgeInsets.all(12),
                    child: SelectableText(
                      conn.probeLog.isEmpty
                          ? '— nog geen verbinding —'
                          : conn.probeLog,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                    ),
                  ),
                  if (conn.probeLog.isNotEmpty)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: IconButton(
                        icon: const Icon(Icons.copy, size: 16),
                        tooltip: 'Kopieer log',
                        onPressed: () {
                          Clipboard.setData(
                              ClipboardData(text: conn.probeLog));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Log gekopieerd')),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final PQBoxNetState state;
  final String? error;

  const _StatusChip({required this.state, this.error});

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (state) {
      PQBoxNetState.idle => ('Niet verbonden', Colors.grey, Icons.circle_outlined),
      PQBoxNetState.scanning => ('Zoeken...', Colors.blue, Icons.search),
      PQBoxNetState.connecting => ('Verbinden...', Colors.orange, Icons.sync),
      PQBoxNetState.probing => ('Probe actief...', Colors.orange, Icons.sync),
      PQBoxNetState.connected => ('Verbonden', Colors.green, Icons.check_circle),
      PQBoxNetState.error => (error ?? 'Fout', Colors.red, Icons.error_outline),
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (state == PQBoxNetState.scanning ||
            state == PQBoxNetState.connecting ||
            state == PQBoxNetState.probing)
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                fontSize: 12, color: color, fontWeight: FontWeight.w500)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// USB / Lokale map tab
// ─────────────────────────────────────────────────────────────────────────────

class _UsbTab extends StatelessWidget {
  const _UsbTab();

  @override
  Widget build(BuildContext context) {
    final conn = context.watch<PQBoxConnector>();

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Uitleg ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Verbind de PQBox via USB en schakel hem in USB Mass Storage-modus '
                      '(Setup → USB → MSC). macOS koppelt het apparaat als schijf. '
                      'Kies de schijf als bronmap en selecteer welke meetmappen je wilt kopiëren.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Pad-selectie ──
          _FolderRow(
            label: 'Bronmap (PQBox)',
            path: conn.sourcePath,
            icon: Icons.usb,
            onPick: () async {
              final path = await FilePicker.platform.getDirectoryPath(
                dialogTitle: 'Selecteer PQBox-map (USB-schijf)',
              );
              if (path != null) {
                conn.sourcePath = path;
                await conn.scanSource();
              }
            },
          ),
          const SizedBox(height: 8),
          _FolderRow(
            label: 'Doelmap (lokaal)',
            path: conn.destinationPath,
            icon: Icons.folder,
            onPick: () async {
              final path = await FilePicker.platform.getDirectoryPath(
                dialogTitle: 'Selecteer doelmap',
              );
              if (path != null) {
                conn.destinationPath = path;
                // Herscand om de "al gesynchroniseerd"-status te herberekenen
                if (conn.sourcePath != null) await conn.scanSource();
              }
            },
          ),
          const SizedBox(height: 16),

          // ── Actiebalk ──
          Row(
            children: [
              Text(
                conn.sourceFolders.isEmpty
                    ? 'Geen mappen geladen'
                    : '${conn.sourceFolders.length} mappen gevonden  •  '
                        '${conn.selectedCount} geselecteerd',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const Spacer(),
              TextButton(
                onPressed:
                    conn.sourceFolders.isEmpty ? null : conn.selectAll,
                child: const Text('Alles'),
              ),
              TextButton(
                onPressed:
                    conn.sourceFolders.isEmpty ? null : conn.selectNone,
                child: const Text('Geen'),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: conn.sourcePath == null || conn.isScanning
                    ? null
                    : conn.scanSource,
                child: const Text('Vernieuwen'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: conn.selectedCount == 0 ||
                        conn.destinationPath == null ||
                        conn.isSyncing
                    ? null
                    : conn.syncSelected,
                child: Text(conn.isSyncing
                    ? 'Bezig… ${conn.syncProgress}/${conn.syncTotal}'
                    : 'Kopiëren (${conn.selectedCount})'),
              ),
            ],
          ),

          // ── Voortgangsbalk ──
          if (conn.isSyncing)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(
                value: conn.syncTotal > 0
                    ? conn.syncProgress / conn.syncTotal
                    : null,
              ),
            ),

          // ── Foutmelding ──
          if (conn.syncError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(conn.syncError!,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12)),
            ),

          const SizedBox(height: 8),

          // ── Mappenlijst ──
          Expanded(
            child: conn.isScanning
                ? const Center(child: CircularProgressIndicator())
                : conn.sourceFolders.isEmpty
                    ? Center(
                        child: Text(
                          conn.sourcePath == null
                              ? 'Kies een bronmap om te beginnen.'
                              : 'Geen meetmappen gevonden in de geselecteerde map.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      )
                    : ListView.builder(
                        itemCount: conn.sourceFolders.length,
                        itemBuilder: (context, i) {
                          final f = conn.sourceFolders[i];
                          return _FolderTile(
                            folder: f,
                            onToggle: () => conn.toggleFolder(i),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _FolderRow extends StatelessWidget {
  final String label;
  final String? path;
  final IconData icon;
  final VoidCallback onPick;

  const _FolderRow({
    required this.label,
    required this.path,
    required this.icon,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        SizedBox(
          width: 110,
          child: Text(label,
              style: Theme.of(context).textTheme.labelMedium),
        ),
        Expanded(
          child: Text(
            path ?? '— niet geselecteerd —',
            style: TextStyle(
              fontSize: 12,
              color: path == null
                  ? Theme.of(context).colorScheme.onSurfaceVariant
                  : null,
              fontFamily: path != null ? 'monospace' : null,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          onPressed: onPick,
          child: const Text('Kies…'),
        ),
      ],
    );
  }
}

class _FolderTile extends StatelessWidget {
  final MeasurementFolder folder;
  final VoidCallback onToggle;

  const _FolderTile({required this.folder, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final dateStr = folder.date != null
        ? DateFormat('dd/MM/yyyy HH:mm').format(folder.date!)
        : null;

    return ListTile(
      dense: true,
      leading: folder.alreadySynced
          ? Icon(Icons.check_circle,
              color: Theme.of(context).colorScheme.primary, size: 20)
          : Checkbox(
              value: folder.selected,
              onChanged: (_) => onToggle(),
            ),
      title: Text(
        folder.name,
        style: TextStyle(
          fontSize: 13,
          fontFamily: 'monospace',
          color: folder.alreadySynced
              ? Theme.of(context).colorScheme.onSurfaceVariant
              : null,
        ),
      ),
      subtitle: dateStr != null ? Text(dateStr, style: const TextStyle(fontSize: 11)) : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${folder.fileCount} bestanden  •  ${folder.sizeLabel}',
            style: const TextStyle(fontSize: 11),
          ),
          const SizedBox(width: 8),
          if (folder.alreadySynced)
            const Chip(
              label: Text('Gesynchroniseerd', style: TextStyle(fontSize: 10)),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
      onTap: folder.alreadySynced ? null : onToggle,
    );
  }
}
