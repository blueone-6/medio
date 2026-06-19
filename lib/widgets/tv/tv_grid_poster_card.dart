import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/tv/tv_image_cache.dart';
import '../../models/emby/emby_media_item.dart';
import '../../services/emby_service.dart';
import '../home/home_typography.dart';
import 'tv_home_layout.dart';

/// Ultra-lean TV browse-grid poster — no glass stack, title below image.
class TvGridPosterCard extends StatelessWidget {
  const TvGridPosterCard({
    super.key,
    required this.item,
    required this.emby,
    required this.posterWidth,
    required this.posterHeight,
  });

  final EmbyMediaItem item;
  final EmbyService emby;
  final double posterWidth;
  final double posterHeight;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final requestH = TvImageCache.posterRequestMaxHeight(posterHeight);
    final url = emby.posterUrlForItem(item, maxHeight: requestH);
    final memCacheH = TvImageCache.memCachePosterHeightPx(context, posterHeight);
    final memCacheW = TvImageCache.memCachePosterWidthPx(context, posterHeight);

    return SizedBox(
      width: posterWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: posterWidth,
            height: posterHeight,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(TvHomeLayout.cardRadius),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.35),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(TvHomeLayout.cardRadius),
                child: url != null && url.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: url,
                        httpHeaders: emby.imageAuthHeaders,
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.low,
                        fadeInDuration: Duration.zero,
                        fadeOutDuration: Duration.zero,
                        memCacheWidth: memCacheW,
                        memCacheHeight: memCacheH,
                        width: posterWidth,
                        height: posterHeight,
                        errorWidget: (_, __, ___) => _placeholder(cs),
                      )
                    : _placeholder(cs),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.mediaCardDisplayTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: HomeTypography.captionXs(cs.onSurface),
          ),
        ],
      ),
    );
  }

  Widget _placeholder(ColorScheme cs) {
    return ColoredBox(
      color: cs.surfaceContainerHighest,
      child: Icon(Icons.movie, color: cs.outline, size: 28),
    );
  }
}
