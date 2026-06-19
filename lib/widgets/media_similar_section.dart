import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../models/emby/emby_media_item.dart';
import '../providers/emby_provider.dart';
import '../services/emby_service.dart';
import '../utils/media_navigation.dart';
import 'loading_indicator.dart';
import 'media_card.dart';
import 'media_grid.dart';

class MediaSimilarItemsSliver extends ConsumerWidget {
  const MediaSimilarItemsSliver({super.key, required this.itemId, required this.emby});

  final String itemId;
  final EmbyService emby;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 32),
      sliver: SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('相关影视',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Consumer(
              builder: (ctx, ref, _) {
                final asyncItems = ref.watch(embySimilarItemsProvider(itemId));
                return asyncItems.when(
                  data: (items) {
                    if (items.isEmpty) return const SizedBox.shrink();
                    return _SimilarGrid(items: items, emby: emby);
                  },
                  loading: () => const SizedBox(
                    height: 160,
                    child: LoadingIndicator.posterRow(
                      posterRowHeight: 160,
                      posterRowItemWidth: 96,
                      posterRowItemCount: 5,
                    ),
                  ),
                  error: (_, __) => const SizedBox.shrink(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SimilarGrid extends StatelessWidget {
  const _SimilarGrid({required this.items, required this.emby});

  final List<EmbyMediaItem> items;
  final EmbyService emby;

  static const _ar = 2 / 3;
  static const _minTileW = 108.0;
  static const _spacing = 16.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, constraints) {
      final w = constraints.maxWidth;
      final crossCount = mediaGridCrossAxisCountForWidth(w,
          minTileWidth: _minTileW, spacing: _spacing);
      final tileW = (w - _spacing * (crossCount - 1)) / crossCount;
      final tileH = mediaCardGridCellHeight(
        context,
        tileW,
        discoverStyle: true,
        posterAspectRatio: _ar,
      );

      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossCount,
          mainAxisSpacing: _spacing,
          crossAxisSpacing: _spacing,
          childAspectRatio: tileW / tileH,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          final url =
              emby.posterUrlForItem(item, maxHeight: AppConfig.posterMaxHeight);
          return MediaCard(
            discoverStyle: true,
            posterAspectRatio: _ar,
            embyItem: item,
            title: item.name,
            subtitle:
                item.mediaCardMetaSubtitle(includeTypeFallback: true),
            imageUrl: url,
            httpHeaders: emby.imageAuthHeaders,
            progress: item.userDataPlayedPercentage,
            onOpenDetail: () => playMediaFromCard(context, emby, item),
            onPlay: () => playMediaFromCard(context, emby, item),
          );
        },
      );
    });
  }
}
