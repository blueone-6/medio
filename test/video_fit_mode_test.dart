import 'package:flutter_test/flutter_test.dart';

import 'package:media_client/core/player/exo/video_fit_mode.dart';

void main() {
  group('VideoFitMode native mapping', () {
    test('maps to the distinct media3 resize modes', () {
      // Verified against media3-ui 1.4.1:
      // FIT = 0, FIXED_WIDTH = 1, FIXED_HEIGHT = 2, FILL = 3, ZOOM = 4.
      // FIXED_WIDTH/FIXED_HEIGHT are intentionally not offered — on a
      // full-screen surface they render exactly like ZOOM/FIT.
      expect(VideoFitMode.fit.nativeValue, 0);
      expect(VideoFitMode.fill.nativeValue, 3);
      expect(VideoFitMode.zoom.nativeValue, 4);
      expect(
        VideoFitMode.values.map((m) => m.nativeValue).toSet(),
        {0, 3, 4},
      );
    });

    test('every mode is labelled and described', () {
      for (final m in VideoFitMode.values) {
        expect(m.label, isNotEmpty);
        expect(m.shortLabel, isNotEmpty);
        expect(m.description, isNotEmpty);
      }
    });

    test('cycles through every mode and wraps around', () {
      expect(VideoFitMode.fit.next, VideoFitMode.zoom);
      expect(VideoFitMode.zoom.next, VideoFitMode.fill);
      expect(VideoFitMode.fill.next, VideoFitMode.fit);
      var m = VideoFitMode.fit;
      final seen = <VideoFitMode>{};
      for (var i = 0; i < VideoFitMode.values.length; i++) {
        seen.add(m);
        m = m.next;
      }
      expect(seen.length, VideoFitMode.values.length);
      expect(m, VideoFitMode.fit);
    });

    test('fromName round-trips and defaults to zoom', () {
      for (final m in VideoFitMode.values) {
        expect(VideoFitMode.fromName(m.name), m);
      }
      expect(VideoFitMode.fromName(null), VideoFitMode.zoom);
      expect(VideoFitMode.fromName('bogus'), VideoFitMode.zoom);
      // Removed names from earlier builds fall back to the default.
      expect(VideoFitMode.fromName('crop'), VideoFitMode.zoom);
      expect(VideoFitMode.fromName('stretch'), VideoFitMode.zoom);
      expect(VideoFitMode.fromName('fixedWidth'), VideoFitMode.zoom);
      expect(VideoFitMode.fromName('fixedHeight'), VideoFitMode.zoom);
    });
  });

  group('effectiveVideoFitMode', () {
    test('landscape honours the chosen mode', () {
      for (final m in VideoFitMode.values) {
        expect(effectiveVideoFitMode(m, landscape: true), m);
      }
    });

    test('portrait always renders fit (any crop would destroy the picture)',
        () {
      for (final m in VideoFitMode.values) {
        expect(effectiveVideoFitMode(m, landscape: false), VideoFitMode.fit);
      }
    });
  });
}
