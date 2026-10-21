class LeagueModel {
  final String id;
  final int sportId;
  final String name;
  final String country;
  final String category;
  final int matchCount;

  const LeagueModel({
    required this.id,
    required this.sportId,
    required this.name,
    required this.country,
    required this.category,
    required this.matchCount,
  });

  factory LeagueModel.fromJson(Map<String, dynamic> json) {
    return LeagueModel(
      id: json['id']?.toString() ?? '',
      sportId: (json['sport_id'] as num?)?.toInt() ??
          int.tryParse(json['sport_id']?.toString() ?? '') ??
          0,
      name: json['name']?.toString() ?? '',
      country: json['country']?.toString() ?? '',
      category: json['category']?.toString() ?? '',
      matchCount: (json['match_count'] as num?)?.toInt() ??
          int.tryParse(json['match_count']?.toString() ?? '') ??
          0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sport_id': sportId,
      'name': name,
      'country': country,
      'category': category,
      'match_count': matchCount,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LeagueModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          sportId == other.sportId &&
          name == other.name &&
          country == other.country &&
          category == other.category &&
          matchCount == other.matchCount;

  @override
  int get hashCode =>
      id.hashCode ^
      sportId.hashCode ^
      name.hashCode ^
      country.hashCode ^
      category.hashCode ^
      matchCount.hashCode;
}
