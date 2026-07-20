import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_motion.dart';
import '../../core/theme/app_radius.dart';
import '../../models/emby/emby_media_item.dart';
import '../../providers/emby_provider.dart';
import '../../services/emby_service.dart';
import '../../utils/media_navigation.dart';
import '../skeleton.dart';
import 'glass_surface.dart';
import 'home_layout.dart';
import 'home_typography.dart';

/// 桌面首页 Hero 轮播：大幅 backdrop + Logo/标题 + 评分/年份/类型 + 简介，
/// 左右箭头与分页圆点切换，静置自动轮播（尊重减少动态效果）。
class HomePcHeroCarousel extends ConsumerStatefulWidget {
  const HomePcHeroCarousel({super.key, required this.emby});

  final EmbyService emby;

  @override
  ConsumerState<HomePcHeroCarousel> createState() => _HomePcHeroCarouselState();
}

class _HomePcHeroCarouselState extends ConsumerState<HomePcHeroCarousel> {
  static const _maxSlides = 6;
  static const _autoAdvanceInterval = Duration(seconds: 8);

  int _index = 0;
  int _slideCount = 0;
  Timer? _autoTimer;
  var _hovered = false;

  @override
  void dispose() {
    _autoTimer?.cancel();
    super.dispose();
  }

  void _restartAutoTimer(int slideCount) {
    _autoTimer?.cancel();
    if (slideCount <= 1) return;
    if (!AppMotion.animationsEnabled(context)) return;
    _autoTimer = Timer.periodic(_autoAdvanceInterval, (_) {
      if (!mounted || _hovered) return;
      _goTo((_index + 1) % slideCount);
    });
  }

  void _goTo(int index) {
    if (!mounted || index == _index) return;
    setState(() => _index = index);
    _restartAutoTimer(_slideCount);
  }

  List<EmbyMediaItem> _slides(List<EmbyMediaItem> items) {
    final out = <EmbyMediaItem>[];
    for (final item in items) {
      if (widget.emby.backdropUrlForItem(item, maxWidth: 1600) == null) {
        continue;
      }
      out.add(item);
      if (out.length >= _maxSlides) break;
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(homeHeroProvider);
    final slides = async.hasValue ? _slides(async.value!) : null;

    if (async.isLoading && slides == null) {
      return const AspectRatio(
        aspectRatio: HomeLayout.pcHeroAspectRatio,
        child: Skeleton(borderRadius: AppRadius.lgR),
      );
    }
    if (slides == null || slides.isEmpty) return const SizedBox.shrink();

    final index = _index.clamp(0, slides.length - 1);
    if (index != _index) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _goTo(index));
    }
    if (slides.length != _slideCount) {
      _slideCount = slides.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _restartAutoTimer(slides.length);
      });
    }

    final item = slides[index];

    return MouseRegion(
      onEnter: (_) => _hovered = true,
      onExit: (_) => _hovered = false,
      child: ClipRRect(
        borderRadius: AppRadius.lgR,
        child: AspectRatio(
          aspectRatio: HomeLayout.pcHeroAspectRatio,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: Theme.of(context).colorScheme.surfaceContainer),
              AnimatedSwitcher(
                duration: AppMotion.effectiveDuration(
                    context, const Duration(milliseconds: 500)),
                child: KeyedSubtree(
                  key: ValueKey(item.id),
                  child: _HeroBackdrop(item: item, emby: widget.emby),
                ),
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Color(0xE0000000),
                      Color(0x73000000),
                      Color(0x1A000000),
                      Colors.transparent,
                    ],
                    stops: [0.0, 0.32, 0.58, 1.0],
                  ),
                ),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => openHomeMediaItemDetail(context, item),
                child: const SizedBox.expand(),
              ),
              Positioned(
                left: HomeLayout.pcHeroContentPadding,
                right: HomeLayout.pcHeroContentPadding,
                bottom: HomeLayout.pcHeroContentPadding,
                child: IgnorePointer(
                  child: AnimatedSwitcher(
                    duration: AppMotion.effectiveDuration(
                        context, const Duration(milliseconds: 350)),
                    child: KeyedSubtree(
                      key: ValueKey('meta-${item.id}'),
                      child: _HeroMeta(item: item, emby: widget.emby),
                    ),
                  ),
                ),
              ),
              if (slides.length > 1) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: _HeroChevron(
                    icon: Icons.chevron_left_rounded,
                    onTap: () => _goTo(
                        (index - 1 + slides.length) % slides.length),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: _HeroChevron(
                    icon: Icons.chevron_right_rounded,
                    onTap: () => _goTo((index + 1) % slides.length),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 12,
                  child: IgnorePointer(
                    child: _HeroDots(count: slides.length, index: index),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroBackdrop extends StatelessWidget {
  const _HeroBackdrop({required this.item, required this.emby});

  final EmbyMediaItem item;
  final EmbyService emby;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final url = emby.backdropUrlForItem(item, maxWidth: 1600);
    if (url == null) {
      return ColoredBox(color: cs.surfaceContainerHighest);
    }
    return RepaintBoundary(
      child: CachedNetworkImage(
        imageUrl: url,
        httpHeaders: emby.imageAuthHeaders,
        fit: BoxFit.cover,
        alignment: const Alignment(0, -0.25),
        filterQuality: FilterQuality.medium,
        fadeInDuration:
            AppMotion.effectiveDuration(context, AppMotion.base),
        errorWidget: (_, __, ___) =>
            ColoredBox(color: cs.surfaceContainerHighest),
      ),
    );
  }
}

class _HeroMeta extends StatelessWidget {
  const _HeroMeta({required this.item, required this.emby});

  final EmbyMediaItem item;
  final EmbyService emby;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final titleColor = HomeGlassTokens.backdropTitleForeground(cs);
    final metaColor = HomeGlassTokens.backdropMetaForeground(cs);

    final logoUrl = emby.logoUrlForItem(item, maxHeight: 168, maxWidth: 840);

    final metaParts = <String>[
      if (item.productionYear != null) '${item.productionYear}',
      if (item.genres != null && item.genres!.isNotEmpty)
        item.genres!.take(3).join(' / '),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (logoUrl != null)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 84, maxWidth: 420),
            child: CachedNetworkImage(
              imageUrl: logoUrl,
              httpHeaders: emby.imageAuthHeaders,
              alignment: Alignment.bottomLeft,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
              errorWidget: (_, __, ___) => const SizedBox.shrink(),
            ),
          )
        else
          Text(
            item.type == 'Episode' &&
                    (item.seriesName?.trim().isNotEmpty ?? false)
                ? item.seriesName!
                : item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: HomeTypography.displayLg(titleColor),
          ),
        const SizedBox(height: 10),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (item.communityRating != null) ...[
              Icon(Icons.star_rounded, size: 16, color: cs.primary),
              const SizedBox(width: 4),
              Text(
                item.communityRating!.toStringAsFixed(1),
                style: HomeTypography.bodyMd(titleColor)
                    .copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 12),
            ],
            if (metaParts.isNotEmpty)
              Flexible(
                child: Text(
                  metaParts.join('  '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: HomeTypography.bodyMd(metaColor),
                ),
              ),
          ],
        ),
        if (item.overview != null && item.overview!.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Text(
              item.overview!.trim(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: HomeTypography.bodyMd(metaColor.withValues(alpha: 0.85)),
            ),
          ),
        ],
      ],
    );
  }
}

class _HeroChevron extends StatefulWidget {
  const _HeroChevron({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_HeroChevron> createState() => _HeroChevronState();
}

class _HeroChevronState extends State<_HeroChevron> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Material(
          color: Colors.black.withValues(alpha: _hovered ? 0.62 : 0.42),
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(widget.icon, size: 28, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroDots extends StatelessWidget {
  const _HeroDots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration:
                AppMotion.effectiveDuration(context, AppMotion.fast),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == index ? 18 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i == index
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.38),
              borderRadius: AppRadius.pillR,
            ),
          ),
      ],
    );
  }
}
