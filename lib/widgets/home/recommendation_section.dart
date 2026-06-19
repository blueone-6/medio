import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/app_config.dart';
import '../../core/layout/platform_layout.dart';
import '../../core/tv/tv_image_cache.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../models/emby/emby_media_item.dart';
import '../../providers/home_recommendation_provider.dart';
import '../../services/emby_service.dart';
import '../../utils/media_navigation.dart';
import '../../utils/user_facing_error.dart';
import '../../widgets/empty_state_view.dart';
import '../../widgets/error_view.dart';
import '../../widgets/loading_indicator.dart';
import 'glass_surface.dart';
import 'home_layout.dart';
import 'home_media_type_badge.dart';
import 'home_section_header.dart';
import 'home_typography.dart';
import 'poster_genre_meta.dart';
import 'pc_hover_play_button.dart';

enum HomeRecommendFilterStyle { underline, pill }

class RecommendationSection extends ConsumerStatefulWidget {
  const RecommendationSection({
    super.key,
    required this.emby,
    this.horizontal = false,
    this.crossAxisCount,
    this.filterStyle = HomeRecommendFilterStyle.underline,
    this.wrapInPadding = true,
    this.usePcSectionTitle = false,
    this.maxPosterHeight,
    this.onOpenSettings,
  });

  final EmbyService emby;
  final bool horizontal;
  final int? crossAxisCount;
  final HomeRecommendFilterStyle filterStyle;
  final bool wrapInPadding;
  final bool usePcSectionTitle;
  final double? maxPosterHeight;
  final VoidCallback? onOpenSettings;

  @override
  ConsumerState<RecommendationSection> createState() => _RecommendationSectionState();
}

class _RecommendationSectionState extends ConsumerState<RecommendationSection> {
  HomeRecommendationFilter _filter = HomeRecommendationFilter.all;

  Widget _buildRecommendLoading() {
    if (widget.horizontal) {
      return const LoadingIndicator.posterRow(posterRowHeight: 180);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols =
            widget.crossAxisCount ?? (constraints.maxWidth >= 600 ? 3 : 2);
        // 与 _buildRecommendData 的 12 项展示对齐，避免切换 filter 时骨架行数与实际不一致造成跳动。
        final placeholders = (12 / cols).ceil() * cols;
        return LoadingIndicator.posterGrid(
          homeRecommendStyle: true,
          pcRecommendStyle: widget.usePcSectionTitle,
          crossAxisCount: cols,
          placeholderCount: placeholders,
          horizontalPadding: 0,
          paddingTop: 0,
          maxContentWidth:
              widget.usePcSectionTitle ? HomeLayout.pcContentMaxWidth : null,
        );
      },
    );
  }

  Widget _buildRecommendData(List<EmbyMediaItem> items) {
    if (items.isEmpty) {
      final filterLabel = homeRecommendationFilterLabel(_filter);
      return EmptyStateView(
        compact: true,
        centered: false,
        icon: Icons.movie_filter_outlined,
        title: _filter == HomeRecommendationFilter.all ? '暂无推荐' : '该分类暂无内容',
        subtitle: _filter == HomeRecommendationFilter.all
            ? '稍后再来，或下拉刷新首页'
            : '「$filterLabel」下没有匹配项，试试其他筛选或刷新',
        actionLabel: '重试',
        onAction: () => ref.invalidate(homeRecommendationProvider),
      );
    }
    if (widget.horizontal) {
      return SizedBox(
        height: 220,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: HomeLayout.gridGap),
          itemBuilder: (context, i) => SizedBox(
            width: 120,
            child: HomeRecommendCard(item: items[i], emby: widget.emby),
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols =
            widget.crossAxisCount ?? (constraints.maxWidth >= 600 ? 3 : 2);
        return _RecommendGrid(
          items: items.take(12).toList(),
          emby: widget.emby,
          columns: cols,
          width: constraints.maxWidth,
          maxPosterHeight: widget.maxPosterHeight,
          useHomeTypography: widget.usePcSectionTitle,
        );
      },
    );
  }

  /// Progressive recommend: show partial data while similar-items load in background.
  Widget _buildRecommendBody(AsyncValue<List<EmbyMediaItem>> async) {
    final items = async.value;
    if (items != null) {
      return _buildRecommendData(items);
    }
    if (async.isLoading) {
      return _buildRecommendLoading();
    }
    return ErrorView.forHomeSection(
      error: async.error!,
      section: HomeLoadSection.recommendations,
      compact: true,
      onRetry: () => ref.invalidate(homeRecommendationProvider),
      onOpenSettings: widget.onOpenSettings,
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(homeRecommendationFilteredProvider(_filter));
    final cs = Theme.of(context).colorScheme;
    final sectionTitle = widget.usePcSectionTitle
        ? HomeTypography.headlineLg(cs.onSurface)
        : AppTextStyles.sectionTitle(context).copyWith(
            fontSize: HomeLayout.sectionTitleFontSize,
            height: HomeLayout.sectionTitleLineHeight,
            color: cs.onSurface,
          );

    final content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          HomeSectionHeader(
            title: '为你推荐',
            titleStyle: sectionTitle,
            trailing: _FilterTabs(
              selected: _filter,
              style: widget.filterStyle,
              onChanged: (f) => setState(() => _filter = f),
            ),
          ),
          const SizedBox(height: HomeLayout.sectionHeaderGap),
          AnimatedSize(
            duration: AppMotion.effectiveDuration(context, AppMotion.base),
            curve: AppMotion.decelerate,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: AppMotion.effectiveDuration(context, AppMotion.base),
              switchInCurve: AppMotion.decelerate,
              switchOutCurve: AppMotion.accelerate,
              // Previous child sits behind, current child sizes the Stack — top-aligned
              // crossfade without parking the old grid at the bottom of the new one.
              layoutBuilder: (currentChild, previousChildren) {
                return Stack(
                  alignment: Alignment.topCenter,
                  children: [
                    ...previousChildren.map(
                      (c) => Positioned.fill(child: c),
                    ),
                    if (currentChild != null) currentChild,
                  ],
                );
              },
              child: KeyedSubtree(
                key: ValueKey<HomeRecommendationFilter>(_filter),
                child: _buildRecommendBody(async),
              ),
            ),
          ),
        ],
      );

    if (!widget.wrapInPadding) return content;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: HomeLayout.horizontalMargin),
      child: content,
    );
  }
}

class _RecommendGrid extends StatelessWidget {
  const _RecommendGrid({
    required this.items,
    required this.emby,
    required this.columns,
    required this.width,
    this.maxPosterHeight,
    this.useHomeTypography = false,
  });

  final List<EmbyMediaItem> items;
  final EmbyService emby;
  final int columns;
  final double width;
  final double? maxPosterHeight;
  final bool useHomeTypography;

  @override
  Widget build(BuildContext context) {
    const gap = HomeLayout.gridGap;
    final rows = <Widget>[];

    for (var i = 0; i < items.length; i += columns) {
      final slice = items.skip(i).take(columns).toList();
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var j = 0; j < columns; j++) ...[
              if (j > 0) const SizedBox(width: gap),
              Expanded(
                child: j < slice.length
                    ? HomeRecommendCard(
                        item: slice[j],
                        emby: emby,
                        maxPosterHeight: maxPosterHeight,
                        useHomeTypography: useHomeTypography,
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ],
        ),
      );
      if (i + columns < items.length) {
        rows.add(const SizedBox(height: gap));
      }
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}

class _FilterTabs extends StatelessWidget {
  const _FilterTabs({
    required this.selected,
    required this.onChanged,
    this.style = HomeRecommendFilterStyle.underline,
  });

  final HomeRecommendationFilter selected;
  final ValueChanged<HomeRecommendationFilter> onChanged;
  final HomeRecommendFilterStyle style;

  @override
  Widget build(BuildContext context) {
    final gap = style == HomeRecommendFilterStyle.pill ? AppSpacing.sm : AppSpacing.lg;

    const filters = HomeRecommendationFilter.values;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < filters.length; i++)
          Padding(
            padding: EdgeInsets.only(left: i == 0 ? 0 : gap),
            child: _FilterTabButton(
              label: homeRecommendationFilterLabel(filters[i]),
              isSelected: filters[i] == selected,
              style: style,
              onPressed: () => onChanged(filters[i]),
            ),
          ),
      ],
    );
  }
}

class _FilterTabButton extends StatefulWidget {
  const _FilterTabButton({
    required this.label,
    required this.isSelected,
    required this.style,
    required this.onPressed,
  });

  final String label;
  final bool isSelected;
  final HomeRecommendFilterStyle style;
  final VoidCallback onPressed;

  @override
  State<_FilterTabButton> createState() => _FilterTabButtonState();
}

class _FilterTabButtonState extends State<_FilterTabButton> {
  var _focused = false;
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final radius =
        widget.style == HomeRecommendFilterStyle.pill ? AppRadius.pillR : AppRadius.smR;

    final isPill = widget.style == HomeRecommendFilterStyle.pill;
    return Semantics(
      button: true,
      selected: widget.isSelected,
      label: widget.label,
      child: Focus(
        onFocusChange: (f) => setState(() => _focused = f),
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onPressed,
              borderRadius: radius,
              // Pill 风格保留 InkWell 内置 focus/hover 着色；underline 风格自绘视觉。
              focusColor: isPill ? cs.primary.withValues(alpha: 0.08) : Colors.transparent,
              hoverColor: isPill ? cs.onSurface.withValues(alpha: 0.05) : Colors.transparent,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  // 仅 pill 在 focus 时画 chip 边框；underline 用 underline color 表达 focus。
                  border: (_focused && isPill)
                      ? Border.all(
                          color: cs.primary.withValues(alpha: 0.55),
                          width: 2,
                        )
                      : null,
                ),
                child: isPill
                    ? _FilterPill(
                        label: widget.label,
                        isSelected: widget.isSelected,
                        hovered: _hovered,
                      )
                    : _FilterTabLabel(
                        label: widget.label,
                        isSelected: widget.isSelected,
                        focused: _focused,
                        color: widget.isSelected
                            ? cs.onSurface
                            : cs.onSurfaceVariant.withValues(
                                alpha: _focused
                                    ? 0.95
                                    : _hovered
                                        ? 0.85
                                        : 0.6,
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

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.isSelected,
    this.hovered = false,
  });

  final String label;
  final bool isSelected;
  final bool hovered;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: AppMotion.effectiveDuration(context, AppMotion.base),
      curve: AppMotion.decelerate,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: isSelected
            ? cs.surfaceContainer
            : hovered
                ? cs.onSurface.withValues(alpha: 0.05)
                : Colors.transparent,
        borderRadius: AppRadius.pillR,
        border: Border.all(
          color: isSelected
              ? cs.onSurface.withValues(alpha: 0.12)
              : hovered
                  ? cs.onSurface.withValues(alpha: 0.08)
                  : Colors.transparent,
        ),
      ),
      child: Text(
        label,
        style: HomeTypography.labelSm(
          isSelected
              ? cs.onSurface
              : hovered
                  ? cs.onSurface.withValues(alpha: 0.9)
                  : cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _FilterTabLabel extends StatelessWidget {
  const _FilterTabLabel({
    required this.label,
    required this.isSelected,
    required this.focused,
    required this.color,
  });

  final String label;
  final bool isSelected;
  final bool focused;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final Color underlineColor;
    if (isSelected) {
      underlineColor = cs.primary;
    } else if (focused) {
      // Focus 走更柔和的下划线（不与选中态混淆）。
      underlineColor = cs.primary.withValues(alpha: 0.55);
    } else {
      underlineColor = Colors.transparent;
    }

    return IntrinsicWidth(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: AppTextStyles.navLabel(context, selected: isSelected).copyWith(
              fontSize: 12,
              // 选中时略加重，与 section title 拉开层级；选中字色随 onSurface，不再借用 primary。
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              height: HomeLayout.posterSubtitleLineHeight,
              color: color,
            ),
          ),
          const SizedBox(height: HomeLayout.filterUnderlineOffset),
          Container(
            height: HomeLayout.filterUnderlineThickness,
            color: underlineColor,
          ),
        ],
      ),
    );
  }
}

String _pcRecommendTitle(EmbyMediaItem item) {
  if (item.type == 'Episode') {
    final sn = item.seriesName?.trim();
    if (sn != null && sn.isNotEmpty) {
      final season = item.parentIndexNumber;
      if (season != null) return '$sn · S$season';
      return sn;
    }
  }
  return item.mediaCardDisplayTitle;
}

class HomeRecommendCard extends StatefulWidget {
  const HomeRecommendCard({
    super.key,
    required this.item,
    required this.emby,
    this.maxPosterHeight,
    this.useHomeTypography = false,
    this.showCaption = false,
    this.tvMode = false,
    this.onOpenDetail,
    this.imageUrl,
  });

  final EmbyMediaItem item;
  final EmbyService emby;
  final double? maxPosterHeight;
  final bool useHomeTypography;
  /// Show title lines under the poster (mobile). PC/TV use [_PosterTitleFooterOverlay].
  final bool showCaption;
  /// TV browse: D-Pad focus ring wraps card; no quick-play overlay.
  final bool tvMode;
  final VoidCallback? onOpenDetail;
  final String? imageUrl;

  @override
  State<HomeRecommendCard> createState() => _HomeRecommendCardState();
}

class _HomeRecommendCardState extends State<HomeRecommendCard> {
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
    final isTv = context.isTvUi || widget.tvMode;
    final canPlay = embyItemSupportsGridPlay(item);

    void openDetail() {
      if (widget.onOpenDetail != null) {
        widget.onOpenDetail!();
      } else {
        openHomeMediaItemDetail(context, item);
      }
    }
    final pc = widget.useHomeTypography ||
        (context.isDesktopUi && !context.isTvUi && !widget.tvMode);
    final badgeInset = pc ? HomeLayout.pcRecommendBadgeInset : HomeLayout.badgeInset;
    final playInset = pc ? HomeLayout.pcRecommendPlayButtonInset : badgeInset;
    // Mobile / TV-with-caption: title lives below the poster — never stack a poster overlay too.
    final captionBelow = !pc || widget.showCaption;

    return LayoutBuilder(
      builder: (context, constraints) {
        var posterW = constraints.maxWidth;
        var posterH = posterW / HomeLayout.recommendPosterAspectRatio;
        final cap = widget.maxPosterHeight;
        if (!pc && cap != null && posterH > cap) {
          posterH = cap;
          posterW = posterH * HomeLayout.recommendPosterAspectRatio;
        }

        final posterRequestH = isTv
            ? TvImageCache.posterRequestMaxHeight(posterH)
            : AppConfig.posterMaxHeight;
        final url = widget.imageUrl ??
            emby.posterUrlForItem(item, maxHeight: posterRequestH);
        final memCacheH =
            isTv ? TvImageCache.memCachePx(context, posterH) : null;
        final memCacheW =
            isTv ? TvImageCache.memCachePx(context, posterW) : null;

        // 静态 badge 层 — 永不随 hover 重建
        final staticBadges = [
          Positioned(
            top: badgeInset,
            left: badgeInset,
            child: HomeMediaTypeBadge(label: item.mediaTypeLabel),
          ),
          if (item.mediaCardRatingText != null)
            Positioned(
              top: badgeInset,
              right: badgeInset,
              child: HomeRatingBadge(
                label: item.mediaCardRatingText!,
                showStar: pc,
              ),
            ),
        ];

        final posterImage = _PosterImage(
          url: url,
          headers: emby.imageAuthHeaders,
          memCacheHeight: memCacheH,
          memCacheWidth: memCacheW,
        );

        final posterStack = Stack(
          fit: StackFit.expand,
          children: [
            if (isTv)
              Stack(
                fit: StackFit.expand,
                children: [
                  posterImage,
                  if (pc)
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
                ],
              )
            else
              HoverAnimatedBackground(
                hovered: _hovered,
                image: posterImage,
                scrim: pc
                    ? homeMediaBackdropScrim(HomeMediaScrimShape.poster)
                    : null,
                restOpacity: HomeGlassTokens.mediaRestOpacity(
                  cs,
                  HomeLayout.pcRecommendImageOpacity,
                ),
                hoverOpacity: 1.0,
                restDarken: HomeLayout.pcRecommendUniformDarken,
                hoverDarken: 0.02,
              ),
            ...staticBadges,
            if (!captionBelow) _PosterTitleFooterOverlay(item: item),
            if (pc && !isTv && !captionBelow)
              _RecommendHoverOverlay(
                hovered: _hovered,
                item: item,
                emby: emby,
                canPlay: canPlay,
                playInset: playInset,
              ),
            if (canPlay && !pc && !widget.tvMode)
              Positioned(
                right: playInset,
                bottom: playInset,
                child: _GlassPlayButton(
                  onTap: () => playMediaFromCard(context, emby, item),
                ),
              ),
          ],
        );

        final framedPoster = SizedBox(
          width: posterW,
          height: posterH,
          child: isTv
              ? _HomePosterFrame(child: posterStack)
              : MouseRegion(
                  onEnter: (_) => _hovered.value = true,
                  onExit: (_) => _hovered.value = false,
                  child: _HomePosterFrame(
                    onTap: pc ? openDetail : null,
                    child: posterStack,
                  ),
                ),
        );

        if (pc && !captionBelow) {
          return framedPoster;
        }

        final caption = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(alignment: Alignment.center, child: framedPoster),
            const SizedBox(height: HomeLayout.posterTitleGap),
            Text(
              item.mediaCardDisplayTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: pc
                  ? HomeTypography.bodyMdSemibold(cs.onSurface)
                  : TextStyle(
                      fontSize: HomeLayout.posterTitleFontSize,
                      height: HomeLayout.posterTitleLineHeight,
                      fontWeight: FontWeight.w400,
                      color: cs.onSurface,
                    ),
            ),
            if (pc)
              PosterGenreMeta(
                item: item,
                metaColor: cs.onSurfaceVariant,
              )
            else if (item.mediaCardRecommendSubtitle.isNotEmpty)
              Text(
                item.mediaCardRecommendSubtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: HomeLayout.posterSubtitleFontSize,
                  height: HomeLayout.posterSubtitleLineHeight,
                  fontWeight: FontWeight.w500,
                  // 0.24 (px-equivalent) 太宽，副文案在小字号下显疏；统一 0.02em 节奏。
                  letterSpacing: 0.02 * HomeLayout.posterSubtitleFontSize,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                ),
              ),
          ],
        );

        if (widget.tvMode) {
          return caption;
        }

        return pc
            ? caption
            : GestureDetector(
          onTap: openDetail,
          child: caption,
        );
      },
    );
  }
}

/// Same glass rim as continue-watching PC cards (`GlassSurface` + `rimBorder`).
class _HomePosterFrame extends StatelessWidget {
  const _HomePosterFrame({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      padding: EdgeInsets.zero,
      clipChild: false,
      rimBorder: true,
      useBlur: false,
      borderRadius: HomeLayout.posterRadiusR,
      onTap: onTap,
      child: child,
    );
  }
}

class _PosterImage extends StatelessWidget {
  const _PosterImage({
    required this.url,
    this.headers,
    this.memCacheHeight,
    this.memCacheWidth,
  });

  final String? url;
  final Map<String, String>? headers;
  final int? memCacheHeight;
  final int? memCacheWidth;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (url != null && url!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: url!,
        httpHeaders: headers,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        memCacheHeight: memCacheHeight,
        memCacheWidth: memCacheWidth,
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

class _GlassPlayButton extends StatelessWidget {
  const _GlassPlayButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return posterPlayControlShell(
      Material(
        color: HomeGlassTokens.playControlFill(cs),
        shape: CircleBorder(
          side: BorderSide(color: HomeGlassTokens.playControlBorder(cs)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 32,
            height: 32,
            child: Icon(
              Icons.play_arrow_rounded,
              size: 18,
              color: HomeGlassTokens.playControlIcon(cs, filled: false),
            ),
          ),
        ),
      ),
    );
  }
}

/// Hover overlay for PC recommend posters — listens to [hovered] via
/// [ValueListenableBuilder] so **only** this subtree rebuilds on mouse movement.
/// Bottom-left title on poster (PC + TV hover cards).
class _PosterTitleFooterOverlay extends StatelessWidget {
  const _PosterTitleFooterOverlay({required this.item});

  final EmbyMediaItem item;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Reserve right gutter so the hover play button (40dp at bottom-right) never
    // overlaps the title/meta. Footer padding + button + breathing space.
    const playGutter = HomeLayout.pcRecommendPlayButtonSize +
        HomeLayout.pcRecommendPlayButtonInset +
        HomeLayout.pcRecommendFooterPadding;
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
            playGutter,
            HomeLayout.pcRecommendFooterPadding,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _pcRecommendTitle(item),
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

/// PC recommend play control — title stays on [_PosterTitleFooterOverlay].
class _RecommendHoverOverlay extends StatelessWidget {
  const _RecommendHoverOverlay({
    required this.hovered,
    required this.emby,
    required this.item,
    required this.canPlay,
    required this.playInset,
  });

  final ValueNotifier<bool> hovered;
  final EmbyService emby;
  final EmbyMediaItem item;
  final bool canPlay;
  final double playInset;

  @override
  Widget build(BuildContext context) {
    if (!canPlay) return const SizedBox.shrink();
    return ValueListenableBuilder<bool>(
      valueListenable: hovered,
      builder: (_, isHovered, __) {
        return Positioned(
          right: playInset,
          bottom: playInset,
          child: PcHoverPlayButton(
            visible: isHovered,
            onTap: () => playMediaFromCard(context, emby, item),
          ),
        );
      },
    );
  }
}
