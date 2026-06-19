import 'package:flutter/material.dart';

import '../core/theme/app_radius.dart';
import '../core/theme/app_spacing.dart';
import 'home/home_layout.dart';
import 'media_grid.dart';
import 'skeleton.dart';

enum _LoadingMode { spinner, posterGrid, posterRow, list, homeFeed }

/// Loading placeholder — spinner for full-page waits, skeletons for content layouts.
class LoadingIndicator extends StatelessWidget {
  const LoadingIndicator({super.key, this.message})
      : _mode = _LoadingMode.spinner,
        homeRecommendStyle = false,
        pcRecommendStyle = false,
        crossAxisCount = null,
        maxContentWidth = null,
        horizontalPadding = null,
        paddingTop = 8,
        placeholderCount = 12,
        posterRowHeight = 220,
        posterRowItemWidth = 120,
        posterRowItemCount = 6,
        showPosterTitle = true,
        listItemCount = 8;

  const LoadingIndicator.posterGrid({
    super.key,
    this.homeRecommendStyle = false,
    this.pcRecommendStyle = false,
    this.crossAxisCount,
    this.maxContentWidth,
    this.horizontalPadding,
    this.paddingTop = 8,
    this.placeholderCount = 12,
  })  : _mode = _LoadingMode.posterGrid,
        message = null,
        posterRowHeight = 220,
        posterRowItemWidth = 120,
        posterRowItemCount = 6,
        showPosterTitle = true,
        listItemCount = 8;

  const LoadingIndicator.posterRow({
    super.key,
    this.posterRowHeight = 220,
    this.posterRowItemWidth = 120,
    this.posterRowItemCount = 6,
    this.showPosterTitle = true,
  })  : _mode = _LoadingMode.posterRow,
        message = null,
        homeRecommendStyle = false,
        pcRecommendStyle = false,
        crossAxisCount = null,
        maxContentWidth = null,
        horizontalPadding = null,
        paddingTop = 8,
        placeholderCount = 12,
        listItemCount = 8;

  const LoadingIndicator.list({super.key, this.listItemCount = 8})
      : _mode = _LoadingMode.list,
        message = null,
        homeRecommendStyle = false,
        pcRecommendStyle = false,
        crossAxisCount = null,
        maxContentWidth = null,
        horizontalPadding = null,
        paddingTop = 8,
        placeholderCount = 12,
        posterRowHeight = 220,
        posterRowItemWidth = 120,
        posterRowItemCount = 6,
        showPosterTitle = true;

  const LoadingIndicator.homeFeed({super.key})
      : _mode = _LoadingMode.homeFeed,
        message = null,
        homeRecommendStyle = false,
        pcRecommendStyle = false,
        crossAxisCount = null,
        maxContentWidth = null,
        horizontalPadding = null,
        paddingTop = 8,
        placeholderCount = 12,
        posterRowHeight = 220,
        posterRowItemWidth = 120,
        posterRowItemCount = 6,
        showPosterTitle = true,
        listItemCount = 8;

  final String? message;
  final _LoadingMode _mode;
  final bool homeRecommendStyle;
  final bool pcRecommendStyle;
  final int? crossAxisCount;
  final double? maxContentWidth;
  final double? horizontalPadding;
  final double paddingTop;
  final int placeholderCount;
  final double posterRowHeight;
  final double posterRowItemWidth;
  final int posterRowItemCount;
  final bool showPosterTitle;
  final int listItemCount;

  @override
  Widget build(BuildContext context) {
    return switch (_mode) {
      _LoadingMode.spinner => _Spinner(message: message),
      _LoadingMode.posterGrid => MediaGridSkeleton(
          homeRecommendStyle: homeRecommendStyle,
          pcRecommendStyle: pcRecommendStyle,
          crossAxisCount: crossAxisCount,
          maxContentWidth: maxContentWidth,
          horizontalPadding: horizontalPadding,
          paddingTop: paddingTop,
          placeholderCount: placeholderCount,
        ),
      _LoadingMode.posterRow => SizedBox(
          height: posterRowHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: HomeLayout.horizontalMargin),
            itemCount: posterRowItemCount,
            separatorBuilder: (_, __) => const SizedBox(width: HomeLayout.gridGap),
            itemBuilder: (_, __) => SizedBox(
              width: posterRowItemWidth,
              child: PosterSkeleton(showTitle: showPosterTitle),
            ),
          ),
        ),
      _LoadingMode.list => ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          itemCount: listItemCount,
          itemBuilder: (_, __) => const ListTileSkeleton(),
        ),
      _LoadingMode.homeFeed => _HomeFeedSkeleton(),
    };
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          if (message != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(message!, textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }
}

class _HomeFeedSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: HomeLayout.horizontalMargin),
            child: const Skeleton(height: 44, borderRadius: AppRadius.mdR),
          ),
          const SizedBox(height: AppSpacing.lg),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: HomeLayout.horizontalMargin),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Skeleton(borderRadius: HomeLayout.cardRadiusR),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: HomeLayout.horizontalMargin),
            child: Row(
              children: [
                for (var i = 0; i < 2; i++) ...[
                  if (i > 0) const SizedBox(width: AppSpacing.sm),
                  const Expanded(
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Skeleton(borderRadius: AppRadius.mdR),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: HomeLayout.sectionHeaderGap),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: HomeLayout.horizontalMargin),
            child: const Skeleton(height: 16, width: 96, borderRadius: AppRadius.xsR),
          ),
          const SizedBox(height: HomeLayout.sectionHeaderGap),
          const LoadingIndicator.posterRow(),
        ],
      ),
    );
  }
}
