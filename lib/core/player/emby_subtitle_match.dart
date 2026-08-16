import 'package:media_kit/media_kit.dart';

import '../../models/emby/emby_subtitle_option.dart';
import 'subtitle_track_kind.dart';

/// Whether [track] is the muxed stream for [option] (menu highlight; approximate).
bool muxedTrackMatchesEmbyOption(SubtitleTrack track, EmbySubtitleOption option) {
  if (option.isExternal) return false;
  if (track.uri || track.data) return false;
  if (track.id == 'auto' || track.id == 'no') return false;
  return _labelMatches(track, option);
}

/// Whether [track] is the active external subtitle for [option].
bool subtitleTrackMatchesEmbyOption(SubtitleTrack t, EmbySubtitleOption o) {
  if (!o.isExternal) return false;
  if (t.id == 'auto' || t.id == 'no') return false;
  if (t.id == o.streamUrl) return true;
  if (t.id == o.selectionId) return true;
  if (t.title != null && t.title!.isNotEmpty && t.title == o.label) {
    return true;
  }
  return false;
}

/// Resolves which Emby option the currently active [track] corresponds to.
///
/// Prefers an exact mpv `sid` match via [indexTracks] (Emby index → resolved
/// muxed track); falls back to label matching when the map isn't ready.
/// Returns null when the active track has no Emby counterpart (e.g. a native
/// muxed track with no Emby metadata).
EmbySubtitleOption? embyOptionForSubtitleTrack(
  SubtitleTrack track,
  Iterable<EmbySubtitleOption> options,
  Map<int, SubtitleTrack>? indexTracks,
) {
  if (track.id == 'auto' || track.id == 'no') return null;
  if (track.uri || track.data) {
    for (final o in options) {
      if (subtitleTrackMatchesEmbyOption(track, o)) return o;
    }
    return null;
  }
  for (final o in options) {
    if (o.isExternal) continue;
    final resolved = indexTracks?[o.index];
    if (resolved != null && resolved.id == track.id) return o;
    if (resolved == null && muxedTrackMatchesEmbyOption(track, o)) return o;
  }
  return null;
}

/// Resolves the selected Emby option directly from mpv's raw `sid`.
///
/// PGS selection may be written with a raw mpv command while media_kit's
/// high-level track state still contains the previous text track. The menu must
/// trust the actual mpv `sid` when it can be mapped back to an Emby stream.
EmbySubtitleOption? embyOptionForMpvSid(
  String? sid,
  Iterable<EmbySubtitleOption> options,
  Map<int, SubtitleTrack>? indexTracks,
) {
  if (sid == null || sid.isEmpty || sid == 'no' || sid == 'auto') return null;
  for (final o in options) {
    final track = indexTracks?[o.index];
    if (track != null && track.id == sid) return o;
  }
  return null;
}

bool _labelMatches(SubtitleTrack track, EmbySubtitleOption option) {
  if (option.isBitmapSubtitle || option.format == 'pgs') {
    if (!isPgsMuxedSubtitle(track)) return false;
  } else {
    if (isPgsMuxedSubtitle(track)) return false;
    if (!isTextMuxedSubtitle(track)) return false;
  }

  final label = option.label;
  final title = track.title ?? '';
  if (title.isNotEmpty && title == label) return true;
  if (label.contains('简体') &&
      (title == 'Simplified' || title.contains('简体'))) {
    return true;
  }
  if (label.contains('繁') &&
      (title == 'Traditional' || title.contains('繁'))) {
    return true;
  }
  if (label.contains('English') && (track.language == 'en' || track.language == 'eng')) {
    return true;
  }
  return false;
}

List<EmbySubtitleOption> uniqueEmbeddedEmbySubtitles(
  Iterable<EmbySubtitleOption> options,
) {
  final seen = <int>{};
  final out = <EmbySubtitleOption>[];
  for (final o in options) {
    if (o.isExternal) continue;
    if (seen.add(o.index)) out.add(o);
  }
  out.sort((a, b) {
    final textFirst =
        (a.isBitmapSubtitle ? 1 : 0).compareTo(b.isBitmapSubtitle ? 1 : 0);
    if (textFirst != 0) return textFirst;
    return a.index.compareTo(b.index);
  });
  return out;
}

List<EmbySubtitleOption> externalEmbySubtitles(
  Iterable<EmbySubtitleOption> options,
) {
  return options.where((o) => o.isExternal).toList()
    ..sort((a, b) => a.index.compareTo(b.index));
}

/// Sync fallback when async `track-list` map is not ready (keeps muxed titles in menu).
Map<int, SubtitleTrack> fallbackEmbyIndexTrackMap(
  Tracks tracks,
  Iterable<EmbySubtitleOption> options,
) {
  final map = <int, SubtitleTrack>{};
  final muxed = tracks.subtitle
      .where((t) => t.id != 'auto' && t.id != 'no' && !t.uri && !t.data)
      .toList();
  for (final o in options) {
    if (o.isExternal) continue;
    for (final t in muxed) {
      if (muxedTrackMatchesEmbyOption(t, o)) {
        map[o.index] = t;
        break;
      }
    }
  }
  return map;
}
