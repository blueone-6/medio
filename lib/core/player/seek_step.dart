/// Hold-time → seconds-per-tick curves for accelerated seeking.
///
/// Two distinct curves exist by design:
/// - [keyboardSeekStepForHold]: desktop / TV keyboard arrows (KeyRepeat).
/// - [gestureSeekStepForHold]: mobile long-press fast seek (200ms ticks).
library;

/// Keyboard: starts at 1 s per repeat and ramps up to 300 s per repeat for
/// long holds (≥12 s) so a full movie can be traversed quickly.
int keyboardSeekStepForHold(Duration held) {
  final ms = held.inMilliseconds;
  if (ms < 500) return 1;
  if (ms < 1000) return 5;
  if (ms < 2000) return 15;
  if (ms < 4000) return 30;
  if (ms < 7000) return 60;
  if (ms < 12000) return 150;
  return 300;
}

/// Mobile gesture long-press: gentler curve, capped at 60 s per tick so a
/// thumb cannot overshoot as violently as the keyboard ramp.
int gestureSeekStepForHold(Duration held) {
  final ms = held.inMilliseconds;
  if (ms < 500) return 2;
  if (ms < 1000) return 5;
  if (ms < 2000) return 10;
  if (ms < 4000) return 20;
  if (ms < 7000) return 40;
  return 60;
}
