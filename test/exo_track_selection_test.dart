import 'package:flutter_test/flutter_test.dart';

import 'package:media_client/core/player/exo/exo_network_error.dart';
import 'package:media_client/core/player/exo/exo_track_selection.dart';
import 'package:media_client/core/player/netdisk_recovery.dart';
import 'package:media_client/models/emby/emby_subtitle_option.dart';

EmbySubtitleOption _sub({
  required int index,
  String format = 'srt',
  String? language,
  bool isExternal = true,
  bool isDefault = false,
  bool isForced = false,
}) {
  return EmbySubtitleOption(
    index: index,
    label: 'sub $index',
    streamUrl: 'http://server/Videos/1/2/Subtitles/$index/Stream.$format',
    format: format,
    language: language,
    isDefault: isDefault,
    isForced: isForced,
    isExternal: isExternal,
  );
}

ExoPlayerTrack _track(
  String id,
  String label, {
  String? language,
}) {
  return ExoPlayerTrack(id: id, label: label, language: language);
}

void main() {
  group('resolveInitialSubtitleSelection', () {
    test('saved no disables subtitles', () {
      final target = resolveInitialSubtitleSelection(
        saved: 'no',
        embySubtitles: [_sub(index: 1)],
        nativeTextTracks: const [],
      );
      expect(target, isA<ExoSubtitleOff>());
    });

    test('saved emby selection maps to the external option', () {
      final target = resolveInitialSubtitleSelection(
        saved: 'emby:3',
        embySubtitles: [_sub(index: 1), _sub(index: 3, format: 'ass')],
        nativeTextTracks: const [],
      );
      expect(target, isA<ExoSubtitleExternal>());
      expect((target as ExoSubtitleExternal).option.index, 3);
    });

    test('saved emby selection falls back when the track vanished', () {
      final target = resolveInitialSubtitleSelection(
        saved: 'emby:9',
        embySubtitles: [_sub(index: 1, isDefault: true)],
        nativeTextTracks: const [],
      );
      expect(target, isA<ExoSubtitleExternal>());
      expect((target as ExoSubtitleExternal).option.index, 1);
    });

    test('saved muxed key matches by language + label', () {
      final track = _track('t:0:1', 'Chinese (Simplified)', language: 'chi');
      final key = muxedTrackPreferenceKey(track);
      final target = resolveInitialSubtitleSelection(
        saved: 'track:$key',
        embySubtitles: const [],
        nativeTextTracks: [track, _track('t:1:0', 'English', language: 'eng')],
      );
      expect(target, isA<ExoSubtitleMuxed>());
      expect((target as ExoSubtitleMuxed).track.id, 't:0:1');
    });

    test('auto prefers default external text over muxed', () {
      final target = resolveInitialSubtitleSelection(
        saved: 'auto',
        embySubtitles: [
          _sub(index: 5, isDefault: true),
          _sub(index: 6),
        ],
        nativeTextTracks: [_track('t:0:0', 'English')],
      );
      expect(target, isA<ExoSubtitleExternal>());
      expect((target as ExoSubtitleExternal).option.index, 5);
    });

    test('embedded default text sub renders from the container, not the API', () {
      // Emby flags the embedded subrip track as default, and its subtitle API
      // returns nothing for embedded tracks — so it must go through the native
      // muxed track (this is the "default SUBRIP shows nothing" bug).
      final target = resolveInitialSubtitleSelection(
        saved: 'auto',
        embySubtitles: [
          _sub(index: 4, isExternal: false, isDefault: true, language: 'chi'),
        ],
        nativeTextTracks: [_track('t:0:0', 'Chinese', language: 'chi')],
      );
      expect(target, isA<ExoSubtitleMuxed>());
      expect((target as ExoSubtitleMuxed).track.id, 't:0:0');
    });

    test('external srt wins when the embedded default has no native track', () {
      final target = resolveInitialSubtitleSelection(
        saved: 'auto',
        embySubtitles: [
          _sub(index: 2, isExternal: false, isDefault: true, language: 'chi'),
          _sub(index: 3, isExternal: true, language: 'zh-CN'),
        ],
        nativeTextTracks: const [],
      );
      expect(target, isA<ExoSubtitleExternal>());
      expect((target as ExoSubtitleExternal).option.index, 3);
    });

    test('saved embedded emby id falls back instead of failing to fetch', () {
      final target = resolveInitialSubtitleSelection(
        saved: 'emby:2',
        embySubtitles: [
          _sub(index: 2, isExternal: false, language: 'chi'),
          _sub(index: 3, isExternal: true, language: 'zh-CN'),
        ],
        nativeTextTracks: [_track('t:0:0', 'Chinese', language: 'chi')],
      );
      expect(target, isA<ExoSubtitleExternal>());
      expect((target as ExoSubtitleExternal).option.index, 3);
    });

    test('external srt wins over an embedded PGS default', () {
      final target = resolveInitialSubtitleSelection(
        saved: 'auto',
        embySubtitles: [
          _sub(index: 2, isExternal: false, isDefault: true, format: 'pgs', language: 'chi'),
          _sub(index: 15, isExternal: true, language: 'zh-CN'),
        ],
        nativeTextTracks: [_track('t:0:0', 'Chinese (默认 PGSSUB)', language: 'chi')],
      );
      expect(target, isA<ExoSubtitleExternal>());
      expect((target as ExoSubtitleExternal).option.index, 15);
    });

    test('embedded stream with no native match is still fetched as a fallback', () {
      final target = resolveInitialSubtitleSelection(
        saved: 'auto',
        embySubtitles: [
          _sub(index: 2, isExternal: false, language: 'chi'),
        ],
        nativeTextTracks: const [],
      );
      expect(target, isA<ExoSubtitleExternal>());
      expect((target as ExoSubtitleExternal).option.index, 2);
    });

    test('auto falls back to the default-flagged bitmap (PGS) muxed track', () {
      final chinese = _track('t:0:0', 'Chinese (Simplified) - PGS', language: 'chi');
      final target = resolveInitialSubtitleSelection(
        saved: null,
        embySubtitles: [
          _sub(
            index: 4,
            isExternal: false,
            isDefault: true,
            format: 'pgs',
            language: 'chi',
          ),
        ],
        nativeTextTracks: [chinese, _track('t:1:0', 'English', language: 'eng')],
      );
      expect(target, isA<ExoSubtitleMuxed>());
      expect((target as ExoSubtitleMuxed).track.id, 't:0:0');
    });

    test('auto picks the single muxed track when Emby has no default', () {
      final only = _track('t:0:0', 'Only');
      final target = resolveInitialSubtitleSelection(
        saved: 'auto',
        embySubtitles: const [],
        nativeTextTracks: [only],
      );
      expect(target, isA<ExoSubtitleMuxed>());
    });

    test('auto stays off with multiple muxed tracks and no default', () {
      final target = resolveInitialSubtitleSelection(
        saved: 'auto',
        embySubtitles: const [],
        nativeTextTracks: [
          _track('t:0:0', 'A'),
          _track('t:1:0', 'B'),
        ],
      );
      expect(target, isA<ExoSubtitleOff>());
    });

    test('bitmap (PGS) emby tracks are never selected as external', () {
      final target = resolveInitialSubtitleSelection(
        saved: 'emby:2',
        embySubtitles: [_sub(index: 2, format: 'pgs')],
        nativeTextTracks: const [],
      );
      expect(target, isA<ExoSubtitleOff>());
    });
  });

  group('externalSubtitleChoices', () {
    test('embedded streams are hidden while the container exposes tracks', () {
      final choices = externalSubtitleChoices(
        embySubtitles: [
          _sub(index: 2, isExternal: false, isDefault: true, language: 'chi'),
          _sub(index: 3, isExternal: true, language: 'zh-CN'),
        ],
        nativeTextTracks: [_track('t:1:0', 'link3.cc/yiiha 发布', language: 'chi')],
      );
      expect(choices.map((c) => c.index), [3]);
    });

    test('embedded streams stay reachable without native tracks', () {
      final choices = externalSubtitleChoices(
        embySubtitles: [
          _sub(index: 2, isExternal: false, language: 'chi'),
        ],
        nativeTextTracks: const [],
      );
      expect(choices.map((c) => c.index), [2]);
    });

    test('bitmap streams are never offered as fetchable', () {
      final choices = externalSubtitleChoices(
        embySubtitles: [_sub(index: 4, format: 'pgs', isExternal: true)],
        nativeTextTracks: const [],
      );
      expect(choices, isEmpty);
    });
  });

  group('normaliseSubtitleLanguage', () {
    test('collapses Emby and media3 codes for the same language', () {
      expect(normaliseSubtitleLanguage('chi'), 'zh');
      expect(normaliseSubtitleLanguage('zho'), 'zh');
      expect(normaliseSubtitleLanguage('zh-CN'), 'zh');
      expect(normaliseSubtitleLanguage('eng'), 'en');
      expect(normaliseSubtitleLanguage('en'), 'en');
      expect(normaliseSubtitleLanguage('jpn'), 'ja');
      expect(normaliseSubtitleLanguage(null), isNull);
      expect(normaliseSubtitleLanguage('  '), isNull);
    });

    test('matches a native track despite chi/zho mismatch', () {
      final track = _track('t:1:0', 'link3.cc/yiiha 发布', language: 'zho');
      final option = _sub(index: 2, isExternal: false, language: 'chi');
      expect(matchNativeTextTrack([track], option)?.id, 't:1:0');
    });
  });

  group('ExoTrackCatalog', () {
    test('parses unsupported audio tracks (no decoder on device)', () {
      final catalog = ExoTrackCatalog.fromMap({
        'audio': <Object?>[],
        'text': [
          {'id': 't:2:0', 'label': 'Chinese'},
        ],
        'unsupportedAudio': [
          {'id': 'a:1:0', 'label': 'English EAC3 5.1', 'mime': 'audio/eac3'},
        ],
      });
      expect(catalog.audio, isEmpty);
      expect(catalog.text.length, 1);
      expect(catalog.unsupportedAudio.single.label, 'English EAC3 5.1');
      expect(catalog.unsupportedAudio.single.id, 'a:1:0');
    });

    test('tolerates a catalog without the unsupported list', () {
      final catalog = ExoTrackCatalog.fromMap({'audio': <Object?>[], 'text': <Object?>[]});
      expect(catalog.unsupportedAudio, isEmpty);
    });
  });

  group('shouldUseRedirectFallback', () {
    test('expired signed URL falls back to the redirecting stream URL', () {
      expect(
        shouldUseRedirectFallback(
          statusCode: 403,
          connectionFailed: false,
          redirectUrl: 'http://host:8095/videos/1/stream?Static=true',
          activeUrl: 'https://cdn.example/file.mkv?sig=abc',
        ),
        isTrue,
      );
      expect(
        shouldUseRedirectFallback(
          statusCode: 401,
          connectionFailed: false,
          redirectUrl: 'http://host:8095/videos/1/stream?Static=true',
          activeUrl: 'https://cdn.example/file.mkv?sig=abc',
        ),
        isTrue,
      );
    });

    test('no fallback without a redirecting URL or when already using it', () {
      expect(
        shouldUseRedirectFallback(
          statusCode: 403,
          connectionFailed: false,
          redirectUrl: null,
          activeUrl: 'https://cdn.example/file.mkv',
        ),
        isFalse,
      );
      expect(
        shouldUseRedirectFallback(
          statusCode: 403,
          connectionFailed: false,
          redirectUrl: 'https://cdn.example/file.mkv',
          activeUrl: 'https://cdn.example/file.mkv',
        ),
        isFalse,
      );
    });

    test('connection failures and 5xx use the refresh path instead', () {
      expect(
        shouldUseRedirectFallback(
          statusCode: null,
          connectionFailed: true,
          redirectUrl: 'http://host/stream',
          activeUrl: 'https://cdn.example/file.mkv',
        ),
        isFalse,
      );
      expect(
        shouldUseRedirectFallback(
          statusCode: 503,
          connectionFailed: false,
          redirectUrl: 'http://host/stream',
          activeUrl: 'https://cdn.example/file.mkv',
        ),
        isFalse,
      );
    });
  });

  group('reResolveDelay', () {
    test('stays short so an expired seek recovers quickly', () {
      expect(reResolveDelay(1), const Duration(milliseconds: 300));
      expect(reResolveDelay(2), const Duration(seconds: 1));
      expect(reResolveDelay(5), const Duration(seconds: 1));
    });
  });

  group('muxedTrackPreferenceKey', () {
    test('stable across native id changes', () {
      final a = _track('t:0:0', 'Chinese', language: 'chi');
      final b = _track('t:2:3', 'Chinese', language: 'chi');
      expect(muxedTrackPreferenceKey(a), muxedTrackPreferenceKey(b));
      expect(matchMuxedTrack([b], muxedTrackPreferenceKey(a))?.id, 't:2:3');
    });
  });

  group('exo network error predicates', () {
    test('recognizes recoverable transport failures', () {
      expect(isRecoverableExoNetworkError('Source error'), isTrue);
      expect(isRecoverableExoNetworkError('InvalidResponseCodeException: Response code: 502'), isTrue);
      expect(isRecoverableExoNetworkError('Response code: 429'), isTrue);
      expect(isRecoverableExoNetworkError('Unable to connect to host'), isTrue);
      expect(isRecoverableExoNetworkError('Unexpected loader exception'), isTrue);
      expect(isRecoverableExoNetworkError('Decoder init failed'), isFalse);
    });

    test('recognizes signed-url expiry for re-bootstrap', () {
      expect(isExoSignedUrlExpiredError('Response code: 403'), isTrue);
      expect(isExoSignedUrlExpiredError('Response code: 410'), isTrue);
      expect(isExoSignedUrlExpiredError('Response code: 500'), isFalse);
    });
  });
}
