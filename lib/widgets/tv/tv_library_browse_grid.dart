import 'package:flutter/material.dart';

import '../../models/emby/emby_media_item.dart';
import '../../services/emby_service.dart';
import '../../utils/media_navigation.dart';
import '../library/library_browse_recommend_card.dart';
import 'tv_focus_ring.dart';
import 'tv_grid_poster_card.dart';
import 'tv_home_layout.dart';

/// TV 媒体库/电影/电视剧浏览网格：两行大卡、D-Pad 焦点、进入详情（无快捷播放）。
class TvLibraryBrowseGrid extends StatefulWidget {
  const TvLibraryBrowseGrid({
    super.key,
    required this.items,
    required this.emby,
    this.onBrowseIntoFolder,
    this.autofocusFirst = true,
    this.loadingMore = false,
    this.hasMore = true,
    this.onNearEnd,
  });

  final List<EmbyMediaItem> items;
  final EmbyService emby;
  final void Function(EmbyMediaItem folder)? onBrowseIntoFolder;
  final bool autofocusFirst;
  final bool loadingMore;
  final bool hasMore;
  final VoidCallback? onNearEnd;

  static const visibleRows = 2;
  static const _titleBandHeight = 22.0;

  @override
  State<TvLibraryBrowseGrid> createState() => _TvLibraryBrowseGridState();
}

class _TvLibraryBrowseGridState extends State<TvLibraryBrowseGrid> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!widget.hasMore || widget.onNearEnd == null) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 320) {
      widget.onNearEnd!();
    }
  }

  void _onCellFocused(int index, _TvGridLayout layout) {
    _scrollToIndex(index: index, layout: layout);
  }

  void _scrollToIndex({required int index, required _TvGridLayout layout}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final position = _scrollController.position;
      if (!position.hasContentDimensions) return;

      final row = index ~/ layout.columns;
      final rowTop = row * layout.rowStride;
      final rowBottom = rowTop + layout.rowH;
      final viewTop = position.pixels;
      final viewBottom = viewTop + position.viewportDimension;

      // Row already fully visible — skip scroll (horizontal moves stay instant).
      if (rowTop >= viewTop && rowBottom <= viewBottom) {
        if (widget.onNearEnd != null &&
            viewBottom >= position.maxScrollExtent - layout.rowH &&
            widget.hasMore) {
          widget.onNearEnd!();
        }
        return;
      }

      final maxOffset = position.maxScrollExtent;
      var offset = rowTop - (position.viewportDimension - layout.rowH) / 2;
      offset = offset.clamp(0.0, maxOffset);
      _scrollController.jumpTo(offset);

      if (widget.onNearEnd != null &&
          offset >= maxOffset - layout.rowH &&
          widget.hasMore) {
        widget.onNearEnd!();
      }
    });
  }

  _TvGridLayout _layoutFor(double gridW, double gridH, double viewportW) {
    const spacing = TvHomeLayout.railGap;
    final rowH =
        (gridH - spacing * (TvLibraryBrowseGrid.visibleRows - 1)) /
            TvLibraryBrowseGrid.visibleRows;

    final designW = TvHomeLayout.scaled(TvHomeLayout.designPosterWidth, viewportW);
    var columns = ((gridW + spacing) / (designW + spacing)).floor().clamp(4, 6);
    var tileW = (gridW - spacing * (columns - 1)) / columns;
    var focusMargin = TvHomeLayout.focusMarginFor(tileW);
    var posterH = rowH - focusMargin * 2 - TvLibraryBrowseGrid._titleBandHeight;

    while (posterH * TvHomeLayout.posterAspect > tileW && columns > 3) {
      columns--;
      tileW = (gridW - spacing * (columns - 1)) / columns;
      focusMargin = TvHomeLayout.focusMarginFor(tileW);
      posterH = rowH - focusMargin * 2 - TvLibraryBrowseGrid._titleBandHeight;
    }

    return _TvGridLayout(
      columns: columns,
      rowH: rowH,
      tileW: tileW,
      posterH: posterH,
      focusMargin: focusMargin,
      spacing: spacing,
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewportW = TvHomeLayout.viewportWidthOf(context);

    return FocusTraversalGroup(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final gridW = constraints.maxWidth;
          final gridH = constraints.maxHeight;
          if (gridW < 48 || gridH < 48) return const SizedBox.shrink();

          final layout = _layoutFor(gridW, gridH, viewportW);
          final itemCount =
              widget.items.length + (widget.loadingMore ? layout.columns : 0);

          return GridView.builder(
            controller: _scrollController,
            padding: EdgeInsets.zero,
            cacheExtent: layout.rowH,
            addAutomaticKeepAlives: true,
            addRepaintBoundaries: true,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: layout.columns,
              mainAxisSpacing: layout.spacing,
              crossAxisSpacing: layout.spacing,
              childAspectRatio: layout.tileW / layout.rowH,
            ),
            itemCount: itemCount,
            itemBuilder: (context, index) {
              if (index >= widget.items.length) {
                return const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }
              final item = widget.items[index];
              return _TvLibraryGridCell(
                key: ValueKey('tv-grid-${item.id}'),
                item: item,
                emby: widget.emby,
                layout: layout,
                autofocus: widget.autofocusFirst && index == 0,
                onBrowseIntoFolder: widget.onBrowseIntoFolder,
                onFocused: () => _onCellFocused(index, layout),
              );
            },
          );
        },
      ),
    );
  }
}

class _TvGridLayout {
  const _TvGridLayout({
    required this.columns,
    required this.rowH,
    required this.tileW,
    required this.posterH,
    required this.focusMargin,
    required this.spacing,
  });

  final int columns;
  final double rowH;
  final double tileW;
  final double posterH;
  final double focusMargin;
  final double spacing;

  double get rowStride => rowH + spacing;
}

class _TvLibraryGridCell extends StatelessWidget {
  const _TvLibraryGridCell({
    super.key,
    required this.item,
    required this.emby,
    required this.layout,
    required this.autofocus,
    required this.onFocused,
    this.onBrowseIntoFolder,
  });

  final EmbyMediaItem item;
  final EmbyService emby;
  final _TvGridLayout layout;
  final bool autofocus;
  final VoidCallback onFocused;
  final void Function(EmbyMediaItem folder)? onBrowseIntoFolder;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Padding(
        padding: EdgeInsets.all(layout.focusMargin),
        child: TvFocusRing(
          autofocus: autofocus,
          scaleFocused: false,
          onActivate: () => openLibraryMediaItemDetail(
            context,
            item,
            onBrowseIntoFolder: onBrowseIntoFolder,
          ),
          onFocusChange: (focused) {
            if (focused) onFocused();
          },
          child: item.isLibraryBrowseCategory
              ? LibraryBrowseRecommendCard(
                  item: item,
                  emby: emby,
                  usePcRecommendStyle: false,
                  tvMode: true,
                  maxPosterHeight: layout.posterH,
                  onBrowseIntoFolder: onBrowseIntoFolder,
                )
              : TvGridPosterCard(
                  item: item,
                  emby: emby,
                  posterWidth: layout.tileW - layout.focusMargin * 2,
                  posterHeight: layout.posterH,
                ),
        ),
      ),
    );
  }
}
