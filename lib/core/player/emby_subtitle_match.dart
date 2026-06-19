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
