/// A top-level view (e.g. Movies, TV Shows library root).
class EmbyLibrary {
  const EmbyLibrary({
    required this.id,
    required this.name,
    required this.collectionType,
  });

  final String id;
  final String name;

  /// Emby `CollectionType`: movies, tvshows, mixed, etc.
  final String? collectionType;

  factory EmbyLibrary.fromJson(Map<String, dynamic> json) {
    return EmbyLibrary(
      id: json['Id'] as String? ?? '',
      name: json['Name'] as String? ?? '',
      collectionType: json['CollectionType'] as String?,
    );
  }
}
