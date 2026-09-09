import 'package:ai_tavern/app/theme.dart';
import 'package:ai_tavern/screens/trpg_shared/trpg_play_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ordinary campaign with one message has no gray remainder', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: TavernTheme.dark,
        home: RepaintBoundary(
          key: const ValueKey('ordinary_campaign_visual'),
          child: const Scaffold(
            body: Column(
              children: [
                TrpgSceneSummary(
                  dense: true,
                  title: '陌生旅店',
                  subtitle: '开场',
                  facts: [
                    TrpgFact(Icons.favorite_outline, 'HP 20/20'),
                    TrpgFact(Icons.health_and_safety_outlined, '状态正常'),
                  ],
                ),
                Expanded(
                  child: TrpgTimelineViewport(
                    children: [
                      TrpgMessageBubble(
                        label: '玩家',
                        content: '拿起桌上的钥匙。',
                        tone: TrpgMessageTone.player,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Skin token integration intentionally updates panel/bubble styling.
    // The baseline still verifies the complete opaque timeline remainder.
    await expectLater(
      find.byKey(const ValueKey('ordinary_campaign_visual')),
      matchesGoldenFile('goldens/trpg_timeline_one_message.png'),
    );
  });
}
