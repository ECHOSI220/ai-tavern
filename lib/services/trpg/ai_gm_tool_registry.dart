// ignore_for_file: use_null_aware_elements

import 'package:uuid/uuid.dart';

import '../../models/trpg_game_models.dart';
import '../../models/trpg_memory_models.dart';
import '../../models/trpg_models.dart';
import '../../models/trpg_presentation_models.dart';
import '../../models/trpg_party_models.dart';
import '../../models/trpg_living_npc_models.dart';
import '../../models/holy_grail_war_models.dart';
import '../../models/trpg_dice_models.dart';
import '../ai/openai_compatible_provider.dart';
import 'dice_service.dart';
import 'trpg_rule_engine.dart';
import 'trpg_state_service.dart';
import 'living_npc_service.dart';
import 'world_generator.dart';
import 'faction_simulation_service.dart';
import 'holy_grail_war_manager.dart';
import 'growth_resolver.dart';
import 'trpg_check_pipeline.dart';

typedef ToolSaveCallback = Future<void> Function(TRPGSession session);

class ToolExecutionOutcome {
  const ToolExecutionOutcome({
    required this.session,
    required this.result,
    required this.record,
    required this.wasCached,
  });
  final TRPGSession session;
  final Map<String, Object?> result;
  final ToolExecutionRecord record;
  final bool wasCached;
}

class AIGMToolRegistry {
  AIGMToolRegistry({
    TRPGRuleEngine? ruleEngine,
    TRPGStateService? stateService,
    DiceService? diceService,
    LivingNPCService? livingNpcService,
    WorldGenerationRuntime? worldGenerationRuntime,
    FactionManager? factionManager,
    WorldSimulationService? worldSimulationService,
    HolyGrailWarManager? holyGrailWarManager,
    GrowthResolver? growthResolver,
    TRPGCheckPipeline? checkPipeline,
  }) : _rules = ruleEngine ?? TRPGRuleEngine(),
       _state = stateService ?? TRPGStateService(),
       _dice = diceService ?? DiceService(),
       _livingNpc = livingNpcService ?? const LivingNPCService(),
       _worldGeneration =
           worldGenerationRuntime ?? const WorldGenerationRuntime(),
       _faction = factionManager ?? const FactionManager(),
       _worldSimulation =
           worldSimulationService ?? const WorldSimulationService(),
       _holyGrail = holyGrailWarManager ?? const HolyGrailWarManager(),
       _growth = growthResolver ?? GrowthResolver(),
       _checks = checkPipeline ?? TRPGCheckPipeline();

  final TRPGRuleEngine _rules;
  final TRPGStateService _state;
  final DiceService _dice;
  final LivingNPCService _livingNpc;
  final WorldGenerationRuntime _worldGeneration;
  final FactionManager _faction;
  final WorldSimulationService _worldSimulation;
  final HolyGrailWarManager _holyGrail;
  final GrowthResolver _growth;
  final TRPGCheckPipeline _checks;
  static const _uuid = Uuid();

  List<Map<String, Object?>> get schemas => [
    _schema(
      'roll_dice',
      '由程序生成权威骰子。必须说明为何需要投骰，以及结果将决定什么；不得自行编造点数。',
      {
        'formula': _string(),
        'sides': _integer(),
        'count': _integer(),
        'modifier': _integer(),
        'difficulty': _integer(),
        'action': _string(),
        'rulePackage': _string(
          enumValues: DiceRulePackageType.values
              .map((value) => value.name)
              .toList(),
        ),
        'reason': _string(),
        'actorPlayerId': _string(),
        'actorCharacterId': _string(),
        'turnId': _string(),
        'actionId': _string(),
      },
      ['reason'],
    ),
    _schema(
      'skill_check',
      '执行正式属性或技能检定。',
      {
        'characterId': _string(),
        'stat': _string(enumValues: TRPGRuleEngine.validStats.toList()),
        'skillId': _string(
          enumValues: TRPGRuleEngine.skills.map((item) => item.id).toList(),
        ),
        'difficulty': _integer(minimum: 5, maximum: 25),
        'reason': _string(),
        'advantageMode': _string(
          enumValues: AdvantageMode.values.map((item) => item.name).toList(),
        ),
        'actorPlayerId': _string(),
        'actorCharacterId': _string(),
        'turnId': _string(),
        'actionId': _string(),
      },
      ['characterId', 'difficulty', 'reason'],
    ),
    _schema(
      'trigger_rule_check',
      '当世界事件主动制造危险或不确定性时，请求规则系统分析并执行权威检定。不得指定骰点、成功或属性变化。',
      {
        'characterId': _string(),
        'situation': _string(),
        'targetId': _string(),
        'turnId': _string(),
      },
      ['characterId', 'situation'],
    ),
    _schema(
      'get_character',
      '读取玩家角色规则状态。',
      {'characterId': _string()},
      ['characterId'],
    ),
    _schema(
      'get_inventory',
      '读取角色背包。',
      {'characterId': _string()},
      ['characterId'],
    ),
    _schema(
      'give_item',
      '给予角色唯一 id 的物品。',
      {
        'characterId': _string(),
        'itemId': _string(),
        'name': _string(),
        'description': _string(),
        'quantity': _integer(minimum: 1, maximum: 999),
        'category': _string(
          enumValues: InventoryCategory.values
              .map((item) => item.name)
              .toList(),
        ),
        'usable': {'type': 'boolean'},
        'reason': _string(),
      },
      ['characterId', 'itemId', 'name', 'quantity', 'reason'],
    ),
    _schema(
      'remove_item',
      '消耗或移除背包物品。',
      {
        'characterId': _string(),
        'itemId': _string(),
        'amount': _integer(minimum: 1, maximum: 999),
        'reason': _string(),
      },
      ['characterId', 'itemId', 'amount', 'reason'],
    ),
    _schema(
      'modify_hp',
      '修改角色 HP，负数为伤害，正数为治疗。',
      {
        'characterId': _string(),
        'amount': _integer(minimum: -1000, maximum: 1000),
        'reason': _string(),
        'damageType': _string(),
      },
      ['characterId', 'amount', 'reason'],
    ),
    _schema(
      'add_status',
      '添加或刷新结构化状态。',
      {
        'characterId': _string(),
        'statusId': _string(),
        'name': _string(),
        'description': _string(),
        'duration': _integer(minimum: 1, maximum: 999),
        'source': _string(),
      },
      ['characterId', 'statusId', 'name'],
    ),
    _schema(
      'remove_status',
      '移除状态。',
      {'characterId': _string(), 'statusId': _string()},
      ['characterId', 'statusId'],
    ),
    _schema(
      'update_quest',
      '发现、激活、推进、完成或失败任务。',
      {
        'questId': _string(),
        'operation': _string(
          enumValues: ['discover', 'activate', 'progress', 'complete', 'fail'],
        ),
        'title': _string(),
        'description': _string(),
        'progress': _string(),
        'objectiveId': _string(),
        'objectiveProgress': _integer(minimum: 0, maximum: 999),
      },
      ['questId', 'operation'],
    ),
    _schema(
      'change_scene',
      '切换场景和世界地点。',
      {
        'sceneId': _string(),
        'locationId': _string(),
        'title': _string(),
        'description': _string(),
        'atmosphere': _string(),
        'time': _string(),
        'weather': _string(),
        'reason': _string(),
      },
      ['sceneId', 'locationId', 'title', 'description', 'reason'],
    ),
    _schema(
      'move_character',
      '移动单个玩家角色；多人分流时必须使用此工具，不能用 change_scene 移动全队。',
      {
        'actorPlayerId': _string(),
        'actorCharacterId': _string(),
        'characterId': _string(),
        'targetSceneId': _string(),
        'targetLocationId': _string(),
        'turnId': _string(),
        'actionId': _string(),
        'reason': _string(),
      },
      [
        'actorPlayerId',
        'actorCharacterId',
        'characterId',
        'targetLocationId',
        'turnId',
        'actionId',
        'reason',
      ],
    ),
    _schema(
      'move_characters',
      '仅移动明确绑定的多个玩家角色；不会自动移动其他角色。',
      {
        'actorPlayerId': _string(),
        'actorCharacterId': _string(),
        'characterIds': {'type': 'array', 'items': _string()},
        'targetSceneId': _string(),
        'targetLocationId': _string(),
        'turnId': _string(),
        'actionId': _string(),
        'reason': _string(),
      },
      [
        'actorPlayerId',
        'actorCharacterId',
        'characterIds',
        'targetLocationId',
        'turnId',
        'actionId',
        'reason',
      ],
    ),
    _schema('get_world_state', '读取当前世界和场景状态。', {}, []),
    _schema(
      'update_world_flag',
      '更新明确的世界布尔标记。',
      {
        'flag': _string(),
        'value': {'type': 'boolean'},
        'reason': _string(),
      },
      ['flag', 'value', 'reason'],
    ),
    _schema('get_campaign_state', '读取任务、线索和进度。', {}, []),
    _schema('get_recent_events', '读取最近结构化事件。', {
      'limit': _integer(minimum: 1, maximum: 30),
    }, []),
    _schema(
      'discover_clue',
      '正式发现并记录线索。',
      {
        'clueId': _string(),
        'name': _string(),
        'description': _string(),
        'characterId': _string(),
      },
      ['clueId', 'name', 'description', 'characterId'],
    ),
    _schema(
      'modify_npc_relationship',
      '调整 NPC 关系值。',
      {
        'npcId': _string(),
        'amount': _integer(minimum: -100, maximum: 100),
        'reason': _string(),
      },
      ['npcId', 'amount', 'reason'],
    ),
    _schema(
      'discover_location',
      '正式发现一个存在的地点。',
      {'locationId': _string()},
      ['locationId'],
    ),
    _schema(
      'discover_npc',
      '让玩家正式认识一个存在的 NPC。',
      {'npcId': _string()},
      ['npcId'],
    ),
    _schema(
      'reveal_information',
      '把当前玩家拥有的私人信息公开给队伍。',
      {'knowledgeId': _string()},
      ['knowledgeId'],
    ),
    _schema(
      'send_private_message',
      '向当前房间内指定玩家发送私人信息。',
      {'recipientPlayerId': _string(), 'content': _string()},
      ['recipientPlayerId', 'content'],
    ),
    _schema(
      'request_private_roll',
      '请求由服务器执行、只对指定玩家和 GM 可见的检定。',
      {'playerId': _string(), 'sides': _integer(), 'reason': _string()},
      ['playerId', 'sides', 'reason'],
    ),
    _schema(
      'add_npc_memory',
      '为 NPC 保存一条压缩后的重要记忆。',
      {
        'npcId': _string(),
        'summary': _string(),
        'playerId': _string(),
        'importance': _integer(minimum: 1, maximum: 5),
      },
      ['npcId', 'summary'],
    ),
    _schema(
      'advance_world_time',
      '推进结构化世界时间，并统一结算到期的 NPC、势力、任务和世界事件。',
      {'minutes': _integer(minimum: 0, maximum: 43200), 'reason': _string()},
      ['minutes', 'reason'],
    ),
    _schema(
      'record_faction_support',
      '记录玩家对势力的实质支持，并让其他势力按规则响应。',
      {
        'factionId': _string(),
        'playerId': _string(),
        'reason': _string(),
        'resourceBoost': _integer(minimum: 1, maximum: 30),
      },
      ['factionId', 'playerId', 'reason'],
    ),
    _schema(
      'modify_faction_relationship',
      '根据已经发生的事件调整两个势力的数值关系，程序会限制到 -100~100。',
      {
        'fromFactionId': _string(),
        'toFactionId': _string(),
        'delta': _integer(minimum: -100, maximum: 100),
        'reason': _string(),
      },
      ['fromFactionId', 'toFactionId', 'delta', 'reason'],
    ),
    _schema(
      'declare_faction_war',
      '在有明确剧情原因时宣告两个既存势力进入战争；后续战斗仍由规则结算。',
      {
        'attackerFactionId': _string(),
        'defenderFactionId': _string(),
        'reason': _string(),
      },
      ['attackerFactionId', 'defenderFactionId', 'reason'],
    ),
    _schema(
      'reveal_faction_knowledge',
      '把某条势力秘密或情报仅揭示给指定玩家，不会向其他玩家广播。',
      {'playerId': _string(), 'secretId': _string(), 'knowledgeId': _string()},
      ['playerId'],
    ),
    _schema(
      'expand_generated_location',
      '玩家首次进入 AI 生成地点时，按需生成普通居民并接入 NPC Life；已生成地点不会重复生成。',
      {'locationId': _string()},
      ['locationId'],
    ),
    _schema(
      'record_npc_interaction',
      '记录玩家或其他 NPC 对某个 NPC 关系与情绪产生的事件驱动变化。',
      {
        'npcId': _string(),
        'targetCharacterId': _string(),
        'reason': _string(),
        'trust': _integer(minimum: -100, maximum: 100),
        'fear': _integer(minimum: -100, maximum: 100),
        'respect': _integer(minimum: -100, maximum: 100),
        'hate': _integer(minimum: -100, maximum: 100),
        'affection': _integer(minimum: -100, maximum: 100),
        'suspicion': _integer(minimum: -100, maximum: 100),
        'memoryImportance': _integer(minimum: 1, maximum: 200),
      },
      ['npcId', 'targetCharacterId', 'reason'],
    ),
    _schema(
      'set_npc_goal',
      '新增或更新 NPC 自己的长期目标。',
      {
        'npcId': _string(),
        'goalId': _string(),
        'type': _string(
          enumValues: NPCGoalType.values.map((value) => value.name).toList(),
        ),
        'description': _string(),
        'priority': _integer(minimum: 0, maximum: 100),
        'targetId': _string(),
        'targetLocationId': _string(),
      },
      ['npcId', 'goalId', 'type', 'description', 'priority'],
    ),
    _schema(
      'record_npc_secret',
      '保存仅 NPC、GM 和明确知情者可见的秘密。',
      {
        'npcId': _string(),
        'content': _string(),
        'importance': _integer(minimum: 1, maximum: 200),
        'knownBy': {'type': 'array', 'items': _string()},
      },
      ['npcId', 'content'],
    ),
    _schema(
      'kill_npc',
      '确认 NPC 死亡并保留死亡事件、凶手、地点和目击者创伤记忆。',
      {
        'npcId': _string(),
        'killerId': _string(),
        'locationId': _string(),
        'reason': _string(),
      },
      ['npcId', 'reason'],
    ),
    _schema(
      'record_promise',
      '记录玩家、NPC或队友作出的重要承诺。',
      {
        'promiser': _string(),
        'promiseTo': _string(),
        'content': _string(),
        'deadline': _string(),
        'visibility': _string(
          enumValues: MemoryVisibility.values
              .map((value) => value.name)
              .toList(),
        ),
      },
      ['promiser', 'promiseTo', 'content'],
    ),
    _schema(
      'resolve_promise',
      '将已有承诺标记为已兑现、已违背或已过期。',
      {
        'promiseId': _string(),
        'status': _string(enumValues: ['fulfilled', 'broken', 'expired']),
      },
      ['promiseId', 'status'],
    ),
    _schema(
      'record_knowledge',
      '记录某个玩家或 NPC 知道、怀疑或错误相信的对象。',
      {
        'subjectId': _string(),
        'relation': _string(
          enumValues: KnowledgeRelationType.values
              .map((value) => value.name)
              .toList(),
        ),
        'objectId': _string(),
        'confidence': _string(
          enumValues: MemoryConfidence.values
              .map((value) => value.name)
              .toList(),
        ),
      },
      ['subjectId', 'relation', 'objectId'],
    ),
    _schema(
      'add_story_thread',
      '登记尚未解决的剧情线或长期伏笔。',
      {
        'title': _string(),
        'description': _string(),
        'relatedEntityIds': {'type': 'array', 'items': _string()},
        'gmOnly': {'type': 'boolean'},
        'foreshadowing': {'type': 'boolean'},
      },
      ['title', 'description'],
    ),
    _schema(
      'update_story_thread',
      '推进、解决或放弃已有剧情线。',
      {
        'threadId': _string(),
        'status': _string(
          enumValues: StoryThreadStatus.values
              .map((value) => value.name)
              .toList(),
        ),
      },
      ['threadId', 'status'],
    ),
    _schema(
      'move_npc',
      '将存在的 NPC 移动到存在的地点。',
      {'npcId': _string(), 'locationId': _string()},
      ['npcId', 'locationId'],
    ),
    _schema(
      'start_combat',
      '开始轻量战斗并生成先攻。',
      {
        'participantIds': {'type': 'array', 'items': _string()},
        'reason': _string(),
      },
      ['participantIds', 'reason'],
    ),
    _schema(
      'attack_check',
      '执行一次攻击命中检定。',
      {
        'attackerId': _string(),
        'targetId': _string(),
        'stat': _string(enumValues: TRPGRuleEngine.validStats.toList()),
        'difficulty': _integer(minimum: 5, maximum: 25),
        'reason': _string(),
      },
      ['attackerId', 'targetId', 'difficulty', 'reason'],
    ),
    _schema(
      'apply_damage',
      '程序掷伤害骰并扣减玩家目标 HP。',
      {
        'sourceId': _string(),
        'targetId': _string(),
        'diceSides': _integer(),
        'diceCount': _integer(minimum: 1, maximum: 10),
        'modifier': _integer(minimum: -20, maximum: 100),
        'damageType': _string(),
        'reason': _string(),
      },
      [
        'sourceId',
        'targetId',
        'diceSides',
        'diceCount',
        'damageType',
        'reason',
      ],
    ),
    _schema('end_combat', '结束战斗并清理先攻。', {'reason': _string()}, ['reason']),
    _schema(
      'set_expression',
      '只改变 NPC 演出表情，不修改规则状态。',
      {
        'npcId': _string(),
        'expression': _string(
          enumValues: NPCExpression.values.map((value) => value.name).toList(),
        ),
      },
      ['npcId', 'expression'],
    ),
    _schema(
      'show_character',
      '在演出层显示一个存在的 NPC，最多三人。',
      {
        'npcId': _string(),
        'position': _string(
          enumValues: PortraitPosition.values
              .map((value) => value.name)
              .toList(),
        ),
        'expression': _string(
          enumValues: NPCExpression.values.map((value) => value.name).toList(),
        ),
      },
      ['npcId', 'position', 'expression'],
    ),
    _schema('hide_character', '从演出层隐藏 NPC。', {'npcId': _string()}, ['npcId']),
    _schema(
      'set_bgm',
      '按白名单情绪选择 BGM，不接收文件路径。',
      {
        'mood': _string(
          enumValues: [
            'exploration',
            'mystery',
            'danger',
            'battle',
            'calm',
            'sad',
            'relax',
            'boss',
          ],
        ),
      },
      ['mood'],
    ),
    _schema(
      'set_ambient',
      '按白名单环境类型选择环境音。',
      {
        'ambient': _string(
          enumValues: [
            'rain',
            'wind',
            'forest',
            'crowd',
            'fire',
            'machine',
            'sea',
            'warehouse',
            'underground',
          ],
        ),
      },
      ['ambient'],
    ),
    _schema(
      'play_sfx',
      '播放白名单短音效。',
      {
        'sfx': _string(
          enumValues: [
            'door_open',
            'door_close',
            'gunshot',
            'sword',
            'hit',
            'heal',
            'item',
            'dice',
            'quest',
            'footstep',
          ],
        ),
      },
      ['sfx'],
    ),
    _schema(
      'set_scene_visual',
      '设置场景的相对资源 ID 与转场，不接受绝对文件路径。',
      {
        'backgroundId': _string(),
        'transition': _string(
          enumValues: SceneTransitionStyle.values
              .map((value) => value.name)
              .toList(),
        ),
      },
      ['backgroundId', 'transition'],
    ),
    _schema(
      'select_holy_grail_master',
      '为当前玩家选择圣杯战争御主身份预设，并记录愿望、人格、起源与家系。',
      {
        'playerId': _string(),
        'archetype': _string(
          enumValues: MasterArchetype.values
              .map((value) => value.name)
              .toList(),
        ),
        'wish': _string(),
        'personality': _string(),
        'origin': _string(),
        'family': _string(),
      },
      ['playerId', 'archetype'],
    ),
    _schema(
      'summon_servant',
      '圣杯战争中根据御主愿望、性格、媒介和起源召唤尚未占用职阶的从者。',
      {'masterId': _string(), 'catalyst': _string()},
      ['masterId'],
    ),
    _schema(
      'investigate_servant',
      '对从者进行观察、跟踪、调查或偷袭，获得该玩家私有的能力和真名线索。',
      {
        'playerId': _string(),
        'targetServantId': _string(),
        'action': _string(
          enumValues: InvestigationAction.values
              .map((value) => value.name)
              .toList(),
        ),
      },
      ['playerId', 'targetServantId', 'action'],
    ),
    _schema(
      'use_command_spell',
      '消耗一划令咒以强制命令、强化或召回自己的从者。',
      {
        'masterId': _string(),
        'effect': _string(
          enumValues: CommandSpellEffect.values
              .map((value) => value.name)
              .toList(),
        ),
        'order': _string(),
      },
      ['masterId', 'effect', 'order'],
    ),
    _schema(
      'release_noble_phantasm',
      '使用宝具。真名解放会增强威力，但向目击玩家暴露身份。',
      {
        'servantId': _string(),
        'trueNameRelease': {'type': 'boolean'},
        'witnessPlayerIds': {'type': 'array', 'items': _string()},
      },
      ['servantId', 'trueNameRelease'],
    ),
    _schema(
      'holy_grail_noble_phantasm_check',
      '执行圣杯战争宝具 D100 参数判定，并展示宝具等级修正。必须说明判定原因。',
      {
        'playerId': _string(),
        'rank': _string(enumValues: const ['E', 'D', 'C', 'B', 'A', 'EX']),
        'difficulty': _integer(),
        'reason': _string(),
      },
      ['playerId', 'rank', 'reason'],
    ),
    _schema(
      'form_holy_alliance',
      '让两个或以上仍在参战的御主建立临时盟约。',
      {
        'masterIds': {'type': 'array', 'items': _string(), 'minItems': 2},
        'purpose': _string(),
        'terms': {'type': 'array', 'items': _string()},
      },
      ['masterIds', 'purpose'],
    ),
    _schema(
      'break_holy_alliance',
      '解除或背叛一项圣杯战争盟约。',
      {
        'allianceId': _string(),
        'actorMasterId': _string(),
        'betrayal': {'type': 'boolean'},
      },
      ['allianceId', 'actorMasterId', 'betrayal'],
    ),
    _schema(
      'eliminate_holy_grail_team',
      '在规则与战斗结果已经确认后，将御主阵营标记为退场并自动判断阶段和胜利条件。',
      {
        'masterId': _string(),
        'masterKilled': {'type': 'boolean'},
      },
      ['masterId', 'masterKilled'],
    ),
  ];

  Future<ToolExecutionOutcome> execute({
    required TRPGSession session,
    required String actionId,
    required OpenAIToolCall call,
    ToolSaveCallback? onMutated,
  }) async {
    final cached = session.toolExecutions
        .where((record) => record.toolCallId == call.id)
        .firstOrNull;
    if (cached != null) {
      return ToolExecutionOutcome(
        session: session,
        result: cached.result,
        record: cached,
        wasCached: true,
      );
    }
    var next = session;
    late Map<String, Object?> result;
    var succeeded = true;
    try {
      final args = call.arguments;
      switch (call.name) {
        case 'select_holy_grail_master':
          final outcome = _holyGrail.selectMaster(
            session,
            playerId: _text(args, 'playerId'),
            archetype: MasterArchetype.values.byName(_text(args, 'archetype')),
            wish: _optionalText(args, 'wish'),
            personality: _optionalText(args, 'personality'),
            origin: _optionalText(args, 'origin'),
            family: _optionalText(args, 'family'),
          );
          next = outcome.session;
          succeeded = outcome.succeeded;
          result = {'summary': outcome.summary, 'succeeded': outcome.succeeded};
        case 'summon_servant':
          final outcome = _holyGrail.summonServant(
            session,
            masterId: _text(args, 'masterId'),
            catalyst: _optionalText(args, 'catalyst') ?? '',
          );
          next = outcome.session;
          succeeded = outcome.succeeded;
          result = {'summary': outcome.summary, 'succeeded': outcome.succeeded};
        case 'investigate_servant':
          final outcome = _holyGrail.investigate(
            session,
            playerId: _text(args, 'playerId'),
            targetServantId: _text(args, 'targetServantId'),
            action: InvestigationAction.values.byName(_text(args, 'action')),
          );
          next = outcome.session;
          succeeded = outcome.succeeded;
          result = {'summary': outcome.summary, 'succeeded': outcome.succeeded};
        case 'use_command_spell':
          final outcome = _holyGrail.useCommandSpell(
            session,
            masterId: _text(args, 'masterId'),
            effect: CommandSpellEffect.values.byName(_text(args, 'effect')),
            order: _text(args, 'order'),
          );
          next = outcome.session;
          succeeded = outcome.succeeded;
          result = {'summary': outcome.summary, 'succeeded': outcome.succeeded};
        case 'release_noble_phantasm':
          final outcome = _holyGrail.releaseNoblePhantasm(
            session,
            servantId: _text(args, 'servantId'),
            trueNameRelease: _bool(args, 'trueNameRelease'),
            witnessPlayerIds: (args['witnessPlayerIds'] as List? ?? const [])
                .map((value) => value.toString())
                .toList(),
          );
          next = outcome.session;
          succeeded = outcome.succeeded;
          result = {'summary': outcome.summary, 'succeeded': outcome.succeeded};
        case 'holy_grail_noble_phantasm_check':
          final roll = _dice.holyGrailNoblePhantasmCheck(
            playerId: _text(args, 'playerId'),
            rank: _text(args, 'rank'),
            reason: _text(args, 'reason'),
            difficulty: _optionalInt(args, 'difficulty'),
          );
          next = _dice.recordResult(session, roll);
          result = roll.toJson();
        case 'form_holy_alliance':
          final outcome = _holyGrail.formAlliance(
            session,
            masterIds: (args['masterIds'] as List? ?? const [])
                .map((value) => value.toString())
                .toList(),
            purpose: _text(args, 'purpose'),
            terms: (args['terms'] as List? ?? const [])
                .map((value) => value.toString())
                .toList(),
          );
          next = outcome.session;
          succeeded = outcome.succeeded;
          result = {'summary': outcome.summary, 'succeeded': outcome.succeeded};
        case 'break_holy_alliance':
          final outcome = _holyGrail.breakAlliance(
            session,
            allianceId: _text(args, 'allianceId'),
            actorMasterId: _text(args, 'actorMasterId'),
            betrayal: _bool(args, 'betrayal'),
          );
          next = outcome.session;
          succeeded = outcome.succeeded;
          result = {'summary': outcome.summary, 'succeeded': outcome.succeeded};
        case 'eliminate_holy_grail_team':
          final outcome = _holyGrail.eliminateTeam(
            session,
            masterId: _text(args, 'masterId'),
            masterKilled: _bool(args, 'masterKilled'),
          );
          next = outcome.session;
          succeeded = outcome.succeeded;
          result = {'summary': outcome.summary, 'succeeded': outcome.succeeded};
        case 'roll_dice':
          final sides = _optionalInt(args, 'sides') ?? 20;
          final actorCharacterId = _optionalText(args, 'actorCharacterId');
          final actorCharacter = actorCharacterId == null
              ? null
              : _character(session, actorCharacterId);
          final actorPlayerId =
              _optionalText(args, 'actorPlayerId') ??
              actorCharacter?.playerId ??
              session.players.first.playerId;
          if (actorCharacter != null &&
              actorCharacter.playerId != actorPlayerId) {
            throw TRPGRuleException('actorPlayerId 与 actorCharacterId 不匹配');
          }
          final count = _optionalInt(args, 'count') ?? 1;
          final modifier = _optionalInt(args, 'modifier') ?? 0;
          final formula =
              _optionalText(args, 'formula') ??
              '${count}D$sides${modifier == 0
                  ? ''
                  : modifier > 0
                  ? '+$modifier'
                  : '$modifier'}';
          final package =
              DiceRulePackageType.values
                  .where((value) => value.name == args['rulePackage'])
                  .firstOrNull ??
              DiceRulePackageType.genericD20;
          final roll = _dice.rollResult(
            formula: formula,
            playerId: actorPlayerId,
            action: _optionalText(args, 'action') ?? 'AI 主持判定',
            reason: _text(args, 'reason'),
            characterId: actorCharacterId,
            difficulty: _optionalInt(args, 'difficulty'),
            rulePackage: package,
            metadata: {
              'turnId': _optionalText(args, 'turnId'),
              'actionId': _optionalText(args, 'actionId') ?? actionId,
            },
          );
          next = _dice.recordResult(session, roll);
          result = roll.toJson();
        case 'skill_check':
        case 'attack_check':
          final existingCheck = session.ruleState.checkHistory
              .where(
                (value) =>
                    value.actionId ==
                    (_optionalText(args, 'actionId') ?? actionId),
              )
              .lastOrNull;
          if (existingCheck != null) {
            result = {
              ...existingCheck.toJson(),
              'success': true,
              'alreadyResolvedByAuthoritativePipeline': true,
              'instruction': '必须依据此真实结果叙事，不得再次投骰或修改结果。',
            };
            break;
          }
          final characterId = call.name == 'attack_check'
              ? _text(args, 'attackerId')
              : _text(args, 'characterId');
          final character = _character(session, characterId);
          final actorPlayerId = _optionalText(args, 'actorPlayerId');
          final actorCharacterId = _optionalText(args, 'actorCharacterId');
          if (actorPlayerId != null && character.playerId != actorPlayerId) {
            throw TRPGRuleException('检定玩家与角色归属不匹配');
          }
          if (actorCharacterId != null && character.id != actorCharacterId) {
            throw TRPGRuleException('检定角色与 actorCharacterId 不匹配');
          }
          final check = _rules.skillCheck(
            character: character,
            stat: args['stat'] as String?,
            skillId: args['skillId'] as String?,
            difficulty: _int(args, 'difficulty'),
            reason: _text(args, 'reason'),
            advantageMode:
                AdvantageMode.values
                    .where((item) => item.name == args['advantageMode'])
                    .firstOrNull ??
                AdvantageMode.normal,
          );
          next = _rules.recordSkillCheck(
            session,
            check,
            characterId: characterId,
            actionId: _optionalText(args, 'actionId') ?? actionId,
            turnId: _optionalText(args, 'turnId'),
          );
          result = check.toJson();
        case 'trigger_rule_check':
          final character = _character(session, _text(args, 'characterId'));
          final checkOutcome = _checks.resolveAction(
            session: session,
            action: _text(args, 'situation'),
            actionId: '$actionId:${call.id}',
            playerId: character.playerId,
            characterId: character.id,
            targetId: _optionalText(args, 'targetId'),
            turnId: _optionalText(args, 'turnId') ?? actionId,
          );
          next = checkOutcome.session;
          result = checkOutcome.result == null
              ? {'requiresCheck': false, 'instruction': '规则判定该事件无需投骰，请按事实继续叙事。'}
              : {
                  ...checkOutcome.result!.toJson(),
                  'instruction': '必须依据此权威结果叙事，不得改骰或反转成败。',
                };
        case 'get_character':
          result = _safeCharacter(
            _character(session, _text(args, 'characterId')),
          );
        case 'get_inventory':
          result = {
            'items': _character(
              session,
              _text(args, 'characterId'),
            ).inventoryItems.map((item) => item.toJson()).toList(),
          };
        case 'give_item':
          final item = InventoryItem(
            id: _text(args, 'itemId'),
            name: _text(args, 'name'),
            description: args['description'] as String? ?? '',
            quantity: _int(args, 'quantity'),
            category:
                InventoryCategory.values
                    .where((item) => item.name == args['category'])
                    .firstOrNull ??
                InventoryCategory.misc,
            usable: args['usable'] as bool? ?? false,
          );
          next = _rules.giveItem(
            session,
            characterId: _text(args, 'characterId'),
            item: item,
            reason: _text(args, 'reason'),
            actionId: actionId,
          );
          result = {'item': item.toJson(), 'success': true};
        case 'remove_item':
          next = _rules.removeItem(
            session,
            characterId: _text(args, 'characterId'),
            itemId: _text(args, 'itemId'),
            amount: _int(args, 'amount'),
            reason: _text(args, 'reason'),
            actionId: actionId,
          );
          result = {'success': true};
        case 'modify_hp':
          next = _rules.modifyHp(
            session,
            characterId: _text(args, 'characterId'),
            amount: _int(args, 'amount'),
            reason: _text(args, 'reason'),
            damageType: args['damageType'] as String?,
            actionId: actionId,
          );
          result = _hpResult(session, next, _text(args, 'characterId'));
        case 'add_status':
          next = _rules.addStatus(
            session,
            characterId: _text(args, 'characterId'),
            effect: StatusEffect(
              id: _text(args, 'statusId'),
              name: _text(args, 'name'),
              description: args['description'] as String? ?? '',
              duration: _optionalInt(args, 'duration'),
              source: args['source'] as String? ?? '',
            ),
            actionId: actionId,
          );
          result = {'success': true};
        case 'remove_status':
          next = _rules.removeStatus(
            session,
            characterId: _text(args, 'characterId'),
            statusId: _text(args, 'statusId'),
            actionId: actionId,
          );
          result = {'success': true};
        case 'update_quest':
          next = _state.updateQuest(
            session,
            questId: _text(args, 'questId'),
            operation: _text(args, 'operation'),
            title: args['title'] as String?,
            description: args['description'] as String?,
            progress: args['progress'] as String?,
            objectiveId: args['objectiveId'] as String?,
            objectiveProgress: _optionalInt(args, 'objectiveProgress'),
            actionId: actionId,
          );
          result = {'success': true, 'questId': args['questId']};
        case 'change_scene':
          final growth = _growth.resolvePending(session);
          final scene = SceneState(
            sceneId: _text(args, 'sceneId'),
            locationId: _text(args, 'locationId'),
            title: _text(args, 'title'),
            description: _text(args, 'description'),
            atmosphere: args['atmosphere'] as String? ?? '',
          );
          next = _state.changeScene(
            growth.session,
            scene: scene,
            reason: _text(args, 'reason'),
            time: args['time'] as String?,
            weather: args['weather'] as String?,
            actionId: actionId,
          );
          result = {
            'scene': scene.toJson(),
            'growth': growth.entries.map((entry) => entry.toJson()).toList(),
            'success': true,
          };
        case 'move_character':
          final characterId = _text(args, 'characterId');
          final actorCharacterId = _text(args, 'actorCharacterId');
          final actorPlayerId = _text(args, 'actorPlayerId');
          if (characterId != actorCharacterId) {
            throw TRPGRuleException('只能移动本次行动绑定的角色');
          }
          final character = _character(session, characterId);
          if (character.playerId != actorPlayerId) {
            throw TRPGRuleException('玩家无权移动其他人的角色');
          }
          final targetLocationId = _text(args, 'targetLocationId');
          final turnId = _text(args, 'turnId');
          final toolActionId = _text(args, 'actionId');
          final now = DateTime.now();
          final oldLocation = session.characterLocations[characterId];
          final locations = <String, CharacterLocationState>{
            ...session.characterLocations,
          };
          locations[characterId] = CharacterLocationState(
            characterId: characterId,
            sceneId:
                args['targetSceneId'] as String? ??
                oldLocation?.sceneId ??
                session.worldState.currentScene.sceneId,
            locationId: targetLocationId,
            groupId: oldLocation?.groupId ?? '',
            enteredAt: now,
            previousSceneId: oldLocation?.sceneId,
            previousLocationId: oldLocation?.locationId,
            movementState: CharacterMovementState.stationary,
          );
          final groups = const PartyGroupManager().rebuild(
            locations,
            previous: session.partyGroups,
            now: now,
          );
          next = session.copyWith(
            characterLocations: locations,
            partyGroups: groups,
            playerCharacters: session.playerCharacters
                .map(
                  (value) => value.id == characterId
                      ? value.copyWith(
                          metadata: {
                            ...value.metadata,
                            'locationId': targetLocationId,
                          },
                        )
                      : value,
                )
                .toList(),
            eventLog: [
              ...session.eventLog,
              TRPGEvent(
                id: _uuid.v4(),
                type: TRPGEventType.sceneChange,
                timestamp: now,
                actorId: actorPlayerId,
                payload: {
                  'turnId': turnId,
                  'actionId': toolActionId,
                  'playerId': actorPlayerId,
                  'characterId': characterId,
                  'targetLocationId': targetLocationId,
                  'reason': _text(args, 'reason'),
                  'scope': 'character',
                },
              ),
            ],
            updatedAt: now,
            lastPlayedAt: now,
          );
          if (next.worldGenerationState.blueprint?.locations.any(
                (item) => item.id == targetLocationId,
              ) ??
              false) {
            next = _worldGeneration.enterLocation(next, targetLocationId);
          }
          result = {
            'success': true,
            'playerId': actorPlayerId,
            'characterId': characterId,
            'turnId': turnId,
            'actionId': toolActionId,
            'locationId': targetLocationId,
          };
        case 'move_characters':
          final ids = (args['characterIds'] as List? ?? const [])
              .map((value) => value.toString())
              .toSet();
          final actorId = _text(args, 'actorCharacterId');
          final actorPlayer = _text(args, 'actorPlayerId');
          if (ids.isEmpty || !ids.contains(actorId)) {
            throw TRPGRuleException('共同移动必须包含当前行动角色');
          }
          for (final id in ids) {
            if (_character(session, id).playerId != actorPlayer) {
              throw TRPGRuleException('只能共同移动同一玩家明确控制的角色');
            }
          }
          final target = _text(args, 'targetLocationId');
          final now = DateTime.now();
          final locations = <String, CharacterLocationState>{
            ...session.characterLocations,
          };
          for (final id in ids) {
            final old = locations[id];
            locations[id] = CharacterLocationState(
              characterId: id,
              sceneId:
                  args['targetSceneId'] as String? ??
                  old?.sceneId ??
                  session.worldState.currentScene.sceneId,
              locationId: target,
              groupId: old?.groupId ?? '',
              enteredAt: now,
              previousSceneId: old?.sceneId,
              previousLocationId: old?.locationId,
            );
          }
          next = session.copyWith(
            characterLocations: locations,
            partyGroups: const PartyGroupManager().rebuild(
              locations,
              previous: session.partyGroups,
              now: now,
            ),
            updatedAt: now,
            lastPlayedAt: now,
          );
          if (next.worldGenerationState.blueprint?.locations.any(
                (item) => item.id == target,
              ) ??
              false) {
            next = _worldGeneration.enterLocation(next, target);
          }
          result = {
            'success': true,
            'characterIds': ids.toList(),
            'locationId': target,
            'groupId': next.partyGroups
                .firstWhere(
                  (group) => group.characterIds.toSet().containsAll(ids),
                  orElse: () => const PartyGroup(groupId: ''),
                )
                .groupId,
          };
        case 'get_world_state':
          result = session.worldState.toJson();
        case 'update_world_flag':
          next = _state.updateWorldFlag(
            session,
            flag: _text(args, 'flag'),
            value: _bool(args, 'value'),
            reason: _text(args, 'reason'),
            actionId: actionId,
          );
          result = {
            'success': true,
            'flag': args['flag'],
            'value': args['value'],
          };
        case 'get_campaign_state':
          result = session.campaignState.toJson();
        case 'get_recent_events':
          final limit = (_optionalInt(args, 'limit') ?? 15).clamp(1, 30);
          result = {
            'events': session.eventLog.reversed
                .take(limit)
                .map((event) => event.toJson())
                .toList()
                .reversed
                .toList(),
          };
        case 'discover_clue':
          next = _state.discoverClue(
            session,
            clueId: _text(args, 'clueId'),
            name: _text(args, 'name'),
            description: _text(args, 'description'),
            characterId: _text(args, 'characterId'),
            actionId: actionId,
          );
          result = {'success': true, 'clueId': args['clueId']};
        case 'modify_npc_relationship':
          final npcId = _text(args, 'npcId');
          final amount = _int(args, 'amount');
          final reason = _text(args, 'reason');
          next = _state.modifyNpcRelationship(
            session,
            npcId: npcId,
            amount: amount,
            reason: reason,
            actionId: actionId,
          );
          final now = DateTime.now();
          final playerId = session.players.firstOrNull?.playerId ?? 'party';
          final history = RelationshipHistory(
            id: _uuid.v4(),
            npcId: npcId,
            playerId: playerId,
            change: amount,
            reason: reason,
            createdAt: now,
            sourceEventId: actionId,
          );
          final relationshipMemory = MemoryEntry(
            id: _uuid.v4(),
            sessionId: session.id,
            type: MemoryType.relationship,
            title: '与 $npcId 的关系发生变化',
            content: reason,
            importance: amount.abs() >= 20 ? 7 : 5,
            createdAt: now,
            updatedAt: now,
            sourceEventIds: [actionId],
            relatedEntityIds: [npcId, playerId],
            npcId: npcId,
            canonPriority: CanonPriority.structuredState,
          );
          next = next.copyWith(
            memoryState: next.memoryState.copyWith(
              relationshipHistory: [
                ...next.memoryState.relationshipHistory,
                history,
              ],
              entries: [...next.memoryState.entries, relationshipMemory],
            ),
          );
          next = _livingNpc.applyRelationshipEvent(
            next,
            npcId: npcId,
            targetCharacter: playerId,
            reason: reason,
            trust: amount,
            respect: amount > 0 ? amount ~/ 3 : 0,
            suspicion: amount < 0 ? -amount : 0,
            memoryImportance: (amount.abs() * 3).clamp(10, 120),
          );
          result = {'success': true};
        case 'discover_location':
          final locationId = _text(args, 'locationId');
          final campaign = session.immersionState.campaignSnapshot;
          final exists = (campaign['locations'] as List? ?? const [])
              .whereType<Map>()
              .any((value) => value['id'] == locationId);
          if (!exists) throw TRPGRuleException('地点不存在：$locationId');
          next = session.copyWith(
            campaignState: session.campaignState.copyWith(
              discoveredLocations: {
                ...session.campaignState.discoveredLocations,
                locationId,
              }.toList(),
            ),
          );
          result = {'success': true, 'locationId': locationId};
        case 'discover_npc':
          final npcId = _text(args, 'npcId');
          if (!session.immersionState.npcInstances.any(
            (value) => value.npcId == npcId,
          )) {
            throw TRPGRuleException('NPC 不存在：$npcId');
          }
          next = session.copyWith(
            immersionState: session.immersionState.copyWith(
              discoveredNpcIds: {
                ...session.immersionState.discoveredNpcIds,
                npcId,
              }.toList(),
              npcInstances: session.immersionState.npcInstances
                  .map(
                    (value) => value.npcId == npcId
                        ? value.copyWith(knownToPlayers: true)
                        : value,
                  )
                  .toList(),
            ),
          );
          result = {'success': true, 'npcId': npcId};
        case 'reveal_information':
          final id = _text(args, 'knowledgeId');
          if (!session.immersionState.privateKnowledge.any(
            (value) => value.id == id,
          )) {
            throw TRPGRuleException('私人信息不存在：$id');
          }
          next = session.copyWith(
            immersionState: session.immersionState.copyWith(
              privateKnowledge: session.immersionState.privateKnowledge
                  .map(
                    (value) => value.id == id
                        ? value.copyWith(
                            visibility: InformationVisibility.public,
                            ownerPlayerIds: const [],
                            revealed: true,
                          )
                        : value,
                  )
                  .toList(),
            ),
          );
          result = {'success': true, 'knowledgeId': id};
        case 'send_private_message':
          final recipient = _text(args, 'recipientPlayerId');
          if (!session.players.any((value) => value.playerId == recipient)) {
            throw TRPGRuleException('玩家不在当前房间：$recipient');
          }
          final message = TRPGPrivateMessage(
            id: _uuid.v4(),
            senderId: 'gm',
            recipientIds: [recipient],
            content: _text(args, 'content'),
            createdAt: DateTime.now(),
            toGm: true,
          );
          next = session.copyWith(
            immersionState: session.immersionState.copyWith(
              privateMessages: [
                ...session.immersionState.privateMessages,
                message,
              ],
            ),
          );
          result = {
            'success': true,
            'messageId': message.id,
            'recipientPlayerId': recipient,
          };
        case 'request_private_roll':
          final playerId = _text(args, 'playerId');
          if (!session.players.any((value) => value.playerId == playerId)) {
            throw TRPGRuleException('玩家不在当前房间：$playerId');
          }
          final sides = _int(args, 'sides');
          final roll = _dice.roll(sides: sides, playerId: playerId);
          next = session.copyWith(
            immersionState: session.immersionState.copyWith(
              timeline: [
                ...session.immersionState.timeline,
                SessionTimelineEntry(
                  id: _uuid.v4(),
                  title: '私密投骰 D$sides = ${roll.total}',
                  detail: _text(args, 'reason'),
                  createdAt: DateTime.now(),
                  visibility: InformationVisibility.playerPrivate,
                  ownerPlayerIds: [playerId],
                ),
              ],
            ),
          );
          result = roll.toJson();
        case 'add_npc_memory':
          final npcId = _text(args, 'npcId');
          if (!session.immersionState.npcInstances.any(
            (value) => value.npcId == npcId,
          )) {
            throw TRPGRuleException('NPC 不存在：$npcId');
          }
          final memory = {
            'id': _uuid.v4(),
            'summary': _text(args, 'summary'),
            'playerId': args['playerId'],
            'importance': _optionalInt(args, 'importance') ?? 1,
            'createdAt': DateTime.now().toIso8601String(),
          };
          next = session.copyWith(
            immersionState: session.immersionState.copyWith(
              npcInstances: session.immersionState.npcInstances
                  .map(
                    (value) => value.npcId == npcId
                        ? value.copyWith(memories: [...value.memories, memory])
                        : value,
                  )
                  .toList(),
            ),
          );
          final isCompanion =
              (session.immersionState.campaignSnapshot['npcs'] as List? ??
                      const [])
                  .whereType<Map>()
                  .any(
                    (value) =>
                        (value['npcId'] == npcId || value['id'] == npcId) &&
                        value['role'] == 'companion',
                  );
          final longTerm = MemoryEntry(
            id: memory['id']! as String,
            sessionId: session.id,
            type: isCompanion
                ? MemoryType.companionMemory
                : MemoryType.npcMemory,
            title: isCompanion ? '队友记忆' : 'NPC 记忆',
            content: memory['summary']! as String,
            importance: ((_optionalInt(args, 'importance') ?? 4) * 2).clamp(
              1,
              10,
            ),
            createdAt: DateTime.parse(memory['createdAt']! as String),
            updatedAt: DateTime.parse(memory['createdAt']! as String),
            relatedEntityIds: [
              npcId,
              if (args['playerId'] is String) args['playerId']! as String,
            ],
            npcId: npcId,
            ownerPlayerId: args['playerId'] as String?,
            visibility: isCompanion
                ? MemoryVisibility.companionPrivate
                : MemoryVisibility.npcPrivate,
            canonPriority: CanonPriority.confirmedMemory,
          );
          next = next.copyWith(
            memoryState: next.memoryState.copyWith(
              entries: [...next.memoryState.entries, longTerm],
            ),
          );
          next = _livingNpc.addMemory(
            next,
            npcId: npcId,
            eventId: memory['id']! as String,
            content: memory['summary']! as String,
            importance: ((_optionalInt(args, 'importance') ?? 4) * 20).clamp(
              1,
              200,
            ),
            kind: (_optionalInt(args, 'importance') ?? 1) >= 5
                ? NPCMemoryKind.longTerm
                : NPCMemoryKind.shortTerm,
            knownBy: [
              npcId,
              if (args['playerId'] is String) args['playerId']! as String,
            ],
          );
          result = {'success': true, 'memoryId': memory['id']};
        case 'advance_world_time':
          final minutes = _int(args, 'minutes');
          next = _worldSimulation.advanceTime(
            session,
            minutes: minutes,
            reason: _text(args, 'reason'),
          );
          result = {
            'success': true,
            'worldMinute': next.livingNpcState.worldMinute,
            'time': next.worldState.time,
            'npcActions': next.livingNpcState.recentActions
                .where(
                  (value) =>
                      value.createdAtMinute >=
                      next.livingNpcState.worldMinute - minutes,
                )
                .map((value) => value.toJson())
                .toList(),
            'factionActions': next.factionSimulationState.actions
                .where(
                  (value) =>
                      value.createdAtMinute >=
                      next.factionSimulationState.worldMinute - minutes,
                )
                .map((value) => value.toJson())
                .toList(),
          };
        case 'record_faction_support':
          next = _faction.applyPlayerSupport(
            session,
            factionId: _text(args, 'factionId'),
            playerId: _text(args, 'playerId'),
            reason: _text(args, 'reason'),
            resourceBoost: _optionalInt(args, 'resourceBoost') ?? 8,
          );
          result = {'success': true};
        case 'modify_faction_relationship':
          next = _faction.modifyRelationship(
            session,
            fromFactionId: _text(args, 'fromFactionId'),
            toFactionId: _text(args, 'toFactionId'),
            delta: _int(args, 'delta'),
            reason: _text(args, 'reason'),
          );
          result = {'success': true};
        case 'declare_faction_war':
          next = _faction.declareWar(
            session,
            attackerFactionId: _text(args, 'attackerFactionId'),
            defenderFactionId: _text(args, 'defenderFactionId'),
            reason: _text(args, 'reason'),
          );
          result = {'success': true, 'state': 'war'};
        case 'reveal_faction_knowledge':
          next = _faction.revealKnowledge(
            session,
            playerId: _text(args, 'playerId'),
            secretId: args['secretId'] as String?,
            knowledgeId: args['knowledgeId'] as String?,
          );
          result = {'success': true};
        case 'expand_generated_location':
          final locationId = _text(args, 'locationId');
          final before =
              session.worldGenerationState.blueprint?.npcs.length ?? 0;
          next = _worldGeneration.enterLocation(session, locationId);
          final after =
              next.worldGenerationState.blueprint?.npcs.length ?? before;
          result = {
            'success': true,
            'locationId': locationId,
            'generatedNpcCount': after - before,
            'alreadyGenerated': after == before,
          };
        case 'record_npc_interaction':
          next = _livingNpc.applyRelationshipEvent(
            session,
            npcId: _text(args, 'npcId'),
            targetCharacter: _text(args, 'targetCharacterId'),
            reason: _text(args, 'reason'),
            trust: _optionalInt(args, 'trust') ?? 0,
            fear: _optionalInt(args, 'fear') ?? 0,
            respect: _optionalInt(args, 'respect') ?? 0,
            hate: _optionalInt(args, 'hate') ?? 0,
            affection: _optionalInt(args, 'affection') ?? 0,
            suspicion: _optionalInt(args, 'suspicion') ?? 0,
            memoryImportance: _optionalInt(args, 'memoryImportance') ?? 40,
          );
          result = {'success': true};
        case 'set_npc_goal':
          final npcId = _text(args, 'npcId');
          final type = NPCGoalType.values.firstWhere(
            (value) => value.name == _text(args, 'type'),
          );
          next = _livingNpc.setGoal(
            session,
            NPCGoal(
              goalId: _text(args, 'goalId'),
              npcId: npcId,
              type: type,
              description: _text(args, 'description'),
              priority: _int(args, 'priority'),
              targetId: args['targetId'] as String?,
              targetLocationId: args['targetLocationId'] as String?,
            ),
          );
          result = {'success': true, 'npcId': npcId};
        case 'record_npc_secret':
          final npcId = _text(args, 'npcId');
          next = _livingNpc.addSecret(
            session,
            npcId: npcId,
            content: _text(args, 'content'),
            importance: _optionalInt(args, 'importance') ?? 50,
            knownBy: (args['knownBy'] as List? ?? const [])
                .map((value) => value.toString())
                .toList(),
          );
          result = {
            'success': true,
            'npcId': npcId,
            'secretId': next.livingNpcState.secrets.last.secretId,
          };
        case 'kill_npc':
          final npcId = _text(args, 'npcId');
          next = _livingNpc.killNpc(
            session,
            npcId: npcId,
            killerId: args['killerId'] as String?,
            locationId: args['locationId'] as String?,
            reason: _text(args, 'reason'),
          );
          result = {'success': true, 'npcId': npcId, 'status': 'dead'};
        case 'record_promise':
          final now = DateTime.now();
          final memoryId = _uuid.v4();
          final promiseId = _uuid.v4();
          final visibility =
              MemoryVisibility.values
                  .where((value) => value.name == args['visibility'])
                  .firstOrNull ??
              MemoryVisibility.public;
          final promise = PromiseMemory(
            id: promiseId,
            promiser: _text(args, 'promiser'),
            promiseTo: _text(args, 'promiseTo'),
            content: _text(args, 'content'),
            createdAt: now,
            deadline: DateTime.tryParse(args['deadline'] as String? ?? ''),
            memoryId: memoryId,
          );
          final memoryEntry = MemoryEntry(
            id: memoryId,
            sessionId: session.id,
            type: MemoryType.promise,
            title: '重要承诺',
            content:
                '${promise.promiser} 向 ${promise.promiseTo} 承诺：${promise.content}',
            importance: 8,
            createdAt: now,
            updatedAt: now,
            relatedEntityIds: [promise.promiser, promise.promiseTo],
            visibility: visibility,
            pinned: true,
            canonPriority: CanonPriority.confirmedEvent,
          );
          next = session.copyWith(
            memoryState: session.memoryState.copyWith(
              promises: [...session.memoryState.promises, promise],
              entries: [...session.memoryState.entries, memoryEntry],
            ),
          );
          result = {'success': true, 'promiseId': promiseId};
        case 'resolve_promise':
          final promiseId = _text(args, 'promiseId');
          final status = PromiseStatus.values
              .where((value) => value.name == args['status'])
              .first;
          final promise = session.memoryState.promises
              .where((value) => value.id == promiseId)
              .firstOrNull;
          if (promise == null) {
            throw TRPGRuleException('承诺不存在：$promiseId');
          }
          final now = DateTime.now();
          next = session.copyWith(
            memoryState: session.memoryState.copyWith(
              promises: session.memoryState.promises
                  .map(
                    (value) => value.id == promiseId
                        ? value.copyWith(status: status, resolvedAt: now)
                        : value,
                  )
                  .toList(),
              entries: session.memoryState.entries
                  .map(
                    (value) => value.id == promise.memoryId
                        ? value.copyWith(resolved: true, updatedAt: now)
                        : value,
                  )
                  .toList(),
            ),
          );
          result = {
            'success': true,
            'promiseId': promiseId,
            'status': status.name,
          };
        case 'record_knowledge':
          final subjectId = _text(args, 'subjectId');
          final knownSubject =
              session.players.any((value) => value.playerId == subjectId) ||
              session.immersionState.npcInstances.any(
                (value) => value.npcId == subjectId,
              );
          if (!knownSubject) {
            throw TRPGRuleException('认知主体不存在：$subjectId');
          }
          final relation = KnowledgeRelation(
            id: _uuid.v4(),
            subjectId: subjectId,
            type: KnowledgeRelationType.values
                .where((value) => value.name == args['relation'])
                .first,
            objectId: _text(args, 'objectId'),
            confidence:
                MemoryConfidence.values
                    .where((value) => value.name == args['confidence'])
                    .firstOrNull ??
                MemoryConfidence.confirmed,
            createdAt: DateTime.now(),
          );
          next = session.copyWith(
            memoryState: session.memoryState.copyWith(
              knowledgeRelations: [
                ...session.memoryState.knowledgeRelations.where(
                  (value) =>
                      value.subjectId != relation.subjectId ||
                      value.objectId != relation.objectId,
                ),
                relation,
              ],
            ),
          );
          result = {'success': true, 'relationId': relation.id};
        case 'add_story_thread':
          final now = DateTime.now();
          final thread = StoryThread(
            id: _uuid.v4(),
            title: _text(args, 'title'),
            description: _text(args, 'description'),
            createdAt: now,
            relatedEntityIds: (args['relatedEntityIds'] as List? ?? const [])
                .map((value) => value.toString())
                .toList(),
            gmOnly: args['gmOnly'] as bool? ?? false,
          );
          final isForeshadowing = args['foreshadowing'] as bool? ?? false;
          final memoryEntry = MemoryEntry(
            id: _uuid.v4(),
            sessionId: session.id,
            type: isForeshadowing
                ? MemoryType.foreshadowing
                : MemoryType.gmPlot,
            title: thread.title,
            content: thread.description,
            importance: isForeshadowing ? 8 : 7,
            createdAt: now,
            updatedAt: now,
            relatedEntityIds: thread.relatedEntityIds,
            visibility: thread.gmOnly
                ? MemoryVisibility.gmOnly
                : MemoryVisibility.public,
            pinned: isForeshadowing,
            canonPriority: CanonPriority.campaignCanon,
          );
          next = session.copyWith(
            memoryState: session.memoryState.copyWith(
              storyThreads: [...session.memoryState.storyThreads, thread],
              entries: [...session.memoryState.entries, memoryEntry],
            ),
          );
          result = {'success': true, 'threadId': thread.id};
        case 'update_story_thread':
          final threadId = _text(args, 'threadId');
          if (!session.memoryState.storyThreads.any(
            (value) => value.id == threadId,
          )) {
            throw TRPGRuleException('剧情线不存在：$threadId');
          }
          final status = StoryThreadStatus.values
              .where((value) => value.name == args['status'])
              .first;
          next = session.copyWith(
            memoryState: session.memoryState.copyWith(
              storyThreads: session.memoryState.storyThreads
                  .map(
                    (value) => value.id == threadId
                        ? value.copyWith(
                            status: status,
                            updatedAt: DateTime.now(),
                          )
                        : value,
                  )
                  .toList(),
            ),
          );
          result = {
            'success': true,
            'threadId': threadId,
            'status': status.name,
          };
        case 'move_npc':
          final npcId = _text(args, 'npcId');
          final locationId = _text(args, 'locationId');
          final locations =
              (session.immersionState.campaignSnapshot['locations'] as List? ??
                      const [])
                  .whereType<Map>();
          if (!locations.any((value) => value['id'] == locationId)) {
            throw TRPGRuleException('地点不存在：$locationId');
          }
          if (!session.immersionState.npcInstances.any(
            (value) => value.npcId == npcId,
          )) {
            throw TRPGRuleException('NPC 不存在：$npcId');
          }
          next = session.copyWith(
            immersionState: session.immersionState.copyWith(
              npcInstances: session.immersionState.npcInstances
                  .map(
                    (value) => value.npcId == npcId
                        ? value.copyWith(locationId: locationId)
                        : value,
                  )
                  .toList(),
            ),
          );
          next = _livingNpc.synchronizeNpcLocation(
            next,
            npcId: npcId,
            locationId: locationId,
          );
          result = {'success': true, 'npcId': npcId, 'locationId': locationId};
        case 'start_combat':
          final participantIds = (args['participantIds'] as List? ?? const [])
              .map((item) => item.toString())
              .toList();
          next = _rules.startCombat(
            session,
            participantIds: participantIds,
            reason: _text(args, 'reason'),
            actionId: actionId,
          );
          result = {
            'initiative': next.ruleState.initiative,
            'activeTurn': next.ruleState.activeTurn,
          };
        case 'apply_damage':
          final damage = _dice.roll(
            sides: _int(args, 'diceSides'),
            count: _int(args, 'diceCount'),
            modifier: _optionalInt(args, 'modifier') ?? 0,
            playerId: _text(args, 'sourceId'),
          );
          next = _dice.record(session, damage, reason: _text(args, 'reason'));
          final targetId = _text(args, 'targetId');
          final playerTarget = next.playerCharacters.any(
            (character) => character.id == targetId,
          );
          final npcTarget = next.worldState.npcs
              .where((npc) => npc.npcId == targetId)
              .firstOrNull;
          final beforeHp = playerTarget
              ? _character(next, targetId).hp
              : npcTarget?.hp;
          if (beforeHp == null) {
            throw TRPGRuleException('伤害目标不存在：$targetId');
          }
          if (playerTarget) {
            next = _rules.modifyHp(
              next,
              characterId: targetId,
              amount: -damage.total.clamp(0, 1000),
              reason: _text(args, 'reason'),
              damageType: _text(args, 'damageType'),
              actionId: actionId,
            );
          } else {
            final npcs = next.worldState.npcs.map((npc) {
              if (npc.npcId != targetId) return npc;
              final hp = (npc.hp - damage.total).clamp(0, npc.maxHp);
              return npc.copyWith(hp: hp, alive: hp > 0);
            }).toList();
            next = next.copyWith(
              worldState: next.worldState.copyWith(npcs: npcs),
              updatedAt: DateTime.now(),
            );
          }
          final damageEvent = TRPGEvent(
            id: _uuid.v4(),
            type: TRPGEventType.damageApplied,
            timestamp: DateTime.now(),
            actorId: _text(args, 'sourceId'),
            payload: {
              'targetId': _text(args, 'targetId'),
              'damage': damage.toJson(),
              'damageType': _text(args, 'damageType'),
              'actionId': actionId,
            },
          );
          next = next.copyWith(eventLog: [...next.eventLog, damageEvent]);
          final afterHp = playerTarget
              ? _character(next, targetId).hp
              : next.worldState.npcs
                    .firstWhere((npc) => npc.npcId == targetId)
                    .hp;
          if (!playerTarget && afterHp <= 0) {
            next = _livingNpc.killNpc(
              next,
              npcId: targetId,
              killerId: _text(args, 'sourceId'),
              reason: _text(args, 'reason'),
            );
          }
          result = {
            'damage': damage.toJson(),
            'before': beforeHp,
            'after': afterHp,
            'maxHp': playerTarget
                ? _character(next, targetId).maxHp
                : next.worldState.npcs
                      .firstWhere((npc) => npc.npcId == targetId)
                      .maxHp,
          };
        case 'end_combat':
          next = _rules.endCombat(
            session,
            reason: _text(args, 'reason'),
            actionId: actionId,
          );
          final growth = _growth.resolvePending(next);
          next = growth.session;
          result = {
            'success': true,
            'growth': growth.entries.map((entry) => entry.toJson()).toList(),
          };
        case 'set_expression':
          final npcId = _text(args, 'npcId');
          _validateNpc(session, npcId);
          next = _applyPresentation(
            session,
            PresentationEventType.characterExpression,
            {'npcId': npcId, 'expression': _text(args, 'expression')},
          );
          result = {'success': true};
        case 'show_character':
          final npcId = _text(args, 'npcId');
          _validateNpc(session, npcId);
          next =
              _applyPresentation(session, PresentationEventType.characterShow, {
                'npcId': npcId,
                'position': _text(args, 'position'),
                'expression': _text(args, 'expression'),
              });
          result = {'success': true};
        case 'hide_character':
          final npcId = _text(args, 'npcId');
          _validateNpc(session, npcId);
          next = _applyPresentation(
            session,
            PresentationEventType.characterHide,
            {'npcId': npcId},
          );
          result = {'success': true};
        case 'set_bgm':
          next = _applyPresentation(session, PresentationEventType.bgmPlay, {
            'assetId': _text(args, 'mood'),
          });
          result = {'success': true};
        case 'set_ambient':
          next = _applyPresentation(
            session,
            PresentationEventType.ambientPlay,
            {'assetId': _text(args, 'ambient')},
          );
          result = {'success': true};
        case 'play_sfx':
          next = _applyPresentation(session, PresentationEventType.sfxPlay, {
            'assetId': _text(args, 'sfx'),
          });
          result = {'success': true};
        case 'set_scene_visual':
          final backgroundId = _text(args, 'backgroundId');
          if (backgroundId.contains(':') || backgroundId.startsWith('/')) {
            throw TRPGRuleException('演出资源必须使用相对资源 ID');
          }
          next = _applyPresentation(
            session,
            PresentationEventType.sceneBackground,
            {'backgroundId': backgroundId},
          );
          next = _applyPresentation(
            next,
            PresentationEventType.screenTransition,
            {'style': _text(args, 'transition')},
          );
          result = {'success': true};
        default:
          throw TRPGRuleException('未注册工具：${call.name}');
      }
    } catch (error) {
      succeeded = false;
      result = {'error': error.toString(), 'tool': call.name};
    }
    result = {
      ...result,
      if (call.arguments['turnId'] != null) 'turnId': call.arguments['turnId'],
      if (call.arguments['actionId'] != null)
        'actionId': call.arguments['actionId'],
      if (call.arguments['actorPlayerId'] != null)
        'actorPlayerId': call.arguments['actorPlayerId'],
      if (call.arguments['actorCharacterId'] != null)
        'actorCharacterId': call.arguments['actorCharacterId'],
    };
    final record = ToolExecutionRecord(
      toolCallId: call.id.isEmpty ? _uuid.v4() : call.id,
      actionId: actionId,
      toolName: call.name,
      arguments: call.arguments,
      result: result,
      succeeded: succeeded,
      executedAt: DateTime.now(),
    );
    next = next.copyWith(toolExecutions: [...next.toolExecutions, record]);
    if (onMutated != null && !identical(next, session)) await onMutated(next);
    return ToolExecutionOutcome(
      session: next,
      result: result,
      record: record,
      wasCached: false,
    );
  }

  static void _validateNpc(TRPGSession session, String npcId) {
    final exists = session.immersionState.npcInstances.any(
      (value) => value.npcId == npcId,
    );
    if (!exists) throw TRPGRuleException('NPC 不存在：$npcId');
  }

  static TRPGSession _applyPresentation(
    TRPGSession session,
    PresentationEventType type,
    Map<String, Object?> payload,
  ) {
    final event = PresentationEvent(
      eventId: _uuid.v4(),
      type: type,
      sequenceNumber: session.presentationState.sequenceNumber + 1,
      createdAt: DateTime.now(),
      payload: payload,
    );
    return session.copyWith(
      presentationState: _reducePresentation(session.presentationState, event),
    );
  }

  static CurrentPresentationState _reducePresentation(
    CurrentPresentationState state,
    PresentationEvent event,
  ) {
    var next = state.copyWith(sequenceNumber: event.sequenceNumber);
    switch (event.type) {
      case PresentationEventType.characterShow:
        final id = event.payload['npcId'] as String;
        final visible = [
          ...next.visibleCharacters.where((value) => value.npcId != id),
        ];
        if (visible.length == 3) visible.removeAt(0);
        visible.add(
          VisibleCharacterState(
            npcId: id,
            expression: NPCExpression.values.byName(
              event.payload['expression'] as String,
            ),
            position: PortraitPosition.values.byName(
              event.payload['position'] as String,
            ),
          ),
        );
        next = next.copyWith(visibleCharacters: visible);
      case PresentationEventType.characterHide:
        next = next.copyWith(
          visibleCharacters: next.visibleCharacters
              .where((value) => value.npcId != event.payload['npcId'])
              .toList(),
        );
      case PresentationEventType.characterExpression:
        next = next.copyWith(
          visibleCharacters: next.visibleCharacters
              .map(
                (value) => value.npcId == event.payload['npcId']
                    ? value.copyWith(
                        expression: NPCExpression.values.byName(
                          event.payload['expression'] as String,
                        ),
                      )
                    : value,
              )
              .toList(),
        );
      case PresentationEventType.bgmPlay:
        next = next.copyWith(bgmId: event.payload['assetId'] as String?);
      case PresentationEventType.ambientPlay:
        next = next.copyWith(ambientId: event.payload['assetId'] as String?);
      case PresentationEventType.sceneBackground:
        next = next.copyWith(
          backgroundId: event.payload['backgroundId'] as String?,
        );
      case PresentationEventType.screenTransition:
        next = next.copyWith(
          transitionStyle: SceneTransitionStyle.values.byName(
            event.payload['style'] as String,
          ),
        );
      default:
        break;
    }
    return next;
  }

  static Map<String, Object?> _schema(
    String name,
    String description,
    Map<String, Object?> properties,
    List<String> required,
  ) => {
    'type': 'function',
    'function': {
      'name': name,
      'description': description,
      'parameters': {
        'type': 'object',
        'properties': properties,
        'required': required,
        'additionalProperties': false,
      },
    },
  };

  static Map<String, Object?> _string({List<String>? enumValues}) => {
    'type': 'string',
    if (enumValues != null) 'enum': enumValues,
  };
  static Map<String, Object?> _integer({int? minimum, int? maximum}) => {
    'type': 'integer',
    if (minimum != null) 'minimum': minimum,
    if (maximum != null) 'maximum': maximum,
  };

  String _text(Map<String, Object?> args, String key) {
    final value = args[key];
    if (value is! String || value.trim().isEmpty) {
      throw TRPGRuleException('参数 $key 不能为空');
    }
    return value.trim();
  }

  int _int(Map<String, Object?> args, String key) {
    final value = args[key];
    if (value is! num) throw TRPGRuleException('参数 $key 必须是整数');
    return value.toInt();
  }

  int? _optionalInt(Map<String, Object?> args, String key) =>
      args[key] is num ? (args[key] as num).toInt() : null;

  String? _optionalText(Map<String, Object?> args, String key) {
    final value = args[key];
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
  }

  bool _bool(Map<String, Object?> args, String key) {
    final value = args[key];
    if (value is! bool) throw TRPGRuleException('参数 $key 必须是布尔值');
    return value;
  }

  PlayerCharacter _character(TRPGSession session, String id) =>
      session.playerCharacters.where((item) => item.id == id).firstOrNull ??
      (throw TRPGRuleException('角色不存在：$id'));

  Map<String, Object?> _safeCharacter(PlayerCharacter character) => {
    'id': character.id,
    'name': character.name,
    'hp': character.hp,
    'maxHp': character.maxHp,
    'stats': character.stats,
    'skills': character.skills,
    'statusEffects': character.structuredStatusEffects
        .map((item) => item.toJson())
        .toList(),
    'equipment': character.equipment,
  };

  Map<String, Object?> _hpResult(
    TRPGSession before,
    TRPGSession after,
    String characterId,
  ) => {
    'before': _character(before, characterId).hp,
    'after': _character(after, characterId).hp,
    'maxHp': _character(after, characterId).maxHp,
  };
}
