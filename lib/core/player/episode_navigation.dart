import '../../models/emby/emby_media_item.dart';

/// Sort episodes by [EmbyMediaItem.indexNumber] ascending (matches detail page).
List<EmbyMediaItem> sortEpisodesByIndex(List<EmbyMediaItem> raw) {
  final list = [...raw];
  list.sort(
    (a, b) => (a.indexNumber ?? 1 << 20).compareTo(b.indexNumber ?? 1 << 20),
  );
  return list;
}

/// Previous / next episode within a sorted season list (same season only).
({EmbyMediaItem? previous, EmbyMediaItem? next}) adjacentEpisodesInSeason(
  List<EmbyMediaItem> sorted,
  String currentId,
) {
  final idx = sorted.indexWhere((e) => e.id == currentId);
  if (idx < 0) return (previous: null, next: null);
  return (
    previous: idx > 0 ? sorted[idx - 1] : null,
    next: idx < sorted.length - 1 ? sorted[idx + 1] : null,
  );
}
