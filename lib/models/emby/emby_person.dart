/// Emby `BaseItemPerson` subset: one cast/crew member attached to a media item.
class EmbyPerson {
  const EmbyPerson({
    required this.id,
    required this.name,
    this.role,
    this.type,
    this.primaryImageTag,
  });

  final String id;
  final String name;
  final String? role;
  final String? type; // Actor, Director, Writer, etc.
  final String? primaryImageTag;

  String get displayLabel {
    if (role != null && role!.isNotEmpty) return '$name · $role';
    return name;
  }

  bool get isActor => type == null || type == 'Actor' || type!.toLowerCase().contains('actor');

  factory EmbyPerson.fromJson(Map<String, dynamic> json) {
    return EmbyPerson(
      id: json['Id']?.toString() ?? json['id']?.toString() ?? '',
      name: json['Name']?.toString() ?? json['name']?.toString() ?? '',
      role: json['Role']?.toString() ?? json['role']?.toString(),
      type: json['Type']?.toString() ?? json['type']?.toString(),
      primaryImageTag: json['PrimaryImageTag']?.toString() ??
          (json['ImageTags'] is Map
              ? (json['ImageTags'] as Map)['Primary']?.toString()
              : null),
    );
  }
}