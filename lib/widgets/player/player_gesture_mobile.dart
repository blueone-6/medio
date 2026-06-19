import 'dart:async';

import 'package:flutter/material.dart';
import 'package:screen_brightness/screen_brightness.dart';

import '../../core/layout/platform_layout.dart';
import 'player_gesture_hud.dart';

enum _LockedPanAxis { none, horizontal, vertical }

/// Android touch gestures following platform conventions:
/// - Single tap: show/hide controls
/// - Double tap left/right half: seek ±10s with ripple
/// - Horizontal drag: preview timeline offset, commit on release
/// - Vertical drag left half: brightness
/// - Vertical drag right half: volume
/// - Long press: accelerated seek (left=rewind, right=forward)
class PlayerGestureLayer extends StatefulWidget {
  const PlayerGestureLayer({
    super.key,
    required this.child,
    this.onTap,
    this.onPlayPause,
    this.onSeekRelative,
    this.onSeekPreview,
    this.onSeekToFraction,
    this.onVolumeDelta,
    this.onBrightnessDelta,
    this.onUserInteraction,
    this.player,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onPlayPause;
  final void Function(int seconds)? onSeekRelative;
  /// Temporary horizontal seek offset (seconds); pass 0 to clear preview.
  final void Function(int deltaSeconds)? onSeekPreview;
  final void Function(double fraction)? onSeekToFraction;
  final void Function(double delta)? onVolumeDelta;
  final void Function(double delta)? onBrightnessDelta;
  final VoidCallback? onUserInteraction;
  final dynamic player;

  @override
  State<PlayerGestureLayer> createState() => _PlayerGestureLayerState();
}

class _PlayerGestureLayerState extends State<PlayerGestureLayer> {
  final GlobalKey _gestureKey = GlobalKey();
  double _layoutWidth = 400;
  double _layoutHeight = 800;
  PlayerGestureHudKind _hudKind = PlayerGestureHudKind.none;
  bool _hudVisible = false;
  double _hudValue = 0;
  int _hudSeekSeconds = 0;
  Timer? _hudHideTimer;

  double? _brightnessBaseline;
  double? _volumeBaseline;

  // Horizontal seek preview
  Duration? _horizSeekBase;
  int _horizSeekAccumulated = 0;
  double _horizSeekAccumulatedExact = 0;

  // Unified pan with axis lock (avoids H/V drag arena fighting on real devices)
  _LockedPanAxis _panAxis = _LockedPanAxis.none;
  Offset? _panStartLocal;
  static const _axisLockSlop = 12.0;

  // Long-press accelerated seek state
  Timer? _longPressTimer;
  Timer? _longPressSeekTimer;
  bool _longPressActive = false;
  int _longPressDirection = 0;
  int _longPressAccumulatedSeconds = 0;
  DateTime? _longPressStartTime;

  // Double-tap ripple
  Offset? _rippleCenter;
  bool _rippleForward = true;

  // Debounce for double-tap vs single-tap
  Timer? _singleTapTimer;
  bool _awaitingDoubleTap = false;
  static const _doubleTapTimeout = Duration(milliseconds: 300);
  static const _hudHideDelay = Duration(milliseconds: 500);
  /// Full-screen vertical swipe = 100% adjustment range (MX Player / VLC).
  static const _volumeRangePerFullHeight = 100.0;
  static const _brightnessRangePerFullHeight = 1.0;

  @override
  void dispose() {
    _hudHideTimer?.cancel();
    _longPressTimer?.cancel();
    _longPressSeekTimer?.cancel();
    _singleTapTimer?.cancel();
    super.dispose();
  }

  void _notify() => widget.onUserInteraction?.call();

  Duration _readPosition() {
    final pos = widget.player?.state?.position;
    if (pos is Duration) return pos;
    return Duration.zero;
  }

  Duration _readDuration() {
    final dur = widget.player?.state?.duration;
    if (dur is Duration) return dur;
    return Duration.zero;
  }

  bool _isRightHalf(Offset localPosition, double width) =>
      localPosition.dx >= width / 2;

  void _showHud(
    PlayerGestureHudKind kind, {
    double value = 0,
    int seekSeconds = 0,
  }) {
    if (!isAndroidMobileUi) return;
    setState(() {
      _hudKind = kind;
      _hudVisible = true;
      _hudValue = value;
      _hudSeekSeconds = seekSeconds;
    });
    _hudHideTimer?.cancel();
    _hudHideTimer = Timer(_hudHideDelay, () {
      if (mounted) setState(() => _hudVisible = false);
    });
  }

  void _clearSeekPreview() {
    _horizSeekBase = null;
    _horizSeekAccumulated = 0;
    _horizSeekAccumulatedExact = 0;
    widget.onSeekPreview?.call(0);
  }

  void _updateHorizontalSeekFromTotalDx(double totalDx, double gestureWidth) {
    final dur = _readDuration();
    if (gestureWidth <= 0 || dur <= Duration.zero) return;

    final fractionDelta = totalDx / gestureWidth;
    final deltaMs = (fractionDelta * dur.inMilliseconds).round();
    _horizSeekAccumulatedExact = deltaMs / 1000.0;
    _horizSeekAccumulated = _horizSeekAccumulatedExact.round();
    widget.onSeekPreview?.call(_horizSeekAccumulated);
    _showHud(
      PlayerGestureHudKind.seek,
      seekSeconds: _horizSeekAccumulated,
    );
  }

  void _onPanStart(DragStartDetails details) {
    _notify();
    _cancelLongPress(commit: false);
    _panAxis = _LockedPanAxis.none;
    _panStartLocal = details.localPosition;
    _horizSeekBase = _readPosition();
    _horizSeekAccumulated = 0;
    _horizSeekAccumulatedExact = 0;
    if (details.localPosition.dx < _layoutWidth / 2) {
      _brightnessBaseline = null;
      _volumeBaseline = null;
    } else {
      _volumeBaseline =
          (widget.player?.state?.volume as num?)?.toDouble() ?? 50.0;
      _brightnessBaseline = null;
    }
  }

  void _onPanUpdate(DragUpdateDetails details, double gestureWidth, double gestureHeight) {
    _notify();
    if (_panAxis == _LockedPanAxis.none && _panStartLocal != null) {
      final totalDx = (details.localPosition.dx - _panStartLocal!.dx).abs();
      final totalDy = (details.localPosition.dy - _panStartLocal!.dy).abs();
      if (totalDx < _axisLockSlop && totalDy < _axisLockSlop) return;
      _panAxis =
          totalDx >= totalDy ? _LockedPanAxis.horizontal : _LockedPanAxis.vertical;
    }

    switch (_panAxis) {
      case _LockedPanAxis.horizontal:
        if (_panStartLocal != null) {
          final totalDx = details.localPosition.dx - _panStartLocal!.dx;
          _updateHorizontalSeekFromTotalDx(totalDx, gestureWidth);
        }
      case _LockedPanAxis.vertical:
        if (_panStartLocal == null) break;
        final startX = _panStartLocal!.dx;
        final totalDy = details.localPosition.dy - _panStartLocal!.dy;
        if (startX < gestureWidth / 2) {
          unawaited(_applyBrightnessFromTotalDy(totalDy, gestureHeight));
        } else {
          _applyVolumeFromTotalDy(totalDy, gestureHeight);
        }
      case _LockedPanAxis.none:
        break;
    }
  }

  void _onPanEnd(DragEndDetails details) {
    if (_panAxis == _LockedPanAxis.horizontal && _horizSeekAccumulated != 0) {
      widget.onSeekRelative?.call(_horizSeekAccumulated);
    }
    if (_panAxis == _LockedPanAxis.horizontal) {
      _clearSeekPreview();
    }
    _panAxis = _LockedPanAxis.none;
    _panStartLocal = null;
    _volumeBaseline = null;
    _brightnessBaseline = null;
  }

  void _onPanCancel() {
    if (_panAxis == _LockedPanAxis.horizontal) {
      _clearSeekPreview();
    }
    _panAxis = _LockedPanAxis.none;
    _panStartLocal = null;
    _volumeBaseline = null;
    _brightnessBaseline = null;
  }

  Duration? _seekTargetDuration() {
    final base = _horizSeekBase ?? _readPosition();
    final dur = _readDuration();
    if (dur <= Duration.zero) return null;
    var target = base + Duration(seconds: _horizSeekAccumulated);
    if (target < Duration.zero) target = Duration.zero;
    if (target > dur) target = dur;
    return target;
  }

  void _cancelLongPress({bool commit = true}) {
    _longPressTimer?.cancel();
    _longPressSeekTimer?.cancel();
    if (commit && _longPressActive && _longPressAccumulatedSeconds != 0) {
      widget.onSeekRelative?.call(_longPressAccumulatedSeconds);
      widget.onSeekPreview?.call(0);
    }
    _longPressActive = false;
    _longPressDirection = 0;
    _longPressAccumulatedSeconds = 0;
    _longPressStartTime = null;
  }

  void _startLongPressSeek(int direction) {
    _longPressDirection = direction;
    _longPressAccumulatedSeconds = 0;
    _longPressStartTime = DateTime.now();
    _longPressActive = true;
    _horizSeekBase = _readPosition();
    _longPressSeekTimer?.cancel();
    _longPressSeekTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!_longPressActive || !mounted) return;
      _notify();
      final elapsed = DateTime.now().difference(_longPressStartTime!);
      final step = _seekStepForDuration(elapsed);
      _longPressAccumulatedSeconds += step * _longPressDirection;
      _horizSeekAccumulated = _longPressAccumulatedSeconds;
      widget.onSeekPreview?.call(_horizSeekAccumulated);
      _showHud(PlayerGestureHudKind.seek, seekSeconds: _horizSeekAccumulated);
    });
  }

  static int _seekStepForDuration(Duration held) {
    final ms = held.inMilliseconds;
    if (ms < 500) return 2;
    if (ms < 1000) return 5;
    if (ms < 2000) return 10;
    if (ms < 4000) return 20;
    if (ms < 7000) return 40;
    return 60;
  }

  Future<void> _applyBrightnessFromTotalDy(
    double totalDy,
    double height,
  ) async {
    if (!isAndroidMobileUi || height <= 0) return;
    try {
      final sb = ScreenBrightness();
      _brightnessBaseline ??= await sb.application;
      final baseline = _brightnessBaseline!;
      final delta =
          -(totalDy / height) * _brightnessRangePerFullHeight;
      final next = (baseline + delta).clamp(0.0, 1.0);
      await sb.setApplicationScreenBrightness(next);
      _showHud(PlayerGestureHudKind.brightness, value: next);
      widget.onBrightnessDelta?.call(next - baseline);
    } catch (_) {
      // Brightness control unavailable on this device — silently ignore.
    }
  }

  void _applyVolumeFromTotalDy(double totalDy, double height) {
    if (height <= 0 || _volumeBaseline == null) return;
    final delta = -(totalDy / height) * _volumeRangePerFullHeight;
    final next = (_volumeBaseline! + delta).clamp(0.0, 100.0);
    final currentVol =
        (widget.player?.state?.volume as num?)?.toDouble() ?? _volumeBaseline!;
    final change = next - currentVol;
    if (change.abs() < 0.01) return;
    widget.onVolumeDelta?.call(change);
    _showHud(PlayerGestureHudKind.volume, value: next);
  }

  void _onDoubleTapDown(TapDownDetails details) {
    _singleTapTimer?.cancel();
    _awaitingDoubleTap = false;
    _notify();

    final box = _gestureKey.currentContext?.findRenderObject() as RenderBox?;
    final width =
        (box != null && box.hasSize && box.size.width > 0)
            ? box.size.width
            : _layoutWidth;
    final forward = _isRightHalf(details.localPosition, width);
    final seconds = forward ? 10 : -10;
    widget.onSeekRelative?.call(seconds);
    _showHud(PlayerGestureHudKind.seek, seekSeconds: seconds);

    setState(() {
      _rippleCenter = details.localPosition;
      _rippleForward = forward;
    });
  }

  void _onRippleFinished() {
    if (!mounted) return;
    setState(() => _rippleCenter = null);
  }

  @override
  Widget build(BuildContext context) {
    if (!isAndroidMobileUi) return widget.child;

    final seekDur = _readDuration();
    final seekTarget = _hudKind == PlayerGestureHudKind.seek &&
            _horizSeekAccumulated != 0
        ? _seekTargetDuration()
        : null;

    return SizedBox.expand(
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          Positioned.fill(
            child: LayoutBuilder(
            builder: (context, constraints) {
              _layoutWidth = constraints.maxWidth.isFinite &&
                      constraints.maxWidth > 0
                  ? constraints.maxWidth
                  : 400.0;
              _layoutHeight = constraints.maxHeight.isFinite &&
                      constraints.maxHeight > 0
                  ? constraints.maxHeight
                  : 800.0;
              final gestureWidth = _layoutWidth;
              final gestureHeight = _layoutHeight;
              return GestureDetector(
            key: _gestureKey,
            behavior: HitTestBehavior.translucent,

            onTap: () {
              if (_awaitingDoubleTap) return;
              _singleTapTimer?.cancel();
              _awaitingDoubleTap = true;
              _singleTapTimer = Timer(_doubleTapTimeout, () {
                _awaitingDoubleTap = false;
                widget.onTap?.call();
              });
            },
            onDoubleTapDown: _onDoubleTapDown,

            onPanStart: _onPanStart,
            onPanUpdate: (details) =>
                _onPanUpdate(details, gestureWidth, gestureHeight),
            onPanEnd: _onPanEnd,
            onPanCancel: _onPanCancel,

            onLongPressStart: (details) {
              _notify();
              final direction =
                  _isRightHalf(details.localPosition, gestureWidth) ? 1 : -1;
              _startLongPressSeek(direction);
            },
            onLongPressMoveUpdate: (details) {
              if (!_longPressActive) return;
              final newDir =
                  _isRightHalf(details.localPosition, gestureWidth) ? 1 : -1;
              if (newDir != _longPressDirection) {
                _longPressDirection = newDir;
                _longPressStartTime = DateTime.now();
              }
            },
            onLongPressEnd: (_) => _cancelLongPress(),
            onLongPressCancel: () => _cancelLongPress(commit: false),
              );
            },
          ),
        ),
        PlayerGestureHud(
          visible: _hudVisible && _hudKind != PlayerGestureHudKind.none,
          kind: _hudKind,
          value: _hudValue,
          seekSeconds: _hudSeekSeconds,
          seekTarget: seekTarget,
          seekDuration: seekDur > Duration.zero ? seekDur : null,
        ),
        if (_rippleCenter != null)
          PlayerGestureDoubleTapRipple(
            center: _rippleCenter!,
            forward: _rippleForward,
            onFinished: _onRippleFinished,
          ),
      ],
      ),
    );
  }
}
