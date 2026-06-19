import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/emby/emby_library.dart';
import '../models/emby/emby_media_item.dart';
import '../models/emby/emby_person.dart';
import '../models/emby/emby_search_result.dart';
import 'settings_provider.dart';

final embyLibrariesProvider = FutureProvider<List<EmbyLibrary>>((ref) {
  return ref.watch(embyServiceProvider).getUserViews();
});

final embyLatestProvider = FutureProvider<List<EmbyMediaItem>>((ref) {
  return ref.watch(embyServiceProvider).getLatest();
});

final embyResumeProvider = FutureProvider<List<EmbyMediaItem>>((ref) {
  final limit = ref.watch(settingsServiceProvider).homeRecentPlayLimit;
  return ref.watch(embyServiceProvider).getResume(limit: limit);
});

/// Browses a library folder, or with [includeItemTypes] set applies the same
/// Emby/Jellyfin query as emby_client `movies.vue` / `tv.vue` (recursive + type filter).
typedef EmbyLibraryListArg = ({
  String parentId,
  String? includeItemTypes,
  bool recursive,
  int limit,
  String? sortBy,
  String? sortOrder,
  String? searchTerm,
});

final embyLibraryItemsProvider = FutureProvider.family<List<EmbyMediaItem>, EmbyLibraryListArg>((ref, arg) {
  return ref.watch(embyServiceProvider).getItems(
        parentId: arg.parentId,
        includeItemTypes: arg.includeItemTypes,
        recursive: arg.recursive,
        limit: arg.limit,
        sortBy: arg.sortBy,
        sortOrder: arg.sortOrder,
        searchTerm: arg.searchTerm,
      );
});

final embyLibraryCategoryCoverProvider = FutureProvider.family<EmbyMediaItem?, String>((ref, parentId) {
  return ref.watch(embyServiceProvider).getLibraryCategoryCoverItem(parentId);
});

final embyItemProvider = FutureProvider.family<EmbyMediaItem, String>((ref, id) {
  return ref.watch(embyServiceProvider).getItem(id);
});

final embyEpisodesProvider = FutureProvider.family<List<EmbyMediaItem>, String>((ref, seasonId) {
  return ref.watch(embyServiceProvider).getEpisodes(seasonId);
});

final embySeasonsProvider = FutureProvider.family<List<EmbyMediaItem>, String>((ref, seriesId) {
  return ref.watch(embyServiceProvider).getSeasons(seriesId);
});

/// "Next Up" episode for a given series (Emby /Shows/NextUp?SeriesId=…).
final embyNextUpForSeriesProvider = FutureProvider.family<EmbyMediaItem?, String>((ref, seriesId) {
  return ref.watch(embyServiceProvider).getNextUpForSeries(seriesId);
});

final embySearchProvider = FutureProvider.family<List<EmbySearchHint>, String>((ref, q) {
  if (q.trim().isEmpty) return Future.value([]);
  return ref.watch(embyServiceProvider).searchHints(q.trim());
});

final embyItemPeopleProvider = FutureProvider.family<List<EmbyPerson>, String>((ref, itemId) {
  return ref.watch(embyServiceProvider).getItemPeople(itemId);
});

final embySimilarItemsProvider = FutureProvider.family<List<EmbyMediaItem>, String>((ref, itemId) {
  return ref.watch(embyServiceProvider).getSimilarItems(itemId);
});
