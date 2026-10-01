import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Bestands- en mapkiezers die per soort de laatst gebruikte locatie
/// onthouden (ook na herstart van de app).
enum PickerLocation {
  /// Meetbestanden en -mappen, standaarden-Excel.
  import('last_import_directory'),

  /// Logo's en afbeeldingen bij notities.
  afbeelding('last_image_directory'),

  /// Opslaan van rapporten en exports.
  opslaan('last_save_directory'),

  /// Bronmap PQBox (USB-schijf).
  pqboxBron('last_pqbox_source_directory'),

  /// Lokale doelmap PQBox-download.
  pqboxDoel('last_pqbox_destination_directory');

  const PickerLocation(this.prefsKey);
  final String prefsKey;
}

Future<String?> _lastDirectory(PickerLocation location) async {
  final prefs = await SharedPreferences.getInstance();
  final dir = prefs.getString(location.prefsKey);
  if (dir == null || !Directory(dir).existsSync()) return null;
  return dir;
}

Future<void> _rememberDirectory(PickerLocation location, String dir) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(location.prefsKey, dir);
}

/// Kiest één of meer bestanden en onthoudt de map waarin ze staan.
Future<FilePickerResult?> pickImportFiles({
  String? dialogTitle,
  FileType type = FileType.any,
  List<String>? allowedExtensions,
  bool allowMultiple = false,
  PickerLocation location = PickerLocation.import,
}) async {
  final result = await FilePicker.platform.pickFiles(
    dialogTitle: dialogTitle,
    type: type,
    allowedExtensions: allowedExtensions,
    allowMultiple: allowMultiple,
    initialDirectory: await _lastDirectory(location),
  );
  final first = result?.files.firstOrNull?.path;
  if (first != null) await _rememberDirectory(location, File(first).parent.path);
  return result;
}

/// Kiest één bestand en geeft het pad terug.
Future<String?> pickImportFile({
  String? dialogTitle,
  FileType type = FileType.any,
  List<String>? allowedExtensions,
  PickerLocation location = PickerLocation.import,
}) async {
  final result = await pickImportFiles(
    dialogTitle: dialogTitle,
    type: type,
    allowedExtensions: allowedExtensions,
    location: location,
  );
  return result?.files.single.path;
}

/// Kiest een map. Standaard wordt de bovenliggende map onthouden, zodat de
/// volgende keer direct een naastgelegen meetmap gekozen kan worden; met
/// [rememberParent] = false wordt de gekozen map zelf onthouden.
Future<String?> pickImportFolder({
  String? dialogTitle,
  PickerLocation location = PickerLocation.import,
  bool rememberParent = true,
}) async {
  final path = await FilePicker.platform.getDirectoryPath(
    dialogTitle: dialogTitle,
    initialDirectory: await _lastDirectory(location),
  );
  if (path != null) {
    await _rememberDirectory(
        location, rememberParent ? Directory(path).parent.path : path);
  }
  return path;
}

/// Opslaan-dialoog die opent in de map van de vorige opslag.
Future<String?> pickSaveFile({
  String? dialogTitle,
  String? fileName,
  FileType type = FileType.any,
  List<String>? allowedExtensions,
}) async {
  final path = await FilePicker.platform.saveFile(
    dialogTitle: dialogTitle,
    fileName: fileName,
    type: type,
    allowedExtensions: allowedExtensions,
    initialDirectory: await _lastDirectory(PickerLocation.opslaan),
  );
  if (path != null) {
    await _rememberDirectory(PickerLocation.opslaan, File(path).parent.path);
  }
  return path;
}
