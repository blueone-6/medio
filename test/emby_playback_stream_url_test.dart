import 'package:flutter_test/flutter_test.dart';
import 'package:media_client/models/emby/emby_playback_info.dart';

void main() {
  group('EmbyPlaybackInfo stream URL selection', () {
    const itemId = 'item-guid';
    const mediaSourceId = 'ms-guid';
    const server = 'http://192.168.1.10:8096';

    test('prefers transcode URLs when SupportsDirectPlay is false', () {
      final info = EmbyPlaybackInfo.fromResponse(
        {
          'PlaySessionId': 'session-1',
          'MediaSources': [
            {
              'Id': mediaSourceId,
              'SupportsDirectPlay': false,
              'Path': 'https://cdn.example.com/movie.mkv',
              'DirectStreamUrl':
                  '/videos/$itemId/stream?MediaSourceId=$mediaSourceId&Static=true',
              'TranscodingUrl':
                  '/videos/$itemId/stream.m3u8?MediaSourceId=$mediaSourceId',
            },
          ],
        },
        itemId: itemId,
        serverPublicBase: server,
        accessToken: 'secret-token',
      );

      expect(info.supportsDirectPlay, isFalse);
      expect(info.streamUrl, contains('/videos/$itemId/stream?'));
      expect(info.streamUrl, isNot(contains('cdn.example.com')));
      expect(info.fallbackStreamUrl, info.streamUrl);
    });

    test('keeps direct CDN path when SupportsDirectPlay is true', () {
      const cdn = 'https://cdn.example.com/movie.mkv';

      final info = EmbyPlaybackInfo.fromResponse(
        {
          'MediaSources': [
            {
              'Id': mediaSourceId,
              'SupportsDirectPlay': true,
              'Path': cdn,
              'TranscodingUrl':
                  '/videos/$itemId/stream.m3u8?MediaSourceId=$mediaSourceId',
            },
          ],
        },
        itemId: itemId,
        serverPublicBase: server,
        accessToken: 'tok',
      );

      expect(info.streamUrl, '$cdn?api_key=tok');
      expect(info.fallbackStreamUrl, contains('/videos/$itemId/stream.m3u8'));
    });

  });
}
