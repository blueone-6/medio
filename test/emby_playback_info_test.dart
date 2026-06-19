import 'package:flutter_test/flutter_test.dart';
import 'package:media_client/models/emby/emby_playback_info.dart';

void main() {
  group('EmbyPlaybackInfo subtitles', () {
    test('parses subtitle streams and builds Subtitles API URLs', () {
      const itemId = 'item-guid';
      const mediaSourceId = 'ms-guid';
      const server = 'http://192.168.1.10:8096';

      final json = {
        'PlaySessionId': 'session-1',
        'MediaSources': [
          {
            'Id': mediaSourceId,
            'Path': 'https://cdn.example.com/movie.mkv',
            'MediaStreams': [
              {
                'Type': 'Video',
                'Index': 0,
              },
              {
                'Type': 'Subtitle',
                'Index': 2,
                'Codec': 'subrip',
                'Language': 'chi',
                'DisplayTitle': '简体中文',
                'IsExternal': true,
                'IsDefault': true,
              },
              {
                'Type': 'Subtitle',
                'Index': 3,
                'Codec': 'ass',
                'Language': 'eng',
                'Title': 'English',
              },
            ],
          },
        ],
      };

      final info = EmbyPlaybackInfo.fromResponse(
        json,
        itemId: itemId,
        serverPublicBase: server,
        accessToken: 'secret-token',
      );

      expect(info.subtitles.length, 2);
      expect(info.subtitles[0].index, 2);
      expect(info.subtitles[0].label, '简体中文');
      expect(info.subtitles[0].format, 'srt');
      expect(info.subtitles[0].isExternal, isTrue);
      expect(info.subtitles[0].isDefault, isTrue);
      expect(
        info.subtitles[0].streamUrl,
        'http://192.168.1.10:8096/emby/Videos/$itemId/$mediaSourceId/Subtitles/2/Stream.srt?api_key=secret-token',
      );

      expect(info.subtitles[1].format, 'ass');
      expect(info.subtitles[1].isExternal, isFalse);
      expect(
        info.subtitles[1].streamUrl,
        'http://192.168.1.10:8096/emby/Videos/$itemId/$mediaSourceId/Subtitles/3/Stream.ass?api_key=secret-token',
      );
      expect(info.preferredSubtitle?.index, 2);

      final noDefault = EmbyPlaybackInfo.fromResponse(
        {
          'MediaSources': [
            {
              'Id': mediaSourceId,
              'Path': 'https://cdn.example.com/movie.mkv',
              'MediaStreams': [
                {
                  'Type': 'Subtitle',
                  'Index': 5,
                  'Codec': 'srt',
                },
              ],
            },
          ],
        },
        itemId: itemId,
        serverPublicBase: server,
      );
      expect(noDefault.preferredSubtitle, isNull);
    });

    test('preferredExoTextSubtitle skips PGS default and prefers SRT', () {
      const itemId = 'item-guid';
      const mediaSourceId = 'ms-guid';
      const server = 'http://192.168.1.10:8096';

      final json = {
        'MediaSources': [
          {
            'Id': mediaSourceId,
            'Path': 'https://cdn.example.com/movie.mkv',
            'MediaStreams': [
              {
                'Type': 'Subtitle',
                'Index': 1,
                'Codec': 'hdmv_pgs_subtitle',
                'DisplayTitle': '特效字幕',
                'IsDefault': true,
              },
              {
                'Type': 'Subtitle',
                'Index': 2,
                'Codec': 'subrip',
                'Language': 'chi',
                'DisplayTitle': '简体中文',
              },
              {
                'Type': 'Subtitle',
                'Index': 3,
                'Codec': 'ass',
                'Language': 'eng',
                'Title': 'English ASS',
              },
            ],
          },
        ],
      };

      final info = EmbyPlaybackInfo.fromResponse(
        json,
        itemId: itemId,
        serverPublicBase: server,
        accessToken: 'tok',
      );

      final exo = info.preferredExoTextSubtitle;
      expect(exo, isNotNull);
      expect(exo!.index, 2);
      expect(exo.format, 'srt');
      expect(exo.exoStreamFormat, 'srt');
      expect(exo.exoStreamUrl, contains('/Subtitles/2/Stream.srt'));

      final ass = info.subtitles.firstWhere((t) => t.index == 3);
      expect(ass.exoStreamFormat, 'srt');
      expect(ass.exoStreamUrl, contains('/Subtitles/3/Stream.srt'));
      expect(ass.exoStreamUrl, isNot(contains('Stream.ass')));
    });

    test('resolvePlaybackStreamUrl proxies strm redirect on fresh play', () {
      const itemId = '2465';
      const mediaSourceId = 'mediasource_2465';
      const server = 'https://media.example.com';

      final info = EmbyPlaybackInfo(
        playSessionId: 'session-1',
        mediaSourceId: mediaSourceId,
        streamUrl:
            'http://strm-proxy:3000/api/v1/redirect_url?pickcode=abc&api_key=tok',
      );

      final url = resolvePlaybackStreamUrl(
        info: info,
        itemId: itemId,
        serverPublicBase: server,
        accessToken: 'tok',
      );

      expect(url, contains('/Videos/$itemId/stream'));
      expect(url, isNot(contains('stream.mkv')));
      expect(url, contains('MediaSourceId=$mediaSourceId'));
      expect(url, contains('Static=true'));
      expect(url, contains('X-Emby-Token=tok'));
      expect(url, isNot(contains('PlaySessionId')));
      expect(url, isNot(contains('strm-proxy')));
    });

    test('resolvePlaybackStreamUrl proxies strm redirect on resume without stream ticks', () {
      const itemId = '2465';
      const mediaSourceId = 'mediasource_2465';
      const server = 'https://media.example.com';
      const ticks = 1253978370;

      final info = EmbyPlaybackInfo(
        playSessionId: 'session-1',
        mediaSourceId: mediaSourceId,
        streamUrl:
            'http://strm-proxy:3000/api/v1/redirect_url?pickcode=abc',
      );

      final url = resolvePlaybackStreamUrl(
        info: info,
        itemId: itemId,
        serverPublicBase: server,
        accessToken: 'tok',
        startTimeTicks: ticks,
      );

      expect(url, contains('/Videos/$itemId/stream'));
      expect(url, contains('Static=true'));
      expect(url, isNot(contains('StartTimeTicks')));
      expect(url, isNot(contains('PlaySessionId')));
      expect(url, isNot(contains('strm-proxy')));
    });

    test('strmViaEmbyStream marks Emby stream entry for P115 strm', () {
      const embyStreamUrl =
          'https://media.example.com/emby/Videos/2465/stream?MediaSourceId=mediasource_2465&Static=true&X-Emby-Token=tok';

      final info = EmbyPlaybackInfo(
        playSessionId: 'session-1',
        mediaSourceId: 'mediasource_2465',
        streamUrl: embyStreamUrl,
        strmViaEmbyStream: true,
      );

      expect(info.streamUrl, embyStreamUrl);
      expect(info.strmViaEmbyStream, isTrue);
    });

    test('resolvePlaybackStreamUrl keeps public CDN on fresh play', () {
      const itemId = 'item-guid';
      const mediaSourceId = 'ms-guid';
      const server = 'http://192.168.1.10:8096';
      const cdn = 'https://cdn.example.com/movie.mkv';

      final info = EmbyPlaybackInfo(
        playSessionId: 's',
        mediaSourceId: mediaSourceId,
        streamUrl: cdn,
      );

      final url = resolvePlaybackStreamUrl(
        info: info,
        itemId: itemId,
        serverPublicBase: server,
        accessToken: 'tok',
      );

      expect(url, cdn);
    });

    test('resolvePlaybackStreamUrl uses Emby stream for external CDN resume', () {
      const itemId = 'item-guid';
      const mediaSourceId = 'ms-guid';
      const server = 'http://192.168.1.10:8096';
      const ticks = 6000000000; // 10 min

      final info = EmbyPlaybackInfo(
        playSessionId: 's',
        mediaSourceId: mediaSourceId,
        streamUrl: 'https://cdn.example.com/movie.mkv',
      );

      final url = resolvePlaybackStreamUrl(
        info: info,
        itemId: itemId,
        serverPublicBase: server,
        accessToken: 'tok',
        startTimeTicks: ticks,
      );

      expect(url, contains('/Videos/$itemId/stream.mkv'));
      expect(url, contains('PlaySessionId=s'));
      expect(url, contains('MediaSourceId=$mediaSourceId'));
      expect(url, contains('StartTimeTicks=$ticks'));
      expect(url, isNot(contains('Static=true')));
      expect(url, contains('api_key=tok'));
    });

    test('playbackSourcesNeedStreamProxy detects strm redirect Path', () {
      final json = {
        'MediaSources': [
          {
            'Id': 'mediasource_2465',
            'Path':
                'http://strm-proxy:3000/api/v1/redirect_url?pickcode=abc',
            'DirectStreamUrl':
                '/videos/2465/stream?MediaSourceId=mediasource_2465&Static=true&StartTimeTicks=4036399835',
          },
        ],
      };
      expect(
        playbackSourcesNeedStreamProxy(json, 'https://media.example.com'),
        isTrue,
      );
    });

    test('buildEmbySubtitleStreamUrl respects /emby in server base path', () {
      final url = buildEmbySubtitleStreamUrl(
        serverPublicBase: 'http://host:8096/emby',
        itemId: 'a',
        mediaSourceId: 'b',
        index: 1,
        format: 'vtt',
        accessToken: 't',
      );
      expect(url, 'http://host:8096/emby/Videos/a/b/Subtitles/1/Stream.vtt?api_key=t');
    });
  });
}
