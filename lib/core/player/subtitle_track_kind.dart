import 'package:media_kit/media_kit.dart';

/// Whether mpv in this client can select [track] via `sid` (probe: subrip OK, PGS fails).
bool isTextMuxedSubtitle(SubtitleTrack track) {
  final c = (track.codec ?? '').toLowerCase();
  if (track.uri || track.data) return false;
  if (track.id == 'auto' || track.id == 'no') return false;
  return c.contains('subrip') ||
      c.contains('ass') ||
      c.contains('ssa') ||
      c.contains('mov_text') ||
      c.contains('text');
}

bool isPgsMuxedSubtitle(SubtitleTrack track) {
  final c = (track.codec ?? '').toLowerCase();
  return c.contains('pgs') || c.contains('hdmv_pgs');
}

List<SubtitleTrack> playableMuxedSubtitles(Iterable<SubtitleTrack> tracks) {
  return tracks
      .where((t) => t.id != 'auto' && t.id != 'no' && !t.uri && !t.data)
      .where(isTextMuxedSubtitle)
      .toList();
}

List<SubtitleTrack> pgsMuxedSubtitles(Iterable<SubtitleTrack> tracks) {
  return tracks
      .where((t) => t.id != 'auto' && t.id != 'no' && !t.uri && !t.data)
      .where(isPgsMuxedSubtitle)
      .toList();
}
