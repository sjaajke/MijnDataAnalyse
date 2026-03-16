import 'package:flutter/foundation.dart';
import '../models/measurement_data.dart';
import '../services/fpqo_parser.dart';
import '../services/measurement_loader.dart';

class MeasurementProvider extends ChangeNotifier {
  final MeasurementLoader _loader = MeasurementLoader();
  final FpqoParser _fpqoParser = FpqoParser();

  final List<MeasurementSession?> sessions = [null, null, null];
  final List<bool> slotsLoading = [false, false, false];
  final List<String?> slotPaths = [null, null, null];
  String? error;

  /// Primary session (slot 0) — used by all existing screens.
  MeasurementSession? get session => sessions[0];

  /// Path of the folder/file loaded into slot 0.
  String? get sessionPath => slotPaths[0];

  bool get isLoading => slotsLoading.any((l) => l);

  void clearError() {
    error = null;
    notifyListeners();
  }

  void clearSlot(int slot) {
    sessions[slot] = null;
    slotPaths[slot] = null;
    notifyListeners();
  }

  /// Loads a folder into slot 0 (backward-compatible).
  Future<void> loadFolder(String path) => loadSlot(0, path);

  /// Loads a single .fpqo file into slot 0.
  Future<void> loadFpqoFile(String path) async {
    slotsLoading[0] = true;
    error = null;
    notifyListeners();

    try {
      sessions[0] = await _fpqoParser.parseFile(path);
      slotPaths[0] = path;
    } catch (e) {
      error = e.toString();
      sessions[0] = null;
      slotPaths[0] = null;
    } finally {
      slotsLoading[0] = false;
      notifyListeners();
    }
  }

  Future<void> loadSlot(int slot, String path) async {
    slotsLoading[slot] = true;
    error = null;
    notifyListeners();

    try {
      sessions[slot] = await _loader.loadFolder(path);
      slotPaths[slot] = path;
    } catch (e) {
      error = e.toString();
      sessions[slot] = null;
      slotPaths[slot] = null;
    } finally {
      slotsLoading[slot] = false;
      notifyListeners();
    }
  }
}
