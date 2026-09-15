import 'dart:convert';

import 'package:pdf/widgets.dart' as pw;

import '../models/bedrijfsgegevens.dart';

/// Returns the logo configured in Standaarden -> Bedrijfsgegevens (the first
/// company entry), or null when there is no company or no logo has been set.
pw.ImageProvider? loadCompanyLogo(List<Bedrijfsgegevens> bedrijven) {
  if (bedrijven.isEmpty) return null;
  final base64 = bedrijven.first.logoBase64;
  if (base64 == null || base64.isEmpty) return null;
  return pw.MemoryImage(base64Decode(base64));
}
