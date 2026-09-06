import 'package:flutter_test/flutter_test.dart';
import 'package:media_client/core/player/bogus_position_guard.dart';

void main() {
  const dur = Duration(minutes: 45);
  const resume = Duration(minutes: 30);

  group('classifyFreshPlaybackPosition', () {
    group('user-seek window (15s / ±5s)', () {
      test('recent user seek at the target is legitimate', () {
        expect(
          classifyFreshPlaybackPosition(
            pos: const Duration(minutes: 10),
            duration: dur,
            elapsed: const Duration(seconds: 3),
            resumeTarget: null,
            userSeekTarget: const Duration(minutes: 10),
            userSeekAge: const Duration(seconds: 4),
          ),
          FreshPositionVerdict.legitimate,
        );
      });

      test('stale user seek (>15s old) no longer confirms and is bogus', () {
        // elapsed=20s → a 10-minute position is impossible for real playback.
        expect(
          classifyFreshPlaybackPosition(
            pos: const Duration(minutes: 10),
            duration: dur,
            elapsed: const Duration(seconds: 20),
            resumeTarget: null,
            userSeekTarget: const Duration(minutes: 10),
            userSeekAge: const Duration(seconds: 16),
          ),
          FreshPositionVerdict.bogus,
        );
      });

      test('position far from the user seek target stays bogus', () {
        expect(
          classifyFreshPlaybackPosition(
            pos: const Duration(minutes: 10),
            duration: dur,
            elapsed: const Duration(seconds: 20),
            resumeTarget: null,
            userSeekTarget: const Duration(minutes: 20),
            userSeekAge: const Duration(seconds: 4),
          ),
          FreshPositionVerdict.bogus,
        );
      });
    });

    group('resume target (±60s)', () {
      test('position near resume target is legitimate', () {
        expect(
          classifyFreshPlaybackPosition(
            pos: resume,
            duration: dur,
            elapsed: const Duration(seconds: 2),
            resumeTarget: resume,
          ),
          FreshPositionVerdict.legitimate,
        );
      });

      test('position ≤500ms near resume target is not confirmable', () {
        expect(
          classifyFreshPlaybackPosition(
            pos: const Duration(milliseconds: 300),
            duration: dur,
            elapsed: const Duration(seconds: 2),
            resumeTarget: const Duration(milliseconds: 400),
          ),
          FreshPositionVerdict.plausible,
        );
      });

      test('near-end position within resume window is legitimate', () {
        // pos = 95% of duration, resume target 25s away: the early resume
        // branch confirms it (mpv legitimately seeks near the resume target).
        expect(
          classifyFreshPlaybackPosition(
            pos: const Duration(minutes: 42, seconds: 45),
            duration: dur,
            elapsed: const Duration(seconds: 5),
            resumeTarget: const Duration(minutes: 42, seconds: 20),
          ),
          FreshPositionVerdict.legitimate,
        );
      });
    });

    group('wall-clock plausibility', () {
      test('position consistent with 2x playback is legitimate', () {
        expect(
          classifyFreshPlaybackPosition(
            pos: const Duration(seconds: 40),
            duration: dur,
            elapsed: const Duration(seconds: 20),
            resumeTarget: null,
          ),
          FreshPositionVerdict.legitimate,
        );
      });

      test('startup transient (<2s) is not confirmable', () {
        expect(
          classifyFreshPlaybackPosition(
            pos: const Duration(seconds: 1),
            duration: dur,
            elapsed: const Duration(seconds: 1),
            resumeTarget: null,
          ),
          FreshPositionVerdict.plausible,
        );
      });

      test('position beyond 2x+3s wall-clock is bogus', () {
        expect(
          classifyFreshPlaybackPosition(
            pos: const Duration(minutes: 10),
            duration: dur,
            elapsed: const Duration(seconds: 5),
            resumeTarget: null,
          ),
          FreshPositionVerdict.bogus,
        );
      });
    });

    group('duration known (>30s)', () {
      test('position ≥90% of duration is bogus on fresh playback', () {
        expect(
          classifyFreshPlaybackPosition(
            pos: const Duration(minutes: 42),
            duration: dur,
            elapsed: const Duration(seconds: 8),
            resumeTarget: null,
          ),
          FreshPositionVerdict.bogus,
        );
      });

      test('mid-file SeekHead offset (≥85% dur but <90%) beyond wall-clock is bogus',
          () {
        expect(
          classifyFreshPlaybackPosition(
            pos: const Duration(minutes: 35), // 77.7% of dur
            duration: dur,
            elapsed: const Duration(seconds: 6),
            resumeTarget: null,
          ),
          FreshPositionVerdict.bogus,
        );
      });

      test('mid-file position within wall-clock is plausible', () {
        expect(
          classifyFreshPlaybackPosition(
            pos: const Duration(minutes: 35),
            duration: dur,
            elapsed: const Duration(minutes: 40),
            resumeTarget: null,
          ),
          FreshPositionVerdict.legitimate, // ≤2x wall-clock → legitimate
        );
      });
    });

    group('duration unknown', () {
      test('resume-target tolerance applies (early branch)', () {
        expect(
          classifyFreshPlaybackPosition(
            pos: const Duration(minutes: 5),
            duration: Duration.zero,
            elapsed: const Duration(seconds: 2),
            resumeTarget: const Duration(minutes: 5, seconds: 30),
          ),
          FreshPositionVerdict.legitimate,
        );
      });

      test('impossible position with unknown duration is bogus', () {
        expect(
          classifyFreshPlaybackPosition(
            pos: const Duration(minutes: 25),
            duration: Duration.zero,
            elapsed: const Duration(seconds: 5),
            resumeTarget: null,
          ),
          FreshPositionVerdict.bogus,
        );
      });
    });

    group('short content (duration ≤30s)', () {
      test('wall-clock rule applies without the 90% branch', () {
        expect(
          classifyFreshPlaybackPosition(
            pos: const Duration(seconds: 28), // 93% of 30s clip
            duration: const Duration(seconds: 30),
            elapsed: const Duration(seconds: 15),
            resumeTarget: null,
          ),
          FreshPositionVerdict.legitimate,
        );
      });
    });
  });

  group('implausibleEndJumpTarget', () {
    const confirmed = Duration(minutes: 20);

    test('returns null without a confirmed position', () {
      expect(
        implausibleEndJumpTarget(
          pos: dur,
          duration: dur,
          confirmedPos: null,
          confirmedAge: null,
        ),
        isNull,
      );
    });

    test('recent user seek exactly at the end is plausible', () {
      expect(
        implausibleEndJumpTarget(
          pos: dur,
          duration: dur,
          confirmedPos: confirmed,
          confirmedAge: const Duration(minutes: 1),
          userSeekTarget: dur, // seeked to the very end
          userSeekAge: const Duration(seconds: 10),
        ),
        isNull,
      );
    });

    test('user seek landing slightly past its target still recovers', () {
      // The ±5s user-seek tolerance is tight: a seek to 44:00 reporting at
      // 45:00 falls outside it and is treated as an implausible EOF jump.
      expect(
        implausibleEndJumpTarget(
          pos: dur,
          duration: dur,
          confirmedPos: confirmed,
          confirmedAge: const Duration(minutes: 1),
          userSeekTarget: const Duration(minutes: 44),
          userSeekAge: const Duration(seconds: 10),
        ),
        confirmed,
      );
    });

    test('confirmed near the end does not trigger recovery', () {
      expect(
        implausibleEndJumpTarget(
          pos: dur,
          duration: dur,
          confirmedPos: const Duration(minutes: 44, seconds: 55),
          confirmedAge: const Duration(seconds: 5),
        ),
        isNull,
      );
    });

    test('small content gap (<10s) does not trigger recovery', () {
      expect(
        implausibleEndJumpTarget(
          pos: const Duration(minutes: 20, seconds: 8),
          duration: dur,
          confirmedPos: confirmed,
          confirmedAge: const Duration(seconds: 8),
        ),
        isNull,
      );
    });

    test('real-time playback covering the distance does not recover', () {
      // Jumped 20→45min, but 26 wall-clock minutes elapsed: plausible 1x.
      expect(
        implausibleEndJumpTarget(
          pos: dur,
          duration: dur,
          confirmedPos: confirmed,
          confirmedAge: const Duration(minutes: 26),
        ),
        isNull,
      );
    });

    test('spurious EOF jump returns the confirmed position', () {
      expect(
        implausibleEndJumpTarget(
          pos: dur,
          duration: dur,
          confirmedPos: confirmed,
          confirmedAge: const Duration(seconds: 30),
        ),
        confirmed,
      );
    });

    test('resume-open spurious EOF (confirmed just after open)', () {
      // Confirmed 2s after open at the resume point, EOF 5s later.
      expect(
        implausibleEndJumpTarget(
          pos: dur,
          duration: dur,
          confirmedPos: resume,
          confirmedAge: const Duration(seconds: 5),
        ),
        resume,
      );
    });
  });
}
