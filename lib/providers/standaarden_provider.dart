import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/standaard.dart';

class StandaardenProvider extends ChangeNotifier {
  static const _prefsKey = 'standaarden';

  final List<Standaard> _standaarden = [];
  bool _loaded = false;

  List<Standaard> get standaarden => List.unmodifiable(_standaarden);
  bool get isLoaded => _loaded;

  StandaardenProvider() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      final list = jsonDecode(raw) as List<dynamic>;
      _standaarden
        ..clear()
        ..addAll(list.map((e) => Standaard.fromJson(e as Map<String, dynamic>)));
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(_standaarden.map((s) => s.toJson()).toList()),
    );
  }

  Future<void> addStandaard(String titel, String tekst) async {
    _standaarden.add(Standaard(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      titel: titel,
      tekst: tekst,
    ));
    notifyListeners();
    await _save();
  }

  Future<void> updateStandaard(String id, String titel, String tekst) async {
    final index = _standaarden.indexWhere((s) => s.id == id);
    if (index == -1) return;
    _standaarden[index] = _standaarden[index].copyWith(titel: titel, tekst: tekst);
    notifyListeners();
    await _save();
  }

  Future<void> removeStandaard(String id) async {
    _standaarden.removeWhere((s) => s.id == id);
    notifyListeners();
    await _save();
  }
}
