import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../models/emby/emby_media_item.dart';
import '../providers/emby_provider.dart';
import '../services/emby_service.dart';
import '../utils/media_navigation.dart';
import 'media_card.dart';
import 'media_grid.dart';
import 'skeleton.dart';

class MediaSimilarItemsSliver extends ConsumerWidget {
  const MediaSimilarItemsSliver({super.key, required this.itemId, required this.emby});

  final String itemId;
  final EmbyService emby;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 32),
      sliver: SliverToBoxAdapter(
        child: Consumer(
          builder: (ctx, ref, _) {
            final asyncItems = ref.watch(embySimilarItemsProvider(itemId));
            // 相似内容是装饰性区块：没有相似条目或接口失败时整段隐藏
            // （连标题一起），否则页面底部会剩一个孤零零的「相关影视」标题。
            final visible = asyncItems.when(
              data: (items) => items.isNotEmpty,
              loading: () => true,
              error: (_, __) => false,
            );
            if (!visible) return const SizedBox.shrink();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('相关影视',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                asyncItems.when(
                  data: (items) => _SimilarGrid(items: items, emby: emby),
                  loading: () => LayoutBuilder(
                    builder: (ctx, constraints) {
                      const minTileW = 108.0;
                      const spacing = 16.0;
                      const ar = 2 / 3;
                      final crossCount = mediaGridCrossAxisCountForWidth(
                        constraints.maxWidth,
                        minTileWidth: minTileW,
                        spacing: spacing,
                      );
                      final tileW = (constraints.maxWidth -
                              spacing * (crossCount - 1)) /
                          crossCount;
                      final tileH = mediaCardGridCellHeight(
                        ctx,
                        tileW,
                        discoverStyle: true,
                        posterAspectRatio: ar,
                      );
                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        gridDelegate:
                            SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossCount,
                          mainAxisSpacing: spacing,
                          crossAxisSpacing: spacing,
                          childAspectRatio: tileW / tileH,
                        ),
                        itemCount: 6,
                        itemBuilder: (_, __) => const PosterSkeleton(
                          aspectRatio: 2 / 3,
                        ),
                      );
                    },
                  ),
                  // Unreachable: errors already hide the whole section above.
                  error: (_, __) => const SizedBox.shrink(),
                ),
              ],
            );
          },
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
