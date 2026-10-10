import 'package:flutter_test/flutter_test.dart';
import 'package:media_client/config/app_config.dart';
import 'package:media_client/core/player/external_cdn_headers.dart';

void main() {
  group('classifyExternalCdnUrl', () {
    test('recognizes 115 CDN hosts', () {
      expect(
        classifyExternalCdnUrl('https://cdnfhnfile.115cdn.net/file.mkv'),
        ExternalCdnKind.p115,
      );
      expect(
        classifyExternalCdnUrl('https://115.com/file.mkv'),
        ExternalCdnKind.p115,
      );
      expect(is115CdnPlaybackUrl('https://cdnfhnfile.115cdn.net/x'), isTrue);
    });

    test('recognizes Quark drive CDN hosts', () {
      expect(
        classifyExternalCdnUrl(
          'https://dl-c-zb-u.drive.quark.cn/jd0SmaYX/file.mp4?auth_key=1',
        ),
        ExternalCdnKind.quark,
      );
      expect(isQuarkCdnPlaybackUrl('https://drive.quark.cn/x'), isTrue);
      expect(isQuarkCdnPlaybackUrl('https://quark.cn/x'), isTrue);
    });

    test('ignores the Emby server, OpenList and unknown hosts', () {
      expect(
        classifyExternalCdnUrl('http://117.72.57.88:8095/emby/Videos/1/stream'),
        ExternalCdnKind.none,
      );
      expect(
        classifyExternalCdnUrl('http://openlist:5244/d/quarktv/x.mp4'),
        ExternalCdnKind.none,
      );
      expect(
        classifyExternalCdnUrl('https://cdn.example.com/movie.mkv'),
        ExternalCdnKind.none,
      );
      expect(isExternalCdnPlaybackUrl('https://cdn.example.com/m'), isFalse);
    });
  });

  group('externalCdnPlaybackHttpHeadersForUrl', () {
    test('115 needs its hotlink Referer/Origin plus UA', () {
      final headers = externalCdnPlaybackHttpHeadersForUrl(
        'https://cdnfhnfile.115cdn.net/x',
      );
      expect(headers['Referer'], 'https://115.com/');
      expect(headers['Origin'], 'https://115.com/');
      expect(headers['User-Agent'], AppConfig.httpUserAgent);
    });

    test('Quark sends UA only (any Referer is rejected with 403)', () {
      final headers = externalCdnPlaybackHttpHeadersForUrl(
        'https://dl-c-zb-u.drive.quark.cn/jd0SmaYX/file.mp4',
      );
      expect(headers.containsKey('Referer'), isFalse);
      expect(headers.containsKey('Origin'), isFalse);
      expect(headers['User-Agent'], AppConfig.httpUserAgent);
    });

    test('non-CDN URLs yield no overrides', () {
      expect(
        externalCdnPlaybackHttpHeadersForUrl('http://openlist:5244/d/x.mp4'),
        isEmpty,
      );
    });
  });
}
