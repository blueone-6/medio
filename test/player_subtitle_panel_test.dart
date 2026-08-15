import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_client/widgets/player/player_subtitle_panel.dart';

void main() {
  testWidgets('Android subtitle panel uses episode picker dimensions and rows',
      (
    tester,
  ) async {
    var selected = false;

    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: PlayerSubtitlePanel(
              onClose: _noop,
              sections: [
                const PlayerSubtitleSection(
                  options: [
                    PlayerSubtitleOption(
                      label: '关闭字幕',
                      selected: true,
                      onSelected: _noop,
                    ),
                  ],
                ),
                PlayerSubtitleSection(
                  title: '外挂',
                  options: [
                    PlayerSubtitleOption(
                      label: '简体中文',
                      detail: 'Simplified Chinese',
                      onSelected: () => selected = true,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final panelSize = tester.getSize(find.byType(PlayerSubtitlePanel));
    expect(panelSize.width, 400);
    expect(panelSize.height, 696);

    final rows = find.byType(InkWell);
    expect(tester.getSize(rows.at(1)).height, 48);
    expect(tester.getSize(rows.last).height, 48);

    await tester.tap(find.text('简体中文'));
    await tester.pumpAndSettle();
    expect(selected, isTrue);
  });
}

void _noop() {}
