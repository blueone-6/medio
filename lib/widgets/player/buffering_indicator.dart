import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import 'player_gesture_hud.dart';

/// Timing thresholds for the in-player buffering indicator.
abstract final class BufferingFeedbackTiming {
  /// Routine rebuffers (a seek, a segment switch) finish well inside this, so
  /// they never flash a spinner and the chrome stays calm.
  static const Duration show = Duration(milliseconds: 700);

  /// Past this the wait is clearly the network rather than a hiccup, so the
  /// indicator starts explaining it.
  static const Duration slow = Duration(seconds: 8);
}

/// Visual stage of the in-player buffering indicator.
enum BufferingStage {
  /// Nothing shown — either playing, or waiting so briefly that it is not worth
  /// interrupting the frame.
  hidden,

  /// Waiting long enough to be noticeable: spinner + 正在缓冲…
  buffering,

  /// Waiting long enough that it is a network problem: names it and shows how
  /// far ahead the buffer reaches.
  slow,
}

/// Pure stage decision: how strongly to signal "the player is waiting".
///
/// Kept separate from the timers so the escalation rules are unit-testable.
BufferingStage bufferingStageFor({
  required bool waiting,
  required Duration waited,
  Duration showDelay = BufferingFeedbackTiming.show,
  Duration slowDelay = BufferingFeedbackTiming.slow,
}) {
  if (!waiting) return BufferingStage.hidden;
  if (waited >= slowDelay) return BufferingStage.slow;
  if (waited >= showDelay) return BufferingStage.buffering;
  return BufferingStage.hidden;
}

/// Delayed, escalating buffering feedback for a waiting player.
///
/// Owns the delay timers and re-renders the host screen when the stage changes.
/// Call [syncBufferingFeedback] from the player state stream, call
/// [disposeBufferingFeedback] from `State.dispose`, and render
/// [BufferingIndicator] whenever [bufferingStage] is not
/// [BufferingStage.hidden].
mixin BufferingFeedbackMixin<T extends StatefulWidget> on State<T> {
  Timer? _bufferingTimer;
  DateTime? _bufferingSince;
  BufferingStage _bufferingStage = BufferingStage.hidden;

  /// Current visual stage to render.
  BufferingStage get bufferingStage => _bufferingStage;

  /// [waiting] should be the player's buffering flag, already gated on "no
  /// other overlay is explaining the wait" (initial load, reconnect, error).
  void syncBufferingFeedback({required bool waiting}) {
    if (!waiting) {
      _bufferingTimer?.cancel();
      _bufferingTimer = null;
      _bufferingSince = null;
      _applyBufferingStage(BufferingStage.hidden);
      return;
    }
    _bufferingSince ??= DateTime.now();
    _scheduleBufferingStage();
  }

  /// Cancels the timers. Call from [State.dispose].
  void disposeBufferingFeedback() {
    _bufferingTimer?.cancel();
    _bufferingTimer = null;
    _bufferingSince = null;
  }

  void _scheduleBufferingStage() {
    _bufferingTimer?.cancel();
    final since = _bufferingSince;
    if (since == null) return;
    final waited = DateTime.now().difference(since);
    final stage = bufferingStageFor(waiting: true, waited: waited);
    _applyBufferingStage(stage);
    if (stage == BufferingStage.slow) return;
    final target = stage == BufferingStage.hidden
        ? BufferingFeedbackTiming.show
        : BufferingFeedbackTiming.slow;
    var remaining = target - waited;
    if (remaining < const Duration(milliseconds: 16)) {
      remaining = const Duration(milliseconds: 16);
    }
    _bufferingTimer = Timer(remaining, _scheduleBufferingStage);
  }

  void _applyBufferingStage(BufferingStage stage) {
    if (stage == _bufferingStage) return;
    if (!mounted) {
      _bufferingStage = stage;
      return;
    }
    setState(() => _bufferingStage = stage);
  }
}

/// In-player buffering pill drawn over the (stalled) frame.
///
/// Deliberately does not black out the video: the picture stays visible and the
/// pill is what tells the viewer the player is waiting for data rather than
/// frozen. At [BufferingStage.slow] it names the likely cause and shows the
/// buffered range, which is what separates "slow network" from "dead source".
class BufferingIndicator extends StatelessWidget {
  const BufferingIndicator({
    super.key,
    required this.stage,
    this.bufferedPosition = Duration.zero,
    this.duration = Duration.zero,
  });

  final BufferingStage stage;
  final Duration bufferedPosition;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final slow = stage == BufferingStage.slow;
    return Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: AppMotion.effectiveDuration(context, AppMotion.base),
        curve: AppMotion.decelerate,
        builder: (context, t, child) => Opacity(opacity: t, child: child),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 18),
          decoration: BoxDecoration(
            color: PlayerPaletteDefaults.panel,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: PlayerPaletteDefaults.hudBorder),
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
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: PlayerPaletteDefaults.foreground,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    slow ? '网络缓慢，正在缓冲…' : '正在缓冲…',
                    style: const TextStyle(
                      color: PlayerPaletteDefaults.foreground,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              if (slow && duration > Duration.zero) ...[
                const SizedBox(height: 8),
                Text(
                  '已缓冲至 ${PlayerGestureHud.fmtHms(bufferedPosition)} / '
                  '${PlayerGestureHud.fmtHms(duration)}',
                  style: const TextStyle(
                    color: PlayerPaletteDefaults.foregroundDim,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
