/// Verifies that a user seek actually landed in the player.
///
/// The check runs [elapsed] wall-clock after the seek was requested, so the
/// comparison must use a *window*, not a fixed tolerance around the target:
/// a seek that landed at `target` keeps playing, and after [elapsed] seconds
/// (at up to 2x rate) the reported position is naturally
/// `target .. target + 2*elapsed`. Comparing the live position against the
/// bare target with a ±2 s tolerance misreads every successful seek that
/// played for more than ~2 s as "did not land" (observed in production logs:
/// seek→43 s, 5 s later position 47 s → false re-open).
///
/// A rejected seek stays at the pre-seek position, which lies far outside
/// the window (for any seek distance larger than the window itself).
library;

/// Whether [pos] is consistent with a seek to [target] that landed and kept
/// playing for [elapsedSinceSeek].
///
/// [tolerance] absorbs keyframe-granularity landing offsets and timer jitter.
bool userSeekLanded({
  required Duration pos,
  required Duration target,
  required Duration elapsedSinceSeek,
  Duration tolerance = const Duration(seconds: 2),
}) {
  final lower = target - tolerance;
  final upper = target + elapsedSinceSeek * 2 + tolerance;
  return pos >= lower && pos <= upper;
}
