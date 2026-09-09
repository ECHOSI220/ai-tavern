import 'package:ai_tavern/screens/trpg_shared/trpg_play_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('TRPG timeline always paints the fixed tavern-dark backdrop', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 600,
            child: TrpgTimelineViewport(
              children: [
                TrpgMessageBubble(
                  label: 'GM',
                  content: '召唤之夜开始。',
                  tone: TrpgMessageTone.gm,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final timeline = find.byType(TrpgTimelineViewport);
    expect(timeline, findsOneWidget);
    final backdrop = tester.widget<ColoredBox>(
      find.byKey(const ValueKey('trpg_timeline_dark_backdrop')),
    );
    expect(backdrop.color, kTrpgTimelineBackground);
    expect(
      find.descendant(of: timeline, matching: find.byType(Material)),
      findsNothing,
    );
    expect(
      find.descendant(
        of: timeline,
        matching: find.byType(SingleChildScrollView),
      ),
      findsOneWidget,
    );
    final contentBackdrop = tester.widget<ColoredBox>(
      find.byKey(const ValueKey('trpg_timeline_content_backdrop')),
    );
    expect(contentBackdrop.color.toARGB32(), 0xFF171311);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('trpg_timeline_content_backdrop')))
          .height,
      600,
    );
  });

  testWidgets('zero-message timeline is dark and creates no scroll viewport', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Center(
            child: SizedBox(
              width: 120,
              height: 120,
              child: TrpgTimelineViewport(children: []),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final timeline = find.byType(TrpgTimelineViewport);
    expect(
      find.descendant(
        of: timeline,
        matching: find.byType(SingleChildScrollView),
      ),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('trpg_timeline_empty_space')),
      findsOneWidget,
    );
    final backdrop = tester.widget<ColoredBox>(
      find.byKey(const ValueKey('trpg_timeline_dark_backdrop')),
    );
    expect(backdrop.color.toARGB32(), 0xFF171311);
  });

  testWidgets('TRPG timeline drops empty message bubbles', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TrpgTimelineViewport(
            children: [
              TrpgMessageBubble(
                label: 'GM 主持',
                content: '   \n ',
                tone: TrpgMessageTone.gm,
              ),
              TrpgMessageBubble(
                label: 'GM 主持',
                content: '真正的开场内容',
                tone: TrpgMessageTone.gm,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('GM 主持'), findsOneWidget);
    expect(find.text('真正的开场内容'), findsOneWidget);
    expect(find.byType(SizedBox), findsWidgets);
  });
}
