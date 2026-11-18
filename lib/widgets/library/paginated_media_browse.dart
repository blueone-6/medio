import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/platform_layout.dart';
import '../../core/theme/app_spacing.dart';
import '../../models/emby/emby_media_item.dart';
import '../../providers/settings_provider.dart';
import '../../utils/user_facing_error.dart';
import '../empty_state_view.dart';
import '../error_view.dart';
import '../home/home_layout.dart';
import '../media_grid.dart';
import '../tv/tv_library_browse_grid.dart';
import 'library_browse_recommend_card.dart';

/// 页头计数快照：`visible` 已加载条数，`total` 服务端总数。
typedef MediaBrowseCounts = ({int visible, int total});

/// 分页媒体库浏览（手机 / 桌面 / TV 共用一份状态机）。
///
/// 为什么不用一次性 `FutureProvider`：Emby 结果动辄上千条，固定 `limit`
/// 会让页面静默截断而用户毫不知情。这里按页拉取、回读 `TotalRecordCount`，
/// 由页头显示「共 N 部 · 已加载 M」，并在列表末尾给出真正的结束态。
class PaginatedMediaBrowse extends ConsumerStatefulWidget {
  const PaginatedMediaBrowse({
    super.key,
    this.parentId,
    this.includeItemTypes,
    this.searchTerm,
    this.sortBy,
    this.sortOrder,
    this.allItems,
    this.onBrowseIntoFolder,
    this.onCountsChanged,
    this.onClearSearch,
    this.tv = false,
    this.horizontalPadding,
    this.paddingTop,
    this.tvAutofocusFirst = true,
    this.refreshToken = 0,
  });

  /// 为 null 时查询全部媒体库（不传 ParentId）。
  final String? parentId;
  final String? includeItemTypes;
  final String? searchTerm;
  final String? sortBy;
  final String? sortOrder;

  /// 宿主合成的条目（如「所有媒体库」入口）；非空时不发请求。
  final List<EmbyMediaItem>? allItems;
  final void Function(EmbyMediaItem folder)? onBrowseIntoFolder;

  /// 每次成功加载后回调，供页头显示真实计数。
  final ValueChanged<MediaBrowseCounts>? onCountsChanged;

  /// 搜索空态里的「清除搜索」。
  final VoidCallback? onClearSearch;

  final bool tv;

  /// 与页头共用的水平内边距；为空时按设备形态取默认值。
  final double? horizontalPadding;
  final double? paddingTop;

  /// TV 首次进入时是否把焦点交给第一张海报；用户主动切换筛选后应为 false，
  /// 否则网格会把焦点从刚按下的筛选 chip 上抢走。
  final bool tvAutofocusFirst;

  /// 宿主下拉刷新时自增；变化即重新拉取第一页（保留旧内容直到新结果返回）。
  final int refreshToken;

  static const phonePageSize = 60;
  static const tvPageSize = 96;
  static const tvFilteredPageSize = 48;

  @override
  ConsumerState<PaginatedMediaBrowse> createState() =>
      PaginatedMediaBrowseState();
}

class PaginatedMediaBrowseState extends ConsumerState<PaginatedMediaBrowse> {
  final _items = <EmbyMediaItem>[];
  final _scroll = ScrollController();

  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _refreshing = false;
  Object? _error;
  int _seq = 0;
  MediaBrowseCounts? _published;

  bool get _filtered => (widget.includeItemTypes ?? '').trim().isNotEmpty;
  bool get _searching => (widget.searchTerm ?? '').trim().isNotEmpty;

  int get _pageSize {
    if (!widget.tv) return PaginatedMediaBrowse.phonePageSize;
    return _filtered || _searching
        ? PaginatedMediaBrowse.tvFilteredPageSize
        : PaginatedMediaBrowse.tvPageSize;
  }

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    final synthetic = widget.allItems;
    if (synthetic != null) {
      _items.addAll(synthetic);
      _total = synthetic.length;
      _loading = false;
      _hasMore = false;
      _publishCounts();
      return;
    }
    _load(reset: true);
  }

  @override
  void didUpdateWidget(covariant PaginatedMediaBrowse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken && widget.allItems == null) {
      refresh();
      return;
    }
    if (oldWidget.parentId != widget.parentId ||
        oldWidget.includeItemTypes != widget.includeItemTypes ||
        oldWidget.searchTerm != widget.searchTerm ||
        oldWidget.sortBy != widget.sortBy ||
        oldWidget.sortOrder != widget.sortOrder ||
        oldWidget.allItems != widget.allItems) {
      final synthetic = widget.allItems;
      if (synthetic != null) {
        setState(() {
          _items
            ..clear()
            ..addAll(synthetic);
          _total = synthetic.length;
          _loading = false;
          _loadingMore = false;
          _refreshing = false;
          _hasMore = false;
          _error = null;
        });
        _publishCounts();
        return;
      }
      // 保留上一次结果：搜索逐键触发时不再把整墙换成骨架屏。
      _load(reset: true, keepItems: true);
    }
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  /// 页头的刷新动作。
  Future<void> refresh() => _load(reset: true, keepItems: true);

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 480) _maybeLoadMore();
  }

  void _maybeLoadMore() {
    if (_loading || _refreshing || _loadingMore || !_hasMore) return;
    _load(reset: false);
  }

  Future<void> _load({required bool reset, bool keepItems = false}) async {
    if (!reset && (_loadingMore || !_hasMore)) return;
    final seq = reset ? ++_seq : _seq;
    setState(() {
      if (reset) {
        _refreshing = keepItems && _items.isNotEmpty;
        if (!_refreshing) _items.clear();
        _loading = _items.isEmpty;
        _error = null;
        _hasMore = true;
        _loadingMore = false;
      } else {
        _loadingMore = true;
      }
    });

    try {
      final page = await ref.read(embyServiceProvider).getItemsPage(
            parentId: widget.parentId,
            startIndex: reset ? 0 : _items.length,
            limit: _pageSize,
            includeItemTypes: widget.includeItemTypes,
            recursive: _filtered || _searching,
            sortBy: widget.sortBy,
            sortOrder: widget.sortOrder,
            searchTerm: _searching ? widget.searchTerm!.trim() : null,
          );
      if (!mounted || seq != _seq) return;
      setState(() {
        if (reset) {
          _items
            ..clear()
            ..addAll(page.items);
        } else {
          _items.addAll(page.items);
        }
        _total = page.total > 0 ? page.total : _items.length;
        _hasMore = _items.length < _total && page.items.length >= _pageSize;
        _loading = false;
        _loadingMore = false;
        _refreshing = false;
        _error = null;
      });
      if (reset && _scroll.hasClients) {
        // 换筛选/排序后从顶部开始，而不是停在上一批结果的中段。
        _scroll.jumpTo(0);
      }
      _publishCounts();
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _refreshing = false;
        _error = e;
      });
    }
  }

  void _publishCounts() {
    final cb = widget.onCountsChanged;
    if (cb == null) return;
    final snapshot = (visible: _items.length, total: _total);
    if (_published == snapshot) return;
    _published = snapshot;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      cb(snapshot);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.tv) return _buildTv(context);
    if (_items.isEmpty) {
      if (_loading || _refreshing) return _buildSkeleton(context);
      if (_error != null) return _buildError(context);
      return _buildEmpty(context);
    }

    final pcStyle = context.isDesktopUi && !context.isTvUi;
    return Stack(
      children: [
        _buildGrid(context, pcStyle: pcStyle),
        if (_refreshing)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(minHeight: 2),
          ),
      ],
    );
  }

  Widget _buildTv(BuildContext context) {
    if (_items.isEmpty) {
      if (_loading) return _buildSkeleton(context);
      if (_error != null) return _buildError(context);
      return _buildEmpty(context);
    }
    return TvLibraryBrowseGrid(
      items: _items,
      emby: ref.read(embyServiceProvider),
      loadingMore: _loadingMore,
      hasMore: _hasMore,
      autofocusFirst: widget.tvAutofocusFirst,
      onNearEnd: _maybeLoadMore,
      onBrowseIntoFolder: widget.onBrowseIntoFolder,
    );
  }

  Widget _buildGrid(BuildContext context, {required bool pcStyle}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final metrics = resolveMediaGridMetrics(
          context,
          availableWidth: constraints.maxWidth,
          crossAxisCount: pcStyle ? HomeLayout.pcRecommendColumns : null,
          homeRecommendStyle: true,
          pcRecommendStyle: pcStyle,
          maxContentWidth: pcStyle ? HomeLayout.pcContentMaxWidth : null,
          horizontalPadding: widget.horizontalPadding,
        );
        final pad = metrics.horizontalPadding;
        Widget cardBuilder(BuildContext context, int index) {
          final item = _items[index];
          return LibraryBrowseRecommendCard(
            item: item,
            usePcRecommendStyle: pcStyle,
            onBrowseIntoFolder: widget.onBrowseIntoFolder,
          );
        }
        // 一屏装得下（且没有下一页）时沿用 MediaGrid 的单行居中，
        // 避免「一张卡孤零零贴左」。
        if (_items.length <= metrics.columns && !_hasMore) {
          return MediaGrid(
            itemCount: _items.length,
            itemBuilder: cardBuilder,
            homeRecommendStyle: true,
            pcRecommendStyle: pcStyle,
            crossAxisCount: pcStyle ? HomeLayout.pcRecommendColumns : null,
            maxContentWidth: pcStyle ? HomeLayout.pcContentMaxWidth : null,
            horizontalPadding: widget.horizontalPadding,
            paddingTop: widget.paddingTop ?? AppSpacing.md,
            centerSingleRow: true,
          );
        }
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: metrics.contentWidth,
            child: CustomScrollView(
              controller: _scroll,
              slivers: [
                if (_error != null)
                  SliverToBoxAdapter(
                    child: _StaleErrorBar(onRetry: () => refresh()),
                  ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    pad,
                    widget.paddingTop ?? AppSpacing.md,
                    pad,
                    0,
                  ),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: metrics.columns,
                      childAspectRatio: metrics.tileWidth / metrics.tileHeight,
                      crossAxisSpacing: metrics.spacing,
                      mainAxisSpacing: metrics.spacing,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      cardBuilder,
                      childCount: _items.length,
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: _BrowseFooter(
                    visible: _items.length,
                    total: _total,
                    loadingMore: _loadingMore,
                    hasMore: _hasMore,
                    onLoadMore: _maybeLoadMore,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSkeleton(BuildContext context) {
    final pcStyle = context.isDesktopUi && !context.isTvUi;
    return MediaGridSkeleton(
      homeRecommendStyle: true,
      pcRecommendStyle: pcStyle,
      crossAxisCount: pcStyle ? HomeLayout.pcRecommendColumns : null,
      maxContentWidth: pcStyle ? HomeLayout.pcContentMaxWidth : null,
      horizontalPadding: widget.horizontalPadding,
      paddingTop: widget.paddingTop ?? AppSpacing.md,
    );
  }

  Widget _buildError(BuildContext context) {
    return ErrorView.forHomeSection(
      error: _error!,
      section: HomeLoadSection.libraries,
      onRetry: () => _load(reset: true),
      onOpenSettings: () => context.push('/settings'),
      aligned: false,
    );
  }

  Widget _buildEmpty(BuildContext context) {
    if (_searching) {
      return EmptyStateView(
        icon: Icons.search_off_rounded,
        title: '未找到相关内容',
        subtitle: '没有匹配「${widget.searchTerm!.trim()}」的影片或剧集',
        actionLabel: widget.onClearSearch != null ? '清除搜索' : null,
        onAction: widget.onClearSearch,
      );
    }
    return EmptyStateView(
      icon: Icons.video_library_outlined,
      title: '这个分类还没有片子',
      subtitle: '整理完成后这里会自动出现；也可以点上面的刷新重新扫描',
      actionLabel: '刷新媒体库',
      onAction: () => _load(reset: true),
    );
  }
}

/// 已加载过内容时的刷新失败提示：不清空旧结果，只在顶部提示。
class _StaleErrorBar extends StatelessWidget {
  const _StaleErrorBar({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        0,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              '刷新失败，下面是上一次的结果',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              minimumSize: const Size(48, 32),
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }
}

/// 列表末尾的真实结束态 + 订阅桥。
class _BrowseFooter extends StatelessWidget {
  const _BrowseFooter({
    required this.visible,
    required this.total,
    required this.loadingMore,
    required this.hasMore,
    required this.onLoadMore,
  });

  final int visible;
  final int total;
  final bool loadingMore;
  final bool hasMore;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Center(
          child: TextButton(
            onPressed: onLoadMore,
            style: TextButton.styleFrom(
              minimumSize: const Size(48, AppSpacing.minTouchTarget),
            ),
            child: const Text('加载更多'),
          ),
        ),
      );
    }
    if (visible < 12) return const SizedBox(height: AppSpacing.xl);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xxl,
        AppSpacing.lg,
        AppSpacing.huge,
      ),
      child: Column(
        children: [
          Text(
            total > 0 ? '共 $total 部 · 到底了' : '到底了',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
