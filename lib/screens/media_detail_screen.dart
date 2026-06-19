import 'package:cached_network_image/cached_network_image.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../config/app_config.dart';
import '../core/tv/tv_remote_actions.dart';
import '../core/player/playback_resume.dart';
import '../core/layout/platform_layout.dart';
import '../core/theme/app_motion.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_radius.dart';
import '../widgets/home/glass_surface.dart';
import '../core/logging/app_log.dart';
import '../models/emby/emby_media_item.dart';
import '../providers/emby_provider.dart';
import '../providers/settings_provider.dart';
import '../services/emby_service.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/error_view.dart';
import '../widgets/loading_indicator.dart';
import '../utils/media_navigation.dart';
import '../widgets/media_badges.dart';
import '../widgets/media_cast_section.dart';
import '../widgets/media_similar_section.dart';
import '../widgets/poster_skeleton.dart';
import '../widgets/tv/tv_focus_ring.dart';
import '../widgets/tv/tv_home_layout.dart';
import '../widgets/tv/tv_keyboard_handler.dart';

/// 详情页简介最大行数（Emby 式长简介；仍限制高度以免顶开分集区）。
const int kMediaDetailOverviewMaxLines = 6;

/// 对外为 [ConsumerWidget]；状态在 [_MediaDetailScreenBody]（与收窄为 `ConsumerWidget?` 的路由/封装兼容）。
class MediaDetailScreen extends ConsumerWidget {
  const MediaDetailScreen({super.key, required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _MediaDetailScreenBody(itemId: itemId);
  }
}

class _MediaDetailScreenBody extends ConsumerStatefulWidget {
  const _MediaDetailScreenBody({required this.itemId});

  final String itemId;

  @override
  ConsumerState<_MediaDetailScreenBody> createState() => _MediaDetailScreenBodyState();
}

class _MediaDetailScreenBodyState extends ConsumerState<_MediaDetailScreenBody> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToHero() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final asyncItem = ref.watch(embyItemProvider(widget.itemId));
    final emby = ref.watch(embyServiceProvider);

    return asyncItem.when(
      data: (item) {
        if (item.type == 'Series') {
          return _SeriesDetailPage(key: ValueKey(item.id), series: item);
        }
        return _buildNonSeriesScaffold(context, ref, emby, item);
      },
      loading: () => const Scaffold(body: LoadingIndicator()),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: ErrorView(
          error: e,
          onRetry: () => ref.invalidate(embyItemProvider(widget.itemId)),
        ),
      ),
    );
  }

  Widget _buildNonSeriesScaffold(
    BuildContext context,
    WidgetRef ref,
    EmbyService emby,
    EmbyMediaItem item,
  ) {
    final backdrop = emby.backdropUrlForItem(item);

    return _detailScrollBody(
      context,
      scrollController: context.isTvUi ? _scrollController : null,
      slivers: [
        _detailHeroSliver(
          context,
          ref,
          emby,
          item,
          item,
          null,
          heroIsSeries: false,
          itemIdForPlay: widget.itemId,
          onPlayFocusChange: context.isTvUi
              ? (focused) {
                  if (focused) _scrollToHero();
                }
              : null,
          overview: item.overview,
          backdropUrl: backdrop,
          topBar: _detailTopBarControls(
            context,
            title: item.name,
            logoUrl: emby.logoUrlForItem(item, maxHeight: 48, maxWidth: 280),
            imageHeaders: emby.imageAuthHeaders,
          ),
        ),
        MediaCastSliver(people: item.people, emby: emby),
        MediaSimilarItemsSliver(itemId: widget.itemId, emby: emby),
      ],
    );
  }
}

/// 电视剧：季列表与分集订阅拆到子树，避免在 [when] 分支中间歇 [ref.watch] 导致卸载断言。
class _SeriesDetailPage extends ConsumerStatefulWidget {
  const _SeriesDetailPage({super.key, required this.series});

  final EmbyMediaItem series;

  @override
  ConsumerState<_SeriesDetailPage> createState() => _SeriesDetailPageState();
}

class _SeriesDetailPageState extends ConsumerState<_SeriesDetailPage> {
  @override
  Widget build(BuildContext context) {
    final seasonsAsync = ref.watch(embySeasonsProvider(widget.series.id));

    return seasonsAsync.when(
      loading: () => const Scaffold(body: LoadingIndicator()),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: ErrorView(
          error: e,
          onRetry: () => ref.invalidate(embySeasonsProvider(widget.series.id)),
        ),
      ),
      data: (seasons) {
        final sorted = [...seasons]
          ..sort((a, b) => (a.indexNumber ?? 9999).compareTo(b.indexNumber ?? 9999));
        if (sorted.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: Text(widget.series.name)),
            body: const EmptyStateView(
              icon: Icons.layers_outlined,
              title: '暂无季信息',
              subtitle: '该剧集还没有可用的季数据',
            ),
          );
        }
        return _SeriesDetailLoaded(series: widget.series, sortedSeasons: sorted);
      },
    );
  }
}

class _SeriesDetailLoaded extends ConsumerStatefulWidget {
  const _SeriesDetailLoaded({
    required this.series,
    required this.sortedSeasons,
  });

  final EmbyMediaItem series;
  final List<EmbyMediaItem> sortedSeasons;

  @override
  ConsumerState<_SeriesDetailLoaded> createState() => _SeriesDetailLoadedState();
}

class _SeriesDetailLoadedState extends ConsumerState<_SeriesDetailLoaded> {
  String? _selectedSeasonId;
  bool _episodeSortAscending = true;
  String? _focusedEpisodeId;
  bool _hasAppliedNextUpSeason = false;
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToHero() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void _onTvBack() {
    if (_focusedEpisodeId != null) {
      setState(() => _focusedEpisodeId = null);
      _scrollToHero();
      return;
    }
    if (context.canPop()) context.pop();
  }

  void _onSeasonChanged(String newSeasonId) {
    setState(() {
      _selectedSeasonId = newSeasonId;
      _focusedEpisodeId = null;
    });
  }

  void _toggleEpisodeSort() {
    setState(() => _episodeSortAscending = !_episodeSortAscending);
  }

  String? _formatRuntime(int? runTimeTicks) {
    if (runTimeTicks == null || runTimeTicks <= 0) return null;
    const ticksPerMinute = 600000000;
    final totalMin = (runTimeTicks / ticksPerMinute).round();
    if (totalMin <= 0) return null;
    if (totalMin < 60) return '$totalMin 分钟';
    final h = totalMin ~/ 60;
    final m = totalMin % 60;
    if (m == 0) return '$h 小时';
    return '$h 小时 $m 分钟';
  }

  String _effectiveSeasonId() {
    final sorted = widget.sortedSeasons;
    final sel = _selectedSeasonId;
    if (sel != null && sorted.any((s) => s.id == sel)) {
      return sel;
    }
    return sorted.first.id;
  }

  String _episodeContextLine(EmbyMediaItem ep, EmbyMediaItem series) {
    final parts = <String>[];
    final sn = series.name.trim();
    if (sn.isNotEmpty) parts.add(sn);
    final p = ep.parentIndexNumber;
    final n = ep.indexNumber;
    if (p != null && n != null) {
      parts.add('S$p:E$n');
    } else if (n != null) {
      parts.add('第 $n 集');
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final emby = ref.watch(embyServiceProvider);
    final item = widget.series;
    final sorted = widget.sortedSeasons;

    // Fetch NextUp episode for this series
    final nextUpAsync = ref.watch(embyNextUpForSeriesProvider(item.id));
    final nextUpEpisode = nextUpAsync.whenOrNull<EmbyMediaItem?>(data: (v) => v);

    // Auto-select the season containing the NextUp episode (once)
    if (nextUpEpisode != null && !_hasAppliedNextUpSeason) {
      final nextUpSeasonId = nextUpEpisode.seasonId;
      if (nextUpSeasonId != null &&
          nextUpSeasonId != _selectedSeasonId &&
          sorted.any((s) => s.id == nextUpSeasonId)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_hasAppliedNextUpSeason) {
            setState(() {
              _selectedSeasonId = nextUpSeasonId;
              _hasAppliedNextUpSeason = true;
            });
          }
        });
      } else {
        _hasAppliedNextUpSeason = true;
      }
    }

    final effectiveSeasonId = _effectiveSeasonId();

    final episodesAsync = ref.watch(embyEpisodesProvider(effectiveSeasonId));

    // Determine scroll target: index of NextUp episode in the sorted list
    String? nextUpEpisodeId;
    if (nextUpEpisode != null && nextUpEpisode.seasonId == effectiveSeasonId) {
      nextUpEpisodeId = nextUpEpisode.id;
    }

    AppLog.instance.d('EpisodeScroll',
        'NextUp: episodeId=${nextUpEpisode?.id} seasonId=${nextUpEpisode?.seasonId} index=${nextUpEpisode?.indexNumber} name=${nextUpEpisode?.name} currentSeason=$effectiveSeasonId match=${nextUpEpisode?.seasonId == effectiveSeasonId}');

    final episodeList = episodesAsync.whenOrNull(data: (v) => v);
    final EmbyMediaItem? focusedEpisode = _focusedEpisodeId != null && episodeList != null
        ? episodeList.firstWhereOrNull((e) => e.id == _focusedEpisodeId)
        : null;

    final fe = focusedEpisode;
    final hero = fe ?? item;

    final backdrop = emby.backdropUrlForItem(hero, seriesParent: item);

    final appBarTitle = fe != null
        ? (fe.name.trim().isNotEmpty ? fe.name : '第 ${fe.indexNumber ?? ''} 集')
        : item.name;

    return _detailScrollBody(
      context,
      scrollController: context.isTvUi ? _scrollController : null,
      onBack: context.isTvUi ? _onTvBack : null,
      slivers: [
        _detailHeroSliver(
          context,
          ref,
          emby,
          item,
          hero,
          fe,
          heroIsSeries: true,
          itemIdForPlay: item.id,
          onClearEpisodeFocus: fe != null && !context.isTvUi
              ? () => setState(() => _focusedEpisodeId = null)
              : null,
          onPlayFocusChange: context.isTvUi
              ? (focused) {
                  if (focused) _scrollToHero();
                }
              : null,
          episodeContextLine: fe != null ? _episodeContextLine(fe, item) : null,
          formatRuntime: fe != null ? _formatRuntime(fe.runTimeTicks) : null,
          overview: hero.overview,
          backdropUrl: backdrop,
          topBar: _detailTopBarControls(
            context,
            title: appBarTitle,
            logoUrl: emby.logoUrlForItem(item, maxHeight: 48, maxWidth: 280),
            imageHeaders: emby.imageAuthHeaders,
          ),
        ),
        SliverToBoxAdapter(
          child: ColoredBox(
            color: Theme.of(context).colorScheme.surface,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: _SeriesEpisodePanel(
                sortedSeasons: sorted,
                effectiveSeasonId: effectiveSeasonId,
                onSeasonChanged: _onSeasonChanged,
                episodeSortAscending: _episodeSortAscending,
                onToggleSort: _toggleEpisodeSort,
                episodesAsync: episodesAsync,
                emby: emby,
                onEpisodeFocus: (id) => setState(() => _focusedEpisodeId = id),
                onPlayEpisode: (ep) => playMediaFromCard(context, emby, ep),
                nextUpEpisodeId: nextUpEpisodeId,
              ),
            ),
          ),
        ),
        MediaCastSliver(people: item.people, emby: emby),
        MediaSimilarItemsSliver(itemId: item.id, emby: emby),
      ],
    );
  }
}

/// 详情页主体：[CustomScrollView]；顶部栏与剧照同在 [_detailHeroSliver] 内，顶栏区背景透明且叠在剧照顶部区域。
Widget _detailScrollBody(
  BuildContext context, {
  required List<Widget> slivers,
  ScrollController? scrollController,
  VoidCallback? onBack,
}) {
  final surface = Theme.of(context).colorScheme.surface;
  final scroll = CustomScrollView(
    controller: scrollController,
    slivers: slivers,
  );

  if (context.isTvUi) {
    return TvRemoteActions(
      onBack: onBack ??
          () {
            if (context.canPop()) context.pop();
          },
      child: Scaffold(
        backgroundColor: surface,
        body: TvKeyboardHandler(
          child: FocusTraversalGroup(
            policy: OrderedTraversalPolicy(),
            child: scroll,
          ),
        ),
      ),
    );
  }

  return Scaffold(
    backgroundColor: surface,
    body: scroll,
  );
}

/// 圆角返回键，无 [SliverAppBar] 容器，避免与背景图产生分层线。
Widget _detailBackButton(BuildContext context) {
  const child = SizedBox(
    width: 40,
    height: 40,
    child: Center(
      child: Icon(Icons.arrow_back_rounded, size: 22, color: Colors.white),
    ),
  );

  if (context.isTvUi) {
    return TvFocusRing(
      onActivate: () {
        if (context.canPop()) context.pop();
      },
      borderRadius: 10,
      scaleFocused: false,
      child: const Material(
        color: Color(0x99000000),
        borderRadius: BorderRadius.all(Radius.circular(10)),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }

  return Material(
    color: const Color(0x99000000),
    borderRadius: BorderRadius.circular(10),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => Navigator.maybePop(context),
      child: child,
    ),
  );
}

double _detailTopBarHeight(BuildContext context) {
  return MediaQuery.paddingOf(context).top + kToolbarHeight;
}

/// 与 [EmbyService.logoUrlForItem] 的 maxWidth 一致，避免 Logo 加载时占满顶栏剩余宽度。
const double _detailTopBarLogoMaxWidth = 280;

/// 顶栏 Logo：用 [Image.network] 替代 [CachedNetworkImage]，避免 pop 后 octo 仍刷新 [ResizeImage]。
class _DetailTopBarLogo extends StatelessWidget {
  const _DetailTopBarLogo({
    required this.url,
    required this.headers,
    required this.fallback,
  });

  final String url;
  final Map<String, String> headers;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return Image.network(
      url,
      headers: headers,
      fit: BoxFit.contain,
      alignment: Alignment.centerLeft,
      width: _detailTopBarLogoMaxWidth,
      height: 26,
      cacheWidth: (_detailTopBarLogoMaxWidth * dpr).round(),
      cacheHeight: (26 * dpr).round(),
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => fallback,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return const SizedBox(
          width: _detailTopBarLogoMaxWidth,
          height: 26,
        );
      },
    );
  }
}

/// 安全区内一行 Logo/标题，背景透明，叠在剧照顶部区域。
Widget _detailTopBarControls(
  BuildContext context, {
  required String title,
  String? logoUrl,
  Map<String, String>? imageHeaders,
}) {
  final fallback = Text(
    title,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: const TextStyle(
      color: Colors.white,
      fontWeight: FontWeight.w600,
      shadows: [Shadow(blurRadius: 8, color: Color(0x66000000))],
    ),
  );
  final Widget titleWidget = (logoUrl != null && logoUrl.isNotEmpty)
      ? Semantics(
          label: title,
          child: Align(
            alignment: Alignment.centerLeft,
            child: _DetailTopBarLogo(
              url: logoUrl,
              headers: imageHeaders ?? const {},
              fallback: fallback,
            ),
          ),
        )
      : fallback;

  return Material(
    type: MaterialType.transparency,
    child: SafeArea(
      bottom: false,
      child: SizedBox(
        height: kToolbarHeight,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (!context.isTvUi) ...[
              const SizedBox(width: 8),
              _detailBackButton(context),
              const SizedBox(width: 8),
            ] else
              const SizedBox(width: 16),
            Expanded(
              child: IgnorePointer(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: titleWidget,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    ),
  );
}

double _detailBackdropBandHeight(Size screen) {
  if (isAndroidMobileUi) {
    return (screen.height * 0.32).clamp(180.0, 280.0);
  }
  return (screen.height * 0.42).clamp(320.0, 460.0);
}

/// 根据信息岛内剩余高度估算简介行数，使正文不超出岛高度（再与全局行数上限取较小值）。
int _overviewMaxLinesForBudget(BuildContext context, double heightPx, TextStyle style) {
  if (!heightPx.isFinite || heightPx <= 4) return 1;
  final scaler = MediaQuery.textScalerOf(context);
  final fs = scaler.scale(style.fontSize ?? 14);
  final lineFactor = style.height ?? 1.38;
  final linePx = fs * lineFactor;
  if (linePx <= 1) return 1;
  final n = (heightPx / linePx).floor();
  return n < 1 ? 1 : n;
}

String _formatMovieRuntime(int? runTimeTicks) {
  if (runTimeTicks == null || runTimeTicks <= 0) return '';
  const ticksPerMinute = 600000000;
  final totalMin = (runTimeTicks / ticksPerMinute).round();
  if (totalMin <= 0) return '';
  if (totalMin < 60) return '$totalMin 分钟';
  final h = totalMin ~/ 60;
  final m = totalMin % 60;
  if (m == 0) return '$h 时';
  return '$h 时 $m 分';
}

/// 元数据标签 Chip — 圆角半透明背景。
class _MetaChip extends StatelessWidget {
  const _MetaChip(this.label, {this.icon});
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: AppRadius.smR,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: cs.onSurfaceVariant),
          const SizedBox(width: 4),
        ],
        Text(label, style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant, fontWeight: FontWeight.w500)),
      ]),
    );
  }
}

Widget _detailHeroPosterStack({
  required BuildContext context,
  required ColorScheme cs,
  required String? imageUrl,
  required Map<String, String>? httpHeaders,
  required EmbyMediaItem item,
  required double fallbackIconSize,
}) {
  final badges = item.mediaSpecBadges;
  return Stack(
    fit: StackFit.expand,
    children: [
      if (imageUrl != null && imageUrl.isNotEmpty)
        CachedNetworkImage(
          imageUrl: imageUrl,
          httpHeaders: httpHeaders,
          fit: BoxFit.cover,
          memCacheHeight: AppConfig.posterMaxHeight,
          fadeInDuration: AppMotion.base,
          fadeInCurve: AppMotion.decelerate,
          placeholder: (_, __) => const PosterImageSkeleton(),
          errorWidget: (_, __, ___) => ColoredBox(
            color: cs.surfaceContainerHighest,
            child: Icon(Icons.movie, size: fallbackIconSize, color: cs.outline.withValues(alpha: 0.5)),
          ),
        )
      else
        ColoredBox(
          color: cs.surfaceContainerHighest,
          child: Center(
            child: Icon(Icons.movie, size: fallbackIconSize, color: cs.outline),
          ),
        ),
      if (badges.isNotEmpty)
        Positioned(
          right: 6,
          bottom: 6,
          child: MediaBadges(badges: badges),
        ),
    ],
  );
}

Widget _detailHeroSliver(
  BuildContext context,
  WidgetRef ref,
  EmbyService emby,
  EmbyMediaItem seriesItem,
  EmbyMediaItem hero,
  EmbyMediaItem? focusedEpisode, {
  required bool heroIsSeries,
  required String itemIdForPlay,
  VoidCallback? onClearEpisodeFocus,
  ValueChanged<bool>? onPlayFocusChange,
  String? episodeContextLine,
  String? formatRuntime,
  String? overview,
  String? backdropUrl,
  Widget? topBar,
}) {
  final theme = Theme.of(context);
  final cs = theme.colorScheme;
  final screen = MediaQuery.sizeOf(context);

  if (isAndroidMobileUi && !context.isTvUi) {
    return _detailHeroSliverMobile(
      context: context,
      ref: ref,
      emby: emby,
      seriesItem: seriesItem,
      hero: hero,
      focusedEpisode: focusedEpisode,
      heroIsSeries: heroIsSeries,
      itemIdForPlay: itemIdForPlay,
      onClearEpisodeFocus: onClearEpisodeFocus,
      formatRuntime: formatRuntime,
      overview: overview,
      backdropUrl: backdropUrl,
      topBar: topBar,
      theme: theme,
      cs: cs,
      screen: screen,
    );
  }

  final bandH = _detailBackdropBandHeight(screen);
  final topBarH = topBar != null ? _detailTopBarHeight(context) : 0.0;
  final totalH = bandH + topBarH;

  final poster = emby.posterUrlForItem(hero, maxHeight: 480);
  final fe = focusedEpisode;
  final overviewText = overview?.trim() ?? '';
  final hasOverview = overviewText.isNotEmpty;

  final innerH = (bandH - 28).clamp(180.0, 300.0);
  final posterH = innerH;
  final posterW = posterH * 2 / 3;

  // ── Hero 信息行（海报 + 信息卡片）──
  final heroRow = Padding(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 海报
        Hero(
          tag: 'poster-$itemIdForPlay',
          flightShuttleBuilder: (_, __, ___, ____, toHero) => toHero.widget,
          child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: posterW,
            height: posterH,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _detailHeroPosterStack(
                  context: context,
                  cs: cs,
                  imageUrl: poster,
                  httpHeaders: emby.imageAuthHeaders,
                  item: hero,
                  fallbackIconSize: posterW * 0.42,
                ),
                // 评分徽章
                if (hero.communityRating != null && hero.communityRating! > 0)
                  Positioned(
                    left: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.72),
                        borderRadius: AppRadius.xsR,
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.star_rounded, color: context.appColors.ratingStar, size: 14),
                        const SizedBox(width: 3),
                        Text(hero.communityRating!.toStringAsFixed(1),
                          style: TextStyle(color: context.appColors.ratingStar, fontSize: 12.5, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  ),
              ],
            ),
          ),
        ),
        ),
        const SizedBox(width: 18),

        // 信息卡片
        Expanded(
          child: SizedBox(
            height: posterH,
            child: ClipRRect(
              borderRadius: AppRadius.mdR,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh.withValues(alpha: 0.92),
                  boxShadow: [
                    BoxShadow(
                      color: cs.shadow.withValues(alpha: 0.10),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 标题
                      Flexible(
                        child: Text(
                          hero.name,
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w700,
                            height: 1.25,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),

                      const SizedBox(height: 8),

                      // 元数据标签行
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          // 年份
                          if (seriesItem.productionYear != null)
                            _MetaChip('${seriesItem.productionYear}', icon: Icons.calendar_today_outlined),
                          // 类型
                          _MetaChip(_typeLabel(seriesItem.type), icon: Icons.label_outline),
                          // 时长（电影/单集）
                          if (!heroIsSeries && seriesItem.runTimeTicks != null && seriesItem.runTimeTicks! > 0)
                            _MetaChip(_formatMovieRuntime(seriesItem.runTimeTicks), icon: Icons.schedule_outlined),
                          if (heroIsSeries && formatRuntime != null)
                            _MetaChip(formatRuntime, icon: Icons.schedule_outlined),
                          // 制片地
                          ...?_productionLocationChips(seriesItem.productionLocations),
                        ],
                      ),

                      const SizedBox(height: 10),

                      // 播放按钮区
                      if (!heroIsSeries &&
                          (seriesItem.type == 'Movie' ||
                              seriesItem.type == 'Episode' ||
                              seriesItem.type == 'Video'))
                        _ModernPlayButton(
                          autofocus: context.isTvUi,
                          traversalOrder: context.isTvUi ? 1 : null,
                          onPressed: () => playMediaFromCard(context, emby, seriesItem),
                          label: '播放',
                          onFocusChange: onPlayFocusChange,
                        ),
                      if (heroIsSeries) ...[
                        if (fe == null) ...[
                          _ModernPlayButton(
                            autofocus: context.isTvUi,
                            traversalOrder: context.isTvUi ? 1 : null,
                            onPressed: () => playMediaFromCard(context, emby, seriesItem),
                            label: context.isTvUi ? '播放' : '播放第一集',
                            onFocusChange: onPlayFocusChange,
                          ),
                          if (!context.isTvUi) ...[
                            const SizedBox(height: 4),
                            Text('或从下方选择一集',
                                style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                          ],
                        ] else ...[
                          _ModernPlayButton(
                            onPressed: () => playMediaFromCard(context, emby, fe),
                            label: context.isTvUi ? '播放' : '播放本集',
                            onFocusChange: onPlayFocusChange,
                          ),
                          if (!context.isTvUi && onClearEpisodeFocus != null) ...[
                            const SizedBox(width: 10),
                            TextButton.icon(
                              onPressed: onClearEpisodeFocus,
                              style: TextButton.styleFrom(
                                foregroundColor: cs.primary,
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                minimumSize: Size.zero,
                              ),
                              icon: const Icon(Icons.arrow_back_rounded, size: 16),
                              label: const Text('整部剧'),
                            ),
                          ],
                        ],
                      ],

                      // 简介
                      if (hasOverview)
                        Expanded(
                          child: LayoutBuilder(
                            builder: (ctx, c) {
                              final overviewStyle = theme.textTheme.bodyMedium!.copyWith(
                                color: cs.onSurface,
                                height: 1.45,
                                fontSize: 13.5,
                              );
                              final budget = c.maxHeight;
                              final byHeight = _overviewMaxLinesForBudget(ctx, budget, overviewStyle);
                              final maxLines = byHeight < kMediaDetailOverviewMaxLines ? byHeight : kMediaDetailOverviewMaxLines;
                              return Align(
                                alignment: Alignment.topLeft,
                                child: Text(
                                  overviewText,
                                  style: overviewStyle,
                                  maxLines: maxLines,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  final Widget band;
  if (backdropUrl != null && backdropUrl.isNotEmpty) {
    band = Stack(
      clipBehavior: Clip.hardEdge,
      fit: StackFit.expand,
      children: [
        CachedNetworkImage(
          imageUrl: backdropUrl,
          httpHeaders: emby.imageAuthHeaders,
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          errorWidget: (_, __, ___) => const ColoredBox(color: Colors.black45),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0.0, 0.50, 0.70, 0.88, 1.0],
              colors: [
                Colors.transparent,
                Colors.transparent,
                cs.surface.withValues(alpha: 0.12),
                cs.surface.withValues(alpha: 0.55),
                cs.surface,
              ],
            ),
          ),
        ),
        if (topBar != null)
          Positioned(top: 0, left: 0, right: 0, child: topBar),
        Positioned(left: 0, right: 0, bottom: 0, child: heroRow),
      ],
    );
  } else {
    band = ColoredBox(
    color: cs.surface,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (topBar != null)
            Positioned(top: 0, left: 0, right: 0, child: topBar),
          Align(alignment: Alignment.bottomCenter, child: heroRow),
        ],
      ),
    );
  }

  return SliverToBoxAdapter(
    child: SizedBox(height: totalH, width: double.infinity, child: band),
  );
}

Widget _detailHeroSliverMobile({
  required BuildContext context,
  required WidgetRef ref,
  required EmbyService emby,
  required EmbyMediaItem seriesItem,
  required EmbyMediaItem hero,
  required EmbyMediaItem? focusedEpisode,
  required bool heroIsSeries,
  required String itemIdForPlay,
  VoidCallback? onClearEpisodeFocus,
  String? formatRuntime,
  String? overview,
  String? backdropUrl,
  Widget? topBar,
  required ThemeData theme,
  required ColorScheme cs,
  required Size screen,
}) {
  final bandH = _detailBackdropBandHeight(screen);
  final topBarH = topBar != null ? _detailTopBarHeight(context) : 0.0;
  final poster = emby.posterUrlForItem(hero, maxHeight: 480);
  final fe = focusedEpisode;
  final overviewText = overview?.trim() ?? '';
  final hasOverview = overviewText.isNotEmpty;
  const posterW = 120.0;
  const posterH = 180.0;
  const hPad = kMobileHorizontalPadding;

  Widget posterWidget = ClipRRect(
    borderRadius: AppRadius.mdR,
    child: SizedBox(
      width: posterW,
      height: posterH,
      child: _detailHeroPosterStack(
        context: context,
        cs: cs,
        imageUrl: poster,
        httpHeaders: emby.imageAuthHeaders,
        item: hero,
        fallbackIconSize: 48,
      ),
    ),
  );

  Widget infoCard = ClipRRect(
    borderRadius: AppRadius.mdR,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh.withValues(alpha: 0.95),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              hero.name,
              style: theme.textTheme.titleLarge?.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (seriesItem.productionYear != null)
                  _MetaChip('${seriesItem.productionYear}', icon: Icons.calendar_today_outlined),
                _MetaChip(_typeLabel(seriesItem.type), icon: Icons.label_outline),
                if (!heroIsSeries && seriesItem.runTimeTicks != null && seriesItem.runTimeTicks! > 0)
                  _MetaChip(_formatMovieRuntime(seriesItem.runTimeTicks), icon: Icons.schedule_outlined),
                if (heroIsSeries && formatRuntime != null)
                  _MetaChip(formatRuntime, icon: Icons.schedule_outlined),
                ...?_productionLocationChips(seriesItem.productionLocations),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!heroIsSeries &&
                    (seriesItem.type == 'Movie' ||
                        seriesItem.type == 'Episode' ||
                        seriesItem.type == 'Video'))
                  _ModernPlayButton(
                    onPressed: () => playMediaFromCard(context, emby, seriesItem),
                    label: '播放',
                  ),
                if (heroIsSeries && fe == null)
                  _ModernPlayButton(
                    onPressed: () => playMediaFromCard(context, emby, seriesItem),
                    label: '播放第一集',
                  ),
                if (heroIsSeries && fe != null) ...[
                  _ModernPlayButton(
                    onPressed: () => playMediaFromCard(context, emby, fe),
                    label: '播放本集',
                  ),
                  if (onClearEpisodeFocus != null)
                    TextButton.icon(
                      onPressed: onClearEpisodeFocus,
                      icon: const Icon(Icons.arrow_back_rounded, size: 16),
                      label: const Text('整部剧'),
                    ),
                ],
              ],
            ),
            if (hasOverview) ...[
              const SizedBox(height: 12),
              Text(
                overviewText,
                style: theme.textTheme.bodyMedium!.copyWith(
                  color: cs.onSurface,
                  height: 1.45,
                  fontSize: 13.5,
                ),
                maxLines: kMediaDetailOverviewMaxLines,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    ),
  );

  Widget backdropSection;
  if (backdropUrl != null && backdropUrl.isNotEmpty) {
    backdropSection = SizedBox(
      height: bandH + topBarH,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CachedNetworkImage(
            imageUrl: backdropUrl,
            httpHeaders: emby.imageAuthHeaders,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            errorWidget: (_, __, ___) => const ColoredBox(color: Colors.black45),
          ),
          DecoratedBox(
            decoration: homeMediaBackdropScrim(HomeMediaScrimShape.hero),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.0, 0.55, 1.0],
                colors: [
                  Colors.transparent,
                  cs.surface.withValues(alpha: 0.35),
                  cs.surface,
                ],
              ),
            ),
          ),
          if (topBar != null) Positioned(top: 0, left: 0, right: 0, child: topBar),
        ],
      ),
    );
  } else {
    backdropSection = SizedBox(
      height: topBarH + 56,
      width: double.infinity,
      child: ColoredBox(
        color: cs.surface,
        child: topBar != null
            ? Align(alignment: Alignment.topCenter, child: topBar)
            : null,
      ),
    );
  }

  return SliverToBoxAdapter(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        backdropSection,
        Padding(
          padding: const EdgeInsets.fromLTRB(hPad, 12, hPad, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              posterWidget,
              const SizedBox(height: 14),
              infoCard,
            ],
          ),
        ),
      ],
    ),
  );
}

/// 现代化播放按钮：accent 色圆角药丸。
class _ModernPlayButton extends StatelessWidget {
  const _ModernPlayButton({
    required this.onPressed,
    required this.label,
    this.autofocus = false,
    this.traversalOrder,
    this.onFocusChange,
  });

  final VoidCallback onPressed;
  final String label;
  final bool autofocus;
  final double? traversalOrder;
  final ValueChanged<bool>? onFocusChange;

  @override
  Widget build(BuildContext context) {
    if (context.isTvUi) {
      return TvDetailPlayButton(
        onActivate: onPressed,
        autofocus: autofocus,
        traversalOrder: traversalOrder,
        onFocusChange: onFocusChange,
      );
    }

    final colors = context.appColors;
    return FilledButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.play_arrow_rounded, size: 20),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.3)),
      style: FilledButton.styleFrom(
        foregroundColor: colors.onPlayAction,
        backgroundColor: colors.playAction,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.smR),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        elevation: 0,
        minimumSize: isAndroidMobileUi ? const Size(48, 48) : Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

/// 类型中文标签。
String _typeLabel(String type) {
  switch (type) {
    case 'Movie':
    case 'Video': return '电影';
    case 'Series': return '剧集';
    case 'Episode': return '分集';
    case 'Season': return '季';
    default: return type;
  }
}

List<Widget>? _productionLocationChips(List<String>? locations) {
  if (locations == null || locations.isEmpty) return null;
  final first = locations.first.trim();
  if (first.isEmpty) return null;
  return [_MetaChip(first, icon: Icons.location_on_outlined)];
}

// ══════════════════════════════════════════ 分集面板 ══════════════════════════════════════════

class _SeriesEpisodePanel extends StatefulWidget {
  const _SeriesEpisodePanel({
    required this.sortedSeasons,
    required this.effectiveSeasonId,
    required this.onSeasonChanged,
    required this.episodeSortAscending,
    required this.onToggleSort,
    required this.episodesAsync,
    required this.emby,
    required this.onEpisodeFocus,
    required this.onPlayEpisode,
    this.nextUpEpisodeId,
  });

  final List<EmbyMediaItem> sortedSeasons;
  final String effectiveSeasonId;
  final ValueChanged<String> onSeasonChanged;
  final bool episodeSortAscending;
  final VoidCallback onToggleSort;
  final AsyncValue<List<EmbyMediaItem>> episodesAsync;
  final EmbyService emby;
  final ValueChanged<String> onEpisodeFocus;
  final void Function(EmbyMediaItem episode) onPlayEpisode;
  final String? nextUpEpisodeId;

  @override
  State<_SeriesEpisodePanel> createState() => _SeriesEpisodePanelState();
}

class _SeriesEpisodePanelState extends State<_SeriesEpisodePanel> {
  bool _panelExpanded = false;
  int? _quickRangeStart; // null = show all, otherwise show [start, start+49]

  String _seasonLabel(EmbyMediaItem s, int displayIndex) {
    final n = s.name.trim();
    if (n.isNotEmpty) return n;
    return '${s.indexNumber ?? displayIndex + 1}';
  }

  String _episodeTitle(EmbyMediaItem ep, int index) {
    final n = ep.indexNumber ?? index + 1;
    final t = ep.name.trim();
    if (t.isEmpty) return '第$n集';
    if (RegExp(r'^第\s*\d+\s*集').hasMatch(t)) return t;
    return '第$n集 $t';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('分集列表', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const Spacer(),
            _EpisodePanelButton(
              icon: Icons.swap_vert,
              label: widget.episodeSortAscending ? '正序' : '倒序',
              onPressed: widget.onToggleSort,
            ),
            const SizedBox(width: 8),
            _EpisodePanelButton(
              icon: _panelExpanded ? Icons.unfold_less : Icons.unfold_more,
              label: _panelExpanded ? '收起' : '选集',
              onPressed: () => setState(() => _panelExpanded = !_panelExpanded),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (widget.sortedSeasons.length > 1)
          Align(
            alignment: Alignment.centerLeft,
            child: _CompactSeasonMenu(
              sortedSeasons: widget.sortedSeasons,
              effectiveSeasonId: widget.effectiveSeasonId,
              seasonLabel: _seasonLabel,
              onChanged: widget.onSeasonChanged,
            ),
          )
        else
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _seasonLabel(widget.sortedSeasons.first, 0),
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        const SizedBox(height: 12),
        widget.episodesAsync.when(
          data: (raw) {
            var list = [...raw]
              ..sort((a, b) {
                final cmp = (a.indexNumber ?? 1 << 20).compareTo(b.indexNumber ?? 1 << 20);
                return widget.episodeSortAscending ? cmp : -cmp;
              });
            if (list.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: EmptyStateView(
                  compact: true,
                  icon: Icons.video_library_outlined,
                  title: '本季暂无分集',
                  subtitle: '试试选择其他季',
                  iconColor: Colors.white54,
                  titleStyle: TextStyle(color: Colors.white54),
                  subtitleStyle: TextStyle(color: Colors.white38),
                ),
              );
            }

            // Compute max episode number for range selector (before filtering)
            final maxEpNum = list.isEmpty
                ? 0
                : list.map((e) => e.indexNumber ?? 0).reduce((a, b) => a > b ? a : b);

            // Quick range filter: scroll to target instead of filtering out episodes
            final rangeStart = _quickRangeStart;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Quick range selector
                _EpisodeRangeSelector(
                  maxEpisodeNumber: maxEpNum,
                  selectedStart: rangeStart,
                  onSelect: (start) {
                    setState(() {
                      _quickRangeStart = _quickRangeStart == start ? null : start;
                      if (!_panelExpanded) _panelExpanded = true;
                    });
                  },
                ),
                const SizedBox(height: 10),
                // Horizontal scrollable episode card list
                _EpisodeCardRow(
                  episodes: list,
                  emby: widget.emby,
                  nextUpEpisodeId: widget.nextUpEpisodeId,
                  scrollToEpisodeNumber: rangeStart,
                  onEpisodeFocus: widget.onEpisodeFocus,
                  onPlayEpisode: widget.onPlayEpisode,
                  titleFor: _episodeTitle,
                ),
              ],
            );
          },
          loading: () => const SizedBox(
            height: 100,
            child: LoadingIndicator.posterRow(
              posterRowHeight: 100,
              posterRowItemWidth: 72,
              posterRowItemCount: 5,
            ),
          ),
          error: (e, _) => ErrorView(error: e, compact: true),
        ),
      ],
    );
  }
}

/// Quick episode range selector: e.g., 1-50, 51-100, 101-150...
class _EpisodeRangeSelector extends StatelessWidget {
  const _EpisodeRangeSelector({
    required this.maxEpisodeNumber,
    required this.selectedStart,
    required this.onSelect,
  });

  final int maxEpisodeNumber;
  final int? selectedStart;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    if (maxEpisodeNumber <= 0) return const SizedBox.shrink();

    final ranges = <({String label, int start})>[];
    for (var start = 1; start <= maxEpisodeNumber; start += 50) {
      final end = (start + 49).clamp(1, maxEpisodeNumber);
      ranges.add((label: '$start-$end', start: start));
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final r in ranges)
          _RangeChip(
            label: r.label,
            selected: selectedStart == r.start,
            onTap: () => onSelect(r.start),
          ),
      ],
    );
  }
}

class _EpisodePanelButton extends StatelessWidget {
  const _EpisodePanelButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    if (context.isTvUi) {
      return TvFocusActionButton(
        label: label,
        icon: icon,
        filled: false,
        onActivate: onPressed,
      );
    }
    return Tooltip(
      message: label,
      child: FilledButton.tonalIcon(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        label: Text(label, style: Theme.of(context).textTheme.labelLarge),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          visualDensity: VisualDensity.compact,
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.smR),
        ),
      ),
    );
  }
}

class _RangeChip extends StatelessWidget {
  const _RangeChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const borderRadius = AppRadius.smR;

    final child = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          color: selected ? cs.onPrimary : cs.onSurfaceVariant,
        ),
      ),
    );

    if (context.isTvUi) {
      return TvFocusRing(
        onActivate: onTap,
        borderRadius: AppRadius.sm,
        scaleFocused: false,
        child: Material(
          color: selected ? cs.primary : cs.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: borderRadius,
          child: child,
        ),
      );
    }

    return Material(
      color: selected ? cs.primary : cs.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: borderRadius,
      child: InkWell(
        borderRadius: borderRadius,
        onTap: onTap,
        child: child,
      ),
    );
  }
}

/// Horizontal scrollable episode card list with poster thumbnails and progress bar.
class _EpisodeCardRow extends StatefulWidget {
  const _EpisodeCardRow({
    required this.episodes,
    required this.emby,
    required this.nextUpEpisodeId,
    this.scrollToEpisodeNumber,
    required this.onEpisodeFocus,
    required this.onPlayEpisode,
    required this.titleFor,
  });

  final List<EmbyMediaItem> episodes;
  final EmbyService emby;
  final String? nextUpEpisodeId;
  final int? scrollToEpisodeNumber;
  final ValueChanged<String> onEpisodeFocus;
  final void Function(EmbyMediaItem episode) onPlayEpisode;
  final String Function(EmbyMediaItem ep, int index) titleFor;

  @override
  State<_EpisodeCardRow> createState() => _EpisodeCardRowState();
}

class _EpisodeCardRowState extends State<_EpisodeCardRow> {
  final ScrollController _scroll = ScrollController();
  final ValueNotifier<bool> _canScrollLeftNotifier = ValueNotifier(false);
  final ValueNotifier<bool> _canScrollRightNotifier = ValueNotifier(false);

  static const _cardWidth = 140.0;
  static const _separatorW = 10.0;
  static const _posterAr = 16 / 9;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToTarget();
      _updateScrollNotifiers();
    });
  }

  void _onScroll() {
    _updateScrollNotifiers();
  }

  void _updateScrollNotifiers() {
    if (!mounted) return;
    _canScrollLeftNotifier.value = _scroll.hasClients && _scroll.offset > 1;
    _canScrollRightNotifier.value =
        _scroll.hasClients && _scroll.offset < _scroll.position.maxScrollExtent - 1;
  }

  void _nudge(int direction) {
    if (!_scroll.hasClients) return;
    final max = _scroll.position.maxScrollExtent;
    if (max <= 0) return;
    const step = (_cardWidth + _separatorW) * 3;
    final target = (_scroll.offset + direction * step).clamp(0.0, max);
    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void didUpdateWidget(_EpisodeCardRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nextUpEpisodeId != widget.nextUpEpisodeId ||
        oldWidget.scrollToEpisodeNumber != widget.scrollToEpisodeNumber) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToTarget();
      });
    }
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _canScrollLeftNotifier.dispose();
    _canScrollRightNotifier.dispose();
    super.dispose();
  }

  void _scrollToTarget() {
    if (!_scroll.hasClients) return;

    // Priority 1: scroll to the episode number requested by range selector
    final targetEpNum = widget.scrollToEpisodeNumber;
    if (targetEpNum != null) {
      final idx = widget.episodes.indexWhere((e) => (e.indexNumber ?? 0) >= targetEpNum);
      if (idx >= 0) {
        final targetOffset = (idx * (_cardWidth + _separatorW)).clamp(
          0.0,
          _scroll.position.maxScrollExtent,
        );
        _scroll.animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
        return;
      }
    }

    // Priority 2: scroll to next-up episode
    final nextUpId = widget.nextUpEpisodeId;
    if (nextUpId == null) return;
    final idx = widget.episodes.indexWhere((e) => e.id == nextUpId);
    if (idx < 0) return;
    final targetOffset = (idx * (_cardWidth + _separatorW)).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    _scroll.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = widget.episodes;
    final emby = widget.emby;
    final nextUpId = widget.nextUpEpisodeId;
    const posterH = _cardWidth / _posterAr; // ~78.75
    const gapPosterTitle = 6.0;
    const titleH = 38.0; // two lines of text at fontSize 12.5, height 1.5
    final isTv = context.isTvUi;
    final focusPad = isTv ? TvHomeLayout.focusBorderWidth : 0.0;
    final cardH = posterH + gapPosterTitle + titleH + focusPad + 4; // +4 安全边距防止溢出

    final listView = SizedBox(
      height: cardH,
      child: ListView.separated(
        controller: _scroll,
        clipBehavior: Clip.hardEdge,
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.fromLTRB(2 + focusPad, focusPad, 2 + focusPad, 0),
        itemCount: list.length,
        separatorBuilder: (_, __) => const SizedBox(width: _separatorW),
        itemBuilder: (context, index) {
          final ep = list[index];
          final isNextUp = ep.id == nextUpId;
          final url = emby.posterUrlForItem(ep, maxHeight: AppConfig.posterMaxHeight);
          final progress = ep.userDataPlayedPercentage;
          return SizedBox(
            width: _cardWidth,
            child: _EpisodeCard(
              imageUrl: url,
              title: widget.titleFor(ep, index),
              isNextUp: isNextUp,
              progress: progress,
              httpHeaders: emby.imageAuthHeaders,
              onTap: () => widget.onEpisodeFocus(ep.id),
              onPlay: () => widget.onPlayEpisode(ep),
            ),
          );
        },
      ),
    );

    if (!context.isDesktopUi && !context.isTvUi) return listView;

    if (context.isTvUi) return listView;

    final cs = Theme.of(context).colorScheme;

    Widget arrowButton({
      required ValueNotifier<bool> notifier,
      required IconData icon,
      required String tooltip,
      required int direction,
    }) {
      return ValueListenableBuilder<bool>(
        valueListenable: notifier,
        builder: (_, canScroll, __) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: SizedBox(
            height: posterH,
            child: Center(
              child: IconButton(
                tooltip: tooltip,
                onPressed: canScroll ? () => _nudge(direction) : null,
                icon: Icon(
                  icon,
                  color: canScroll ? cs.onSurface : cs.outlineVariant,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        arrowButton(
          notifier: _canScrollLeftNotifier,
          icon: Icons.chevron_left,
          tooltip: '向左',
          direction: -1,
        ),
        Expanded(child: listView),
        arrowButton(
          notifier: _canScrollRightNotifier,
          icon: Icons.chevron_right,
          tooltip: '向右',
          direction: 1,
        ),
      ],
    );
  }
}

/// Emby [PlayedPercentage] 多为 0–100；转为进度条 0–1。已看完（≥99.5%）不显示。
double? _episodeProgressFraction(double? raw) {
  final pct = normalizePlayedPercentage(raw);
  if (pct == null || pct <= 0 || pct >= 99.5) return null;
  return (pct / 100.0).clamp(0.0, 1.0);
}

class _EpisodeCard extends StatelessWidget {
  const _EpisodeCard({
    required this.imageUrl,
    required this.title,
    required this.isNextUp,
    this.progress,
    this.httpHeaders,
    required this.onTap,
    required this.onPlay,
  });

  final String? imageUrl;
  final String title;
  final bool isNextUp;
  final double? progress;
  final Map<String, String>? httpHeaders;
  final VoidCallback onTap;
  final VoidCallback onPlay;

  void _ensureVisible(BuildContext context) {
    Scrollable.ensureVisible(
      context,
      alignment: 0.5,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final colors = context.appColors;
    final progressFraction = _episodeProgressFraction(progress);
    const posterAr = 16 / 9;
    const posterH = 140.0 / posterAr;

    Widget posterBody = Stack(
      fit: StackFit.expand,
      children: [
        if (imageUrl != null)
          CachedNetworkImage(
            imageUrl: imageUrl!,
            httpHeaders: httpHeaders ?? const {},
            fit: BoxFit.cover,
            memCacheHeight: AppConfig.posterMaxHeight,
            errorWidget: (_, __, ___) => ColoredBox(
              color: cs.surfaceContainerHighest,
              child: Center(
                child: Icon(Icons.movie, size: 32, color: cs.outline.withValues(alpha: 0.5)),
              ),
            ),
          )
        else
          ColoredBox(
            color: cs.surfaceContainerHighest,
            child: Center(
              child: Icon(Icons.movie, size: 32, color: cs.outline.withValues(alpha: 0.5)),
            ),
          ),
        // 正在播放标签
        if (isNextUp)
          Positioned(
            top: 6,
            left: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                '正在播放',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        if (progressFraction != null)
          Align(
            alignment: Alignment.bottomCenter,
            child: LinearProgressIndicator(
              value: progressFraction,
              minHeight: 4,
              color: colors.progressActive,
              backgroundColor: colors.scrimStrong,
              borderRadius: AppRadius.xsR,
            ),
          ),
        if (!context.isTvUi)
          Positioned(
            bottom: 4,
            right: 4,
            child: Material(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: AppRadius.xsR,
              child: InkWell(
                borderRadius: AppRadius.xsR,
                onTap: onPlay,
                child: const SizedBox(
                  width: 28,
                  height: 28,
                  child: Center(
                    child: Icon(Icons.play_arrow_rounded, size: 18, color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
      ],
    );

    final poster = ClipRRect(
      borderRadius: AppRadius.smR,
      child: SizedBox(height: posterH, child: posterBody),
    );

    if (context.isTvUi) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TvFocusRing(
            onActivate: onPlay,
            borderRadius: 8,
            scaleFocused: false,
            onFocusChange: (focused) {
              if (focused) {
                onTap();
                _ensureVisible(context);
              }
            },
            child: poster,
          ),
          const SizedBox(height: 6),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: isNextUp ? FontWeight.w600 : FontWeight.w400,
              color: cs.onSurface,
              height: 1.5,
            ),
          ),
        ],
      );
    }

    final card = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        poster,
        const SizedBox(height: 6),
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: isNextUp ? FontWeight.w600 : FontWeight.w400,
            color: cs.onSurface,
            height: 1.5,
          ),
        ),
      ],
    );

    return Semantics(
      button: true,
      label: title,
      child: GestureDetector(
        onTap: onTap,
        child: card,
      ),
    );
  }
}

/// 紧凑圆角触发器 + 下方菜单（勾选当前季、浅底与阴影），替代 [InputDecorator]/[DropdownButton]。
class _CompactSeasonMenu extends StatelessWidget {
  const _CompactSeasonMenu({
    required this.sortedSeasons,
    required this.effectiveSeasonId,
    required this.seasonLabel,
    required this.onChanged,
  });

  final List<EmbyMediaItem> sortedSeasons;
  final String effectiveSeasonId;
  final String Function(EmbyMediaItem s, int displayIndex) seasonLabel;
  final ValueChanged<String> onChanged;

  Future<void> _showTvSeasonPicker(BuildContext context) async {
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('选择季'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < sortedSeasons.length; i++)
                TvFocusListTile(
                  title: seasonLabel(sortedSeasons[i], i),
                  trailing: sortedSeasons[i].id == effectiveSeasonId
                      ? Icon(Icons.check, color: Theme.of(ctx).colorScheme.primary)
                      : null,
                  onActivate: () => Navigator.pop(ctx, sortedSeasons[i].id),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final idx = sortedSeasons.indexWhere((s) => s.id == effectiveSeasonId);
    final safeIdx = idx >= 0 ? idx : 0;
    final currentLabel = seasonLabel(sortedSeasons[safeIdx], safeIdx);

    if (context.isTvUi) {
      final cs = Theme.of(context).colorScheme;
      const focusPad = TvHomeLayout.focusBorderWidth;
      return Padding(
        padding: const EdgeInsets.all(focusPad),
        child: TvFocusRing(
          onActivate: () => _showTvSeasonPicker(context),
          borderRadius: AppRadius.sm,
          scaleFocused: false,
          child: Material(
            color: cs.surfaceContainerHighest,
            borderRadius: AppRadius.smR,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    currentLabel,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.expand_more, size: 20, color: cs.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final cs = Theme.of(context).colorScheme;

    return MenuAnchor(
      consumeOutsideTap: true,
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(cs.surfaceContainerHigh),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(4),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm))),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 4)),
        minimumSize: const WidgetStatePropertyAll(Size(160, 0)),
      ),
      menuChildren: [
        for (var i = 0; i < sortedSeasons.length; i++)
          MenuItemButton(
            leadingIcon: SizedBox(
              width: 22,
              child: Align(
                alignment: Alignment.centerLeft,
                child: sortedSeasons[i].id == effectiveSeasonId
                    ? Icon(Icons.check, size: 18, color: cs.primary)
                    : const SizedBox.shrink(),
              ),
            ),
            onPressed: () {
              onChanged(sortedSeasons[i].id);
              MenuController.maybeOf(context)?.close();
            },
            child: Text(seasonLabel(sortedSeasons[i], i), overflow: TextOverflow.ellipsis),
          ),
      ],
      builder: (context, menuController, _) {
        return Material(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: AppRadius.smR,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            borderRadius: AppRadius.smR,
            onTap: () {
              if (menuController.isOpen) { menuController.close(); } else { menuController.open(); }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(currentLabel, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurface)),
                  const SizedBox(width: 2),
                  Icon(menuController.isOpen ? Icons.expand_less : Icons.expand_more, size: 20, color: cs.onSurfaceVariant),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}