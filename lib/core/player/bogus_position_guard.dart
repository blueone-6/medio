import 'playback_resume.dart';

/// Outcome of the fresh-playback bogus-position check.
enum FreshPositionVerdict {
  /// The position is confirmed legitimate — the caller may latch
  /// "legitimate seen" and disarm the guard permanently.
  legitimate,

  /// The position is not bogus, but it does not confirm real playback either
  /// (e.g. a near-end position within a resume window). Do not latch.
  plausible,

  /// The position matches the MKV SeekHead artifact (or is otherwise
  /// impossible for the elapsed wall-clock time) — treat as bogus.
  bogus,
}

/// Pure decision core of the bogus-position guard.
///
/// Root cause being guarded: mpv's MKV demuxer reads the SeekHead/Duration at
/// EOF to determine the file structure. On a cold CDN cache the byte-range
/// seek back to 0 (or to the resume target) may fail, leaving mpv reporting
/// position ≈ duration (or a mid-file SeekHead offset) while no real playback
/// happens. Reporting that position would mark the episode as watched.
///
/// All timestamps are passed as *ages* (durations relative to now) so tests
/// can drive the logic without a fake clock.
FreshPositionVerdict classifyFreshPlaybackPosition({
  required Duration pos,
  required Duration duration,
  required Duration elapsed,
  required Duration? resumeTarget,
  Duration? userSeekTarget,
  Duration? userSeekAge,
}) {
  // A position landing on a recent user seek is legitimate.
  if (userSeekTarget != null &&
      userSeekAge != null &&
      userSeekAge <= const Duration(seconds: 15) &&
      (pos - userSeekTarget).abs() <= const Duration(seconds: 5)) {
    return FreshPositionVerdict.legitimate;
  }

  // A position near the resume target (±60s) is legitimate — mpv
  // legitimately jumps there via `--start`.
  if (resumeTarget != null &&
      pos > const Duration(milliseconds: 500) &&
      (pos - resumeTarget).abs() <= const Duration(seconds: 60)) {
    return FreshPositionVerdict.legitimate;
  }

  // A position that is non-trivial, within the playable range, and consistent
  // with elapsed wall-clock time (at up to 2x speed) is legitimate. The 2s
  // threshold avoids mistaking the startup transient and the guard's own
  // seek(0) for confirmed real playback.
  if (pos >= const Duration(seconds: 2) &&
      (duration <= const Duration(seconds: 30) || pos < duration * 0.85) &&
      pos <= _maxPlausibleContent(elapsed)) {
    return FreshPositionVerdict.legitimate;
  }

  if (duration > const Duration(seconds: 30)) {
    // Position near the end (>= 90% of duration) is bogus unless it is a
    // resume session near the resume target (that case is merely plausible:
    // near-end positions must not latch the guard).
    if (pos >= duration * 0.9) {
      if (resumeTarget != null &&
          (pos - resumeTarget).abs() <= const Duration(seconds: 60)) {
        return FreshPositionVerdict.plausible;
      }
      return FreshPositionVerdict.bogus;
    }
    // Mid-file but far beyond what could have been played in the elapsed
    // wall-clock time (at 2x speed): the SeekHead artifact at an offset.
    if (pos > _maxPlausibleContent(elapsed)) {
      return FreshPositionVerdict.bogus;
    }
    return FreshPositionVerdict.plausible;
  }

  // Duration unknown (0 or not yet determined) — resume-target tolerance
  // then wall-clock plausibility.
  if (resumeTarget != null &&
      (pos - resumeTarget).abs() <= const Duration(seconds: 60)) {
    return FreshPositionVerdict.plausible;
  }
  return pos > _maxPlausibleContent(elapsed)
      ? FreshPositionVerdict.bogus
      : FreshPositionVerdict.plausible;
}

/// At 2x rate, T of wall-clock produces at most ~2T+3s of content
/// (3s buffer for startup jitter).
Duration _maxPlausibleContent(Duration elapsed) =>
    Duration(milliseconds: elapsed.inMilliseconds * 2 + 3000);

/// If [pos] is an implausible jump to ≈duration — i.e. the last confirmed
/// mid-file position was not near the end, yet [pos] is at/near the end far
/// faster than real (≈1x) playback could have covered that content distance —
/// returns that confirmed position as the recovery target. Returns null when
/// the position is a plausible result of actual playback.
///
/// Real playback covers ~1x, so wall-time ≈ content-time; a spurious EOF
/// (CDN byte-range failure during resume/open) has wall-time << content-time.
/// Requiring a >10s content gap keeps the genuine end-of-movie case (last
/// confirmed position within seconds of the end) from being misread.
Duration? implausibleEndJumpTarget({
  required Duration pos,
  required Duration duration,
  required Duration? confirmedPos,
  required Duration? confirmedAge,
  Duration? userSeekTarget,
  Duration? userSeekAge,
}) {
  if (userSeekTarget != null &&
      userSeekAge != null &&
      userSeekAge <= const Duration(seconds: 15) &&
      (pos - userSeekTarget).abs() <= const Duration(seconds: 5)) {
    return null;
  }

  if (confirmedPos == null || confirmedAge == null) return null;
  if (isPlaybackNearEnd(confirmedPos, duration)) return null;
  final contentGap = pos - confirmedPos;
  if (contentGap <= const Duration(seconds: 10)) return null;
  if (confirmedAge >= contentGap - const Duration(seconds: 3)) return null;
  return confirmedPos;
}
