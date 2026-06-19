import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/emby/emby_media_item.dart';
import 'emby_provider.dart';

enum RecentPlayFilter { all, series, movie }

List<EmbyMediaItem> filterRecentPlayItems(
  List<EmbyMediaItem> items,
  RecentPlayFilter filter,
) {
  switch (filter) {
    case RecentPlayFilter.series:
      return items.where((m) => m.isRecentPlaySeriesItem).toList();
    case RecentPlayFilter.movie:
      return items.where((m) => m.isRecentPlayMovieItem).toList();
    case RecentPlayFilter.all:
      return items;
  }
}

final recentPlayFilteredProvider =
    Provider.family<AsyncValue<List<EmbyMediaItem>>, RecentPlayFilter>((ref, filter) {
  return ref.watch(embyResumeProvider).whenData(
        (items) => filterRecentPlayItems(items, filter),
      );
});
