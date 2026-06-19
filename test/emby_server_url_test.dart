import 'package:flutter_test/flutter_test.dart';
import 'package:media_client/utils/emby_server_url.dart';

void main() {
  group('embyServerUrlCandidates', () {
    test('no scheme tries https then http without forcing port', () {
      expect(
        embyServerUrlCandidates('192.168.1.10'),
        ['https://192.168.1.10', 'http://192.168.1.10'],
      );
    });

    test('no scheme keeps explicit port', () {
      expect(
        embyServerUrlCandidates('192.168.1.10:8920'),
        ['https://192.168.1.10:8920', 'http://192.168.1.10:8920'],
      );
    });

    test('http scheme returns single candidate unchanged', () {
      expect(
        embyServerUrlCandidates('http://192.168.1.10'),
        ['http://192.168.1.10'],
      );
    });

    test('https scheme preserves host without adding port', () {
      expect(
        embyServerUrlCandidates('https://emby.local'),
        ['https://emby.local'],
      );
    });

    test('empty input returns empty list', () {
      expect(embyServerUrlCandidates(''), isEmpty);
      expect(embyServerUrlCandidates('   '), isEmpty);
    });
  });

  group('embyApiRootForServerUrl', () {
    test('builds emby root with explicit port', () {
      expect(
        embyApiRootForServerUrl('http://192.168.1.10:8096'),
        'http://192.168.1.10:8096/emby',
      );
    });

    test('builds emby root without port uses scheme default', () {
      expect(
        embyApiRootForServerUrl('https://emby.example.com'),
        'https://emby.example.com/emby',
      );
    });
  });
}
