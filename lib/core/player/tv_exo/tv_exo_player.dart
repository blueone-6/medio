import 'dart:async';

import 'package:flutter/services.dart';

import '../../logging/app_log.dart';
import '../../../models/emby/emby_subtitle_option.dart';

/// Playback state pushed from native ExoPlayer (Android TV).
class TvExoPlayerState {
  const TvExoPlayerState({
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.bufferedPosition = Duration.zero,
    this.isPlaying = false,
    this.isBuffering = false,
  });

  final Duration position;
  final Duration duration;

  /// How far ahead the buffered range reaches — shown while stall-buffering.
  final Duration bufferedPosition;
  final bool isPlaying;
  final bool isBuffering;

  TvExoPlayerState copyWith({
    Duration? position,
    Duration? duration,
    Duration? bufferedPosition,
    bool? isPlaying,
    bool? isBuffering,
  }) {
    return TvExoPlayerState(
      position: position ?? this.position,
      duration: duration ?? this.duration,
      bufferedPosition: bufferedPosition ?? this.bufferedPosition,
      isPlaying: isPlaying ?? this.isPlaying,
      isBuffering: isBuffering ?? this.isBuffering,
    );
  }
}

/// App-lifetime listener on the shared native ExoPlayer event channel.
///
/// Same reason as the phone bridge: `EventChannel.cancel()` drops the
/// channel's shared Dart message handler, so a screen disposing after the next
/// episode already subscribed would silence its ready/position events.
class _TvExoEventPump {
  _TvExoEventPump._();

  static final _TvExoEventPump instance = _TvExoEventPump._();

  static const _events = EventChannel('media_client/tv_exo_player_events');

  final state = StreamController<TvExoPlayerState>.broadcast();
  final error = StreamController<String>.broadcast();
  final completed = StreamController<void>.broadcast();
  final ready = StreamController<void>.broadcast();

  TvExoPlayerState latest = const TvExoPlayerState();

  StreamSubscription<dynamic>? _sub;

  void attach(int sessionId) {
    _sub ??= _events.receiveBroadcastStream({'sessionId': sessionId}).listen(
          _dispatch,
          onError: (Object e) {
            AppLog.instance.e('TvExoPlayer', 'event channel error: $e');
          },
        );
  }

  void _dispatch(dynamic raw) {
    if (raw is! Map) return;
    final event = raw['event']?.toString() ?? '';
    switch (event) {
      case 'position':
        final posMs = (raw['positionMs'] as num?)?.toInt() ?? 0;
        final durMs = (raw['durationMs'] as num?)?.toInt() ?? 0;
        latest = latest.copyWith(
          position: Duration(milliseconds: posMs),
          duration: Duration(milliseconds: durMs),
          bufferedPosition:
              Duration(milliseconds: (raw['bufferedPositionMs'] as num?)?.toInt() ?? 0),
          isPlaying: raw['isPlaying'] == true,
          isBuffering: raw['isBuffering'] == true,
        );
        state.add(latest);
      case 'error':
        error.add(raw['message']?.toString() ?? 'playback error');
      case 'completed':
        completed.add(null);
      case 'ready':
        final readyPosMs = (raw['positionMs'] as num?)?.toInt();
        if (readyPosMs != null) {
          latest = latest.copyWith(position: Duration(milliseconds: readyPosMs));
          state.add(latest);
        }
        ready.add(null);
      case 'hdr_output':
        AppLog.instance.i(
          'TvExoPlayer',
          'hdr_output isHdr=${raw['isHdrContent']} range=${raw['videoRange']} '
              'displayHdr10=${raw['displayHdr10']} colorMode=${raw['colorMode']} '
              'applied=${raw['hdrApplied']} reason=${raw['reason']}',
        );
      default:
        break;
    }
  }
}

/// Dart bridge to Android TV ExoPlayer (Media3 + SurfaceView).
class TvExoPlayer {
  TvExoPlayer() : sessionId = ++_sessionSeq {
    startListening();
  }

  static const _method = MethodChannel('media_client/tv_exo_player');

  static final _pump = _TvExoEventPump.instance;

  static int _sessionSeq = 0;

  /// Id of this screen's playback session — native ignores a stale
  /// `stop`/`dispose` from the previous episode's screen.
  final int sessionId;

  Stream<TvExoPlayerState> get stateStream => _pump.state.stream;
  Stream<String> get errorStream => _pump.error.stream;
  Stream<void> get completedStream => _pump.completed.stream;
  Stream<void> get readyStream => _pump.ready.stream;

  TvExoPlayerState get state => _pump.latest;

  void startListening() => _pump.attach(sessionId);

  Future<void> setSource({
    required String url,
    Map<String, String>? headers,
    Duration startPosition = Duration.zero,
    String? subtitleUrl,
    String? subtitleMime,
    bool isHdrContent = false,
    String? videoRange,
  }) async {
    _pump.latest = const TvExoPlayerState();
    AppLog.instance.i(
      'TvExoPlayer',
      'setSource url=$url start=${startPosition.inSeconds}s '
          'subtitle=${subtitleUrl != null} hdr=$isHdrContent range=$videoRange',
    );
    await _method.invokeMethod<void>('setSource', {
      'url': url,
      'headers': headers,
      'startPositionMs': startPosition.inMilliseconds,
      'subtitleUrl': subtitleUrl,
      'subtitleMime': subtitleMime,
      'isHdrContent': isHdrContent,
      'videoRange': videoRange,
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

  Future<void> stop() =>
      _method.invokeMethod<void>('stop', {'sessionId': sessionId});

  Future<TvExoPlayerState> pollState() async {
    final raw = await _method.invokeMapMethod<String, dynamic>('getState');
    if (raw == null) return _pump.latest;
    final posMs = (raw['positionMs'] as num?)?.toInt() ?? 0;
    final durMs = (raw['durationMs'] as num?)?.toInt() ?? 0;
    _pump.latest = _pump.latest.copyWith(
      position: Duration(milliseconds: posMs),
      duration: Duration(milliseconds: durMs),
      isPlaying: raw['isPlaying'] == true,
      isBuffering: raw['isBuffering'] == true,
    );
    return _pump.latest;
  }

  Future<void> dispose() async {
    // Shared pump outlives this screen — see _TvExoEventPump.
    try {
      await _method.invokeMethod<void>('dispose', {'sessionId': sessionId});
    } catch (_) {}
  }
}

/// Maps Emby subtitle stream format to ExoPlayer MIME type (mpv path).
String subtitleMimeForEmbyFormat(String format) {
  switch (format.toLowerCase()) {
    case 'vtt':
      return 'text/vtt';
    case 'ass':
    case 'ssa':
      return 'text/x-ssa';
    default:
      return 'application/x-subrip';
  }
}

/// ExoPlayer TV — only SRT/VTT sidecars (ASS is fetched as SRT from Emby).
String exoSubtitleMimeForEmby(EmbySubtitleOption option) {
  switch (option.exoStreamFormat) {
    case 'vtt':
      return 'text/vtt';
    default:
      return 'application/x-subrip';
  }
}
