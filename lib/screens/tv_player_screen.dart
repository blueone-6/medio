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
import '../core/player/seek_step.dart';
import '../core/player/tv_exo/tv_exo_player.dart';
import '../core/player/tv_exo/tv_exo_video_view.dart';
import '../core/tv/tv_remote_actions.dart' show TvRemoteActions, TvRemoteSelectKeys;
import '../core/player/external_cdn_headers.dart';
import '../core/player/netdisk_transport.dart';
import '../core/player/netdisk_types.dart';
import '../models/emby/emby_media_item.dart';
import '../models/emby/emby_playback_info.dart';
import '../providers/settings_provider.dart';
import '../services/emby_service.dart';
import '../utils/playback_http_headers.dart';
import '../utils/player_route.dart';
import '../widgets/error_view.dart';
import '../widgets/loading_indicator.dart';
import '../widgets/player/buffering_indicator.dart';
import '../widgets/player/player_episode_panel.dart';
import '../widgets/player/player_gesture_hud.dart';
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
    this.hintPlayedPercentage,
  });

  final String itemId;
  final int? hintPositionTicks;

  /// Route resume hint (0–100) from item UserData; used with
  /// [hintPositionTicks] to decide whether a resume position is worth seeking.
  final double? hintPlayedPercentage;

  @override
  ConsumerState<TvPlayerScreen> createState() => _TvPlayerScreenState();
}

class _TvPlayerScreenState extends ConsumerState<TvPlayerScreen>
    with BufferingFeedbackMixin<TvPlayerScreen> {
  static const _chromeHideDelay = Duration(seconds: 4);

  late final TvExoPlayer _player;
  final FocusNode _playerFocusNode = FocusNode(debugLabel: 'tv_player');
  EmbyService? _emby;
  EmbyPlaybackInfo? _info;
  EmbyMediaItem? _currentItem;

  /// Localhost netdisk transport URL currently handed to ExoPlayer, when the
  /// stream is routed through [NetdiskTransport].
  String? _activeProxyUrl;

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

  // D-pad hold-to-seek: the remote repeats slowly, so a timer drives the
  // acceleration curve while the key is down. The seek commits on key-up,
  // matching the desktop/keyboard behaviour instead of hammering ExoPlayer
  // with a seek per repeat event.
  static const _arrowHoldTick = Duration(milliseconds: 200);
  Timer? _arrowHoldTimer;
  DateTime? _arrowHoldStart;
  Duration? _arrowHoldBasePos;
  int _arrowAccumulatedSeconds = 0;
  int _arrowHoldDirection = 0;

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
      syncBufferingFeedback(
        waiting: s.isBuffering && !_loading && _error == null,
      );
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
    _discardArrowHold();
    disposeBufferingFeedback();
    _unregisterActiveProxy();
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
    _settleTimeoutExtensions = 0;
  }

  int _settleTimeoutExtensions = 0;

  /// One re-bootstrap attempt per screen instance — `_resetPlaybackSettle`
  /// must not clear this, otherwise a persistently dead stream loops forever.
  bool _settleRebootstrapped = false;

  void _installPlaybackSettleWatcher(PerfSpan span) {
    _bootstrapSpan?.end(extraContext: {'settle_via': 'replaced'});
    _bootstrapSpan = span;
    _settleTimeoutTimer?.cancel();
    _settleTimeoutTimer = Timer(const Duration(seconds: 15), () {
      _onSettleTimeout();
    });
    _trySettlePlayback('install');
  }

  /// 15 s passed without a settled position. A cold strm (lazy MediaSource
  /// resolution + CDN first-byte) can legitimately take that long while
  /// ExoPlayer is still buffering — keep waiting then. But when the player is
  /// neither playing nor buffering (stream dead / rejected), silently dropping
  /// the loading mask leaves the user on a black screen with controls; retry
  /// the bootstrap once instead, and surface an error if it repeats.
  void _onSettleTimeout() {
    if (_playbackSettled || !mounted) return;
    if (_exoState.isBuffering || _exoState.isPlaying) {
      if (_settleTimeoutExtensions < 3) {
        _settleTimeoutExtensions++;
        _settleTimeoutTimer = Timer(const Duration(seconds: 10), _onSettleTimeout);
        return;
      }
    }
    if (!_settleRebootstrapped && !_exoState.isPlaying &&
        !_exoState.isBuffering) {
      _settleRebootstrapped = true;
      AppLog.instance.w(
        'TvPlayer',
        'settle timeout: player idle (not playing/buffering) - re-bootstrapping',
      );
      unawaited(_retryPlayback());
      return;
    }
    if (_settleTimeoutExtensions >= 3 && !_exoState.isPlaying) {
      _onPlaybackSettled('timeout-error');
      setState(() => _error = '播放长时间无响应，请重试');
      return;
    }
    _onPlaybackSettled('timeout');
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

  /// Registers a netdisk/strm upstream with [NetdiskTransport] and returns the
  /// localhost URL, or null when the stream should open directly. The transport
  /// owns per-CDN headers, bounded ranges, disk caching, and transparent
  /// re-resolution of expired signed URLs.
  Future<String?> _transportUrlFor(EmbyPlaybackInfo pb) async {
    final emby = _emby;
    final strm = pb.strmViaEmbyStream;
    final external = isExternalCdnPlaybackUrl(pb.streamUrl);
    if (emby == null || (!strm && !external)) return null;
    try {
      var upstream = pb.streamUrl;
      Map<String, String> headers;
      Future<ResolvedStreamTarget> Function()? refresh;
      if (strm) {
        final resolved = await emby.resolveExternalCdnUrl(pb.streamUrl);
        if (isExternalCdnPlaybackUrl(resolved)) {
          upstream = resolved;
          headers = externalCdnPlaybackHttpHeadersForUrl(resolved);
        } else {
          headers = externalCdnPlaybackHttpHeaders();
        }
        refresh = () => emby.reResolveCdnTarget(pb.streamUrl);
      } else {
        headers = externalCdnPlaybackHttpHeadersForUrl(pb.streamUrl);
      }
      _unregisterActiveProxy();
      final local = await NetdiskTransport.instance.register(
        upstreamUrl: upstream,
        headers: headers,
        cacheKey: '${widget.itemId}/${pb.mediaSourceId}',
        // Pre-resolved CDN URLs expire; the Emby stream URL 307s to a fresh one
        // per request, which is the fast recovery path for a mid-session expiry.
        redirectUrl: strm ? pb.streamUrl : null,
        refresh: refresh,
      );
      _activeProxyUrl = local;
      AppLog.instance.i(
        'TvPlayer',
        'netdisk transport route ${AppLog.redactUrl(local)}',
      );
      return local;
    } catch (e) {
      AppLog.instance.w('TvPlayer', 'transport registration failed: $e');
      return null;
    }
  }

  void _unregisterActiveProxy() {
    final url = _activeProxyUrl;
    if (url == null) return;
    NetdiskTransport.instance.unregister(url);
    _activeProxyUrl = null;
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

      // Cold strm MediaSources resolve lazily server-side: the first
      // PlaybackInfo may carry no RunTimeTicks while the item metadata does.
      final effectiveRunTimeTicks = pb.runTimeTicks ?? item.runTimeTicks;
      final resumeAt = resumePlaybackPosition(
        playbackPositionTicks:
            startTimeTicks > 0 ? startTimeTicks : widget.hintPositionTicks,
        runTimeTicks: effectiveRunTimeTicks,
        playedPercentage: widget.hintPlayedPercentage,
      );

      var openUrl = pb.streamUrl;
      if (!mounted) return;

      final proxyUrl = await _transportUrlFor(pb);
      if (!mounted) return;
      if (proxyUrl != null) openUrl = proxyUrl;

      final headers = proxyUrl != null
          ? null
          : playbackHttpHeaders(
                openUrl,
                embyServerBase: settings.embyServerUrl,
                embyToken: settings.embyAccessToken,
              ) ??
              (isExternalCdnPlaybackUrl(openUrl)
                  ? externalCdnPlaybackHttpHeadersForUrl(openUrl)
                  : (pb.strmViaEmbyStream
                      ? externalCdnPlaybackHttpHeaders()
                      : null));

      // go-emby2openlist resolves MediaSource lazily for strm items: the first
      // PlaybackInfo may return empty MediaStreams (subs=0). Re-fetch to pick
      // up subtitles before ExoPlayer opens (ExoPlayer cannot add external
      // subtitle tracks after setSource).
      var subtitle = pb.preferredExoTextSubtitle;
      if (subtitle == null &&
          pb.strmViaEmbyStream &&
          pb.subtitles.isEmpty) {
        // The lazy resolution needs a moment even for the first re-fetch
        // (the first PlaybackInfo above triggered it server-side) — always
        // wait before retrying, not only from the second attempt on.
        for (var attempt = 0; attempt < 3 && subtitle == null; attempt++) {
          await Future<void>.delayed(const Duration(seconds: 2));
          if (!mounted) return;
          try {
            final freshPb = await emby.getPlaybackInfo(widget.itemId);
            if (!mounted) return;
            if (freshPb.subtitles.isNotEmpty) {
              subtitle = freshPb.preferredExoTextSubtitle;
              AppLog.instance.i(
                'TvPlayer',
                'refetched subtitles: ${freshPb.subtitles.length} tracks '
                    '(attempt ${attempt + 1}) itemId=${widget.itemId}',
              );
            }
          } catch (e) {
            AppLog.instance.w(
              'TvPlayer',
              'refetch subtitles failed (attempt ${attempt + 1}): $e',
            );
          }
        }
      }

      final isHdr = item.isHdr;
      final videoRange = item.videoRange;
      AppLog.instance.i(
        'TvPlayer',
        'open itemId=${widget.itemId} url=${AppLog.redactUrl(openUrl)} '
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
      var openUrl = pb.streamUrl;
      if (!mounted) return;

      final settings = ref.read(settingsServiceProvider);
      final proxyUrl = await _transportUrlFor(pb);
      if (!mounted) return;
      if (proxyUrl != null) openUrl = proxyUrl;

      final headers = proxyUrl != null
          ? null
          : playbackHttpHeaders(
                openUrl,
                embyServerBase: settings.embyServerUrl,
                embyToken: settings.embyAccessToken,
              ) ??
              (isExternalCdnPlaybackUrl(openUrl)
                  ? externalCdnPlaybackHttpHeadersForUrl(openUrl)
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

  /// PlaybackInfo RunTimeTicks with item-metadata fallback: cold strm
  /// MediaSources resolve lazily and may omit RunTimeTicks on first fetch.
  int? get _effectiveRunTimeTicks =>
      _info?.runTimeTicks ?? _currentItem?.runTimeTicks;

  void _maybeRecordPlayHistory(int positionTicks, int? runTimeTicks) {
    final runtime = runTimeTicks ?? _effectiveRunTimeTicks;
    if (runtime == null || runtime <= 0) return;
    if (positionTicks < runtime * 0.05) return;
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
    _discardArrowHold();
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

  Duration _clampToDuration(Duration target) {
    final dur = _exoState.duration;
    var clamped = target < Duration.zero ? Duration.zero : target;
    if (dur > Duration.zero && clamped > dur) clamped = dur;
    return clamped;
  }

  void _seekBy(int seconds) {
    _lastSeekAt = DateTime.now();
    unawaited(_player.seekTo(_clampToDuration(
      _exoState.position + Duration(seconds: seconds),
    )));
    _onUserInteraction();
  }

  /// Starts the accelerated preview for a held D-pad arrow. The first step is
  /// applied immediately; the timer ramps subsequent steps with hold time and
  /// the seek is committed on key-up.
  void _beginArrowHold(int direction, int baseStep) {
    if (_arrowHoldTimer != null) return;
    _arrowHoldDirection = direction;
    _arrowHoldBasePos = _exoState.position;
    _arrowAccumulatedSeconds = direction * baseStep;
    _arrowHoldStart = DateTime.now();
    _onUserInteraction();
    _arrowHoldTimer = Timer.periodic(_arrowHoldTick, (_) {
      if (!mounted || _arrowHoldStart == null) return;
      final held = DateTime.now().difference(_arrowHoldStart!);
      // Remote safety: if the key-up never reaches us, stop instead of
      // accumulating an unbounded offset forever.
      if (held >= const Duration(seconds: 20)) {
        _endArrowHold();
        return;
      }
      setState(() {
        _arrowAccumulatedSeconds +=
            _arrowHoldDirection * gestureSeekStepForHold(held);
      });
    });
    setState(() {});
  }

  Duration? get _arrowSeekTarget {
    final base = _arrowHoldBasePos;
    if (base == null) return null;
    return _clampToDuration(
      base + Duration(seconds: _arrowAccumulatedSeconds),
    );
  }

  /// Commits the accumulated offset. Safe to call twice: the desktop/global
  /// key paths both see the same key-up event.
  void _endArrowHold() {
    if (_arrowHoldTimer == null) return;
    final base = _arrowHoldBasePos;
    final offset = _arrowAccumulatedSeconds;
    _discardArrowHold();
    if (base == null || offset == 0) {
      if (mounted) setState(() {});
      return;
    }
    _lastSeekAt = DateTime.now();
    if (mounted) setState(() {});
    unawaited(
      _player.seekTo(_clampToDuration(base + Duration(seconds: offset))),
    );
  }

  void _discardArrowHold() {
    _arrowHoldTimer?.cancel();
    _arrowHoldTimer = null;
    _arrowHoldStart = null;
    _arrowHoldBasePos = null;
    _arrowAccumulatedSeconds = 0;
    _arrowHoldDirection = 0;
  }

  KeyEventResult _handlePlayerKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) {
      if ((event.logicalKey == LogicalKeyboardKey.arrowLeft ||
              event.logicalKey == LogicalKeyboardKey.arrowRight) &&
          _arrowHoldTimer != null) {
        _endArrowHold();
        return KeyEventResult.handled;
      }
      // Not our hold (e.g. scrolling the episode panel): let it through.
      return KeyEventResult.ignored;
    }
    // The one-shot key below starts the hold; the timer (not the repeat rate)
    // drives the acceleration, so repeats are consumed without extra seeks.
    if (event is KeyRepeatEvent) {
      if ((event.logicalKey == LogicalKeyboardKey.arrowLeft ||
              event.logicalKey == LogicalKeyboardKey.arrowRight) &&
          _arrowHoldTimer != null) {
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      _beginArrowHold(-1, 10);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _beginArrowHold(1, 10);
      return KeyEventResult.handled;
    }
    // Any other key means the hold is over; commit before acting on it.
    _endArrowHold();
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
              // Buffering mid-playback: keep the frame visible and add a pill, so
              // a slow network reads as "loading" rather than a frozen picture.
              // Gated here as well as in syncBufferingFeedback: a codec fallback
              // flips _loading on between state events, and a stale stage must
              // not paint over the reconnect overlay.
              if (bufferingStage != BufferingStage.hidden &&
                  !_loading &&
                  _error == null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: BufferingIndicator(
                      stage: bufferingStage,
                      bufferedPosition: _exoState.bufferedPosition,
                      duration: _exoState.duration,
                    ),
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
                // Held D-pad preview: the video only seeks on release, so show
                // where the jump will land.
                if (_arrowHoldTimer != null &&
                    !_loading &&
                    _exoState.duration > Duration.zero)
                  PlayerGestureHud(
                    visible: true,
                    kind: PlayerGestureHudKind.seek,
                    seekSeconds: _arrowAccumulatedSeconds,
                    seekTarget: _arrowSeekTarget,
                    seekDuration: _exoState.duration,
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
