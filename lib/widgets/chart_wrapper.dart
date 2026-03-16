import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ChartWrapper extends StatelessWidget {
  final String title;
  final bool isLoading;
  final bool isEmpty;
  final String emptyMessage;
  final LineChartData chartData;
  final double height;
  final List<LegendItem> legendItems;

  const ChartWrapper({
    super.key,
    required this.title,
    required this.chartData,
    this.isLoading = false,
    this.isEmpty = false,
    this.emptyMessage = 'No data available',
    this.height = 380,
    this.legendItems = const [],
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 24, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            if (legendItems.isNotEmpty)
              Wrap(
                spacing: 16,
                runSpacing: 4,
                children: legendItems
                    .map((item) => _LegendChip(item: item))
                    .toList(),
              ),
            if (legendItems.isNotEmpty) const SizedBox(height: 12),
            SizedBox(
              height: height,
              child: _buildBody(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (isEmpty) {
      return Center(
        child: Text(
          emptyMessage,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
    }
    return LineChart(
      chartData,
      duration: const Duration(milliseconds: 300),
    );
  }
}

class _LegendChip extends StatelessWidget {
  final LegendItem item;
  const _LegendChip({required this.item});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 24,
          height: 3,
          decoration: BoxDecoration(
            color: item.color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          item.label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class LegendItem {
  final String label;
  final Color color;

  const LegendItem({required this.label, required this.color});
}

/// Format a millisecond-epoch double to a short date+time label.
String formatXAxisLabel(double msEpoch) {
  final dt =
      DateTime.fromMillisecondsSinceEpoch(msEpoch.toInt(), isUtc: true)
          .toLocal();
  return DateFormat('MMM d HH:mm').format(dt);
}
