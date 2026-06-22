import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../config/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../models/emby/emby_media_item.dart';
import '../../services/emby_service.dart';
import '../../utils/media_navigation.dart';
import '../empty_state_view.dart';
import '../error_view.dart';
import '../skeleton.dart';
import '../../utils/user_facing_error.dart';
import 'glass_surface.dart';
import 'home_layout.dart';
import 'home_media_type_badge.dart';
import 'home_section_header.dart';
import 'home_typography.dart';
import 'pc_hover_play_button.dart';

class ContinueWatchingPcSection extends StatelessWidget {
  const ContinueWatchingPcSection({
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
    if (isLoading) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PcSectionHeader(onViewAll: onViewAll),
          const SizedBox(height: HomeLayout.sectionHeaderGap),
          const _PcContinueWatchingSkeleton(),
        ],
      );
    }

    if (loadError != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PcSectionHeader(onViewAll: onViewAll),
          const SizedBox(height: HomeLayout.sectionHeaderGap),
          ErrorView.forHomeSection(
            error: loadError!,
            section: HomeLoadSection.resume,
            compact: true,
            onRetry: onRetry!,
            onOpenSettings: onOpenSettings,
          ),
        ],
      );
    }

    if (items.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PcSectionHeader(onViewAll: onViewAll),
          const SizedBox(height: HomeLayout.sectionHeaderGap),
          const EmptyStateView(
            compact: true,
            centered: false,
            icon: Icons.play_circle_outline,
            title: '暂无继续观看',
            subtitle: '开始观看后，进度会显示在这里',
          ),
        ],
      );
    }

    final featured = items.first;
    final secondary = items.length > 1 ? items.sublist(1, items.length.clamp(1, 3)) : <EmbyMediaItem>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PcSectionHeader(onViewAll: onViewAll),
        const SizedBox(height: HomeLayout.sectionHeaderGap),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            if (!wide) {
              return Column(
                children: [
                  _PcHeroCard(item: featured, emby: emby),
                  if (secondary.isNotEmpty) ...[
                    const SizedBox(height: HomeLayout.gridGap),
                    for (var i = 0; i < secondary.length; i++) ...[
                      if (i > 0) const SizedBox(height: HomeLayout.gridGap),
                      SizedBox(
                        height: 160,
                        child: _PcSecondaryCard(item: secondary[i], emby: emby),
                      ),
                    ],
                  ],
                ],
              );
            }

            const gap = HomeLayout.gridGap;
            final heroWidth = (constraints.maxWidth - gap) * 2 / 3;
            final rowHeight = heroWidth / HomeLayout.pcHeroAspectRatio;

            return SizedBox(
              height: rowHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 2,
                    child: _PcHeroCard(item: featured, emby: emby, expandToFill: true),
                  ),
                  if (secondary.isNotEmpty) ...[
                    const SizedBox(width: gap),
                    Expanded(
                      child: Column(
                        children: [
                          for (var i = 0; i < secondary.length; i++) ...[
                            if (i > 0) const SizedBox(height: gap),
                            Expanded(
                              child: _PcSecondaryCard(item: secondary[i], emby: emby),
                            ),
                          ],
                          if (secondary.length == 1) const Expanded(child: SizedBox()),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _PcContinueWatchingSkeleton extends StatelessWidget {
  const _PcContinueWatchingSkeleton();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        if (!wide) {
          return Column(
            children: [
              const AspectRatio(
                aspectRatio: HomeLayout.pcHeroAspectRatio,
                child: Skeleton(borderRadius: HomeLayout.cardRadiusR),
              ),
              const SizedBox(height: HomeLayout.gridGap),
              for (var i = 0; i < 2; i++) ...[
                if (i > 0) const SizedBox(height: HomeLayout.gridGap),
                const SizedBox(
                  height: 160,
                  child: Skeleton(borderRadius: AppRadius.mdR),
                ),
              ],
            ],
          );
        }

        const gap = HomeLayout.gridGap;
        final heroWidth = (constraints.maxWidth - gap) * 2 / 3;
        final rowHeight = heroWidth / HomeLayout.pcHeroAspectRatio;

        return SizedBox(
          height: rowHeight,
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 2,
                child: Skeleton(borderRadius: HomeLayout.cardRadiusR),
              ),
              SizedBox(width: gap),
              Expanded(
                child: Column(
                  children: [
                    Expanded(child: Skeleton(borderRadius: AppRadius.mdR)),
                    SizedBox(height: gap),
                    Expanded(child: Skeleton(borderRadius: AppRadius.mdR)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PcSectionHeader extends StatelessWidget {
  const _PcSectionHeader({this.onViewAll});

  final VoidCallback? onViewAll;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return HomeSectionHeader(
      title: '继续观看',
      titleStyle: HomeTypography.headlineLg(cs.onSurface),
      trailingLabel: onViewAll == null ? null : '查看全部',
      onTrailingTap: onViewAll,
    );
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

class _PcProgressBar extends StatelessWidget {
  const _PcProgressBar({
    required this.value,
    this.maxWidth,
  });

  final double value;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final colors = context.appColors;
    final bar = ClipRRect(
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
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.progressActive,
                  borderRadius: AppRadius.pillR,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (maxWidth != null) {
      return ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth!),
        child: bar,
      );
    }
    return bar;
  }
}

class _PcHeroCard extends StatefulWidget {
  const _PcHeroCard({
    required this.item,
    required this.emby,
    this.expandToFill = false,
  });

  final EmbyMediaItem item;
  final EmbyService emby;
  final bool expandToFill;

  @override
  State<_PcHeroCard> createState() => _PcHeroCardState();
}

class _PcHeroCardState extends State<_PcHeroCard> {
  final _hovered = ValueNotifier(false);

  @override
  void dispose() {
    _hovered.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final item = widget.item;
    final emby = widget.emby;
    final url = emby.backdropUrlForItem(item) ??
        emby.posterUrlForItem(item, maxHeight: AppConfig.posterMaxHeight);
    final fraction = _playedFraction(item);
    final progressLine = item.continueWatchingProgressLine;
    final remaining = item.remainingWatchLabel;

    final metaParts = <String>[];
    if (progressLine != null) metaParts.add(progressLine);
    if (remaining != null && (progressLine == null || !progressLine.contains(remaining))) {
      metaParts.add(remaining);
    }

    // 静态内容 — 永不随 hover 重建
    final staticOverlay = Padding(
      padding: const EdgeInsets.all(HomeLayout.pcHeroContentPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          HomeMediaTypeBadge(label: item.mediaTypeLabel),
          const SizedBox(height: HomeLayout.pcHeroBadgeTitleGap),
          Text(
            _heroTitle(item),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: HomeTypography.displayLg(HomeGlassTokens.backdropTitleForeground(cs)).copyWith(
              fontSize: HomeLayout.pcHeroTitleFontSize,
              height: HomeLayout.pcHeroTitleLineHeight,
            ),
          ),
          if (metaParts.isNotEmpty) ...[
            const SizedBox(height: HomeLayout.pcHeroTitleMetaGap),
            Text(
              metaParts.join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: HomeTypography.bodyMd(HomeGlassTokens.backdropMetaForeground(cs)),
            ),
          ],
          if (fraction != null) ...[
            const SizedBox(height: HomeLayout.pcHeroMetaProgressGap),
            _PcProgressBar(
              value: fraction,
              maxWidth: HomeLayout.pcHeroProgressMaxWidth,
            ),
            const SizedBox(height: HomeLayout.pcHeroProgressButtonGap),
          ] else if (metaParts.isNotEmpty) ...[
            const SizedBox(height: HomeLayout.pcHeroMetaProgressGap),
          ],
          Row(
            children: [
              _PcHeroPlayButton(
                onPressed: () => playMediaFromCard(context, emby, item),
              ),
              const SizedBox(width: HomeLayout.pcActionButtonGap),
              _PcHeroGlassButton(
                label: '详情',
                onPressed: () => openHomeMediaItemDetail(context, item),
              ),
            ],
          ),
        ],
      ),
    );

    final stack = Stack(
      fit: StackFit.expand,
      children: [
        // 动画背景层 — 仅此子树响应 hover 变化
        HoverAnimatedBackground(
          hovered: _hovered,
          image: _BackdropImage(url: url, headers: emby.imageAuthHeaders),
          scrim: homeMediaBackdropScrim(HomeMediaScrimShape.hero),
          restOpacity: HomeGlassTokens.mediaRestOpacity(
            cs,
            HomeLayout.pcHeroImageOpacity,
          ),
          hoverOpacity: 1.0,
          restDarken: HomeLayout.pcHeroUniformDarken,
          hoverDarken: 0.0,
        ),
        // 静态 overlay — 不受 hover 影响
        staticOverlay,
      ],
    );

    return MouseRegion(
      onEnter: (_) => _hovered.value = true,
      onExit: (_) => _hovered.value = false,
      child: GlassSurface(
        padding: EdgeInsets.zero,
        clipChild: false,
        rimBorder: true,
        useBlur: false,
        onTap: () => openHomeMediaItemDetail(context, item),
        child: widget.expandToFill
            ? stack
            : AspectRatio(
                aspectRatio: HomeLayout.pcHeroAspectRatio,
                child: stack,
              ),
      ),
    );
  }
}

/// Stitch hero play pill — `px-8 py-3`, 24px icon, flat primary fill.
class _PcHeroPlayButton extends StatelessWidget {
  const _PcHeroPlayButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final labelStyle = HomeTypography.labelSm(
      colors.onPlayAction,
      fontWeight: FontWeight.w700,
    );

    return Material(
      color: colors.playAction,
      borderRadius: AppRadius.pillR,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        borderRadius: AppRadius.pillR,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: HomeLayout.pcActionButtonHPad,
            vertical: HomeLayout.pcActionButtonVPad,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.play_arrow_rounded,
                size: HomeLayout.pcHeroPlayIconSize,
                color: colors.onPlayAction,
              ),
              const SizedBox(width: HomeLayout.pcHeroPlayIconGap),
              Text('播放', style: labelStyle),
            ],
          ),
        ),
      ),
    );
  }
}

/// Stitch hero glass pill — matches play button height.
class _PcHeroGlassButton extends StatelessWidget {
  const _PcHeroGlassButton({
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: AppRadius.pillR,
        color: HomeGlassTokens.backdropGlassButtonFill(cs),
        border: Border.all(color: HomeGlassTokens.backdropGlassButtonBorder(cs)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: AppRadius.pillR,
          hoverColor: cs.brightness == Brightness.dark
              ? cs.onSurface.withValues(alpha: 0.1)
              : Colors.white.withValues(alpha: 0.12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: HomeLayout.pcHeroPlayIconSize + HomeLayout.pcActionButtonVPad * 2,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: HomeLayout.pcActionButtonHPad,
                vertical: HomeLayout.pcActionButtonVPad,
              ),
              child: Center(
                child: Text(
                  label,
                  style: HomeTypography.labelSm(
                    HomeGlassTokens.backdropGlassButtonLabel(cs),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PcSecondaryCard extends StatefulWidget {
  const _PcSecondaryCard({required this.item, required this.emby});

  final EmbyMediaItem item;
  final EmbyService emby;

  @override
  State<_PcSecondaryCard> createState() => _PcSecondaryCardState();
}

class _PcSecondaryCardState extends State<_PcSecondaryCard> {
  final _hovered = ValueNotifier(false);

  @override
  void dispose() {
    _hovered.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final item = widget.item;
    final emby = widget.emby;
    final url = emby.backdropUrlForItem(item) ??
        emby.posterUrlForItem(item, maxHeight: 200);
    final fraction = _playedFraction(item);
    final compact = _secondaryProgressLine(item);

    // 静态内容 — 永不随 hover 重建
    final staticOverlay = Padding(
      padding: const EdgeInsets.all(HomeLayout.pcSecondaryContentPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            _heroTitle(item),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: HomeTypography.headlineMd(HomeGlassTokens.backdropTitleForeground(cs)),
          ),
          if (compact != null) ...[
            const SizedBox(height: HomeLayout.pcSecondaryTitleMetaGap),
            Text(
              compact,
              style: HomeTypography.captionXs(
                HomeGlassTokens.backdropMetaForeground(cs),
              ),
            ),
          ],
          if (fraction != null) ...[
            const SizedBox(height: HomeLayout.pcSecondaryMetaProgressGap),
            _PcProgressBar(value: fraction),
          ],
        ],
      ),
    );

    return MouseRegion(
      onEnter: (_) => _hovered.value = true,
      onExit: (_) => _hovered.value = false,
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
              image: _BackdropImage(url: url, headers: emby.imageAuthHeaders),
              scrim: homeMediaBackdropScrim(HomeMediaScrimShape.secondary),
              restOpacity: HomeGlassTokens.mediaRestOpacity(
                cs,
                HomeLayout.pcSecondaryImageOpacity,
              ),
              hoverOpacity: 1.0,
              restDarken: HomeLayout.pcSecondaryUniformDarken,
              hoverDarken: 0.04,
            ),
            staticOverlay,
            // 播放按钮 — 仅此子树响应 hover 变化
            _SecondaryPlayButtonOverlay(
              hovered: _hovered,
              onTap: () => playMediaFromCard(context, emby, item),
            ),
          ],
        ),
      ),
    );
  }
}

/// Play-button overlay for secondary cards — listens to [hovered] via
/// [ValueListenableBuilder] so **only** this subtree rebuilds on mouse movement.
class _SecondaryPlayButtonOverlay extends StatelessWidget {
  const _SecondaryPlayButtonOverlay({required this.hovered, required this.onTap});

  final ValueNotifier<bool> hovered;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: hovered,
      builder: (_, isHovered, __) {
        return Center(
          child: PcHoverPlayButton(
            visible: isHovered,
            onTap: onTap,
          ),
        );
      },
    );
  }
}

class _BackdropImage extends StatelessWidget {
  const _BackdropImage({
    required this.url,
    this.headers,
  });

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
          child: Icon(Icons.movie, color: cs.outline, size: 32),
        ),
      );
    }
    return ColoredBox(
      color: cs.surfaceContainerHighest,
      child: Icon(Icons.movie, color: cs.outline, size: 32),
    );
  }
}
