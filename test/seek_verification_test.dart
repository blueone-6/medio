import 'package:flutter_test/flutter_test.dart';
import 'package:media_client/core/player/seek_verification.dart';

void main() {
  group('userSeekLanded', () {
    test('landed seek that kept playing stays inside the window', () {
      // Production regression: seek→43 s, 5 s later position 47 s was
      // misjudged as "did not land" and triggered a full re-open.
      expect(
        userSeekLanded(
          pos: const Duration(seconds: 47),
          target: const Duration(seconds: 43),
          elapsedSinceSeek: const Duration(seconds: 5),
        ),
        isTrue,
      );
    });

    test('landed seek at 2x playback stays inside the window', () {
      expect(
        userSeekLanded(
          pos: const Duration(seconds: 53),
          target: const Duration(seconds: 43),
          elapsedSinceSeek: const Duration(seconds: 5),
        ),
        isTrue,
      );
    });

    test('paused right after landing still counts as landed', () {
      expect(
        userSeekLanded(
          pos: const Duration(seconds: 43),
          target: const Duration(seconds: 43),
          elapsedSinceSeek: const Duration(seconds: 5),
        ),
        isTrue,
      );
    });

    test('keyframe landing slightly before the target counts as landed', () {
      expect(
        userSeekLanded(
          pos: const Duration(seconds: 41, milliseconds: 500),
          target: const Duration(seconds: 43),
          elapsedSinceSeek: const Duration(seconds: 1),
        ),
        isTrue,
      );
    });

    test('rejected backward seek (stays near old position) is detected', () {
      // User at 19:36 seeked back to 43 s; the seek was rejected and the
      // position kept advancing near the old spot — far outside the window.
      expect(
        userSeekLanded(
          pos: const Duration(minutes: 19, seconds: 41),
          target: const Duration(seconds: 43),
          elapsedSinceSeek: const Duration(seconds: 5),
        ),
        isFalse,
      );
    });

    test('rejected forward seek (position far below target) is detected', () {
      expect(
        userSeekLanded(
          pos: const Duration(seconds: 105),
          target: const Duration(seconds: 500),
          elapsedSinceSeek: const Duration(seconds: 5),
        ),
        isFalse,
      );
    });

    test('small misses within tolerance are tolerated', () {
      // A ~1.5 s miss (e.g. keyframe landing below the target) is not worth
      // a disruptive re-open.
      expect(
        userSeekLanded(
          pos: const Duration(seconds: 101, milliseconds: 500),
          target: const Duration(seconds: 103),
          elapsedSinceSeek: const Duration(seconds: 1),
        ),
        isTrue,
      );
      // 3 s below the target is outside the ±2 s tolerance: reported as not
      // landed (only relevant for slider seeks, which are rarely this small).
      expect(
        userSeekLanded(
          pos: const Duration(seconds: 100),
          target: const Duration(seconds: 103),
          elapsedSinceSeek: const Duration(seconds: 1),
        ),
        isFalse,
      );
    });
  });
}
