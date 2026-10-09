import 'package:flutter_test/flutter_test.dart';
import 'package:media_client/core/player/player_volume_memory.dart';

void main() {
  group('volumeToPersist', () {
    test('muted / negative / NaN are transient and not persisted', () {
      expect(volumeToPersist(0), isNull);
      expect(volumeToPersist(-3), isNull);
      expect(volumeToPersist(double.nan), isNull);
      expect(volumeToPersist(-double.infinity), isNull);
    });

    test('audible levels persist as-is', () {
      expect(volumeToPersist(40), 40);
      expect(volumeToPersist(0.5), 0.5);
      expect(volumeToPersist(100), 100);
      expect(volumeToPersist(12.34), 12.34);
    });

    test('values above the mpv ceiling clamp to 100', () {
      expect(volumeToPersist(130), 100);
      expect(volumeToPersist(double.infinity), 100);
    });
  });

  group('restorePlayerVolume', () {
    test('missing / unusable saved values fall back to mpv default 100', () {
      expect(restorePlayerVolume(null), 100);
      expect(restorePlayerVolume(0), 100);
      expect(restorePlayerVolume(-1), 100);
      expect(restorePlayerVolume(double.nan), 100);
      expect(restorePlayerVolume(double.infinity), 100);
    });

    test('audible saved values restore as-is', () {
      expect(restorePlayerVolume(37), 37);
      expect(restorePlayerVolume(0.5), 0.5);
      expect(restorePlayerVolume(100), 100);
    });

    test('out-of-range saved values clamp to 100', () {
      expect(restorePlayerVolume(240), 100);
    });
  });
}
