import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';

/// Gesture feedback overlay kinds shown during Android touch interaction.
enum PlayerGestureHudKind { none, seek, volume, brightness, speed }

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
    } else if (kind == PlayerGestureHudKind.speed) {
      icon = Icons.fast_forward_rounded;
      label = '${value.toStringAsFixed(1)}x 快进';
      subtitle = '松开恢复正常速度';
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

/// Full-screen gesture cheat-sheet shown while playback is paused.
///
/// The scrim is translucent so the paused frame stays visible, and
/// [IgnorePointer] lets taps/drags fall through to the gesture layer. Dashed
/// dividers at the third boundaries put each hint inside the zone it belongs
/// to, so the copy never has to say "left / middle / right".
class PlayerGestureHints extends StatelessWidget {
  const PlayerGestureHints({super.key, required this.visible});

  final bool visible;

  static const _leftHints = <({IconData icon, String label})>[
    (icon: Icons.replay_10_rounded, label: '双击 快退 10s'),
    (icon: Icons.fast_rewind_rounded, label: '长按 加速快退'),
    (icon: Icons.brightness_6_rounded, label: '上下滑动 亮度'),
  ];

  static const _middleHints = <({IconData icon, String label})>[
    (icon: Icons.play_circle_outline_rounded, label: '双击 播放 / 暂停'),
  ];

  static const _rightHints = <({IconData icon, String label})>[
    (icon: Icons.forward_10_rounded, label: '双击 快进 10s'),
    (icon: Icons.fast_forward_rounded, label: '长按 2× 快进'),
    (icon: Icons.volume_up_rounded, label: '上下滑动 音量'),
  ];

  @override
  Widget build(BuildContext context) {
    final player = context.playerColors;
    return Positioned.fill(
      child: IgnorePointer(
        child: ExcludeSemantics(
          excluding: !visible,
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: ColoredBox(
              color: player.scrim,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CustomPaint(
                    painter: _GestureZoneDividerPainter(
                      color: player.foreground.withValues(alpha: 0.28),
                    ),
                  ),
                  SafeArea(
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: _GestureZone(hints: _leftHints),
                                ),
                                Expanded(
                                  child: _GestureZone(hints: _middleHints),
                                ),
                                Expanded(
                                  child: _GestureZone(hints: _rightHints),
                                ),
                              ],
                            ),
                            const SizedBox(height: 26),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.swipe_rounded,
                                  size: 18,
                                  color: player.foregroundDim,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '左右滑动 调整进度',
                                  style: TextStyle(
                                    color: player.foregroundDim,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One third of the cheat-sheet: icon + copy centered in its zone.
class _GestureZone extends StatelessWidget {
  const _GestureZone({required this.hints});

  final List<({IconData icon, String label})> hints;

  @override
  Widget build(BuildContext context) {
    final player = context.playerColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < hints.length; i++) ...[
            if (i > 0) const SizedBox(height: 20),
            Icon(hints[i].icon, size: 24, color: player.foregroundDim),
            const SizedBox(height: 6),
            Text(
              hints[i].label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: player.foreground,
                fontSize: 12,
                height: 1.3,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Two vertical dashed lines at the 1/3 and 2/3 boundaries.
class _GestureZoneDividerPainter extends CustomPainter {
  const _GestureZoneDividerPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const dash = 7.0;
    const gap = 7.0;
    for (final x in <double>[size.width / 3, size.width * 2 / 3]) {
      for (var y = 0.0; y < size.height; y += dash + gap) {
        canvas.drawLine(
          Offset(x, y),
          Offset(x, (y + dash).clamp(0.0, size.height)),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_GestureZoneDividerPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Circular ripple shown at the double-tap location: ±10 s seek feedback, or
/// play/pause when [icon] is given.
class PlayerGestureDoubleTapRipple extends StatefulWidget {
  const PlayerGestureDoubleTapRipple({
    super.key,
    required this.center,
    required this.forward,
    required this.onFinished,
    this.icon,
  });

  final Offset center;
  final bool forward;
  final VoidCallback onFinished;

  /// Overrides the default forward/replay icon (middle-tap play/pause).
  final IconData? icon;

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
                        widget.icon ??
                            (widget.forward
                                ? Icons.forward_10_rounded
                                : Icons.replay_10_rounded),
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
