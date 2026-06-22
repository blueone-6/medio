import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:media_client/widgets/player/player_gesture.dart';
// ignore: implementation_imports
import 'package:media_client/widgets/player/player_gesture_mobile.dart'
    as mobile;

Widget _androidGestureHarness({
  required Widget child,
}) {
  return MediaQuery(
    data: const MediaQueryData(size: Size(400, 800)),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(width: 400, height: 800, child: child),
    ),
  );
}

void main() {
  group('PlayerGestureLayer - pass-through on non-Android', () {
    testWidgets('renders child directly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: PlayerGestureLayer(
            child: Text('video'),
          ),
        ),
      );

      expect(find.text('video'), findsOneWidget);
    });
  });

  group('PlayerGestureLayer - Android gestures', () {
    testWidgets('single tap triggers onTap', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      int tapCount = 0;
      await tester.pumpWidget(
        _androidGestureHarness(
          child: mobile.PlayerGestureLayer(
            onTap: () => tapCount++,
            child: const SizedBox(width: 400, height: 800),
          ),
        ),
      );

      await tester.tapAt(const Offset(200, 400));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(seconds: 1));

      expect(tapCount, 1);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('double tap left seeks -10s', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      int tapCount = 0;
      int? seekSeconds;
      await tester.pumpWidget(
        _androidGestureHarness(
          child: mobile.PlayerGestureLayer(
            onTap: () => tapCount++,
            onSeekRelative: (s) => seekSeconds = s,
            child: const SizedBox(width: 400, height: 800),
          ),
        ),
      );

      await tester.tapAt(const Offset(100, 400));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(const Offset(100, 400));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(seekSeconds, -10);
      expect(tapCount, 0);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('double tap right seeks +10s', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      int? seekSeconds;
      await tester.pumpWidget(
        _androidGestureHarness(
          child: mobile.PlayerGestureLayer(
            onSeekRelative: (s) => seekSeconds = s,
            child: const ColoredBox(color: Color(0xFF000000)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final layerBox = tester.renderObject<RenderBox>(
        find.byType(mobile.PlayerGestureLayer),
      );
      final rightX = layerBox.size.width * 0.75;
      final centerY = layerBox.size.height / 2;
      final rightTap = layerBox.localToGlobal(Offset(rightX, centerY));

      await tester.tapAt(rightTap);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(rightTap);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(seekSeconds, 10);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('horizontal drag previews then commits seek', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final previewDeltas = <int>[];
      int? committed;
      await tester.pumpWidget(
        _androidGestureHarness(
          child: mobile.PlayerGestureLayer(
            onSeekPreview: previewDeltas.add,
            onSeekRelative: (s) => committed = s,
            player: _FakePlayer(
              position: const Duration(minutes: 5),
              duration: const Duration(minutes: 60),
            ),
            child: const SizedBox(width: 400, height: 800),
          ),
        ),
      );

      final detector = find.byType(GestureDetector).last;
      await tester.drag(detector, const Offset(150, 0));
      await tester.pump(const Duration(seconds: 1));

      expect(previewDeltas, isNotEmpty);
      expect(previewDeltas.last, 0);
      expect(committed, isNotNull);
      expect(committed!, isNot(0));
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('horizontal drag seek scales with video duration', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      int? shortCommit;
      int? longCommit;

      Future<void> dragSeek(Duration duration, void Function(int) onCommit) async {
        await tester.pumpWidget(
          _androidGestureHarness(
            child: mobile.PlayerGestureLayer(
              onSeekRelative: onCommit,
              player: _FakePlayer(
                position: Duration.zero,
                duration: duration,
              ),
              child: const SizedBox(width: 400, height: 800),
            ),
          ),
        );
        final detector = find.byType(GestureDetector).last;
        await tester.drag(detector, const Offset(150, 0));
        await tester.pump(const Duration(seconds: 1));
      }

      await dragSeek(const Duration(hours: 1), (s) => shortCommit = s);
      await dragSeek(const Duration(hours: 2), (s) => longCommit = s);

      expect(shortCommit, isNotNull);
      expect(longCommit, isNotNull);
      expect(shortCommit!, isNot(0));
      // Same swipe distance → seek offset doubles when duration doubles.
      expect(longCommit!, inInclusiveRange(shortCommit! * 2 - 2, shortCommit! * 2 + 2));
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('vertical drag right half full height raises volume ~100',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      var totalDelta = 0.0;
      final player = _MutableVolumePlayer(initialVolume: 0);
      await tester.pumpWidget(
        _androidGestureHarness(
          child: mobile.PlayerGestureLayer(
            onVolumeDelta: (d) {
              player.adjustVolume(d);
              totalDelta += d;
            },
            player: player,
            child: const SizedBox(width: 400, height: 800),
          ),
        ),
      );

      final detector = find.byType(GestureDetector).last;
      await tester.drag(detector, const Offset(2, -700));
      await tester.pump(const Duration(seconds: 1));

      // ~700/800 of full 0–100 range
      expect(totalDelta, greaterThanOrEqualTo(80));
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('vertical drag right half increases volume', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      double? volumeDelta;
      await tester.pumpWidget(
        _androidGestureHarness(
          child: mobile.PlayerGestureLayer(
            onVolumeDelta: (d) => volumeDelta = d,
            player: _FakePlayer(volume: 50),
            child: const SizedBox(width: 400, height: 800),
          ),
        ),
      );

      final detector = find.byType(GestureDetector).last;
      await tester.drag(detector, const Offset(2, -100));
      await tester.pump(const Duration(seconds: 1));

      expect(volumeDelta, isNotNull);
      expect(volumeDelta! > 0, isTrue);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('vertical drag right half decreases volume', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      double? volumeDelta;
      await tester.pumpWidget(
        _androidGestureHarness(
          child: mobile.PlayerGestureLayer(
            onVolumeDelta: (d) => volumeDelta = d,
            player: _FakePlayer(volume: 50),
            child: const SizedBox(width: 400, height: 800),
          ),
        ),
      );

      final detector = find.byType(GestureDetector).last;
      await tester.drag(detector, const Offset(2, 100));
      await tester.pump(const Duration(seconds: 1));

      expect(volumeDelta, isNotNull);
      expect(volumeDelta! < 0, isTrue);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('onUserInteraction fires on horizontal drag', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      int count = 0;
      await tester.pumpWidget(
        _androidGestureHarness(
          child: mobile.PlayerGestureLayer(
            onSeekPreview: (_) {},
            onUserInteraction: () => count++,
            child: const SizedBox(width: 400, height: 800),
          ),
        ),
      );

      final detector = find.byType(GestureDetector).last;
      await tester.drag(detector, const Offset(150, 0));
      await tester.pump(const Duration(seconds: 1));

      expect(count, greaterThanOrEqualTo(1));
      debugDefaultTargetPlatformOverride = null;
    });
  });
}

class _FakePlayer {
  _FakePlayer({
    this.volume = 50,
    this.position = Duration.zero,
    this.duration = Duration.zero,
  });
  final double volume;
  final Duration position;
  final Duration duration;
  _FakeState get state => _FakeState(volume, position, duration);
}

/// Tracks volume updates so gesture displacement tests see current level.
class _MutableVolumePlayer {
  _MutableVolumePlayer({double initialVolume = 50}) : _volume = initialVolume;

  double _volume;

  _FakeState get state => _FakeState(_volume, Duration.zero, Duration.zero);

  void adjustVolume(double delta) {
    _volume = (_volume + delta).clamp(0.0, 100.0);
  }
}

class _FakeState {
  _FakeState(this.volume, this.position, this.duration);
  final double volume;
  final Duration position;
  final Duration duration;
}
