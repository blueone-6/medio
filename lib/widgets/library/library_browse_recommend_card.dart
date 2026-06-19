import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/app_config.dart';
import '../../core/tv/tv_image_cache.dart';
import '../../models/emby/emby_media_item.dart';
import '../../providers/emby_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/emby_service.dart';
import '../../utils/media_navigation.dart';
import '../home/recommendation_section.dart';
import '../tv/tv_media_poster_card.dart';

/// 媒体库浏览卡片（全屏库 / TV 网格共用）。
class LibraryBrowseRecommendCard extends ConsumerWidget {
  const LibraryBrowseRecommendCard({
    super.key,
    required this.item,
    required this.usePcRecommendStyle,
    required this.onBrowseIntoFolder,
    this.tvMode = false,
    this.maxPosterHeight,
    this.emby,
  });

  final EmbyMediaItem item;
  final bool usePcRecommendStyle;
  final void Function(EmbyMediaItem folder)? onBrowseIntoFolder;
  final bool tvMode;
  final double? maxPosterHeight;

  /// When set (TV grid), skips per-cell [embyServiceProvider] watch.
  final EmbyService? emby;

  int get _posterRequestHeight {
    if (tvMode && maxPosterHeight != null) {
      return TvImageCache.posterRequestMaxHeight(maxPosterHeight!);
    }
    return AppConfig.posterMaxHeight;
  }

  String? _resolveCategoryImageUrl(EmbyService emby, EmbyMediaItem? seed) {
    final h = _posterRequestHeight;
    final own = emby.libraryCategoryCoverUrl(item, maxHeight: h);
    if (own != null) return own;
    if (seed != null) {
      return emby.posterUrlForItem(seed, maxHeight: h);
    }
    return emby.posterUrl(item.id, maxHeight: h);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final EmbyService emby = this.emby ?? ref.watch(embyServiceProvider);

    if (tvMode && !item.isLibraryBrowseCategory) {
      return TvMediaPosterCard(
        item: item,
        emby: emby,
        maxPosterHeight: maxPosterHeight,
      );
    }

    if (!item.isLibraryBrowseCategory) {
      return _buildCard(
        context,
        emby,
        imageUrl: emby.posterUrlForItem(item, maxHeight: _posterRequestHeight),
      );
    }

    final syncUrl =
        emby.libraryCategoryCoverUrl(item, maxHeight: _posterRequestHeight);
    if (syncUrl != null) {
      return _buildCard(context, emby, imageUrl: syncUrl);
    }

    final coverAsync = ref.watch(embyLibraryCategoryCoverProvider(item.id));
    return coverAsync.when(
      data: (seed) => _buildCard(context, emby, imageUrl: _resolveCategoryImageUrl(emby, seed)),
      loading: () => _buildCard(context, emby, imageUrl: null),
      error: (_, __) => _buildCard(context, emby, imageUrl: null),
    );
  }

  Widget _buildCard(BuildContext context, EmbyService emby, {required String? imageUrl}) {
    return HomeRecommendCard(
      item: item,
      emby: emby,
      imageUrl: imageUrl,
      maxPosterHeight: maxPosterHeight,
      useHomeTypography: tvMode || usePcRecommendStyle,
      tvMode: tvMode,
      showCaption: !tvMode && !usePcRecommendStyle,
      onOpenDetail: () => openLibraryMediaItemDetail(
        context,
        item,
        onBrowseIntoFolder: onBrowseIntoFolder,
      ),
    );
  }
}
