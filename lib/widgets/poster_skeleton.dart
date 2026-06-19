import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_motion.dart';
import '../core/theme/app_radius.dart';

/// 海报区域 shimmer（铺满父级，无圆角裁切）。
///
/// 自制 [LinearGradient] + [AnimationController]，不引入第三方 shimmer 包。
class PosterImageSkeleton extends StatefulWidget {
  const PosterImageSkeleton({super.key});

  @override
  State<PosterImageSkeleton> createState() => _PosterImageSkeletonState();
}

class _PosterImageSkeletonState extends State<PosterImageSkeleton>
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
          final dx = (_controller.value * 2) - 1;
          return DecoratedBox(
            decoration: BoxDecoration(
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

/// 海报骨架（默认 2:3，含标题占位）— 用于网格首屏加载。
class PosterSkeleton extends StatelessWidget {
  const PosterSkeleton({
    super.key,
    this.aspectRatio = 2 / 3,
    this.showTitle = true,
  });

  final double aspectRatio;
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        AspectRatio(
          aspectRatio: aspectRatio,
          child: const DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: AppRadius.mdR,
              color: Colors.transparent,
            ),
            child: PosterImageSkeleton(),
          ),
        ),
        if (showTitle) ...[
          const SizedBox(height: 6),
          const _TitleLineSkeleton(height: 12),
          const SizedBox(height: 4),
          const FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: 0.6,
            child: _TitleLineSkeleton(height: 10),
          ),
        ],
      ],
    );
  }
}

class _TitleLineSkeleton extends StatelessWidget {
  const _TitleLineSkeleton({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: colors.skeletonBase,
        borderRadius: AppRadius.xsR,
      ),
    );
  }
}
