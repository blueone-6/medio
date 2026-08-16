import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_client/widgets/player/player_menu_sheet.dart';

void main() {
  testWidgets('menu sheet uses subtitle-panel dimensions and row rhythm',
      (tester) async {
    var selected = false;

    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: PlayerMenuSheet(
              title: '更多',
              rows: [
                const PlayerMenuRow(
                  label: '倍速',
                  value: '1.0x',
                  children: [PlayerMenuRow(label: '1.0x', selected: true)],
                ),
                const PlayerMenuRow(sectionTitle: '外挂'),
                PlayerMenuRow(
                  label: '简体中文',
                  value: 'Simplified Chinese',
                  onTap: () => selected = true,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final panelSize = tester.getSize(find.byType(PlayerMenuSheet));
    expect(panelSize.width, 400);
    expect(panelSize.height, 696);

    final rows = find.byType(InkWell);
    expect(tester.getSize(rows.at(1)).height, 48);
    expect(tester.getSize(rows.last).height, 48);

    await tester.tap(find.text('简体中文'));
    await tester.pumpAndSettle();
    expect(selected, isTrue);
  });

  testWidgets('row with children pushes a nested page with back arrow',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: PlayerMenuSheet(
              title: '更多',
              rows: [
                PlayerMenuRow(
                  label: '倍速',
                  value: '1.0x',
                  children: [
                    PlayerMenuRow(label: '0.5x'),
                    PlayerMenuRow(label: '1.0x', selected: true),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('倍速'), findsOneWidget);

    await tester.tap(find.text('倍速'));
    await tester.pumpAndSettle();

    expect(find.text('0.5x'), findsOneWidget);
    expect(find.text('1.0x'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    expect(find.text('倍速'), findsOneWidget);
  });
}
