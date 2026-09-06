import 'package:flutter_test/flutter_test.dart';
import 'package:media_client/core/player/playback_resume.dart';

void main() {
  group('resolveResumePositionTicks', () {
    test('normalizes 0-1 fraction to percent', () {
      expect(normalizePlayedPercentage(0.65), 65.0);
      expect(normalizePlayedPercentage(72), 72.0);
    });

    test('uses played percentage when ticks are missing', () {
      const runtime = 24 * 60 * 60 * 10000000; // 24h in ticks
      expect(
        resolveResumePositionTicks(
          playedPercentage: 50,
          runTimeTicks: runtime,
        ),
        runtime ~/ 2,
      );
    });

    test('prefers the larger of emby and local ticks', () {
      expect(
        resolveResumePositionTicks(
          embyPlaybackPositionTicks: 100,
          localPlaybackPositionTicks: 500,
        ),
        500,
      );
    });
  });

  group('resumePlaybackPosition', () {
    test('returns null when no saved position', () {
      expect(resumePlaybackPosition(playbackPositionTicks: null), isNull);
      expect(resumePlaybackPosition(playbackPositionTicks: 0), isNull);
    });

    test('resumes from played percentage alone', () {
      const runtime = 60 * 60 * 10000000; // 1h
      expect(
        resumePlaybackPosition(
          playedPercentage: 50,
          runTimeTicks: runtime,
          played: false,
        ),
        const Duration(minutes: 30),
      );
    });

    test('still resumes when Played=true but position ticks exist', () {
      expect(
        resumePlaybackPosition(
          playbackPositionTicks: 6000000000,
          runTimeTicks: 120 * 60 * 10000000,
          played: true,
        ),
        const Duration(minutes: 10),
      );
    });

    test('returns null when near end of runtime', () {
      const runtime = 3600 * 10000000;
      const nearEnd = runtime - 20 * 10000000;
      expect(
        resumePlaybackPosition(
          playbackPositionTicks: nearEnd,
          runTimeTicks: runtime,
        ),
        isNull,
      );
    });

    // Regression: cold strm MediaSources resolve lazily and can omit
    // RunTimeTicks. Callers must fall back to item-metadata runtime so this
    // guard still applies; without any runtime the near-end filter cannot
    // fire (documented behavior, see player bootstrap runtime fallback).
    test('returns null for near-end position with playedPercentage hint', () {
      const runtime = 3600 * 10000000;
      const nearEnd = runtime - 20 * 10000000;
      expect(
        resumePlaybackPosition(
          playbackPositionTicks: nearEnd,
          runTimeTicks: runtime,
          playedPercentage: 99.4,
        ),
        isNull,
      );
    });

    test('returns null when pct >= 90 and no ticks are available', () {
      expect(
        resumePlaybackPosition(
          playbackPositionTicks: null,
          playedPercentage: 92,
          runTimeTicks: 3600 * 10000000,
        ),
        isNull,
      );
    });

    test('no runtime means near-end guard cannot apply (strm cold fetch)', () {
      const runtime = 3600 * 10000000;
      const nearEnd = runtime - 20 * 10000000;
      // Without runtime the position still resumes — screens are expected to
      // supply the item-metadata RunTimeTicks fallback for lazy strm sources.
      expect(
        resumePlaybackPosition(playbackPositionTicks: nearEnd),
        const Duration(seconds: 3580),
      );
    });

    test('returns seek target for resumable progress', () {
      const ticks = 45 * 60 * 10000000;
      expect(
        resumePlaybackPosition(
          playbackPositionTicks: ticks,
          runTimeTicks: 90 * 60 * 10000000,
          played: false,
        ),
        const Duration(minutes: 45),
      );
    });
  });

  group('isResumePositionSettled', () {
    test('accepts position slightly below mpv --start target', () {
      const resume = Duration(minutes: 14, seconds: 55);
      const reported = Duration(minutes: 14, seconds: 54, milliseconds: 500);
      expect(isResumePositionSettled(reported, resume), isTrue);
    });

    test('fresh playback requires movement past 50ms', () {
      expect(isResumePositionSettled(Duration.zero, Duration.zero), isFalse);
      expect(
        isResumePositionSettled(const Duration(milliseconds: 100), Duration.zero),
        isTrue,
      );
    });
  });

  group('isPlaybackNearEnd', () {
    test('rejects mid-playback positions', () {
      const dur = Duration(minutes: 21, seconds: 23);
      const pos = Duration(minutes: 14, seconds: 55);
      expect(isPlaybackNearEnd(pos, dur), isFalse);
    });

    test('accepts positions in the last 15 seconds', () {
      const dur = Duration(minutes: 10);
      const pos = Duration(minutes: 9, seconds: 50);
      expect(isPlaybackNearEnd(pos, dur), isTrue);
    });
  });
}
