import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:media_kit/media_kit.dart';

// ignore: implementation_imports
import 'package:media_kit/src/player/native/player/real.dart' as native;

import '../logging/app_log.dart';
import '../../models/emby/emby_subtitle_option.dart';

final _sidByEmbyIndexExpando = Expando<Map<int, String>>();

void invalidateMpvSidIndexCache(Player player) {
  _sidByEmbyIndexExpando[player] = null;
}

/// Cached Emby index → mpv sid map (no I/O). Refresh via [mpvSidByEmbyStreamIndex].
Map<int, String>? cachedMpvSidByEmbyIndex(Player player) {
  return _sidByEmbyIndexExpando[player];
}

/// Maps Emby [EmbySubtitleOption.index] (MediaStreams Index) → mpv `sid` via `track-list` `ff-index`.
Future<Map<int, String>> mpvSidByEmbyStreamIndex(Player player) async {
  final cached = _sidByEmbyIndexExpando[player];
  if (cached != null) {
    return cached;
  }
  final out = <int, String>{};
  if (kIsWeb) return out;
  final platform = player.platform;
  if (platform is! native.NativePlayer) return out;
  try {
    final raw = await platform.getProperty('track-list', waitForInitialization: false);
    if (raw.isEmpty) return out;
    final list = jsonDecode(raw);
    if (list is! List) return out;
    for (final entry in list) {
      if (entry is! Map) continue;
      if (entry['type']?.toString() != 'sub') continue;
      final id = entry['id'];
      if (id == null) continue;
      final sid = id.toString();

      final ff = entry['ff-index'] ?? entry['ff_index'];
      final ffIndex = ff is int ? ff : int.tryParse(ff?.toString() ?? '');
      if (ffIndex != null) out[ffIndex] = sid;

      // Some builds expose container stream index as src-id (aligns with Emby MediaStreams Index).
      final src = entry['src-id'] ?? entry['src_id'];
      final srcId = src is int ? src : int.tryParse(src?.toString() ?? '');
      if (srcId != null) out[srcId] = sid;
    }
  } catch (e, st) {
    AppLog.instance.e('Subtitle', 'track-list parse failed', error: e, stackTrace: st);
  }
  _sidByEmbyIndexExpando[player] = out;
  return out;
}

Future<String?> mpvSidForEmbyStreamIndex(Player player, int embyIndex) async {
  final map = await mpvSidByEmbyStreamIndex(player);
  return map[embyIndex];
}

/// mpv `track-list` entries for subtitles added via `sub-add` (`external: true`).
Future<List<String>> mpvExternalSubtitleIds(Player player) async {
  final out = <String>[];
  if (kIsWeb) return out;
  final platform = player.platform;
  if (platform is! native.NativePlayer) return out;
  try {
    final raw = await platform.getProperty('track-list', waitForInitialization: false);
    if (raw.isEmpty) return out;
    final list = jsonDecode(raw);
    if (list is! List) return out;
    for (final entry in list) {
      if (entry is! Map) continue;
      if (entry['type']?.toString() != 'sub') continue;
      if (entry['external'] != true) continue;
      final id = entry['id'];
      if (id != null) out.add(id.toString());
    }
  } catch (e, st) {
    AppLog.instance.e('Subtitle', 'track-list external parse failed', error: e, stackTrace: st);
  }
  return out;
}

SubtitleTrack? _trackBySid(Player player, String sid) {
  for (final t in player.state.tracks.subtitle) {
    if (t.id == sid) return t;
  }
  return null;
}

/// One track-list read → map Emby stream index to muxed [SubtitleTrack].
Future<Map<int, SubtitleTrack>> buildEmbyIndexTrackMap(
  Player player,
  Iterable<EmbySubtitleOption> embyOptions,
) async {
  final sidByIndex = await mpvSidByEmbyStreamIndex(player);
  final out = <int, SubtitleTrack>{};
  for (final o in embyOptions) {
    if (o.isExternal) continue;
    final sid = sidByIndex[o.index];
    if (sid == null) continue;
    final t = _trackBySid(player, sid);
    if (t != null) out[o.index] = t;
  }
  return out;
}

Future<SubtitleTrack?> muxedTrackForEmbyStreamIndex(
  Player player,
  int embyIndex,
) async {
  final sid = await mpvSidForEmbyStreamIndex(player, embyIndex);
  if (sid == null) {
    AppLog.instance.w('Subtitle', 'no mpv sid for emby stream index=$embyIndex');
    return null;
  }
  final t = _trackBySid(player, sid);
  if (t != null) {
    AppLog.instance.d(
      'Subtitle',
      'embyIndex=$embyIndex → mpv sid=$sid title=${t.title} codec=${t.codec}',
    );
  }
  return t;
}

Future<SubtitleTrack?> resolveEmbeddedEmbySubtitleTrack(
  Player player,
  EmbySubtitleOption option,
) async {
  return muxedTrackForEmbyStreamIndex(player, option.index);
}

/// Menu label: prefer muxed title (SDR简体特效 / Simplified) over generic Emby name.
String embeddedSubtitleMenuLabel(
  EmbySubtitleOption option,
  SubtitleTrack? native,
) {
  final tag = option.isBitmapSubtitle ? 'PGS' : '文本';
  final nativeName = muxedTrackDisplayName(native);
  if (nativeName != null) {
    return '$nativeName [$tag]';
  }
  return '${option.label} [$tag]';
}

String? muxedTrackDisplayName(SubtitleTrack? track) {
  if (track == null) return null;
  final title = track.title?.trim();
  if (title != null && title.isNotEmpty) return title;
  final lang = track.language?.trim();
  if (lang != null && lang.isNotEmpty) {
    if (lang == 'zh-Hans') return '简体 (轨 ${track.id})';
    if (lang == 'zh-Hant') return '繁体 (轨 ${track.id})';
    if (lang == 'en' || lang == 'eng') return 'English (轨 ${track.id})';
    return '$lang (轨 ${track.id})';
  }
  final codec = track.codec?.toLowerCase() ?? '';
  if (codec.contains('pgs')) return 'PGS 轨 ${track.id}';
  if (codec.contains('subrip')) return '文本轨 ${track.id}';
  return '轨 ${track.id}';
}
