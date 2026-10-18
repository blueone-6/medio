import 'package:flutter_test/flutter_test.dart';
import 'package:media_client/core/player/player_av_sync.dart';

void main() {
  group('clampAudioDelayMs', () {
    test('keeps in-range values', () {
      expect(clampAudioDelayMs(0), 0);
      expect(clampAudioDelayMs(400), 400);
      expect(clampAudioDelayMs(-400), -400);
    });

    test('clamps to the supported range', () {
      expect(clampAudioDelayMs(99999), audioDelayMaxMs);
      expect(clampAudioDelayMs(-99999), audioDelayMinMs);
    });
  });

  group('formatAudioDelayMs', () {
    test('signs and one decimal', () {
      expect(formatAudioDelayMs(0), '0.0s');
      expect(formatAudioDelayMs(500), '+0.5s');
      expect(formatAudioDelayMs(-100), '-0.1s');
      expect(formatAudioDelayMs(1500), '+1.5s');
    });
  });

  group('describeAudioDelay', () {
    test('zero reads as aligned', () {
      expect(describeAudioDelay(0), '声音与画面已对齐');
    });

    test('positive means the sound is delayed', () {
      expect(describeAudioDelay(500), '声音延后 0.5s');
    });

    test('negative means the sound is advanced', () {
      expect(describeAudioDelay(-300), '声音提前 0.3s');
    });
  });

  group('mpvAudioDelaySeconds', () {
    test('seconds with three decimals', () {
      expect(mpvAudioDelaySeconds(0), '0.000');
      expect(mpvAudioDelaySeconds(500), '0.500');
      expect(mpvAudioDelaySeconds(-120), '-0.120');
    });
  });

  group('avDelay memory', () {
    test('decode ignores malformed payloads', () {
      expect(decodeAvDelayMemory(null), isEmpty);
      expect(decodeAvDelayMemory(''), isEmpty);
      expect(decodeAvDelayMemory('not json'), isEmpty);
      expect(decodeAvDelayMemory('[1,2]'), isEmpty);
      expect(decodeAvDelayMemory('{"a": "x", "b": 500}'), {'b': 500});
    });

    test('decode drops zero entries and clamps', () {
      expect(decodeAvDelayMemory('{"a": 0, "b": 99999}'), {
        'b': audioDelayMaxMs,
      });
    });

    test('round-trips through encode', () {
      final memory = avDelayMemoryWith(<String, int>{}, 'item/1', 1000);
      expect(decodeAvDelayMemory(encodeAvDelayMemory(memory)), memory);
    });

    test('setting 0 removes the entry so untouched videos stay default', () {
      var memory = avDelayMemoryWith(<String, int>{}, 'item/1', 1000);
      memory = avDelayMemoryWith(memory, 'item/1', 0);
      expect(memory, isEmpty);
      expect(avDelayMemoryWith(memory, 'item/2', 500), {'item/2': 500});
    });

    test('clamps to the supported range', () {
      expect(
        avDelayMemoryWith(<String, int>{}, 'item/1', 99999),
        {'item/1': audioDelayMaxMs},
      );
    });

    test('prunes the oldest entries past the cap', () {
      var memory = <String, int>{};
      for (var i = 0; i < avDelayMemoryMaxEntries + 5; i++) {
        memory = avDelayMemoryWith(memory, 'item/$i', 100);
      }
      expect(memory.length, avDelayMemoryMaxEntries);
      expect(memory.containsKey('item/0'), isFalse);
      expect(memory.containsKey('item/4'), isFalse);
      expect(memory.containsKey('item/5'), isTrue);
      expect(memory.keys.last, 'item/${avDelayMemoryMaxEntries + 4}');
    });
  });
}
