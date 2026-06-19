import 'package:flutter/material.dart';

import '../../models/emby/emby_media_item.dart';
import 'home_typography.dart';

/// Poster footer: up to two genre labels (媒体类型由左上角角标展示).
class PosterGenreMeta extends StatelessWidget {
  const PosterGenreMeta({
    super.key,
    required this.item,
    required this.metaColor,
    this.maxGenres = 2,
  });

  final EmbyMediaItem item;
  final Color metaColor;
  final int maxGenres;

  @override
  Widget build(BuildContext context) {
    final labels = item.mediaCardGenreLabels(max: maxGenres);
    if (labels == null) return const SizedBox.shrink();

    return Text(
      labels,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: HomeTypography.captionXs(metaColor),
    );
  }
}
