import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../config/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../models/emby/emby_media_item.dart';
import '../../services/emby_service.dart';
import '../../utils/media_navigation.dart';
import '../empty_state_view.dart';
import 'glass_surface.dart';
import 'home_layout.dart';
import 'home_section_header.dart';

class ContinueWatchingSection extends StatelessWidget {
  const ContinueWatchingSection({
    super.key,
    required this.items,
    required this.emby,
    this.compact = false,
    this.onViewAll,
  });

  final List<EmbyMediaItem> items;
  final EmbyService emby;
  final bool compact;
  final VoidCallback? onViewAll;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: HomeLayout.horizontalMargin),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            HomeSectionHeader(
              title: '继续观看',
              trailingLabel: onViewAll == null ? null : '全部',
              onTrailingTap: onViewAll,
            ),
            const SizedBox(height: HomeLayout.sectionHeaderGap),
            const EmptyStateView(
              compact: true,
              centered: false,
              icon: Icons.play_circle_outline,
              title: '暂无继续观看',
              subtitle: '开始观看后，进度会显示在这里',
            ),
          ],
        ),
      );
    }

    final featured = items.first;
    final secondary = items.length > 1 ? items.sublist(1, items.length.clamp(1, 3)) : <EmbyMediaItem>[];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: HomeLayout.horizontalMargin),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HomeSectionHeader(
            title: '继续观看',
            trailingLabel: onViewAll == null ? null : '全部',
            onTrailingTap: onViewAll,
          ),
          const SizedBox(height: HomeLayout.sectionHeaderGap),
          _FeaturedContinueCard(item: featured, emby: emby),
          if (secondary.isNotEmpty) ...[
            const SizedBox(height: HomeLayout.sectionInnerGap),
            Row(
              children: [
                for (var i = 0; i < secondary.length; i++) ...[
                  if (i > 0) const SizedBox(width: AppSpacing.sm),
                  Expanded(child: _SecondaryContinueCard(item: secondary[i], emby: emby)),
                ],
                if (secondary.length == 1) const Expanded(child: SizedBox()),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _FeaturedContinueCard extends StatelessWidget {
  const _FeaturedContinueCard({required this.item, required this.emby});

  final EmbyMediaItem item;
  final EmbyService emby;

  String? _thumbUrl() {
    return emby.backdropUrlForItem(item) ?? emby.posterUrlForItem(item, maxHeight: AppConfig.posterMaxHeight);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final url = _thumbUrl();
    final titleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          height: 28 / 20,
        );

    return GlassSurface(
      padding: const EdgeInsets.all(HomeLayout.cardPadding),
      useBlur: false,
      onTap: () => openHomeMediaItemDetail(context, item),
      child: Stack(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                flex: HomeLayout.featuredThumbFlex,
                child: ClipRRect(
                  borderRadius: HomeLayout.thumbRadiusR,
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: _ThumbImage(url: url, headers: emby.imageAuthHeaders),
                  ),
                ),
              ),
              const SizedBox(width: HomeLayout.sectionHeaderGap),
              Expanded(
                flex: HomeLayout.featuredBodyFlex,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, AppSpacing.xs, 52, AppSpacing.xs),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 2),
                        decoration: BoxDecoration(
                          color: cs.onSurface.withValues(alpha: 0.1),
                          borderRadius: AppRadius.xsR,
                        ),
                        child: Text(
                          '${item.mediaTypeLabel} · 继续播放',
                          style: AppTextStyles.badge(context).copyWith(
                            fontSize: 10,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        item.mediaCardSeriesSeasonLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: titleStyle,
                      ),
                      if (item.continueWatchingProgressLine != null) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          item.continueWatchingProgressLine!,
                          style: AppTextStyles.cardMeta(context).copyWith(
                            fontSize: 12,
                            color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                      if (item.remainingWatchLabel != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          item.remainingWatchLabel!,
                          style: AppTextStyles.cardMeta(context).copyWith(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            right: AppSpacing.sm,
            bottom: AppSpacing.sm,
            child: Material(
              color: context.appColors.playAction,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => playMediaFromCard(context, emby, item),
                customBorder: const CircleBorder(),
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(
                    Icons.play_arrow_rounded,
                    color: context.appColors.onPlayAction,
                    size: 26,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SecondaryContinueCard extends StatelessWidget {
  const _SecondaryContinueCard({required this.item, required this.emby});

  final EmbyMediaItem item;
  final EmbyService emby;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final url = emby.backdropUrlForItem(item) ?? emby.posterUrlForItem(item, maxHeight: 120);

    return GlassSurface(
      padding: const EdgeInsets.all(HomeLayout.cardPadding),
      useBlur: false,
      onTap: () => playMediaFromCard(context, emby, item),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: HomeLayout.smallThumbRadiusR,
            child: SizedBox(
              width: 64,
              height: 40,
              child: _ThumbImage(url: url, headers: emby.imageAuthHeaders),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.mediaCardSeriesSeasonLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.cardSubtitle(context).copyWith(fontSize: 12),
                ),
                if (item.continueWatchingCompactProgressLine != null)
                  Text(
                    item.continueWatchingCompactProgressLine!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.cardMeta(context).copyWith(
                      fontSize: 10,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ThumbImage extends StatelessWidget {
  const _ThumbImage({required this.url, this.headers});

  final String? url;
  final Map<String, String>? headers;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (url != null && url!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: url!,
        httpHeaders: headers,
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => ColoredBox(
          color: cs.surfaceContainerHighest,
          child: Icon(Icons.movie, color: cs.outline, size: 24),
        ),
      );
    }
    return ColoredBox(
      color: cs.surfaceContainerHighest,
      child: Icon(Icons.movie, color: cs.outline, size: 24),
    );
  }
}
