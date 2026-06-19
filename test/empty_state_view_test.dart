import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_client/widgets/empty_state_view.dart';

void main() {
  testWidgets('EmptyStateView renders title and action', (tester) async {
    var tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EmptyStateView(
            icon: Icons.inbox_outlined,
            title: '暂无内容',
            subtitle: '试试刷新',
            actionLabel: '刷新',
            onAction: () => tapped = true,
          ),
        ),
      ),
    );

    expect(find.text('暂无内容'), findsOneWidget);
    expect(find.text('试试刷新'), findsOneWidget);
    expect(find.text('刷新'), findsOneWidget);

    await tester.tap(find.text('刷新'));
    await tester.pump();
    expect(tapped, isTrue);
  });

  testWidgets('EmptyStateView compact mode uses smaller icon', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EmptyStateView(
            compact: true,
            centered: false,
            title: '暂无推荐',
          ),
        ),
      ),
    );

    expect(find.text('暂无推荐'), findsOneWidget);
    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.size, 28);
  });
}
