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

const _targetCount = 30;
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

/// 从分集列表中找出窗口内新入库的分集，返回对应剧集 ID 集合。
Set<String> _recentEpisodeSeriesIds(
  List<EmbyMediaItem> episodes,
  Duration recentWindow,
) {
  final ids = <String>{};
  for (final item in episodes) {
    if (item.type != 'Episode') continue;
    if (!item.isRecentlyAdded(recentWindow)) continue;
    final sid = item.seriesId?.trim();
    if (sid != null && sid.isNotEmpty) ids.add(sid);
  }
  return ids;
}

/// 将 [display] 标记为「有新分集入库」。
EmbyMediaItem _markSeriesRecentlyAdded(EmbyMediaItem display) {
  return EmbyMediaItem(
    id: display.id,
    name: display.name,
    type: display.type,
    overview: display.overview,
    runTimeTicks: display.runTimeTicks,
    productionYear: display.productionYear,
    seriesName: display.seriesName,
    seasonName: display.seasonName,
    parentIndexNumber: display.parentIndexNumber,
    indexNumber: display.indexNumber,
    primaryImageTag: display.primaryImageTag,
    primaryImageItemId: display.primaryImageItemId,
    parentThumbItemId: display.parentThumbItemId,
    parentThumbImageTag: display.parentThumbImageTag,
    seriesPrimaryImageTag: display.seriesPrimaryImageTag,
    logoImageTag: display.logoImageTag,
    backdropImageTags: display.backdropImageTags,
    seriesId: display.seriesId,
    seasonId: display.seasonId,
    userDataPlayedPercentage: display.userDataPlayedPercentage,
    userDataPlayed: display.userDataPlayed,
    userDataPlaybackPositionTicks: display.userDataPlaybackPositionTicks,
    productionLocations: display.productionLocations,
    communityRating: display.communityRating,
    lastPlayedDate: display.lastPlayedDate,
    dateCreated: display.dateCreated,
    hasRecentlyAddedEpisode: true,
    people: display.people,
    genres: display.genres,
    videoCodec: display.videoCodec,
    videoRange: display.videoRange,
    audioCodec: display.audioCodec,
    isAtmos: display.isAtmos,
    videoHeight: display.videoHeight,
    videoWidth: display.videoWidth,
  );
}

List<EmbyMediaItem> _mergeRecommendItems(
  List<EmbyMediaItem> raw,
  Set<String> excludeKeys,
  Duration recentWindow, {
  Set<String> recentSeriesIds = const {},
}) {
  final seen = <String>{};
  final out = <EmbyMediaItem>[];
  for (final item in raw) {
    if (!_isRecommendableType(item.type)) continue;
    var display = item.toRecommendDisplayItem();
    if (display.type == 'Series' && recentSeriesIds.contains(display.id)) {
      display = _markSeriesRecentlyAdded(display);
    }
    final key = display.recommendDedupKey;
    if (excludeKeys.contains(key) || excludeKeys.contains('item:${display.id}')) {
      continue;
    }
    if (!seen.add(key)) continue;
    out.add(display);
  }
  // 优先最近入库：窗口内按入库时间倒序，其余按评分倒序补位。
  out.sort((a, b) => _recommendPriorityCompare(a, b, recentWindow));
  if (out.length > _targetCount) out.removeRange(_targetCount, out.length);
  return out;
}

/// 推荐排序：最近入库优先（按 [EmbyMediaItem.dateCreated] 倒序），其次按社区评分倒序。
int _recommendPriorityCompare(
  EmbyMediaItem a,
  EmbyMediaItem b,
  Duration recentWindow,
) {
  final aRecent = a.isRecentlyAdded(recentWindow);
  final bRecent = b.isRecentlyAdded(recentWindow);
  if (aRecent != bRecent) return aRecent ? -1 : 1;
  if (aRecent) {
    final da = a.dateCreated;
    final db = b.dateCreated;
    if (da != null && db != null) return db.compareTo(da);
    if (da != null) return -1;
    if (db != null) return 1;
    return 0;
  }
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
    final recentWindow = Duration(
      days: ref.read(settingsServiceProvider).recentAddedWindowDays,
    );
    final emby = ref.read(embyServiceProvider);

    // 预取最近入库的分集，建立「有新集数的剧集」集合；这是识别老剧新集的关键。
    Set<String> recentSeriesIds = {};
    try {
      final latestEpisodes = await emby.getLatestEpisodes(limit: 50);
      recentSeriesIds = _recentEpisodeSeriesIds(latestEpisodes, recentWindow);
    } catch (_) {}

    List<EmbyMediaItem> collected = [];

    // Phase 1 — fast path (usually warm from home Latest).
    try {
      final latest = await ref.read(embyLatestProvider.future);
      final quick = _mergeRecommendItems(
        latest,
        exclude,
        recentWindow,
        recentSeriesIds: recentSeriesIds,
      );
      if (quick.isNotEmpty) {
        state = AsyncData(quick);
        if (quick.length >= _targetCount) {
          return quick;
        }
      }
    } catch (_) {}

    // Phase 2 — personalized similar items.
    final seeds = await _recommendSeeds(ref);
    if (seeds.isNotEmpty) {
      final similarBatches = await Future.wait(
        seeds.map((id) => emby.getSimilarItems(id, limit: _similarPerSeed)),
      );
      for (final batch in similarBatches) {
        collected.addAll(batch);
      }
    }

    var result = _mergeRecommendItems(
      collected,
      exclude,
      recentWindow,
      recentSeriesIds: recentSeriesIds,
    );

    if (result.length < _targetCount) {
      try {
        final latest = await ref.read(embyLatestProvider.future);
        collected = [...collected, ...latest];
        result = _mergeRecommendItems(
          collected,
          exclude,
          recentWindow,
          recentSeriesIds: recentSeriesIds,
        );
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
