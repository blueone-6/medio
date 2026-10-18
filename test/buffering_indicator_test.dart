import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_client/widgets/player/buffering_indicator.dart';

void main() {
  group('bufferingStageFor', () {
    test('stays hidden while the player is not waiting', () {
      expect(
        bufferingStageFor(waiting: false, waited: const Duration(minutes: 3)),
        BufferingStage.hidden,
      );
    });

    test('hides the routine sub-second rebuffer of a seek', () {
      expect(
        bufferingStageFor(waiting: true, waited: Duration.zero),
        BufferingStage.hidden,
      );
      expect(
        bufferingStageFor(waiting: true, waited: const Duration(milliseconds: 699)),
        BufferingStage.hidden,
      );
    });

    test('shows the spinner once a wait is noticeable', () {
      expect(
        bufferingStageFor(waiting: true, waited: BufferingFeedbackTiming.show),
        BufferingStage.buffering,
      );
      expect(
        bufferingStageFor(waiting: true, waited: const Duration(seconds: 7)),
        BufferingStage.buffering,
      );
    });

    test('escalates to the slow-network message', () {
      expect(
        bufferingStageFor(waiting: true, waited: BufferingFeedbackTiming.slow),
        BufferingStage.slow,
      );
      expect(
        bufferingStageFor(waiting: true, waited: const Duration(minutes: 2)),
        BufferingStage.slow,
      );
    });
  });

  group('BufferingIndicator', () {
    testWidgets('names the wait without claiming the network is at fault', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: BufferingIndicator(stage: BufferingStage.buffering)),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('正在缓冲…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.textContaining('已缓冲至'), findsNothing);
    });

    testWidgets('explains a long stall with the buffered range', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: BufferingIndicator(
            stage: BufferingStage.slow,
            bufferedPosition: Duration(minutes: 12, seconds: 3),
            duration: Duration(hours: 2, minutes: 35),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('网络缓慢，正在缓冲…'), findsOneWidget);
      expect(find.text('已缓冲至 00:12:03 / 02:35:00'), findsOneWidget);
    });
  });
}
