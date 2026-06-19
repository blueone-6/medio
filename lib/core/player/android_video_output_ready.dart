import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

// ignore: implementation_imports
import 'package:media_kit_video/src/video_controller/android_video_controller/real.dart';

import '../layout/platform_layout.dart';
import '../logging/app_log.dart';
import '../logging/perf.dart';

const _mediaKitVideoChannel = MethodChannel('com.alexmercerind/media_kit_video');

/// After [setState] assigns a [VideoController], wait until [Video] has laid out.
Future<void> waitForVideoWidgetMounted() async {
  await WidgetsBinding.instance.endOfFrame;
  await WidgetsBinding.instance.endOfFrame;
}

String _formatPlaybackClock(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (h > 0) return '${h.toString().padLeft(2, '0')}:$m:$s';
  return '$m:$s';
}

void logPlayerPlaybackPosition(
  Player player,
  String milestone, {
  Duration? expectedResumeAt,
}) {
  final pos = player.state.position;
  final dur = player.state.duration;
  final expect = expectedResumeAt != null
      ? ' expectedResume=${_formatPlaybackClock(expectedResumeAt)}'
      : '';
  AppLog.instance.i(
    'Player',
    '$milestone position=${_formatPlaybackClock(pos)} '
    '(${pos.inMilliseconds}ms) duration=${_formatPlaybackClock(dur)}$expect',
  );
}

/// media_kit_video resets playback when `wid` goes 0→non-zero after [Player.open].
/// In 1.3.x the library's widListener calls `seek(Duration.zero)`; in 2.0.1+
/// (PR #1294) it calls `seek(player.state.position)` instead — but when position
/// is still 0 at attach time (lazy surface + mpv --start), that is still seek(0).
/// Re-seek once when that happens if we still look like a failed resume.
///
/// Also serves as the unified "Android surface attached & first frame can
/// actually display" signal for fresh playback ([resumeAt] = 0): in that case
/// no re-seek is needed, the guard only waits for the 120 ms widListener seek
/// to land and then fires [onSurfaceSettled] so the player can drop its
/// loading mask once mpv is genuinely producing visible frames.
///
/// IMPORTANT — the 120 ms wait below is **not** redundant. Empirical evidence:
/// `media_kit_video`'s internal widListener is registered *after* ours via a
/// separate async path inside `AndroidVideoController` initialization, so its
/// `seek(0)` is issued *after* whatever we send here. Without waiting for
/// `seek(0)` to actually land in mpv, any `seek(resumeAt)` we fire eagerly is
/// overwritten by the late-arriving `seek(0)` and playback starts at 0.
/// (Tried racing them on 2026-05-27, all three runs landed at pos=0.)
VoidCallback? installAndroidResumeSurfaceGuard({
  required VideoController controller,
  required Player player,
  required Duration resumeAt,
  VoidCallback? onSurfaceSettled,
}) {
  if (!isAndroidMobileUi) return null;

  var handled = false;
  VoidCallback? removeWidListener;
  final resumeMs = resumeAt.inMilliseconds;
  final isResumeFlow = resumeMs > 0;

  Future<void> onSurfaceAttached(int wid) async {
    if (handled) return;
    handled = true;
    removeWidListener?.call();
    removeWidListener = null;

    final span = PerfTracer.start(
      'player.resumeGuard',
      context: {
        'wid': wid,
        'resumeSec': resumeAt.inSeconds,
        'flow': isResumeFlow ? 'resume' : 'fresh',
      },
    );

    // Wait for media_kit_video's widListener seek to actually settle in mpv.
    // 120 ms is conservative — observed mpv command latency is 20–80 ms on
    // real Android devices. Applies equally to fresh playback where the
    // widListener also issues a `seek(state.position)`.
    await Future<void>.delayed(const Duration(milliseconds: 120));
    span.stage('wait_widlistener_seek0');
    logPlayerPlaybackPosition(
      player,
      'Android surface attached (wid=$wid), before resume guard',
      expectedResumeAt: isResumeFlow ? resumeAt : null,
    );

    try {
      final pos = player.state.position;
      final posMs = pos.inMilliseconds;
      // Reset detection only makes sense for resume flows — `resumeMs >= 10000
      // && posMs < 5000` is naturally false when resumeMs == 0.
      final reset = isResumeFlow && resumeMs >= 10000 && posMs < 5000;
      if (reset) {
        AppLog.instance.w(
          'Player',
          'Resume guard: position reset after surface attach '
          '(pos=${pos.inSeconds}s target=${resumeAt.inSeconds}s), re-seeking',
        );
        await player.seek(resumeAt);
        span.stage('re_seek');
        await Future<void>.delayed(const Duration(milliseconds: 80));
        span.stage('settle');
        logPlayerPlaybackPosition(
          player,
          'Android resume guard after re-seek',
          expectedResumeAt: resumeAt,
        );
      } else if (isResumeFlow) {
        AppLog.instance.i(
          'Player',
          'Resume guard: position OK after surface attach '
          '(pos=${pos.inSeconds}s target=${resumeAt.inSeconds}s), no re-seek',
        );
      } else {
        AppLog.instance.d(
          'Player',
          'Surface attach settled (fresh playback, pos=${pos.inMilliseconds}ms)',
        );
      }
      final finalPos = player.state.position;
      span.end(extraContext: {
        'reset': reset,
        'finalPosSec': finalPos.inSeconds,
        'drift': isResumeFlow
            ? (finalPos.inMilliseconds - resumeMs).abs()
            : finalPos.inMilliseconds,
      });
      onSurfaceSettled?.call();
    } catch (e, st) {
      span.endError(e, st);
      AppLog.instance.w('Player', 'Resume guard seek failed', e);
    }
  }

  controller.platform.future.then((platform) async {
    if (platform is! AndroidVideoController) return;

    int? lastWid = platform.wid.value;
    void widListener() {
      final wid = platform.wid.value;
      final prev = lastWid;
      lastWid = wid;
      if (handled) return;
      final wasUnset = prev == null || prev == 0;
      final nowSet = wid != null && wid != 0;
      if (wasUnset && nowSet) {
        AppLog.instance.i(
          'Player',
          'Android wid changed $prev→$wid (surface attach)',
        );
        unawaited(onSurfaceAttached(wid));
      }
    }

    platform.wid.addListener(widListener);
    removeWidListener = () => platform.wid.removeListener(widListener);

    // Surface may already be attached before we subscribe — still fire the
    // settle callback so the loading mask can drop, but skip the re-seek
    // window because mpv has already been rendering against that surface.
    final currentWid = platform.wid.value;
    if (currentWid != null && currentWid != 0 && !handled) {
      AppLog.instance.d(
        'Player',
        'Resume guard: wid already $currentWid at install, skipping wait',
      );
      handled = true;
      removeWidListener?.call();
      removeWidListener = null;
      onSurfaceSettled?.call();
    }
  });

  return () {
    handled = true;
    removeWidListener?.call();
    removeWidListener = null;
  };
}

/// Uses media_kit native helper (same as [AndroidVideoController]).
Future<bool> isMediaKitAndroidEmulator() async {
  if (!isAndroidMobileUi) return false;
  try {
    final v = await _mediaKitVideoChannel
        .invokeMethod<bool>('Utils.IsEmulator')
        .timeout(const Duration(milliseconds: 500));
    return v == true;
  } catch (_) {
    return false;
  }
}

/// Once a lazy-surface device is observed (wid stays null past the wait
/// budget), this session-level flag remembers it so subsequent player
/// bootstraps use a much shorter timeout instead of paying ~800 ms every
/// time. Cleared on full app restart.
bool _knownLazySurfaceDevice = false;

/// Default surface-wait budget for the **first** bootstrap of this session.
/// Eager-surface devices (Pixel) typically attach in 100–400 ms; we used to
/// wait 800 ms which was pure overhead on lazy devices. 300 ms covers most
/// eager attaches while limiting wasted time on lazy devices to ~300 ms once.
const _defaultSurfaceWaitFirst = Duration(milliseconds: 300);

/// After we've confirmed this device is lazy, skip almost entirely — the
/// `installAndroidResumeSurfaceGuard` widListener will pick up the eventual
/// attach. 80 ms still gives a tiny window for the listener to fire if
/// surface attached during our setup.
const _defaultSurfaceWaitLazy = Duration(milliseconds: 80);

/// Waits until mpv has a non-zero `--wid` (VideoOutput.Resize / Surface attached).
///
/// media_kit_video's [AndroidVideoController.widListener] re-seeks after vo/wid
/// reinit when `wid` changes. Pre-2.0.1 that was always `seek(Duration.zero)`;
/// 2.0.1+ uses `seek(player.state.position)` (PR #1294).
/// If the Surface attaches *after* [Player.open], that seek resets the
/// `--start` position back to 0. To prevent this we must ensure the Surface
/// is attached **before** [Player.open].
///
/// Strategy (both real device and emulator):
///   - `ValueNotifier` does not replay its current value to a new listener,
///     and on Android the Surface frequently attaches in the gap between
///     the initial `ready()` check and `addListener`. To close that race
///     we combine three signals: a listener for instant wake-up, a poll
///     timer for missed edges, and one immediate re-check right after
///     [ValueNotifier.addListener]. Whichever fires first completes.
///   - Default budget is 300 ms for the first bootstrap of a session; once
///     a lazy-surface device has been observed (timeout hit), subsequent
///     bootstraps shorten to 80 ms because `wid` won't arrive until *after*
///     [Player.open] starts demuxing on those devices. The eventual `wid`
///     transition is handled by [installAndroidResumeSurfaceGuard].
Future<bool> waitForAndroidVideoSurface(
  VideoController controller, {
  Duration? timeout,
}) async {
  if (!isAndroidMobileUi) return true;

  final effectiveTimeout = timeout ??
      (_knownLazySurfaceDevice ? _defaultSurfaceWaitLazy : _defaultSurfaceWaitFirst);

  await controller.platform.future;
  await SchedulerBinding.instance.endOfFrame;
  await SchedulerBinding.instance.endOfFrame;

  final platform = await controller.platform.future;
  if (platform is! AndroidVideoController) return true;

  final isEmu = await isMediaKitAndroidEmulator();

  bool ready() {
    final wid = platform.wid.value;
    final rect = platform.rect.value;
    if (wid == null || wid == 0) return false;
    if (isEmu) {
      return rect != null && rect.width > 1 && rect.height > 1;
    }
    return true;
  }

  AppLog.instance.d(
    'Player',
    'Waiting for Android surface '
    '(wid=${platform.wid.value} id=${controller.id.value} '
    'rect=${platform.rect.value?.width.toInt()}x${platform.rect.value?.height.toInt()})',
  );

  if (ready()) {
    AppLog.instance.i(
      'Player',
      'Android surface already ready wid=${platform.wid.value} '
      'id=${controller.id.value}',
    );
    return true;
  }

  final sw = Stopwatch()..start();
  final completer = Completer<bool>();
  void check() {
    if (completer.isCompleted) return;
    if (ready()) {
      completer.complete(true);
    }
  }

  void listener() => check();
  platform.wid.addListener(listener);

  // Heartbeat poll — backstop for the listener miss-edge case where the
  // Surface attaches during the race window between `if (ready())` and
  // `addListener`. Also catches platforms where `rect` (emulator gate)
  // arrives after `wid` via a different notifier.
  final poll = Timer.periodic(const Duration(milliseconds: 60), (_) => check());

  // Diagnostic heartbeat — if we are about to time out, the log will record
  // exactly what state `wid` / `rect` were stuck in. Cheap (1 line / sec).
  final diag = Timer.periodic(const Duration(seconds: 1), (_) {
    if (completer.isCompleted) return;
    AppLog.instance.d(
      'Player',
      'Surface wait t=${sw.elapsedMilliseconds}ms '
      'wid=${platform.wid.value} '
      'rect=${platform.rect.value?.width.toInt()}x${platform.rect.value?.height.toInt()}',
    );
  });

  // Re-check immediately after registering the listener — closes the race
  // window where `wid` transitions to non-zero between the initial `ready()`
  // call above and `addListener`. ValueNotifier does NOT replay its current
  // value to new listeners, so without this re-check we'd wait the full
  // timeout for a transition that already happened.
  check();

  try {
    final ok = await completer.future.timeout(
      effectiveTimeout,
      onTimeout: () => false,
    );
    if (ok) {
      AppLog.instance.i(
        'Player',
        'Android surface ready after ${sw.elapsedMilliseconds}ms '
        'wid=${platform.wid.value} id=${controller.id.value}',
      );
      return true;
    }
  } finally {
    poll.cancel();
    diag.cancel();
    platform.wid.removeListener(listener);
  }

  if (!_knownLazySurfaceDevice) {
    _knownLazySurfaceDevice = true;
    AppLog.instance.i(
      'Player',
      'Marked device as lazy-surface; future bootstraps will shorten '
      'pre-open wait to ${_defaultSurfaceWaitLazy.inMilliseconds}ms',
    );
  }
  AppLog.instance.w(
    'Player',
    'Android surface not ready within ${effectiveTimeout.inMilliseconds}ms '
    '(wid=${platform.wid.value} id=${controller.id.value}), continuing anyway',
  );
  return false;
}