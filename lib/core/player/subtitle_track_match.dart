import 'package:collection/collection.dart';
import 'package:media_kit/media_kit.dart';

import '../../models/emby/emby_subtitle_option.dart';
import 'subtitle_track_kind.dart';

/// Picks a muxed [SubtitleTrack] for [option] (Emby menu label ↔ mpv title/lang).
SubtitleTrack? matchMuxedSubtitleTrack(
  List<SubtitleTrack> tracks,
  EmbySubtitleOption option,
) {
  if (tracks.isEmpty) return null;

  final label = option.label;
  final lower = label.toLowerCase();

  if (label.contains('English') || lower.contains('eng')) {
    for (final t in tracks) {
      if (t.language == 'en' || t.language == 'eng') return t;
      if ((t.title ?? '').toLowerCase().contains('eng')) return t;
    }
  }

  final textPool = tracks.where(isTextMuxedSubtitle).toList();

  if (lower.contains('traditional') || lower.contains('chinese traditional')) {
    for (final t in textPool) {
      if (t.title == 'Traditional') return t;
    }
    final trad = textPool
        .where(
          (t) =>
              (t.title ?? '').contains('繁') || (t.title ?? '').contains('繁體'),
        )
        .toList();
    if (trad.length == 1) return trad.first;
    if (trad.isNotEmpty) return trad.first;
    final tradAll = tracks
        .where(
          (t) =>
              t.title == 'Traditional' ||
              (t.title ?? '').contains('繁') ||
              (t.title ?? '').contains('繁體'),
        )
        .toList();
    if (tradAll.length == 1) return tradAll.first;
    if (tradAll.isNotEmpty) return tradAll.first;
  }

  if (lower.contains('simplified') || lower.contains('chinese simplified')) {
    for (final t in textPool) {
      if (t.title == 'Simplified') return t;
      if ((t.title ?? '').contains('简体')) return t;
    }
  }
  if (label.contains('简体')) {
    for (final t in tracks) {
      if (t.title == 'Simplified') return t;
      final title = t.title ?? '';
      if (isTextMuxedSubtitle(t) && title.contains('简体')) return t;
      if (!isPgsMuxedSubtitle(t) &&
          (title.contains('SDR简体') || title.contains('HDR简体'))) {
        return t;
      }
    }
  }

  if (label.contains('繁')) {
    final trad = tracks
        .where(
          (t) =>
              t.title == 'Traditional' ||
              (t.title ?? '').contains('繁') ||
              (t.title ?? '').contains('繁體'),
        )
        .toList();
    if (trad.length == 1) return trad.first;
    if (trad.isNotEmpty) return trad.first;
  }

  // Avoid mapping every "默认" PGSSUB entry to the first mpv default flag track.
  if ((label.contains('默认') || lower.contains('default')) &&
      !option.isBitmapSubtitle) {
    return tracks.where((t) => t.isDefault == true).firstOrNull;
  }

  for (final t in tracks) {
    if (t.title != null && t.title!.isNotEmpty && t.title == label) {
      return t;
    }
  }

  if (label.isNotEmpty) {
    for (final t in tracks) {
      final title = t.title ?? '';
      if (title.isNotEmpty && title.contains(label)) return t;
      if (label.contains(title) && title.length >= 2) return t;
    }
  }

  return null;
}

/// Text muxed track to use when a PGS [option] cannot be decoded.
SubtitleTrack? textMuxedFallbackForPgs(
  List<SubtitleTrack> allMuxed,
  EmbySubtitleOption option,
) {
  final text = playableMuxedSubtitles(allMuxed);
  if (text.isEmpty) return null;
  return matchMuxedSubtitleTrack(text, option) ??
      pickDefaultTextTrack(text) ??
      text.firstOrNull;
}

SubtitleTrack? pickDefaultTextTrack(List<SubtitleTrack> playable) {
  for (final t in playable) {
    final title = t.title ?? '';
    if (title.contains('简体') || title == 'Simplified') return t;
  }
  for (final t in playable) {
    if (t.isDefault == true) return t;
  }
  return playable.firstOrNull;
}
