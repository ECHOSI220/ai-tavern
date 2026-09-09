import 'package:ai_tavern/models/trpg_game_models.dart';
import 'package:ai_tavern/models/trpg_models.dart';
import 'package:ai_tavern/screens/trpg_shared/trpg_player_guide_card.dart';
import 'package:ai_tavern/services/trpg/trpg_player_guidance_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('玩家下一步与骰子引导', () {
    test('从最新剧情、任务与现场人物生成无剧透行动建议', () {
      const service = TrpgPlayerGuidanceService();
      final guidance = service.build(session: _session(), playerId: 'player-1');

      expect(guidance.situation, contains('守卫正朝仓库门口靠近'));
      expect(guidance.objective, contains('找到失踪的记者'));
      expect(guidance.suggestedActions, hasLength(3));
      expect(
        guidance.suggestedActions.any((action) => action.contains('艾琳')),
        isTrue,
      );
    });

    test('输入有风险行动时提前说明自动骰、公式和用途', () {
      const service = TrpgPlayerGuidanceService();
      final preview = service.dicePreview(
        session: _session(),
        playerId: 'player-1',
        action: '我潜行绕过守卫，悄悄进入仓库。',
      );
      final safe = service.dicePreview(
        session: _session(),
        playerId: 'player-1',
        action: '我坐下和艾琳说话。',
      );

      expect(preview.title, contains('潜行检定'));
      expect(preview.detail, contains('1D20'));
      expect(preview.detail, contains('决定'));
      expect(safe.title, contains('无需投骰'));
    });

    testWidgets('建议可以一键填入输入框且实时更新骰子提示', (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  TrpgPlayerGuideCard(
                    session: _session(),
                    playerId: 'player-1',
                    controller: controller,
                  ),
                  TextField(controller: controller),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('接下来做什么'), findsOneWidget);
      expect(find.text('不用自己决定何时投骰'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('trpg-suggestion-0')));
      await tester.pump();
      expect(controller.text, isNotEmpty);

      await tester.tap(find.text('接下来做什么'));
      controller.text = '我攻击守卫';
      await tester.pump();
      expect(find.textContaining('攻击检定'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('紧凑模式默认只显示一行目标且仍可展开全部功能', (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TrpgPlayerGuideCard(
              session: _session(),
              playerId: 'player-1',
              controller: controller,
              initiallyExpanded: false,
            ),
          ),
        ),
      );

      expect(find.text('接下来做什么'), findsOneWidget);
      expect(find.textContaining('找到失踪的记者'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('trpg-suggested-actions')),
        findsNothing,
      );

      await tester.tap(find.text('接下来做什么'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('trpg-suggested-actions')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('trpg-dice-guidance')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

TRPGSession _session() {
  final now = DateTime.utc(2026, 9, 6, 12);
  return TRPGSession(
    id: 'guide-session',
    title: '雾港调查',
    mode: TRPGMode.solo,
    status: TRPGSessionStatus.active,
    createdAt: now,
    updatedAt: now,
    lastPlayedAt: now,
    campaignId: 'mist-harbor',
    players: [
      TRPGPlayer(
        playerId: 'player-1',
        displayName: '玩家',
        characterId: 'character-1',
        joinedAt: now,
      ),
    ],
    playerCharacters: const [
      PlayerCharacter(id: 'character-1', playerId: 'player-1', name: '调查员'),
    ],
    campaignState: CampaignState(
      activeQuests: const ['quest-1'],
      quests: [
        QuestState(
          questId: 'quest-1',
          title: '失踪案',
          status: QuestStatus.active,
          discoveredAt: now,
          objectives: const [
            QuestObjective(id: 'objective-1', description: '找到失踪的记者'),
          ],
        ),
      ],
    ),
    worldState: const WorldState(
      location: '旧港仓库',
      knownNpcs: ['npc-1'],
      currentScene: SceneState(
        sceneId: 'scene-1',
        locationId: 'warehouse',
        title: '旧港仓库',
        npcIds: ['npc-1'],
      ),
      npcs: [
        NPCState(
          npcId: 'npc-1',
          name: '艾琳',
          knownToPlayer: true,
          locationId: 'warehouse',
        ),
      ],
    ),
    chatHistory: [
      TRPGMessage(
        id: 'gm-1',
        messageType: TRPGMessageType.gmMessage,
        content: '远处传来急促脚步声，守卫正朝仓库门口靠近。',
        createdAt: now,
      ),
    ],
  );
}
