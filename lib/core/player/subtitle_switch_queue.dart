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
