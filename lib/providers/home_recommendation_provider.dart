import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/emby/emby_media_item.dart';
import 'emby_provider.dart';
import 'settings_provider.dart';

enum HomeRecommendationFilter { all, series, movie }

/// Home recommend filter labels — shared across mobile, desktop, and TV.
String homeRecommendationFilterLabel(HomeRecommendationFilter filter) {
  switch (filter) {
    case HomeRecommendationFilter.all:
      return '全部';
    case HomeRecommendationFilter.series:
      return '剧集';
    case HomeRecommendationFilter.movie:
      return '电影';
  }
}

const _targetCount = 12;
const _maxSeeds = 5;
const _similarPerSeed = 8;

List<EmbyMediaItem> filterHomeRecommendations(
  List<EmbyMediaItem> items,
  HomeRecommendationFilter filter,
) {
  switch (filter) {
    case HomeRecommendationFilter.series:
      return items.where((m) => m.type == 'Series').toList();
    case HomeRecommendationFilter.movie:
      return items.where((m) => m.type == 'Movie' || m.type == 'Video').toList();
    case HomeRecommendationFilter.all:
      return items;
  }
}

bool _isRecommendableType(String type) =>
    type == 'Series' || type == 'Movie' || type == 'Video' || type == 'Episode';

Set<String> _resumeExcludeKeys(List<EmbyMediaItem> resume) {
  final keys = <String>{};
  for (final m in resume) {
    keys.add(m.recommendDedupKey);
    keys.add('item:${m.id}');
  }
  return keys;
}

List<EmbyMediaItem> _mergeRecommendItems(
  List<EmbyMediaItem> raw,
  Set<String> excludeKeys,
) {
  final seen = <String>{};
  final out = <EmbyMediaItem>[];
  for (final item in raw) {
    if (!_isRecommendableType(item.type)) continue;
    final display = item.toRecommendDisplayItem();
    final key = display.recommendDedupKey;
    if (excludeKeys.contains(key) || excludeKeys.contains('item:${display.id}')) {
      continue;
    }
    if (!seen.add(key)) continue;
    out.add(display);
    if (out.length >= _targetCount) break;
  }
  return out;
}

int _ratingSort(EmbyMediaItem a, EmbyMediaItem b) {
  final ra = a.communityRating ?? 0;
  final rb = b.communityRating ?? 0;
  return rb.compareTo(ra);
}

Future<Set<String>> _recommendExcludeKeys(Ref ref) async {
  final resume = await ref.watch(embyResumeProvider.future);
  return _resumeExcludeKeys(resume);
}

Future<List<String>> _recommendSeeds(Ref ref) async {
  final history = ref.watch(playHistoryServiceProvider);
  var seeds = history.recentMediaLevelIds(limit: _maxSeeds);
  if (seeds.isNotEmpty) return seeds;

  final resume = await ref.watch(embyResumeProvider.future);
  return [
    for (final m in resume.take(3))
      if (m.type == 'Episode')
        (m.seriesId?.trim().isNotEmpty == true ? m.seriesId! : m.id)
      else
        m.id,
  ];
}

/// Progressive load: [embyLatest] first, then similar-items merge in background.
class HomeRecommendationNotifier extends AsyncNotifier<List<EmbyMediaItem>> {
  @override
  Future<List<EmbyMediaItem>> build() => _load();

  Future<List<EmbyMediaItem>> _load() async {
    final exclude = await _recommendExcludeKeys(ref);
    List<EmbyMediaItem> collected = [];

    // Phase 1 — fast path (usually warm from home Latest).
    try {
      final latest = await ref.read(embyLatestProvider.future);
      final fallback = [...latest]..sort(_ratingSort);
      final quick = _mergeRecommendItems(fallback, exclude);
      if (quick.isNotEmpty) {
        state = AsyncData(quick);
        if (quick.length >= _targetCount) {
          return quick;
        }
      }
    } catch (_) {}

    // Phase 2 — personalized similar items.
    final emby = ref.read(embyServiceProvider);
    final seeds = await _recommendSeeds(ref);
    if (seeds.isNotEmpty) {
      final similarBatches = await Future.wait(
        seeds.map((id) => emby.getSimilarItems(id, limit: _similarPerSeed)),
      );
      for (final batch in similarBatches) {
        collected.addAll(batch);
      }
    }

    var result = _mergeRecommendItems(collected, exclude);

    if (result.length < _targetCount) {
      try {
        final latest = await ref.read(embyLatestProvider.future);
        final fallback = [...latest]..sort(_ratingSort);
        collected = [...collected, ...fallback];
        result = _mergeRecommendItems(collected, exclude);
      } catch (_) {}
    }

    return result;
  }
}

final homeRecommendationProvider =
    AsyncNotifierProvider<HomeRecommendationNotifier, List<EmbyMediaItem>>(
  HomeRecommendationNotifier.new,
);

final homeRecommendationFilteredProvider = Provider.family<
    AsyncValue<List<EmbyMediaItem>>,
    HomeRecommendationFilter>((ref, filter) {
  final all = ref.watch(homeRecommendationProvider);
  return all.whenData((items) => filterHomeRecommendations(items, filter));
});
