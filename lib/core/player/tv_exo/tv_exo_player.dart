import 'dart:async';

import 'package:flutter/services.dart';

import '../../logging/app_log.dart';
import '../../../models/emby/emby_subtitle_option.dart';

/// Playback state pushed from native ExoPlayer (Android TV).
class TvExoPlayerState {
  const TvExoPlayerState({
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.isPlaying = false,
    this.isBuffering = false,
  });

  final Duration position;
  final Duration duration;
  final bool isPlaying;
  final bool isBuffering;

  TvExoPlayerState copyWith({
    Duration? position,
    Duration? duration,
    bool? isPlaying,
    bool? isBuffering,
  }) {
    return TvExoPlayerState(
      position: position ?? this.position,
      duration: duration ?? this.duration,
      isPlaying: isPlaying ?? this.isPlaying,
      isBuffering: isBuffering ?? this.isBuffering,
    );
  }
}

/// Dart bridge to Android TV ExoPlayer (Media3 + SurfaceView).
class TvExoPlayer {
  TvExoPlayer() {
    startListening();
  }

  static const _method = MethodChannel('media_client/tv_exo_player');
  static const _events = EventChannel('media_client/tv_exo_player_events');

  final _stateController = StreamController<TvExoPlayerState>.broadcast();
  final _errorController = StreamController<String>.broadcast();
  final _completedController = StreamController<void>.broadcast();
  final _readyController = StreamController<void>.broadcast();

  StreamSubscription<dynamic>? _eventSub;
  TvExoPlayerState _state = const TvExoPlayerState();

  Stream<TvExoPlayerState> get stateStream => _stateController.stream;
  Stream<String> get errorStream => _errorController.stream;
  Stream<void> get completedStream => _completedController.stream;
  Stream<void> get readyStream => _readyController.stream;

  TvExoPlayerState get state => _state;

  void startListening() {
    _eventSub ??= _events.receiveBroadcastStream().listen(
          _onEvent,
          onError: (Object e) {
            AppLog.instance.e('TvExoPlayer', 'event channel error: $e');
          },
        );
  }

  void _onEvent(dynamic raw) {
    if (raw is! Map) return;
    final event = raw['event']?.toString() ?? '';
    switch (event) {
      case 'position':
        final posMs = (raw['positionMs'] as num?)?.toInt() ?? 0;
        final durMs = (raw['durationMs'] as num?)?.toInt() ?? 0;
        final playing = raw['isPlaying'] == true;
        final buffering = raw['isBuffering'] == true;
        _state = _state.copyWith(
          position: Duration(milliseconds: posMs),
          duration: Duration(milliseconds: durMs),
          isPlaying: playing,
          isBuffering: buffering,
        );
        _stateController.add(_state);
      case 'error':
        final message = raw['message']?.toString() ?? 'playback error';
        _errorController.add(message);
      case 'completed':
        _completedController.add(null);
      case 'ready':
        final readyPosMs = (raw['positionMs'] as num?)?.toInt();
        if (readyPosMs != null) {
          _state = _state.copyWith(
            position: Duration(milliseconds: readyPosMs),
          );
          _stateController.add(_state);
        }
        _readyController.add(null);
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

  Future<void> setSource({
    required String url,
    Map<String, String>? headers,
    Duration startPosition = Duration.zero,
    String? subtitleUrl,
    String? subtitleMime,
    bool isHdrContent = false,
    String? videoRange,
  }) async {
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

  Future<void> stop() => _method.invokeMethod<void>('stop');

  Future<TvExoPlayerState> pollState() async {
    final raw = await _method.invokeMapMethod<String, dynamic>('getState');
    if (raw == null) return _state;
    final posMs = (raw['positionMs'] as num?)?.toInt() ?? 0;
    final durMs = (raw['durationMs'] as num?)?.toInt() ?? 0;
    _state = _state.copyWith(
      position: Duration(milliseconds: posMs),
      duration: Duration(milliseconds: durMs),
      isPlaying: raw['isPlaying'] == true,
      isBuffering: raw['isBuffering'] == true,
    );
    return _state;
  }

  Future<void> dispose() async {
    await _eventSub?.cancel();
    _eventSub = null;
    try {
      await _method.invokeMethod<void>('dispose');
    } catch (_) {}
    await _stateController.close();
    await _errorController.close();
    await _completedController.close();
    await _readyController.close();
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
