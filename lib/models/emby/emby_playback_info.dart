import 'emby_subtitle_option.dart';

/// Parsed playback URL and session metadata from `PlaybackInfo`.
class EmbyPlaybackInfo {
  const EmbyPlaybackInfo({
    required this.playSessionId,
    required this.mediaSourceId,
    required this.streamUrl,
    this.subtitles = const [],
    this.supportsDirectPlay,
    this.directStreamUrl,
    this.transcodingUrl,
    this.fallbackStreamUrl,
    this.runTimeTicks,
    this.strmViaEmbyStream = false,
  });

  final String playSessionId;
  final String mediaSourceId;

  /// URL for mpv (Emby `/Videos/.../stream` for server-side redirect targets,
  /// or a direct CDN / Emby path).
  final String streamUrl;

  /// Server-side redirect: open [streamUrl] on Emby; mpv follows the 307 to
  /// the final CDN URL (no client pre-resolve).
  final bool strmViaEmbyStream;

  /// Subtitle tracks from the active [MediaSource], via Emby Subtitles Stream API.
  final List<EmbySubtitleOption> subtitles;

  final bool? supportsDirectPlay;
  final String? directStreamUrl;
  final String? transcodingUrl;

  /// Resolved server transcode/direct-stream URL when direct play is unavailable.
  final String? fallbackStreamUrl;
  final int? runTimeTicks;

  /// Default or forced subtitle from Emby metadata (no fallback to first track).
  EmbySubtitleOption? get preferredSubtitle {
    for (final t in subtitles) {
      if (t.isDefault || t.isForced) return t;
    }
    return null;
  }

  /// Preferred text subtitle for mpv (skips PGS; ASS is OK).
  EmbySubtitleOption? get preferredTextSubtitle {
    EmbySubtitleOption? pick(EmbySubtitleOption? t) {
      if (t == null || t.isBitmapSubtitle) return null;
      return t;
    }

    final textTracks = subtitles.where((t) => !t.isBitmapSubtitle).toList();
    return pick(preferredSubtitle) ??
        (textTracks.isEmpty ? null : pick(textTracks.first));
  }

  /// ExoPlayer TV: skip PGS/特效 default; prefer plain SRT/VTT, else ASS via SRT extract.
  EmbySubtitleOption? get preferredExoTextSubtitle {
    final playable =
        subtitles.where((t) => t.isExoPlayableTextSubtitle).toList();
    if (playable.isEmpty) return null;

    for (final t in playable) {
      if (t.isDefault || t.isForced) return t;
    }

    int rank(EmbySubtitleOption t) {
      if (t.isEffectSubtitle) return 2;
      final f = t.format.toLowerCase();
      if (f == 'srt' || f == 'sub') return 0;
      if (f == 'vtt') return 1;
      return 2;
    }

    playable.sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      if (byRank != 0) return byRank;
      return a.index.compareTo(b.index);
    });
    return playable.first;
  }

  /// [serverPublicBase] = user-configured server URL without trailing slash, e.g. `http://host:8095`.
  /// [accessToken] is appended as `api_key` when missing (Jellyfin streaming; mpv cannot send custom headers).
  factory EmbyPlaybackInfo.fromResponse(
    Map<String, dynamic> json, {
    required String itemId,
    required String serverPublicBase,
    String? accessToken,
    int startTimeTicks = 0,
  }) {
    final sources = _mediaSources(json);
    if (sources.isEmpty) {
      throw FormatException('PlaybackInfo has no MediaSources for $itemId');
    }

    sources.sort((a, b) {
      final ar = _readBool(a, const ['IsRemote', 'isRemote']) == true ? 1 : 0;
      final br = _readBool(b, const ['IsRemote', 'isRemote']) == true ? 1 : 0;
      return br.compareTo(ar);
    });

    String? playSession = _readString(json, const ['PlaySessionId', 'playSessionId']);

    for (final src in sources) {
      final mediaSourceId = _readString(src, const ['Id', 'id']) ?? '';
      final runTime = _readInt(src, const ['RunTimeTicks', 'runTimeTicks']);

      final supportsDirectPlay =
          _readBool(src, const ['SupportsDirectPlay', 'supportsDirectPlay']);
      final directStreamRaw =
          _readString(src, const ['DirectStreamUrl', 'directStreamUrl']);
      final transcodeRaw =
          _readString(src, const ['TranscodingUrl', 'transcodingUrl']);
      final remuxRaw = _readString(src, const ['RemuxUrl', 'remuxUrl']);
      final candidates = _playbackStreamCandidates(
        path: _readString(src, const ['Path', 'path']),
        directStreamUrl: directStreamRaw,
        transcodingUrl: transcodeRaw,
        remuxUrl: remuxRaw,
        startTimeTicks: startTimeTicks,
        supportsDirectPlay: supportsDirectPlay,
      );
      final fallbackStreamUrl = _resolveFirstPlaybackUrl(
        [directStreamRaw, transcodeRaw, remuxRaw],
        serverPublicBase: serverPublicBase,
        accessToken: accessToken,
      );

      for (final raw in candidates) {
        if (raw == null || raw.trim().isEmpty) continue;
        final resolved = _resolveToHttpUrl(raw.trim(), serverPublicBase);
        if (resolved == null) continue;
        final withKey = _appendStreamApiKey(resolved, accessToken);
        playSession ??= _readString(src, const ['PlaySessionId', 'playSessionId']);
        final subtitles = _parseSubtitleStreams(
          src,
          itemId: itemId,
          mediaSourceId: mediaSourceId,
          serverPublicBase: serverPublicBase,
          accessToken: accessToken,
        );
        return EmbyPlaybackInfo(
          playSessionId: playSession ?? '',
          mediaSourceId: mediaSourceId,
          streamUrl: withKey,
          subtitles: subtitles,
          supportsDirectPlay: supportsDirectPlay,
          directStreamUrl: directStreamRaw,
          transcodingUrl: transcodeRaw,
          fallbackStreamUrl: fallbackStreamUrl,
          runTimeTicks: runTime,
        );
      }
    }

    final err = _readString(json, const ['ErrorMessage', 'errorMessage']);
    if (err != null && err.isNotEmpty) {
      throw FormatException('PlaybackInfo: $err');
    }
    throw FormatException('No playable HTTP(S) URL in MediaSources for $itemId');
  }
}

List<String?> _playbackStreamCandidates({
  required String? path,
  required String? directStreamUrl,
  required String? transcodingUrl,
  required String? remuxUrl,
  required int startTimeTicks,
  bool? supportsDirectPlay,
}) {
  if (supportsDirectPlay == false) {
    return [directStreamUrl, transcodingUrl, remuxUrl, path];
  }
  if (startTimeTicks > 0) {
    return [transcodingUrl, directStreamUrl, remuxUrl, path];
  }
  return [path, directStreamUrl, transcodingUrl, remuxUrl];
}

String? _resolveFirstPlaybackUrl(
  List<String?> rawCandidates, {
  required String serverPublicBase,
  String? accessToken,
}) {
  for (final raw in rawCandidates) {
    if (raw == null || raw.trim().isEmpty) continue;
    final resolved = _resolveToHttpUrl(raw.trim(), serverPublicBase);
    if (resolved == null) continue;
    return _appendStreamApiKey(resolved, accessToken);
  }
  return null;
}

List<Map<String, dynamic>> _mediaSources(Map<String, dynamic> json) {
  final raw = json['MediaSources'] ?? json['mediaSources'];
  if (raw is! List) return [];
  return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
}

/// True when any [MediaSources] entry [Path] is a server-side strm redirect.
bool playbackSourcesNeedStreamProxy(
  Map<String, dynamic> json,
  String serverPublicBase,
) {
  for (final src in _mediaSources(json)) {
    final path = _readString(src, const ['Path', 'path']);
    if (path != null && needsEmbyStreamProxy(path, serverPublicBase)) {
      return true;
    }
  }
  return false;
}

String? _readString(Map<String, dynamic> m, List<String> keys) {
  for (final k in keys) {
    final v = m[k];
    if (v is String && v.isNotEmpty) return v;
  }
  return null;
}

bool? _readBool(Map<String, dynamic> m, List<String> keys) {
  for (final k in keys) {
    final v = m[k];
    if (v is bool) return v;
  }
  return null;
}

int? _readInt(Map<String, dynamic> m, List<String> keys) {
  for (final k in keys) {
    final v = m[k];
    if (v is num) return v.toInt();
  }
  return null;
}

/// Returns an http(s) URL, or null if [raw] is only a server-local filesystem path.
String? _resolveToHttpUrl(String raw, String serverPublicBase) {
  if (raw.startsWith('http://') ||
      raw.startsWith('https://') ||
      raw.startsWith('rtmp://') ||
      raw.startsWith('rtsp://')) {
    return raw;
  }
  if (_isServerLocalPath(raw)) return null;
  if (raw.startsWith('/') && !_looksLikeJellyfinStreamPath(raw)) {
    return null;
  }

  final origin = _serverOrigin(serverPublicBase);
  if (origin == null) return null;

  final path = raw.startsWith('/') ? raw : '/$raw';
  return origin.resolve(path).toString();
}

/// Avoid turning `/mnt/media/file.mkv` into `http://host/mnt/media/file.mkv`.
bool _looksLikeJellyfinStreamPath(String s) {
  final lower = s.toLowerCase();
  return lower.startsWith('/videos/') ||
      lower.startsWith('/audio/') ||
      lower.startsWith('/emby/') ||
      lower.startsWith('/live/');
}

bool _isServerLocalPath(String s) {
  if (s.startsWith('http://') || s.startsWith('https://')) return false;
  if (RegExp(r'^[A-Za-z]:[/\\]').hasMatch(s)) return true;
  if (s.startsWith(r'\\')) return true;
  return false;
}

Uri? _serverOrigin(String serverPublicBase) {
  var t = serverPublicBase.trim();
  if (t.isEmpty) return null;
  while (t.endsWith('/')) {
    t = t.substring(0, t.length - 1);
  }
  final u = Uri.parse(t);
  if (u.host.isEmpty) return null;
  return Uri(scheme: u.scheme.isEmpty ? 'http' : u.scheme, host: u.host, port: u.hasPort ? u.port : null);
}

String _appendStreamApiKey(String url, String? token, {bool useEmbyTokenParam = false}) {
  if (token == null || token.isEmpty) return url;
  final lower = url.toLowerCase();
  if (lower.contains('api_key=') ||
      lower.contains('apikey=') ||
      lower.contains('access_token=') ||
      lower.contains('x-emby-token=')) {
    return url;
  }
  final sep = url.contains('?') ? '&' : '?';
  final param = useEmbyTokenParam ? 'X-Emby-Token' : 'api_key';
  return '$url$sep$param=${Uri.encodeComponent(token)}';
}

/// True when [url] points at a server-side strm/redirect target the desktop client cannot open
/// directly (Docker service names, server-side redirect plugins, etc.).
bool needsEmbyStreamProxy(String url, String serverPublicBase) {
  if (isEmbyHostedStreamUrl(url, serverPublicBase)) return false;

  final uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty) return true;

  final host = uri.host.toLowerCase();
  if (host == 'localhost' || host == '127.0.0.1') {
    return true;
  }

  final path = uri.path.toLowerCase();
  if (path.contains('redirect_url') ||
      (path.contains('/plugin/') && path.contains('redirect'))) {
    return true;
  }

  return false;
}

/// True when [url] is served by the configured Emby/Jellyfin host (not a remote CDN/strm target).
bool isEmbyHostedStreamUrl(String url, String serverPublicBase) {
  final stream = Uri.tryParse(url);
  final origin = _serverOrigin(serverPublicBase);
  if (stream == null || origin == null || stream.host.isEmpty) return false;
  final sameHost = stream.host.toLowerCase() == origin.host.toLowerCase();
  if (!sameHost) return false;
  final streamPort = stream.hasPort ? stream.port : stream.scheme == 'https' ? 443 : 80;
  final originPort = origin.hasPort ? origin.port : origin.scheme == 'https' ? 443 : 80;
  return streamPort == originPort;
}

/// Canonical direct stream URL through Emby.
///
/// [strmProxy]: match server-side strm proxy — `/Videos/{id}/stream`
/// without extension or PlaySessionId, token as `X-Emby-Token` query param.
String? buildEmbyVideoStreamUrl({
  required String serverPublicBase,
  required String itemId,
  required String mediaSourceId,
  required String playSessionId,
  String? accessToken,
  int? startTimeTicks,
  bool directStream = true,
  bool strmProxy = false,
}) {
  final origin = _serverOrigin(serverPublicBase);
  if (origin == null) return null;

  final embyPrefix = _embyPathPrefix(serverPublicBase);
  final path = strmProxy
      ? '$embyPrefix/Videos/$itemId/stream'
      : '$embyPrefix/Videos/$itemId/stream.mkv';

  final query = <String, String>{
    'MediaSourceId': mediaSourceId,
    if (!strmProxy) ...{
      'PlaySessionId': playSessionId.trim().isEmpty
          ? 'media-client-${DateTime.now().millisecondsSinceEpoch}'
          : playSessionId,
    },
    if (directStream) 'Static': 'true',
    if (startTimeTicks != null && startTimeTicks > 0) 'StartTimeTicks': '$startTimeTicks',
  };
  final resolved = origin.replace(path: path, queryParameters: query).toString();
  return _appendStreamApiKey(resolved, accessToken, useEmbyTokenParam: strmProxy);
}

/// Picks the stream URL clients should open in mpv.
///
/// Strm / server-side redirect paths always go through Emby stream
/// (server-side strm redirect). Public CDN URLs are opened directly
/// when starting from the beginning; resume still uses Emby.
String resolvePlaybackStreamUrl({
  required EmbyPlaybackInfo info,
  required String itemId,
  required String serverPublicBase,
  String? accessToken,
  int? startTimeTicks,
}) {
  final direct = info.streamUrl;
  final ticks = startTimeTicks ?? 0;

  if (needsEmbyStreamProxy(direct, serverPublicBase)) {
    // Strm: no StartTimeTicks on /stream (server-side proxy). Resume via PlaybackInfo body + CDN seek.
    final embyStream = buildEmbyVideoStreamUrl(
      serverPublicBase: serverPublicBase,
      itemId: itemId,
      mediaSourceId: info.mediaSourceId,
      playSessionId: info.playSessionId,
      accessToken: accessToken,
      directStream: true,
      strmProxy: true,
    );
    return embyStream ?? direct;
  }

  if (ticks <= 0) return direct;

  if (isEmbyHostedStreamUrl(direct, serverPublicBase)) {
    final uri = Uri.parse(direct);
    final q = Map<String, String>.from(uri.queryParameters);
    q['StartTimeTicks'] = '$ticks';
    return _appendStreamApiKey(uri.replace(queryParameters: q).toString(), accessToken);
  }

  final embyStream = buildEmbyVideoStreamUrl(
    serverPublicBase: serverPublicBase,
    itemId: itemId,
    mediaSourceId: info.mediaSourceId,
    playSessionId: info.playSessionId,
    accessToken: accessToken,
    startTimeTicks: ticks,
    directStream: false,
  );
  return embyStream ?? direct;
}

List<EmbySubtitleOption> _parseSubtitleStreams(
  Map<String, dynamic> mediaSource, {
  required String itemId,
  required String mediaSourceId,
  required String serverPublicBase,
  String? accessToken,
}) {
  final raw = mediaSource['MediaStreams'] ?? mediaSource['mediaStreams'];
  if (raw is! List) return const [];

  final out = <EmbySubtitleOption>[];
  for (final entry in raw) {
    if (entry is! Map) continue;
    final m = Map<String, dynamic>.from(entry);
    final type = (_readString(m, const ['Type', 'type']) ?? '').toLowerCase();
    if (type != 'subtitle') continue;

    final index = _readInt(m, const ['Index', 'index']);
    if (index == null) continue;

    final format = _subtitleStreamFormat(m);
    final isExternal = _readBool(m, const ['IsExternal', 'isExternal']) == true;
    final streamUrl = buildEmbySubtitleStreamUrl(
      serverPublicBase: serverPublicBase,
      itemId: itemId,
      mediaSourceId: mediaSourceId,
      index: index,
      format: format,
      accessToken: accessToken,
    );
    if (streamUrl == null) continue;

    final language = _readString(m, const ['Language', 'language']);
    final label = _subtitleDisplayLabel(m, index, language);
    out.add(
      EmbySubtitleOption(
        index: index,
        label: label,
        streamUrl: streamUrl,
        format: format,
        language: language,
        isDefault: _readBool(m, const ['IsDefault', 'isDefault']) == true,
        isForced: _readBool(m, const ['IsForced', 'isForced']) == true,
        isExternal: isExternal,
      ),
    );
  }

  out.sort((a, b) => a.index.compareTo(b.index));
  return out;
}

/// Canonical Emby/Jellyfin subtitle stream URL (stable for direct players).
String? buildEmbySubtitleStreamUrl({
  required String serverPublicBase,
  required String itemId,
  required String mediaSourceId,
  required int index,
  required String format,
  String? accessToken,
}) {
  final origin = _serverOrigin(serverPublicBase);
  if (origin == null) return null;

  final embyPrefix = _embyPathPrefix(serverPublicBase);
  final path =
      '$embyPrefix/Videos/$itemId/$mediaSourceId/Subtitles/$index/Stream.$format';
  final resolved = origin.resolve(path).toString();
  return _appendStreamApiKey(resolved, accessToken);
}

/// `/emby` or existing base path segment from configured server URL.
String _embyPathPrefix(String serverPublicBase) {
  var t = serverPublicBase.trim();
  while (t.endsWith('/')) {
    t = t.substring(0, t.length - 1);
  }
  final u = Uri.tryParse(t);
  if (u == null) return '/emby';
  var path = u.path;
  if (path.endsWith('/emby')) return path;
  if (path.isEmpty) return '/emby';
  return '$path/emby';
}

String _subtitleStreamFormat(Map<String, dynamic> stream) {
  final codec = (_readString(stream, const ['Codec', 'codec']) ?? '').toLowerCase();
  if (codec.contains('webvtt') || codec == 'vtt') return 'vtt';
  if (codec.contains('ass') || codec == 'ssa') return 'ass';
  if (codec.contains('pgs') || codec.contains('hdmv_pgs')) return 'pgs';
  if (codec.contains('subrip') || codec == 'srt' || codec == 'sub') return 'srt';
  return 'srt';
}

String _subtitleDisplayLabel(Map<String, dynamic> stream, int index, String? language) {
  final display = _readString(stream, const ['DisplayTitle', 'displayTitle']);
  if (display != null && display.isNotEmpty) return display;
  final title = _readString(stream, const ['Title', 'title']);
  if (title != null && title.isNotEmpty) return title;
  if (language != null && language.isNotEmpty) return language;
  final external = _readBool(stream, const ['IsExternal', 'isExternal']) == true;
  return external ? '外挂字幕 $index' : '字幕 $index';
}
