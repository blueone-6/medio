import 'package:flutter_test/flutter_test.dart';
import 'package:media_client/core/player/seek_step.dart';

void main() {
  group('keyboardSeekStepForHold', () {
    test('ramp matches the desktop keyboard acceleration curve', () {
      expect(keyboardSeekStepForHold(const Duration(milliseconds: 100)), 1);
      expect(keyboardSeekStepForHold(const Duration(milliseconds: 499)), 1);
      expect(keyboardSeekStepForHold(const Duration(milliseconds: 500)), 5);
      expect(keyboardSeekStepForHold(const Duration(milliseconds: 999)), 5);
      expect(keyboardSeekStepForHold(const Duration(seconds: 1)), 15);
      expect(keyboardSeekStepForHold(const Duration(milliseconds: 1999)), 15);
      expect(keyboardSeekStepForHold(const Duration(seconds: 2)), 30);
      expect(keyboardSeekStepForHold(const Duration(milliseconds: 3999)), 30);
      expect(keyboardSeekStepForHold(const Duration(seconds: 4)), 60);
      expect(keyboardSeekStepForHold(const Duration(milliseconds: 6999)), 60);
      expect(keyboardSeekStepForHold(const Duration(seconds: 7)), 150);
      expect(keyboardSeekStepForHold(const Duration(milliseconds: 11999)), 150);
      expect(keyboardSeekStepForHold(const Duration(seconds: 12)), 300);
      expect(keyboardSeekStepForHold(const Duration(seconds: 30)), 300);
    });

    test('curve is monotonically non-decreasing', () {
      var prev = 0;
      for (var ms = 0; ms <= 20000; ms += 250) {
        final step = keyboardSeekStepForHold(Duration(milliseconds: ms));
        expect(step, greaterThanOrEqualTo(prev),
            reason: 'step dropped at ${ms}ms');
        prev = step;
      }
    });
  });

  group('gestureSeekStepForHold', () {
    test('ramp matches the mobile long-press curve (capped at 60)', () {
      expect(gestureSeekStepForHold(const Duration(milliseconds: 100)), 2);
      expect(gestureSeekStepForHold(const Duration(milliseconds: 500)), 5);
      expect(gestureSeekStepForHold(const Duration(seconds: 1)), 10);
      expect(gestureSeekStepForHold(const Duration(seconds: 2)), 20);
      expect(gestureSeekStepForHold(const Duration(seconds: 4)), 40);
      expect(gestureSeekStepForHold(const Duration(seconds: 7)), 60);
      expect(gestureSeekStepForHold(const Duration(seconds: 20)), 60);
    });

    test('gesture curve never exceeds the keyboard cap', () {
      for (var ms = 0; ms <= 30000; ms += 500) {
        expect(
          gestureSeekStepForHold(Duration(milliseconds: ms)),
          lessThanOrEqualTo(60),
        );
      }
    });
  });
}
