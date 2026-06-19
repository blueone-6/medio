import 'package:media_kit/media_kit.dart';

import 'subtitle_track_kind.dart';

/// How subtitles are drawn with [PlayerConfiguration.libass] = true.
enum SubtitleRenderMode {
  /// Muxed text: `sub-ass=no`, Flutter [SubtitleView] via `sub-text` (sid changes do not stall VO).
  flutterOverlay,

  /// External / `sub-add` — libass composited (smooth for this client).
  mpvLibass,

  /// PGSSUB bitmap — libass + texture.
  mpvBitmap,

  off,
}

SubtitleRenderMode subtitleRenderModeForTrack(SubtitleTrack track) {
  if (track.id == 'no' || track.id == 'auto') return SubtitleRenderMode.off;
  if (isPgsMuxedSubtitle(track)) return SubtitleRenderMode.mpvBitmap;
  if (track.uri || track.data) return SubtitleRenderMode.mpvLibass;
  if (isTextMuxedSubtitle(track)) return SubtitleRenderMode.flutterOverlay;
  return SubtitleRenderMode.mpvLibass;
}

/// Flutter overlay for muxed text; PGS/external stay on mpv texture / sub-add.
bool shouldUseFlutterSubtitleOverlay(SubtitleTrack track) {
  if (track.id == 'no' || track.id == 'auto') return false;
  return subtitleRenderModeForTrack(track) == SubtitleRenderMode.flutterOverlay;
}
