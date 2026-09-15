class Bedrijfsgegevens {
  final String id;
  final String naam;
  final String adres;
  final String postcodePlaats;
  final String telefoon;
  final String email;
  final String contactpersoon;

  /// Base64-encoded logo image bytes, or null when no logo is set.
  final String? logoBase64;

  const Bedrijfsgegevens({
    required this.id,
    required this.naam,
    required this.adres,
    required this.postcodePlaats,
    required this.telefoon,
    required this.email,
    required this.contactpersoon,
    this.logoBase64,
  });

  Bedrijfsgegevens copyWith({
    String? naam,
    String? adres,
    String? postcodePlaats,
    String? telefoon,
    String? email,
    String? contactpersoon,
    String? logoBase64,
    bool clearLogo = false,
  }) =>
      Bedrijfsgegevens(
        id: id,
        naam: naam ?? this.naam,
        adres: adres ?? this.adres,
        postcodePlaats: postcodePlaats ?? this.postcodePlaats,
        telefoon: telefoon ?? this.telefoon,
        email: email ?? this.email,
        contactpersoon: contactpersoon ?? this.contactpersoon,
        logoBase64: clearLogo ? null : (logoBase64 ?? this.logoBase64),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'naam': naam,
        'adres': adres,
        'postcodePlaats': postcodePlaats,
        'telefoon': telefoon,
        'email': email,
        'contactpersoon': contactpersoon,
        'logoBase64': logoBase64,
      };

  factory Bedrijfsgegevens.fromJson(Map<String, dynamic> json) => Bedrijfsgegevens(
        id: json['id'] as String,
        naam: json['naam'] as String,
        adres: json['adres'] as String,
        postcodePlaats: json['postcodePlaats'] as String,
        telefoon: json['telefoon'] as String,
        email: json['email'] as String,
        contactpersoon: json['contactpersoon'] as String,
        logoBase64: json['logoBase64'] as String?,
      );
}
