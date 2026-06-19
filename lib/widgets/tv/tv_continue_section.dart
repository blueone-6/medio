import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../config/app_config.dart';
import '../../core/tv/tv_image_cache.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../models/emby/emby_media_item.dart';
import '../../services/emby_service.dart';
import '../../utils/media_navigation.dart';
import '../empty_state_view.dart';
import '../home/glass_surface.dart';
import '../home/home_layout.dart';
import '../home/home_media_type_badge.dart';
import '../home/home_typography.dart';
import 'tv_focus_ring.dart';
import 'tv_home_layout.dart';

class TvContinueSection extends StatelessWidget {
  const TvContinueSection({
    super.key,
    required this.items,
    required this.emby,
    this.autofocusHero = false,
    this.onViewAll,
  });

  final List<EmbyMediaItem> items;
  final EmbyService emby;
  final bool autofocusHero;
  final VoidCallback? onViewAll;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      final cs = Theme.of(context).colorScheme;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TvContinueSectionHeader(
            viewportWidth: TvHomeLayout.viewportWidthOf(context),
            onViewAll: onViewAll,
          ),
          SizedBox(height: TvHomeLayout.sectionHeaderGapFor(TvHomeLayout.viewportWidthOf(context))),
          EmptyStateView(
            compact: true,
            centered: false,
            icon: Icons.play_circle_outline,
            title: '暂无继续观看',
            subtitle: '开始观看后，进度会显示在这里',
            titleStyle: HomeTypography.bodyMd(cs.onSurfaceVariant),
            subtitleStyle: HomeTypography.bodyMd(cs.onSurfaceVariant.withValues(alpha: 0.8)),
          ),
        ],
      );
    }

    final viewportW = TvHomeLayout.viewportWidthOf(context);
    final featured = items.first;
    final secondary = items.length > 1
        ? items.sublist(1, items.length.clamp(1, 3))
        : <EmbyMediaItem>[];

    final viewportH = MediaQuery.sizeOf(context).height;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final hasSecondary = secondary.isNotEmpty;
        // TV: mirror PC — hero + secondary column side-by-side when possible.
        final wide = hasSecondary && maxW >= 640;
        final heroContentW =
            wide ? (maxW - HomeLayout.gridGap) * 2 / 3 : maxW;
        final sectionGap = TvHomeLayout.sectionHeaderGapFor(viewportW);

        Widget content;
        if (!wide) {
          content = LayoutBuilder(
            builder: (context, constraints) {
              final maxH = TvHomeLayout.continueSingleHeroMaxHeight(viewportH);
              final rowH = math.min(
                constraints.maxWidth / HomeLayout.pcHeroAspectRatio,
                maxH,
              );
              return SizedBox(
                height: rowH,
                child: _TvContinueHero(
                  item: featured,
                  emby: emby,
                  autofocus: autofocusHero,
                  expandToFill: true,
                  viewportWidth: viewportW,
                ),
              );
            },
          );
        } else {
          final secondaryMinH = TvHomeLayout.scaled(112, viewportW);
          final columnMinH = secondary.length * secondaryMinH +
              (secondary.length - 1) * HomeLayout.gridGap;
          final resolvedRowHeight = TvHomeLayout.continueWideRowHeightFor(
            heroContentWidth: heroContentW,
            viewportHeight: viewportH,
            secondaryColumnMinHeight: columnMinH,
          );

          content = SizedBox(
            height: resolvedRowHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 2,
                  child: _TvContinueHero(
                    item: featured,
                    emby: emby,
                    autofocus: autofocusHero,
                    expandToFill: true,
                    viewportWidth: viewportW,
                  ),
                ),
                const SizedBox(width: HomeLayout.gridGap),
                Expanded(
                  child: Column(
                    children: [
                      for (var i = 0; i < secondary.length; i++) ...[
                        if (i > 0) const SizedBox(height: HomeLayout.gridGap),
                        Expanded(
                          child: _TvSecondaryContinueCard(
                            item: secondary[i],
                            emby: emby,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TvContinueSectionHeader(
              viewportWidth: viewportW,
              onViewAll: onViewAll,
            ),
            SizedBox(height: sectionGap),
            content,
          ],
        );
      },
    );
  }
}

class _TvContinueSectionHeader extends StatelessWidget {
  const _TvContinueSectionHeader({
    required this.viewportWidth,
    this.onViewAll,
  });

  final double viewportWidth;
  final VoidCallback? onViewAll;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sectionTitleSize = TvHomeLayout.sectionTitleSizeFor(viewportWidth);
    final titleStyle = HomeTypography.headlineLg(cs.onSurface).copyWith(
      fontSize: sectionTitleSize,
      height: TvHomeLayout.sectionTitleLineHeightFor(
        viewportWidth,
        sectionTitleSize,
      ),
    );
    final linkStyle = HomeTypography.labelSm(
      cs.onSurfaceVariant.withValues(alpha: 0.8),
    ).copyWith(letterSpacing: 0.8);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(
          child: Text(
            '继续观看',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: titleStyle.copyWith(height: 1.0),
            textHeightBehavior: TvHomeLayout.sectionHeaderTextBehavior,
          ),
        ),
        if (onViewAll != null)
          TvFocusRing(
            onActivate: onViewAll!,
            scaleFocused: false,
            borderRadius: 8,
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '查看全部',
                    style: linkStyle.copyWith(height: 1.0),
                    textHeightBehavior: TvHomeLayout.sectionHeaderTextBehavior,
                  ),
                  Icon(Icons.chevron_right, size: 16, color: linkStyle.color),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Opaque media rim — same as PC continue cards and TV recommend posters.
class _TvContinueCardFrame extends StatelessWidget {
  const _TvContinueCardFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      padding: EdgeInsets.zero,
      clipChild: false,
      rimBorder: true,
      useBlur: false,
      borderRadius: BorderRadius.circular(TvHomeLayout.cardRadius),
      child: child,
    );
  }
}

class _TvSecondaryContinueCard extends StatelessWidget {
  const _TvSecondaryContinueCard({
    required this.item,
    required this.emby,
  });

  final EmbyMediaItem item;
  final EmbyService emby;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final url = emby.backdropUrlForItem(
          item,
          maxWidth: TvImageCache.backdropRequestMaxWidth,
          maxHeight: TvImageCache.backdropRequestMaxHeight,
        ) ??
        emby.posterUrlForItem(item, maxHeight: 200);
    final fraction = _playedFraction(item);
    final compact = _secondaryProgressLine(item);

    return TvFocusRing(
      onActivate: () => playMediaFromCard(context, emby, item),
      borderRadius: TvHomeLayout.cardRadius,
      child: _TvContinueCardFrame(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final tight = constraints.maxHeight < 96;
            final overlayPadding = EdgeInsets.all(
              tight ? 10 : HomeLayout.pcSecondaryContentPadding,
            );
            final viewportW = TvHomeLayout.viewportWidthOf(context);
            final titleStyle = HomeTypography.headlineMd(
              HomeGlassTokens.backdropTitleForeground(cs),
            ).copyWith(
              fontSize: tight
                  ? TvHomeLayout.scaled(18, viewportW)
                  : TvHomeLayout.scaled(22, viewportW),
              height: 1.2,
            );

          return Stack(
            fit: StackFit.expand,
            children: [
              _HeroImage(
                url: url,
                headers: emby.imageAuthHeaders,
                memCacheWidth:
                    TvImageCache.memCachePx(context, constraints.maxWidth),
                memCacheHeight:
                    TvImageCache.memCachePx(context, constraints.maxHeight),
              ),
              DecoratedBox(
                decoration: homeMediaBackdropScrim(HomeMediaScrimShape.secondary),
              ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Padding(
                    padding: overlayPadding,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _heroTitle(item),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: titleStyle,
                        ),
                        if (compact != null) ...[
                          SizedBox(
                            height: tight
                                ? 2
                                : HomeLayout.pcSecondaryTitleMetaGap,
                          ),
                          Text(
                            compact,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: HomeTypography.captionXs(
                              HomeGlassTokens.backdropMetaForeground(cs),
                            ).copyWith(
                              fontSize: tight
                                  ? TvHomeLayout.scaled(11, viewportW)
                                  : TvHomeLayout.scaled(12, viewportW),
                            ),
                          ),
                        ],
                        if (fraction != null) ...[
                          SizedBox(
                            height: tight
                                ? HomeLayout.pcSecondaryTitleMetaGap
                                : HomeLayout.pcSecondaryMetaProgressGap,
                          ),
                          _TvSecondaryProgressBar(value: fraction),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TvSecondaryProgressBar extends StatelessWidget {
  const _TvSecondaryProgressBar({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: AppRadius.pillR,
      child: SizedBox(
        height: HomeLayout.pcProgressBarHeight,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: HomeGlassTokens.backdropProgressTrack(cs)),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: value.clamp(0.0, 1.0),
              child: ColoredBox(
                color: cs.primary,
                child: const SizedBox.expand(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TvContinueHero extends StatelessWidget {
  const _TvContinueHero({
    required this.item,
    required this.emby,
    required this.viewportWidth,
    this.autofocus = false,
    this.expandToFill = false,
  });

  final EmbyMediaItem item;
  final EmbyService emby;
  final double viewportWidth;
  final bool autofocus;
  final bool expandToFill;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final url = emby.backdropUrlForItem(
          item,
          maxWidth: TvImageCache.backdropRequestMaxWidth,
          maxHeight: TvImageCache.backdropRequestMaxHeight,
        ) ??
        emby.posterUrlForItem(item, maxHeight: AppConfig.posterMaxHeight);
    final fraction = _playedFraction(item);
    final progressLine = item.continueWatchingProgressLine;
    final remaining = item.remainingWatchLabel;

    final metaParts = <String>[];
    if (progressLine != null) metaParts.add(progressLine);
    if (remaining != null &&
        (progressLine == null || !progressLine.contains(remaining))) {
      metaParts.add(remaining);
    }

    final content = LayoutBuilder(
        builder: (context, constraints) {
          final tight = constraints.maxHeight < 200;
          final overlayPadding = EdgeInsets.all(
            tight ? 16 : HomeLayout.pcHeroContentPadding,
          );
          final titleSize = tight
              ? TvHomeLayout.scaled(30, viewportWidth)
              : TvHomeLayout.continueHeroTitleSizeFor(viewportWidth);

          return Stack(
            fit: StackFit.expand,
            children: [
              _HeroImage(
                url: url,
                headers: emby.imageAuthHeaders,
                memCacheWidth:
                    TvImageCache.memCachePx(context, constraints.maxWidth),
                memCacheHeight:
                    TvImageCache.memCachePx(context, constraints.maxHeight),
              ),
              DecoratedBox(
                decoration: homeMediaBackdropScrim(HomeMediaScrimShape.hero),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Padding(
                  padding: overlayPadding,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!tight) ...[
                        HomeMediaTypeBadge(label: item.mediaTypeLabel),
                        const SizedBox(height: HomeLayout.pcHeroBadgeTitleGap),
                      ],
                      Text(
                        _heroTitle(item),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: HomeTypography.displayLg(
                          HomeGlassTokens.backdropTitleForeground(cs),
                        ).copyWith(
                          fontSize: titleSize,
                          height: HomeLayout.pcHeroTitleLineHeight,
                        ),
                      ),
                      if (metaParts.isNotEmpty) ...[
                        SizedBox(
                          height: tight
                              ? 2
                              : HomeLayout.pcHeroTitleMetaGap,
                        ),
                        Text(
                          metaParts.join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: HomeTypography.bodyMd(
                            HomeGlassTokens.backdropMetaForeground(cs),
                          ),
                        ),
                      ],
                      if (fraction != null) ...[
                        SizedBox(
                          height: tight
                              ? 8
                              : HomeLayout.pcHeroMetaProgressGap,
                        ),
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: HomeLayout.pcHeroProgressMaxWidth,
                          ),
                          child: _TvSecondaryProgressBar(value: fraction),
                        ),
                        SizedBox(
                          height: tight
                              ? 10
                              : HomeLayout.pcHeroProgressButtonGap,
                        ),
                      ] else if (metaParts.isNotEmpty) ...[
                        SizedBox(
                          height: tight
                              ? 10
                              : HomeLayout.pcHeroMetaProgressGap,
                        ),
                      ],
                      Row(
                        children: [
                          _TvActionButton(
                            label: '播放',
                            filled: true,
                            autofocus: autofocus,
                            compact: tight,
                            onActivate: () =>
                                playMediaFromCard(context, emby, item),
                          ),
                          SizedBox(
                            width: tight ? 8 : HomeLayout.pcActionButtonGap,
                          ),
                          _TvActionButton(
                            label: '详情',
                            filled: false,
                            onBackdrop: true,
                            compact: tight,
                            onActivate: () =>
                                openHomeMediaItemDetail(context, item),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      );

    return _TvContinueCardFrame(
      child: expandToFill
          ? content
          : AspectRatio(
              aspectRatio: HomeLayout.pcHeroAspectRatio,
              child: content,
            ),
    );
  }
}

class _TvActionButton extends StatefulWidget {
  const _TvActionButton({
    required this.label,
    required this.filled,
    required this.onActivate,
    this.autofocus = false,
    this.compact = false,
    this.onBackdrop = false,
  });

  final String label;
  final bool filled;
  final VoidCallback onActivate;
  final bool autofocus;
  final bool compact;
  final bool onBackdrop;

  @override
  State<_TvActionButton> createState() => _TvActionButtonState();
}

class _TvActionButtonState extends State<_TvActionButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final colors = context.appColors;
    final filled = widget.filled;
    final focused = _focused;

    final Color bg;
    final Color fg;
    final Border? border;

    if (filled) {
      bg = focused ? colors.playAction.withValues(alpha: 0.88) : colors.playAction;
      fg = colors.onPlayAction;
      border = null;
    } else if (widget.onBackdrop) {
      bg = focused
          ? Colors.white.withValues(alpha: 0.22)
          : HomeGlassTokens.backdropGlassButtonFill(cs);
      fg = HomeGlassTokens.backdropGlassButtonLabel(cs);
      border = Border.all(color: HomeGlassTokens.backdropGlassButtonBorder(cs));
    } else if (focused) {
      bg = cs.onSurface.withValues(alpha: 0.18);
      fg = cs.onSurface;
      border = null;
    } else {
      bg = cs.onSurface.withValues(alpha: 0.1);
      fg = cs.onSurface;
      border = Border.all(color: cs.onSurface.withValues(alpha: 0.1));
    }

    final child = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: widget.compact ? 16 : 24,
        vertical: widget.compact ? 8 : 10,
      ),
      child: Text(
        widget.label,
        style: HomeTypography.labelSm(fg, fontWeight: FontWeight.w700),
      ),
    );

    return TvFocusRing(
      autofocus: widget.autofocus,
      onActivate: widget.onActivate,
      onFocusChange: (f) => setState(() => _focused = f),
      borderRadius: 999,
      scaleFocused: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: AppRadius.pillR,
          border: border,
        ),
        child: child,
      ),
    );
  }
}

class _HeroImage extends StatelessWidget {
  const _HeroImage({
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
        filterQuality: FilterQuality.medium,
        memCacheWidth: memCacheWidth,
        memCacheHeight: memCacheHeight,
        errorWidget: (_, __, ___) => ColoredBox(color: cs.surfaceContainerHigh),
      );
    }
    return ColoredBox(color: cs.surfaceContainerHigh);
  }
}

double? _playedFraction(EmbyMediaItem item) {
  final pct = item.userDataPlayedPercentage;
  if (pct != null) return (pct / 100).clamp(0.0, 1.0);
  final total = item.runTimeTicks;
  final pos = item.userDataPlaybackPositionTicks;
  if (total != null && total > 0 && pos != null) {
    return (pos / total).clamp(0.0, 1.0);
  }
  return null;
}

String _heroTitle(EmbyMediaItem item) {
  if (item.type == 'Episode') {
    final sn = item.seriesName?.trim();
    if (sn != null && sn.isNotEmpty) {
      final p = item.parentIndexNumber;
      if (p != null) return '$sn · S$p';
      return sn;
    }
  }
  return item.name;
}

String? _secondaryProgressLine(EmbyMediaItem item) =>
    item.continueWatchingCompactProgressLine ?? item.continueWatchingShortProgressLine;
