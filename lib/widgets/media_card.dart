import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/app_config.dart';
import '../core/layout/platform_layout.dart';
import '../core/tv/tv_remote_actions.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_motion.dart';
import '../core/theme/app_text.dart';
import '../models/emby/emby_media_item.dart';
import 'media_badges.dart';
import 'poster_badge.dart';
import 'poster_skeleton.dart';

double mediaCardBodyMediumLineHeight(BuildContext context) {
  final t = Theme.of(context).textTheme.bodyMedium;
  if (t == null) return 20;
  final fs = t.fontSize ?? 14;
  final h = t.height ?? 1.25;
  return fs * h;
}

double mediaCardBodySmallLineHeight(BuildContext context) {
  final t = Theme.of(context).textTheme.bodySmall;
  if (t == null) return 16;
  final fs = t.fontSize ?? 12;
  final h = t.height ?? 1.25;
  return fs * h;
}

/// 竖版海报（宽:高 = [posterAspectRatio]）+ 与 [MediaCard] 网格模式一致的标题/副标题占位，用于计算 [SliverGrid.childAspectRatio]。
///
/// 含少量垂直余量，避免子像素舍入导致「BOTTOM OVERFLOWED BY … PIXELS」。
double mediaCardGridCellHeight(
  BuildContext context,
  double tileWidth, {
  double posterAspectRatio = 2 / 3,
  bool reserveSubtitle = true,
  bool discoverStyle = false,
  bool discoverShowEpisode = false,
}) {
  const gapBelowPoster = 6.0;
  final posterH = tileWidth / posterAspectRatio;
  const layoutSlopPx = 2.0;
  if (discoverStyle) {
    final lh = mediaCardBodySmallLineHeight(context);
    final titleH = discoverShowEpisode ? lh * 2 + 2 : lh * 2;
    return posterH + gapBelowPoster + titleH + layoutSlopPx;
  }
  final lh = mediaCardBodyMediumLineHeight(context);
  const blockGap = 2.0;
  final titleSlotH = lh * 2 + blockGap;
  final subH = reserveSubtitle ? mediaCardBodySmallLineHeight(context) : 0;
  return posterH + gapBelowPoster + titleSlotH + subH + layoutSlopPx;
}

class _EmbyPosterTouchInteractor extends StatefulWidget {
  const _EmbyPosterTouchInteractor({
    required this.child,
    required this.onOpenDetail,
    required this.onPlay,
  });

  final Widget child;
  final VoidCallback onOpenDetail;
  final VoidCallback onPlay;

  @override
  State<_EmbyPosterTouchInteractor> createState() => _EmbyPosterTouchInteractorState();
}

class _EmbyPosterTouchInteractorState extends State<_EmbyPosterTouchInteractor> {
  bool _showPlayOverlay = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onOpenDetail,
            onLongPress: () => setState(() => _showPlayOverlay = true),
          ),
        ),
        if (_showPlayOverlay) ...[
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _showPlayOverlay = false),
              child: ColoredBox(color: colors.scrim),
            ),
          ),
          Center(
            child: Material(
              color: colors.playAction,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: widget.onPlay,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Icon(Icons.play_arrow,
                      color: colors.onPlayAction, size: 32),
                ),
              ),
            ),
          ),
        ],
        Positioned(
          right: 6,
          bottom: 6,
          child: Material(
            color: colors.scrimStrong,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: widget.onPlay,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 18),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Emby 网页端式海报：悬停时压暗并显示中央播放；点播放走 [onPlay]，点海报其余区域走 [onOpenDetail]。
class _EmbyPosterHoverInteractor extends StatefulWidget {
  const _EmbyPosterHoverInteractor({
    required this.child,
    required this.onOpenDetail,
    required this.onPlay,
  });

  final Widget child;
  final VoidCallback onOpenDetail;
  final VoidCallback onPlay;

  @override
  State<_EmbyPosterHoverInteractor> createState() => _EmbyPosterHoverInteractorState();
}

class _EmbyPosterHoverInteractorState extends State<_EmbyPosterHoverInteractor> {
  bool _hoverPoster = false;
  bool _hoverPlay = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return MouseRegion(
      onEnter: (_) => setState(() => _hoverPoster = true),
      onExit: (_) => setState(() {
        _hoverPoster = false;
        _hoverPlay = false;
      }),
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (!_hoverPoster)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onOpenDetail,
              ),
            ),
          if (_hoverPoster) ...[
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onOpenDetail,
                child: ColoredBox(color: colors.scrim),
              ),
            ),
            Center(
              child: MouseRegion(
                onEnter: (_) => setState(() => _hoverPlay = true),
                onExit: (_) => setState(() => _hoverPlay = false),
                child: Material(
                  color: _hoverPlay ? colors.playAction : colors.scrimStrong,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    overlayColor: WidgetStateProperty.resolveWith(
                      (states) => states.contains(WidgetState.pressed)
                          ? Colors.white.withValues(alpha: 0.2)
                          : null,
                    ),
                    onTap: widget.onPlay,
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(Icons.play_arrow, color: Colors.white, size: 30),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class MediaCard extends StatelessWidget {
  const MediaCard({
    super.key,
    required this.title,
    this.episodeTitle,
    this.subtitle,
    this.imageUrl,
    this.httpHeaders,
    this.progress,
    required this.onOpenDetail,
    this.onPlay,
    this.fixedPosterHeight,
    this.posterAspectRatio,
    this.discoverStyle = false,
    this.typeBadge,
    this.ratingBadge,
    this.heroTag,
    this.specBadges = const [],
    this.embyItem,
  });

  /// 第一块：剧名.季号；有 [episodeTitle] 时单行，否则最多两行（占满两行槽）。
  final String title;
  /// 第二块：第N集.集名；单行；电影等可省略。
  final String? episodeTitle;
  final String? subtitle;
  final String? imageUrl;
  final Map<String, String>? httpHeaders;
  final double? progress;
  /// 进入详情（海报非播放钮区域、标题区）。
  final VoidCallback onOpenDetail;
  /// 非 null 时悬停海报显示播放钮并走此回调（电影直播；剧集由上层解析为首集）。
  final VoidCallback? onPlay;
  final double? fixedPosterHeight;
  final double? posterAspectRatio;
  /// 与发现页一致：角标 + 精简标题；[episodeTitle]/[progress] 仍可显示（如最近播放）。
  final bool discoverStyle;
  final String? typeBadge;
  final String? ratingBadge;
  /// 非 null 时海报参与 Hero 共享元素转场（需保证同屏唯一）。
  final Object? heroTag;
  /// 媒体规格徽章（4K/HDR/DV/Atmos），叠加海报右下角。
  final List<MediaSpecBadge> specBadges;

  /// 提供时且 [specBadges] 为空，自动使用 [EmbyMediaItem.mediaSpecBadges]。
  final EmbyMediaItem? embyItem;

  List<MediaSpecBadge> get _effectiveSpecBadges {
    if (specBadges.isNotEmpty) return specBadges;
    return embyItem?.mediaSpecBadges ?? const [];
  }

  Widget _posterImage(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: imageUrl!,
        httpHeaders: httpHeaders,
        fit: BoxFit.cover,
        alignment: Alignment.center,
        memCacheHeight: AppConfig.posterMaxHeight,
        fadeInDuration: AppMotion.base,
        fadeInCurve: AppMotion.decelerate,
        placeholder: (_, __) => const PosterImageSkeleton(),
        errorWidget: (_, __, ___) => ColoredBox(
          color: cs.surfaceContainerHighest,
          child: Icon(Icons.movie, size: 48, color: cs.outline),
        ),
      );
    }
    return ColoredBox(
      color: cs.surfaceContainerHighest,
      child: Icon(Icons.movie, size: 48, color: cs.outline),
    );
  }

  List<Widget> _posterBadges(BuildContext context) {
    final type = typeBadge;
    if (type == null || type.isEmpty) return const [];
    final cs = Theme.of(context).colorScheme;
    final rating = ratingBadge;
    return [
      Positioned(
        left: 6,
        top: 6,
        child: PosterBadge(
          label: type,
          background: cs.primaryContainer.withValues(alpha: 0.92),
          foreground: cs.onPrimaryContainer,
        ),
      ),
      if (rating != null && rating.isNotEmpty)
        Positioned(
          right: 6,
          top: 6,
          child: PosterBadge(
            label: rating,
            background: cs.brightness == Brightness.dark
                ? Colors.black.withValues(alpha: 0.72)
                : Colors.black.withValues(alpha: 0.68),
            foreground: cs.primary,
            borderColor: cs.primary.withValues(
              alpha: cs.brightness == Brightness.dark ? 0.38 : 0.45,
            ),
          ),
        ),
    ];
  }

  Widget _posterStackContent(BuildContext context) {
    final colors = context.appColors;
    return Stack(
      fit: StackFit.expand,
      children: [
        _posterImage(context),
        if (_effectiveSpecBadges.isNotEmpty)
          Positioned(
            // 有右下角播放钮时改放左下，避免被遮挡。
            left: onPlay != null ? 5 : null,
            right: onPlay != null ? null : 5,
            bottom: progress != null && progress! > 0 && progress! < 99.5 ? 9 : 5,
            child: MediaBadges(badges: _effectiveSpecBadges, compact: true),
          ),
        if (progress != null && progress! > 0 && progress! < 99.5)
          Align(
            alignment: Alignment.bottomCenter,
            child: LinearProgressIndicator(
              value: progress! / 100.0,
              minHeight: 4,
              color: colors.progressActive,
              backgroundColor: colors.scrimStrong,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
      ],
    );
  }

  Widget _clipPoster(BuildContext context) {
    final inner = _posterStackContent(context);
    final posterBody = onPlay != null
        ? (isAndroidMobileUi
            ? _EmbyPosterTouchInteractor(
                onOpenDetail: onOpenDetail,
                onPlay: onPlay!,
                child: inner,
              )
            : _EmbyPosterHoverInteractor(
                onOpenDetail: onOpenDetail,
                onPlay: onPlay!,
                child: inner,
              ))
        : inner;
    final clipped = ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: discoverStyle
          ? Stack(
              fit: StackFit.expand,
              children: [
                posterBody,
                ..._posterBadges(context),
              ],
            )
          : posterBody,
    );
    Widget poster = heroTag == null
        ? clipped
        : Hero(
            tag: heroTag!,
            // 转场过程中保持圆角不被裁切跳变。
            flightShuttleBuilder: (_, __, ___, ____, toHero) => toHero.widget,
            child: clipped,
          );
    // 指针 / 遥控器输入下，聚焦或悬停时海报放大（Netflix/Plex 风格）。
    final modality = context.inputModality;
    if (modality == InputModality.pointer || modality == InputModality.dpad) {
      poster = _PosterFocusScale(child: poster);
    }
    return poster;
  }

  Widget _titleBlock(BuildContext context, double lh, double blockGap, double twoLineSlotH, bool hasEpisode) {
    if (hasEpisode) {
      return SizedBox(
        height: twoLineSlotH,
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: lh,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.cardTitle(context),
              ),
            ),
            SizedBox(height: blockGap),
            SizedBox(
              height: lh,
              child: Text(
                episodeTitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.cardSubtitle(context).copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Text(
      title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: AppTextStyles.cardTitle(context),
    );
  }

  Widget _metaBelowTitle(BuildContext context) {
    if (subtitle == null || subtitle!.isEmpty) return const SizedBox.shrink();
    return Text(
      subtitle!,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTextStyles.cardMeta(context),
    );
  }

  Widget _discoverTitle(BuildContext context) {
    final ep = episodeTitle?.trim();
    final hasEpisode = ep != null && ep.isNotEmpty;
    final style = Theme.of(context).textTheme.bodySmall;
    if (!hasEpisode) {
      return Text(
        title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    final lh = mediaCardBodySmallLineHeight(context);
    const blockGap = 2.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: lh,
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
        const SizedBox(height: blockGap),
        SizedBox(
          height: lh,
          child: Text(
            ep,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final poster = _clipPoster(context);
    if (discoverStyle) {
      final column = Column(
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (posterAspectRatio != null)
            AspectRatio(aspectRatio: posterAspectRatio!, child: poster)
          else if (fixedPosterHeight != null)
            SizedBox(height: fixedPosterHeight, width: double.infinity, child: poster)
          else
            Expanded(child: poster),
          const SizedBox(height: 6),
          _discoverTitle(context),
          if (posterAspectRatio != null) const Spacer(),
        ],
      );
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onOpenDetail,
          borderRadius: BorderRadius.circular(12),
          child: column,
        ),
      );
    }

    final lh = mediaCardBodyMediumLineHeight(context);
    const blockGap = 2.0;
    final twoLineSlotH = lh * 2 + blockGap;
    final hasEpisode = episodeTitle != null && episodeTitle!.trim().isNotEmpty;

    final titleArea = _titleBlock(context, lh, blockGap, twoLineSlotH, hasEpisode);

    final ar = posterAspectRatio;
    if (ar != null) {
      final column = Column(
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(aspectRatio: ar, child: poster),
          const SizedBox(height: 6),
          titleArea,
          _metaBelowTitle(context),
          const Spacer(),
        ],
      );
      return InkWell(
        onTap: onOpenDetail,
        borderRadius: BorderRadius.circular(12),
        child: column,
      );
    }

    final fixedH = fixedPosterHeight;
    if (fixedH != null) {
      final column = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: fixedH, width: double.infinity, child: poster),
          const SizedBox(height: 6),
          titleArea,
          _metaBelowTitle(context),
        ],
      );
      return InkWell(
        onTap: onOpenDetail,
        borderRadius: BorderRadius.circular(12),
        child: column,
      );
    }

    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: poster),
        const SizedBox(height: 6),
        titleArea,
        _metaBelowTitle(context),
      ],
    );
    return InkWell(
      onTap: onOpenDetail,
      borderRadius: BorderRadius.circular(12),
      child: column,
    );
  }
}

/// 海报聚焦/悬停放大（指针 + 遥控器）。聚焦时叠加柔和投影描边。
class _PosterFocusScale extends StatefulWidget {
  const _PosterFocusScale({required this.child});

  final Widget child;

  @override
  State<_PosterFocusScale> createState() => _PosterFocusScaleState();
}

class _PosterFocusScaleState extends State<_PosterFocusScale> {
  bool _hover = false;
  bool _focused = false;

  bool get _active => _hover || _focused;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Focus(
        onFocusChange: (f) => setState(() => _focused = f),
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          if (TvRemoteSelectKeys.isSelect(event.logicalKey)) {
            Actions.invoke(context, const ActivateIntent());
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: AnimatedScale(
          scale: _active ? 1.05 : 1.0,
          duration: AppMotion.fast,
          curve: AppMotion.emphasized,
          child: AnimatedContainer(
            duration: AppMotion.fast,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: _active
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : const [],
            ),
            foregroundDecoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _focused ? cs.primary : Colors.transparent,
                width: 2.5,
              ),
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}