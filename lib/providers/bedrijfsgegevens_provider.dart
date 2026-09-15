import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/bedrijfsgegevens.dart';

class BedrijfsgegevensProvider extends ChangeNotifier {
  static const _prefsKey = 'bedrijfsgegevens';

  final List<Bedrijfsgegevens> _bedrijven = [];
  bool _loaded = false;

  List<Bedrijfsgegevens> get bedrijven => List.unmodifiable(_bedrijven);
  bool get isLoaded => _loaded;

  BedrijfsgegevensProvider() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      final list = jsonDecode(raw) as List<dynamic>;
      _bedrijven
        ..clear()
        ..addAll(list.map((e) => Bedrijfsgegevens.fromJson(e as Map<String, dynamic>)));
    } else {
      // Eerste keer openen: vul een startvoorbeeld in.
      _bedrijven.add(const Bedrijfsgegevens(
        id: 'epm-default',
        naam: 'EPM',
        adres: 'Business Park Stein 408',
        postcodePlaats: '6181 MD Elsloo',
        telefoon: '043-364 28 23',
        email: 'Inspectie@epm.nl',
        contactpersoon: 'Vivianne Feron',
      ));
      await _save();
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(_bedrijven.map((b) => b.toJson()).toList()),
    );
  }

  Future<void> addBedrijf(Bedrijfsgegevens bedrijf) async {
    _bedrijven.add(bedrijf);
    notifyListeners();
    await _save();
  }

  Future<void> updateBedrijf(Bedrijfsgegevens bedrijf) async {
    final index = _bedrijven.indexWhere((b) => b.id == bedrijf.id);
    if (index == -1) return;
    _bedrijven[index] = bedrijf;
    notifyListeners();
    await _save();
  }

  Future<void> removeBedrijf(String id) async {
    _bedrijven.removeWhere((b) => b.id == id);
    notifyListeners();
    await _save();
  }
}
