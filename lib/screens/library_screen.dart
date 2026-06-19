import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/layout/platform_layout.dart';
import '../models/emby/emby_media_item.dart';
import '../providers/emby_provider.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/error_view.dart';
import '../widgets/home/home_layout.dart';
import '../widgets/library/library_browse_recommend_card.dart';
import '../widgets/media_grid.dart';
import '../widgets/tv/tv_paginated_library_browse.dart';

EmbyLibraryListArg libraryItemsQuery(
  String parentId,
  String? itemsQuery, {
  String? searchTerm,
}) {
  final types = itemsQuery?.trim();
  final filtered = types != null && types.isNotEmpty;
  final term = searchTerm?.trim();
  return (
    parentId: parentId,
    includeItemTypes: filtered ? types : null,
    recursive: filtered || (term != null && term.isNotEmpty),
    limit: filtered ? 500 : 50,
    sortBy: filtered ? 'SortName' : null,
    sortOrder: filtered ? 'Ascending' : null,
    searchTerm: term != null && term.isNotEmpty ? term : null,
  );
}

/// 媒体库条目网格（无 Scaffold），供全屏 [LibraryScreen] 与首页右侧面板复用。
class LibraryBrowseBody extends ConsumerWidget {
  const LibraryBrowseBody({
    super.key,
    required this.parentId,
    this.includeItemTypes,
    this.searchTerm,
    this.allItems,
    this.onBrowseIntoFolder,
  });

  final String parentId;

  /// Emby `IncludeItemTypes` (e.g. `Movie`, `Series`) with recursive listing, matching emby_client.
  final String? includeItemTypes;

  /// Optional inline search term for filtering this library pane in place.
  final String? searchTerm;

  /// Synthetic top-level entries for "all libraries" scopes.
  final List<EmbyMediaItem>? allItems;

  /// 为 null 时文件夹点击走全屏路由；非 null 时由宿主内嵌浏览（如首页右栏）。
  final void Function(EmbyMediaItem folder)? onBrowseIntoFolder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listArg = libraryItemsQuery(
      parentId,
      includeItemTypes,
      searchTerm: searchTerm,
    );
    final term = searchTerm?.trim();
    final isSearching = term != null && term.isNotEmpty;
    final syntheticItems = allItems;
    final items = syntheticItems == null
        ? ref.watch(embyLibraryItemsProvider(listArg))
        : AsyncValue<List<EmbyMediaItem>>.data(syntheticItems);
    final isTv = context.isTvUi;
    final pcRecommend = context.isDesktopUi && !isTv;
    final crossAxisCount = pcRecommend ? HomeLayout.pcRecommendColumns : null;
    final maxContentWidth = pcRecommend ? HomeLayout.pcContentMaxWidth : null;
    final horizontalPadding = pcRecommend ? HomeLayout.horizontalMargin : null;
    final paddingTop = pcRecommend ? HomeLayout.pcSectionGap : 12.0;

    if (isTv) {
      return TvPaginatedLibraryBrowse(
        key: ValueKey(
          '$parentId-${includeItemTypes ?? ''}-${searchTerm ?? ''}-${syntheticItems?.length ?? 0}',
        ),
        parentId: parentId,
        includeItemTypes: includeItemTypes,
        allItems: syntheticItems,
        onBrowseIntoFolder: onBrowseIntoFolder,
      );
    }

    return items.when(
      data: (list) {
        if (list.isEmpty) {
          return EmptyStateView(
            icon: isSearching
                ? Icons.search_off_rounded
                : Icons.video_library_outlined,
            title: isSearching ? '未找到相关内容' : '暂无内容',
            subtitle: isSearching ? '没有匹配“$term”的影片或剧集' : '此文件夹下还没有可浏览的条目',
            actionLabel: '刷新',
            onAction: () => ref.invalidate(embyLibraryItemsProvider(listArg)),
          );
        }
        return MediaGrid(
          homeRecommendStyle: true,
          pcRecommendStyle: pcRecommend,
          crossAxisCount: crossAxisCount,
          maxContentWidth: maxContentWidth,
          horizontalPadding: horizontalPadding,
          paddingTop: paddingTop,
          itemCount: list.length,
          itemBuilder: (context, i) {
            final m = list[i];
            return LibraryBrowseRecommendCard(
              item: m,
              usePcRecommendStyle: pcRecommend,
              onBrowseIntoFolder: onBrowseIntoFolder,
            );
          },
        );
      },
      loading: () => MediaGridSkeleton(
        homeRecommendStyle: true,
        pcRecommendStyle: pcRecommend,
        crossAxisCount: crossAxisCount,
        maxContentWidth: maxContentWidth,
        horizontalPadding: horizontalPadding,
        paddingTop: paddingTop,
      ),
      error: (e, _) => ErrorView(
        error: e,
        onRetry: () => ref.invalidate(embyLibraryItemsProvider(listArg)),
      ),
    );
  }
}

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({
    super.key,
    required this.parentId,
    this.title,
    this.includeItemTypes,
  });

  final String parentId;
  final String? title;

  /// Emby `IncludeItemTypes` (e.g. `Movie`, `Series`) with recursive listing, matching emby_client.
  final String? includeItemTypes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(title ?? '媒体库')),
      body: LibraryBrowseBody(
        parentId: parentId,
        includeItemTypes: includeItemTypes,
      ),
    );
  }
}
