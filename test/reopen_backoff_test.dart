import 'package:flutter_test/flutter_test.dart';
import 'package:media_client/core/player/reopen_backoff.dart';

void main() {
  group('reopenBackoffDelay', () {
    test('first automatic re-open already waits 1s', () {
      // Even the first recovery benefits from a stop→open gap: it covers
      // both the CDN stale-connection window and the go-emby2openlist lazy
      // MediaSource resolution.
      expect(reopenBackoffDelay(0), const Duration(seconds: 1));
    });

    test('schedule escalates 1s → 3s → 6s → 10s', () {
      expect(reopenBackoffDelay(1), const Duration(seconds: 3));
      expect(reopenBackoffDelay(2), const Duration(seconds: 6));
      expect(reopenBackoffDelay(3), const Duration(seconds: 10));
    });

    test('caps at 10s for long failure streaks', () {
      // Production logs show the CDN recovering ~10-13s after the first
      // failed re-open; waiting longer than that adds nothing.
      expect(reopenBackoffDelay(4), const Duration(seconds: 10));
      expect(reopenBackoffDelay(7), const Duration(seconds: 10));
      expect(reopenBackoffDelay(99), const Duration(seconds: 10));
    });

    test('negative counts fall back to the first step', () {
      expect(reopenBackoffDelay(-1), const Duration(seconds: 1));
      expect(reopenBackoffDelay(-100), const Duration(seconds: 1));
    });
  });
}
