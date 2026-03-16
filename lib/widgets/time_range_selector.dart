import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// A range slider with timestamp labels for filtering chart data by time.
///
/// [totalMinMs] / [totalMaxMs] define the full data range (epoch ms, UTC).
/// [filterMinMs] / [filterMaxMs] are the current selection.
/// Call [onChanged] when the user drags a handle.
/// Call [onReset] when the user taps the reset button.
class TimeRangeSelector extends StatelessWidget {
  final double totalMinMs;
  final double totalMaxMs;
  final double filterMinMs;
  final double filterMaxMs;
  final void Function(double start, double end) onChanged;
  final VoidCallback onReset;

  const TimeRangeSelector({
    super.key,
    required this.totalMinMs,
    required this.totalMaxMs,
    required this.filterMinMs,
    required this.filterMaxMs,
    required this.onChanged,
    required this.onReset,
  });

  static final _fmt = DateFormat('d MMM HH:mm');

  String _label(double ms) =>
      _fmt.format(DateTime.fromMillisecondsSinceEpoch(ms.toInt(), isUtc: true).toLocal());

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final span = totalMaxMs - totalMinMs;
    final startVal = span > 0 ? (filterMinMs - totalMinMs) / span : 0.0;
    final endVal = span > 0 ? (filterMaxMs - totalMinMs) / span : 1.0;
    final isFiltered = startVal > 0.001 || endVal < 0.999;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(_label(filterMinMs),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  )),
              const Spacer(),
              if (isFiltered)
                TextButton.icon(
                  onPressed: onReset,
                  icon: const Icon(Icons.zoom_out_map, size: 14),
                  label: const Text('Reset', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              const Spacer(),
              Text(_label(filterMaxMs),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  )),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              rangeThumbShape: const RoundRangeSliderThumbShape(enabledThumbRadius: 7),
              trackHeight: 3,
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: RangeSlider(
              values: RangeValues(startVal.clamp(0.0, 1.0), endVal.clamp(0.0, 1.0)),
              min: 0.0,
              max: 1.0,
              onChanged: (v) {
                final newMin = totalMinMs + v.start * span;
                final newMax = totalMinMs + v.end * span;
                onChanged(newMin, newMax);
              },
            ),
          ),
        ],
      ),
    );
  }
}
