import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness/screen_brightness.dart';

import '../core/tv/tv_remote_actions.dart';
import '../core/logging/app_log.dart';
import '../core/logging/perf.dart';
import '../core/player/apply_emby_subtitle.dart';
import '../core/player/player_subtitle_visibility.dart';
import '../core/player/select_embedded_subtitle.dart';
import '../core/player/subtitle_switch_queue.dart';
import '../core/player/subtitle_render_mode.dart';
import '../core/player/subtitle_mpv_probe.dart';
import '../core/player/episode_navigation.dart';
import '../core/player/playback_resume.dart';
import '../core/player/player_codec_error.dart';
import '../core/player/player_network_error.dart';
import '../core/player/player_http_headers.dart';
import '../core/player/android_video_output_ready.dart';
import '../core/player/player_home_refresh.dart';
import '../core/player/player_video_controller_config.dart';
import '../core/player/player_subtitle_delay.dart';
import '../core/player/player_mpv_properties.dart';
import '../core/player/external_cdn_headers.dart';
import '../models/emby/emby_media_item.dart';
import '../models/emby/emby_playback_info.dart';
import '../models/emby/emby_subtitle_option.dart';
import '../core/layout/platform_layout.dart';
import '../platform/desktop_fullscreen.dart';
import '../providers/settings_provider.dart';
import '../providers/emby_provider.dart';
import '../services/emby_service.dart';
import '../services/playback_preferences_service.dart';
import '../utils/player_route.dart';
import '../widgets/error_view.dart';
import '../widgets/loading_indicator.dart';
import '../widgets/player/player_controls.dart';
import '../widgets/player/player_episode_panel.dart';
import '../widgets/player/player_top_info.dart';
import '../widgets/player/player_gesture.dart';
import '../widgets/player/player_subtitle_style.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({
    super.key,
    required this.itemId,
    this.hintPositionTicks,
  });

  final String itemId;
  final int? hintPositionTicks;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  static const _chromeHideDelay = Duration(seconds: 4);

  /// Carries landscape preference across [context.replace] when switching episodes.
  static bool _preserveAndroidLandscapeOnNextOpen = false;

  late Player _player;
  EmbyService? _emby;
  VideoController? _controller;
  EmbyPlaybackInfo? _info;
  bool _loading = true;
  String? _error;
  bool _showChrome = true;
  bool _desktopFullscreen = false;
  bool _androidLandscape = false;
  bool _orientationChangeInProgress = false;
  Timer? _progressTimer;
  Timer? _chromeIdleTimer;
  StreamSubscription<dynamic>? _playerErrorSub;
  StreamSubscription<dynamic>? _completedSub;
  StreamSubscription<Track>? _diagTrackSub;
  StreamSubscription<Tracks>? _diagTracksSub;
  VoidCallback? _cancelAndroidResumeGuard;

  /// Prevents _bootstrap from running more than once per State.
  bool _bootstrapped = false;

  /// True after playback completed and we reported PlaybackStopped to Emby.
  /// If the user seeks back and plays again, we need to re-report PlaybackStarted.
  bool _playbackReportedStopped = false;

  /// Tracks an in-flight Progress HTTP call so exit can await it before Stopped.
  Future<void>? _progressReportInFlight;

  /// Last position sent to Emby; fallback when the player is torn down before exit.
  int? _lastReportedPositionTicks;

  /// Current media item info (fetched during bootstrap for episode navigation).
  EmbyMediaItem? _currentItem;

  /// Auto-play next episode state.
  bool _showNextEp = false;
  EmbyMediaItem? _nextEpisode;
  Timer? _nextEpCountdownTimer;
  int _nextEpCountdown = 5;

  /// Episode navigation state.
  final ValueNotifier<bool> _episodeListOpenNotifier =
      ValueNotifier<bool>(false);
  List<EmbyMediaItem>? _episodes;
  bool _hasPrevEpisode = false;
  bool _hasNextEpisode = false;

  /// Tracks the last seek time to suppress auto-play-next false positives
  /// triggered by mpv spurious "completed" events during seeks.
  DateTime _lastSeekAt = DateTime.now();

  /// Prevents exiting fullscreen in dispose() when switching episodes.
  bool _episodeSwitching = false;

  double? _preMuteVolume;
  final ValueNotifier<int> _volumeShowToken = ValueNotifier<int>(0);
  final ValueNotifier<int> _gestureSeekPreview = ValueNotifier<int>(0);

  /// 长按方向键快进/快退的状态。
  DateTime? _arrowHoldStart;
  int _arrowHoldDirection = 0; // 0=无, -1=左, 1=右
  int _arrowAccumulatedSeconds = 0; // 累计偏移秒数
  Duration? _arrowSeekBasePos; // 按键按下时的播放位置
  bool _arrowIsLongPress = false; // 是否触发了 KeyRepeatEvent
  Timer? _arrowSeekDelayTimer; // 短按延迟提交定时器
  bool get _arrowSeekActive =>
      _arrowHoldStart != null || _arrowAccumulatedSeconds != 0;

  /// Overlapping `window_manager.setFullScreen` calls can freeze the Flutter view on Windows
  /// while media_kit keeps decoding — run all fullscreen mutations strictly one-after-another.
  Future<void> _fullscreenOpChain = Future<void>.value();

  /// Active bootstrap span. Closed when the first non-zero playback position
  /// is observed (= true "first frame" indication from mpv).
  PerfSpan? _bootstrapSpan;
  StreamSubscription<Duration>? _firstFrameWatch;
  bool _firstFrameReported = false;

  /// Separate first-frame trace for F-A1 baseline (`player_first_frame`).
  PerfSpan? _firstFramePerfSpan;
  StreamSubscription<VideoParams>? _videoParamsFirstFrameSub;
  bool _firstFramePerfDone = false;

  /// Invoked by resume guard / video-params when bootstrap can drop the overlay.
  VoidCallback? _trySettleFirstFrame;

  /// True once the Android Surface is attached **and** media_kit_video's
  /// widListener seek(state.position) has settled (~120 ms wait). Drives the
  /// loading-mask gate so the overlay doesn't drop while the screen is still
  /// black or about to re-seek. Non-Android sets this to true right after
  /// `_ensureVideoOutputReady` since there is no late-attach race.
  bool _surfaceAttachSettled = false;

  /// Captured while [context] is still mounted — safe for [dispose].
  ProviderContainer? _riverpodContainer;

  /// True once mpv reports a position that crosses the resume target (or
  /// crosses 50 ms for fresh playback). Drives the loading-mask gate.
  bool _positionFirstFrameReady = false;

  Timer? _bootstrapTimeoutTimer;

  /// Set when retry/error aborts an in-flight bootstrap.
  bool _bootstrapCancelled = false;

  EmbyPlaybackInfo? _pendingSubtitlePb;

  /// Resume position for manual retry / recovery (ticks); overrides [hintPositionTicks].
  int? _resumeTicksOverride;

  static const _maxNetworkRecoveryAttempts = 3;

  int _networkRecoveryAttempts = 0;
  bool _networkRecoveryInProgress = false;
  int _networkRecoveryGeneration = 0;
  bool _reconnecting = false;
  bool _leavingPlayer = false;
  bool _codecFallbackAttempted = false;
  bool _codecFallbackInProgress = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _riverpodContainer ??= ProviderScope.containerOf(context);
  }

  @override
  void initState() {
    super.initState();
    final playerSvc = ref.read(playerServiceProvider);
    playerSvc.disposePlayer();
    _player = playerSvc.player;
    _diagTrackSub = _player.stream.track.listen((t) {
      AppLog.instance.d(
        'SubtitleDiag',
        'stream.track.subtitle id=${t.subtitle.id} title=${t.subtitle.title}',
      );
    });
    _diagTracksSub = _player.stream.tracks.listen((tracks) {
      final n =
          tracks.subtitle.where((s) => s.id != 'auto' && s.id != 'no').length;
      AppLog.instance.d('SubtitleDiag', 'stream.tracks subtitle_count=$n');
    });
    _bindPlayerErrorListener();
    unawaited(_bootstrap());
    if (isAndroidMobileUi) {
      unawaited(
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky));
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
    }
  }

  bool get _canDesktopFullscreen =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);

  void _cancelNetworkRecovery() {
    _networkRecoveryGeneration++;
    _networkRecoveryInProgress = false;
    _reconnecting = false;
  }

  int? _capturePlaybackPositionTicks() {
    try {
      final pos = _player.state.position;
      if (pos <= Duration.zero) return null;
      return (pos.inMicroseconds * 10).clamp(0, 1 << 62).toInt();
    } catch (_) {
      return null;
    }
  }

  Duration _clampResumePosition(Duration at, int? runTimeTicks) {
    if (runTimeTicks == null || runTimeTicks <= 0) return at;
    final runtime = Duration(microseconds: runTimeTicks ~/ 10);
    if (runtime <= const Duration(seconds: 30)) return at;
    final maxStart = runtime - const Duration(seconds: 30);
    if (at > maxStart) return maxStart;
    return at;
  }

  Future<void> _failPlayback(String message) async {
    _cancelNetworkRecovery();
    _cancelBootstrapInProgress(firstFrameVia: 'playback_error');
    try {
      await _player.stop();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _error = isRecoverablePlayerCodecError(message)
          ? playerCodecErrorFinalMessage(message)
          : message;
      _loading = false;
      _bootstrapped = false;
      _reconnecting = false;
    });
  }

  void _bindPlayerErrorListener() {
    _playerErrorSub?.cancel();
    _playerErrorSub = _player.stream.error.listen((message) {
      if (!mounted) return;
      final text = message.toString().trim();
      if (text.isEmpty) return;
      if (isNonFatalPlayerSubtitleError(text)) {
        AppLog.instance.w('Player', 'non-fatal subtitle error: $text');
        return;
      }
      if (isRecoverablePlayerNetworkError(text) &&
          _bootstrapped &&
          _info != null &&
          !_bootstrapCancelled) {
        AppLog.instance.w('Player', 'recoverable network error: $text');
        unawaited(_handleRecoverableNetworkError(text));
        return;
      }
      if (isRecoverablePlayerCodecError(text) &&
          _info != null &&
          !_bootstrapCancelled &&
          !_codecFallbackAttempted) {
        AppLog.instance.w('Player', 'recoverable codec error: $text');
        unawaited(_handleRecoverableCodecError(text));
        return;
      }
      AppLog.instance.e('Player', 'playback error: $text');
      unawaited(_failPlayback(text));
    });
  }

  Future<void> _handleRecoverableCodecError(String raw) async {
    if (_codecFallbackInProgress || _codecFallbackAttempted) {
      await _failPlayback(raw);
      return;
    }
    final emby = _emby;
    if (emby == null) {
      await _failPlayback(raw);
      return;
    }

    _codecFallbackAttempted = true;
    _codecFallbackInProgress = true;

    try {
      if (!mounted) return;

      AppLog.instance.w(
        'Player',
        'codec fallback: re-fetching PlaybackInfo for transcode',
      );

      setState(() {
        _error = null;
        _loading = true;
        _reconnecting = true;
      });

      final ticks = _capturePlaybackPositionTicks() ??
          widget.hintPositionTicks ??
          0;

      final pb = await emby.getPlaybackInfo(
        widget.itemId,
        startTimeTicks: ticks,
      );
      if (!mounted) return;

      final fallback = pb.fallbackStreamUrl;
      final sameDirectUrl = pb.streamUrl == _info?.streamUrl;
      if (pb.supportsDirectPlay != false &&
          (fallback == null || fallback == pb.streamUrl) &&
          sameDirectUrl) {
        await _failPlayback(raw);
        return;
      }

      await _preparePlaybackRetry(resetCodecFallback: false);
      if (!mounted) return;

      setState(() {
        _info = pb;
        _error = null;
        _loading = true;
        _reconnecting = false;
      });
      await _bootstrap();
    } catch (e, st) {
      AppLog.instance.e(
        'Player',
        'codec fallback failed',
        error: e,
        stackTrace: st,
      );
      await _failPlayback(raw);
    } finally {
      _codecFallbackInProgress = false;
    }
  }

  Future<void> _handleRecoverableNetworkError(String raw) async {
    if (_networkRecoveryInProgress) return;
    if (!_bootstrapped || _info == null) {
      await _failPlayback(raw);
      return;
    }

    _networkRecoveryInProgress = true;
    final gen = ++_networkRecoveryGeneration;

    try {
      while (_networkRecoveryAttempts < _maxNetworkRecoveryAttempts) {
        if (!mounted || gen != _networkRecoveryGeneration) return;

        _networkRecoveryAttempts++;
        final attempt = _networkRecoveryAttempts;

        final ticks = _capturePlaybackPositionTicks();
        var resumeAt = ticks != null && ticks > 0
            ? Duration(microseconds: ticks ~/ 10)
            : _player.state.position;
        resumeAt = _clampResumePosition(resumeAt, _info!.runTimeTicks);
        if (resumeAt <= Duration.zero) {
          await _failPlayback(raw);
          return;
        }

        AppLog.instance.w(
          'Player',
          'network recovery attempt=$attempt/$_maxNetworkRecoveryAttempts '
              'pos=${resumeAt.inSeconds}s: $raw',
        );

        try {
          await _player.stop();
        } catch (_) {}

        if (!mounted || gen != _networkRecoveryGeneration) return;

        _progressTimer?.cancel();
        _progressTimer = null;
        _completedSub?.cancel();
        _completedSub = null;
        _firstFrameWatch?.cancel();
        _firstFrameWatch = null;

        setState(() {
          _error = null;
          _reconnecting = true;
          _loading = true;
        });

        final delayMs = 400 * (1 << (attempt - 1));
        await Future<void>.delayed(Duration(milliseconds: delayMs));
        if (!mounted || gen != _networkRecoveryGeneration) return;

        try {
          await _reopenPlaybackAt(
            resumeAt,
            attempt: attempt,
            generation: gen,
          );
          await _waitPlaybackResumed(resumeAt);
          if (!mounted || gen != _networkRecoveryGeneration) return;

          _networkRecoveryAttempts = 0;
          _progressTimer = Timer.periodic(
            const Duration(seconds: 10),
            (_) => unawaited(_reportProgress()),
          );
          _completedSub = _player.stream.completed.listen((completed) {
            if (!mounted || !completed) return;
            unawaited(_onPlaybackCompleted());
          });

          AppLog.instance.i(
            'Player',
            'network recovery ok attempt=$attempt pos=${resumeAt.inSeconds}s',
          );
          setState(() {
            _reconnecting = false;
            _loading = false;
          });
          return;
        } catch (e, st) {
          AppLog.instance.e(
            'Player',
            'network recovery attempt=$attempt failed',
            error: e,
            stackTrace: st,
          );
        }
      }

      await _failPlayback(
        playerNetworkErrorFinalMessage(_maxNetworkRecoveryAttempts),
      );
    } finally {
      if (gen == _networkRecoveryGeneration) {
        _networkRecoveryInProgress = false;
        _reconnecting = false;
      }
    }
  }

  Future<void> _reopenPlaybackAt(
    Duration resumeAt, {
    required int attempt,
    required int generation,
  }) async {
    final pb = _info;
    final emby = _emby;
    if (pb == null || emby == null) {
      throw StateError('playback info not ready');
    }
    if (generation != _networkRecoveryGeneration) {
      throw StateError('recovery cancelled');
    }

    final startSecsStr = (resumeAt.inMilliseconds / 1000).toStringAsFixed(3);
    await _player.setMpvProperty('start', startSecsStr);

    if (pb.strmViaEmbyStream) {
      final cdnFuture = PerfTracer.measure(
        'emby.resolveExternalCdnUrl',
        () => emby.resolveExternalCdnUrl(pb.streamUrl),
        context: {'mode': 'network_recovery'},
      );
      await _openStrmPlayback(pb.streamUrl, cdnUrlFuture: cdnFuture);
    } else {
      final headers = emby.playbackStreamHttpHeaders(pb.streamUrl);
      final serverBase =
          ref.read(settingsServiceProvider).embyServerUrl?.trim() ?? '';
      final normalizedBase = serverBase.endsWith('/')
          ? serverBase.substring(0, serverBase.length - 1)
          : serverBase;
      final tuneProbe = !isAndroidMobileUi &&
          normalizedBase.isNotEmpty &&
          isEmbyHostedStreamUrl(pb.streamUrl, normalizedBase);
      await _openStream(
        pb.streamUrl,
        headers: headers,
        externalCdn: isExternalCdnPlaybackUrl(pb.streamUrl),
        tuneProbe: tuneProbe,
      );
    }

    if (!mounted || generation != _networkRecoveryGeneration) {
      throw StateError('recovery cancelled');
    }

    await _applyResumeAndStart();
  }

  Future<void> _waitPlaybackResumed(
    Duration target, {
    Duration timeout = const Duration(seconds: 12),
  }) async {
    if (target <= Duration.zero) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      return;
    }
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (!mounted) return;
      final pos = _player.state.position;
      if (isResumePositionSettled(pos, target)) return;
      if (_player.state.playing &&
          pos.inMilliseconds >= target.inMilliseconds - 3000) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  /// Stops first-frame watchers, timers, and incomplete bootstrap spans.
  void _cancelBootstrapInProgress({String? firstFrameVia}) {
    _bootstrapCancelled = true;
    _bootstrapTimeoutTimer?.cancel();
    _bootstrapTimeoutTimer = null;
    _firstFrameWatch?.cancel();
    _firstFrameWatch = null;
    _trySettleFirstFrame = null;
    _surfaceAttachSettled = false;
    _positionFirstFrameReady = false;
    _completedSub?.cancel();
    _completedSub = null;
    _progressTimer?.cancel();
    _progressTimer = null;
    if (!_firstFrameReported) {
      _firstFrameReported = true;
      final span = _bootstrapSpan;
      if (span != null) {
        span.end(
            extraContext: {'first_frame_via': firstFrameVia ?? 'cancelled'});
        _bootstrapSpan = null;
      }
    }
    if (!_firstFramePerfDone) {
      _cancelFirstFramePerfTrace();
    }
  }

  Future<void> _preparePlaybackRetry({bool resetCodecFallback = true}) async {
    _cancelNetworkRecovery();
    if (resetCodecFallback) {
      _codecFallbackAttempted = false;
    }
    final ticks = _capturePlaybackPositionTicks();
    if (ticks != null && ticks > 0) {
      _resumeTicksOverride = ticks;
    }
    _cancelBootstrapInProgress(firstFrameVia: 'retry');
    _cancelAndroidResumeGuard?.call();
    _cancelAndroidResumeGuard = null;
    _bootstrapped = false;
    _playbackReportedStopped = false;
    _bootstrapCancelled = false;
    _networkRecoveryAttempts = 0;
    try {
      await _player.stop();
    } catch (_) {}
  }

  Future<void> _retryPlayback() async {
    await _preparePlaybackRetry();
    if (!mounted) return;
    setState(() {
      _error = null;
      _loading = true;
      _reconnecting = false;
    });
    await _bootstrap();
  }

  int? _consumeResumeTicksOverride() {
    final v = _resumeTicksOverride;
    _resumeTicksOverride = null;
    return v;
  }

  Future<void> _bootstrap() async {
    if (_bootstrapped) return;
    _bootstrapCancelled = false;
    _firstFrameReported = false;
    _startFirstFramePerfTrace();
    final span = PerfTracer.start(
      'player.bootstrap',
      context: {
        'itemId': widget.itemId,
        'hintTicks': widget.hintPositionTicks,
      },
    );
    _bootstrapSpan = span;
    await AppLog.bindTrace(span.traceId, () => _bootstrapWithSpan(span));
  }

  void _startFirstFramePerfTrace() {
    _videoParamsFirstFrameSub?.cancel();
    _firstFramePerfDone = false;
    final span = PerfTracer.start(
      'player_first_frame',
      context: {'itemId': widget.itemId},
    );
    _firstFramePerfSpan = span;
    _videoParamsFirstFrameSub = _player.stream.videoParams.listen((params) {
      if (_firstFramePerfDone) return;
      if (!_hasDecodedVideoParams(params)) return;
      _firstFramePerfDone = true;
      span.end(extraContext: {'w': params.w, 'h': params.h});
      _firstFramePerfSpan = null;
      _videoParamsFirstFrameSub?.cancel();
      _videoParamsFirstFrameSub = null;
      _trySettleFirstFrame?.call();
    });
  }

  bool _hasDecodedVideoParams(VideoParams params) {
    final w = params.w;
    final h = params.h;
    return w != null && h != null && w > 0 && h > 0;
  }

  void _cancelFirstFramePerfTrace({Object? error, StackTrace? stackTrace}) {
    _videoParamsFirstFrameSub?.cancel();
    _videoParamsFirstFrameSub = null;
    final span = _firstFramePerfSpan;
    if (span == null || _firstFramePerfDone) return;
    _firstFramePerfDone = true;
    if (error != null) {
      span.endError(error, stackTrace);
    } else {
      span.end(extraContext: {'first_frame_via': 'cancelled'});
    }
    _firstFramePerfSpan = null;
  }

  Future<void> _bootstrapWithSpan(PerfSpan span) async {
    try {
      _lastSeekAt = DateTime.now();
      final emby = ref.read(embyServiceProvider);
      _emby = emby;
      final startTimeTicks =
          _consumeResumeTicksOverride() ?? widget.hintPositionTicks ?? 0;
      final settings = ref.read(settingsServiceProvider);
      final playbackResults = await Future.wait<Object>([
        emby.getPlaybackInfo(
          widget.itemId,
          startTimeTicks: startTimeTicks,
        ),
        emby.getItemForPlayer(widget.itemId),
      ]);
      final pb = playbackResults[0] as EmbyPlaybackInfo;
      final item = playbackResults[1] as EmbyMediaItem;
      span.stage('playback_info');
      if (!mounted || _bootstrapCancelled) return;

      _currentItem = item;

      // Resolve external CDN in parallel with surface setup; consumed synchronously at
      // mpv_open so the URL stays fresh (unlike early parallel + late open).
      Future<String>? strmCdnFuture;
      if (pb.strmViaEmbyStream) {
        strmCdnFuture = PerfTracer.measure(
          'emby.resolveExternalCdnUrl',
          () => emby.resolveExternalCdnUrl(pb.streamUrl),
          context: {'mode': 'parallel_surface'},
        );
      }

      final hwDecoding = settings.hardwareDecoding;
      final onEmulator = await isMediaKitAndroidEmulator();
      if (onEmulator) {
        AppLog.instance.i(
          'Player',
          'Android emulator: vo=mediacodec_embed hwdec=mediacodec',
        );
      }
      final vc = VideoController(
        _player,
        configuration: videoControllerConfiguration(
          hardwareDecoding: hwDecoding,
          onEmulator: onEmulator,
        ),
      );
      span.stage('controller_created');
      setState(() {
        _controller = vc;
        _info = pb;
      });
      // [Video] is created on the next frame; waiting avoids a false 10s surface
      // timeout while wid is still null (then open runs and wid attach resets --start).
      await waitForVideoWidgetMounted();
      if (!mounted || _bootstrapCancelled) return;
      span.stage('widget_mounted');
      AppLog.instance
          .d('Player', 'Video widget mounted, checking Android surface');
      await _ensureVideoOutputReady(
        vc,
        allowOpenWithoutSurface: onEmulator,
      );
      if (!mounted || _bootstrapCancelled) return;
      span.stage('surface_ready');
      // Non-Android has no late-attach race — open the loading-mask gate now.
      if (!isAndroidMobileUi) {
        _surfaceAttachSettled = true;
      }
      final serverBase =
          ref.read(settingsServiceProvider).embyServerUrl?.trim() ?? '';
      final normalizedBase = serverBase.endsWith('/')
          ? serverBase.substring(0, serverBase.length - 1)
          : serverBase;
      final strm = pb.strmViaEmbyStream;
      final resumeAt = resumePlaybackPosition(
        playbackPositionTicks:
            startTimeTicks > 0 ? startTimeTicks : widget.hintPositionTicks,
        runTimeTicks: pb.runTimeTicks,
      );
      AppLog.instance.i(
        'Player',
        'open itemId=${widget.itemId} strm=$strm url=${AppLog.redactUrl(pb.streamUrl)} '
            'subs=${pb.subtitles.length} resumeTicks=$startTimeTicks '
            'resumeAt=${resumeAt != null ? "${resumeAt.inSeconds}s" : "none"}',
      );

      // Set mpv start position BEFORE opening so playback begins at the resume
      // point. This is more reliable than post-open seek on Android where the
      // decoder may not accept seek commands until fully initialized.
      _cancelAndroidResumeGuard?.call();
      _cancelAndroidResumeGuard = null;
      // Install the Android surface guard for both resume and fresh playback —
      // we need the "wid attached + widListener seek settled" signal in both
      // cases to gate the loading mask. The guard internally skips re-seek
      // when resumeAt is zero.
      if (isAndroidMobileUi) {
        _cancelAndroidResumeGuard = installAndroidResumeSurfaceGuard(
          controller: vc,
          player: _player,
          resumeAt: resumeAt ?? Duration.zero,
          onSurfaceSettled: () {
            _surfaceAttachSettled = true;
            if (onEmulator) {
              unawaited(_nudgeEmulatorSurfaceOutput());
            }
            _trySettleFirstFrame?.call();
          },
        );
      }
      if (resumeAt != null) {
        // mpv --start accepts fractional seconds — use ms precision so resume
        // lands within the actual saved position instead of rounding down up
        // to a full second.
        final startSecsStr =
            (resumeAt.inMilliseconds / 1000).toStringAsFixed(3);
        await _player.setMpvProperty('start', startSecsStr);
        AppLog.instance.i('Player', 'mpv start set to ${startSecsStr}s');
        logPlayerPlaybackPosition(
          _player,
          'After mpv --start property',
          expectedResumeAt: resumeAt,
        );
      }
      if (strm) {
        await _openStrmPlayback(pb.streamUrl, cdnUrlFuture: strmCdnFuture);
      } else {
        final headers = emby.playbackStreamHttpHeaders(pb.streamUrl);
        final tuneProbe = !isAndroidMobileUi &&
            normalizedBase.isNotEmpty &&
            isEmbyHostedStreamUrl(pb.streamUrl, normalizedBase);
        await _openStream(
          pb.streamUrl,
          headers: headers,
          externalCdn: isExternalCdnPlaybackUrl(pb.streamUrl),
          tuneProbe: tuneProbe,
        );
      }
      if (!mounted || _bootstrapCancelled || _error != null) return;
      span.stage('mpv_open');
      logPlayerPlaybackPosition(
        _player,
        'After _openStream, before play',
        expectedResumeAt: resumeAt,
      );
      await _applyResumeAndStart();
      _pendingSubtitlePb = pb;
      span.stage('play_called');
      logPlayerPlaybackPosition(
        _player,
        'After play()',
        expectedResumeAt: resumeAt,
      );
      await logMpvSubtitleDecoderSupport(_player);
      if (!mounted || _bootstrapCancelled) return;
      _bootstrapped = true;
      // Loading overlay stays visible until the **first frame at the expected
      // position** is observed — this hides the brief seek(0) → resume bounce
      // caused by media_kit_video's Android widListener on lazy-surface
      // devices (see _installFirstFrameWatcher).
      _installFirstFrameWatcher(span, resumeAt: resumeAt);
      _lastSeekAt = DateTime.now();
      _progressTimer = Timer.periodic(
          const Duration(seconds: 10), (_) => unawaited(_reportProgress()));
      _completedSub = _player.stream.completed.listen((completed) {
        if (!mounted || !completed) return;
        unawaited(_onPlaybackCompleted());
      });
      unawaited(emby.reportPlaybackStarted(
        itemId: widget.itemId,
        mediaSourceId: pb.mediaSourceId,
        playSessionId: pb.playSessionId,
        positionTicks: startTimeTicks,
      ));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_canDesktopFullscreen) {
          unawaited(_syncDesktopFullscreenFlag());
        }
        _scheduleChromeHide();
      });
    } catch (e, st) {
      _cancelFirstFramePerfTrace(error: e, stackTrace: st);
      if (!mounted) {
        span.endError(e, st);
        _bootstrapSpan = null;
        return;
      }
      _bootstrapped = false; // Allow retry.
      AppLog.instance.e(
        'Player',
        'bootstrap failed itemId=${widget.itemId}',
        error: e,
        stackTrace: st,
      );
      span.endError(e, st);
      _bootstrapSpan = null;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// Closes the bootstrap span when mpv reports playback at or past the
  /// expected start position (= the real, correct frame is on screen) and
  /// hides the loading overlay at the same time.
  ///
  /// On Android, `media_kit_video`'s widListener does `seek(Duration.zero)`
  /// when `wid` flips 0 → non-zero, which momentarily resets the position to
  /// 0 even when we requested resume via `mpv --start`. Keeping the loading
  /// overlay until we see a position > resumeAt hides that bounce — the user
  /// sees `正在准备播放…` straight through to the correct frame.
  ///
  /// Two settle paths:
  /// - `position` — pos crossed `resumeAt + 50 ms`, the normal resume case.
  /// - `playing_off_target` — pos has advanced ≥ 1 s continuously since the
  ///   first non-zero reading, but never reached the resume target. This
  ///   covers the failure mode where the resume guard mis-fires and mpv plays
  ///   from 0 (or some other wrong position): UI should drop the loading
  ///   overlay so the user can see what's happening instead of waiting for
  ///   the 12 s safety timeout.
  /// - `timeout` — 12 s hard safety so the overlay never sticks forever.
  void _installFirstFrameWatcher(PerfSpan span, {Duration? resumeAt}) {
    _firstFrameWatch?.cancel();
    _firstFrameReported = false;
    _positionFirstFrameReady = false;
    _trySettleFirstFrame = null;
    final resumeTarget = resumeAt ?? Duration.zero;

    void settle(String reason) {
      if (_firstFrameReported) return;
      _firstFrameReported = true;
      _trySettleFirstFrame = null;
      _bootstrapTimeoutTimer?.cancel();
      _bootstrapTimeoutTimer = null;
      _firstFrameWatch?.cancel();
      _firstFrameWatch = null;
      span.stage(reason == 'timeout' ? 'first_frame_timeout' : 'first_frame');
      span.end(extraContext: {'first_frame_via': reason});
      _bootstrapSpan = null;
      if (mounted && _loading) {
        setState(() => _loading = false);
      }
      _runPostFirstFrameTasks();
    }

    // Drops the mask only after **both** signals are in:
    //   1) mpv has reached the expected playback position
    //   2) on Android, the Surface attached and media_kit_video's widListener
    //      seek(state.position) has settled (the 120 ms guard wait).
    // Without (2) the overlay vanishes while the screen is still black and
    // the user sees a visible "seek bounce" once the surface finally attaches.
    void settleIfGatesOpen(String reason) {
      if (_firstFrameReported) return;
      if (!_positionFirstFrameReady) return;
      if (isAndroidMobileUi && !_surfaceAttachSettled) return;
      settle(reason);
    }

    void trySettle(String reason) {
      if (_firstFrameReported) return;
      final pos = _player.state.position;
      if (isResumePositionSettled(pos, resumeTarget)) {
        _positionFirstFrameReady = true;
        settleIfGatesOpen(reason);
        return;
      }
      // Fresh playback: decoded video + playing is enough once position moves.
      if (resumeTarget <= Duration.zero &&
          _firstFramePerfDone &&
          _player.state.playing &&
          pos.inMilliseconds > 50) {
        _positionFirstFrameReady = true;
        settleIfGatesOpen(reason);
        return;
      }
      // Resume: decoded frames while position is still catching up to --start.
      if (resumeTarget > Duration.zero &&
          _firstFramePerfDone &&
          _player.state.playing &&
          pos.inMilliseconds >= 100) {
        _positionFirstFrameReady = true;
        settleIfGatesOpen('video_playing');
      }
    }

    _trySettleFirstFrame = () => trySettle('bootstrap_settle');

    // Track the first significant non-zero reading so we can recognise
    // "playing, just not where we expected" as a valid first-frame signal.
    Duration? firstAdvancePos;
    DateTime? firstAdvanceAt;

    _firstFrameWatch = _player.stream.position.listen((pos) {
      if (isResumePositionSettled(pos, resumeTarget)) {
        _positionFirstFrameReady = true;
        settleIfGatesOpen('position');
        return;
      }

      // Fallback path — resume guard mis-fired but playback is happening.
      // Require: pos > 200 ms (skip 0/initial noise), and 1 s of continuous
      // advancement of at least 500 ms (so we don't fire on a single stray
      // position event from the seek(0) bounce). This path bypasses the
      // surface gate intentionally: if mpv has played 500 ms of content the
      // surface is definitely attached, even if the guard callback missed.
      final posMs = pos.inMilliseconds;
      if (posMs < 200) return;
      if (firstAdvancePos == null) {
        firstAdvancePos = pos;
        firstAdvanceAt = DateTime.now();
        return;
      }
      final advanceMs = posMs - firstAdvancePos!.inMilliseconds;
      final elapsed = DateTime.now().difference(firstAdvanceAt!);
      if (elapsed >= const Duration(seconds: 1) && advanceMs >= 500) {
        settle('playing_off_target');
      }
    });

    _bootstrapTimeoutTimer?.cancel();
    _bootstrapTimeoutTimer =
        Timer(const Duration(seconds: 12), () => settle('timeout'));
  }

  EmbySubtitleOption? _embySubtitleBySelection(
    String selection,
    List<EmbySubtitleOption> subtitles,
  ) {
    if (!selection.startsWith(PlaybackPreferencesService.subtitleEmbyPrefix)) {
      return null;
    }
    final index = int.tryParse(
      selection.substring(PlaybackPreferencesService.subtitleEmbyPrefix.length),
    );
    if (index == null) return null;
    for (final o in subtitles) {
      if (o.index == index) return o;
    }
    return null;
  }

  Future<bool> _applySavedEmbeddedSubtitle(
    String trackId, {
    int? expectedMuxedTracks,
  }) async {
    // Fast path mirrors applyEmbySubtitle — no muxed track will ever appear.
    if (expectedMuxedTracks != null && expectedMuxedTracks <= 0) {
      AppLog.instance.w(
        'Subtitle',
        'saved embedded skipped — file has no muxed subtitles trackId=$trackId',
      );
      return false;
    }
    // Aligned with applyEmbySubtitle's 12 × 80 ms = ~1 s retry budget.
    for (var attempt = 0; attempt < 12; attempt++) {
      for (final t in _player.state.tracks.subtitle) {
        if (t.id == trackId) {
          await SubtitleSwitchQueue.withMpv(
            () =>
                _player.activateMuxedSubtitle(t, reason: 'pref_track_$trackId'),
          );
          await _applySubtitleOffset();
          return true;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
    return false;
  }

  void _logActiveSubtitleTracks(String reason) {
    final cur = _player.state.track.subtitle;
    final tracks = _player.state.tracks.subtitle
        .where((t) => t.id != 'auto' && t.id != 'no')
        .toList();
    AppLog.instance.i(
      'Subtitle',
      '$reason current sid=${cur.id} title=${cur.title} lang=${cur.language} '
          'available=${tracks.map((t) => "sid=${t.id}:${t.title ?? t.language ?? "?"}").join(", ")}',
    );
  }

  Future<void> _applySubtitleOffset() async {
    final offsetMs = ref.read(settingsServiceProvider).subtitleOffsetMs;
    AppLog.instance.d('Subtitle', 'setSubtitleDelay offsetMs=$offsetMs');
    try {
      await _player.setSubtitleDelay(Duration(milliseconds: offsetMs));
    } catch (e, st) {
      AppLog.instance.w('Subtitle', 'setSubtitleDelay failed', e);
      AppLog.instance.e('Subtitle', 'delay error', error: e, stackTrace: st);
    }
  }

  Future<void> _applySubtitlePreference(EmbyPlaybackInfo pb) async {
    final emby = _emby;
    if (emby == null) return;

    // Count of muxed (non-external) subtitle tracks Emby reports for this
    // file. When this is 0 we can skip every muxed retry path immediately —
    // mpv won't ever surface tracks that aren't in the file.
    final expectedMuxedTracks = pb.subtitles.where((s) => !s.isExternal).length;

    final prefs = ref.read(playbackPreferencesServiceProvider);
    final saved = prefs.getSubtitleSelection(widget.itemId);
    SubtitleSwitchQueue.runDetached((gen) async {
      try {
        if (saved == PlaybackPreferencesService.subtitleOff) {
          await SubtitleSwitchQueue.withMpv(
            () => _player.activateSubtitleTrack(
              SubtitleTrack.no(),
              reason: 'pref_off',
            ),
          );
          return;
        }
        if (saved == PlaybackPreferencesService.subtitleAuto) {
          await selectEmbeddedSubtitle(
            player: _player,
            embyOptions: pb.subtitles,
            prefer: pb.preferredSubtitle,
            emby: emby,
            generation: gen,
          );
          _logActiveSubtitleTracks('auto');
          if (SubtitleSwitchQueue.isCurrent(gen)) {
            await _applySubtitleOffset();
          }
          return;
        }
        if (saved != null) {
          final option = _embySubtitleBySelection(saved, pb.subtitles);
          if (option != null) {
            await applyEmbySubtitle(
              player: _player,
              option: option,
              emby: emby,
              generation: gen,
              expectedMuxedTracks: expectedMuxedTracks,
            );
            if (SubtitleSwitchQueue.isCurrent(gen)) {
              await _applySubtitleOffset();
            }
            return;
          }
          if (saved
              .startsWith(PlaybackPreferencesService.subtitleTrackPrefix)) {
            final trackId = saved.substring(
              PlaybackPreferencesService.subtitleTrackPrefix.length,
            );
            if (await _applySavedEmbeddedSubtitle(
              trackId,
              expectedMuxedTracks: expectedMuxedTracks,
            )) {
              return;
            }
          }
        }

        final preferredSub = pb.preferredSubtitle;
        if (preferredSub != null) {
          await applyEmbySubtitle(
            player: _player,
            option: preferredSub,
            emby: emby,
            generation: gen,
            expectedMuxedTracks: expectedMuxedTracks,
          );
        }
        if (SubtitleSwitchQueue.isCurrent(gen)) {
          await _applySubtitleOffset();
        }
      } catch (e, st) {
        if (isSubtitleSwitchCancelled(e)) return;
        AppLog.instance.e(
          'Subtitle',
          'applySubtitlePreference failed itemId=${widget.itemId}',
          error: e,
          stackTrace: st,
        );
      }
    });
  }

  /// Episode metadata, subtitles, and ep list — after loading overlay drops.
  void _runPostFirstFrameTasks() {
    final pb = _pendingSubtitlePb ?? _info;
    _pendingSubtitlePb = null;
    if (pb != null) {
      unawaited(_player.configureMpvSubtitlesOnce());
      unawaited(_applySubtitlePreference(pb));
    }
    unawaited(_loadPlayerItemMetadata());
  }

  Future<void> _loadPlayerItemMetadata() async {
    final emby = _emby;
    if (emby == null) return;
    try {
      if (_currentItem == null) {
        final item = await emby.getItemForPlayer(widget.itemId);
        if (!mounted) return;
        setState(() => _currentItem = item);
      }
      await _fetchEpisodes();
    } catch (e) {
      AppLog.instance.w('Player',
          'loadPlayerItemMetadata failed itemId=${widget.itemId}: $e');
    }
  }

  Future<void> _applyResumeAndStart() async {
    // Resume is handled via mpv --start property set before _player.open().
    // The Android Surface is guaranteed to be attached before open thanks to
    // waitForAndroidVideoSurface's wid-listener approach, so media_kit_video's
    // widListener won't reset the position with seek(Duration.zero).
    AppLog.instance
        .i('Player', 'Resume: starting playback (resume via mpv --start)');
    final speed = ref.read(settingsServiceProvider).defaultPlaybackSpeed;

    if (isAndroidMobileUi && _player.state.volume <= 0) {
      await _player.setVolume(100);
    }

    await _player.play();
    await _player.setRate(speed);
  }

  /// After mediacodec_embed surface attach on AVD, nudge mpv to repaint without
  /// recreating the [Video] widget (which would detach the Surface again).
  Future<void> _nudgeEmulatorSurfaceOutput() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;
    final pos = _player.state.position;
    if (pos <= Duration.zero) return;
    try {
      await _player.seek(pos);
    } catch (_) {}
  }

  /// [Video] 必须在 [Player.open] 前挂载；Android 还需非零 `--wid`（Surface 已绑定）。
  Future<void> _ensureVideoOutputReady(
    VideoController controller, {
    bool allowOpenWithoutSurface = false,
  }) async {
    if (!isAndroidMobileUi) {
      await controller.platform.future;
      await WidgetsBinding.instance.endOfFrame;
      return;
    }
    final ok = await waitForAndroidVideoSurface(controller);
    if (ok) return;
    if (allowOpenWithoutSurface) {
      AppLog.instance.w(
        'Player',
        'Android emulator: opening without surface (using mediacodec_embed renderer)',
      );
      return;
    }
    // Surface not ready but don't crash; try to continue anyway.
    AppLog.instance.w(
      'Player',
      'Android surface not ready, continuing anyway (may recover after open)',
    );
  }

  /// Upper bound for blocking on the parallel external CDN resolve before
  /// falling back to opening the Emby `/stream` URL (mpv follows the 307).
  ///
  /// IMPORTANT — do NOT shorten this to "save" mpv_open time. The Emby 307
  /// fallback is a **much slower** playback path, not an equivalent one: with
  /// it, every mpv seek/range request (including the resume `--start` seek)
  /// re-traverses Emby → 307 → CDN, which pushed first_frame from ~1 s to
  /// 9–12 s in testing (2026-05-29). The direct CDN URL lets mpv issue range
  /// requests straight to the CDN. So we wait essentially as long as it takes.
  ///
  /// Strm: prefer fresh CDN URL at mpv_open (parallel resolve during surface
  /// wait); on expired CDN clear MP 302 cache and resolve once more; fall back
  /// to Emby `/stream` 307 when resolve fails, times out, or URL stays expired.
  ///
  /// Expired + retry path can add up to ~8s (clear) + 8s (re-resolve) before the
  /// slower Emby 307 fallback — worse than the old immediate 307 on expired URL.
  Future<void> _openStrmPlayback(
    String embyStreamUrl, {
    Future<String>? cdnUrlFuture,
  }) async {
    final emby = _emby;
    if (emby == null) return;
    const picked = null;
    if (!mounted || _bootstrapCancelled) return;
    final openUrl = picked ?? embyStreamUrl;
    const mode = picked != null ? 'cdn_direct' : 'emby_307';
    final headers = externalCdnPlaybackHttpHeaders();

    AppLog.instance.i(
      'Player',
      'strm playback: mode=$mode openUrl=${AppLog.redactUrl(openUrl)} '
      'headers=${headers.keys.toList()}',
    );
    await _openStream(
      openUrl,
      headers: headers,
      externalCdn: true,
      tuneProbe: false,
    );
  }

  Future<void> _openStream(
    String url, {
    Map<String, String>? headers,
    bool externalCdn = false,
    bool tuneProbe = false,
  }) async {
    AppLog.instance.i(
      'Player',
      '_openStream: url=${AppLog.redactUrl(url)} externalCdn=$externalCdn headers=${headers?.keys.toList()}',
    );
    if (externalCdn) {
      await _player.applyExternalCdnPlaybackOptions(headers: headers);
    } else {
      await _player.applyExternalCdnPlaybackOptions(headers: null);
    }
    await _player.applyAndroidPlaybackOutput();
    await _player.applyStreamProbeTuning(enabled: tuneProbe);
    if (!externalCdn) {
      await _player.applyPlaybackHttpHeaders(headers);
    }
    await _player.applyStreamCacheOptions(enabled: true);
    await _player.open(Media(url, httpHeaders: headers));
  }

  Future<void> _syncDesktopFullscreenFlag() {
    if (!_canDesktopFullscreen) return Future<void>.value();
    return _enqueueFullscreenWork(() async {
      final v = await desktopIsFullScreen();
      if (mounted) setState(() => _desktopFullscreen = v);
    });
  }

  /// Let Material ink / overlay finish before native window mode changes (reduces Windows stalls).
  Future<void> _beforeNativeFullscreen() async {
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;
  }

  /// After `setFullScreen`, give the compositor + Flutter a couple of frames before `setState`.
  Future<void> _afterFullscreenNativeTransition() async {
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;
    if (defaultTargetPlatform == TargetPlatform.windows) {
      // DWM / ANGLE occasionally need a beat after exclusive-style resize; keeps UI responsive.
      await Future<void>.delayed(const Duration(milliseconds: 32));
    }
  }

  /// Runs [work] after any prior fullscreen operation; keeps the chain alive on errors.
  Future<void> _enqueueFullscreenWork(Future<void> Function() work) {
    final done = Completer<void>();
    _fullscreenOpChain = _fullscreenOpChain.then((_) async {
      try {
        await work();
      } catch (_) {
        // Swallow so the queue never stalls; UI state is re-synced from the system when needed.
      } finally {
        if (!done.isCompleted) done.complete();
      }
    });
    return done.future;
  }

  void _scheduleChromeHide() {
    _chromeIdleTimer?.cancel();
    if (!_showChrome) return;
    _chromeIdleTimer = Timer(_chromeHideDelay, () {
      if (mounted) setState(() => _showChrome = false);
    });
  }

  /// Mouse move / control use: show bar and reset idle timer.
  void _onUserInteraction() {
    if (!mounted) return;
    if (!_showChrome) {
      setState(() => _showChrome = true);
    }
    _scheduleChromeHide();
  }

  void _onVideoTap() {
    setState(() {
      _showChrome = !_showChrome;
    });
    if (_showChrome) {
      _scheduleChromeHide();
    } else {
      _chromeIdleTimer?.cancel();
    }
  }

  /// 方向键按下：累加偏移，不启动定时器（由 KeyUpEvent 决定是否延迟提交）。
  void _onArrowDown(int direction, int step) {
    _arrowSeekDelayTimer?.cancel();
    _arrowHoldStart = DateTime.now();
    _arrowHoldDirection = direction;
    _arrowSeekBasePos ??= _player.state.position;
    _arrowAccumulatedSeconds += step * direction;
    _onUserInteraction();
    setState(() {});
  }

  /// 仅更新快进/快退预览偏移（不 seek），由 [KeyRepeatEvent] 调用。
  void _updateSeekPreview() {
    final start = _arrowHoldStart;
    if (start == null || _arrowHoldDirection == 0) return;
    final held = DateTime.now().difference(start);
    _arrowAccumulatedSeconds +=
        _seekStepForDuration(held) * _arrowHoldDirection;
    _onUserInteraction();
    setState(() {});
  }

  /// 提交实际 seek 并复位所有状态。
  void _commitSeek() {
    _arrowSeekDelayTimer?.cancel();
    final base = _arrowSeekBasePos;
    final dur = _player.state.duration;
    if (base != null && _arrowAccumulatedSeconds != 0 && dur > Duration.zero) {
      var target = base + Duration(seconds: _arrowAccumulatedSeconds);
      if (target < Duration.zero) target = Duration.zero;
      if (target > dur) target = dur;
      _player.seek(target);
      _lastSeekAt = DateTime.now();
    }
    _arrowHoldStart = null;
    _arrowHoldDirection = 0;
    _arrowAccumulatedSeconds = 0;
    _arrowSeekBasePos = null;
    _onUserInteraction();
    setState(() {});
  }

  static int _seekStepForDuration(Duration held) {
    final ms = held.inMilliseconds;
    if (ms < 500) return 1;
    if (ms < 1000) return 5;
    if (ms < 2000) return 15;
    if (ms < 4000) return 30;
    if (ms < 7000) return 60;
    if (ms < 12000) return 150;
    return 300;
  }

  /// 键盘调节音量（delta 为百分比增量，范围 0-100）。
  void _adjustVolume(double delta) {
    final vol = _player.state.volume;
    _player.setVolume((vol + delta).clamp(0, 100));
    _volumeShowToken.value++;
  }

  /// 键盘切换静音（通过将音量设为 0 / 恢复来实现）。
  void _toggleMute() {
    final vol = _player.state.volume;
    if (vol <= 0.001) {
      _player.setVolume((_preMuteVolume ?? 50).clamp(1, 100));
      _preMuteVolume = null;
    } else {
      _preMuteVolume = vol;
      _player.setVolume(0);
    }
    _volumeShowToken.value++;
  }

  Future<void> _toggleFullscreen() {
    if (!_canDesktopFullscreen) return Future<void>.value();
    return _enqueueFullscreenWork(() async {
      await _beforeNativeFullscreen();
      final cur = await desktopIsFullScreen();
      await desktopSetFullScreen(!cur);
      await _afterFullscreenNativeTransition();
      if (!mounted) return;
      final actual = await desktopIsFullScreen();
      if (mounted) setState(() => _desktopFullscreen = actual);
      _onUserInteraction();
    });
  }

  Future<void> _handleEscape() {
    if (!_canDesktopFullscreen) {
      _leavePlayer();
      return Future<void>.value();
    }
    return _enqueueFullscreenWork(() async {
      final fs = await desktopIsFullScreen();
      if (fs) {
        await _beforeNativeFullscreen();
        await desktopSetFullScreen(false);
        await _afterFullscreenNativeTransition();
        if (!mounted) return;
        final actual = await desktopIsFullScreen();
        if (mounted) setState(() => _desktopFullscreen = actual);
        _onUserInteraction();
        return;
      }
      _leavePlayer();
    });
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
    final pos = _player.state.position;
    final ticks = (pos.inMicroseconds * 10).clamp(0, 1 << 62).toInt();
    if (_playbackReportedStopped) return;
    await emby.reportProgress(
      itemId: widget.itemId,
      mediaSourceId: i.mediaSourceId,
      playSessionId: i.playSessionId,
      positionTicks: ticks,
      isPaused: !_player.state.playing,
    );
    _lastReportedPositionTicks = ticks;
    _maybeRecordPlayHistory(ticks, i.runTimeTicks);
  }

  void _cancelProgressReporting() {
    _progressTimer?.cancel();
    _progressTimer = null;
  }

  int? _playbackExitPositionTicks() =>
      _capturePlaybackPositionTicks() ?? _lastReportedPositionTicks;

  /// Waits for any in-flight Progress, then reports Stopped (Progress must not
  /// arrive at Emby after Stopped).
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

  void _maybeRecordPlayHistory(int positionTicks, int? runTimeTicks) {
    if (runTimeTicks == null || runTimeTicks <= 0) return;
    if (positionTicks < runTimeTicks * 0.05) return;
    final item = _currentItem;
    if (item == null) return;
    try {
      final history = ref.read(playHistoryServiceProvider);
      unawaited(history.recordPlay(
        itemId: item.id,
        type: item.type,
        seriesId: item.seriesId,
      ));
    } catch (_) {}
  }

  /// 当视频播放完毕后用户回看（seek back），需要重新上报 PlaybackStarted
  /// 并重启进度定时器，以便 Emby 服务器跟踪新的播放会话。
  void _onSeekAfterPlaybackStopped() {
    if (!_playbackReportedStopped) return;
    final i = _info;
    final emby = _emby;
    if (i == null || emby == null) return;
    _playbackReportedStopped = false;
    final pos = _player.state.position;
    final ticks = (pos.inMicroseconds * 10).clamp(0, 1 << 62).toInt();
    unawaited(emby.reportPlaybackStarted(
      itemId: widget.itemId,
      mediaSourceId: i.mediaSourceId,
      playSessionId: i.playSessionId,
      positionTicks: ticks,
    ));
    _progressTimer ??= Timer.periodic(
        const Duration(seconds: 10), (_) => unawaited(_reportProgress()));
  }

  Future<void> _stopPlayerForExit() async {
    try {
      await _player.pause();
    } catch (_) {}
    try {
      await _player.stop();
    } catch (_) {}
  }

  /// Leave the player immediately; await in-flight Progress before Stopped.
  void _leavePlayer() {
    if (_leavingPlayer) return;
    _leavingPlayer = true;
    _cancelNetworkRecovery();
    _cancelBootstrapInProgress(firstFrameVia: 'leave_player');
    _nextEpCountdownTimer?.cancel();
    final exitTicks = _playbackExitPositionTicks();
    unawaited(() async {
      await _reportStoppedIfNeeded(positionTicks: exitTicks);
      await _stopPlayerForExit();
    }());
    final container = _riverpodContainer;
    if (container != null) schedulePlayerHomeDataRefresh(container);
    if (mounted && context.canPop()) context.pop();
  }

  /// Fetch episode list for episode navigation controls (上一集/下一集/选集).
  Future<void> _fetchEpisodes() async {
    final item = _currentItem;
    if (item == null) return;
    final seasonId = item.seasonId;
    if (seasonId == null) return;
    final emby = _emby;
    if (emby == null) return;

    try {
      final episodes = await emby.getEpisodes(seasonId);
      if (!mounted) return;
      final sorted = sortEpisodesByIndex(episodes);
      final adj = adjacentEpisodesInSeason(sorted, widget.itemId);
      setState(() {
        _episodes = sorted;
        _hasPrevEpisode = adj.previous != null;
        _hasNextEpisode = adj.next != null;
      });
      // Pre-warm Riverpod providers so the episode panel loads instantly.
      final seriesId = item.seriesId;
      if (seriesId != null && mounted) {
        unawaited(ref.read(embySeasonsProvider(seriesId).future));
        unawaited(ref.read(embyEpisodesProvider(seasonId).future));
      }
    } catch (_) {
      // Best-effort — leave buttons hidden.
    }
  }

  void _toggleEpisodeList() {
    final opening = !_episodeListOpenNotifier.value;
    _episodeListOpenNotifier.value = opening;
    if (opening) {
      _chromeIdleTimer?.cancel();
      if (mounted && _showChrome) {
        setState(() => _showChrome = false);
      }
    }
  }

  void _closeEpisodeList() {
    if (_episodeListOpenNotifier.value) {
      _episodeListOpenNotifier.value = false;
    }
  }

  void _markAndroidLandscapePreserveForEpisodeSwitch() {
    if (isAndroidMobileUi && _androidLandscape) {
      _preserveAndroidLandscapeOnNextOpen = true;
    }
  }

  Widget _buildEpisodeListOverlay() {
    final item = _currentItem;
    if (item?.seasonId == null) return const SizedBox.shrink();

    return ValueListenableBuilder<bool>(
      valueListenable: _episodeListOpenNotifier,
      builder: (context, episodeListOpen, _) {
        void selectEpisode(String id) {
          _closeEpisodeList();
          _onSelectEpisode(id);
        }

        if (isAndroidMobileUi) {
          return _buildAndroidEpisodeSheet(
            item: item!,
            open: episodeListOpen,
            onSelectEpisode: selectEpisode,
          );
        }

        if (!episodeListOpen) return const SizedBox.shrink();

        return Positioned(
          top: 0,
          left: 0,
          right: 0,
          bottom: 100,
          child: PlayerEpisodePanel(
            episode: item!,
            playingEpisodeId: widget.itemId,
            onClose: _toggleEpisodeList,
            onSelectEpisode: selectEpisode,
          ),
        );
      },
    );
  }

  /// Centered large sheet on Android (portrait + landscape).
  /// Panel stays mounted while closed ([Offstage]) so providers stay warm.
  Widget _buildAndroidEpisodeSheet({
    required EmbyMediaItem item,
    required bool open,
    required void Function(String id) onSelectEpisode,
  }) {
    final padding = MediaQuery.paddingOf(context);
    final size = MediaQuery.sizeOf(context);
    final panelW = (size.width * 0.72).clamp(300.0, 400.0);
    // Use nearly full viewport height in landscape — vertical space is precious.
    final panelH = size.height - padding.top - padding.bottom - 24;

    final panel = RepaintBoundary(
      child: PlayerEpisodePanel(
        episode: item,
        playingEpisodeId: widget.itemId,
        mobileLayout: true,
        centeredSheet: true,
        onClose: _toggleEpisodeList,
        onSelectEpisode: onSelectEpisode,
      ),
    );

    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !open,
        child: Stack(
          children: [
            Positioned.fill(
              child: AnimatedOpacity(
                opacity: open ? 1 : 0,
                duration: const Duration(milliseconds: 120),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggleEpisodeList,
                  child: const ColoredBox(color: Color(0x66000000)),
                ),
              ),
            ),
            Offstage(
              offstage: !open,
              child: Center(
                child: SizedBox(
                  width: panelW,
                  height: panelH,
                  child: panel,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _seekRelative(int seconds) {
    _gestureSeekPreview.value = 0;
    _lastSeekAt = DateTime.now();
    _onSeekAfterPlaybackStopped();
    final cur = _player.state.position;
    final dur = _player.state.duration;
    var next = cur + Duration(seconds: seconds);
    if (next < Duration.zero) next = Duration.zero;
    if (next > dur) next = dur;
    _player.seek(next);
  }

  void _adjustVolumeDelta(double delta) {
    final next = (_player.state.volume + delta).clamp(0.0, 100.0);
    _player.setVolume(next);
    _volumeShowToken.value++;
  }

  /// Toggle between portrait and landscape on Android.
  /// Landscape: auto-rotate enabled (sensorLandscape), bars hidden.
  /// Portrait: locked to portraitUp.
  Future<void> _toggleAndroidOrientation() async {
    if (_orientationChangeInProgress) return;
    _orientationChangeInProgress = true;
    final targetLandscape = !_androidLandscape;
    setState(() => _androidLandscape = targetLandscape);
    if (targetLandscape) {
      // Enter landscape: enable auto-rotation for smooth sensor-based transition
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      // Return to portrait
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    // Allow the orientation animation to settle
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (mounted) {
      _orientationChangeInProgress = false;
      _onUserInteraction();
    }
  }

  /// Handle system back button: close overlays, exit landscape, then leave player.
  Future<bool> _onAndroidPopInvoked() async {
    if (_episodeListOpenNotifier.value) {
      _closeEpisodeList();
      return false;
    }
    if (_androidLandscape) {
      await _toggleAndroidOrientation();
      return false;
    }
    _leavePlayer();
    return true;
  }

  VoidCallback? get _fullScreenToggle => _canDesktopFullscreen
      ? () => unawaited(_toggleFullscreen())
      : (isAndroidMobileUi
          ? () => unawaited(_toggleAndroidOrientation())
          : null);

  bool get _isFullScreenUi =>
      _canDesktopFullscreen ? _desktopFullscreen : _androidLandscape;

  BoxFit _videoFitForViewport(BuildContext context) => BoxFit.contain;

  void _onSelectEpisode(String episodeId) {
    _markAndroidLandscapePreserveForEpisodeSwitch();
    _closeEpisodeList();
    final exitTicks = _playbackExitPositionTicks();
    unawaited(_reportStoppedIfNeeded(positionTicks: exitTicks));
    _episodeSwitching = true;
    final route = playerRouteForItem(episodeId);
    if (mounted) context.replace(route);
  }

  void _goToAdjacentEpisode({bool next = true}) {
    final item = _currentItem;
    final episodes = _episodes;
    if (item == null || episodes == null || episodes.isEmpty) return;
    final sorted = episodes;
    final adj = adjacentEpisodesInSeason(sorted, widget.itemId);
    final target = next ? adj.next : adj.previous;
    if (target == null) return;
    _onSelectEpisode(target.id);
  }

  /// Auto-play next episode when current playback reaches the end.
  Future<void> _onPlaybackCompleted() async {
    if (!_bootstrapped || _loading) return;
    // Guard: suppress false positives — mpv may fire "completed" spuriously
    // during seek operations. Require a 3 s cooldown after the last seek.
    if (DateTime.now().difference(_lastSeekAt).inSeconds < 3) return;

    final pos = _player.state.position;
    final dur = _player.state.duration;
    if (!isPlaybackNearEnd(pos, dur)) return;

    final item = _currentItem;
    if (item == null) return;

    // 视频播放完毕，等待在途 Progress 后上报 PlaybackStopped。
    if (!_playbackReportedStopped) {
      final ticks = (pos.inMicroseconds * 10).clamp(0, 1 << 62).toInt();
      await _reportStoppedIfNeeded(positionTicks: ticks);
    }

    final settings = ref.read(settingsServiceProvider);
    if (!settings.autoPlayNext) return;

    final seasonId = item.seasonId;
    final seriesId = item.seriesId;
    if (seasonId == null || seriesId == null) return;

    if (!mounted) return;

    // Use cached episode list if available, otherwise fetch.
    List<EmbyMediaItem> episodes = _episodes ?? [];
    if (episodes.isEmpty) {
      final emby = _emby;
      if (emby == null) return;
      try {
        episodes = await emby.getEpisodes(seasonId);
      } catch (_) {
        return;
      }
    }
    final sorted = sortEpisodesByIndex(episodes);
    final adj = adjacentEpisodesInSeason(sorted, widget.itemId);
    if (adj.next == null) return;

    if (!mounted) return;
    setState(() {
      _nextEpisode = adj.next;
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
    // GoRouter handles the old screen disposal automatically.
    if (mounted) {
      // 使用 replace 而非 go，避免在路由栈中累积多个播放器页面。
      context.replace(route);
    }
  }

  @override
  void dispose() {
    _cancelNetworkRecovery();
    _cancelAndroidResumeGuard?.call();
    _cancelAndroidResumeGuard = null;
    _playerErrorSub?.cancel();
    _diagTrackSub?.cancel();
    _diagTrackSub = null;
    _diagTracksSub?.cancel();
    _diagTracksSub = null;
    _progressTimer?.cancel();
    _chromeIdleTimer?.cancel();
    _completedSub?.cancel();
    _bootstrapTimeoutTimer?.cancel();
    _bootstrapTimeoutTimer = null;
    _firstFrameWatch?.cancel();
    _firstFrameWatch = null;
    _trySettleFirstFrame = null;
    _videoParamsFirstFrameSub?.cancel();
    _videoParamsFirstFrameSub = null;
    if (!_firstFramePerfDone) {
      _firstFramePerfSpan?.end(extraContext: {'first_frame_via': 'disposed'});
      _firstFramePerfSpan = null;
      _firstFramePerfDone = true;
    }
    // If the player was torn down before the first frame ever fired, close the
    // span so the bootstrap isn't lost from the diagnostics ring buffer.
    if (!_firstFrameReported) {
      _bootstrapSpan?.end(extraContext: {'first_frame_via': 'disposed'});
      _bootstrapSpan = null;
      _firstFrameReported = true;
    }
    _nextEpCountdownTimer?.cancel();
    _arrowSeekDelayTimer?.cancel();
    if (!_leavingPlayer && !_episodeSwitching) {
      unawaited(_reportStoppedIfNeeded());
    }
    if (!_leavingPlayer) {
      unawaited(_stopPlayerForExit());
    }
    unawaited(_player.applyExternalCdnPlaybackOptions(headers: null));
    unawaited(_player.applyPlaybackHttpHeaders(null));
    final container = _riverpodContainer;
    if (container != null) {
      try {
        container.read(playerServiceProvider).disposePlayerIfCurrent(_player);
      } catch (_) {}
    }
    _volumeShowToken.dispose();
    _gestureSeekPreview.dispose();
    _episodeListOpenNotifier.dispose();
    if (_canDesktopFullscreen && !_episodeSwitching) {
      _fullscreenOpChain = _fullscreenOpChain.then((_) async {
        try {
          await desktopSetFullScreen(false);
        } catch (_) {}
      });
    }
    if (isAndroidMobileUi && !_episodeSwitching) {
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
      unawaited(
          SystemChrome.setPreferredOrientations(DeviceOrientation.values));
      unawaited(_restoreScreenBrightness());
    }
    super.dispose();
  }

  /// Restore system brightness when leaving the player (gesture may have changed it).
  Future<void> _restoreScreenBrightness() async {
    try {
      await ScreenBrightness().resetApplicationScreenBrightness();
    } catch (_) {
      // Best-effort — some devices reject brightness reset.
    }
  }

  /// `00:00:51` 格式 (HH:MM:SS)。
  static String _fmtHms(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  /// 键盘 seek 预览 OSD：居中显示目标位置、方向图标和进度条。
  Widget _buildSeekOsd() {
    final base = _arrowSeekBasePos ?? const Duration();
    final dur = _player.state.duration;
    if (dur <= Duration.zero) return const SizedBox.shrink();
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
                        fontFeatures: [FontFeature.tabularFigures()],
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
                    fontFeatures: [FontFeature.tabularFigures()],
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
                          gradient: const LinearGradient(
                            colors: [Color(0xFF64B5F6), Color(0xFF42A5F5)],
                          ),
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
                    fontFeatures: [FontFeature.tabularFigures()],
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

  @override
  Widget build(BuildContext context) {
    // Sync landscape state with actual device orientation (phone/tablet only).
    if (isAndroidMobileUi) {
      final isLandscape =
          MediaQuery.of(context).orientation == Orientation.landscape;
      if (_androidLandscape != isLandscape && !_orientationChangeInProgress) {
        // Orientation changed externally (e.g. device physically rotated if other orientations allowed)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _androidLandscape = isLandscape);
        });
      }
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
          onRetry: () => unawaited(_retryPlayback()),
        ),
      );
    }

    if (_controller == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: LoadingIndicator(
          message: _reconnecting ? '正在重连…' : '正在准备播放…',
        ),
      );
    }

    return TvRemoteActions(
      onBack: _leavePlayer,
      onPlayPause: () {
        if (_player.state.playing) {
          _player.pause();
        } else {
          _player.play();
        }
        _onUserInteraction();
      },
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
        if (!didPop) {
          if (isAndroidMobileUi) {
            unawaited(_onAndroidPopInvoked());
          } else {
            _leavePlayer();
          }
        }
      },
      child: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          // 方向键抬起
          if (event is KeyUpEvent) {
            if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
                event.logicalKey == LogicalKeyboardKey.arrowRight) {
              _arrowHoldStart = null;
              if (_arrowIsLongPress) {
                // 长按结束 → 立即提交 seek
                _commitSeek();
              } else {
                // 短按抬起 → 启动 500ms 延迟定时器（期间再次短按会重置）
                _arrowSeekDelayTimer?.cancel();
                _arrowSeekDelayTimer =
                    Timer(const Duration(milliseconds: 500), () {
                  _commitSeek();
                });
              }
              _arrowIsLongPress = false;
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          }
          // 长按左右方向键 → 取消延迟定时器，仅更新预览
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
          if (event.logicalKey == LogicalKeyboardKey.space) {
            if (_player.state.playing) {
              _player.pause();
            } else {
              _player.play();
            }
            _onUserInteraction();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            unawaited(_handleEscape());
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.keyF) {
            if (_canDesktopFullscreen) {
              unawaited(_toggleFullscreen());
            }
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            _arrowIsLongPress = false;
            _onArrowDown(-1, 10);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            _arrowIsLongPress = false;
            _onArrowDown(1, 10);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            _adjustVolume(5);
            _onUserInteraction();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            _adjustVolume(-5);
            _onUserInteraction();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.keyM) {
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
              final hidePointerCursor =
                  context.inputModality == InputModality.pointer &&
                      !_showChrome &&
                      !episodeListOpen;
              return MouseRegion(
                cursor: hidePointerCursor
                    ? SystemMouseCursors.none
                    : MouseCursor.defer,
                onHover: (_) => _onUserInteraction(),
                child: Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: RepaintBoundary(
                    child: PlayerGestureLayer(
                      player: _player,
                      onTap: _onVideoTap,
                      onSeekRelative: isAndroidMobileUi ? _seekRelative : null,
                      onSeekPreview: isAndroidMobileUi
                          ? (delta) => _gestureSeekPreview.value = delta
                          : null,
                      onVolumeDelta:
                          isAndroidMobileUi ? _adjustVolumeDelta : null,
                      onUserInteraction: _onUserInteraction,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: isAndroidMobileUi ? null : _onVideoTap,
                        child: StreamBuilder<Track>(
                          stream: _player.stream.track,
                          initialData: _player.state.track,
                          builder: (context, trackSnap) {
                            final sub =
                                trackSnap.data?.subtitle ?? SubtitleTrack.no();
                            final overlay =
                                shouldUseFlutterSubtitleOverlay(sub);
                            final fit = _videoFitForViewport(context);
                            return LayoutBuilder(
                              builder: (context, constraints) {
                                final width = constraints.maxWidth;
                                final height = constraints.maxHeight;
                                // Stable key — recreating [Video] on resize breaks
                                // Android Surface attach on emulators.
                                final viewportKey = isAndroidMobileUi
                                    ? ValueKey<Object>(
                                        'android-video-${widget.itemId}',
                                      )
                                    : null;
                                return Video(
                                  key: viewportKey,
                                  controller: _controller!,
                                  width: width,
                                  height: height,
                                  fit: fit,
                                  controls: NoVideoControls,
                                  subtitleViewConfiguration:
                                      PlayerSubtitleStyle.configuration(
                                    fontSize: ref
                                        .watch(settingsServiceProvider)
                                        .subtitleFontSize,
                                    visible: overlay,
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ),
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
                if (_arrowSeekActive) _buildSeekOsd(),
                if (_showNextEp && _nextEpisode != null && !_loading)
                  _buildNextEpisodeOverlay(),
                ValueListenableBuilder<bool>(
                  valueListenable: _episodeListOpenNotifier,
                  builder: (context, episodeListOpen, _) {
                    if (!_showChrome || episodeListOpen || _loading) {
                      return const SizedBox.shrink();
                    }
                    return PlayerTopInfo(
                      title: _currentItem?.name ?? '',
                      onBack: _leavePlayer,
                    );
                  },
                ),
                // Hide bottom controls while the loading overlay is up — otherwise
                // the progress bar would render `_player.state.position` flipping
                // through 0 → seek(0) → resumeAt during the widListener bounce,
                // even though the video underneath is masked by the loading scrim.
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
                      child: ValueListenableBuilder<bool>(
                        valueListenable: _episodeListOpenNotifier,
                        builder: (context, episodeListOpenInner, _) {
                          return PlayerControls(
                            player: _player,
                            itemId: widget.itemId,
                            embySubtitles: _info?.subtitles ?? const [],
                            onUserInteraction: _onUserInteraction,
                            onSeek: () {
                              _lastSeekAt = DateTime.now();
                              _gestureSeekPreview.value = 0;
                              _onSeekAfterPlaybackStopped();
                            },
                            volumeShowToken: _volumeShowToken,
                            gestureSeekPreviewSeconds:
                                isAndroidMobileUi ? _gestureSeekPreview : null,
                            // 触屏（手机/平板）用紧凑布局；指针（桌面）与遥控（TV）用完整布局。
                            compact:
                                context.inputModality == InputModality.touch,
                            isFullScreen: _isFullScreenUi,
                            onToggleFullScreen: _fullScreenToggle,
                            showEpisodeControls: _currentItem?.seasonId != null,
                            hasPreviousEpisode: _hasPrevEpisode,
                            hasNextEpisode: _hasNextEpisode,
                            episodeListOpen: episodeListOpenInner,
                            onPreviousEpisode: _hasPrevEpisode
                                ? () => _goToAdjacentEpisode(next: false)
                                : null,
                            onNextEpisode: _hasNextEpisode
                                ? () => _goToAdjacentEpisode(next: true)
                                : null,
                            onToggleEpisodeList: _currentItem?.seasonId != null
                                ? _toggleEpisodeList
                                : null,
                          );
                        },
                      ),
                    );
                  },
                ),
                _buildEpisodeListOverlay(),
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
}
