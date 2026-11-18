import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/emby/emby_media_item.dart';
import '../providers/emby_provider.dart';
import '../widgets/library/paginated_media_browse.dart';

EmbyLibraryListArg libraryItemsQuery(
  String? parentId,
  String? itemsQuery, {
  String? searchTerm,
  String? sortBy,
  String? sortOrder,
}) {
  final types = itemsQuery?.trim();
  final filtered = types != null && types.isNotEmpty;
  final term = searchTerm?.trim();
  return (
    parentId: parentId,
    includeItemTypes: filtered ? types : null,
    recursive: filtered || (term != null && term.isNotEmpty),
    limit: filtered ? 500 : 50,
    sortBy: sortBy ?? (filtered ? 'SortName' : null),
    sortOrder: sortOrder ?? (filtered ? 'Ascending' : null),
    searchTerm: term != null && term.isNotEmpty ? term : null,
  );
}

/// 媒体库条目网格（无 Scaffold），供全屏 [LibraryScreen]、媒体库页与首页右侧面板复用。
///
/// 分页、总数与错误/空态由 [PaginatedMediaBrowse] 统一处理：三端同一套，
/// 不再出现「只显示前 500 条」的静默截断。
class LibraryBrowseBody extends ConsumerWidget {
  const LibraryBrowseBody({
    super.key,
    required this.parentId,
    this.includeItemTypes,
    this.searchTerm,
    this.sortBy,
    this.sortOrder,
    this.allItems,
    this.onBrowseIntoFolder,
    this.refreshToken = 0,
  });

  /// 为 null 时查询全部媒体库（不传 ParentId）。
  final String? parentId;

  /// Emby `IncludeItemTypes` (e.g. `Movie`, `Series`) with recursive listing, matching emby_client.
  final String? includeItemTypes;

  /// Optional inline search term for filtering this library pane in place.
  final String? searchTerm;

  /// 排序字段/方向；为空时沿用默认（过滤视图按 SortName 升序）。
  final String? sortBy;
  final String? sortOrder;

  /// Synthetic top-level entries for "all libraries" scopes.
  final List<EmbyMediaItem>? allItems;

  /// 为 null 时文件夹点击走全屏路由；非 null 时由宿主内嵌浏览（如首页右栏）。
  final void Function(EmbyMediaItem folder)? onBrowseIntoFolder;

  /// 宿主下拉刷新时自增；透传给分页网格。
  final int refreshToken;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PaginatedMediaBrowse(
      parentId: parentId,
      includeItemTypes: includeItemTypes,
      searchTerm: searchTerm,
      sortBy: sortBy,
      sortOrder: sortOrder,
      allItems: allItems,
      onBrowseIntoFolder: onBrowseIntoFolder,
      refreshToken: refreshToken,
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
