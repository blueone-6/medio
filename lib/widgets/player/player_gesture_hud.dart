import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';

/// Gesture feedback overlay kinds shown during Android touch interaction.
enum PlayerGestureHudKind { none, seek, volume, brightness }

/// Centered HUD with [AnimatedOpacity]; parent controls visibility via [visible].
class PlayerGestureHud extends StatelessWidget {
  const PlayerGestureHud({
    super.key,
    required this.visible,
    required this.kind,
    this.value = 0,
    this.seekSeconds = 0,
    this.seekTarget,
    this.seekDuration,
  });

  final bool visible;
  final PlayerGestureHudKind kind;
  final double value;
  final int seekSeconds;
  final Duration? seekTarget;
  final Duration? seekDuration;

  static String fmtHms(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (kind == PlayerGestureHudKind.none) {
      return const SizedBox.shrink();
    }

    final padding = MediaQuery.paddingOf(context);
    late IconData icon;
    late String label;
    double? barValue;
    String? subtitle;

    if (kind == PlayerGestureHudKind.seek) {
      if (seekSeconds != 0) {
        icon = seekSeconds > 0
            ? Icons.fast_forward_rounded
            : Icons.fast_rewind_rounded;
        label = '${seekSeconds > 0 ? '+' : ''}${seekSeconds}s';
        if (seekTarget != null &&
            seekDuration != null &&
            seekDuration! > Duration.zero) {
          subtitle =
              '${fmtHms(seekTarget!)} / ${fmtHms(seekDuration!)}';
        }
      } else {
        icon = Icons.schedule_rounded;
        label = '跳转';
      }
    } else if (kind == PlayerGestureHudKind.volume) {
      icon = value <= 0
          ? Icons.volume_off_rounded
          : value < 50
              ? Icons.volume_down_rounded
              : Icons.volume_up_rounded;
      label = '${value.round()}%';
      barValue = (value / 100).clamp(0.0, 1.0);
    } else if (kind == PlayerGestureHudKind.brightness) {
      icon = Icons.brightness_6_rounded;
      label = '${(value * 100).round()}%';
      barValue = value.clamp(0.0, 1.0);
    } else {
      return const SizedBox.shrink();
    }

    final player = context.playerColors;

    return Positioned.fill(
      child: IgnorePointer(
        child: Padding(
          padding: EdgeInsets.only(
            top: padding.top + 8,
            bottom: padding.bottom + 8,
          ),
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: const Duration(milliseconds: 180),
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: player.hudBackground,
                  borderRadius: AppRadius.lgR,
                  border: Border.all(color: player.hudBorder),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, color: player.foreground, size: 28),
                      const SizedBox(height: 8),
                      Text(
                        label,
                        style: TextStyle(
                          color: player.foreground,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: player.foregroundDim,
                            fontSize: 13,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                      if (barValue != null) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          width: 140,
                          child: ClipRRect(
                            borderRadius: const BorderRadius.all(Radius.circular(2)),
                            child: LinearProgressIndicator(
                              value: barValue,
                              minHeight: 4,
                              backgroundColor: player.progressTrack,
                              color: player.progressActive.withValues(alpha: 0.9),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Circular ripple shown at double-tap location (±10s seek feedback).
class PlayerGestureDoubleTapRipple extends StatefulWidget {
  const PlayerGestureDoubleTapRipple({
    super.key,
    required this.center,
    required this.forward,
    required this.onFinished,
  });

  final Offset center;
  final bool forward;
  final VoidCallback onFinished;

  @override
  State<PlayerGestureDoubleTapRipple> createState() =>
      _PlayerGestureDoubleTapRippleState();
}

class _PlayerGestureDoubleTapRippleState
    extends State<PlayerGestureDoubleTapRipple>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    )..forward().whenComplete(() {
        if (mounted) widget.onFinished();
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = context.playerColors;
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = Curves.easeOut.transform(_controller.value);
            final size = 48.0 + t * 72;
            final opacity = (1 - t).clamp(0.0, 1.0);
            return Stack(
              children: [
                Positioned(
                  left: widget.center.dx - size / 2,
                  top: widget.center.dy - size / 2,
                  child: Opacity(
                    opacity: opacity * 0.55,
                    child: Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: player.progressTrack,
                        border: Border.all(
                          color: player.progressBuffer,
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        widget.forward
                            ? Icons.forward_10_rounded
                            : Icons.replay_10_rounded,
                        color: player.foreground,
                        size: 28,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
