import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../models/emby/emby_media_item.dart';
import '../../services/emby_service.dart';
import '../../utils/media_navigation.dart';
import '../../utils/user_facing_error.dart';
import '../empty_state_view.dart';
import '../error_view.dart';
import '../skeleton.dart';
import 'glass_surface.dart';
import 'home_layout.dart';
import 'home_section_header.dart';
import 'home_typography.dart';
import 'pc_hover_play_button.dart';

/// 桌面首页「继续观看」：横向 16:9 剧照卡片行，缩略图底部叠进度条，
/// 标题与集数信息在卡片下方（对齐 Hills Lite 方向）。
class ContinueWatchingPcRow extends StatelessWidget {
  const ContinueWatchingPcRow({
    super.key,
    required this.items,
    required this.emby,
    this.onViewAll,
    this.isLoading = false,
    this.loadError,
    this.onRetry,
    this.onOpenSettings,
  });

  final List<EmbyMediaItem> items;
  final EmbyService emby;
  final VoidCallback? onViewAll;
  final bool isLoading;
  final Object? loadError;
  final VoidCallback? onRetry;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeSectionHeader(
          title: '继续观看',
          titleStyle: HomeTypography.headlineLg(
              Theme.of(context).colorScheme.onSurface),
          trailingLabel: onViewAll == null ? null : '查看全部',
          onTrailingTap: onViewAll,
        ),
        const SizedBox(height: HomeLayout.sectionHeaderGap),
        if (isLoading)
          const _ContinueRowSkeleton()
        else if (loadError != null)
          ErrorView.forHomeSection(
            error: loadError!,
            section: HomeLoadSection.resume,
            compact: true,
            onRetry: onRetry!,
            onOpenSettings: onOpenSettings,
          )
        else if (items.isEmpty)
          const EmptyStateView(
            compact: true,
            centered: false,
            icon: Icons.play_circle_outline,
            title: '暂无继续观看',
            subtitle: '开始观看后，进度会显示在这里',
          )
        else
          SizedBox(
            height: _ContinueCard.rowHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(width: HomeLayout.gridGap),
              itemBuilder: (context, i) =>
                  _ContinueCard(item: items[i], emby: emby),
            ),
          ),
      ],
    );
  }
}

class _ContinueRowSkeleton extends StatelessWidget {
  const _ContinueRowSkeleton();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _ContinueCard.rowHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 4,
        separatorBuilder: (_, __) =>
            const SizedBox(width: HomeLayout.gridGap),
        itemBuilder: (_, __) => const SizedBox(
          width: _ContinueCard.thumbWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Skeleton(borderRadius: HomeLayout.cardRadiusR),
              ),
              SizedBox(height: HomeLayout.posterTitleGap),
              Skeleton(height: 14, borderRadius: AppRadius.xsR),
              SizedBox(height: 6),
              Skeleton(height: 10, width: 120, borderRadius: AppRadius.xsR),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContinueCard extends StatefulWidget {
  const _ContinueCard({required this.item, required this.emby});

  static const thumbWidth = 296.0;
  static const _titleH = 20.0;
  static const _subtitleH = 16.0;
  static double get rowHeight =>
      thumbWidth * 9 / 16 +
      HomeLayout.posterTitleGap +
      _titleH +
      2 +
      _subtitleH +
      4;

  final EmbyMediaItem item;
  final EmbyService emby;

  @override
  State<_ContinueCard> createState() => _ContinueCardState();
}

class _ContinueCardState extends State<_ContinueCard> {
  final _hovered = ValueNotifier(false);

  @override
  void dispose() {
    _hovered.dispose();
    super.dispose();
  }

  double? get _fraction {
    final item = widget.item;
    final pct = item.userDataPlayedPercentage;
    if (pct != null) return (pct / 100).clamp(0.0, 1.0);
    final total = item.runTimeTicks;
    final pos = item.userDataPlaybackPositionTicks;
    if (total != null && total > 0 && pos != null) {
      return (pos / total).clamp(0.0, 1.0);
    }
    return null;
  }

  String get _title {
    final item = widget.item;
    if (item.type == 'Episode') {
      final sn = item.seriesName?.trim();
      if (sn != null && sn.isNotEmpty) return sn;
    }
    return item.name;
  }

  String? get _subtitle {
    final item = widget.item;
    if (item.type == 'Episode') {
      final s = item.parentIndexNumber;
      final e = item.indexNumber;
      final parts = <String>[
        if (s != null && e != null) 'S${s}E$e',
        item.name,
      ];
      return parts.isEmpty ? null : parts.join(' · ');
    }
    if (item.productionYear != null) return '${item.productionYear}';
    return item.remainingWatchLabel;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final colors = context.appColors;
    final item = widget.item;
    final emby = widget.emby;
    final url = emby.backdropUrlForItem(item, maxWidth: 640) ??
        emby.posterUrlForItem(item, maxHeight: 200);
    final fraction = _fraction;
    final subtitle = _subtitle;

    return SizedBox(
      width: _ContinueCard.thumbWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MouseRegion(
            onEnter: (_) => _hovered.value = true,
            onExit: (_) => _hovered.value = false,
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: GlassSurface(
                padding: EdgeInsets.zero,
                clipChild: false,
                rimBorder: true,
                useBlur: false,
                onTap: () => playMediaFromCard(context, emby, item),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    HoverAnimatedBackground(
                      hovered: _hovered,
                      image: _ThumbImage(
                          url: url, headers: emby.imageAuthHeaders),
                      scrim: null,
                      restOpacity:
                          HomeGlassTokens.mediaRestOpacity(cs, 0.85),
                      hoverOpacity: 1.0,
                      restDarken: 0.05,
                      hoverDarken: 0.0,
                    ),
                    if (fraction != null)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: SizedBox(
                          height: HomeLayout.pcProgressBarHeight,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ColoredBox(
                                color: Colors.black
                                    .withValues(alpha: 0.45),
                              ),
                              FractionallySizedBox(
                                alignment: Alignment.centerLeft,
                                widthFactor:
                                    fraction.clamp(0.0, 1.0),
                                child: ColoredBox(
                                    color: colors.progressActive),
                              ),
                            ],
                          ),
                        ),
                      ),
                    Center(
                      child: ValueListenableBuilder<bool>(
                        valueListenable: _hovered,
                        builder: (_, hovered, __) => PcHoverPlayButton(
                          visible: hovered,
                          onTap: () =>
                              playMediaFromCard(context, emby, item),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: HomeLayout.posterTitleGap),
          GestureDetector(
            onTap: () => openHomeMediaItemDetail(context, item),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      HomeTypography.bodyMdSemibold(cs.onSurface),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: HomeTypography.labelSm(cs.onSurfaceVariant),
                  ),
                ],
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
        filterQuality: FilterQuality.medium,
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
