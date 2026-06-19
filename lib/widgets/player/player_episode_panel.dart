import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/emby/emby_media_item.dart';
import '../../providers/emby_provider.dart';
import '../empty_state_view.dart';
import '../loading_indicator.dart';

/// Widget that performs layout but skips painting — used to hide the episode
/// list while scroll alignment is in progress without paying the paint cost of
/// [Opacity(opacity: 0)].
class _SkipPaintWidget extends SingleChildRenderObjectWidget {
  const _SkipPaintWidget({required this.skipPaint, super.child});

  final bool skipPaint;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSkipPaint(skipPaint);

  @override
  void updateRenderObject(BuildContext context, _RenderSkipPaint renderObject) {
    renderObject.skipPaint = skipPaint;
  }
}

class _RenderSkipPaint extends RenderProxyBox {
  _RenderSkipPaint(this._skipPaint);

  bool _skipPaint;

  set skipPaint(bool value) {
    if (_skipPaint == value) return;
    _skipPaint = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_skipPaint) return;
    super.paint(context, offset);
  }
}

/// Right-side episode picker overlay for [PlayerScreen].
class PlayerEpisodePanel extends ConsumerStatefulWidget {
  const PlayerEpisodePanel({
    super.key,
    required this.episode,
    required this.playingEpisodeId,
    required this.onClose,
    required this.onSelectEpisode,
    this.mobileLayout = false,
    this.centeredSheet = false,
  });

  final EmbyMediaItem episode;
  final String playingEpisodeId;
  final VoidCallback onClose;
  final ValueChanged<String> onSelectEpisode;
  final bool mobileLayout;
  /// Android centered sheet: rounded on all corners + full safe-area insets.
  final bool centeredSheet;

  @override
  ConsumerState<PlayerEpisodePanel> createState() => _PlayerEpisodePanelState();
}

class _PlayerEpisodePanelState extends ConsumerState<PlayerEpisodePanel> {
  static const _episodeRangeSize = 50;
  /// Fixed row height — must match [ListView.itemExtent] for accurate range jumps.
  static const _episodeRowHeight = 48.0;

  late String _selectedSeasonId;
  ScrollController? _scrollController;

  /// List hidden until scroll is aligned to the playing episode (no animated scroll).
  bool _listScrollReady = false;
  bool _alignScheduled = false;

  /// Active quick-range start (1, 51, 101, …). Null = align to playing episode.
  int? _activeRangeStart;

  /// Tracks which season the current [_scrollController] was built for.
  String? _scrollSeasonId;

  @override
  void initState() {
    super.initState();
    _selectedSeasonId = widget.episode.seasonId!;
  }

  @override
  void didUpdateWidget(PlayerEpisodePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playingEpisodeId != widget.playingEpisodeId) {
      _disposeScrollController();
      _listScrollReady = false;
      _alignScheduled = false;
      _activeRangeStart = null;
    }
  }

  @override
  void dispose() {
    _disposeScrollController();
    super.dispose();
  }

  void _disposeScrollController() {
    _scrollController?.dispose();
    _scrollController = null;
    _scrollSeasonId = null;
  }

  bool get _isPlayingSeason => _selectedSeasonId == widget.episode.seasonId;

  List<EmbyMediaItem> _sortedEpisodes(List<EmbyMediaItem> raw) {
    final list = [...raw]
      ..sort(
        (a, b) =>
            (a.indexNumber ?? 1 << 20).compareTo(b.indexNumber ?? 1 << 20),
      );
    return list;
  }

  List<({int start, int end})> _episodeRanges(List<EmbyMediaItem> list) {
    if (list.length <= _episodeRangeSize) return const [];
    final maxEp = list.last.indexNumber ?? list.length;
    final ranges = <({int start, int end})>[];
    for (var start = 1; start <= maxEp; start += _episodeRangeSize) {
      final end = (start + _episodeRangeSize - 1).clamp(start, maxEp);
      ranges.add((start: start, end: end));
    }
    return ranges;
  }

  int _indexForEpisodeNumber(List<EmbyMediaItem> list, int episodeNumber) {
    for (var i = 0; i < list.length; i++) {
      final epNum = list[i].indexNumber ?? i + 1;
      if (epNum >= episodeNumber) return i;
    }
    return 0;
  }

  int? _rangeStartForEpisodeNumber(int episodeNumber) {
    if (episodeNumber <= _episodeRangeSize) return 1;
    return ((episodeNumber - 1) ~/ _episodeRangeSize) * _episodeRangeSize + 1;
  }

  void _resetScrollState({bool clearRange = true}) {
    _disposeScrollController();
    _listScrollReady = false;
    _alignScheduled = false;
    if (clearRange) _activeRangeStart = null;
  }

  void _jumpToEpisodeRange(List<EmbyMediaItem> list, int rangeStart) {
    setState(() => _activeRangeStart = rangeStart);

    void scroll() {
      final controller = _scrollController;
      if (controller == null || !controller.hasClients) return;
      final idx = _indexForEpisodeNumber(list, rangeStart);
      final target =
          (idx * _episodeRowHeight).clamp(0.0, controller.position.maxScrollExtent);
      controller.jumpTo(target);
    }

    if (_scrollController?.hasClients == true) {
      scroll();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) scroll();
      });
    }
    if (!_listScrollReady) setState(() => _listScrollReady = true);
  }

  int? _effectiveRangeStart(List<EmbyMediaItem> list) {
    if (list.length <= _episodeRangeSize) return null;
    if (_activeRangeStart != null) return _activeRangeStart;
    if (_isPlayingSeason) {
      final idx = list.indexWhere((e) => e.id == widget.playingEpisodeId);
      if (idx >= 0) {
        final epNum = list[idx].indexNumber ?? idx + 1;
        return _rangeStartForEpisodeNumber(epNum);
      }
    }
    return 1;
  }

  /// Row height — kept in sync with [ListView.itemExtent].
  double get _episodeRowExtent => _episodeRowHeight;

  double _estimatedScrollOffset(List<EmbyMediaItem> list, BuildContext context) {
    final extent = _episodeRowExtent;
    final rangeStart = _effectiveRangeStart(list);
    if (rangeStart != null) {
      final idx = _indexForEpisodeNumber(list, rangeStart);
      return idx * extent;
    }
    if (!_isPlayingSeason) return 0;
    final idx = list.indexWhere((e) => e.id == widget.playingEpisodeId);
    if (idx <= 0) return 0;
    final viewport = MediaQuery.sizeOf(context).height * 0.55;
    return (idx * extent - viewport * 0.35).clamp(0.0, double.infinity);
  }

  ScrollController _controllerForSeason(List<EmbyMediaItem> list) {
    if (_scrollController != null && _scrollSeasonId == _selectedSeasonId) {
      return _scrollController!;
    }
    _disposeScrollController();
    final initial = _estimatedScrollOffset(list, context);
    _scrollController = ScrollController(initialScrollOffset: initial);
    _scrollSeasonId = _selectedSeasonId;
    return _scrollController!;
  }

  void _fineTuneScroll(List<EmbyMediaItem> list) {
    final controller = _scrollController;
    if (controller == null || !controller.hasClients) return;

    final rangeStart = _effectiveRangeStart(list);
    if (rangeStart != null) {
      final idx = _indexForEpisodeNumber(list, rangeStart);
      final target = (idx * _episodeRowHeight).clamp(0.0, controller.position.maxScrollExtent);
      if ((controller.offset - target).abs() > 1) controller.jumpTo(target);
      if (!_listScrollReady) setState(() => _listScrollReady = true);
      return;
    }

    if (!_isPlayingSeason) {
      if (controller.offset != 0) controller.jumpTo(0);
      if (!_listScrollReady) setState(() => _listScrollReady = true);
      return;
    }

    final idx = list.indexWhere((e) => e.id == widget.playingEpisodeId);
    if (idx <= 0) {
      if (!_listScrollReady) setState(() => _listScrollReady = true);
      return;
    }

    final extent = _episodeRowExtent;
    final pos = controller.position;
    final target =
        (idx * extent - pos.viewportDimension * 0.35).clamp(0.0, pos.maxScrollExtent);
    if ((controller.offset - target).abs() > 1) {
      controller.jumpTo(target);
    }
    if (!_listScrollReady) setState(() => _listScrollReady = true);
  }

  void _scheduleFineTuneScroll(List<EmbyMediaItem> list) {
    if (_listScrollReady || _alignScheduled) return;
    _alignScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _alignScheduled = false;
      if (!mounted || _listScrollReady) return;
      _fineTuneScroll(list);
    });
  }

  String _seasonLabel(EmbyMediaItem s, int displayIndex) {
    final n = s.name.trim();
    if (n.isNotEmpty) return n;
    return '第 ${s.indexNumber ?? displayIndex + 1} 季';
  }

  Widget _buildRangeChip({
    required int start,
    required int end,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? const Color(0x28FFFFFF) : const Color(0x0FFFFFFF),
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            '$start-$end',
            style: TextStyle(
              color: selected ? const Color(0xFFE8E8E8) : const Color(0x99E8E8E8),
              fontSize: 12.5,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSeasonAndRangeRow({
    required List<EmbyMediaItem> seasons,
    required List<EmbyMediaItem>? episodes,
  }) {
    final episodeList = episodes == null ? null : _sortedEpisodes(episodes);
    final ranges =
        episodeList == null ? const [] : _episodeRanges(episodeList);
    final activeRange =
        episodeList == null ? null : _effectiveRangeStart(episodeList);

    Widget seasonControl;
    if (seasons.length == 1) {
      seasonControl = Text(
        _seasonLabel(seasons.first, 0),
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0x99E8E8E8),
            ),
      );
    } else {
      seasonControl = _PlayerSeasonMenu(
        sortedSeasons: seasons,
        effectiveSeasonId: _selectedSeasonId,
        seasonLabel: _seasonLabel,
        onChanged: (id) {
          setState(() {
            _selectedSeasonId = id;
            _resetScrollState();
          });
        },
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          seasonControl,
          if (ranges.isNotEmpty && episodeList != null) ...[
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 34,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.zero,
                  clipBehavior: Clip.hardEdge,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < ranges.length; i++) ...[
                        if (i > 0) const SizedBox(width: 6),
                        Builder(
                          builder: (context) {
                            final r = ranges[i];
                            final selected = activeRange == r.start;
                            return _buildRangeChip(
                              start: r.start,
                              end: r.end,
                              selected: selected,
                              onTap: () => _jumpToEpisodeRange(episodeList, r.start),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final seriesId = widget.episode.seriesId;
    if (seriesId == null) return const SizedBox.shrink();

    final seasonsAsync = ref.watch(embySeasonsProvider(seriesId));
    final episodesAsync = ref.watch(embyEpisodesProvider(_selectedSeasonId));
    final panelWidth = widget.mobileLayout
        ? MediaQuery.sizeOf(context).width
        : (MediaQuery.sizeOf(context).width * 0.38).clamp(280.0, 360.0);

    final panel = Material(
      color: const Color(0xEE101010),
      elevation: widget.mobileLayout ? 0 : 12,
      shadowColor: Colors.black54,
      borderRadius: widget.mobileLayout
          ? (widget.centeredSheet
              ? BorderRadius.circular(16)
              : const BorderRadius.vertical(top: Radius.circular(16)))
          : const BorderRadius.horizontal(left: Radius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        // Centered sheet is already inset from screen edges — skip horizontal
        // safe padding so the panel content stays visually centered in landscape.
        left: !widget.mobileLayout || !widget.centeredSheet,
        top: widget.mobileLayout,
        right: !widget.centeredSheet,
        bottom: widget.centeredSheet,
        child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 12, 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.episode.seriesName?.trim().isNotEmpty == true
                                ? widget.episode.seriesName!.trim()
                                : '选集',
                            style: const TextStyle(
                              color: Color(0xFFE8E8E8),
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Material(
                          color: const Color(0x1AFFFFFF),
                          borderRadius: BorderRadius.circular(10),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: widget.onClose,
                            child: const SizedBox(
                              width: 36, height: 36,
                              child: Center(
                                child: Icon(Icons.close_rounded, color: Color(0xFFE8E8E8), size: 20),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  seasonsAsync.when(
                      data: (raw) {
                        final sorted = [...raw]
                          ..sort(
                            (a, b) => (a.indexNumber ?? 1 << 20)
                                .compareTo(b.indexNumber ?? 1 << 20),
                          );
                        if (sorted.isEmpty) return const SizedBox.shrink();
                        final episodes = episodesAsync.asData?.value;
                        return _buildSeasonAndRangeRow(
                          seasons: sorted,
                          episodes: episodes,
                        );
                      },
                      loading: () => const SizedBox(
                        height: 36,
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ),
                      error: (_, __) => const SizedBox.shrink(),
                    ),
                  const SizedBox(height: 8),
                  const Divider(height: 1, color: Color(0x14FFFFFF)),
                  Expanded(
                    child: episodesAsync.when(
                      data: (raw) {
                        final list = _sortedEpisodes(raw);
                        if (list.isEmpty) {
                          return const Center(
                            child: EmptyStateView(
                              compact: true,
                              icon: Icons.video_library_outlined,
                              title: '本季暂无分集',
                              iconColor: Colors.white54,
                              titleStyle: TextStyle(color: Colors.white54),
                            ),
                          );
                        }
                        _scheduleFineTuneScroll(list);
                        final scrollController = _controllerForSeason(list);
                        return _SkipPaintWidget(
                          skipPaint: !_listScrollReady,
                          child: ListView.builder(
                            controller: scrollController,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            itemExtent: _episodeRowHeight,
                            itemCount: list.length,
                            itemBuilder: (context, i) {
                              final e = list[i];
                              final isPlaying = e.id == widget.playingEpisodeId;
                              final epNum = e.indexNumber ?? i + 1;
                              final title = e.name.trim().isEmpty ? '第 $epNum 集' : e.name.trim();
                              return Material(
                                color: isPlaying
                                    ? const Color(0x18FFFFFF)
                                    : Colors.transparent,
                                child: DecoratedBox(
                                  decoration: const BoxDecoration(
                                    border: Border(
                                      bottom: BorderSide(
                                        color: Color(0x18FFFFFF),
                                        width: 1,
                                      ),
                                    ),
                                  ),
                                  child: _PlayerEpisodeRow(
                                    episodeNumber: epNum,
                                    title: title,
                                    isPlaying: isPlaying,
                                    onTap: isPlaying
                                        ? null
                                        : () => widget.onSelectEpisode(e.id),
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                      loading: () => const LoadingIndicator(),
                      error: (err, _) => Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            '$err',
                            style: const TextStyle(color: Colors.white54),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
        ),
      ),
    );

    if (widget.mobileLayout) {
      return panel;
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onClose,
            child: const ColoredBox(color: Color(0x66000000)),
          ),
        ),
        Positioned(
          top: 0,
          right: 0,
          bottom: 0,
          width: panelWidth,
          child: panel,
        ),
      ],
    );
  }
}

/// Episode row for the player panel — plain index number, high-contrast text.
class _PlayerEpisodeRow extends StatelessWidget {
  static const _numberColumnWidth = 44.0;

  const _PlayerEpisodeRow({
    required this.episodeNumber,
    required this.title,
    this.isPlaying = false,
    this.onTap,
  });

  final int episodeNumber;
  final String title;
  final bool isPlaying;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final numberColor = isPlaying
        ? const Color(0xFFE8E8E8)
        : const Color(0x99E8E8E8);
    final titleColor = isPlaying
        ? const Color(0xFFE8E8E8)
        : const Color(0xCCE8E8E8);

    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: _PlayerEpisodePanelState._episodeRowHeight,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: _numberColumnWidth,
                child: Text(
                  '$episodeNumber',
                  maxLines: 1,
                  overflow: TextOverflow.visible,
                  softWrap: false,
                  style: TextStyle(
                    color: numberColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: titleColor,
                    fontSize: 14,
                    fontWeight: isPlaying ? FontWeight.w600 : FontWeight.w400,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact season dropdown (player panel styling).
class _PlayerSeasonMenu extends StatelessWidget {
  const _PlayerSeasonMenu({
    required this.sortedSeasons,
    required this.effectiveSeasonId,
    required this.seasonLabel,
    required this.onChanged,
  });

  final List<EmbyMediaItem> sortedSeasons;
  final String effectiveSeasonId;
  final String Function(EmbyMediaItem s, int displayIndex) seasonLabel;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final idx = sortedSeasons.indexWhere((s) => s.id == effectiveSeasonId);
    final safeIdx = idx >= 0 ? idx : 0;
    final currentLabel = seasonLabel(sortedSeasons[safeIdx], safeIdx);

    return MenuAnchor(
      consumeOutsideTap: true,
      style: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(Color(0xFF212121)),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(4),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
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
                    ? const Icon(Icons.check, size: 18, color: Color(0xFFE8E8E8))
                    : const SizedBox.shrink(),
              ),
            ),
            onPressed: () {
              onChanged(sortedSeasons[i].id);
              MenuController.maybeOf(context)?.close();
            },
            child: Text(
              seasonLabel(sortedSeasons[i], i),
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      builder: (context, menuController, _) {
        return Material(
          color: const Color(0x1AFFFFFF),
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              if (menuController.isOpen) {
                menuController.close();
              } else {
                menuController.open();
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    currentLabel,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFFE8E8E8),
                        ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    menuController.isOpen ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: const Color(0x99E8E8E8),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
