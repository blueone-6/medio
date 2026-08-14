import 'dart:async';

import 'package:flutter/foundation.dart';

import '../logging/app_log.dart';

/// Serializes subtitle work without blocking video playback.
///
/// - [runSerial]: one switch at a time; sets [busy] for UI lockout.
/// - Network/download is **not** queued behind other downloads.
/// - Only short mpv mutations go through [withMpv].
abstract final class SubtitleSwitchQueue {
  static int _generation = 0;
  static Future<void> _mpvChain = Future<void>.value();

  /// True while a subtitle switch (including network fetch) is in progress.
  static final ValueNotifier<bool> busy = ValueNotifier<bool>(false);

  /// When the latest subtitle switch started. Used by the player screen to
  /// distinguish a spurious mpv EOF (triggered by the `sid` change + `time-pos`
  /// re-seek on a strm-over-CDN MKV) from a genuine end-of-media completion.
  static DateTime? lastSwitchStartedAt;

  /// Player position captured right before the latest subtitle switch's mpv
  /// mutation. Recovery target when a spurious EOF follows the switch.
  static Duration? positionBeforeSwitch;

  /// Records the switch start, including the player position at that moment.
  /// [playerPosition] may be null when the position isn't available yet.
  static void recordSwitchStart(Duration? playerPosition) {
    lastSwitchStartedAt = DateTime.now();
    if (playerPosition != null) {
      positionBeforeSwitch = playerPosition;
    }
  }

  /// Clears switch-tracking state (call before player disposal).
  static void clearSwitchTracking() {
    lastSwitchStartedAt = null;
    positionBeforeSwitch = null;
  }

  static int begin() => ++_generation;

  static bool isCurrent(int generation) => generation == _generation;

  /// Runs one subtitle operation; rejects if another switch is already running.
  static Future<void> runSerial(Future<void> Function(int generation) action) {
    if (busy.value) {
      AppLog.instance.d('Subtitle', 'switch ignored — already in progress');
      return Future.value();
    }
    final generation = begin();
    busy.value = true;
    return Future<void>(() async {
      try {
        await action(generation);
      } on SubtitleSwitchCancelled {
        // Superseded or disposed.
      } catch (e, st) {
        AppLog.instance.e('Subtitle', 'switch failed', error: e, stackTrace: st);
      } finally {
        busy.value = false;
      }
    });
  }

  /// @deprecated Prefer [runSerial]. Kept for call sites that fire-and-forget.
  static void runDetached(Future<void> Function(int generation) action) {
    unawaited(runSerial(action));
  }

  /// Cancels pending mpv chain (call before player disposal).
  static void reset() {
    _generation++;
    _mpvChain = Future<void>.value();
    busy.value = false;
    clearSwitchTracking();
  }
  static Future<T> withMpv<T>(Future<T> Function() action) async {
    final completer = Completer<T>();
    _mpvChain = _mpvChain.then((_) async {
      try {
        if (!completer.isCompleted) {
          completer.complete(await action());
        }
      } catch (e, st) {
        if (!completer.isCompleted) {
          completer.completeError(e, st);
        }
      }
    });
    return completer.future;
  }
}

/// Thrown when a newer subtitle selection superseded this operation.
final class SubtitleSwitchCancelled implements Exception {
  @override
  String toString() => 'SubtitleSwitchCancelled';
}

bool isSubtitleSwitchCancelled(Object? error) => error is SubtitleSwitchCancelled;
