import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/measurement_provider.dart';

class OverviewScreen extends StatelessWidget {
  const OverviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MeasurementProvider>();
    final session = provider.session;
    final folderPath = provider.sessionPath;
    final theme = Theme.of(context);

    if (session == null) {
      return const Center(
        child: Text('No data loaded. Open a PQF measurement folder to begin.'),
      );
    }

    final dateFmt = DateFormat('dd MMM yyyy HH:mm');
    final duration = session.duration;
    final durationStr =
        '${duration.inDays}d ${duration.inHours.remainder(24)}h '
        '${duration.inMinutes.remainder(60)}m';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Recording Overview', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 16),
          if (folderPath != null) ...[
            _PathCard(path: folderPath),
            const SizedBox(height: 16),
          ],
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _InfoCard(
                icon: Icons.devices,
                title: 'Device',
                value: session.deviceId,
                color: theme.colorScheme.primaryContainer,
              ),
              if (session.location != null)
                _InfoCard(
                  icon: Icons.location_on,
                  title: 'Location',
                  value: session.location!,
                  color: theme.colorScheme.secondaryContainer,
                ),
              _InfoCard(
                icon: Icons.calendar_today,
                title: 'Start',
                value: dateFmt.format(session.startTime.toLocal()),
                color: theme.colorScheme.tertiaryContainer,
              ),
              _InfoCard(
                icon: Icons.calendar_month,
                title: 'End',
                value: dateFmt.format(session.endTime.toLocal()),
                color: theme.colorScheme.tertiaryContainer,
              ),
              _InfoCard(
                icon: Icons.timer,
                title: 'Duration',
                value: durationStr,
                color: theme.colorScheme.surfaceContainerHighest,
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Quick Statistics', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              if (session.avgVoltageL1 != null)
                _StatCard(
                  label: 'Avg Voltage L1',
                  value: '${session.avgVoltageL1!.toStringAsFixed(1)} V',
                  color: Colors.red.shade700,
                ),
              if (session.avgVoltageL2 != null)
                _StatCard(
                  label: 'Avg Voltage L2',
                  value: '${session.avgVoltageL2!.toStringAsFixed(1)} V',
                  color: Colors.amber.shade700,
                ),
              if (session.avgVoltageL3 != null)
                _StatCard(
                  label: 'Avg Voltage L3',
                  value: '${session.avgVoltageL3!.toStringAsFixed(1)} V',
                  color: Colors.blue.shade700,
                ),
              if (session.avgFrequency != null)
                _StatCard(
                  label: 'Avg Frequency',
                  value: '${session.avgFrequency!.toStringAsFixed(3)} Hz',
                  color: Colors.green.shade700,
                ),
              _StatCard(
                label: 'Total Events',
                value: '${session.events.length}',
                color: Colors.orange.shade700,
              ),
              _StatCard(
                label: 'Voltage Points',
                value: '${session.voltageData.length}',
                color: theme.colorScheme.primary,
              ),
              _StatCard(
                label: 'Frequency Points (10s)',
                value: '${session.frequencyData10s.length}',
                color: theme.colorScheme.secondary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PathCard extends StatelessWidget {
  final String path;
  const _PathCard({required this.path});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fileName = path.split('/').last;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outline.withAlpha(60)),
      ),
      child: Row(
        children: [
          Icon(Icons.folder_open, size: 22, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fileName,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  path,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurface.withAlpha(140)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.copy, size: 18),
            tooltip: 'Kopieer pad',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: path));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Pad gekopieerd'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final Color color;

  const _InfoCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 180, maxWidth: 420),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 28),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 4),
                Text(value,
                    style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: color, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 6),
          Text(
            value,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(color: color, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
