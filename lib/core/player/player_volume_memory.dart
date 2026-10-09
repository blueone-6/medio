/// Volume persisted across playback sessions (absorbed from Kazumi's
/// remembered-volume behavior).
///
/// Zero (muted) is transient: persisting it would resurrect a muted state the
/// user may not want, so exiting while muted keeps the last audible level.
library;

/// The volume worth remembering, or null when [volume] must not be persisted.
double? volumeToPersist(double volume) {
  if (volume.isNaN || volume <= 0) return null;
  if (volume > 100) return 100;
  return volume;
}

/// Volume to apply on a fresh [Player]: the persisted level when present and
/// audible, otherwise mpv's default (100).
double restorePlayerVolume(double? persisted) {
  if (persisted == null || !persisted.isFinite || persisted <= 0) return 100;
  if (persisted > 100) return 100;
  return persisted;
}
