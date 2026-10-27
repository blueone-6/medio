import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:screen_brightness/screen_brightness.dart';

import '../core/logging/app_log.dart';
import '../core/logging/perf.dart';
import '../core/player/episode_navigation.dart';
import '../core/player/exo/exo_network_error.dart';
import '../core/player/exo/exo_player_bridge.dart';
import '../core/player/exo/exo_track_selection.dart';
import '../core/player/exo/subtitle_text_parse.dart';
import '../core/player/exo/video_fit_mode.dart';
import '../core/player/external_cdn_headers.dart';
import '../core/player/hold_speed.dart';
import '../core/player/netdisk_transport.dart';
import '../core/player/netdisk_types.dart';
import '../core/player/playback_resume.dart';
import '../core/player/player_av_sync.dart';
import '../core/player/player_codec_error.dart';
import '../core/player/player_home_refresh.dart';
import '../core/player/player_volume_memory.dart';
import '../core/player/reopen_backoff.dart';
import '../core/player/seek_step.dart';
import '../core/player/subtitle_offset.dart';
import '../core/player/tv_exo/tv_exo_video_view.dart';
import '../core/theme/app_colors.dart';
import '../core/tv/tv_remote_actions.dart' show TvRemoteActions;
import '../models/emby/emby_media_item.dart';
import '../models/emby/emby_playback_info.dart';
import '../models/emby/emby_subtitle_option.dart';
import '../providers/settings_provider.dart';
import '../services/emby_service.dart';
import '../utils/playback_http_headers.dart';
import '../utils/player_route.dart';
import '../widgets/error_view.dart';
import '../widgets/loading_indicator.dart';
import '../widgets/player/buffering_indicator.dart';
import '../widgets/player/exo_player_controls.dart';
import '../widgets/player/exo_subtitle_overlay.dart';
import '../widgets/player/player_episode_panel.dart';
import '../widgets/player/player_gesture_mobile.dart';
import '../widgets/player/player_top_info.dart';

/// Android phone playback screen — Media3 ExoPlayer (SurfaceView).
///
/// Desktop keeps [PlayerScreen] (media_kit / libmpv); TV keeps
/// [TvPlayerScreen]. Session logic (resume, progress reporting, next-episode,
/// codec fallback, netdisk transport) mirrors those screens.
class ExoPlayerScreen extends ConsumerStatefulWidget {
  const ExoPlayerScreen({
    super.key,
    required this.itemId,
    this.hintPositionTicks,
    this.hintPlayedPercentage,
  });

  final String itemId;
  final int? hintPositionTicks;
  final double? hintPlayedPercentage;

  @override
  ConsumerState<ExoPlayerScreen> createState() => _ExoPlayerScreenState();
}

class _ExoPlayerScreenState extends ConsumerState<ExoPlayerScreen>
    with WidgetsBindingObserver, BufferingFeedbackMixin<ExoPlayerScreen> {
  static const _chromeHideDelay = Duration(seconds: 4);

  /// Keeps landscape across episode switches (absorbed from PlayerScreen).
  static var _preserveAndroidLandscapeOnNextOpen = false;

  late final ExoPlayerBridge _player;
  EmbyService? _emby;
  EmbyPlaybackInfo? _info;
  EmbyMediaItem? _currentItem;

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
  bool _bootstrapped = false;

  Future<void>? _progressReportInFlight;
  int? _lastReportedPositionTicks;

  Timer? _progressTimer;
  Timer? _chromeIdleTimer;
  Timer? _settleTimeoutTimer;
  Timer? _nextEpCountdownTimer;
  Timer? _volumePersistTimer;
  Timer? _arrowSeekDelayTimer;
  StreamSubscription<String>? _errorSub;
  StreamSubscription<void>? _completedSub;
  StreamSubscription<ExoPlayerBridgeState>? _readySub;
  StreamSubscription<ExoPlayerBridgeState>? _stateSub;

  ExoPlayerBridgeState _exoState = const ExoPlayerBridgeState();
  PerfSpan? _bootstrapSpan;
  Duration _resumeTarget = Duration.zero;
  bool _playbackSettled = false;
  int _settleTimeoutExtensions = 0;
  bool _settleRebootstrapped = false;
  DateTime _lastSeekAt = DateTime.now();
  ProviderContainer? _riverpodContainer;

  // Network reopen recovery.
  int _networkReopenAttempts = 0;
  bool _networkRecoveryInProgress = false;
  int _rebootstrapAttempts = 0;

  /// Last URL + headers handed to setSource (same-source reopen target).
  String? _activeSourceUrl;
  Map<String, String>? _lastSourceHeaders;

  Future<void> _openSource(
    String url,
    Map<String, String>? headers,
    Duration resumeAt, {
    bool reinstallSettleWatcher = false,
  }) async {
    _activeSourceUrl = url;
    _lastSourceHeaders = headers;
    _awaitingSourceReady = true;
    _selectionApplyAttempts = 0;
    await _player.setSource(
      url: url,
      headers: headers,
      startPosition: resumeAt,
      isHdrContent: _currentItem?.isHdr ?? false,
      videoRange: _currentItem?.videoRange,
    );
    if (_speed != 1.0) {
      await _player.setPlaybackSpeed(_speed);
    }
    await _player.setVolume(_volumeAdjustAnchor);
    await _player.setSubtitleDelayMs(_subtitleOffsetMs);
    if (reinstallSettleWatcher) {
      _resetPlaybackSettle(resumeAt);
    }
  }

  // Tracks / subtitles / audio.
  ExoTrackCatalog _tracks = const ExoTrackCatalog();
  ExoSubtitleTarget? _subtitleTarget;
  List<ParsedSubtitleCue> _externalCues = const [];
  int _subtitleOffsetMs = 0;

  /// 音画同步补偿（音频相对画面的延迟），毫秒；正 = 声音延后。
  ///
  /// **按片源记忆**：只有个别片源自带音频延迟（现场实测一部 EAC3 软解 remux 需要
  /// 约 1 s），全局值会把正常片源一起带偏，所以未记录过的片源一律 0，并且每次
  /// [_openSource] 都会把本片源的值重新下发给 native（bridge 字段会跨 player
  /// 重建保留，不主动下发就会漏到下一个片源）。
  int _audioDelayMs = 0;
  ExoPlayerTrack? _currentAudio;
  double _speed = 1.0;
  bool _muted = false;

  /// Temporary 2x while the user holds the right half of the screen.
  bool _holdSpeedActive = false;
  double? _speedBeforeHold;
  bool _holdResumedFromPause = false;

  /// Picture scaling mode chosen by the user (persisted). The mode actually
  /// handed to the player is [effectiveVideoFitMode] — portrait always renders
  /// fit, because cropping a landscape frame into a tall viewport would discard
  /// most of the picture.
  VideoFitMode _videoFitMode = VideoFitMode.zoom;
  VideoFitMode? _appliedVideoFitMode;

  /// True between setSource and the next STATE_READY — distinguishes a fresh
  /// preparation (track ids invalid, selections must be re-applied) from a
  /// buffering→ready transition (selections still valid).
  bool _awaitingSourceReady = false;

  /// Guards against overlapping selection re-applies (ready + state fallback).
  bool _selectionApplyInFlight = false;

  /// Bounded retries for the state-driven selection fallback.
  int _selectionApplyAttempts = 0;

  // Volume memory.
  double _volumeAdjustAnchor = 100;
  static const _volumePersistDelay = Duration(seconds: 2);

  // Orientation (phone).
  bool _androidLandscape = false;
  bool _orientationChangeInProgress = false;

  // Keyboard seek preview (arrow keys).
  bool _arrowSeekActive = false;
  bool _arrowIsLongPress = false;
  DateTime? _arrowHoldStart;
  int _arrowAccumulatedSeconds = 0;
  Duration? _arrowSeekBasePos;
  final ValueNotifier<int> _gestureSeekPreview = ValueNotifier<int>(0);

  // Next-episode countdown.
  EmbyMediaItem? _nextEpisode;
  bool _showNextEp = false;
  int _nextEpCountdown = 5;

  final ValueNotifier<bool> _episodeListOpenNotifier = ValueNotifier<bool>(false);
  List<EmbyMediaItem>? _episodes;
  bool _hasPrevEpisode = false;
  bool _hasNextEpisode = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _riverpodContainer ??= ProviderScope.containerOf(context);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subtitleOffsetMs = ref.read(settingsServiceProvider).subtitleOffsetMs;
    _audioDelayMs =
        ref.read(settingsServiceProvider).audioDelayMsFor(widget.itemId);
    _videoFitMode = ref.read(settingsServiceProvider).videoFitMode;
    _player = ExoPlayerBridge();
    _stateSub = _player.stateStream.listen((s) {
      if (!mounted) return;
      setState(() => _exoState = s);
      syncBufferingFeedback(
        waiting: s.isBuffering && !_loading && _error == null,
      );
      _trySettlePlayback('position');
      _applySelectionsIfPending();
    });
    _readySub = _player.readyStream.listen((s) {
      _trySettlePlayback('ready');
      unawaited(_onSourceReady());
    });
    _errorSub = _player.errorStream.listen((msg) {
      unawaited(_handlePlaybackError(msg));
    });
    _completedSub = _player.completedStream.listen((_) {
      unawaited(_onPlaybackCompleted());
    });
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky));
    if (_preserveAndroidLandscapeOnNextOpen) {
      _preserveAndroidLandscapeOnNextOpen = false;
      _androidLandscape = true;
      unawaited(SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]));
    } else {
      unawaited(SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]));
    }
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _chromeIdleTimer?.cancel();
    _settleTimeoutTimer?.cancel();
    _nextEpCountdownTimer?.cancel();
    _volumePersistTimer?.cancel();
    _arrowSeekDelayTimer?.cancel();
    disposeBufferingFeedback();
    _unregisterActiveProxy();
    _progressTimer?.cancel();
    _errorSub?.cancel();
    _completedSub?.cancel();
    _readySub?.cancel();
    _stateSub?.cancel();
    _bootstrapSpan?.end(extraContext: {'settle_via': 'dispose'});
    _bootstrapSpan = null;
    _episodeListOpenNotifier.dispose();
    _gestureSeekPreview.dispose();
    if (!_episodeSwitching && !_leavingPlayer) {
      _cancelProgressReporting();
      unawaited(_reportStoppedIfNeeded());
    }
    WidgetsBinding.instance.removeObserver(this);
    final container = _riverpodContainer;
    if (container != null) {
      schedulePlayerHomeDataRefresh(container);
    }
    unawaited(_restoreChromeOnExit());
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> _restoreChromeOnExit() async {
    if (_episodeSwitching) return;
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      // The player is the only landscape surface on the phone; restoring
      // "all orientations" left the app stuck in landscape when the device's
      // auto-rotate was off, so lock back to portrait explicitly.
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
      await ScreenBrightness().resetApplicationScreenBrightness();
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused) {
      if (_exoState.isPlaying) {
        unawaited(_pauseForBackground());
      }
      return;
    }
    if (state == AppLifecycleState.resumed) {
      // Nothing to restore — ExoPlayer kept its buffers while backgrounded.
    }
  }

  Future<void> _pauseForBackground() async {
    try {
      await _player.pause();
    } catch (_) {}
    try {
      await _reportProgress(flushing: true);
    } catch (_) {}
  }

  // ── Bootstrap ──

  void _resetPlaybackSettle(Duration resumeAt) {
    _settleTimeoutTimer?.cancel();
    _playbackSettled = false;
    _resumeTarget = resumeAt;
    _settleTimeoutExtensions = 0;
  }

  void _installPlaybackSettleWatcher(PerfSpan span) {
    _bootstrapSpan?.end(extraContext: {'settle_via': 'replaced'});
    _bootstrapSpan = span;
    _settleTimeoutTimer?.cancel();
    _settleTimeoutTimer = Timer(const Duration(seconds: 15), _onSettleTimeout);
    _trySettlePlayback('install');
  }

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
        'ExoPlayer',
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
      _scheduleChromeHide();
    });
  }

  /// Registers a netdisk/strm upstream with [NetdiskTransport] and returns the
  /// localhost URL, or null when the stream should open directly.
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
        'ExoPlayer',
        'netdisk transport route ${AppLog.redactUrl(local)}',
      );
      return local;
    } catch (e) {
      AppLog.instance.w('ExoPlayer', 'transport registration failed: $e');
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
    final span = PerfTracer.start('exo_player_bootstrap');
    try {
      _lastSeekAt = DateTime.now();
      final emby = ref.read(embyServiceProvider);
      _emby = emby;
      final settings = ref.read(settingsServiceProvider);
      final startTimeTicks = widget.hintPositionTicks ?? 0;

      final results = await Future.wait<Object>([
        emby.getPlaybackInfo(widget.itemId, startTimeTicks: startTimeTicks),
        emby.getItemForPlayer(widget.itemId),
      ]);
      if (!mounted) return;

      final pb = results[0] as EmbyPlaybackInfo;
      final item = results[1] as EmbyMediaItem;
      _currentItem = item;
      _info = pb;

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

      final isHdr = item.isHdr;
      final videoRange = item.videoRange;
      AppLog.instance.i(
        'ExoPlayer',
        'open itemId=${widget.itemId} url=${AppLog.redactUrl(openUrl)} '
            'resume=${resumeAt?.inSeconds}s subs=${pb.subtitles.length} '
            'hdr=$isHdr range=$videoRange',
      );

      final resumeTarget = resumeAt ?? Duration.zero;
      _resetPlaybackSettle(resumeTarget);
      _awaitingSourceReady = true;
      _selectionApplyAttempts = 0;

      await _player.setSource(
        url: openUrl,
        headers: headers,
        startPosition: resumeTarget,
        isHdrContent: isHdr,
        videoRange: videoRange,
      );
      // Native (muxed) subtitles must honour 字幕字号 too, not just the overlay.
      await _player.setSubtitleFontScale(settings.subtitleFontSize / 42);
      _activeSourceUrl = openUrl;
      _lastSourceHeaders = headers;

      if (!mounted) return;

      _installPlaybackSettleWatcher(span);

      // Restore remembered volume + default speed.
      final restoredVolume = restorePlayerVolume(settings.playerVolume);
      await _player.setVolume(restoredVolume);
      _volumeAdjustAnchor = restoredVolume;
      _speed = settings.defaultPlaybackSpeed;
      if (_speed != 1.0) {
        await _player.setPlaybackSpeed(_speed);
      }
      if (_subtitleOffsetMs > 0) {
        await _player.setSubtitleDelayMs(_subtitleOffsetMs);
      }
      // Always push the current value (0 for a fresh screen): the native bridge
      // keeps it across player rebuilds, so a previous video's offset must not
      // leak into this one.
      await _player.setAudioDelayMs(_audioDelayMs);
      _appliedVideoFitMode = null;
      _applyVideoFitMode();

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
      _bootstrapped = true;
    } catch (e, st) {
      span.endError(e, st);
      _bootstrapSpan = null;
      AppLog.instance.e(
        'ExoPlayer',
        'bootstrap failed itemId=${widget.itemId}',
        error: e,
        stackTrace: st,
      );
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  /// Re-applies the subtitle/audio selection after a fresh preparation.
  ///
  /// Runs on the native `ready` event and, as a fallback, from the playback
  /// state stream: the event channel is shared and `ready` carries no source
  /// id, so a stale/early one (e.g. emitted while the previous screen was still
  /// tearing down) could consume the one-shot flag and leave the session with
  /// no subtitle or audio selection until a manual pick. The flag is only
  /// cleared once the catalog was read and the selections were applied.
  Future<void> _onSourceReady() async {
    if (!_awaitingSourceReady || _info == null) return;
    if (_selectionApplyInFlight) return;
    _selectionApplyInFlight = true;
    try {
      final catalog = ExoTrackCatalog.fromMap(await _player.getTracksRaw());
      if (!mounted) return;
      setState(() => _tracks = catalog);
      await _reapplySelectionsAfterPrepare();
      // Cleared only after the selections were actually applied: a failed
      // apply keeps the flag set so the state-stream fallback retries it,
      // which is the difference between "no subtitle this session" and a
      // recoverable race.
      _awaitingSourceReady = false;
    } catch (e) {
      AppLog.instance.w('ExoPlayer', 'apply track selections failed: $e');
    } finally {
      _selectionApplyInFlight = false;
    }
  }

  /// Re-reads the native track catalog for the track sheets.
  ///
  /// The catalog used for playback is read early in preparation, before media3
  /// has marked a track as selected, so the sheets refresh it first: that is
  /// what lets 音轨 show the player's own default as the selected row.
  Future<void> _refreshTrackCatalog() async {
    try {
      final catalog = ExoTrackCatalog.fromMap(await _player.getTracksRaw());
      if (!mounted) return;
      setState(() => _tracks = catalog);
      debugPrint(
        'MEDIO-TRACKS audio=${catalog.audio.length} '
        'selected=${catalog.audio.where((t) => t.isSelected).map((t) => t.id).toList()} '
        'unsupported=${catalog.unsupportedAudio.length}',
      );
    } catch (e) {
      AppLog.instance.w('ExoPlayer', 'refresh track catalog failed: $e');
    }
  }

  /// Fallback driver for [_onSourceReady], called from the playback state
  /// stream: playback state is authoritative, so once the source is actually
  /// running the selections are applied even if the `ready` event was missed or
  /// the catalog read failed.
  void _applySelectionsIfPending() {
    if (!_awaitingSourceReady || _info == null) return;
    if (_selectionApplyInFlight) return;
    if (_exoState.duration <= Duration.zero) return;
    if (_selectionApplyAttempts >= 5) {
      _awaitingSourceReady = false;
      AppLog.instance.w(
        'ExoPlayer',
        'gave up applying track selections after $_selectionApplyAttempts attempts',
      );
      return;
    }
    _selectionApplyAttempts++;
    unawaited(_onSourceReady());
  }

  Future<void> _reapplySelectionsAfterPrepare() async {
    final info = _info;
    if (info == null) return;

    final prefs = ref.read(playbackPreferencesServiceProvider);
    final saved = prefs.getSubtitleSelection(widget.itemId);
    final target = resolveInitialSubtitleSelection(
      saved: saved ?? 'auto',
      embySubtitles: info.subtitles,
      nativeTextTracks: _tracks.text,
    );
    await _applySubtitleTarget(target, persist: false);

    // Re-apply the remembered audio track (ids change across re-prepares).
    final audio = _currentAudio;
    if (audio != null) {
      ExoPlayerTrack? match;
      for (final t in _tracks.audio) {
        if (t.language != null &&
            t.language == audio.language &&
            t.label == audio.label) {
          match = t;
          break;
        }
      }
      if (match != null) {
        await _player.selectAudioTrack(match.id);
        if (mounted) setState(() => _currentAudio = match);
      }
    }
  }

  // ── Subtitles ──

  Future<void> _applySubtitleTarget(
    ExoSubtitleTarget target, {
    bool persist = true,
  }) async {
    _subtitleTarget = target;
    if (mounted) setState(() {});

    switch (target) {
      case ExoSubtitleOff():
        _externalCues = const [];
        await _player.selectTextTrack(null);
      case ExoSubtitleExternal(:final option):
        await _player.selectTextTrack(null);
        await _loadExternalCues(option);
      case ExoSubtitleMuxed(:final track):
        _externalCues = const [];
        await _player.selectTextTrack(track.id);
    }

    if (persist) {
      final prefs = ref.read(playbackPreferencesServiceProvider);
      final value = switch (target) {
        ExoSubtitleOff() => 'no',
        ExoSubtitleExternal(:final option) =>
          'emby:${option.index}',
        ExoSubtitleMuxed(:final track) =>
          'track:${muxedTrackPreferenceKey(track)}',
      };
      await prefs.setSubtitleSelection(widget.itemId, value);
    }
  }

  Future<void> _loadExternalCues(EmbySubtitleOption option) async {
    final emby = _emby;
    if (emby == null) return;
    var cues = await _fetchExternalCues(emby, option);
    if (cues.isEmpty) {
      // A transient fetch/parse failure used to leave the session without any
      // subtitle for good (the empty cue list also hides the overlay), so retry
      // once before accepting the failure.
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      if (!mounted || !_isCurrentExternalTarget(option)) return;
      cues = await _fetchExternalCues(emby, option);
    }
    if (!mounted || !_isCurrentExternalTarget(option)) return;
    setState(() => _externalCues = cues);
  }

  /// True while [option] is still the selected external subtitle (a retry must
  /// not clobber a newer choice).
  bool _isCurrentExternalTarget(EmbySubtitleOption option) {
    final target = _subtitleTarget;
    return target is ExoSubtitleExternal && target.option.index == option.index;
  }

  Future<List<ParsedSubtitleCue>> _fetchExternalCues(
    EmbyService emby,
    EmbySubtitleOption option,
  ) async {
    try {
      final text = await emby.fetchSubtitleText(option.exoStreamUrl);
      final cues = text == null
          ? const <ParsedSubtitleCue>[]
          : parseSubtitleText(text, format: option.exoStreamFormat);
      if (cues.isEmpty) {
        AppLog.instance.w(
          'ExoPlayer',
          'external subtitle empty: ${option.label} bytes=${text?.length}',
        );
      }
      return cues;
    } catch (e) {
      AppLog.instance.w('ExoPlayer', 'fetch subtitle failed: $e');
      return const <ParsedSubtitleCue>[];
    }
  }

  void _onSubtitleMenuPicked(ExoSubtitleTarget target) {
    unawaited(_applySubtitleTarget(target));
  }

  void _adjustSubtitleDelay(int deltaMs) {
    final settings = ref.read(settingsServiceProvider);
    final next = clampSubtitleOffsetMs(settings.subtitleOffsetMs + deltaMs);
    setState(() => _subtitleOffsetMs = next);
    unawaited(settings.setSubtitleOffsetMs(next));
    // Muxed (native) subs only support ≈0 in ExoPlayer; the bridge clamps.
    unawaited(_player.setSubtitleDelayMs(next));
  }

  void _resetSubtitleDelay() {
    final settings = ref.read(settingsServiceProvider);
    setState(() => _subtitleOffsetMs = 0);
    unawaited(settings.setSubtitleOffsetMs(0));
    unawaited(_player.setSubtitleDelayMs(0));
  }

  /// 音画同步：正 = 声音延后。**按片源记忆**（按 itemId 存，未记录的片源恒为
  /// 0），换片/换集自动用各自的值，不会影响正常片源。
  void _adjustAudioDelay(int deltaMs) {
    final settings = ref.read(settingsServiceProvider);
    final next = clampAudioDelayMs(_audioDelayMs + deltaMs);
    setState(() => _audioDelayMs = next);
    unawaited(settings.setAudioDelayMsFor(widget.itemId, next));
    unawaited(_player.setAudioDelayMs(next));
  }

  void _resetAudioDelay() {
    final settings = ref.read(settingsServiceProvider);
    setState(() => _audioDelayMs = 0);
    unawaited(settings.setAudioDelayMsFor(widget.itemId, 0));
    unawaited(_player.setAudioDelayMs(0));
  }

  // ── Audio / speed / volume ──

  void _onAudioPicked(ExoPlayerTrack? track) {
    setState(() => _currentAudio = track);
    unawaited(_player.selectAudioTrack(track?.id));
  }

  void _onRatePicked(double rate) {
    setState(() => _speed = rate);
    unawaited(_player.setPlaybackSpeed(rate));
  }

  /// Hold-to-fast-forward gesture: temporarily play at [holdFastForwardRate],
  /// then restore the user's chosen speed on release. A paused video resumes
  /// for the duration of the hold and pauses again afterwards.
  void _onHoldSpeedChanged(bool active) {
    if (active == _holdSpeedActive) return;
    _holdSpeedActive = active;
    if (active) {
      _speedBeforeHold = _speed;
      // A rebuffer is not a pause: resuming here would make release pause a
      // stream that was about to continue on its own.
      if (!_exoState.isPlaying && !_exoState.isBuffering) {
        _holdResumedFromPause = true;
        unawaited(_player.play());
      }
      unawaited(_player.setPlaybackSpeed(holdFastForwardRate));
      return;
    }
    unawaited(_player.setPlaybackSpeed(_speedBeforeHold ?? _speed));
    _speedBeforeHold = null;
    if (_holdResumedFromPause) {
      _holdResumedFromPause = false;
      unawaited(_player.pause());
    }
  }

  /// Applies the user's picture mode, honouring the portrait fallback.
  /// Idempotent — safe to call from the orientation paths.
  void _applyVideoFitMode() {
    final effective = effectiveVideoFitMode(
      _videoFitMode,
      landscape: _androidLandscape,
    );
    if (effective == _appliedVideoFitMode) return;
    _appliedVideoFitMode = effective;
    unawaited(_player.setVideoFitMode(effective));
  }

  void _onVideoFitModePicked(VideoFitMode mode) {
    setState(() => _videoFitMode = mode);
    unawaited(ref.read(settingsServiceProvider).setVideoFitMode(mode));
    _appliedVideoFitMode = null;
    _applyVideoFitMode();
  }

  void _changeVolume(double delta) {
    final next = (_volumeAdjustAnchor + delta).clamp(0.0, 100.0);
    _volumeAdjustAnchor = next;
    _muted = false;
    unawaited(_player.setVolume(next));
    unawaited(_player.setMuted(false));
    if (mounted) setState(() {});
    _persistVolumeDebounced(next);
  }

  void _setVolume(double volume) {
    final next = volume.clamp(0.0, 100.0);
    _volumeAdjustAnchor = next;
    unawaited(_player.setVolume(next));
    if (mounted) setState(() {});
    _persistVolumeDebounced(next);
  }

  void _toggleMute() {
    _muted = !_muted;
    unawaited(_player.setMuted(_muted));
    setState(() {});
  }

  void _persistVolumeDebounced(double volume) {
    _volumePersistTimer?.cancel();
    _volumePersistTimer = Timer(_volumePersistDelay, () {
      final persistable = volumeToPersist(volume);
      if (persistable == null || !mounted) return;
      final settings = ref.read(settingsServiceProvider);
      if (settings.playerVolume == persistable) return;
      unawaited(settings.setPlayerVolume(persistable));
    });
  }

  // ── Errors / recovery ──

  Future<void> _handlePlaybackError(String raw) async {
    if (!mounted || _codecFallbackInProgress || _networkRecoveryInProgress) {
      return;
    }
    if (isRecoverablePlayerCodecError(raw) && !_codecFallbackAttempted) {
      await _handleCodecFallback(raw);
      return;
    }
    if (isExoSignedUrlExpiredError(raw) && _rebootstrapAttempts < 1) {
      _rebootstrapAttempts++;
      AppLog.instance.w('ExoPlayer', 'signed URL expired - re-bootstrapping');
      await _retryPlayback();
      return;
    }
    if (isRecoverableExoNetworkError(raw) && _networkReopenAttempts < 3) {
      await _handleRecoverableNetworkError(raw);
      return;
    }
    if (mounted) {
      setState(() {
        _error = playerCodecErrorFinalMessage(raw);
        _loading = false;
        _reconnecting = false;
      });
    }
  }

  Future<void> _handleRecoverableNetworkError(String raw) async {
    final url = _activeSourceUrl;
    if (url == null || url.isEmpty) {
      await _retryPlayback();
      return;
    }
    _networkRecoveryInProgress = true;
    _networkReopenAttempts++;
    final delay = reopenBackoffDelay(_networkReopenAttempts - 1);
    AppLog.instance.w(
      'ExoPlayer',
      'recoverable network error (attempt=$_networkReopenAttempts/3, '
          'reopen in ${delay.inSeconds}s): $raw',
    );
    setState(() {
      _error = null;
      _loading = true;
      _reconnecting = true;
    });
    await Future<void>.delayed(delay);
    if (!mounted) {
      _networkRecoveryInProgress = false;
      return;
    }
    // Reopen the current source at the live position: same MediaItem, so the
    // CDN URL / transport route stays valid; only the connection is retried.
    try {
      await _openSource(
        url,
        _lastSourceHeaders,
        _exoState.position,
        reinstallSettleWatcher: true,
      );
    } catch (e) {
      AppLog.instance.w('ExoPlayer', 'network reopen failed: $e');
    } finally {
      _networkRecoveryInProgress = false;
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

      _resetPlaybackSettle(resumeAt);
      final fallbackSpan = PerfTracer.start('exo_player_codec_fallback');

      await _openSource(openUrl, headers, resumeAt);

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

  /// Re-opens the current source from scratch.
  ///
  /// [userInitiated] means a deliberate retry (the error screen's 重试) rather
  /// than automatic recovery. Only then is the one-shot signed-URL-re-bootstrap
  /// budget handed back: resetting it on *every* retry made the
  /// `_rebootstrapAttempts < 1` guard dead code, so a stream whose signed URL
  /// can no longer be minted (dead CDN object, server still serving its cached
  /// redirect) retried forever behind 「正在准备播放…」 instead of showing the
  /// error screen.
  Future<void> _retryPlayback({bool userInitiated = false}) async {
    setState(() {
      _error = null;
      _loading = true;
      _codecFallbackAttempted = false;
      _networkReopenAttempts = 0;
      if (userInitiated) _rebootstrapAttempts = 0;
    });
    await _bootstrap();
  }

  // ── Progress reporting ──

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

  // ── Episodes ──

  Future<void> _fetchEpisodes() async {
    final item = _currentItem;
    if (item?.seasonId == null) return;
    final emby = _emby;
    if (emby == null) return;
    try {
      final episodes =
          sortEpisodesByIndex(await emby.getEpisodes(item!.seasonId!));
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
    if (!_bootstrapped || _loading) return;
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
    setState(() {
      _nextEpisode = next;
      _showNextEp = true;
      _nextEpCountdown = 5;
    });
    _startNextEpCountdown();
  }

  void _startNextEpCountdown() {
    _nextEpCountdownTimer?.cancel();
    _nextEpCountdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_nextEpCountdown <= 1) {
        _cancelNextEp();
        _navigateToNextEpisode();
        return;
      }
      setState(() => _nextEpCountdown--);
    });
  }

  void _cancelNextEp() {
    _nextEpCountdownTimer?.cancel();
    if (!mounted) return;
    setState(() => _showNextEp = false);
  }

  void _navigateToNextEpisode() {
    final next = _nextEpisode;
    if (next == null) return;
    _markAndroidLandscapePreserveForEpisodeSwitch();
    _episodeSwitching = true;
    final route = playerRouteForItem(next.id);
    if (mounted) context.replace(route);
  }

  // ── Navigation / chrome ──

  void _leavePlayer() {
    if (_leavingPlayer) return;
    _leavingPlayer = true;
    final exitTicks = _playbackExitPositionTicks();
    unawaited(() async {
      await _reportStoppedIfNeeded(positionTicks: exitTicks);
      await _player.stop();
    }());
    if (mounted && context.canPop()) context.pop();
  }

  void _markAndroidLandscapePreserveForEpisodeSwitch() {
    if (_androidLandscape) {
      _preserveAndroidLandscapeOnNextOpen = true;
    }
  }

  void _onSelectEpisode(String episodeId) {
    _markAndroidLandscapePreserveForEpisodeSwitch();
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

  // ── Orientation ──

  Future<void> _toggleAndroidOrientation() async {
    if (_orientationChangeInProgress) return;
    _orientationChangeInProgress = true;
    final targetLandscape = !_androidLandscape;
    setState(() => _androidLandscape = targetLandscape);
    if (targetLandscape) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
    }
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (mounted) {
      _orientationChangeInProgress = false;
      _applyVideoFitMode();
      _onUserInteraction();
    }
  }

  Future<bool> _onAndroidPopInvoked() async {
    if (_episodeListOpenNotifier.value) {
      _episodeListOpenNotifier.value = false;
      return false;
    }
    if (_androidLandscape) {
      await _toggleAndroidOrientation();
      return false;
    }
    _leavePlayer();
    return true;
  }

  // ── Keyboard seek preview ──

  void _onArrowDown(int direction, int baseStep) {
    _arrowSeekDelayTimer?.cancel();
    if (!_arrowSeekActive) {
      _arrowSeekBasePos = _exoState.position;
      _arrowAccumulatedSeconds = 0;
    }
    _arrowHoldStart ??= DateTime.now();
    setState(() {
      _arrowSeekActive = true;
      _arrowAccumulatedSeconds += direction * baseStep;
    });
  }

  void _updateSeekPreview() {
    // KeyRepeat: ramp the step with hold duration.
    final held = DateTime.now().difference(_arrowHoldStart ?? DateTime.now());
    final step = keyboardSeekStepForHold(held);
    setState(() {
      _arrowAccumulatedSeconds +=
          (_arrowAccumulatedSeconds >= 0 ? 1 : -1) * step;
    });
  }

  void _commitSeek() {
    final base = _arrowSeekBasePos ?? _exoState.position;
    final dur = _exoState.duration;
    var target = base + Duration(seconds: _arrowAccumulatedSeconds);
    if (target < Duration.zero) target = Duration.zero;
    if (dur > Duration.zero && target > dur) target = dur;
    _arrowSeekBasePos = null;
    _arrowAccumulatedSeconds = 0;
    setState(() => _arrowSeekActive = false);
    _arrowIsLongPress = false;
    _arrowHoldStart = null;
    _lastSeekAt = DateTime.now();
    unawaited(_player.seekTo(target));
  }

  // ── Build ──

  static String _fmtHms(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  bool get _showEpisodeControls =>
      _currentItem?.type == 'Episode' && (_episodes?.isNotEmpty ?? false);

  @override
  Widget build(BuildContext context) {
    // Sync landscape state with the physical orientation.
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    if (_androidLandscape != isLandscape && !_orientationChangeInProgress) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _androidLandscape = isLandscape);
          _applyVideoFitMode();
        }
      });
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: _leavePlayer,
          ),
        ),
        body: ErrorView(
          message: _error!,
          onRetry: () => unawaited(_retryPlayback(userInitiated: true)),
        ),
      );
    }

    return TvRemoteActions(
      onBack: _leavePlayer,
      onPlayPause: _togglePlayPause,
      onFastForward: () {
        _onArrowDown(1, 30);
        _commitSeek();
      },
      onRewind: () {
        _onArrowDown(-1, 30);
        _commitSeek();
      },
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) unawaited(_onAndroidPopInvoked());
        },
        child: Focus(
          autofocus: true,
          onKeyEvent: (node, event) {
            if (event is KeyUpEvent) {
              if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
                  event.logicalKey == LogicalKeyboardKey.arrowRight) {
                _arrowHoldStart = null;
                if (_arrowIsLongPress) {
                  _commitSeek();
                } else {
                  _arrowSeekDelayTimer?.cancel();
                  _arrowSeekDelayTimer =
                      Timer(const Duration(milliseconds: 500), _commitSeek);
                }
                _arrowIsLongPress = false;
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            }
            if (event is KeyRepeatEvent) {
              if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
                  event.logicalKey == LogicalKeyboardKey.arrowRight) {
                _arrowSeekDelayTimer?.cancel();
                _arrowIsLongPress = true;
                _updateSeekPreview();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            }
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            final key = event.logicalKey;
            if (key == LogicalKeyboardKey.space) {
              _togglePlayPause();
              return KeyEventResult.handled;
            }
            if (key == LogicalKeyboardKey.escape) {
              unawaited(_onAndroidPopInvoked());
              return KeyEventResult.handled;
            }
            if (key == LogicalKeyboardKey.arrowLeft) {
              _arrowIsLongPress = false;
              _onArrowDown(-1, 10);
              return KeyEventResult.handled;
            }
            if (key == LogicalKeyboardKey.arrowRight) {
              _arrowIsLongPress = false;
              _onArrowDown(1, 10);
              return KeyEventResult.handled;
            }
            if (key == LogicalKeyboardKey.arrowUp) {
              _changeVolume(5);
              _onUserInteraction();
              return KeyEventResult.handled;
            }
            if (key == LogicalKeyboardKey.arrowDown) {
              _changeVolume(-5);
              _onUserInteraction();
              return KeyEventResult.handled;
            }
            if (key == LogicalKeyboardKey.keyM) {
              _toggleMute();
              _onUserInteraction();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Scaffold(
            backgroundColor: Colors.black,
            body: ValueListenableBuilder<bool>(
              valueListenable: _episodeListOpenNotifier,
              builder: (context, episodeListOpen, _) {
                return MouseRegion(
                  cursor: !_showChrome && !episodeListOpen
                      ? SystemMouseCursors.none
                      : MouseCursor.defer,
                  onHover: (_) => _onUserInteraction(),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Positioned.fill(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final width = constraints.maxWidth;
                            final height = constraints.maxHeight;
                            return Stack(
                              fit: StackFit.expand,
                              children: [
                                const TvExoVideoView(),
                                // External (Emby) subtitle overlay — full cue
                                // timeline powers both-direction delay and
                                // letterbox-aware anchoring.
                                if (_externalCues.isNotEmpty)
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      child: ExoSubtitleOverlay(
                                        cues: _externalCues,
                                        position: _exoState.position,
                                        delayMs: _subtitleOffsetMs,
                                        fontSizeSetting: ref
                                            .watch(settingsServiceProvider)
                                            .subtitleFontSize,
                                        fitMode: effectiveVideoFitMode(
                                          _videoFitMode,
                                          landscape: _androidLandscape,
                                        ),
                                        viewportWidth: width,
                                        viewportHeight: height,
                                        videoWidth: _exoState.videoWidth > 0
                                            ? _exoState.videoWidth
                                            : _currentItem?.videoWidth,
                                        videoHeight: _exoState.videoHeight > 0
                                            ? _exoState.videoHeight
                                            : _currentItem?.videoHeight,
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
                      // Touch gestures above the PlatformView.
                      Positioned.fill(
                        child: PlayerGestureLayer(
                          player: _player,
                          onTap: _onVideoTap,
                          onPlayPause: _togglePlayPause,
                          // Buffering/loading is not a user pause: showing the
                          // cheat-sheet there would cover the buffering pill.
                          isPlaying: _exoState.isPlaying ||
                              _exoState.isBuffering ||
                              _loading,
                          onSeekRelative: _seekRelative,
                          onSeekPreview: (delta) =>
                              _gestureSeekPreview.value = delta,
                          onVolumeDelta: _changeVolume,
                          onHoldSpeedChanged: _onHoldSpeedChanged,
                          onUserInteraction: _onUserInteraction,
                          child: const SizedBox.expand(),
                        ),
                      ),
                      if (_loading)
                        Positioned.fill(
                          child: ColoredBox(
                            color: Colors.black87,
                            child: LoadingIndicator(
                              message: _reconnecting ? '正在重连…' : '正在准备播放…',
                            ),
                          ),
                        ),
                      // Buffering mid-playback: keep the frame visible and add a
                      // pill, so a slow network reads as "loading" rather than
                      // as a frozen picture. Gated here as well as in
                      // syncBufferingFeedback: a codec fallback flips _loading on
                      // between state events, and a stale stage must not paint
                      // over the reconnect overlay.
                      if (bufferingStage != BufferingStage.hidden &&
                          !_arrowSeekActive &&
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
                      if (_arrowSeekActive &&
                          !_loading &&
                          _exoState.duration > Duration.zero)
                        _buildSeekOsd(),
                      if (_showNextEp && _nextEpisode != null && !_loading)
                        _buildNextEpisodeOverlay(),
                      if (_showChrome && !_loading && !episodeListOpen)
                        PlayerTopInfo(
                          title: _currentItem?.name ?? '',
                          onBack: _leavePlayer,
                        ),
                      if (_showChrome && !_loading && !episodeListOpen)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: ExoPlayerControls(
                            state: ExoPlayerControlsStateSnapshot(
                              position: _exoState.position,
                              duration: _exoState.duration,
                              isPlaying: _exoState.isPlaying,
                              volume: _exoState.volume,
                            ),
                            onPlayPause: _togglePlayPause,
                            onSeekTo: (target) async {
                              _lastSeekAt = DateTime.now();
                              await _player.seekTo(target);
                            },
                            onVolumeChanged: _setVolume,
                            muted: _muted,
                            embySubtitles: _info?.subtitles ?? const [],
                            nativeTextTracks: _tracks.text,
                            audioTracks: _tracks.audio,
                            unsupportedAudioTracks: _tracks.unsupportedAudio,
                            currentSubtitle: _subtitleTarget,
                            onSubtitlePicked: _onSubtitleMenuPicked,
                            currentAudio: _currentAudio,
                            onAudioPicked: _onAudioPicked,
                            onRefreshTracks: _refreshTrackCatalog,
                            speed: _speed,
                            onRatePicked: _onRatePicked,
                            videoFitMode: _videoFitMode,
                            onVideoFitModePicked: _onVideoFitModePicked,
                            readSubtitleOffsetMs: () => _subtitleOffsetMs,
                            onAdjustSubtitleDelay: _adjustSubtitleDelay,
                            onResetSubtitleDelay: _resetSubtitleDelay,
                            readAudioDelayMs: () => _audioDelayMs,
                            onAdjustAudioDelay: _adjustAudioDelay,
                            onResetAudioDelay: _resetAudioDelay,
                            gestureSeekPreviewSeconds: _gestureSeekPreview,
                            isFullScreen: _androidLandscape,
                            onToggleFullScreen: _toggleAndroidOrientation,
                            showEpisodeControls: _showEpisodeControls,
                            hasPreviousEpisode: _hasPrevEpisode,
                            hasNextEpisode: _hasNextEpisode,
                            onPreviousEpisode: _hasPrevEpisode
                                ? () => _goToAdjacentEpisode(next: false)
                                : null,
                            onNextEpisode: _hasNextEpisode
                                ? () => _goToAdjacentEpisode(next: true)
                                : null,
                            episodeListOpen: episodeListOpen,
                            onToggleEpisodeList: _showEpisodeControls
                                ? () {
                                    _episodeListOpenNotifier.value =
                                        !_episodeListOpenNotifier.value;
                                    _onUserInteraction();
                                  }
                                : null,
                            onUserInteraction: _onUserInteraction,
                          ),
                        ),
                      if (episodeListOpen)
                        PlayerEpisodePanel(
                          episode: _currentItem!,
                          playingEpisodeId: widget.itemId,
                          onSelectEpisode: _onSelectEpisode,
                          onClose: () =>
                              _episodeListOpenNotifier.value = false,
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  void _seekRelative(int seconds) {
    _gestureSeekPreview.value = 0;
    final cur = _exoState.position;
    final dur = _exoState.duration;
    var next = cur + Duration(seconds: seconds);
    if (next < Duration.zero) next = Duration.zero;
    if (dur > Duration.zero && next > dur) next = dur;
    _lastSeekAt = DateTime.now();
    unawaited(_player.seekTo(next));
  }

  Widget _buildSeekOsd() {
    final base = _arrowSeekBasePos ?? const Duration();
    final dur = _exoState.duration;
    var target = base + Duration(seconds: _arrowAccumulatedSeconds);
    if (target < Duration.zero) target = Duration.zero;
    if (target > dur) target = dur;
    final dir = _arrowAccumulatedSeconds > 0;
    final fraction = dur.inMilliseconds > 0
        ? (target.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 22),
            decoration: BoxDecoration(
              color: const Color(0xE6121212),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0x18FFFFFF)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: const Color(0x18FFFFFF),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        dir
                            ? Icons.fast_forward_rounded
                            : Icons.fast_rewind_rounded,
                        color: const Color(0xFFE8E8E8),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Text(
                      _fmtHms(target),
                      style: const TextStyle(
                        color: Color(0xFFE8E8E8),
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  '${_fmtHms(base)} / ${_fmtHms(dur)}',
                  style: const TextStyle(
                    color: Color(0x9AE8E8E8),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  width: 220,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0x26FFFFFF),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: fraction,
                      child: Container(
                        decoration: BoxDecoration(
                          color: context.playerColors.accent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNextEpisodeOverlay() {
    final ep = _nextEpisode!;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 90,
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
          decoration: BoxDecoration(
            color: const Color(0xE61A1A1A),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0x1AFFFFFF)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0x18FFFFFF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.skip_next_rounded,
                    color: Color(0xFFE8E8E8)),
              ),
              const SizedBox(width: 14),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '即将播放',
                      style:
                          TextStyle(color: Color(0x99E8E8E8), fontSize: 11.5),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      ep.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFE8E8E8),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0x26FFD54F),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${_nextEpCountdown}s',
                  style: const TextStyle(
                    color: Color(0xFFFFD54F),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Material(
                color: const Color(0x18FFFFFF),
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: _cancelNextEp,
                  child: const SizedBox(
                    width: 36,
                    height: 36,
                    child: Center(
                      child: Icon(Icons.close_rounded,
                          color: Color(0xFFE8E8E8), size: 20),
                    ),
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
