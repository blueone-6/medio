import 'package:flutter_test/flutter_test.dart';

import 'package:media_client/core/player/player_subtitle_position.dart';

void main() {
  group('subtitleLetterboxBottom', () {
    test('portrait viewport with 16:9 video returns the bottom bar height',
        () {
      // 1080x1920 portrait, 16:9 video → video 1080x607.5, bar = 656.25.
      final bar = subtitleLetterboxBottom(
        viewportWidth: 1080,
        viewportHeight: 1920,
        aspect: 16 / 9,
      );
      expect(bar, closeTo(656.25, 0.001));
    });

    test('landscape viewport with 16:9 video has no bottom bar', () {
      final bar = subtitleLetterboxBottom(
        viewportWidth: 1920,
        viewportHeight: 1080,
        aspect: 16 / 9,
      );
      expect(bar, closeTo(0, 0.001));
    });

    test('landscape viewport with 21:9 video letterboxes above/below', () {
      // 1920x1080 landscape, 21:9 video → video 1920x822.86, bar = 128.57.
      final bar = subtitleLetterboxBottom(
        viewportWidth: 1920,
        viewportHeight: 1080,
        aspect: 21 / 9,
      );
      expect(bar, closeTo(128.571, 0.001));
    });

    test('portrait video in landscape viewport letterboxes the sides only', () {
      final bar = subtitleLetterboxBottom(
        viewportWidth: 1920,
        viewportHeight: 1080,
        aspect: 9 / 16,
      );
      expect(bar, closeTo(0, 0.001));
    });

    test('falls back to dw/dh when aspect is null', () {
      final bar = subtitleLetterboxBottom(
        viewportWidth: 1080,
        viewportHeight: 1920,
        dw: 1920,
        dh: 1080,
      );
      expect(bar, closeTo(656.25, 0.001));
    });

    test('falls back to w/h when aspect and dw/dh are null', () {
      final bar = subtitleLetterboxBottom(
        viewportWidth: 1080,
        viewportHeight: 1920,
        w: 3840,
        h: 2160,
      );
      expect(bar, closeTo(656.25, 0.001));
    });

    test('returns 0 when no aspect information is available', () {
      final bar = subtitleLetterboxBottom(
        viewportWidth: 1080,
        viewportHeight: 1920,
      );
      expect(bar, closeTo(0, 0.001));
    });

    test('returns 0 for degenerate viewport dimensions', () {
      expect(
        subtitleLetterboxBottom(
          viewportWidth: 0,
          viewportHeight: 1920,
          aspect: 16 / 9,
        ),
        0,
      );
    });
  });
}
