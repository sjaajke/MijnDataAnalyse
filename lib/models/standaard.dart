class Standaard {
  final String id;
  final String titel;
  final String tekst;

  const Standaard({
    required this.id,
    required this.titel,
    required this.tekst,
  });

  Standaard copyWith({String? titel, String? tekst}) => Standaard(
        id: id,
        titel: titel ?? this.titel,
        tekst: tekst ?? this.tekst,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'titel': titel,
        'tekst': tekst,
      };

  factory Standaard.fromJson(Map<String, dynamic> json) => Standaard(
        id: json['id'] as String,
        titel: json['titel'] as String,
        tekst: json['tekst'] as String,
      );
}
