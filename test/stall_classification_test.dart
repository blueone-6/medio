import 'package:flutter_test/flutter_test.dart';
import 'package:media_client/core/player/stall_classification.dart';

void main() {
  StalledPlaybackKind classify({
    Duration position = const Duration(minutes: 5),
    Duration basePosition = const Duration(minutes: 5),
    bool playing = true,
    bool buffering = false,
    bool userPaused = false,
    Duration advanceThreshold = const Duration(milliseconds: 100),
  }) {
    return classifyStalledPlayback(
      position: position,
      basePosition: basePosition,
      playing: playing,
      buffering: buffering,
      userPaused: userPaused,
      advanceThreshold: advanceThreshold,
    );
  }

  group('advancing', () {
    test('position advanced past the threshold is healthy', () {
      expect(
        classify(
          basePosition: const Duration(seconds: 10),
          position: const Duration(seconds: 10, milliseconds: 500),
        ),
        StalledPlaybackKind.advancing,
      );
    });

    test('exactly at the threshold counts as advancing', () {
      expect(
        classify(
          basePosition: const Duration(seconds: 10),
          position: const Duration(seconds: 10, milliseconds: 100),
        ),
        StalledPlaybackKind.advancing,
      );
    });

    test('advancing wins even if mpv reports buffering', () {
      expect(
        classify(
          basePosition: const Duration(seconds: 10),
          position: const Duration(seconds: 12),
          buffering: true,
        ),
        StalledPlaybackKind.advancing,
      );
    });
  });

  group('cdnStall', () {
    test('empty cache while paused-like is an unambiguous stall', () {
      expect(
        classify(playing: false, buffering: true, userPaused: false),
        StalledPlaybackKind.cdnStall,
      );
    });

    test('frozen position while still "playing" is a stall', () {
      expect(
        classify(playing: true, buffering: false, userPaused: false),
        StalledPlaybackKind.cdnStall,
      );
    });

    test(
      'silent stall that mpv reports as paused (not playing, not buffering) '
      'is recovered instead of being excused as a user pause',
      () {
        expect(
          classify(playing: false, buffering: false, userPaused: false),
          StalledPlaybackKind.cdnStall,
        );
      },
    );

    test('fresh-playback freeze near zero is a stall', () {
      expect(
        classify(
          basePosition: Duration.zero,
          position: Duration.zero,
          playing: false,
          buffering: false,
          userPaused: false,
        ),
        StalledPlaybackKind.cdnStall,
      );
    });
  });

  group('userPaused', () {
    test('deliberate pause holds the position without recovery', () {
      expect(
        classify(playing: false, buffering: false, userPaused: true),
        StalledPlaybackKind.userPaused,
      );
    });

    test('deliberate pause overrides an empty cache', () {
      expect(
        classify(playing: false, buffering: true, userPaused: true),
        StalledPlaybackKind.userPaused,
      );
    });

    test('deliberate pause overrides a frozen "playing" flag', () {
      expect(
        classify(playing: true, buffering: false, userPaused: true),
        StalledPlaybackKind.userPaused,
      );
    });
  });
}
