import '../models/emby/emby_library.dart';
import '../models/emby/emby_media_item.dart';

class LibraryScope {
  const LibraryScope({
    required this.pickerLibraries,
    required this.selectedId,
    required this.selectedParentId,
    required this.allItems,
  });

  static const allId = '__all__';

  final List<EmbyLibrary> pickerLibraries;
  final String selectedId;
  final String? selectedParentId;
  final List<EmbyMediaItem>? allItems;
}

/// Picks the active top-level library for browse panes.
EmbyLibrary? resolveBrowseRoot(
  List<EmbyLibrary> libraries, {
  String? selectedLibraryId,
}) {
  if (libraries.isEmpty) return null;
  if (selectedLibraryId != null) {
    for (final lib in libraries) {
      if (lib.id == selectedLibraryId) return lib;
    }
  }
  return libraries.first;
}

/// Keeps [selectedLibraryId] valid when the server library list changes.
String? normalizeSelectedLibraryId(
  List<EmbyLibrary> libraries,
  String? selectedLibraryId,
) {
  if (libraries.isEmpty) return null;
  if (selectedLibraryId != null &&
      libraries.any((l) => l.id == selectedLibraryId)) {
    return selectedLibraryId;
  }
  return libraries.first.id;
}

/// Builds a browse scope with an optional synthetic "all" root.
LibraryScope buildLibraryScope({
  required List<EmbyLibrary> libraries,
  required String? selectedLibraryId,
  required String allLabel,
  Set<String>? collectionTypes,
  bool includeAll = false,
}) {
  final filtered = collectionTypes == null
      ? libraries
      : libraries
          .where(
              (lib) => collectionTypes.contains(_normalizeCollectionType(lib)))
          .toList(growable: false);
  final visible = filtered.isEmpty ? libraries : filtered;

  if (visible.isEmpty) {
    return const LibraryScope(
      pickerLibraries: [],
      selectedId: LibraryScope.allId,
      selectedParentId: null,
      allItems: null,
    );
  }

  final selectedIsVisible = selectedLibraryId != null &&
      visible.any((lib) => lib.id == selectedLibraryId);
  final selectedId = includeAll
      ? (selectedIsVisible ? selectedLibraryId : LibraryScope.allId)
      : (selectedIsVisible ? selectedLibraryId : visible.first.id);
  final selectedParentId = selectedId == LibraryScope.allId ? null : selectedId;
  final pickerLibraries = includeAll
      ? [
          EmbyLibrary(
            id: LibraryScope.allId,
            name: allLabel,
            collectionType: null,
          ),
          ...visible,
        ]
      : visible;

  return LibraryScope(
    pickerLibraries: pickerLibraries,
    selectedId: selectedId,
    selectedParentId: selectedParentId,
    allItems: selectedId == LibraryScope.allId
        ? visible
            .map(
              (lib) => EmbyMediaItem(
                id: lib.id,
                name: lib.name,
                type: 'CollectionFolder',
              ),
            )
            .toList(growable: false)
        : null,
  );
}

String? _normalizeCollectionType(EmbyLibrary library) {
  final raw = library.collectionType?.trim().toLowerCase();
  if (raw == null || raw.isEmpty) return null;
  return raw;
}
