import 'package:ai_tavern/screens/trpg_shared/trpg_play_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('TRPG play controls remain usable on a narrow phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: Scaffold(
          body: Column(
            children: [
              const TrpgSceneSummary(
                dense: true,
                title: '雾港旧仓库',
                subtitle: '深夜 · 暴雨',
                facts: [
                  TrpgFact(Icons.favorite_outline, 'HP 18/20'),
                  TrpgFact(Icons.assignment_outlined, '调查失踪者'),
                  TrpgFact(
                    Icons.sports_martial_arts_outlined,
                    '战斗 · 第 2 回合',
                    emphasized: true,
                  ),
                ],
              ),
              Expanded(
                child: TrpgTimelineViewport(
                  children: const [
                    TrpgMessageBubble(
                      label: 'AI GM',
                      content: '雨水敲打着生锈的铁门，你听见仓库深处传来脚步声。',
                      tone: TrpgMessageTone.gm,
                    ),
                    TrpgMessageBubble(
                      label: '玩家',
                      content: '我压低身形，沿墙靠近声音来源。',
                      tone: TrpgMessageTone.player,
                    ),
                  ],
                ),
              ),
              TrpgComposer(
                controller: controller,
                hintText: '描述你的行动…',
                onSend: () {},
                modeSelector: const Wrap(
                  spacing: 6,
                  children: [
                    ChoiceChip(selected: true, label: Text('行动')),
                    ChoiceChip(selected: false, label: Text('闲聊')),
                    ChoiceChip(selected: false, label: Text('秘密行动')),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('trpg_action_input')), findsOneWidget);
    expect(find.byKey(const ValueKey('trpg_send_action')), findsOneWidget);
    expect(tester.getSize(find.byType(TrpgSceneSummary)).height, lessThan(110));
    expect(tester.takeException(), isNull);
  });

  testWidgets('timeline keeps a dark backdrop and scrolls back to top', (
    tester,
  ) async {
    const background = Color(0xff171311);
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(
          useMaterial3: true,
        ).copyWith(scaffoldBackgroundColor: background),
        home: Scaffold(
          body: SizedBox(
            height: 420,
            child: TrpgTimelineViewport(
              controller: scroll,
              children: List.generate(
                20,
                (index) => SizedBox(height: 64, child: Text('消息 $index')),
              ),
            ),
          ),
        ),
      ),
    );

    final timeline = find.byKey(const ValueKey('trpg_timeline_scroll_view'));
    expect(timeline, findsOneWidget);
    expect(
      find.descendant(of: timeline, matching: find.byType(Material)),
      findsNothing,
    );

    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pump();
    final bottomOffset = scroll.offset;
    await tester.drag(timeline, const Offset(0, 260));
    await tester.pumpAndSettle();
    expect(scroll.offset, lessThan(bottomOffset));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'confirmed action replaces send arrow with a working cancel button',
    (tester) async {
      final controller = TextEditingController(text: '已确认行动');
      addTearDown(controller.dispose);
      var cancelled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TrpgComposer(
              controller: controller,
              hintText: '行动已确认',
              enabled: false,
              onSend: () {},
              onCancelConfirmation: () => cancelled = true,
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
      expect(find.byIcon(Icons.arrow_upward_rounded), findsNothing);
      await tester.tap(find.byKey(const ValueKey('trpg_send_action')));
      expect(cancelled, isTrue);
    },
  );

  testWidgets('quick actions scroll instead of overflowing', (tester) async {
    tester.view.physicalSize = const Size(320, 160);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TrpgQuickActions(
            actions: List.generate(
              8,
              (index) => TrpgActionSpec(
                icon: Icons.extension_outlined,
                label: '功能 $index',
                onPressed: () {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('功能 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
