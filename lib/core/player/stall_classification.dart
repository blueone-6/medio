/// Classifies why the playback position stopped advancing.
///
/// mpv leaves `playing == false` in *both* a deliberate user pause and a
/// silent upstream stall. A deliberate pause keeps the demuxer cache healthy
/// (`buffering == false`), but a CDN edge that drops the connection mid-file —
/// observed with Quark netdisk strm sources ("Connection closed while
/// receiving data") — also drains the cache and leaves mpv sitting in a
/// paused-like state.
///
/// The previous heuristic ("not playing + not buffering ⇒ the user paused")
/// therefore misread every silent stall as a pause: the detector re-armed
/// without recovering, and the picture stayed frozen until the user gave up.
/// The only reliable discriminator is whether the pause was user-initiated.
library;

/// Outcome of inspecting a playback position that may have stopped advancing.
enum StalledPlaybackKind {
  /// Position advanced by at least the threshold — playback is healthy.
  advancing,

  /// mpv is paused because the user asked it to; leave it alone.
  userPaused,

  /// Playback froze — the cache is empty, or mpv is in a paused-like state the
  /// user never requested. Trigger stall recovery.
  cdnStall,
}

/// Classifies the playback state after the stall detector's check interval.
///
/// [position] and [basePosition] are the current and detector-arm positions;
/// [playing] / [buffering] mirror mpv's flags; [userPaused] is true only when
/// the app itself paused playback on the user's behalf (play/pause toggle,
/// app backgrounding). A stall that mpv reports as paused is recovered unless
/// that pause was user-initiated.
StalledPlaybackKind classifyStalledPlayback({
  required Duration position,
  required Duration basePosition,
  required bool playing,
  required bool buffering,
  required bool userPaused,
  Duration advanceThreshold = const Duration(milliseconds: 100),
}) {
  if (position - basePosition >= advanceThreshold) {
    return StalledPlaybackKind.advancing;
  }
  // A pause the user asked for is authoritative: hold the position still
  // regardless of what the cache flags say, so recovery never fights a
  // deliberate pause (including app backgrounding).
  if (userPaused) return StalledPlaybackKind.userPaused;
  // Position is not advancing and the user never paused. An empty cache is
  // unambiguously a stall.
  if (buffering) return StalledPlaybackKind.cdnStall;
  // Cache looks healthy but mpv still claims to be playing while the position
  // is frozen — the stream has stalled regardless of what the flags say.
  if (playing) return StalledPlaybackKind.cdnStall;
  // Paused-like without a user pause: a silent stall the detector must recover
  // from.
  return StalledPlaybackKind.cdnStall;
}
