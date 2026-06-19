import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/tv/tv_image_cache.dart';
import '../../models/emby/emby_media_item.dart';
import '../../services/emby_service.dart';
import '../home/glass_surface.dart';
import '../home/home_layout.dart';
import '../home/home_media_type_badge.dart';
import '../home/home_typography.dart';
import '../home/poster_genre_meta.dart';

/// Lean TV poster card — no hover controllers, no MouseRegion.
class TvMediaPosterCard extends StatelessWidget {
  const TvMediaPosterCard({
    super.key,
    required this.item,
    required this.emby,
    this.imageUrl,
    this.maxPosterHeight,
    this.showTitleOverlay = true,
  });

  final EmbyMediaItem item;
  final EmbyService emby;
  final String? imageUrl;
  final double? maxPosterHeight;
  final bool showTitleOverlay;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        var posterW = constraints.maxWidth;
        var posterH = posterW / HomeLayout.recommendPosterAspectRatio;
        final cap = maxPosterHeight;
        if (cap != null && posterH > cap) {
          posterH = cap;
          posterW = posterH * HomeLayout.recommendPosterAspectRatio;
        }

        final requestH = TvImageCache.posterRequestMaxHeight(posterH);
        final url = imageUrl ??
            emby.posterUrlForItem(item, maxHeight: requestH);
        final memCacheH = TvImageCache.memCachePosterHeightPx(context, posterH);
        final memCacheW = TvImageCache.memCachePosterWidthPx(context, posterH);

        return SizedBox(
          width: posterW,
          height: posterH,
          child: GlassSurface(
            padding: EdgeInsets.zero,
            clipChild: false,
            rimBorder: true,
            useBlur: false,
            borderRadius: HomeLayout.posterRadiusR,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _TvPosterImage(
                  url: url,
                  headers: emby.imageAuthHeaders,
                  memCacheWidth: memCacheW,
                  memCacheHeight: memCacheH,
                ),
                DecoratedBox(
                  decoration:
                      homeMediaBackdropScrim(HomeMediaScrimShape.poster),
                ),
                ColoredBox(
                  color: Colors.black.withValues(
                    alpha: HomeGlassTokens.mediaUniformDarken(
                      cs,
                      HomeLayout.pcRecommendUniformDarken,
                    ),
                  ),
                ),
                Positioned(
                  top: HomeLayout.pcRecommendBadgeInset,
                  left: HomeLayout.pcRecommendBadgeInset,
                  child: HomeMediaTypeBadge(label: item.mediaTypeLabel),
                ),
                if (item.mediaCardRatingText != null)
                  Positioned(
                    top: HomeLayout.pcRecommendBadgeInset,
                    right: HomeLayout.pcRecommendBadgeInset,
                    child: HomeRatingBadge(
                      label: item.mediaCardRatingText!,
                      showStar: true,
                    ),
                  ),
                if (showTitleOverlay) _TvPosterTitleOverlay(item: item),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TvPosterTitleOverlay extends StatelessWidget {
  const _TvPosterTitleOverlay({required this.item});

  final EmbyMediaItem item;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.vertical(
            bottom: Radius.circular(HomeLayout.posterRadius),
          ),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.black.withValues(alpha: 0.55),
              Colors.black.withValues(alpha: 0.88),
            ],
            stops: const [0.0, 0.45, 1.0],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            HomeLayout.pcRecommendFooterPadding,
            20,
            HomeLayout.pcRecommendFooterPadding,
            HomeLayout.pcRecommendFooterPadding,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                item.mediaCardDisplayTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: HomeTypography.bodyMdSemibold(
                  HomeGlassTokens.backdropTitleForeground(cs),
                ),
              ),
              const SizedBox(height: 2),
              PosterGenreMeta(
                item: item,
                metaColor: HomeGlassTokens.backdropMetaForeground(cs),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TvPosterImage extends StatelessWidget {
  const _TvPosterImage({
    required this.url,
    this.headers,
    this.memCacheWidth,
    this.memCacheHeight,
  });

  final String? url;
  final Map<String, String>? headers;
  final int? memCacheWidth;
  final int? memCacheHeight;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (url != null && url!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: url!,
        httpHeaders: headers,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.low,
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        memCacheWidth: memCacheWidth,
        memCacheHeight: memCacheHeight,
        width: double.infinity,
        height: double.infinity,
        errorWidget: (_, __, ___) => ColoredBox(
          color: cs.surfaceContainerHighest,
          child: Icon(Icons.movie, color: cs.outline, size: 28),
        ),
      );
    }
    return ColoredBox(
      color: cs.surfaceContainerHighest,
      child: Icon(Icons.movie, color: cs.outline, size: 28),
    );
  }
}
