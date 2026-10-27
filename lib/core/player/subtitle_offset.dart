/// Subtitle timing offset ("字幕偏移"), ms.
///
/// Positive values show subtitles later, negative earlier — the same sign
/// convention as mpv's `sub-delay` and media3's cue timestamp shift.
library;

/// Supported range, ms. ±30 s covers badly muxed sources while keeping the
/// fine (±0.1 s) and coarse (±0.5 s) stepper steps usable across the range.
const int subtitleOffsetLimitMs = 30000;

/// Clamps [ms] into the supported offset range.
int clampSubtitleOffsetMs(int ms) =>
    ms.clamp(-subtitleOffsetLimitMs, subtitleOffsetLimitMs);
