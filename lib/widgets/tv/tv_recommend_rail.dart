import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/perf.dart';
import '../../core/theme/app_motion.dart';
import '../../models/emby/emby_media_item.dart';
import '../../providers/home_recommendation_provider.dart';
import '../../services/emby_service.dart';
import '../../utils/media_navigation.dart';
import '../empty_state_view.dart';
import 'tv_error_panel.dart';
import '../home/home_typography.dart';
import '../loading_indicator.dart';
import 'tv_focus_ring.dart';
import 'tv_home_layout.dart';
import 'tv_media_poster_card.dart';

class TvRecommendRail extends ConsumerStatefulWidget {
  const TvRecommendRail({super.key, required this.emby});

  final EmbyService emby;

  @override
  ConsumerState<TvRecommendRail> createState() => _TvRecommendRailState();
}

class _TvRecommendRailState extends ConsumerState<TvRecommendRail> {
  HomeRecommendationFilter _filter = HomeRecommendationFilter.all;
  final _scrollController = ScrollController();
  DateTime? _lastFocusScrollAt;
  PerfSpan? _readySpan;
  bool _readyLogged = false;

  @override
  void initState() {
    super.initState();
    _readySpan = PerfTracer.start('tv.recommend_rail.ready');
  }

  @override
  void dispose() {
    _readySpan?.end(extraContext: {'first_frame_via': 'cancelled'});
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToFocusedItem(int index, double itemStride, double itemW) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final position = _scrollController.position;
      if (!position.hasContentDimensions) return;
      final viewport = position.viewportDimension;
      final maxOffset = position.maxScrollExtent;
      final target = index * itemStride;

      // Keep the focused item fully inside the viewport (incl. focus border + scale).
      var offset = target - (viewport - itemW) / 2;
      if (target + itemW > offset + viewport) {
        offset = target + itemW - viewport;
      }
      if (target < offset) {
        offset = target;
      }
      offset = offset.clamp(0.0, maxOffset);

      final now = DateTime.now();
      final rapid = _lastFocusScrollAt != null &&
          now.difference(_lastFocusScrollAt!) <
              const Duration(milliseconds: 150);
      _lastFocusScrollAt = now;

      if (rapid) {
        _scrollController.jumpTo(offset);
      } else {
        _scrollController.animateTo(
          offset,
          duration: AppMotion.base,
          curve: AppMotion.decelerate,
        );
      }
    });
  }

  void _markRailReady(int count) {
    if (_readyLogged || count <= 0) return;
    _readyLogged = true;
    _readySpan?.end(extraContext: {'count': count});
    _readySpan = null;
  }

  Widget _buildRail({
    required List<EmbyMediaItem> items,
    required bool showLoadingShell,
    required Object? error,
    required ColorScheme cs,
    required double contentW,
    required double viewportW,
    required double maxRailH,
  }) {
    final approxPosterW =
        TvHomeLayout.scaled(TvHomeLayout.designPosterWidth, viewportW);
    final focusMargin = TvHomeLayout.focusMarginFor(approxPosterW);
    final posterSize = TvHomeLayout.recommendPosterSize(
      contentWidth: contentW,
      viewportWidth: viewportW,
      maxRailHeight: (maxRailH - focusMargin * 2).clamp(0, maxRailH),
    );

    if (error != null && items.isEmpty) {
      return TvErrorPanel(
        error: error,
        compact: true,
        onRetry: () => ref.invalidate(homeRecommendationProvider),
      );
    }

    if (showLoadingShell && items.isEmpty) {
      return SizedBox(
        height: posterSize.height + focusMargin * 2,
        child: LoadingIndicator.posterRow(
          posterRowHeight: posterSize.height + focusMargin * 2,
          posterRowItemWidth: posterSize.width,
          posterRowItemCount: 5,
          showPosterTitle: false,
        ),
      );
    }

    if (items.isEmpty) {
      if (maxRailH < 72) {
        return Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '暂无推荐',
            style: HomeTypography.bodyMd(cs.onSurfaceVariant),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );
      }
      final railCompact = maxRailH < 140;
      return Align(
        alignment: Alignment.centerLeft,
        child: EmptyStateView(
          compact: true,
          centered: false,
          icon: Icons.movie_filter_outlined,
          title: '暂无推荐',
          subtitle: railCompact ? null : '试试切换筛选条件或稍后再来',
          actionLabel: railCompact ? null : '刷新',
          autofocusAction: !railCompact,
          onAction: railCompact
              ? null
              : () => ref.invalidate(homeRecommendationProvider),
          titleStyle: HomeTypography.bodyMd(cs.onSurfaceVariant),
          subtitleStyle: HomeTypography.bodyMd(
            cs.onSurfaceVariant.withValues(alpha: 0.8),
          ),
        ),
      );
    }
    final itemFocusMargin = TvHomeLayout.focusMarginFor(posterSize.width);
    final itemW = posterSize.width + itemFocusMargin * 2;
    final itemH = posterSize.height + itemFocusMargin * 2;
    final itemStride = itemW + TvHomeLayout.railGap;
    final visible = items.length.clamp(0, 12);
    _markRailReady(visible);

    return ClipRect(
      child: SizedBox(
        height: itemH,
        child: ListView.separated(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          scrollCacheExtent: ScrollCacheExtent.pixels(itemStride * 2),
          padding: EdgeInsets.only(right: itemFocusMargin),
          itemCount: visible,
          separatorBuilder: (_, __) => const SizedBox(width: TvHomeLayout.railGap),
          itemBuilder: (context, i) {
            final item = items[i];
            return RepaintBoundary(
              child: SizedBox(
                width: itemW,
                height: itemH,
                child: Padding(
                  padding: EdgeInsets.all(itemFocusMargin),
                  child: TvFocusRing(
                    key: ValueKey('tv-rail-focus-${item.id}'),
                    onActivate: () => openHomeMediaItemDetail(context, item),
                    onFocusChange: (f) {
                      if (f) {
                        _scrollToFocusedItem(i, itemStride, itemW);
                      }
                    },
                    child: TvMediaPosterCard(
                      item: item,
                      emby: widget.emby,
                      maxPosterHeight: posterSize.height,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final async = ref.watch(homeRecommendationFilteredProvider(_filter));
    final items = async.value ?? const <EmbyMediaItem>[];
    final showLoadingShell = async.isLoading && items.isEmpty;
    final error = async.hasError && items.isEmpty ? async.error : null;
    final viewportW = TvHomeLayout.viewportWidthOf(context);
    final sectionTitleSize = TvHomeLayout.sectionTitleSizeFor(viewportW);
    final headerGap = TvHomeLayout.sectionHeaderGapFor(viewportW);

    return LayoutBuilder(
      builder: (context, constraints) {
        final contentW = constraints.maxWidth;
        if (contentW < 200) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text(
                    '为你推荐',
                    style: HomeTypography.headlineLg(cs.onSurface).copyWith(
                      fontSize: sectionTitleSize,
                      height: 1.0,
                    ),
                    textHeightBehavior: TvHomeLayout.sectionHeaderTextBehavior,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _TvFilterTabs(
                  selected: _filter,
                  onChanged: (f) => setState(() => _filter = f),
                ),
              ],
            ),
            SizedBox(height: headerGap),
            Expanded(
              child: LayoutBuilder(
                builder: (context, railConstraints) {
                  final maxRailH = railConstraints.maxHeight;
                  return _buildRail(
                    items: items,
                    showLoadingShell: showLoadingShell,
                    error: error,
                    cs: cs,
                    contentW: contentW,
                    viewportW: viewportW,
                    maxRailH: maxRailH,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TvFilterTabs extends StatelessWidget {
  const _TvFilterTabs({
    required this.selected,
    required this.onChanged,
  });

  final HomeRecommendationFilter selected;
  final ValueChanged<HomeRecommendationFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    const filters = HomeRecommendationFilter.values;

    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          for (var i = 0; i < filters.length; i++) ...[
            if (i > 0) const SizedBox(width: 24),
            _TvFilterChip(
              label: homeRecommendationFilterLabel(filters[i]),
              selected: selected == filters[i],
              onActivate: () => onChanged(filters[i]),
              isFirst: i == 0,
              isLast: i == filters.length - 1,
            ),
          ],
        ],
      ),
    );
  }
}

class _TvFilterChip extends StatefulWidget {
  const _TvFilterChip({
    required this.label,
    required this.selected,
    required this.onActivate,
    this.isFirst = false,
    this.isLast = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onActivate;
  final bool isFirst;
  final bool isLast;

  @override
  State<_TvFilterChip> createState() => _TvFilterChipState();
}

class _TvFilterChipState extends State<_TvFilterChip> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final focused = _focused;
    final selected = widget.selected;

    final Color bg;
    final Color fg;
    final Border? border;

    if (focused) {
      bg = cs.primary;
      fg = cs.onPrimary;
      border = null;
    } else if (selected) {
      bg = cs.primaryContainer.withValues(alpha: 0.32);
      fg = cs.primary;
      border = Border.all(color: cs.primary.withValues(alpha: 0.45), width: 1);
    } else {
      bg = Colors.transparent;
      fg = cs.onSurfaceVariant;
      border = Border.all(color: cs.outlineVariant.withValues(alpha: 0.35), width: 1);
    }

    final style = HomeTypography.labelSm(fg).copyWith(
      fontWeight: selected || focused ? FontWeight.w700 : FontWeight.w500,
    );

    const focusPadH = 6.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        widget.isFirst ? 0 : focusPadH,
        0,
        widget.isLast ? 0 : focusPadH,
        0,
      ),
      child: TvFocusRing(
        onActivate: widget.onActivate,
        onFocusChange: (f) => setState(() => _focused = f),
        borderRadius: 8,
        scaleFocused: false,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.standard,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: border,
          ),
          child: Text(
            widget.label,
            style: style.copyWith(height: 1.0),
            textHeightBehavior: TvHomeLayout.sectionHeaderTextBehavior,
          ),
        ),
      ),
    );
  }
}
