import 'package:flutter/material.dart';

/// Desktop / web: no gesture handling.
class PlayerGestureLayer extends StatelessWidget {
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
  final void Function(int deltaSeconds)? onSeekPreview;
  final void Function(double fraction)? onSeekToFraction;
  final void Function(double delta)? onVolumeDelta;
  final void Function(double delta)? onBrightnessDelta;
  final VoidCallback? onUserInteraction;
  final dynamic player;

  @override
  Widget build(BuildContext context) => child;
}
