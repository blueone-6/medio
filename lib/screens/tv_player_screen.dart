import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/logging/app_log.dart';
import '../core/logging/perf.dart';
import '../core/player/episode_navigation.dart';
import '../core/player/playback_resume.dart';
import '../core/player/player_codec_error.dart';
import '../core/player/player_home_refresh.dart';
import '../core/player/tv_exo/tv_exo_player.dart';
import '../core/player/tv_exo/tv_exo_video_view.dart';
import '../core/tv/tv_remote_actions.dart' show TvRemoteActions, TvRemoteSelectKeys;
import '../core/player/external_cdn_headers.dart';
import '../models/emby/emby_media_item.dart';
import '../models/emby/emby_playback_info.dart';
import '../providers/settings_provider.dart';
import '../services/emby_service.dart';
import '../utils/playback_http_headers.dart';
import '../utils/player_route.dart';
import '../widgets/error_view.dart';
import '../widgets/loading_indicator.dart';
import '../widgets/player/player_episode_panel.dart';
import '../widgets/player/player_top_info.dart';
import '../widgets/player/tv_exo_player_controls.dart';

/// Android TV playback screen — ExoPlayer (Media3) + SurfaceView.
///
/// Phone / desktop keep [PlayerScreen] (media_kit / libmpv).
class TvPlayerScreen extends ConsumerStatefulWidget {
  const TvPlayerScreen({
    super.key,
    required this.itemId,
    this.hintPositionTicks,
  });

  final String itemId;
  final int? hintPositionTicks;

  @override
  ConsumerState<TvPlayerScreen> createState() => _TvPlayerScreenState();
}

class _TvPlayerScreenState extends ConsumerState<TvPlayerScreen> {
  static const _chromeHideDelay = Duration(seconds: 4);

  late final TvExoPlayer _player;
  final FocusNode _playerFocusNode = FocusNode(debugLabel: 'tv_player');
  EmbyService? _emby;
  EmbyPlaybackInfo? _info;
  EmbyMediaItem? _currentItem;

  bool _loading = true;
  bool _reconnecting = false;
  String? _error;
  bool _showChrome = true;
  bool _leavingPlayer = false;
  bool _playbackReportedStopped = false;
  bool _codecFallbackAttempted = false;
  bool _codecFallbackInProgress = false;
  bool _episodeSwitching = false;

  Future<void>? _progressReportInFlight;
  int? _lastReportedPositionTicks;

  Timer? _progressTimer;
  Timer? _chromeIdleTimer;
  Timer? _settleTimeoutTimer;
  StreamSubscription<String>? _errorSub;
  StreamSubscription<void>? _completedSub;
  StreamSubscription<void>? _readySub;
  StreamSubscription<TvExoPlayerState>? _stateSub;

  TvExoPlayerState _exoState = const TvExoPlayerState();
  PerfSpan? _bootstrapSpan;
  Duration _resumeTarget = Duration.zero;
  bool _playbackSettled = false;

  final ValueNotifier<bool> _episodeListOpenNotifier =
      ValueNotifier<bool>(false);
  List<EmbyMediaItem>? _episodes;
  bool _hasPrevEpisode = false;
  bool _hasNextEpisode = false;

  DateTime _lastSeekAt = DateTime.now();
  ProviderContainer? _riverpodContainer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _riverpodContainer ??= ProviderScope.containerOf(context);
  }

  @override
  void initState() {
    super.initState();
    _player = TvExoPlayer();
    _stateSub = _player.stateStream.listen((s) {
      if (!mounted) return;
      setState(() => _exoState = s);
      _trySettlePlayback('position');
    });
    _readySub = _player.readyStream.listen((_) {
      _trySettlePlayback('ready');
    });
    _errorSub = _player.errorStream.listen((msg) {
      unawaited(_handlePlaybackError(msg));
    });
    _completedSub = _player.completedStream.listen((_) {
      unawaited(_onPlaybackCompleted());
    });
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
    unawaited(_bootstrap());
  }

  bool _onHardwareKey(KeyEvent event) {
    if (!mounted) return false;
    return _handlePlayerKey(_playerFocusNode, event) == KeyEventResult.handled;
  }

  @override
  void dispose() {
    _chromeIdleTimer?.cancel();
    _settleTimeoutTimer?.cancel();
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    _playerFocusNode.dispose();
    _progressTimer?.cancel();
    _errorSub?.cancel();
    _completedSub?.cancel();
    _readySub?.cancel();
    _stateSub?.cancel();
    _bootstrapSpan?.end(extraContext: {'settle_via': 'dispose'});
    _bootstrapSpan = null;
    _episodeListOpenNotifier.dispose();
    if (!_episodeSwitching && !_leavingPlayer) {
      _cancelProgressReporting();
      unawaited(_reportStoppedIfNeeded());
    }
    unawaited(_player.dispose());
    super.dispose();
  }

  void _resetPlaybackSettle(Duration resumeAt) {
    _settleTimeoutTimer?.cancel();
    _playbackSettled = false;
    _resumeTarget = resumeAt;
  }

  void _installPlaybackSettleWatcher(PerfSpan span) {
    _bootstrapSpan?.end(extraContext: {'settle_via': 'replaced'});
    _bootstrapSpan = span;
    _settleTimeoutTimer?.cancel();
    _settleTimeoutTimer = Timer(const Duration(seconds: 15), () {
      _onPlaybackSettled('timeout');
    });
    _trySettlePlayback('install');
  }

  void _trySettlePlayback(String reason) {
    if (_playbackSettled || !_loading) return;
    final pos = _exoState.position;
    if (isResumePositionSettled(pos, _resumeTarget)) {
      _onPlaybackSettled(reason);
      return;
    }
    if (_resumeTarget <= Duration.zero &&
        _exoState.isPlaying &&
        pos.inMilliseconds > 50) {
      _onPlaybackSettled('playing');
    }
  }

  void _onPlaybackSettled(String reason) {
    if (_playbackSettled) return;
    _playbackSettled = true;
    _settleTimeoutTimer?.cancel();
    _settleTimeoutTimer = null;
    final span = _bootstrapSpan;
    if (span != null) {
      span.end(extraContext: {'settle_via': reason});
      _bootstrapSpan = null;
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _reconnecting = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _playerFocusNode.requestFocus();
      _scheduleChromeHide();
    });
  }

  Future<void> _bootstrap() async {
    final span = PerfTracer.start('tv_player_bootstrap');
    try {
      _lastSeekAt = DateTime.now();
      final emby = ref.read(embyServiceProvider);
      _emby = emby;
      final settings = ref.read(settingsServiceProvider);
      final startTimeTicks = widget.hintPositionTicks ?? 0;

      final results = await Future.wait<Object>([
        emby.getPlaybackInfo(
          widget.itemId,
          startTimeTicks: startTimeTicks,
        ),
        emby.getItemForPlayer(widget.itemId),
      ]);
      if (!mounted) return;

      final pb = results[0] as EmbyPlaybackInfo;
      final item = results[1] as EmbyMediaItem;
      _currentItem = item;
      _info = pb;

      final resumeAt = resumePlaybackPosition(
        playbackPositionTicks:
            startTimeTicks > 0 ? startTimeTicks : widget.hintPositionTicks,
        runTimeTicks: pb.runTimeTicks,
      );

      final openUrl = pb.streamUrl;
      if (!mounted) return;

      final headers = playbackHttpHeaders(
        openUrl,
        embyServerBase: settings.embyServerUrl,
        embyToken: settings.embyAccessToken,
      ) ?? (isExternalCdnPlaybackUrl(openUrl)
          ? externalCdnPlaybackHttpHeaders()
          : (pb.strmViaEmbyStream
              ? externalCdnPlaybackHttpHeaders()
              : null));

      final subtitle = pb.preferredExoTextSubtitle;
      final isHdr = item.isHdr;
      final videoRange = item.videoRange;
      AppLog.instance.i(
        'TvPlayer',
        'open itemId=${widget.itemId} url=$openUrl '
            'resume=${resumeAt?.inSeconds}s subtitle=${subtitle?.label} '
            'exo=${subtitle != null} hdr=$isHdr range=$videoRange',
      );

      final resumeTarget = resumeAt ?? Duration.zero;
      _resetPlaybackSettle(resumeTarget);

      await _player.setSource(
        url: openUrl,
        headers: headers,
        startPosition: resumeTarget,
        subtitleUrl: subtitle?.exoStreamUrl,
        subtitleMime: subtitle != null ? exoSubtitleMimeForEmby(subtitle) : null,
        isHdrContent: isHdr,
        videoRange: videoRange,
      );

      if (!mounted) return;

      _installPlaybackSettleWatcher(span);

      final reportTicks = resumeTarget > Duration.zero
          ? (resumeTarget.inMicroseconds * 10).clamp(0, 1 << 62).toInt()
          : startTimeTicks;
      unawaited(emby.reportPlaybackStarted(
        itemId: widget.itemId,
        mediaSourceId: pb.mediaSourceId,
        playSessionId: pb.playSessionId,
        positionTicks: reportTicks,
      ));

      _progressTimer ??= Timer.periodic(
        const Duration(seconds: 10),
        (_) => unawaited(_reportProgress()),
      );

      unawaited(_fetchEpisodes());

      final speed = settings.defaultPlaybackSpeed;
      if (speed != 1.0) {
        unawaited(_player.setPlaybackSpeed(speed));
      }
    } catch (e, st) {
      span.endError(e, st);
      _bootstrapSpan = null;
      AppLog.instance.e('TvPlayer', 'bootstrap failed', error: e, stackTrace: st);
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _handlePlaybackError(String raw) async {
    if (!mounted || _codecFallbackInProgress) return;
    if (isRecoverablePlayerCodecError(raw) && !_codecFallbackAttempted) {
      await _handleCodecFallback(raw);
      return;
    }
    if (mounted) {
      setState(() {
        _error = playerCodecErrorFinalMessage(raw);
        _loading = false;
      });
    }
  }

  Future<void> _handleCodecFallback(String raw) async {
    if (_codecFallbackAttempted || _codecFallbackInProgress) return;
    final emby = _emby;
    if (emby == null) return;

    _codecFallbackAttempted = true;
    _codecFallbackInProgress = true;
    try {
      setState(() {
        _error = null;
        _loading = true;
        _reconnecting = true;
      });

      final ticks = (_exoState.position.inMicroseconds * 10)
          .clamp(0, 1 << 62)
          .toInt();
      final pb = await emby.getPlaybackInfo(
        widget.itemId,
        startTimeTicks: ticks > 0 ? ticks : (widget.hintPositionTicks ?? 0),
      );
      if (!mounted) return;

      await _player.stop();
      _info = pb;
      final openUrl = pb.streamUrl;
      if (!mounted) return;

      final settings = ref.read(settingsServiceProvider);
      final headers = playbackHttpHeaders(
        openUrl,
        embyServerBase: settings.embyServerUrl,
        embyToken: settings.embyAccessToken,
      ) ?? (isExternalCdnPlaybackUrl(openUrl)
          ? externalCdnPlaybackHttpHeaders()
          : (pb.strmViaEmbyStream
              ? externalCdnPlaybackHttpHeaders()
              : null));

      final resumeAt = Duration(
        microseconds: (ticks > 0 ? ticks : 0) ~/ 10,
      );
      final subtitle = pb.preferredExoTextSubtitle;
      final item = _currentItem;
      final isHdr = item?.isHdr ?? false;
      final videoRange = item?.videoRange;

      _resetPlaybackSettle(resumeAt);
      final fallbackSpan = PerfTracer.start('tv_player_codec_fallback');

      await _player.setSource(
        url: openUrl,
        headers: headers,
        startPosition: resumeAt,
        subtitleUrl: subtitle?.exoStreamUrl,
        subtitleMime: subtitle != null ? exoSubtitleMimeForEmby(subtitle) : null,
        isHdrContent: isHdr,
        videoRange: videoRange,
      );

      if (mounted) {
        _installPlaybackSettleWatcher(fallbackSpan);
      } else {
        fallbackSpan.end(extraContext: {'settle_via': 'unmounted'});
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = playerCodecErrorFinalMessage(raw);
          _loading = false;
          _reconnecting = false;
        });
      }
    } finally {
      _codecFallbackInProgress = false;
    }
  }

  Future<void> _reportProgress({bool flushing = false}) async {
    final i = _info;
    final emby = _emby;
    if (i == null || emby == null || _playbackReportedStopped) return;
    if (!flushing && !mounted) return;

    final task = _reportProgressOnce(i, emby);
    _progressReportInFlight = task;
    try {
      await task;
    } finally {
      if (identical(_progressReportInFlight, task)) {
        _progressReportInFlight = null;
      }
    }
  }

  Future<void> _reportProgressOnce(EmbyPlaybackInfo i, EmbyService emby) async {
    if (_playbackReportedStopped) return;
    final pos = _exoState.position;
    final ticks = (pos.inMicroseconds * 10).clamp(0, 1 << 62).toInt();
    if (_playbackReportedStopped) return;
    await emby.reportProgress(
      itemId: widget.itemId,
      mediaSourceId: i.mediaSourceId,
      playSessionId: i.playSessionId,
      positionTicks: ticks,
      isPaused: !_exoState.isPlaying,
    );
    _lastReportedPositionTicks = ticks;
    _maybeRecordPlayHistory(ticks, i.runTimeTicks);
  }

  void _maybeRecordPlayHistory(int positionTicks, int? runTimeTicks) {
    if (runTimeTicks == null || runTimeTicks <= 0) return;
    if (positionTicks < runTimeTicks * 0.05) return;
    final item = _currentItem;
    if (item == null) return;
    try {
      unawaited(ref.read(playHistoryServiceProvider).recordPlay(
            itemId: item.id,
            type: item.type,
            seriesId: item.seriesId,
          ));
    } catch (_) {}
  }

  int? _playbackExitPositionTicks() {
    final pos = _exoState.position;
    if (pos > Duration.zero) {
      return (pos.inMicroseconds * 10).clamp(0, 1 << 62).toInt();
    }
    return _lastReportedPositionTicks;
  }

  Future<void> _reportStoppedIfNeeded({int? positionTicks}) async {
    if (_playbackReportedStopped) return;
    _cancelProgressReporting();

    final inFlight = _progressReportInFlight;
    if (inFlight != null) {
      try {
        await inFlight;
      } catch (_) {}
    }
    if (_playbackReportedStopped) return;

    final i = _info;
    final emby = _emby;
    if (i == null || emby == null) return;
    final ticks = positionTicks ?? _playbackExitPositionTicks() ?? 0;
    _playbackReportedStopped = true;
    await emby.reportPlaybackStopped(
      itemId: widget.itemId,
      mediaSourceId: i.mediaSourceId,
      playSessionId: i.playSessionId,
      positionTicks: ticks,
    );
  }

  void _cancelProgressReporting() {
    _progressTimer?.cancel();
    _progressTimer = null;
  }

  Future<void> _fetchEpisodes() async {
    final item = _currentItem;
    if (item?.seasonId == null) return;
    final emby = _emby;
    if (emby == null) return;
    try {
      final episodes = sortEpisodesByIndex(await emby.getEpisodes(item!.seasonId!));
      if (!mounted) return;
      final adj = adjacentEpisodesInSeason(episodes, widget.itemId);
      setState(() {
        _episodes = episodes;
        _hasPrevEpisode = adj.previous != null;
        _hasNextEpisode = adj.next != null;
      });
    } catch (_) {}
  }

  Future<void> _onPlaybackCompleted() async {
    if (_loading) return;
    if (DateTime.now().difference(_lastSeekAt).inSeconds < 3) return;
    final pos = _exoState.position;
    final dur = _exoState.duration;
    if (!isPlaybackNearEnd(pos, dur)) return;

    if (!_playbackReportedStopped) {
      final ticks = (pos.inMicroseconds * 10).clamp(0, 1 << 62).toInt();
      await _reportStoppedIfNeeded(positionTicks: ticks);
    }

    final settings = ref.read(settingsServiceProvider);
    if (!settings.autoPlayNext) return;
    final item = _currentItem;
    if (item?.seasonId == null) return;

    List<EmbyMediaItem> episodes = _episodes ?? [];
    if (episodes.isEmpty) {
      final emby = _emby;
      if (emby == null) return;
      try {
        episodes = sortEpisodesByIndex(await emby.getEpisodes(item!.seasonId!));
      } catch (_) {
        return;
      }
    }
    final next = adjacentEpisodesInSeason(episodes, widget.itemId).next;
    if (next == null || !mounted) return;
    _episodeSwitching = true;
    context.replace(playerRouteForItem(next.id));
  }

  void _leavePlayer() {
    if (_leavingPlayer) return;
    _leavingPlayer = true;
    final exitTicks = _playbackExitPositionTicks();
    unawaited(() async {
      await _reportStoppedIfNeeded(positionTicks: exitTicks);
      await _player.stop();
    }());
    final container = _riverpodContainer;
    if (container != null) schedulePlayerHomeDataRefresh(container);
    if (mounted && context.canPop()) context.pop();
  }

  void _scheduleChromeHide() {
    _chromeIdleTimer?.cancel();
    if (!_showChrome) return;
    _chromeIdleTimer = Timer(_chromeHideDelay, () {
      if (mounted) setState(() => _showChrome = false);
    });
  }

  void _onUserInteraction() {
    if (!mounted) return;
    if (!_showChrome) {
      setState(() => _showChrome = true);
    }
    _scheduleChromeHide();
  }

  void _onVideoTap() {
    setState(() => _showChrome = !_showChrome);
    if (_showChrome) {
      _scheduleChromeHide();
    } else {
      _chromeIdleTimer?.cancel();
    }
  }

  void _togglePlayPause() {
    if (_exoState.isPlaying) {
      unawaited(_player.pause());
    } else {
      unawaited(_player.play());
    }
    _onUserInteraction();
  }

  void _seekBy(int seconds) {
    final target = _exoState.position + Duration(seconds: seconds);
    final clamped = target < Duration.zero ? Duration.zero : target;
    _lastSeekAt = DateTime.now();
    unawaited(_player.seekTo(clamped));
    _onUserInteraction();
  }

  KeyEventResult _handlePlayerKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      _seekBy(-10);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _seekBy(10);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaRewind) {
      _seekBy(-30);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaFastForward) {
      _seekBy(30);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaPlayPause ||
        key == LogicalKeyboardKey.mediaPlay ||
        key == LogicalKeyboardKey.mediaPause ||
        key == LogicalKeyboardKey.space) {
      _togglePlayPause();
      return KeyEventResult.handled;
    }
    if (TvRemoteSelectKeys.isSelect(key)) {
      if (!_showChrome) {
        _onUserInteraction();
      } else {
        _togglePlayPause();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      _onUserInteraction();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _onSelectEpisode(String episodeId) {
    _episodeListOpenNotifier.value = false;
    final exitTicks = _playbackExitPositionTicks();
    unawaited(_reportStoppedIfNeeded(positionTicks: exitTicks));
    _episodeSwitching = true;
    if (mounted) context.replace(playerRouteForItem(episodeId));
  }

  void _goToAdjacentEpisode({bool next = true}) {
    final episodes = _episodes;
    if (episodes == null) return;
    final adj = adjacentEpisodesInSeason(episodes, widget.itemId);
    final target = next ? adj.next : adj.previous;
    if (target != null) _onSelectEpisode(target.id);
  }

  Future<void> _retryPlayback() async {
    setState(() {
      _error = null;
      _loading = true;
      _codecFallbackAttempted = false;
    });
    await _bootstrap();
  }

  bool get _showEpisodeControls =>
      _currentItem?.type == 'Episode' && (_episodes?.isNotEmpty ?? false);

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: _leavePlayer,
          ),
        ),
        body: ErrorView(message: _error!, onRetry: () => unawaited(_retryPlayback())),
      );
    }

    return TvRemoteActions(
      onBack: _leavePlayer,
      onPlayPause: _togglePlayPause,
      onFastForward: () => _seekBy(30),
      onRewind: () => _seekBy(-30),
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _leavePlayer();
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            fit: StackFit.expand,
            children: [
              const Center(
                child: TvExoVideoView(),
              ),
              if (_loading)
                ColoredBox(
                  color: Colors.black87,
                  child: LoadingIndicator(
                    message: _reconnecting ? '正在重连…' : '正在准备播放…',
                  ),
                ),
              // Key + tap layer above PlatformView (native view steals Flutter focus).
              if (!_loading)
                Positioned.fill(
                  child: Focus(
                    focusNode: _playerFocusNode,
                    autofocus: true,
                    onKeyEvent: _handlePlayerKey,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: _onVideoTap,
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
                if (_showChrome && !_loading)
                  ValueListenableBuilder<bool>(
                    valueListenable: _episodeListOpenNotifier,
                    builder: (context, episodeListOpen, _) {
                      if (episodeListOpen) return const SizedBox.shrink();
                      return PlayerTopInfo(
                        title: _currentItem?.name ?? '',
                        onBack: _leavePlayer,
                      );
                    },
                  ),
                ValueListenableBuilder<bool>(
                  valueListenable: _episodeListOpenNotifier,
                  builder: (context, episodeListOpen, _) {
                    if (!_showChrome || _loading || episodeListOpen) {
                      return const SizedBox.shrink();
                    }
                    return Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: TvExoPlayerControls(
                        state: _exoState,
                        onPlayPause: _togglePlayPause,
                        onSeek: (pos) {
                          _lastSeekAt = DateTime.now();
                          unawaited(_player.seekTo(pos));
                        },
                        onUserInteraction: _onUserInteraction,
                        showEpisodeControls: _showEpisodeControls,
                        hasPreviousEpisode: _hasPrevEpisode,
                        hasNextEpisode: _hasNextEpisode,
                        onPreviousEpisode: () =>
                            _goToAdjacentEpisode(next: false),
                        onNextEpisode: () => _goToAdjacentEpisode(next: true),
                        episodeListOpen: episodeListOpen,
                        onToggleEpisodeList: () {
                          _episodeListOpenNotifier.value =
                              !_episodeListOpenNotifier.value;
                          _onUserInteraction();
                        },
                      ),
                    );
                  },
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: _episodeListOpenNotifier,
                  builder: (context, open, _) {
                    if (!open) return const SizedBox.shrink();
                    final item = _currentItem;
                    if (item == null) return const SizedBox.shrink();
                    return PlayerEpisodePanel(
                      episode: item,
                      playingEpisodeId: widget.itemId,
                      onSelectEpisode: _onSelectEpisode,
                      onClose: () => _episodeListOpenNotifier.value = false,
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
