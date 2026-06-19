import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_radius.dart';
import '../core/theme/app_text.dart';
import '../models/emby/emby_media_item.dart';

/// 媒体规格徽章类型（4K / HDR / Dolby Vision / Atmos）。
enum MediaSpecBadge { uhd4k, hdr, dolbyVision, atmos }

/// 媒体规格徽章组（叠加在海报右下角）。
///
/// 颜色取自 [AppColors] 令牌（对齐主流播放器规范色）。数据解析（从
/// Emby MediaStreams 提取分辨率/HDR/Atmos）属于 F-C2 范畴，本组件仅负责渲染。
class MediaBadges extends StatelessWidget {
  const MediaBadges({super.key, required this.badges, this.compact = false});

  final List<MediaSpecBadge> badges;

  /// 紧凑模式（网格小卡）：更小内边距。
  final bool compact;

  static String _label(MediaSpecBadge b) {
    switch (b) {
      case MediaSpecBadge.uhd4k:
        return '4K';
      case MediaSpecBadge.hdr:
        return 'HDR';
      case MediaSpecBadge.dolbyVision:
        return 'DV';
      case MediaSpecBadge.atmos:
        return 'ATMOS';
    }
  }

  static Color _bg(AppColors c, MediaSpecBadge b) {
    switch (b) {
      case MediaSpecBadge.uhd4k:
        return c.badge4k;
      case MediaSpecBadge.hdr:
        return c.badgeHdr;
      case MediaSpecBadge.dolbyVision:
        return c.badgeDolbyVision;
      case MediaSpecBadge.atmos:
        return c.badgeAtmos;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (badges.isEmpty) return const SizedBox.shrink();
    final colors = context.appColors;
    final style = AppTextStyles.badge(context).copyWith(color: colors.badgeForeground);
    final pad = compact
        ? const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5)
        : const EdgeInsets.symmetric(horizontal: 5, vertical: 2.5);
    return Wrap(
      spacing: 3,
      runSpacing: 3,
      children: [
        for (final b in badges)
          DecoratedBox(
            decoration: BoxDecoration(
              color: _bg(colors, b),
              borderRadius: AppRadius.xsR,
            ),
            child: Padding(
              padding: pad,
              child: Text(_label(b), style: style),
            ),
          ),
      ],
    );
  }
}

/// 从 [EmbyMediaItem] 预解析的流信息推导规格徽章（列表/详情共用，不调 PlaybackInfo）。
extension EmbyMediaItemSpecBadges on EmbyMediaItem {
  List<MediaSpecBadge> get mediaSpecBadges {
    final out = <MediaSpecBadge>[];
    if (isUhd4k) out.add(MediaSpecBadge.uhd4k);
    if (isDolbyVision) {
      out.add(MediaSpecBadge.dolbyVision);
    } else if (isHdr) {
      out.add(MediaSpecBadge.hdr);
    }
    if (isAtmos) out.add(MediaSpecBadge.atmos);
    return out;
  }
}
