import '../../../models/emby/emby_subtitle_option.dart';

/// A text track surfaced by the ExoPlayer bridge (`getTracks`).
class ExoPlayerTrack {
  const ExoPlayerTrack({
    required this.id,
    required this.label,
    this.language,
    this.isSelected = false,
  });

  final String id;
  final String label;
  final String? language;
  final bool isSelected;

  factory ExoPlayerTrack.fromMap(Map<Object?, Object?> map) {
    return ExoPlayerTrack(
      id: map['id']?.toString() ?? '',
      label: map['label']?.toString() ?? '',
      language: map['language']?.toString(),
      isSelected: map['isSelected'] == true,
    );
  }
}

/// Whether [track] should render as the selected row in a track sheet.
///
/// [current] is the track the user picked this session; when there is none, the
/// player's own selection is used — the native catalog marks the auto-selected
/// default (`isSelected`), which the 音轨 sheet previously ignored, so no row
/// looked selected until the user picked one manually.
bool isTrackSelected(ExoPlayerTrack track, ExoPlayerTrack? current) {
  if (current != null) return current.id == track.id;
  return track.isSelected;
}

/// Audio + text tracks of the currently prepared media item.
class ExoTrackCatalog {
  const ExoTrackCatalog({
    this.audio = const [],
    this.text = const [],
    this.unsupportedAudio = const [],
  });

  final List<ExoPlayerTrack> audio;
  final List<ExoPlayerTrack> text;

  /// Audio tracks the container exposes but this device cannot decode (e.g. EAC3
  /// on a phone with no Dolby decoder). Reported so the 音轨 sheet can explain
  /// the silence instead of just showing an empty list.
  final List<ExoPlayerTrack> unsupportedAudio;

  factory ExoTrackCatalog.fromMap(Map<Object?, Object?>? map) {
    if (map == null) return const ExoTrackCatalog();
    List<ExoPlayerTrack> parse(Object? raw) => (raw is List)
        ? raw
            .whereType<Map>()
            .map((m) => ExoPlayerTrack.fromMap(Map<Object?, Object?>.from(m)))
            .toList()
        : <ExoPlayerTrack>[];
    return ExoTrackCatalog(
      audio: parse(map['audio']),
      text: parse(map['text']),
      unsupportedAudio: parse(map['unsupportedAudio']),
    );
  }
}

/// Which subtitle should be active and how it is rendered.
sealed class ExoSubtitleTarget {
  const ExoSubtitleTarget();
}

/// Subtitles off (native text tracks disabled, no overlay cues).
class ExoSubtitleOff extends ExoSubtitleTarget {
  const ExoSubtitleOff();
}

/// External Emby subtitle rendered by the Flutter overlay.
class ExoSubtitleExternal extends ExoSubtitleTarget {
  const ExoSubtitleExternal(this.option);

  final EmbySubtitleOption option;
}

/// Muxed text track rendered by ExoPlayer's native subtitle surface.
class ExoSubtitleMuxed extends ExoSubtitleTarget {
  const ExoSubtitleMuxed(this.track);

  final ExoPlayerTrack track;
}

/// Stable persistence key for a muxed track: native `id`s are only valid for
/// the current preparation, so key by language + label instead.
String muxedTrackPreferenceKey(ExoPlayerTrack track) {
  final lang = track.language ?? '';
  final label = track.label;
  return 'exomux:$lang|$label';
}

/// Matches a persisted `exomux:` key against the current track list.
ExoPlayerTrack? matchMuxedTrack(
  List<ExoPlayerTrack> tracks,
  String savedKey,
) {
  if (!savedKey.startsWith('exomux:')) return null;
  for (final t in tracks) {
    if (muxedTrackPreferenceKey(t) == savedKey) return t;
  }
  return null;
}

/// Resolves the subtitle to activate when a new item starts playing.
///
/// [saved] is the persisted per-item selection (`no` / `auto` / `emby:{index}`
/// / `track:{key}`). Falls back to Emby's preferred subtitle (default or
/// forced, plain text first) when the saved entry no longer resolves.
ExoSubtitleTarget resolveInitialSubtitleSelection({
  required String? saved,
  required List<EmbySubtitleOption> embySubtitles,
  required List<ExoPlayerTrack> nativeTextTracks,
}) {
  if (saved == 'no') return const ExoSubtitleOff();

  if (saved != null && saved.startsWith('emby:')) {
    final index = int.tryParse(saved.substring('emby:'.length));
    if (index != null) {
      for (final t in embySubtitles) {
        if (t.index == index && t.isExternal && t.isExoPlayableTextSubtitle) {
          return ExoSubtitleExternal(t);
        }
      }
    }
    // Saved external track vanished (new transcode/replace) — fall through to
    // the default resolution below.
  }

  if (saved != null && saved.startsWith('track:')) {
    final track = matchMuxedTrack(nativeTextTracks, saved.substring('track:'.length));
    if (track != null) return ExoSubtitleMuxed(track);
  }

  // auto / first run: an external file first (a real fetcher — supports both
  // delay directions), then the default/forced embedded track through the
  // native muxed path, since Emby's subtitle API cannot serve embedded tracks.
  final preferred = _preferredExternal(embySubtitles);
  if (preferred != null) return ExoSubtitleExternal(preferred);

  final flagged = _flaggedStream(embySubtitles);
  if (flagged != null && !flagged.isExternal) {
    final muxed = matchNativeTextTrack(nativeTextTracks, flagged);
    if (muxed != null) return ExoSubtitleMuxed(muxed);
  }

  final muxedDefault = _preferredMuxed(embySubtitles, nativeTextTracks);
  if (muxedDefault != null) return ExoSubtitleMuxed(muxedDefault);

  // Last resort: an embedded stream with no native counterpart — let Emby try
  // to extract it rather than showing nothing.
  final fallback = _anyPlayableTextSubtitle(embySubtitles);
  if (fallback != null) return ExoSubtitleExternal(fallback);

  return const ExoSubtitleOff();
}

/// First subtitle stream flagged default/forced by the server.
EmbySubtitleOption? _flaggedStream(List<EmbySubtitleOption> subs) {
  for (final t in subs) {
    if (t.isDefault || t.isForced) return t;
  }
  return null;
}

EmbySubtitleOption? _anyPlayableTextSubtitle(List<EmbySubtitleOption> subs) {
  for (final t in subs) {
    if (t.isExoPlayableTextSubtitle) return t;
  }
  return null;
}

EmbySubtitleOption? _preferredExternal(List<EmbySubtitleOption> subs) {
  EmbySubtitleOption? ranked;
  int rank(EmbySubtitleOption t) {
    if (t.isDefault || t.isForced) return 0;
    final f = t.format.toLowerCase();
    if (f == 'srt' || f == 'sub') return 1;
    if (f == 'vtt') return 2;
    return 3;
  }

  for (final t in subs) {
    // Embedded (muxed) streams are rendered natively straight from the
    // container. Emby's subtitle API cannot serve them — the endpoint returns
    // nothing for an embedded track — so treating the embedded "default
    // SUBRIP" as an external file left the default subtitle blank while the
    // real external SRT worked.
    if (!t.isExternal) continue;
    if (!t.isExoPlayableTextSubtitle) continue;
    if (ranked == null || rank(t) < rank(ranked)) ranked = t;
  }
  return ranked;
}

/// Emby subtitle streams the 外挂 list may offer, i.e. things the app fetches.
///
/// Real external files always qualify. A stream the server reports as embedded
/// only qualifies when the container exposes no subtitle track at all — then
/// the Emby API is the only way to show it. When the container does expose
/// tracks they are listed under 内嵌, and duplicating them here only invites a
/// tap that cannot work (the API returns nothing for embedded tracks).
List<EmbySubtitleOption> externalSubtitleChoices({
  required List<EmbySubtitleOption> embySubtitles,
  required List<ExoPlayerTrack> nativeTextTracks,
}) {
  final hasNative = nativeTextTracks.isNotEmpty;
  return embySubtitles
      .where(
        (s) => s.isExoPlayableTextSubtitle && (s.isExternal || !hasNative),
      )
      .toList();
}

/// Picks the native track matching Emby's default/forced muxed subtitle.
ExoPlayerTrack? _preferredMuxed(
  List<EmbySubtitleOption> embySubtitles,
  List<ExoPlayerTrack> nativeTextTracks,
) {
  EmbySubtitleOption? preferred;
  for (final s in embySubtitles) {
    if (s.isExternal) continue;
    if (s.isDefault || s.isForced) {
      preferred = s;
      break;
    }
  }
  if (preferred != null) {
    final byLanguage = matchNativeTextTrack(nativeTextTracks, preferred);
    if (byLanguage != null) return byLanguage;
  }
  // No Emby default flag: fall back to the first supported native text track
  // when the file only carries one (multi-language files stay off — the user
  // picks explicitly, matching TV behavior).
  if (preferred == null && nativeTextTracks.length == 1) {
    return nativeTextTracks.single;
  }
  return null;
}

/// Native text track matching [option] (by language first, then by label).
///
/// Used both to pick the container track for an embedded Emby stream and to
/// tell which Emby streams the 内嵌 list already covers. Language codes differ
/// between the server and the container (Emby reports the Matroska
/// bibliographic code, e.g. `chi`, while media3 may expose the terminology
/// code, e.g. `zho`), so compare normalised codes.
ExoPlayerTrack? matchNativeTextTrack(
  List<ExoPlayerTrack> tracks,
  EmbySubtitleOption option,
) {
  final label = option.label.toLowerCase();
  final lang = normaliseSubtitleLanguage(option.language);
  for (final t in tracks) {
    final tl = t.label.toLowerCase();
    final tLang = normaliseSubtitleLanguage(t.language);
    if (lang != null && tLang != null && lang == tLang) return t;
    if (label.isNotEmpty && tl.contains(label)) return t;
  }
  return null;
}

/// Maps the language codes Emby and media3 use for the same language onto one
/// value (`chi`/`zho`/`zh` → `zh`, `eng`/`en` → `en`, …).
String? normaliseSubtitleLanguage(String? raw) {
  final lang = raw?.trim().toLowerCase().replaceAll('_', '-');
  if (lang == null || lang.isEmpty) return null;
  final base = lang.split('-').first;
  switch (base) {
    case 'zh':
    case 'chi':
    case 'zho':
    case 'cmn':
    case 'chs':
    case 'cht':
      return 'zh';
    case 'en':
    case 'eng':
      return 'en';
    case 'ja':
    case 'jpn':
      return 'ja';
    case 'ko':
    case 'kor':
      return 'ko';
    default:
      return base;
  }
}
