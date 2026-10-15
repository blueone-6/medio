import 'package:flutter/material.dart';

import '../core/layout/platform_layout.dart';
import 'home/home_layout.dart';
import 'media_card.dart';
import 'skeleton.dart';

/// 与首页 hub 海报区一致：按最小瓦片宽度自动分列。
int mediaGridCrossAxisCountForWidth(
  double gridWidth, {
  double minTileWidth = 108,
  double spacing = 16,
}) {
  if (gridWidth <= 0) return 1;
  final n = ((gridWidth + spacing) / (minTileWidth + spacing)).floor();
  return n.clamp(1, 12);
}

class MediaGrid extends StatelessWidget {
  const MediaGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.crossAxisCount,
    this.homeRecommendStyle = false,
    this.pcRecommendStyle = false,
    this.paddingTop = 8,
    this.maxContentWidth,
    this.horizontalPadding,
    this.centerSingleRow = false,
  });

  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;
  final int? crossAxisCount;
  final bool homeRecommendStyle;
  final bool pcRecommendStyle;
  final double paddingTop;
  final double? maxContentWidth;
  final double? horizontalPadding;

  /// When the items fit in a single row, center that row instead of hugging
  /// the left edge. Avoids a lone card floating in a wide empty canvas
  /// (e.g. a media library with few libraries).
  final bool centerSingleRow;

  @override
  Widget build(BuildContext context) {
    final horizontalPad = horizontalPadding ?? horizontalPaddingOf(context);
    const gridSpacing = HomeLayout.gridGap;
    final minTileWidth = posterMinTileWidthOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final contentW = maxContentWidth == null
            ? constraints.maxWidth
            : constraints.maxWidth.clamp(0.0, maxContentWidth!);
        final gridW = (contentW - horizontalPad * 2).clamp(0.0, double.infinity);
        final count = crossAxisCount ?? mediaGridCrossAxisCountForWidth(gridW, minTileWidth: minTileWidth, spacing: gridSpacing);
        final tileW = (gridW - gridSpacing * (count - 1)) / count;
        final tileH = homeRecommendStyle
            ? HomeLayout.recommendGridCellHeight(tileW, pcStyle: pcRecommendStyle)
            : mediaCardGridCellHeight(context, tileW);
        final grid = GridView.builder(
          padding: EdgeInsets.fromLTRB(horizontalPad, paddingTop, horizontalPad, 8),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: count,
            childAspectRatio: tileW / tileH,
            crossAxisSpacing: gridSpacing,
            mainAxisSpacing: gridSpacing,
          ),
          itemCount: itemCount,
          itemBuilder: itemBuilder,
        );
        Widget content = grid;
        if (centerSingleRow && itemCount > 0 && itemCount <= count) {
          content = Padding(
            padding: EdgeInsets.fromLTRB(horizontalPad, paddingTop, horizontalPad, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < itemCount; i++) ...[
                  if (i > 0) const SizedBox(width: gridSpacing),
                  SizedBox(
                    width: tileW,
                    height: tileH,
                    child: itemBuilder(context, i),
                  ),
                ],
              ],
            ),
          );
        }
        if (maxContentWidth == null) return content;
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(width: contentW, child: content),
        );
      },
    );
  }
}

/// 网格加载骨架（占位海报 + 标题），与 [MediaGrid] 列宽规则一致。
class MediaGridSkeleton extends StatelessWidget {
  const MediaGridSkeleton({
    super.key,
    this.placeholderCount = 12,
    this.homeRecommendStyle = false,
    this.pcRecommendStyle = false,
    this.paddingTop = 8,
    this.maxContentWidth,
    this.horizontalPadding,
    this.crossAxisCount,
  });

  final int placeholderCount;
  final bool homeRecommendStyle;
  final bool pcRecommendStyle;
  final double paddingTop;
  final double? maxContentWidth;
  final double? horizontalPadding;
  final int? crossAxisCount;

  @override
  Widget build(BuildContext context) {
    final horizontalPad = horizontalPadding ?? horizontalPaddingOf(context);
    const gridSpacing = HomeLayout.gridGap;
    final minTileWidth = posterMinTileWidthOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final contentW = maxContentWidth == null
            ? constraints.maxWidth
            : constraints.maxWidth.clamp(0.0, maxContentWidth!);
        final gridW = (contentW - horizontalPad * 2).clamp(0.0, double.infinity);
        final count = crossAxisCount ?? mediaGridCrossAxisCountForWidth(gridW,
            minTileWidth: minTileWidth, spacing: gridSpacing);
        final tileW = (gridW - gridSpacing * (count - 1)) / count;
        final tileH = homeRecommendStyle
            ? HomeLayout.recommendGridCellHeight(tileW, pcStyle: pcRecommendStyle)
            : mediaCardGridCellHeight(context, tileW);
        // Skeleton grids often sit inside CustomScrollView / Column — must not
        // claim unbounded viewport height.
        final grid = GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(horizontalPad, paddingTop, horizontalPad, 8),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: count,
            childAspectRatio: tileW / tileH,
            crossAxisSpacing: gridSpacing,
            mainAxisSpacing: gridSpacing,
          ),
          itemCount: placeholderCount,
          itemBuilder: (_, __) => PosterSkeleton(
            showTitle: !(homeRecommendStyle && pcRecommendStyle),
            homeRecommendCaption: homeRecommendStyle && !pcRecommendStyle,
          ),
        );
        if (maxContentWidth == null) return grid;
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(width: contentW, child: grid),
        );
      },
    );
  }
}

/// Convenience wrapper building [MediaCard] rows from parallel lists.
class MediaGridFromCards extends StatelessWidget {
  const MediaGridFromCards({
    super.key,
    required this.children,
  });

  final List<MediaCard> children;

  @override
  Widget build(BuildContext context) {
    return MediaGrid(
      itemCount: children.length,
      itemBuilder: (c, i) => children[i],
    );
  }
}
