import 'dart:convert';

import 'emby/emby_library.dart';

/// Main home grid: type / recency; [year] maps to Emby `Years`; [region] is refined client-side.
enum HomeBrowseKind { all, recentlyPlayed, movies, tvShows }

enum HomeRegionFilter { none, mandarin, western, korea, japan }

typedef HomeBrowseQuery = ({
  List<String> seedParentIds,
  HomeBrowseKind kind,
  int? year,
  HomeRegionFilter region,
  String searchTerm,
});

List<String> seedParentIdsFromLibraries(List<EmbyLibrary> libs) {
  final seen = <String>{};
  final out = <String>[];
  for (final l in libs) {
    final c = l.collectionType?.toLowerCase() ?? '';
    if (c == 'movies' || c == 'tvshows' || c == 'mixed') {
      if (seen.add(l.id)) out.add(l.id);
    }
  }
  if (out.isEmpty) {
    return libs.map((l) => l.id).toList();
  }
  return out;
}

/// Stable cache key for merged home-browse queries (Riverpod `family` + [List] records can re-fetch every frame).
String encodeHomeBrowseQuery(HomeBrowseQuery q) {
  final seeds = [...q.seedParentIds.toSet()]..sort();
  return jsonEncode({
    's': seeds,
    'k': q.kind.name,
    'y': q.year,
    'r': q.region.name,
    't': q.searchTerm,
  });
}

HomeBrowseQuery decodeHomeBrowseQuery(String key) {
  final m = jsonDecode(key) as Map<String, dynamic>;
  final seeds = (m['s'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? <String>[];
  return (
    seedParentIds: seeds,
    kind: HomeBrowseKind.values.byName(m['k'] as String),
    year: (m['y'] as num?)?.toInt(),
    region: HomeRegionFilter.values.byName(m['r'] as String),
    searchTerm: m['t'] as String? ?? '',
  );
}
