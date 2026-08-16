import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_client/widgets/player/player_menu_sheet.dart';
import 'package:media_client/widgets/player/player_subtitle_style.dart';

void main() {
  testWidgets('short portrait menu is translucent', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: PlayerMenuSheet(
            title: '更多',
            rows: [
              PlayerMenuRow(label: '倍速'),
              PlayerMenuRow(label: '音轨'),
              PlayerMenuRow(label: '字幕'),
              PlayerMenuRow(label: '字幕偏移'),
            ],
          ),
        ),
      ),
    );

    final panel = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(PlayerMenuSheet),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(panel.color, isNotNull);
    expect(panel.color!.a, lessThan(230));
  });

  test('subtitle view remount key changes with bottom padding', () {
    expect(
      PlayerSubtitleStyle.viewKey(656.25),
      isNot(PlayerSubtitleStyle.viewKey(24)),
    );
    expect(PlayerSubtitleStyle.viewKey(24), PlayerSubtitleStyle.viewKey(24));
  });
}

