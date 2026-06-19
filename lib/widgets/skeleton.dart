import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_motion.dart';
import '../core/theme/app_radius.dart';
import 'home/home_layout.dart';

/// 自制 shimmer 骨架占位（不引入第三方依赖）。
///
/// 用一个横向移动的高光渐变扫过底色，适配亮暗主题（取 [AppColors] 令牌）。
class Skeleton extends StatefulWidget {
  const Skeleton({
    super.key,
    this.width,
    this.height,
    this.borderRadius = AppRadius.smR,
    this.shape = BoxShape.rectangle,
  });

  /// 圆形骨架（头像等）。
  const Skeleton.circle({super.key, required double size})
      : width = size,
        height = size,
        borderRadius = AppRadius.smR,
        shape = BoxShape.circle;

  final double? width;
  final double? height;
  final BorderRadius borderRadius;
  final BoxShape shape;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppMotion.shimmer,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value;
          // 高光位置从左外侧移动到右外侧。
          final dx = (t * 2) - 1; // -1 → 1
          return Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              shape: widget.shape,
              borderRadius:
                  widget.shape == BoxShape.circle ? null : widget.borderRadius,
              gradient: LinearGradient(
                begin: Alignment(-1 - dx, 0),
                end: Alignment(1 - dx, 0),
                colors: [
                  colors.skeletonBase,
                  colors.skeletonHighlight,
                  colors.skeletonBase,
                ],
                stops: const [0.35, 0.5, 0.65],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 海报骨架（默认 2:3，含标题占位）。
class PosterSkeleton extends StatelessWidget {
  const PosterSkeleton({
    super.key,
    this.aspectRatio = 2 / 3,
    this.showTitle = true,
    this.homeRecommendCaption = false,
  });

  final double aspectRatio;
  final bool showTitle;

  /// Match [HomeLayout.recommendCaptionHeight] for homepage recommend grids.
  final bool homeRecommendCaption;

  double get _titleBlockHeight => homeRecommendCaption
      ? HomeLayout.recommendCaptionHeight
      : 6.0 + 12.0 + 4.0 + 10.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final poster = const Skeleton(borderRadius: AppRadius.mdR);
        if (!showTitle) {
          return AspectRatio(aspectRatio: aspectRatio, child: poster);
        }

        final titleLines = homeRecommendCaption
            ? [
                SizedBox(height: HomeLayout.posterTitleGap),
                Skeleton(
                  height: HomeLayout.posterTitleFontSize *
                      HomeLayout.posterTitleLineHeight,
                  borderRadius: AppRadius.xsR,
                ),
                Skeleton(
                  height: HomeLayout.posterSubtitleFontSize *
                      HomeLayout.posterSubtitleLineHeight,
                  borderRadius: AppRadius.xsR,
                ),
              ]
            : [
                const SizedBox(height: 6),
                const Skeleton(height: 12, borderRadius: AppRadius.xsR),
                const SizedBox(height: 4),
                const FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: 0.6,
                  child: Skeleton(height: 10, borderRadius: AppRadius.xsR),
                ),
              ];

        if (constraints.hasBoundedHeight) {
          final posterH =
              (constraints.maxHeight - _titleBlockHeight).clamp(0.0, double.infinity);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: posterH, child: poster),
              ...titleLines,
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(aspectRatio: aspectRatio, child: poster),
            ...titleLines,
          ],
        );
      },
    );
  }
}

/// 列表项骨架（缩略图 + 两行文字）。
class ListTileSkeleton extends StatelessWidget {
  const ListTileSkeleton({super.key, this.thumbWidth = 48, this.thumbHeight = 72});

  final double thumbWidth;
  final double thumbHeight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Skeleton(
              width: thumbWidth,
              height: thumbHeight,
              borderRadius: AppRadius.smR),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Skeleton(height: 14, borderRadius: AppRadius.xsR),
                SizedBox(height: 8),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: 0.5,
                  child: Skeleton(height: 12, borderRadius: AppRadius.xsR),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
