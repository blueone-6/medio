import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/platform_layout.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../models/emby/emby_library.dart';
import '../../providers/emby_provider.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/tv/tv_focus_ring.dart';
import '../home/home_layout.dart';
import '../home/home_typography.dart';
import 'paginated_media_browse.dart';

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
  /// 菜单里的标签自带方向：只写「最近更新 / 添加时间」时用户分不清两者差别。
  String get label {
    switch (this) {
      case MediaBrowseSort.recent:
        return '最近更新';
      case MediaBrowseSort.name:
        return '名称 A→Z';
      case MediaBrowseSort.rating:
        return '评分 高→低';
      case MediaBrowseSort.added:
        return '入库时间 新→旧';
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

/// 「影视」页：标题 + 计数 + 类型切换 + 分类筛选 + 排序 + 分页卡片网格。
///
/// 三端共用：手机底部 tab、桌面/电视侧栏入口。分类 chips 由 Emby 媒体库
/// （即二级分类目录）自动生成，不硬编码；「全部」走不带 ParentId 的跨库查询。
///
/// 布局约定：页头与网格共用同一个水平内边距与内容列宽（桌面 1200 居中），
/// 否则宽屏上控件条会贴在左边而海报居中。
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
  static const _searchDebounce = Duration(milliseconds: 300);

  final _browseKey = GlobalKey<PaginatedMediaBrowseState>();
  final _searchController = TextEditingController();
  final _kindNodes = {
    for (final kind in MediaBrowseKind.values) kind: FocusNode(),
  };
  final _tvSortAnchorKey = GlobalKey();

  late MediaBrowseKind _kind;
  MediaBrowseSort _sort = MediaBrowseSort.recent;
  String? _categoryId;
  bool _searching = false;
  String _searchTerm = '';
  Timer? _debounce;
  MediaBrowseCounts _counts = (visible: 0, total: 0);

  /// 用户在页头动过手之后，不再把焦点自动交给第一张海报（TV）。
  bool _userTouchedHeader = false;

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
    _debounce?.cancel();
    _searchController.dispose();
    for (final node in _kindNodes.values) {
      node.dispose();
    }
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
      _userTouchedHeader = true;
      // 电影/剧集分类不通用，切换时回落到「全部」
      _categoryId = null;
    });
    _persist(_kKindKey, kind.name);
    _restoreCategoryFromStorage(kind);
    if (widget.tv) {
      // 焦点留在刚按下的 chip 上，而不是被网格重新抢走。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _kindNodes[kind]?.requestFocus();
      });
    }
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
    setState(() {
      _categoryId = categoryId;
      _userTouchedHeader = true;
    });
    _persist(_categoryKey, categoryId);
  }

  void _onSortSelected(MediaBrowseSort sort) {
    if (sort == _sort) return;
    setState(() {
      _sort = sort;
      _userTouchedHeader = true;
    });
    _persist(_kSortKey, sort.name);
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(_searchDebounce, () => _applySearch(value));
  }

  void _applySearch(String value) {
    final term = value.trim();
    if (term == _searchTerm) return;
    setState(() => _searchTerm = term);
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      _userTouchedHeader = true;
      if (!_searching) {
        _searchTerm = '';
        _searchController.clear();
        _debounce?.cancel();
      }
    });
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchController.clear();
    if (_searchTerm.isEmpty) {
      _toggleSearch();
      return;
    }
    setState(() => _searchTerm = '');
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

  /// 页头与网格共用的水平内边距。
  ///
  /// TV 由 `tv_home_shell` 提供 48dp 安全区，这里不再叠加；
  /// 桌面沿用首页的 20，避免页头与海报各算一套。
  double _horizontalInset(BuildContext context) {
    if (widget.tv) return 0;
    if (context.isDesktopUi) return HomeLayout.horizontalMargin;
    return horizontalPaddingOf(context);
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
            child: PaginatedMediaBrowse(
              key: _browseKey,
              parentId: effectiveCategory,
              includeItemTypes: _kind.itemTypes,
              searchTerm: _searchTerm.isEmpty ? null : _searchTerm,
              sortBy: _sort.sortBy,
              sortOrder: _sort.sortOrder,
              onCountsChanged: (counts) {
                if (counts == _counts || !mounted) return;
                setState(() => _counts = counts);
              },
              onClearSearch: _clearSearch,
              tv: widget.tv,
              horizontalPadding: _horizontalInset(context),
              tvAutofocusFirst: !_userTouchedHeader,
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
    final cs = Theme.of(context).colorScheme;
    final tv = widget.tv;
    final inset = _horizontalInset(context);
    final showTitle = !context.isPhoneUi;
    // 指针设备（桌面）鼠标命中可以更小；触控与遥控守住 48dp。
    final controlHeight = tv
        ? AppSpacing.minTouchTarget
        : (context.isDesktopUi ? 36.0 : AppSpacing.minTouchTarget);
    // 分段控件的轨道留 2px 内缩，故比单个控件高 4px 才能保证内部命中 ≥48。
    final switchHeight = controlHeight + AppSpacing.xs;

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: context.isDesktopUi && !tv
              ? HomeLayout.pcContentMaxWidth
              : double.infinity,
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            inset,
            tv ? AppSpacing.sm : AppSpacing.lg,
            inset,
            AppSpacing.xs,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (showTitle) ...[
                    Text(
                      '影视',
                      style: HomeTypography.headlineLg(cs.onSurface),
                    ),
                    const SizedBox(width: AppSpacing.md),
                  ],
                  const Spacer(),
                  if (!tv) ...[
                    _SortControl(
                      sort: _sort,
                      height: controlHeight,
                      onSelected: _onSortSelected,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    IconButton(
                      tooltip: '刷新',
                      onPressed: () => _browseKey.currentState?.refresh(),
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                    ),
                  ],
                  if (widget.showSearch && !tv)
                    IconButton(
                      tooltip: _searching ? '收起搜索' : '搜索',
                      onPressed: _toggleSearch,
                      icon: Icon(
                        _searching
                            ? Icons.close_rounded
                            : Icons.search_rounded,
                        size: 20,
                      ),
                    ),
                  if (tv) ...[
                    KeyedSubtree(
                      key: _tvSortAnchorKey,
                      child: _TvActionChip(
                        label: _sort.label,
                        icon: Icons.swap_vert_rounded,
                        onTap: () => _openSortMenu(context),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    _TvActionChip(
                      label: '搜索',
                      icon: Icons.search_rounded,
                      onTap: () {
                        setState(() => _userTouchedHeader = true);
                        context.push('/search');
                      },
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    _TvActionChip(
                      label: '刷新',
                      icon: Icons.refresh_rounded,
                      onTap: () => _browseKey.currentState?.refresh(),
                    ),
                  ],
                ],
              ),
              if (_searching && !tv)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: CallbackShortcuts(
                    bindings: {
                      const SingleActivator(LogicalKeyboardKey.escape):
                          _toggleSearch,
                    },
                    child: TextField(
                      controller: _searchController,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      onChanged: _onSearchChanged,
                      onSubmitted: _applySearch,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: '搜索片名',
                        prefixIcon: const Icon(Icons.search_rounded, size: 18),
                        suffixIcon: IconButton(
                          tooltip: '清除搜索',
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: _clearSearch,
                        ),
                      ),
                    ),
                  ),
                ),
              SizedBox(height: tv ? AppSpacing.md : AppSpacing.sm),
              Row(
                children: [
                  _BrowseKindSwitch(
                    value: _kind,
                    height: switchHeight,
                    tv: tv,
                    focusNodes: _kindNodes,
                    onChanged: _onKindChanged,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _CategoryChips(
                      categories: visible,
                      selectedId: effectiveCategory,
                      height: controlHeight,
                      tv: tv,
                      onSelected: _onCategorySelected,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              _CountLine(
                counts: _counts,
                style: HomeTypography.cjkLabel(
                  fontSize: 12,
                  height: 16 / 12,
                  fontWeight: FontWeight.w500,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// TV 没有 hover：用菜单路由承载排序，焦点由焦点环持有，菜单自身可由 D-Pad 导航。
  Future<void> _openSortMenu(BuildContext context) async {
    final anchor = _tvSortAnchorKey.currentContext?.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (anchor == null || overlay == null) return;
    final topLeft = anchor.localToGlobal(Offset.zero, ancestor: overlay);
    setState(() => _userTouchedHeader = true);
    final selected = await showMenu<MediaBrowseSort>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(
          topLeft.dx,
          topLeft.dy,
          anchor.size.width,
          anchor.size.height,
        ),
        Offset.zero & overlay.size,
      ),
      items: [
        for (final sort in MediaBrowseSort.values)
          CheckedPopupMenuItem(
            value: sort,
            checked: sort == _sort,
            child: Text(sort.label),
          ),
      ],
    );
    if (selected != null) _onSortSelected(selected);
  }
}

/// 「共 N 部 · 已加载 M」——数字用等宽数字，避免计数变化时抖动。
class _CountLine extends StatelessWidget {
  const _CountLine({required this.counts, required this.style});

  final MediaBrowseCounts counts;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    if (counts.total <= 0 && counts.visible <= 0) {
      return const SizedBox(height: 16);
    }
    final total = _format(counts.total);
    final text = counts.visible < counts.total
        ? '共 $total 部 · 已加载 ${_format(counts.visible)}'
        : '共 $total 部';
    return Text(
      text,
      style: style.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
    );
  }

  static String _format(int value) {
    final digits = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }
}

/// 剧集 / 电影：两态分段控件。
///
/// 不用 M3 `SegmentedButton`：它的选中段比未选中更暗（`secondaryContainer`
/// 承托 `onSecondaryContainer`），状态被读反，也不带品牌强调色。这里用
/// `primaryContainer` + `onPrimaryContainer`（默认琥珀下 4.58:1）并补上
/// `Semantics(selected:)`。
class _BrowseKindSwitch extends StatelessWidget {
  const _BrowseKindSwitch({
    required this.value,
    required this.height,
    required this.tv,
    required this.focusNodes,
    required this.onChanged,
  });

  final MediaBrowseKind value;
  final double height;
  final bool tv;
  final Map<MediaBrowseKind, FocusNode> focusNodes;
  final ValueChanged<MediaBrowseKind> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHigh,
      borderRadius: AppRadius.smR,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final kind in MediaBrowseKind.values)
              _segment(context, kind, cs),
          ],
        ),
      ),
    );
  }

  Widget _segment(BuildContext context, MediaBrowseKind kind, ColorScheme cs) {
    final selected = kind == value;
    final label = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: tv ? AppSpacing.lg : AppSpacing.md,
        vertical: (height - AppSpacing.xxs * 2 - 18) / 2,
      ),
      child: ExcludeSemantics(
        child: Text(
          kind.label,
          style: HomeTypography.cjkLabel(
            fontSize: 13,
            height: 18 / 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
          ),
        ),
      ),
    );

    final content = Semantics(
      button: true,
      selected: selected,
      label: kind.label,
      child: Material(
        color: selected ? cs.primaryContainer : Colors.transparent,
        borderRadius: AppRadius.smR,
        child: InkWell(
          onTap: () => onChanged(kind),
          canRequestFocus: !tv,
          borderRadius: AppRadius.smR,
          child: label,
        ),
      ),
    );

    if (!tv) return content;
    return TvFocusRing(
      focusNode: focusNodes[kind],
      borderRadius: AppRadius.sm,
      scaleFocused: false,
      borderWidth: 2,
      onActivate: () => onChanged(kind),
      child: content,
    );
  }
}

/// 分类 chips：pill 形态，选中态与类型切换同一套语义色。
class _CategoryChips extends StatelessWidget {
  const _CategoryChips({
    required this.categories,
    required this.selectedId,
    required this.height,
    required this.tv,
    required this.onSelected,
  });

  final List<EmbyLibrary> categories;
  final String? selectedId;
  final double height;
  final bool tv;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
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
    final interactive = Semantics(
      button: true,
      selected: selected,
      label: label,
      onTap: () => onSelected(value),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onSelected(value),
        child: SizedBox(
          height: height,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: _ChipPill(
                label: label,
                selected: selected,
              ),
            ),
          ),
        ),
      ),
    );

    final child = tv
        ? TvFocusRing(
            borderRadius: AppRadius.pill,
            scaleFocused: false,
            borderWidth: 2,
            onActivate: () => onSelected(value),
            child: interactive,
          )
        : interactive;

    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: child,
    );
  }
}

/// chip 的视觉本体：36px 高，外层的 48px 命中区由父级提供。
class _ChipPill extends StatefulWidget {
  const _ChipPill({
    required this.label,
    required this.selected,
  });

  final String label;
  final bool selected;

  @override
  State<_ChipPill> createState() => _ChipPillState();
}

class _ChipPillState extends State<_ChipPill> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fill = widget.selected
        ? cs.primaryContainer
        : (_hovered ? cs.surfaceContainerHighest : cs.surfaceContainerHigh);
    final ink = widget.selected ? cs.onPrimaryContainer : cs.onSurfaceVariant;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.emphasized,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: AppRadius.pillR,
        ),
        child: ExcludeSemantics(
          child: Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: HomeTypography.cjkLabel(
              fontSize: 12,
              height: 16 / 12,
              fontWeight: widget.selected ? FontWeight.w700 : FontWeight.w500,
              color: ink,
            ),
          ),
        ),
      ),
    );
  }
}

/// 桌面 / 平板排序控件：当前值可见 + 菜单勾选态 + 明确方向。
class _SortControl extends StatelessWidget {
  const _SortControl({
    required this.sort,
    required this.height,
    required this.onSelected,
  });

  final MediaBrowseSort sort;
  final double height;
  final ValueChanged<MediaBrowseSort> onSelected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopupMenuButton<MediaBrowseSort>(
      tooltip: '排序',
      initialValue: sort,
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final item in MediaBrowseSort.values)
          CheckedPopupMenuItem(
            value: item,
            checked: item == sort,
            child: Text(item.label),
          ),
      ],
      child: _HoverSurface(
        height: height,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.swap_vert_rounded, size: 18, color: cs.onSurfaceVariant),
              const SizedBox(width: AppSpacing.xs),
              Text(
                sort.label,
                style: HomeTypography.cjkLabel(
                  fontSize: 12,
                  height: 16 / 12,
                  fontWeight: FontWeight.w500,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 桌面排序控件的 hover 反馈（PopupMenuButton 自己只管点击）。
class _HoverSurface extends StatefulWidget {
  const _HoverSurface({required this.child, required this.height});

  final Widget child;
  final double height;

  @override
  State<_HoverSurface> createState() => _HoverSurfaceState();
}

class _HoverSurfaceState extends State<_HoverSurface> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.emphasized,
        height: widget.height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _hovered ? cs.surfaceContainerHigh : Colors.transparent,
          borderRadius: AppRadius.smR,
        ),
        child: widget.child,
      ),
    );
  }
}

/// TV 页头的动作 chip：焦点环 + 48dp 命中区。
class _TvActionChip extends StatelessWidget {
  const _TvActionChip({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final chip = Material(
      color: cs.surfaceContainerHigh,
      borderRadius: AppRadius.pillR,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: AppSpacing.xs),
            Text(
              label,
              style: HomeTypography.cjkLabel(
                fontSize: 12,
                height: 16 / 12,
                fontWeight: FontWeight.w500,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );

    return TvFocusRing(
      borderRadius: AppRadius.pill,
      scaleFocused: false,
      borderWidth: 2,
      onActivate: onTap,
      child: SizedBox(
        height: AppSpacing.minTouchTarget,
        child: Center(child: chip),
      ),
    );
  }
}
