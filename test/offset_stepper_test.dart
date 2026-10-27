import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_client/core/player/subtitle_offset.dart';
import 'package:media_client/widgets/player/offset_stepper.dart';
import 'package:media_client/widgets/player/player_menu_sheet.dart';

Widget _host(Widget child, {double width = 300}) => MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: SizedBox(width: width, height: PlayerMenuSheet.rowHeight, child: child),
        ),
      ),
    );

void main() {
  test('subtitle offset clamps to the range the stepper offers', () {
    expect(subtitleOffsetLimitMs, 30000);
    expect(clampSubtitleOffsetMs(31000), subtitleOffsetLimitMs);
    expect(clampSubtitleOffsetMs(-31000), -subtitleOffsetLimitMs);
    expect(clampSubtitleOffsetMs(120), 120);
  });

  testWidgets('stepper fits the narrow menu sheet without overflowing',
      (tester) async {
    await tester.pumpWidget(_host(
      OffsetStepper(valueMs: 1200, onAdjust: (_) {}, onReset: () {}),
    ));

    for (final label in ['-0.5', '-0.1', '+0.1', '+0.5']) {
      final text = tester.widget<Text>(find.text(label));
      expect(text.style?.fontSize, 12);
    }
    expect(find.text('+1.2s'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('each side offers a fine and a coarse step', (tester) async {
    final deltas = <int>[];
    await tester.pumpWidget(_host(
      OffsetStepper(valueMs: 0, onAdjust: deltas.add, onReset: () {}),
    ));

    await tester.tap(find.text('-0.1'));
    await tester.tap(find.text('+0.1'));
    await tester.tap(find.text('-0.5'));
    await tester.tap(find.text('+0.5'));
    await tester.pump();

    expect(deltas, [-100, 100, -500, 500]);
  });

  testWidgets('steps past the range are disabled', (tester) async {
    final deltas = <int>[];
    await tester.pumpWidget(_host(
      // Native subtitle cues can only be delayed: minMs 0 blocks "提前".
      OffsetStepper(
        valueMs: 0,
        minMs: 0,
        onAdjust: deltas.add,
        onReset: () {},
      ),
    ));

    await tester.tap(find.text('-0.1'));
    await tester.tap(find.text('-0.5'));
    await tester.pump();
    expect(deltas, isEmpty);

    await tester.tap(find.text('+0.1'));
    await tester.pump();
    expect(deltas, [100]);
  });

  testWidgets('tapping the centred value resets only when offset is set',
      (tester) async {
    var resets = 0;
    await tester.pumpWidget(_host(
      OffsetStepper(valueMs: 0, onAdjust: (_) {}, onReset: () => resets++),
    ));
    expect(find.text('已对齐'), findsOneWidget);
    await tester.tap(find.text('0.0s'));
    await tester.pump();
    expect(resets, 0);

    await tester.pumpWidget(_host(
      OffsetStepper(valueMs: -300, onAdjust: (_) {}, onReset: () => resets++),
    ));
    expect(find.text('-0.3s'), findsOneWidget);
    expect(find.text('点此归零'), findsOneWidget);
    await tester.tap(find.text('-0.3s'));
    await tester.pump();
    expect(resets, 1);
  });

  testWidgets('menu sheet renders the stepper as a custom row', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: PlayerMenuSheet(
            title: '字幕',
            rows: [
              const PlayerMenuRow(sectionTitle: '字幕同步'),
              PlayerMenuRow(
                custom: OffsetStepper(
                  valueMs: 500,
                  onAdjust: (_) {},
                  onReset: () {},
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('+0.5s'), findsOneWidget);
    expect(find.text('-0.5'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
