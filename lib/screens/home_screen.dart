import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/measurement_provider.dart';
import 'comparison_screen.dart';
import 'cos_phi_screen.dart';
import 'en50160_screen.dart';
import 'pqbox_download_screen.dart';
import 'current_capacity_screen.dart';
import 'current_screen.dart';
import 'events_screen.dart';
import 'frequency_screen.dart';
import 'harmonic_screen.dart';
import 'opname_screen.dart';
import 'overview_screen.dart';
import 'power_screen.dart';
import 'transients_screen.dart';
import 'systeemcode_screen.dart';
import 'meter_excel_screen.dart';
import 'standaarden_screen.dart';
import 'voltage_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  final Set<int> _bezochteIndices = {0};

  static const List<NavigationRailDestination> _destinations = [
    NavigationRailDestination(
      icon: Icon(Icons.dashboard_outlined),
      selectedIcon: Icon(Icons.dashboard),
      label: Text('Overview'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.electric_bolt_outlined),
      selectedIcon: Icon(Icons.electric_bolt),
      label: Text('Voltage'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.waves_outlined),
      selectedIcon: Icon(Icons.waves),
      label: Text('Current'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.speed_outlined),
      selectedIcon: Icon(Icons.speed),
      label: Text('Frequency'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.warning_amber_outlined),
      selectedIcon: Icon(Icons.warning_amber),
      label: Text('Events'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.bar_chart_outlined),
      selectedIcon: Icon(Icons.bar_chart),
      label: Text('Harmonischen'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.rotate_right_outlined),
      selectedIcon: Icon(Icons.rotate_right),
      label: Text('Cos φ'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.analytics_outlined),
      selectedIcon: Icon(Icons.analytics),
      label: Text('Opname'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.compare_arrows_outlined),
      selectedIcon: Icon(Icons.compare_arrows),
      label: Text('Vergelijking'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.electric_meter_outlined),
      selectedIcon: Icon(Icons.electric_meter),
      label: Text('Capaciteit'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.flash_on_outlined),
      selectedIcon: Icon(Icons.flash_on),
      label: Text('Transiënten'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.bolt_outlined),
      selectedIcon: Icon(Icons.bolt),
      label: Text('Vermogen'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.verified_outlined),
      selectedIcon: Icon(Icons.verified),
      label: Text('EN 50160'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.auto_awesome_outlined),
      selectedIcon: Icon(Icons.auto_awesome),
      label: Text('Systeemcode'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.table_chart_outlined),
      selectedIcon: Icon(Icons.table_chart),
      label: Text('Energiemeter'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.rule_folder_outlined),
      selectedIcon: Icon(Icons.rule_folder),
      label: Text('Standaarden'),
    ),
  ];

  final List<Widget> _screens = const [
    OverviewScreen(),
    VoltageScreen(),
    CurrentScreen(),
    FrequencyScreen(),
    EventsScreen(),
    HarmonicScreen(),
    CosPhiScreen(),
    OpnameScreen(),
    ComparisonScreen(),
    CurrentCapacityScreen(),
    TransientsScreen(),
    PowerScreen(),
    En50160Screen(),
    SysteemcodeScreen(),
    MeterExcelScreen(),
    StandaardenScreen(),
  ];

  Future<void> _pickFolder(BuildContext context) async {
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select PQF Measurement Folder',
    );
    if (path != null && context.mounted) {
      await context.read<MeasurementProvider>().loadFolder(path);
    }
  }

  Future<void> _pickFpqoFile(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Open Fluke FPQO bestand',
      type: FileType.custom,
      allowedExtensions: ['fpqo'],
    );
    final path = result?.files.single.path;
    if (path != null && context.mounted) {
      await context.read<MeasurementProvider>().loadFpqoFile(path);
    }
  }

  Future<void> _pickPwvxFile(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Open Metrel PowerView bestand',
      type: FileType.custom,
      allowedExtensions: ['pwvx'],
    );
    final path = result?.files.single.path;
    if (path != null && context.mounted) {
      await context.read<MeasurementProvider>().loadPwvxFile(path);
    }
  }

  Future<void> _pickCsvFolder(BuildContext context) async {
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select PQ-Box 150 CSV Folder',
    );
    if (path != null && context.mounted) {
      await context.read<MeasurementProvider>().loadCsvFolder(path);
    }
  }

  Future<void> _pickDvbFile(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Open Chauvin Arnoux DataView bestand',
      type: FileType.custom,
      allowedExtensions: ['dvb'],
    );
    final path = result?.files.single.path;
    if (path != null && context.mounted) {
      await context.read<MeasurementProvider>().loadDvbFile(path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MeasurementProvider>();
    final theme = Theme.of(context);

    return Scaffold(
      body: Row(
        children: [
          SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  minHeight: MediaQuery.of(context).size.height),
              child: IntrinsicHeight(
                child: NavigationRail(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: (index) => setState(() {
                    _selectedIndex = index;
                    _bezochteIndices.add(index);
                  }),
                  labelType: NavigationRailLabelType.all,
                  destinations: _destinations,
                  leading: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Column(
                      children: [
                        Icon(
                          Icons.bolt,
                          size: 32,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'PQAnalyse',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        PopupMenuButton<String>(
                          enabled: !provider.isLoading,
                          onSelected: (value) {
                            if (value == 'pqf') _pickFolder(context);
                            if (value == 'csv') _pickCsvFolder(context);
                            if (value == 'fpqo') _pickFpqoFile(context);
                            if (value == 'dvb') _pickDvbFile(context);
                            if (value == 'pwvx') _pickPwvxFile(context);
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'pqf',
                              child: ListTile(
                                leading: Icon(Icons.folder_open),
                                title: Text('PQF map (A-Eberle)'),
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                            PopupMenuItem(
                              value: 'csv',
                              child: ListTile(
                                leading: Icon(Icons.folder_open),
                                title: Text('CSV map (PQ-Box 150)'),
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                            PopupMenuItem(
                              value: 'fpqo',
                              child: ListTile(
                                leading: Icon(Icons.file_open),
                                title: Text('FPQO bestand (Fluke)'),
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                            PopupMenuItem(
                              value: 'dvb',
                              child: ListTile(
                                leading: Icon(Icons.analytics_outlined),
                                title: Text('DVB bestand (Chauvin Arnoux)'),
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                            PopupMenuItem(
                              value: 'pwvx',
                              child: ListTile(
                                leading: Icon(Icons.electrical_services),
                                title: Text('PWVX bestand (Metrel)'),
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ],
                          child: Builder(
                            builder: (context) {
                              final colors = Theme.of(context).colorScheme;
                              final isEnabled = !provider.isLoading;
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isEnabled
                                      ? colors.secondaryContainer
                                      : colors.onSurface.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.upload_file,
                                        size: 20,
                                        color: isEnabled
                                            ? colors.onSecondaryContainer
                                            : colors.onSurface.withValues(alpha: 0.38)),
                                    const SizedBox(height: 2),
                                    Text('Importeer',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: isEnabled
                                                ? colors.onSecondaryContainer
                                                : colors.onSurface.withValues(alpha: 0.38))),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
                        FilledButton.tonal(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const PQBoxDownloadScreen(),
                            ),
                          ),
                          child: const Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.download, size: 20),
                              SizedBox(height: 2),
                              Text('PQBox', style: TextStyle(fontSize: 11)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(
            child: Stack(
              children: [
                IndexedStack(
                  index: _selectedIndex,
                  children: [
                    for (var i = 0; i < _screens.length; i++)
                      _bezochteIndices.contains(i)
                          ? _screens[i]
                          : const SizedBox.shrink(),
                  ],
                ),
                if (provider.isLoading)
                  const Positioned.fill(
                    child: ColoredBox(
                      color: Colors.black45,
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ),
                if (provider.error != null)
                  Positioned(
                    bottom: 16,
                    left: 16,
                    right: 16,
                    child: _ErrorBanner(
                      message: provider.error!,
                      onDismiss: () =>
                          context.read<MeasurementProvider>().clearError(),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;

  const _ErrorBanner({required this.message, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(8),
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.error_outline,
                color: Theme.of(context).colorScheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: SelectableText(
                message,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.copy_outlined),
              tooltip: 'Kopiëren',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: message));
              },
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: onDismiss,
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
          ],
        ),
      ),
    );
  }
}
