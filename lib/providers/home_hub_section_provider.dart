import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/emby/emby_library.dart';
import '../models/emby/emby_media_item.dart';
import '../models/home_browse.dart';
import 'emby_provider.dart';
import 'settings_provider.dart';

/// Order view roots so the active [section] hits the right collection first.
List<String> orderedSeedIdsForHomeSection(List<EmbyLibrary> libs, List<String> seedIds, String section) {
  final byId = {for (final l in libs) l.id: l};
  int rank(String id) {
    final l = byId[id];
    final c = l?.collectionType?.toLowerCase() ?? '';
    if (section == 'movie') {
      if (c == 'movies') return 0;
      if (c == 'mixed') return 1;
      if (c == 'tvshows') return 2;
    } else if (section == 'series') {
      if (c == 'tvshows') return 0;
      if (c == 'mixed') return 1;
      if (c == 'movies') return 2;
    }
    return 3;
  }

  final ids = [...seedIds];
  ids.sort((a, b) => rank(a).compareTo(rank(b)));
  return ids;
}

@immutable
class HomeHubSectionListState {
  const HomeHubSectionListState({
    this.items = const [],
    this.hasMore = true,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.error,
  });

  final List<EmbyMediaItem> items;
  final bool hasMore;
  final bool isLoading;
  final bool isLoadingMore;
  final Object? error;

  HomeHubSectionListState copyWith({
    List<EmbyMediaItem>? items,
    bool? hasMore,
    bool? isLoading,
    bool? isLoadingMore,
    Object? error = _sentinel,
  }) {
    return HomeHubSectionListState(
      items: items ?? this.items,
      hasMore: hasMore ?? this.hasMore,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: identical(error, _sentinel) ? this.error : error,
    );
  }

  static const _sentinel = Object();
}

class HomeHubSectionListNotifier extends Notifier<HomeHubSectionListState> {
  HomeHubSectionListNotifier(this.section);

  static const _pageSize = 48;
  static const _prefetchMinItems = 36;
  static const _prefetchMaxExtraPages = 4;

  final String section;
  final Set<String> _seen = {};
  List<String> _orderedSeeds = [];
  int _libIndex = 0;
  int _startIndex = 0;

  @override
  HomeHubSectionListState build() {
    Future.microtask(refresh);
    return const HomeHubSectionListState(isLoading: true);
  }

  Future<void> refresh() async {
    _seen.clear();
    _libIndex = 0;
    _startIndex = 0;
    _orderedSeeds = [];
    state = const HomeHubSectionListState(isLoading: true);
    if (section == 'recent') {
      await _loadRecent();
      return;
    }
    await _loadNextBatch(append: false);
    await _prefetchIfSparse();
  }

  Future<void> loadMore() async {
    if (section == 'recent') return;
    if (state.isLoading || state.isLoadingMore || !state.hasMore) return;
    state = state.copyWith(isLoadingMore: true, error: null);
    await _loadNextBatch(append: true);
  }

  Future<void> _loadRecent() async {
    try {
      final list = await ref.read(embyResumeProvider.future);
      state = HomeHubSectionListState(items: list, hasMore: false, isLoading: false);
    } catch (e) {
      state = HomeHubSectionListState(isLoading: false, error: e);
    }
  }

  Future<void> _prefetchIfSparse() async {
    if (state.error != null || !state.hasMore) return;
    var extra = 0;
    while (state.hasMore &&
        state.items.length < _prefetchMinItems &&
        extra < _prefetchMaxExtraPages) {
      extra++;
      await _loadNextBatch(append: true);
      if (state.error != null) break;
    }
  }

  Future<void> _loadNextBatch({required bool append}) async {
    try {
      if (_orderedSeeds.isEmpty) {
        final libs = await ref.read(embyLibrariesProvider.future);
        final seeds = seedParentIdsFromLibraries(libs);
        if (seeds.isEmpty) {
          state = HomeHubSectionListState(
            items: append ? state.items : const [],
            hasMore: false,
            isLoading: false,
            isLoadingMore: false,
          );
          return;
        }
        _orderedSeeds = orderedSeedIdsForHomeSection(libs, seeds, section);
      }

      final include = section == 'movie' ? 'Movie' : 'Series';
      final wantMovie = section == 'movie';
      final api = ref.read(embyServiceProvider);
      final batch = <EmbyMediaItem>[];

      while (batch.length < _pageSize && _libIndex < _orderedSeeds.length) {
        final pid = _orderedSeeds[_libIndex];
        final raw = await api.getItems(
          parentId: pid,
          startIndex: _startIndex,
          limit: _pageSize,
          includeItemTypes: include,
          recursive: true,
          sortBy: 'SortName',
          sortOrder: 'Ascending',
        );

        if (raw.isEmpty) {
          _libIndex++;
          _startIndex = 0;
          continue;
        }

        for (final m in raw) {
          final okType = wantMovie ? m.type == 'Movie' : m.type == 'Series';
          if (!okType) continue;
          if (_seen.add(m.id)) batch.add(m);
        }

        _startIndex += raw.length;
        if (raw.length < _pageSize) {
          _libIndex++;
          _startIndex = 0;
        }
      }

      final merged = append ? [...state.items, ...batch] : batch;
      final hasMore = _libIndex < _orderedSeeds.length;
      state = HomeHubSectionListState(
        items: merged,
        hasMore: hasMore,
        isLoading: false,
        isLoadingMore: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        isLoadingMore: false,
        error: e,
      );
    }
  }
}

final homeHubSectionProvider = NotifierProvider.autoDispose
    .family<HomeHubSectionListNotifier, HomeHubSectionListState, String>(
  HomeHubSectionListNotifier.new,
);
