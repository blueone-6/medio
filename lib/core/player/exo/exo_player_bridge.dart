import 'dart:async';

import 'package:flutter/services.dart';

import '../../logging/app_log.dart';
import 'video_fit_mode.dart';

/// Playback state pushed from the native ExoPlayer bridge (Android phone).
///
/// [volume] uses the mpv-style 0–100 scale so the shared gesture layer's
/// baseline math works unchanged.
class ExoPlayerBridgeState {
  const ExoPlayerBridgeState({
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.bufferedPosition = Duration.zero,
    this.isPlaying = false,
    this.isBuffering = false,
    this.volume = 100,
    this.videoWidth = 0,
    this.videoHeight = 0,
    this.speed = 1.0,
  });

  final Duration position;
  final Duration duration;

  /// How far ahead the buffered range reaches — shown while stall-buffering so
  /// a slow network is distinguishable from a dead stream.
  final Duration bufferedPosition;
  final bool isPlaying;
  final bool isBuffering;
  final double volume;
  final int videoWidth;
  final int videoHeight;
  final double speed;

  double get videoAspect =>
      videoWidth > 0 && videoHeight > 0 ? videoWidth / videoHeight : 0;

  ExoPlayerBridgeState copyWith({
    Duration? position,
    Duration? duration,
    Duration? bufferedPosition,
    bool? isPlaying,
    bool? isBuffering,
    double? volume,
    int? videoWidth,
    int? videoHeight,
    double? speed,
  }) {
    return ExoPlayerBridgeState(
      position: position ?? this.position,
      duration: duration ?? this.duration,
      bufferedPosition: bufferedPosition ?? this.bufferedPosition,
      isPlaying: isPlaying ?? this.isPlaying,
      isBuffering: isBuffering ?? this.isBuffering,
      volume: volume ?? this.volume,
      videoWidth: videoWidth ?? this.videoWidth,
      videoHeight: videoHeight ?? this.videoHeight,
      speed: speed ?? this.speed,
    );
  }
}

/// App-lifetime listener on the shared native ExoPlayer event channel.
///
/// The native player is a singleton, so the Dart subscription must outlive
/// individual player screens. `EventChannel.cancel()` also removes the
/// channel's *shared* message handler, and on an episode switch the next screen
/// subscribes before the previous screen disposes — the old cancel used to tear
/// that handler down and silently kill every later "ready"/position event
/// (stuck "正在准备播放" overlay until its timeout, frozen subtitles).
class _ExoEventPump {
  _ExoEventPump._();

  static final _ExoEventPump instance = _ExoEventPump._();

  static const _events = EventChannel('media_client/tv_exo_player_events');

  final state = StreamController<ExoPlayerBridgeState>.broadcast();
  final error = StreamController<String>.broadcast();
  final completed = StreamController<void>.broadcast();
  final ready = StreamController<ExoPlayerBridgeState>.broadcast();

  /// Last state seen, so a screen that subscribes mid-playback is not blank.
  ExoPlayerBridgeState latest = const ExoPlayerBridgeState();

  StreamSubscription<dynamic>? _sub;

  /// Attaches once per app run; later screens reuse the same subscription.
  void attach(int sessionId) {
    _sub ??= _events.receiveBroadcastStream({'sessionId': sessionId}).listen(
          _dispatch,
          onError: (Object e) {
            AppLog.instance.e('ExoPlayer', 'event channel error: $e');
          },
        );
  }

  void _dispatch(dynamic raw) {
    if (raw is! Map) return;
    final event = raw['event']?.toString() ?? '';
    switch (event) {
      case 'position':
        latest = latest.copyWith(
          position: Duration(milliseconds: _readMs(raw['positionMs'])),
          duration: Duration(milliseconds: _readMs(raw['durationMs'])),
          bufferedPosition:
              Duration(milliseconds: _readMs(raw['bufferedPositionMs'])),
          isPlaying: raw['isPlaying'] == true,
          isBuffering: raw['isBuffering'] == true,
          videoWidth: _readInt(raw['videoWidth']),
          videoHeight: _readInt(raw['videoHeight']),
          speed: _readDouble(raw['speed']),
        );
        state.add(latest);
      case 'error':
        error.add(raw['message']?.toString() ?? 'playback error');
      case 'completed':
        completed.add(null);
      case 'ready':
        final readyState = latest.copyWith(
          position: Duration(milliseconds: _readMs(raw['positionMs'])),
          videoWidth: _readInt(raw['videoWidth']),
          videoHeight: _readInt(raw['videoHeight']),
        );
        latest = readyState;
        state.add(latest);
        ready.add(readyState);
      default:
        break;
    }
  }

  static int _readMs(Object? v) => (v is num) ? v.toInt() : 0;
  static int _readInt(Object? v) => (v is num) ? v.toInt() : 0;
  static double _readDouble(Object? v) => (v is num) ? v.toDouble() : 1.0;
}

/// Dart bridge to the shared native ExoPlayer (Media3) plugin.
///
/// Reuses the `media_client/tv_exo_player` channels — only one player screen
/// is ever active per device (TV screen on TVs, this one on phones), and the
/// native side is a single bridge instance.
class ExoPlayerBridge {
  ExoPlayerBridge() : sessionId = ++_sessionSeq {
    startListening();
  }

  static const _method = MethodChannel('media_client/tv_exo_player');

  static final _pump = _ExoEventPump.instance;

  static int _sessionSeq = 0;

  /// Unique id of this screen's playback session.
  ///
  /// The native bridge is a singleton: on an episode switch the new platform
  /// view is created before the previous screen's `dispose()` reaches native
  /// code. Sending our id with `setSource`/`stop`/`dispose` lets native ignore
  /// the stale teardown instead of detaching the *new* player from its surface
  /// (which showed up as "audio plays, picture stays black").
  final int sessionId;

  Stream<ExoPlayerBridgeState> get stateStream => _pump.state.stream;
  Stream<String> get errorStream => _pump.error.stream;
  Stream<void> get completedStream => _pump.completed.stream;
  Stream<ExoPlayerBridgeState> get readyStream => _pump.ready.stream;

  ExoPlayerBridgeState get state => _pump.latest;

  void startListening() => _pump.attach(sessionId);

  Future<void> setSource({
    required String url,
    Map<String, String>? headers,
    Duration startPosition = Duration.zero,
    bool isHdrContent = false,
    String? videoRange,
    Duration positionEventInterval = const Duration(milliseconds: 250),
    bool handleAudioFocus = true,
    bool customSubtitleRendering = true,
  }) async {
    // New session: drop the previous episode's position/video size.
    _pump.latest = ExoPlayerBridgeState(volume: _pump.latest.volume);
    AppLog.instance.i(
      'ExoPlayer',
      'setSource url=${AppLog.redactUrl(url)} start=${startPosition.inSeconds}s '
          'hdr=$isHdrContent range=$videoRange',
    );
    await _method.invokeMethod<void>('setSource', {
      'url': url,
      'headers': headers,
      'startPositionMs': startPosition.inMilliseconds,
      'subtitleUrl': null,
      'subtitleMime': null,
      'isHdrContent': isHdrContent,
      'videoRange': videoRange,
      'positionEventIntervalMs': positionEventInterval.inMilliseconds,
      'handleAudioFocus': handleAudioFocus,
      'customSubtitleRendering': customSubtitleRendering,
      'sessionId': sessionId,
    });
  }

  Future<void> play() => _method.invokeMethod<void>('play');

  Future<void> pause() => _method.invokeMethod<void>('pause');

  Future<void> seekTo(Duration position) => _method.invokeMethod<void>(
        'seekTo',
        {'positionMs': position.inMilliseconds},
      );

  Future<void> setPlaybackSpeed(double speed) =>
      _method.invokeMethod<void>('setPlaybackSpeed', {'speed': speed});

  /// [volume] is on the 0–100 scale (mpv parity); native expects 0..1.
  Future<void> setVolume(double volume) async {
    _pump.latest = _pump.latest.copyWith(volume: volume.clamp(0.0, 100.0));
    _pump.state.add(_pump.latest);
    await _method.invokeMethod<void>('setVolume', {
      'volume': (volume.clamp(0.0, 100.0) / 100.0),
    });
  }

  Future<void> setMuted(bool muted) =>
      _method.invokeMethod<void>('setMuted', {'muted': muted});

  /// Subtitle delay for muxed (native-rendered) text tracks, ms ≥ 0.
  Future<void> setSubtitleDelayMs(int delayMs) =>
      _method.invokeMethod<void>('setSubtitleDelayMs', {'delayMs': delayMs});

  /// Scales native (muxed) subtitle text; 1.0 = the authored default (42).
  Future<void> setSubtitleFontScale(double scale) =>
      _method.invokeMethod<void>('setSubtitleFontScale', {'scale': scale});

  /// Video scaling mode (`AspectRatioFrameLayout.RESIZE_MODE_*` via
  /// [VideoFitMode.nativeValue]). Stored natively, so it survives a
  /// PlayerView re-attach (episode switch / orientation change).
  Future<void> setVideoFitMode(VideoFitMode mode) =>
      _method.invokeMethod<void>('setResizeMode', {'mode': mode.nativeValue});

  /// Polls the native track lists (audio + text) of the prepared item.
  Future<Map<Object?, Object?>?> getTracksRaw() =>
      _method.invokeMapMethod<String, dynamic>('getTracks');

  Future<void> selectAudioTrack(String? id) =>
      _method.invokeMethod<void>('selectAudioTrack', {'id': id});

  Future<void> selectTextTrack(String? id) =>
      _method.invokeMethod<void>('selectTextTrack', {'id': id});

  Future<void> stop() =>
      _method.invokeMethod<void>('stop', {'sessionId': sessionId});

  Future<void> dispose() async {
    // The shared event pump deliberately outlives this screen: cancelling an
    // `EventChannel` stream also drops the channel's shared Dart message
    // handler, which is what killed the *next* episode's ready/position events.
    try {
      await _method.invokeMethod<void>('dispose', {'sessionId': sessionId});
    } catch (_) {}
  }
}
