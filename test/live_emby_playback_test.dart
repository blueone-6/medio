// Live integration test against a real Emby/go-emby2openlist server.
//
// Skipped by default — opt in with environment variables:
//
//   EMBY_LIVE_SERVER  e.g. http://host:8095
//   EMBY_LIVE_USER    username (or use EMBY_LIVE_API_KEY instead)
//   EMBY_LIVE_PASS    password
//   EMBY_LIVE_API_KEY API key (alternative to user/pass)
//
//   $env:EMBY_LIVE_SERVER='http://host:8095'
//   $env:EMBY_LIVE_USER='user'; $env:EMBY_LIVE_PASS='pass'
//   flutter test test/live_emby_playback_test.dart
//
// Covered operation matrix (API level):
//   A. authentication (AuthenticateByName / API key)
//   B. PlaybackInfo with the app's real DeviceProfiles (desktop + android)
//   C. strm proxy 307 resolve + CDN byte-range seek (head/middle/tail = Cues)
//   D. 115 CDN UA binding contract (guards the client CDN-direct mode)
//   E. subtitle streams: ASS original, server conversion to SRT/VTT
//   F. progress reporting lifecycle: Started → Progress → Stopped → resume state
//   G. StartTimeTicks resume echo on PlaybackInfo
//   H. query-param-only auth on stream URLs (mpv cannot send custom headers)
//
// Playback progress written by section F is reset at the end of the run.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _chromeUa =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
const _cdnReferer = 'https://115.com/';

String? _server;
String? _user;
String? _pass;
String? _apiKey;
String? _token;
String? _userId;
Map<String, dynamic>? _testItem; // strm item with external subtitle
int _testSubIndex = 0; // stream index of the discovered external subtitle
String _testSubCodec = 'srt';
late HttpClient _client;

bool _skip() => Platform.environment['EMBY_LIVE_SERVER'] == null;

Uri _u(String path) => Uri.parse('$_server$path');

Map<String, String> _authHeaders({String? contentType}) => {
      if (_token != null) 'X-Emby-Token': _token!,
      if (_token == null && _apiKey != null) 'X-Emby-Token': _apiKey!,
      if (contentType != null) 'Content-Type': contentType,
    };

Future<Map<String, dynamic>> _postJson(
  String path,
  Map<String, dynamic> body, {
  Map<String, String>? query,
}) async {
  var uri = _u(path);
  if (query != null) uri = uri.replace(queryParameters: query);
  final req = await _client.postUrl(uri);
  _authHeaders(contentType: 'application/json')
      .forEach(req.headers.set);
  // Mirrors the app's X-Emby-Authorization header (Emby requires appName
  // on AuthenticateByName).
  req.headers.set(
    'X-Emby-Authorization',
    'MediaBrowser Client="medio-live-test", Device="CI", '
        'DeviceId="live-test-device-0001", Version="1.0.0"',
  );
  req.write(jsonEncode(body));
  final res = await req.close();
  final text = await res.transform(utf8.decoder).join();
  if (res.statusCode != 200 && res.statusCode != 204) {
    throw StateException('POST $path -> ${res.statusCode}: $text');
  }
  return text.isEmpty ? <String, dynamic>{} : jsonDecode(text) as Map<String, dynamic>;
}

Future<Map<String, dynamic>> _getJson(String path) async {
  final req = await _client.getUrl(_u(path));
  _authHeaders().forEach(req.headers.set);
  final res = await req.close();
  final text = await res.transform(utf8.decoder).join();
  if (res.statusCode != 200) {
    throw StateException('GET $path -> ${res.statusCode}: $text');
  }
  return jsonDecode(text) as Map<String, dynamic>;
}

class StateException implements Exception {
  StateException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The strm-with-external-subtitle item chosen in setUpAll, or marks the
/// calling test skipped when the library has none.
Map<String, dynamic> _requireTestItem() {
  final item = _testItem;
  if (item == null) {
    markTestSkipped('no strm item with external subtitles in the library');
    // markTestSkipped aborts the test by throwing; this is analyzer appeasement.
    throw StateError('unreachable after markTestSkipped');
  }
  return item;
}

/// DeviceProfiles copied from lib/models/emby/emby_device_profile.dart —
/// keep them in sync so this test exercises what the app actually sends.
Map<String, dynamic> _deviceProfile(String kind) {
  final android = kind == 'android';
  final videoCodecs = android ? 'h264,hevc' : 'h264,hevc,vp9,av1';
  final audioCodecs = android
      ? 'aac,ac3,eac3,mp3,opus,flac,vorbis,alac'
      : 'aac,ac3,eac3,mp3,opus,flac,vorbis,alac,dts,truehd,mlp';
  return {
    'Name': android ? 'Media Client Android' : 'Media Client',
    'MaxStaticBitrate': android ? 140000000 : 999999999,
    'MaxStreamingBitrate': android ? 140000000 : 999999999,
    'MusicStreamingTranscodingBitrate': android ? 384000 : 192000,
    'DirectPlayProfiles': [
      {
        'Container': android ? 'mp4,m4v,mov,mkv,ts,mpegts' : 'mp4,m4v,mov,mkv,ts,mpegts,webm',
        'Type': 'Video',
        'VideoCodec': videoCodecs,
        'AudioCodec': audioCodecs,
      },
      {
        'Container': 'mp3,aac,flac,ogg,wav',
        'Type': 'Audio',
        'AudioCodec': audioCodecs,
      },
    ],
    'TranscodingProfiles': [
      {
        'Container': 'ts', 'Type': 'Video', 'VideoCodec': 'h264',
        'AudioCodec': 'aac', 'Protocol': 'hls', 'EstimateContentLength': false,
        'EnableMpegtsM2TsMode': false, 'TranscodingSeekInfo': 'Auto',
        'CopyTimestamps': false, 'Context': 'Streaming',
        'MaxAudioChannels': '6', 'MinSegments': 2, 'BreakOnNonKeyFrames': true,
      },
      {
        'Container': 'mp4', 'Type': 'Video', 'VideoCodec': 'h264',
        'AudioCodec': 'aac', 'Protocol': 'http', 'EstimateContentLength': false,
        'EnableMpegtsM2TsMode': false, 'TranscodingSeekInfo': 'Auto',
        'CopyTimestamps': false, 'Context': 'Streaming',
        'MaxAudioChannels': '6', 'MinSegments': 0, 'BreakOnNonKeyFrames': false,
      },
      {
        'Container': 'mp3', 'Type': 'Audio', 'AudioCodec': 'aac',
        'Protocol': 'http', 'EstimateContentLength': false,
        'EnableMpegtsM2TsMode': false, 'TranscodingSeekInfo': 'Auto',
        'CopyTimestamps': false, 'Context': 'Streaming',
        'MaxAudioChannels': '2', 'MinSegments': 0, 'BreakOnNonKeyFrames': false,
      },
    ],
    'CodecProfiles': <Object>[],
    'ContainerProfiles': <Object>[],
    'SubtitleProfiles': [
      {'Format': 'srt', 'Method': 'External'},
      {'Format': 'ass', 'Method': 'External'},
      {'Format': 'vtt', 'Method': 'External'},
    ],
  };
}

Future<Map<String, dynamic>> _playbackInfo(
  String itemId, {
  String kind = 'desktop',
  int startTimeTicks = 0,
}) {
  return _postJson(
    '/emby/Items/$itemId/PlaybackInfo',
    {
      'UserId': _userId,
      'StartTimeTicks': startTimeTicks,
      'DeviceProfile': _deviceProfile(kind),
    },
    query: {'UserId': _userId!},
  );
}

/// Resolves the strm redirect with the exact headers mpv will use
/// (mirrors EmbyService.resolveExternalCdnUrl after the UA-binding fix).
Future<String> _resolveCdnUrl(String embyStreamUrl, {String? ua}) async {
  var current = embyStreamUrl;
  for (var hop = 0; hop < 5; hop++) {
    final uri = Uri.parse(current);
    if (uri.host.contains('115cdn') || uri.host == '115.com') return current;
    final req = await _client.getUrl(uri);
    req.followRedirects = false;
    req.headers.set(HttpHeaders.userAgentHeader, ua ?? _chromeUa);
    req.headers.set(HttpHeaders.refererHeader, _cdnReferer);
    final res = await req.close();
    if (res.isRedirect) {
      final location = res.headers.value(HttpHeaders.locationHeader);
      if (location == null) {
        throw StateException('redirect without Location at $current');
      }
      current = Uri.parse(current).resolve(location).toString();
      continue;
    }
    // Non-redirect response: drain and treat as final (some proxies answer
    // 200 directly for non-strm content).
    await res.drain<void>();
    return current;
  }
  throw StateException('redirect chain exceeded 5 hops');
}

Future<HttpClientResponse> _rangeGet(
  String url,
  int start,
  int end, {
  String? ua,
}) async {
  final req = await _client.getUrl(Uri.parse(url));
  req.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-$end');
  req.headers.set(HttpHeaders.userAgentHeader, ua ?? _chromeUa);
  req.headers.set(HttpHeaders.refererHeader, _cdnReferer);
  return req.close();
}

void main() {
  setUpAll(() async {
    _server = Platform.environment['EMBY_LIVE_SERVER'];
    _user = Platform.environment['EMBY_LIVE_USER'];
    _pass = Platform.environment['EMBY_LIVE_PASS'];
    _apiKey = Platform.environment['EMBY_LIVE_API_KEY'];
    if (_server == null) return;
    _server = _server!.endsWith('/') ? _server!.substring(0, _server!.length - 1) : _server;
    _client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);

    // A. Authenticate (or use API key) — section A of the matrix.
    if (_user != null && _pass != null) {
      final auth = await _postJson('/emby/Users/AuthenticateByName', {
        'Username': _user,
        'Pw': _pass,
      });
      _token = auth['AccessToken'] as String?;
      final user = auth['User'] as Map<String, dynamic>?;
      _userId = user?['Id'] as String?;
      expect(_token, isNotNull, reason: 'AuthenticateByName returned no token');
      expect(_userId, isNotNull, reason: 'AuthenticateByName returned no user id');
    } else {
      expect(_apiKey, isNotNull,
          reason: 'Provide EMBY_LIVE_USER/PASS or EMBY_LIVE_API_KEY');
      _token = _apiKey;
      // Discover user id via /emby/Users.
      final users = await _getJson('/emby/Users');
      final list = users['Items'] as List<dynamic>? ?? users as List<dynamic>?;
      _userId = (list!.first as Map<String, dynamic>)['Id'] as String;
    }

    // Pick an item whose playback goes through the server-side strm proxy
    // (Path is an http URL, not a local file) with a probed runtime and a
    // fetchable external subtitle. Probing items flips their Container from
    // 'strm' to the real container, so the Path is the stable signal.
    final items = await _getJson(
      '/emby/Users/$_userId/Items?Recursive=true&IncludeItemTypes=Movie,Episode'
      '&Fields=MediaStreams,RunTimeTicks,Path&Limit=300',
    );
    for (final raw in items['Items'] as List<dynamic>) {
      final item = raw as Map<String, dynamic>;
      if (item['RunTimeTicks'] == null) continue;
      final sources = item['MediaSources'] as List<dynamic>?;
      if (sources == null || sources.isEmpty) continue;
      final src = sources.first as Map<String, dynamic>;
      final path = src['Path'] as String? ?? '';
      final isProxyStrm = path.startsWith('http://') || path.startsWith('https://');
      if (!isProxyStrm) continue;
      final streams = src['MediaStreams'] as List<dynamic>? ?? const [];
      for (final s in streams) {
        final m = s as Map<String, dynamic>;
        if (m['Type'] != 'Subtitle' || m['IsExternal'] != true) continue;
        final subIndex = m['Index'] as int? ?? 0;
        final id = item['Id'] as String;
        // Some sidecar files exist in metadata but are empty on the server —
        // probe the subtitle endpoint and only accept items with content.
        try {
          final probe = await _client.getUrl(
            _u('/emby/Videos/$id/mediasource_$id/Subtitles/$subIndex'
                '/Stream.srt?api_key=$_token'),
          );
          final probeRes = await probe.close();
          final probeText = await probeRes.transform(utf8.decoder).join();
          if (probeRes.statusCode != 200 || !probeText.contains('-->')) {
            continue;
          }
        } catch (_) {
          continue;
        }
        _testItem = item;
        _testSubIndex = subIndex;
        _testSubCodec = (m['Codec'] as String? ?? 'srt').toLowerCase();
        break;
      }
      if (_testItem != null) break;
    }
  });

  tearDownAll(() async {
    // H. Reset the playback state written by the progress lifecycle tests.
    if (_server == null || _userId == null) return;
    final item = _testItem;
    if (item != null) {
      final id = item['Id'] as String;
      try {
        await _postJson('/emby/Sessions/Playing/Progress', {
          'ItemId': id,
          'MediaSourceId': 'mediasource_$id',
          'PlaySessionId': 'live-test-cleanup',
          'PositionTicks': 0,
          'IsPaused': true,
          'CanSeek': true,
          'UserId': _userId,
          'PlayMethod': 'DirectPlay',
        });
        await _postJson('/emby/Users/$_userId/PlayedItems/$id/Delete', {});
      } catch (_) {
        // Best effort — a leftover resume position is cosmetic.
      }
    }
    if (_user != null) {
      try {
        await _postJson('/emby/Sessions/Logout', {});
      } catch (_) {}
    }
    _client.close();
  });

  group('live Emby playback matrix', () {
    test('A. authentication', () {
      expect(_skip(), isFalse, reason: 'EMBY_LIVE_SERVER not set');
      expect(_token, isNotNull);
      expect(_userId, isNotNull);
    }, skip: _skip() ? 'set EMBY_LIVE_SERVER (+ USER/PASS or API_KEY)' : false);

    test('B1. PlaybackInfo (desktop profile) direct-play decision', () async {
      final item = _requireTestItem();
      final pb = await _playbackInfo(item['Id'] as String, kind: 'desktop');
      final sources = pb['MediaSources'] as List<dynamic>;
      expect(sources, isNotEmpty, reason: 'no MediaSources');
      final src = sources.first as Map<String, dynamic>;
      expect(src['SupportsDirectPlay'], isTrue,
          reason: 'strm items must direct-play (no server transcode)');
      expect(src['DirectStreamUrl'], isNotNull,
          reason: 'go-emby2openlist must expose a DirectStreamUrl');
      expect(pb['PlaySessionId'], isNotNull);
    }, skip: _skip() ? 'live only' : false);

    test('B2. PlaybackInfo (android profile) parses', () async {
      final item = _requireTestItem();
      final pb = await _playbackInfo(item['Id'] as String, kind: 'android');
      final src = (pb['MediaSources'] as List<dynamic>).first
          as Map<String, dynamic>;
      expect(src['Id'], isNotNull);
    }, skip: _skip() ? 'live only' : false);

    test('B3. PlaybackInfo returns the external subtitle track', () async {
      final item = _requireTestItem();
      final pb = await _playbackInfo(item['Id'] as String);
      final src = (pb['MediaSources'] as List<dynamic>).first
          as Map<String, dynamic>;
      final subs = (src['MediaStreams'] as List<dynamic>? ?? const [])
          .where((s) => (s as Map<String, dynamic>)['Type'] == 'Subtitle')
          .toList();
      expect(subs, isNotEmpty,
          reason: 'test item was selected for having external subtitles');
    }, skip: _skip() ? 'live only' : false);

    test('C1. strm proxy 307 resolves to a CDN host', () async {
      final item = _requireTestItem();
      final id = item['Id'] as String;
      final url = '$_server/emby/Videos/$id/stream'
          '?MediaSourceId=mediasource_$id&X-Emby-Token=$_token';
      final cdn = await _resolveCdnUrl(url);
      final host = Uri.parse(cdn).host;
      expect(host, isNot(equals(Uri.parse(_server!).host)),
          reason: 'expected a CDN redirect target, got $cdn');
    }, skip: _skip() ? 'live only' : false);

    test('C2-C4. CDN byte-range seek (head / middle / tail Cues)', () async {
      final item = _requireTestItem();
      final id = item['Id'] as String;
      final url = '$_server/emby/Videos/$id/stream'
          '?MediaSourceId=mediasource_$id&X-Emby-Token=$_token';
      final cdn = await _resolveCdnUrl(url);

      // Probe size with a 1-byte range.
      final head = await _rangeGet(cdn, 0, 0);
      expect(head.statusCode, 206, reason: 'head range failed');
      await head.drain<void>();
      final contentRange = head.headers.value(HttpHeaders.contentRangeHeader)!;
      final total = int.parse(contentRange.split('/').last);
      expect(total, greaterThan(1024 * 1024), reason: 'implausible file size');

      // Tail (MKV Cues live in the last 64KB — the seek-critical range).
      final tail = await _rangeGet(cdn, total - 65536, total - 1);
      expect(tail.statusCode, 206, reason: 'tail range (Cues) failed');
      final tailRange = tail.headers.value(HttpHeaders.contentRangeHeader)!;
      expect(tailRange, contains('bytes ${total - 65536}-'));
      await tail.drain<void>();

      // Middle.
      final mid = await _rangeGet(cdn, total ~/ 2, total ~/ 2 + 1023);
      expect(mid.statusCode, 206, reason: 'middle range failed');
      await mid.drain<void>();
    }, skip: _skip() ? 'live only' : false);

    test('D. 115 CDN UA binding contract (guards CDN-direct mode)', () async {
      final item = _requireTestItem();
      final id = item['Id'] as String;
      final url = '$_server/emby/Videos/$id/stream'
          '?MediaSourceId=mediasource_$id&X-Emby-Token=$_token';

      // Same UA for resolve + access → must succeed (the app's CDN-direct
      // mode relies on this after the resolveExternalCdnUrl fix).
      final cdn = await _resolveCdnUrl(url);
      final ok = await _rangeGet(cdn, 0, 1023);
      expect(ok.statusCode, 206,
          reason: 'same-UA resolve+access must work for CDN-direct mode');
      await ok.drain<void>();

      // Mismatched UA → 403. The signed URL is bound to the resolving UA.
      final cdnOther = await _resolveCdnUrl(url, ua: '$_chromeUa/x');
      final forbidden = await _rangeGet(cdnOther, 0, 1023, ua: 'libmpv-test');
      expect(
        forbidden.statusCode,
        anyOf(403, 404),
        reason: 'UA mismatch should be rejected by the 115 CDN '
            '(if this fails, the CDN stopped binding UAs — revisit '
            'resolveExternalCdnUrl docs)',
      );
      await forbidden.drain<void>();
    }, skip: _skip() ? 'live only' : false);

    test('E1. subtitle ASS original stream', () async {
      final item = _requireTestItem();
      final id = item['Id'] as String;
      final req = await _client.getUrl(
        _u('/emby/Videos/$id/mediasource_$id/Subtitles/$_testSubIndex'
            '/Stream.ass?api_key=$_token'),
      );
      final res = await req.close();
      final text = await res.transform(utf8.decoder).join();
      expect(res.statusCode, 200,
          reason: 'subtitle endpoint rejected the request');
      expect(text, contains('[Script Info]'),
          reason: 'expected ASS script header (source codec=$_testSubCodec)');
    }, skip: _skip() ? 'live only' : false);

    test('E2. server converts subtitle to SRT', () async {
      final item = _requireTestItem();
      final id = item['Id'] as String;
      final req = await _client.getUrl(
        _u('/emby/Videos/$id/mediasource_$id/Subtitles/$_testSubIndex'
            '/Stream.srt?api_key=$_token'),
      );
      final res = await req.close();
      final text = await res.transform(utf8.decoder).join();
      expect(res.statusCode, 200,
          reason: 'subtitle endpoint rejected the request');
      expect(text, contains('-->'), reason: 'expected SRT timing arrows');
    }, skip: _skip() ? 'live only' : false);

    test('E3. server converts subtitle to VTT', () async {
      final item = _requireTestItem();
      final id = item['Id'] as String;
      final req = await _client.getUrl(
        _u('/emby/Videos/$id/mediasource_$id/Subtitles/$_testSubIndex'
            '/Stream.vtt?api_key=$_token'),
      );
      final res = await req.close();
      final text = await res.transform(utf8.decoder).join();
      expect(res.statusCode, 200,
          reason: 'subtitle endpoint rejected the request');
      expect(text, startsWith('WEBVTT'), reason: 'expected WEBVTT header');
    }, skip: _skip() ? 'live only' : false);

    test('F. progress lifecycle: Started → Progress → Stopped → resume state',
        () async {
      final item = _requireTestItem();
      final id = item['Id'] as String;
      final pb = await _playbackInfo(id);
      final psid = pb['PlaySessionId'] as String;

      Map<String, dynamic> body(int ticks, {bool paused = false}) => {
            'QueueableMediaTypes': ['Audio', 'Video'],
            'CanSeek': true,
            'ItemId': id,
            'MediaSourceId': 'mediasource_$id',
            'IsPaused': paused,
            'IsMuted': false,
            'PositionTicks': ticks,
            'VolumeLevel': 100,
            'PlayMethod': 'DirectPlay',
            'PlaySessionId': psid,
            'PlaylistIndex': 0,
            'PlaylistLength': 1,
            'PlaybackRate': 1,
            'UserId': _userId,
          };

      // All three reports must be accepted by the server (2xx).
      await _postJson('/emby/Sessions/Playing', body(5 * 600000000));
      await _postJson('/emby/Sessions/Playing/Progress',
          {...body(10 * 600000000), 'EventName': 'TimeUpdate'});
      await _postJson('/emby/Sessions/Playing/Stopped',
          body(12 * 600000000, paused: true));

      // Intermediate Progress reports do not land in UserData on this
      // stack until playback stops (go-emby2openlist bridges that with its
      // auxiliary Progress after Stopped, asynchronously) — poll for the
      // final state, which is what the app's resume flow reads.
      var detail = await _getJson('/emby/Users/$_userId/Items/$id');
      var userData = detail['UserData'] as Map<String, dynamic>;
      const expected = 12 * 600000000;
      for (var i = 0;
          i < 10 &&
              (userData['PlaybackPositionTicks'] as num? ?? 0) != expected;
          i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        detail = await _getJson('/emby/Users/$_userId/Items/$id');
        userData = detail['UserData'] as Map<String, dynamic>;
      }
      expect(userData['PlaybackPositionTicks'], expected,
          reason: 'Stopped position must become the resume source');
      expect(userData['Played'], isFalse,
          reason: '~51% watched must not mark the item as played');
    }, skip: _skip() ? 'live only' : false);

    test('G. PlaybackInfo accepts StartTimeTicks (resume echo)', () async {
      final item = _requireTestItem();
      final id = item['Id'] as String;
      final pb =
          await _playbackInfo(id, startTimeTicks: 7 * 600000000);
      final sources = pb['MediaSources'] as List<dynamic>;
      expect(sources, isNotEmpty,
          reason: 'server rejected the resume PlaybackInfo request');
    }, skip: _skip() ? 'live only' : false);

    test('H. stream URL works with query-param auth only (mpv constraint)', () async {
      final item = _requireTestItem();
      final id = item['Id'] as String;
      final req = await _client.getUrl(
        _u('/emby/Videos/$id/stream?MediaSourceId=mediasource_$id'
            '&X-Emby-Token=$_token'),
      );
      // No auth header at all — the token travels in the query string only
      // (go-emby2openlist reads X-Emby-Token from the query on /stream).
      // Do not follow the 307, otherwise the whole file would download.
      req.followRedirects = false;
      final res = await req.close();
      expect(res.statusCode, anyOf(200, 206, 307),
          reason: 'query-param auth must be accepted (got ${res.statusCode})');
      await res.drain<void>();
    }, skip: _skip() ? 'live only' : false);
  });
}
