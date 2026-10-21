class SportModel {
  final int id;
  final String name;
  final String key;
  final String slug;
  final bool active;
  final int matchCount;
  final String iconUrl;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const SportModel({
    required this.id,
    required this.name,
    required this.key,
    required this.slug,
    required this.active,
    this.matchCount = 0,
    this.iconUrl = '',
    this.createdAt,
    this.updatedAt,
  });

  factory SportModel.fromJson(Map<String, dynamic> json) {
    final keyVal = json['key'] as String? ?? json['slug'] as String? ?? '';
    final slugVal = json['slug'] as String? ?? json['key'] as String? ?? '';
    final activeVal = json['is_active'] as bool? ?? json['active'] as bool? ?? true;
    final matchCountVal = json['match_count'] is num
        ? (json['match_count'] as num).toInt()
        : int.tryParse(json['match_count']?.toString() ?? '') ?? 0;

    return SportModel(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      key: keyVal,
      slug: slugVal,
      active: activeVal,
      matchCount: matchCountVal,
      iconUrl: json['icon_url'] as String? ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'key': key,
      'slug': slug,
      'is_active': active,
      'active': active,
      'match_count': matchCount,
      'icon_url': iconUrl,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SportModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          key == other.key &&
          active == other.active;

  @override
  int get hashCode =>
      id.hashCode ^ name.hashCode ^ key.hashCode ^ active.hashCode;
}
