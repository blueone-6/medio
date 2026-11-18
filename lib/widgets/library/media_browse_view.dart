import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../models/emby/emby_library.dart';
import '../../providers/emby_provider.dart';
import '../../providers/settings_provider.dart';
import '../../screens/library_screen.dart';
import '../home/home_typography.dart';

/// 影视页的内容类型。
enum MediaBrowseKind { series, movie }

extension MediaBrowseKindX on MediaBrowseKind {
  String get label => this == MediaBrowseKind.series ? '剧集' : '电影';
  String get itemTypes => this == MediaBrowseKind.series ? 'Series' : 'Movie';
  String get collectionType =>
      this == MediaBrowseKind.series ? 'tvshows' : 'movies';
}

/// 影视页排序方式。
enum MediaBrowseSort { recent, name, rating, added }

extension MediaBrowseSortX on MediaBrowseSort {
  String get label {
    switch (this) {
      case MediaBrowseSort.recent:
        return '最近更新';
      case MediaBrowseSort.name:
        return '名称';
      case MediaBrowseSort.rating:
        return '评分';
      case MediaBrowseSort.added:
        return '添加时间';
    }
  }

  String get sortBy {
    switch (this) {
      case MediaBrowseSort.recent:
        return 'DateLastContentAdded';
      case MediaBrowseSort.name:
        return 'SortName';
      case MediaBrowseSort.rating:
        return 'CommunityRating';
      case MediaBrowseSort.added:
        return 'DateCreated';
    }
  }

  String get sortOrder =>
      this == MediaBrowseSort.name ? 'Ascending' : 'Descending';
}

/// 「影视」页：类型切换 + 分类筛选 + 排序 + 卡片网格。
///
/// 三端共用：手机底部 tab、桌面/电视侧栏入口。分类 chips 由 Emby 媒体库
/// （即二级分类目录）自动生成，不硬编码；「全部」走不带 ParentId 的跨库查询。
class MediaBrowseView extends ConsumerStatefulWidget {
  const MediaBrowseView({
    super.key,
    this.initialKind = MediaBrowseKind.series,
    this.tv = false,
    this.showSearch = true,
    this.padding,
  });

  final MediaBrowseKind initialKind;
  final bool tv;
  final bool showSearch;
  final EdgeInsetsGeometry? padding;

  @override
  ConsumerState<MediaBrowseView> createState() => _MediaBrowseViewState();
}

class _MediaBrowseViewState extends ConsumerState<MediaBrowseView> {
  static const _kKindKey = 'browse.kind';
  static const _kSortKey = 'browse.sort';
  static const _kCategorySeriesKey = 'browse.category.series';
  static const _kCategoryMovieKey = 'browse.category.movie';

  late MediaBrowseKind _kind;
  MediaBrowseSort _sort = MediaBrowseSort.recent;
  String? _categoryId;
  bool _searching = false;
  String _searchTerm = '';
  final _searchController = TextEditingController();

  String get _categoryKey => _kind == MediaBrowseKind.series
      ? _kCategorySeriesKey
      : _kCategoryMovieKey;

  @override
  void initState() {
    super.initState();
    _kind = widget.initialKind;
    _restorePreferences();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _restorePreferences() {
    try {
      final ls = ref.read(localStorageProvider);
      final kind = ls.getString(_kKindKey);
      if (kind == 'movie') {
        _kind = MediaBrowseKind.movie;
      } else if (kind == 'series') {
        _kind = MediaBrowseKind.series;
      }
      final sort = ls.getString(_kSortKey);
      _sort = MediaBrowseSort.values.firstWhere(
        (s) => s.name == sort,
        orElse: () => MediaBrowseSort.recent,
      );
      _categoryId = ls.getString(_categoryKey);
    } catch (_) {
      // 存储不可用时使用默认值
    }
  }

  void _persist(String key, String? value) {
    try {
      ref.read(localStorageProvider).setString(key, value);
    } catch (_) {
      // 忽略写失败
    }
  }

  void _onKindChanged(MediaBrowseKind kind) {
    if (kind == _kind) return;
    setState(() {
      _kind = kind;
      // 电影/剧集分类不通用，切换时回落到「全部」
      _categoryId = null;
    });
    _persist(_kKindKey, kind.name);
    _restoreCategoryFromStorage(kind);
  }

  void _restoreCategoryFromStorage(MediaBrowseKind kind) {
    try {
      final ls = ref.read(localStorageProvider);
      final key = kind == MediaBrowseKind.series
          ? _kCategorySeriesKey
          : _kCategoryMovieKey;
      final saved = ls.getString(key);
      if (saved != null && mounted) {
        setState(() => _categoryId = saved);
      }
    } catch (_) {
      // 忽略
    }
  }

  void _onCategorySelected(String? categoryId) {
    setState(() => _categoryId = categoryId);
    _persist(_categoryKey, categoryId);
  }

  void _onSortSelected(MediaBrowseSort sort) {
    setState(() => _sort = sort);
    _persist(_kSortKey, sort.name);
  }

  List<EmbyLibrary> _visibleLibraries(List<EmbyLibrary> libraries) {
    return libraries.where((lib) {
      final type = (lib.collectionType ?? '').trim().toLowerCase();
      // mixed 库在两种类型下都可见，保证单库部署也能用
      return type.isEmpty ||
          type == 'mixed' ||
          type == _kind.collectionType;
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final librariesAsync = ref.watch(embyLibrariesProvider);
    final libraries = librariesAsync.value ?? const <EmbyLibrary>[];
    final visible = _visibleLibraries(libraries);

    // 保存的分类不在当前类型下时回落到「全部」
    final effectiveCategory =
        _categoryId != null && visible.any((lib) => lib.id == _categoryId)
            ? _categoryId
            : null;

    return Padding(
      padding: widget.padding ?? EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(context, visible, effectiveCategory),
          Expanded(
            child: LibraryBrowseBody(
              key: ValueKey(
                'browse-${_kind.name}-${effectiveCategory ?? 'all'}-${_sort.name}-$_searchTerm',
              ),
              parentId: effectiveCategory,
              includeItemTypes: _kind.itemTypes,
              searchTerm: _searchTerm.isEmpty ? null : _searchTerm,
              sortBy: _sort.sortBy,
              sortOrder: _sort.sortOrder,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    List<EmbyLibrary> visible,
    String? effectiveCategory,
  ) {
    final isTv = widget.tv;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _KindSwitch(
                value: _kind,
                onChanged: _onKindChanged,
                tv: isTv,
              ),
              const Spacer(),
              if (!isTv)
                PopupMenuButton<MediaBrowseSort>(
                  tooltip: '排序',
                  initialValue: _sort,
                  onSelected: _onSortSelected,
                  itemBuilder: (context) => [
                    for (final sort in MediaBrowseSort.values)
                      PopupMenuItem(
                        value: sort,
                        child: Text(sort.label),
                      ),
                  ],
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.swap_vert_rounded,
                        size: 18,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        _sort.label,
                        style: HomeTypography.labelSm(
                          Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              if (widget.showSearch && !isTv) ...[
                const SizedBox(width: AppSpacing.sm),
                IconButton(
                  tooltip: _searching ? '收起搜索' : '搜索',
                  icon: Icon(
                    _searching ? Icons.close_rounded : Icons.search_rounded,
                  ),
                  onPressed: () {
                    setState(() {
                      _searching = !_searching;
                      if (!_searching) {
                        _searchTerm = '';
                        _searchController.clear();
                      }
                    });
                  },
                ),
              ],
            ],
          ),
          if (_searching && !isTv)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: '搜索片名',
                  prefixIcon: Icon(Icons.search_rounded, size: 18),
                ),
                onChanged: (value) =>
                    setState(() => _searchTerm = value.trim()),
              ),
            ),
          const SizedBox(height: AppSpacing.xs),
          _CategoryChips(
            categories: visible,
            selectedId: effectiveCategory,
            onSelected: _onCategorySelected,
            tv: isTv,
          ),
        ],
      ),
    );
  }
}

class _KindSwitch extends StatelessWidget {
  const _KindSwitch({
    required this.value,
    required this.onChanged,
    required this.tv,
  });

  final MediaBrowseKind value;
  final ValueChanged<MediaBrowseKind> onChanged;
  final bool tv;

  @override
  Widget build(BuildContext context) {
    if (tv) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final kind in MediaBrowseKind.values) ...[
            if (kind != MediaBrowseKind.values.first)
              const SizedBox(width: AppSpacing.sm),
            _TvSegChip(
              label: kind.label,
              selected: kind == value,
              onTap: () => onChanged(kind),
            ),
          ],
        ],
      );
    }
    return SegmentedButton<MediaBrowseKind>(
      segments: [
        for (final kind in MediaBrowseKind.values)
          ButtonSegment(value: kind, label: Text(kind.label)),
      ],
      selected: {value},
      showSelectedIcon: false,
      onSelectionChanged: (selection) {
        if (selection.isNotEmpty) onChanged(selection.first);
      },
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(
          borderRadius: AppRadius.smR,
        )),
      ),
    );
  }
}

class _TvSegChip extends StatelessWidget {
  const _TvSegChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? cs.primaryContainer.withValues(alpha: 0.5)
          : cs.surfaceContainerHigh,
      borderRadius: AppRadius.smR,
      child: InkWell(
        borderRadius: AppRadius.smR,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            label,
            style: HomeTypography.labelSm(
              selected ? cs.primary : cs.onSurfaceVariant,
            ).copyWith(fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
          ),
        ),
      ),
    );
  }
}

class _CategoryChips extends StatelessWidget {
  const _CategoryChips({
    required this.categories,
    required this.selectedId,
    required this.onSelected,
    required this.tv,
  });

  final List<EmbyLibrary> categories;
  final String? selectedId;
  final ValueChanged<String?> onSelected;
  final bool tv;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _chip(context, label: '全部', value: null),
          for (final lib in categories)
            _chip(context, label: lib.name, value: lib.id),
        ],
      ),
    );
  }

  Widget _chip(
    BuildContext context, {
    required String label,
    required String? value,
  }) {
    final selected = value == selectedId;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: Material(
        color: selected
            ? cs.primaryContainer.withValues(alpha: 0.5)
            : cs.surfaceContainerHigh.withValues(alpha: 0.7),
        borderRadius: AppRadius.pillR,
        child: InkWell(
          borderRadius: AppRadius.pillR,
          onTap: () => onSelected(value),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Text(
              label,
              style: HomeTypography.labelSm(
                selected ? cs.primary : cs.onSurfaceVariant,
              ).copyWith(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
