import 'package:ai_tavern/widgets/collapsible_choice_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget testApp() => const MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: CollapsibleChoicePanel(
          title: '选择下一步行动（10 项）',
          child: SizedBox(height: 300, child: Text('剧情选项内容')),
        ),
      ),
    ),
  );

  testWidgets('dragging down collapses and dragging up expands the panel', (
    tester,
  ) async {
    await tester.pumpWidget(testApp());
    expect(find.text('剧情选项内容'), findsOneWidget);

    final dragArea = find.byKey(const ValueKey('choice-panel-drag-area'));
    await tester.drag(dragArea, const Offset(0, 80));
    await tester.pumpAndSettle();
    expect(find.text('剧情选项内容'), findsNothing);
    expect(find.text('上拉展开剧情选项'), findsOneWidget);

    await tester.drag(dragArea, const Offset(0, -80));
    await tester.pumpAndSettle();
    expect(find.text('剧情选项内容'), findsOneWidget);
    expect(find.text('下拉收起，查看完整剧情'), findsOneWidget);
  });

  testWidgets('toggle button collapses and expands the panel', (tester) async {
    await tester.pumpWidget(testApp());
    final toggle = find.byKey(const ValueKey('choice-panel-toggle'));

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.text('剧情选项内容'), findsNothing);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.text('剧情选项内容'), findsOneWidget);
  });
}
