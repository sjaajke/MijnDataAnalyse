import 'package:flutter/foundation.dart';

import '../models/measurement_data.dart';
import '../models/metrel_record.dart';
import '../services/metrel_catalog.dart';
import '../services/metrel_pwvx_parser.dart';
import '../services/metrel_record_reader.dart';

/// Houdt het geopende Metrel-bestand (.pwvx of recordmap) bij voor het
/// Metrel-scherm.
class MetrelProvider extends ChangeNotifier {
  List<MetrelRecord> records = const [];
  int selectedIndex = 0;
  String? path;
  bool isLoading = false;
  String? error;

  MetrelRecord? get selected =>
      records.isEmpty ? null : records[selectedIndex];

  Future<void> open(String path) async {
    isLoading = true;
    error = null;
    notifyListeners();

    try {
      final catalog = await MetrelCatalog.load();
      records = await MetrelRecordReader(catalog).open(path);
      selectedIndex = 0;
      this.path = path;
    } catch (e) {
      error = e.toString();
      records = const [];
      this.path = null;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  void select(int index) {
    if (index == selectedIndex || index < 0 || index >= records.length) return;
    selectedIndex = index;
    notifyListeners();
  }

  void clearError() {
    error = null;
    notifyListeners();
  }

  /// Sessie voor de analyseschermen op basis van het geselecteerde record.
  MeasurementSession? sessionForSelected() {
    final r = selected;
    return r == null ? null : MetrelPwvxParser.sessionFromRecord(r);
  }
}
