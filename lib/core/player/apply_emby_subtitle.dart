import 'dart:async';
import 'dart:io';

import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;

import '../logging/app_log.dart';
import '../../models/emby/emby_subtitle_option.dart';
import '../../services/emby_service.dart';
import 'player_subtitle_visibility.dart';
import 'subtitle_emby_index.dart';
import 'subtitle_switch_queue.dart';
import 'subtitle_track_kind.dart';
import 'subtitle_track_match.dart';

/// Worst-case retry budget for embedded muxed subtitle activation. mpv typically
/// populates `player.state.tracks.subtitle` within 300–600 ms on real Android
/// devices once the demuxer finishes scanning; 12 × 80 ms = 960 ms keeps the
/// failure path under a second while still covering slow files. (Was 25 × 80
/// ms = 2 s — the longer budget never recovered the hard-fail case anyway and
/// just delayed visible failure feedback.)
const _embeddedRetryAttempts = 12;
const _embeddedRetryDelay = Duration(milliseconds: 80);

/// When the caller knows the file has zero muxed subtitle tracks (from
/// Emby's `MediaStreams`), pass `expectedMuxedTracks: 0` to skip the retry
/// loop entirely — there is no muxed track to wait for.
Future<bool> applyEmbySubtitle({
  required Player player,
  required EmbySubtitleOption option,
  required EmbyService emby,
  required int generation,
  SubtitleTrack? resolvedMuxed,
  int? expectedMuxedTracks,
}) async {
  AppLog.instance.d(
    'Subtitle',
    'apply index=${option.index} external=${option.isExternal} '
        'format=${option.format} label=${option.label}',
  );

  if (!SubtitleSwitchQueue.isCurrent(generation)) {
    throw SubtitleSwitchCancelled();
  }

  if (option.isExternal) {
    return _applyExternalSubtitle(
      player: player,
      option: option,
      emby: emby,
      generation: generation,
    );
  }

  // Fast path: file is known to have zero muxed subtitles, so the retry loop
  // would never find a match. Avoids wasting ~1 s and spamming the log with
  // "muxed tracks not ready" attempts when the file is sub-less remux.
  if (expectedMuxedTracks != null && expectedMuxedTracks <= 0) {
    AppLog.instance.w(
      'Subtitle',
      'embedded skipped — file has no muxed subtitles '
      '(index=${option.index} label=${option.label})',
    );
    return false;
  }

  for (var attempt = 0; attempt < _embeddedRetryAttempts; attempt++) {
    if (!SubtitleSwitchQueue.isCurrent(generation)) {
      throw SubtitleSwitchCancelled();
    }

    final muxed = _muxedTracks(player);
    if (muxed.isEmpty) {
      AppLog.instance.d(
        'Subtitle',
        'muxed tracks not ready attempt=$attempt index=${option.index}',
      );
      await Future<void>.delayed(_embeddedRetryDelay);
      continue;
    }

    SubtitleTrack? matched = resolvedMuxed;
    if (matched != null && !_muxedContains(muxed, matched)) {
      matched = null;
    }

    if (matched == null) {
      if (attempt == 0 || attempt == 4) {
        invalidateMpvSidIndexCache(player);
      }
      final sidMap = await mpvSidByEmbyStreamIndex(player);
      matched = _resolveMuxedTrack(
        muxed: muxed,
        option: option,
        sidMap: sidMap,
      );
    }

    if (matched == null) {
      if (attempt == 0 || attempt == _embeddedRetryAttempts - 1) {
        AppLog.instance.w(
          'Subtitle',
          'no muxed match index=${option.index} label=${option.label}',
        );
      }
      await Future<void>.delayed(_embeddedRetryDelay);
      continue;
    }

    final ok = await SubtitleSwitchQueue.withMpv(
      () => _activateResolvedMuxed(
        player: player,
        option: option,
        generation: generation,
        matched: matched!,
        allMuxed: muxed,
      ),
    );
    if (ok) {
      AppLog.instance.i(
        'Subtitle',
        'embedded PGS OK index=${option.index} mpvSid=${await player.mpvSubtitleId()}',
      );
      return true;
    }

    await Future<void>.delayed(_embeddedRetryDelay);
  }

  AppLog.instance.w(
    'Subtitle',
    'embedded failed after retries index=${option.index} label=${option.label}',
  );
  return false;
}

SubtitleTrack? _resolveMuxedTrack({
  required List<SubtitleTrack> muxed,
  required EmbySubtitleOption option,
  required Map<int, String> sidMap,
}) {
  final sid = sidMap[option.index];
  if (sid != null) {
    for (final t in muxed) {
      if (t.id == sid) return t;
    }
    AppLog.instance.w(
      'Subtitle',
      'sid map stale embyIndex=${option.index} mpvSid=$sid',
    );
  }

  if (option.isBitmapSubtitle || option.format == 'pgs') {
    final pgs = pgsMuxedSubtitles(muxed).toList()
      ..sort(
        (a, b) => (int.tryParse(a.id) ?? 0).compareTo(int.tryParse(b.id) ?? 0),
      );
    final pgsKeys = sidMap.entries
        .where((e) {
          for (final t in muxed) {
            if (t.id == e.value && isPgsMuxedSubtitle(t)) return true;
          }
          return false;
        })
        .map((e) => e.key)
        .toList()
      ..sort();
    final pos = pgsKeys.indexOf(option.index);
    if (pos >= 0 && pos < pgs.length) return pgs[pos];

    return matchMuxedSubtitleTrack(pgs, option);
  }

  return matchMuxedSubtitleTrack(muxed, option);
}

bool _muxedContains(List<SubtitleTrack> muxed, SubtitleTrack t) {
  for (final m in muxed) {
    if (m.id == t.id) return true;
  }
  return false;
}

Future<bool> _activateResolvedMuxed({
  required Player player,
  required EmbySubtitleOption option,
  required int generation,
  required SubtitleTrack matched,
  required List<SubtitleTrack> allMuxed,
}) async {
  if (!SubtitleSwitchQueue.isCurrent(generation)) {
    throw SubtitleSwitchCancelled();
  }

  var track = matched;

  if (option.isBitmapSubtitle || option.format == 'pgs') {
    if (!isPgsMuxedSubtitle(track)) {
      final pgs = pgsMuxedSubtitles(allMuxed);
      track = matchMuxedSubtitleTrack(pgs, option) ?? track;
    }
    if (isPgsMuxedSubtitle(track)) {
      final ok = await player.activateMuxedSubtitle(
        track,
        reason: 'applyEmby PGS index=${option.index}',
      );
      if (ok && SubtitleSwitchQueue.isCurrent(generation)) return true;
    }
    final textMatch = textMuxedFallbackForPgs(allMuxed, option);
    if (textMatch != null) {
      AppLog.instance.i(
        'Subtitle',
        'PGS→text fallback index=${option.index} → sid=${textMatch.id}',
      );
      return player.activateMuxedSubtitle(
        textMatch,
        reason: 'pgs→text index=${option.index}',
      );
    }
    return false;
  }

  if (isPgsMuxedSubtitle(track)) {
    track = textMuxedFallbackForPgs(allMuxed, option) ?? track;
  }

  if (!isPgsMuxedSubtitle(track)) {
    return player.activateMuxedTextSubtitle(
      track,
      reason: 'applyEmby text index=${option.index}',
    );
  }

  return false;
}

Future<String?> _readValidEmbySubtitleCache(EmbySubtitleOption option) async {
  final path = _embySubtitleCachePath(option);
  final file = File(path);
  if (!await file.exists()) return null;
  if (await file.length() < 8) return null;
  return path;
}

String _embySubtitleCachePath(EmbySubtitleOption option) {
  final itemId = _itemIdFromStreamUrl(option.streamUrl);
  final mediaSourceId = _mediaSourceIdFromStreamUrl(option.streamUrl);
  final ext = switch (option.format.toLowerCase()) {
    'vtt' => 'vtt',
    'ass' || 'ssa' => 'ass',
    _ => 'srt',
  };
  final dir = Directory(p.join(Directory.systemTemp.path, 'media_client_sub'));
  final key = itemId.isNotEmpty && mediaSourceId.isNotEmpty
      ? '${itemId}_${mediaSourceId}_${option.index}'
      : 'idx_${option.index}';
  return p.join(dir.path, 'emby_$key.$ext');
}

String _itemIdFromStreamUrl(String url) {
  final m = RegExp(r'/Videos/([^/]+)/').firstMatch(url);
  return m?.group(1) ?? '';
}

String _mediaSourceIdFromStreamUrl(String url) {
  final m = RegExp(r'/Videos/[^/]+/([^/]+)/Subtitles/').firstMatch(url);
  return m?.group(1) ?? '';
}

Future<bool> _applyExternalSubtitle({
  required Player player,
  required EmbySubtitleOption option,
  required EmbyService emby,
  required int generation,
}) async {
  final cachedPath = await _readValidEmbySubtitleCache(option);
  if (cachedPath != null) {
    AppLog.instance.d('Subtitle', 'disk cache hit index=${option.index}');
    final fileTrack = SubtitleTrack.uri(
      Uri.file(cachedPath).toString(),
      title: option.label,
      language: option.language,
    );
    final ok = await SubtitleSwitchQueue.withMpv(
      () => player.activateExternalSubtitleFile(
        fileTrack,
        reason: 'cached index=${option.index}',
      ),
    );
    return ok;
  }

  final track = SubtitleTrack.uri(
    option.streamUrl,
    title: option.label,
    language: option.language,
  );

  final embyStream = option.streamUrl.contains('/Subtitles/');

  if (!embyStream && !_externalSubtitleNeedsDownload(option)) {
    final direct = await SubtitleSwitchQueue.withMpv(
      () => player.activateExternalSubtitleFile(
        track,
        reason: 'external direct index=${option.index}',
      ),
    );
    if (!SubtitleSwitchQueue.isCurrent(generation)) {
      throw SubtitleSwitchCancelled();
    }
    if (direct) {
      AppLog.instance.i(
        'Subtitle',
        'external direct OK index=${option.index} format=${option.format}',
      );
      return true;
    }
    AppLog.instance.w(
      'Subtitle',
      'external direct failed → download fallback index=${option.index}',
    );
  }

  final text = await emby.fetchSubtitleText(option.streamUrl);
  if (!SubtitleSwitchQueue.isCurrent(generation)) {
    throw SubtitleSwitchCancelled();
  }
  if (text == null || text.isEmpty) {
    AppLog.instance.w('Subtitle', 'fetchSubtitleText failed index=${option.index}');
    return false;
  }

  final cachePath = _embySubtitleCachePath(option);
  await Directory(p.dirname(cachePath)).create(recursive: true);
  await File(cachePath).writeAsString(text);
  if (!SubtitleSwitchQueue.isCurrent(generation)) {
    throw SubtitleSwitchCancelled();
  }

  final fileTrack = SubtitleTrack.uri(
    Uri.file(cachePath).toString(),
    title: track.title,
    language: track.language,
  );
  final ok = await SubtitleSwitchQueue.withMpv(
    () => player.activateExternalSubtitleFile(
      fileTrack,
      reason: 'external file index=${option.index}',
    ),
  );
  if (ok) {
    AppLog.instance.i(
      'Subtitle',
      'external file OK index=${option.index} format=${option.format}',
    );
  }
  return ok;
}

List<SubtitleTrack> _muxedTracks(Player player) {
  return player.state.tracks.subtitle
      .where((t) => t.id != 'auto' && t.id != 'no' && !t.uri && !t.data)
      .toList();
}

bool _externalSubtitleNeedsDownload(EmbySubtitleOption option) {
  if (option.isBitmapSubtitle || option.format == 'pgs') return true;
  return option.streamUrl.trim().isEmpty;
}

bool isNonFatalPlayerSubtitleError(String text) {
  final lower = text.toLowerCase();
  return lower.contains('external file') ||
      lower.contains('/subtitles/') ||
      lower.contains('stream.srt') ||
      lower.contains('stream.vtt') ||
      lower.contains('stream.ass');
}
