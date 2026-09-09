import 'dart:io';

import 'package:ai_tavern/models/trpg_game_models.dart';
import 'package:ai_tavern/repositories/trpg_session_repository.dart';
import 'package:ai_tavern/services/ai/openai_compatible_provider.dart';
import 'package:ai_tavern/services/storage_service.dart';
import 'package:ai_tavern/services/trpg/ai_gm_tool_registry.dart';
import 'package:ai_tavern/services/trpg/campaign_service.dart';
import 'package:ai_tavern/services/trpg/trpg_session_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Mist Harbor complete structured flow saves, exits and restores',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'mist_harbor_e2e',
      );
      final storage = StorageService();
      await storage.initialize(
        databasePath: '${directory.path}${Platform.pathSeparator}game.db',
      );
      final repository = TRPGSessionRepository(storage);
      final sessionService = TRPGSessionService(repository);
      var session = await sessionService.createSolo(
        campaign: const CampaignService().getById('mist_harbor_test'),
        playerName: '玩家',
        characterName: '晨歌',
        characterBackground: '调查员',
        stats: const {'STR': 10, 'DEX': 14, 'INT': 14, 'PER': 14, 'CHA': 10},
        maxHp: 20,
      );
      final characterId = session.playerCharacters.single.id;
      final tools = AIGMToolRegistry();

      Future<void> execute(
        String id,
        String name,
        Map<String, Object?> args,
      ) async {
        session = (await tools.execute(
          session: session,
          actionId: 'adventure-action',
          call: OpenAIToolCall(id: id, name: name, arguments: args),
        )).session;
      }

      await execute('check', 'skill_check', {
        'characterId': characterId,
        'skillId': 'perception',
        'difficulty': 5,
        'reason': '观察港口',
      });
      await execute('clue', 'discover_clue', {
        'clueId': 'muddy_bootprints',
        'name': '泥泞脚印',
        'description': '通向仓库侧门',
        'characterId': characterId,
      });
      await execute('key', 'give_item', {
        'characterId': characterId,
        'itemId': 'warehouse_brass_key',
        'name': '旧仓库黄铜钥匙',
        'quantity': 1,
        'category': 'keyItem',
        'reason': '守卫交给玩家',
      });
      await execute('consume-key', 'remove_item', {
        'characterId': characterId,
        'itemId': 'warehouse_brass_key',
        'amount': 1,
        'reason': '打开仓库侧门',
      });
      await execute('door', 'update_world_flag', {
        'flag': 'warehouse_door_open',
        'value': true,
        'reason': '使用钥匙',
      });
      await execute('scene', 'change_scene', {
        'sceneId': 'warehouse_interior',
        'locationId': 'warehouse_interior',
        'title': '旧港仓库内部',
        'description': '腐木地板下传来水声。',
        'atmosphere': '黑暗、潮湿',
        'reason': '打开仓库门',
      });
      await execute('damage', 'modify_hp', {
        'characterId': characterId,
        'amount': -4,
        'reason': '腐朽木板塌陷',
        'damageType': 'bludgeoning',
      });
      await execute('quest-progress', 'update_quest', {
        'questId': 'missing_keeper',
        'operation': 'progress',
        'progress': '已进入旧港仓库并找到地下室入口',
      });
      await execute('quest-complete', 'update_quest', {
        'questId': 'missing_keeper',
        'operation': 'complete',
        'progress': '已找到失踪调查员',
      });

      await repository.upsert(session);
      await storage.close();

      final reopened = StorageService();
      await reopened.initialize(
        databasePath: '${directory.path}${Platform.pathSeparator}game.db',
      );
      final restored = await TRPGSessionRepository(
        reopened,
      ).getById(session.id);
      expect(restored, isNotNull);
      expect(restored!.playerCharacters.single.hp, 16);
      expect(restored.playerCharacters.single.inventoryItems, isEmpty);
      expect(restored.worldState.worldFlags['warehouse_door_open'], true);
      expect(restored.worldState.currentScene.sceneId, 'warehouse_interior');
      expect(restored.campaignState.clues.first.discovered, true);
      expect(restored.campaignState.quests.first.status, QuestStatus.completed);
      expect(restored.toolExecutions, hasLength(9));

      await reopened.close();
      await directory.delete(recursive: true);
    },
  );
}
