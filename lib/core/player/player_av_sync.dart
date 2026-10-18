/// Constant audio/video offset compensation ("音画同步").
///
/// A player cannot know the physical latency of its own video pipeline (decoder
/// + surface + display) nor of the audio output device, so a *constant* offset
/// — most visible with software-decoded Dolby/DTS remuxes, where the audio can
/// lead the picture by up to a second — has to be corrected by hand, exactly
/// like mpv's `--audio-delay` or VLC's "audio track synchronization". It is
/// remembered per media item (see the memory helpers below), because only a few
/// files carry such an offset and a global setting would drag every other video
/// along.
///
/// Sign convention follows mpv: positive = the audio is heard later relative to
/// the picture. The Android ExoPlayer path implements it by moving the clock the
/// video renderer syncs to (the audio clock) forward by the same amount, which
/// advances the picture; the mpv/desktop path sets `audio-delay` directly.
library;

import 'dart:convert';

/// Compensation range, ms. ±2 s covers the field reports (a few hundred ms up to
/// ~1 s) while keeping a misdrag harmless.
const int audioDelayMinMs = -2000;
const int audioDelayMaxMs = 2000;

/// Preset step for the menu rows, ms.
const int audioDelayStepMs = 100;

/// Clamps [ms] into the supported compensation range.
int clampAudioDelayMs(int ms) => ms.clamp(audioDelayMinMs, audioDelayMaxMs);

/// `+0.3s` / `-0.1s` / `0.0s`, one decimal.
String formatAudioDelayMs(int ms) {
  final seconds = ms / 1000.0;
  final sign = ms > 0 ? '+' : (ms < 0 ? '-' : '');
  return '$sign${seconds.abs().toStringAsFixed(1)}s';
}

/// Human label for the menu section title: what the setting does to the sound.
String describeAudioDelay(int ms) {
  if (ms == 0) return '声音与画面已对齐';
  final dir = ms > 0 ? '声音延后' : '声音提前';
  return '$dir ${(ms.abs() / 1000.0).toStringAsFixed(1)}s';
}

/// mpv `audio-delay` value in seconds for [ms].
String mpvAudioDelaySeconds(int ms) => (ms / 1000.0).toStringAsFixed(3);

// ── Per-source memory ──
//
// Only a handful of files carry their own audio offset, so a global setting
// would drag every other video along. The calibration is therefore remembered
// per media item (`itemId`), defaulting to 0 — i.e. no compensation — for
// everything the user has not touched.

/// Entries kept. Insertion order is most-recent-last, so the oldest are dropped.
const int avDelayMemoryMaxEntries = 50;

/// Decodes the stored `itemId → ms` memory, ignoring malformed payloads.
Map<String, int> decodeAvDelayMemory(String? raw) {
  if (raw == null || raw.isEmpty) return <String, int>{};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return <String, int>{};
    final out = <String, int>{};
    decoded.forEach((key, value) {
      final itemId = key?.toString() ?? '';
      if (itemId.isEmpty || value is! num) return;
      final ms = clampAudioDelayMs(value.toInt());
      if (ms != 0) out[itemId] = ms;
    });
    return out;
  } catch (_) {
    return <String, int>{};
  }
}

/// Encodes [memory] for storage (empty memory is written as an empty object).
String encodeAvDelayMemory(Map<String, int> memory) => jsonEncode(memory);

/// Returns [memory] with [itemId] set to [ms] (clamped, pruned).
///
/// A clamped value of 0 removes the entry: "no compensation" is the default, so
/// the memory only ever holds the few files that actually need one.
Map<String, int> avDelayMemoryWith(
  Map<String, int> memory,
  String itemId,
  int ms,
) {
  final next = Map<String, int>.from(memory);
  next.remove(itemId);
  final clamped = clampAudioDelayMs(ms);
  if (clamped != 0 && itemId.isNotEmpty) next[itemId] = clamped;
  while (next.length > avDelayMemoryMaxEntries) {
    next.remove(next.keys.first);
  }
  return next;
}
