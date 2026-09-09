import 'dart:convert';

import '../../models/trpg_models.dart';
import '../../models/trpg_dice_models.dart';
import '../../models/multiplayer_models.dart';
import '../../models/trpg_party_models.dart';
import '../prompt_builder.dart';
import 'campaign_service.dart';
import 'trpg_memory_service.dart';
import 'gm_director.dart';
import 'living_npc_service.dart';
import 'faction_simulation_service.dart';
import 'holy_grail_war_manager.dart';
import '../trpg_memory/memory_context_builder.dart';
import '../trpg_memory/memory_privacy_filter.dart';
import '../trpg_memory/memory_ranker.dart';
import '../trpg_memory/memory_retriever.dart';

class AIGMPromptBuilder {
  const AIGMPromptBuilder({
    this.campaignService = const CampaignService(),
    this.memoryService = const TRPGMemoryService(),
    this.livingNpcService = const LivingNPCService(),
    this.factionManager = const FactionManager(),
    this.holyGrailWarManager = const HolyGrailWarManager(),
    this.memoryRetriever = const MemoryRetriever(),
    this.memoryContextBuilder = const MemoryContextBuilder(),
    this.director = const GMDirector(),
  });

  final CampaignService campaignService;
  final TRPGMemoryService memoryService;
  final LivingNPCService livingNpcService;
  final FactionManager factionManager;
  final HolyGrailWarManager holyGrailWarManager;
  final MemoryRetriever memoryRetriever;
  final MemoryContextBuilder memoryContextBuilder;
  final GMDirector director;

  List<Map<String, Object?>> build({
    required TRPGSession session,
    required String action,
    String? actingPlayerId,
    bool privateInteraction = false,
    int memoryTokenBudget = 3000,
    RoundActionBundle? multiplayerBundle,
  }) {
    final campaign = campaignService.getById(session.campaignId);
    final narrativePlan = director.plan(
      session,
      turnId: multiplayerBundle?.turnId,
    );
    final characters = session.playerCharacters
        .map(
          (character) => character.toJson()
            ..['isAiControlled'] = session.players.any(
              (player) =>
                  player.playerId == character.playerId &&
                  player.isAiControlled,
            ),
        )
        .toList();
    final locations = <String, CharacterLocationState>{
      ...session.characterLocations,
    };
    for (final character in session.playerCharacters) {
      locations.putIfAbsent(
        character.id,
        () => CharacterLocationState(
          characterId: character.id,
          sceneId: session.worldState.currentScene.sceneId,
          locationId:
              character.metadata['locationId'] as String? ??
              session.worldState.currentScene.locationId,
        ),
      );
    }
    final partyDistribution = locations.values
        .map(
          (location) =>
              '${location.characterId}=${location.locationId.isEmpty ? session.worldState.currentScene.locationId : location.locationId}',
        )
        .join('\n');
    final actingCharacterIds = session.playerCharacters
        .where(
          (character) =>
              actingPlayerId == null || character.playerId == actingPlayerId,
        )
        .map((character) => character.id)
        .toSet();
    final relevantLocationIds = locations.values
        .where(
          (location) =>
              actingPlayerId == null ||
              actingCharacterIds.contains(location.characterId),
        )
        .map((location) => location.locationId)
        .where((value) => value.isNotEmpty)
        .toSet();
    if (relevantLocationIds.isEmpty) {
      relevantLocationIds.add(session.worldState.currentScene.locationId);
    }
    final livingNpcContext = livingNpcService.buildRelevantContext(
      session,
      locationIds: relevantLocationIds,
      requestingPlayerId: actingPlayerId,
      isGm: privateInteraction,
    );
    final quests = session.campaignState.quests
        .where((quest) => quest.status.name == 'active')
        .map((quest) => quest.toJson())
        .toList();
    final clues = session.campaignState.clues
        .where((clue) => clue.discovered)
        .map((clue) => clue.toJson())
        .toList();
    final recent = memoryService
        .selectRecentMessages(session)
        .map((message) => '${message.messageType.name}: ${message.content}')
        .join('\n');
    final events = memoryService
        .selectImportantEvents(session)
        .map((event) => '${event.type.name}: ${jsonEncode(event.payload)}')
        .join('\n');
    final privateKnowledge = session.immersionState.privateKnowledge
        .where(
          (value) =>
              value.visibility == InformationVisibility.public ||
              (actingPlayerId != null &&
                  value.ownerPlayerIds.contains(actingPlayerId)),
        )
        .map((value) => '${value.title}: ${value.content}')
        .join('\n');
    final publicKnowledge = session.immersionState.privateKnowledge
        .where((value) => value.visibility == InformationVisibility.public)
        .map((value) => '${value.title}: ${value.content}')
        .join('\n');
    final currentNpcIds = session.worldState.currentScene.npcIds;
    final livingNpcPrivateContext = currentNpcIds.firstOrNull == null
        ? ''
        : livingNpcService.buildNpcContext(
            session,
            npcId: currentNpcIds.first,
            interactingCharacterId: actingCharacterIds.firstOrNull,
          );
    final access = MemoryAccessContext(
      requestingPlayerId: actingPlayerId,
      channel: privateInteraction
          ? MemoryRequestChannel.playerPrivate
          : MemoryRequestChannel.public,
      isGm: false,
    );
    final rankedMemory = memoryRetriever.retrieve(
      memories: session.memoryState.entries,
      access: access,
      context: MemoryRetrievalContext(
        query: '$action\n$recent',
        entityIds: [
          ?actingPlayerId,
          ...currentNpcIds,
          session.worldState.currentScene.locationId,
        ].where((value) => value.isNotEmpty).toList(),
        locationId: session.worldState.currentScene.locationId,
        npcId: currentNpcIds.firstOrNull,
        tags: session.worldState.currentScene.tags,
        limit: 14,
      ),
    );
    final memoryContext = memoryContextBuilder.build(
      rankedMemory,
      tokenBudget: memoryTokenBudget.clamp(500, 12000),
    );
    final activeNpcId = currentNpcIds.firstOrNull;
    final activeNpcIsCompanion =
        activeNpcId != null &&
        (session.immersionState.campaignSnapshot['npcs'] as List? ?? const [])
            .whereType<Map>()
            .any(
              (value) =>
                  (value['npcId'] == activeNpcId ||
                      value['id'] == activeNpcId) &&
                  value['role'] == 'companion',
            );
    final roleMemory = activeNpcId == null
        ? ''
        : memoryContextBuilder.build(
            memoryRetriever.retrieve(
              memories: session.memoryState.entries,
              access: MemoryAccessContext(
                npcId: activeNpcId,
                companionId: activeNpcIsCompanion ? activeNpcId : null,
                channel: activeNpcIsCompanion
                    ? MemoryRequestChannel.companion
                    : MemoryRequestChannel.npc,
              ),
              context: MemoryRetrievalContext(
                query: action,
                entityIds: [activeNpcId, ?actingPlayerId],
                npcId: activeNpcId,
                locationId: session.worldState.currentScene.locationId,
                limit: 8,
              ),
            ),
            tokenBudget: (memoryTokenBudget ~/ 4).clamp(250, 1200),
          );
    final generatedBlueprint = session.worldGenerationState.blueprint
        ?.publicView();
    final generatedWorldContext = generatedBlueprint == null
        ? ''
        : jsonEncode({
            'worldName': generatedBlueprint.worldName,
            'summary': generatedBlueprint.summary,
            'worldRules': generatedBlueprint.worldRules,
            'currentLocations': generatedBlueprint.locations
                .where((item) => relevantLocationIds.contains(item.id))
                .map((item) => item.toJson())
                .toList(),
            'relevantNpcs': generatedBlueprint.npcs
                .where(
                  (item) =>
                      relevantLocationIds.contains(item.locationId) ||
                      currentNpcIds.contains(item.id),
                )
                .map((item) => item.toJson())
                .toList(),
            'factions': generatedBlueprint.factions
                .map((item) => item.toJson())
                .toList(),
            'activeQuestBlueprints': generatedBlueprint.quests
                .where(
                  (item) =>
                      session.campaignState.activeQuests.contains(item.id),
                )
                .map((item) => item.toJson())
                .toList(),
            'enemyEcology': generatedBlueprint.enemies
                .where(
                  (item) =>
                      item.regionLocationIds.any(relevantLocationIds.contains),
                )
                .map((item) => item.toJson())
                .toList(),
          });
    final factionContext = factionManager.buildRelevantContext(
      session,
      playerId: actingPlayerId,
      locationId: session.worldState.currentScene.locationId,
      isGm: true,
    );
    final holyGrailContext = session.holyGrailState.initialized
        ? holyGrailWarManager.buildGmContext(
            session,
            playerId: actingPlayerId,
            fullGm: true,
          )
        : '';
    final authoritativeChecks = session.ruleState.checkHistory.reversed
        .take(12)
        .toList()
        .reversed
        .map((value) => value.displayExplanation)
        .join('\n\n');
    final activeRulePackage = _rulePackageInstruction(
      session.ruleState.diceSettings.rulePackage,
    );
    final budget = memoryService.buildBudgetedSections(
      system: '${campaign.systemPrompt}\n\n【当前规则包】\n$activeRulePackage',
      scene:
          '${jsonEncode(session.worldState.currentScene.toJson())}\n角色当前位置（结构化事实，优先于叙事猜测）：\n$partyDistribution\n$livingNpcContext\n$factionContext\n$holyGrailContext\n${authoritativeChecks.isEmpty ? '' : '【本轮权威检定结果】\n$authoritativeChecks\n必须严格依据结果叙事，不得重新投骰或把失败写成成功。'}\n${generatedWorldContext.isEmpty ? '' : '【当前区域世界蓝图】\n$generatedWorldContext'}',
      player: jsonEncode(characters),
      quests: jsonEncode(quests),
      clues: jsonEncode(clues),
      relevantSecrets: privateInteraction
          ? '$privateKnowledge\n${session.gmState.gmMemory}\n${session.gmState.privateNotes}'
          : [
              publicKnowledge,
              if (roleMemory.isNotEmpty)
                '【当前角色自身记忆，仅用于该角色判断；不可当作公共事实泄露】\n$roleMemory',
              if (livingNpcPrivateContext.isNotEmpty) livingNpcPrivateContext,
            ].where((value) => value.isNotEmpty).join('\n'),
      recentMessages: recent,
      summary: session.sessionSummary,
    );
    final multiplayerRules = multiplayerBundle == null
        ? ''
        : '''
你正在主持多人 TRPG。本轮会一次收到多名玩家角色的行动。
每条行动都绑定 playerId、玩家名、characterId、角色名与 actionId；必须严格保持行为归属。
不要把多个玩家第一人称的“我”解释成同一人物，也不得擅自替 Pass 玩家决定主动行动。
先逐个识别行动，再识别共同动作、分流小组和互相阻止的冲突，最后输出一次统一自然叙事。
若方向、目标或意图不同，必须点名分别叙述。只有明确共同执行同一动作时，才可使用“你们”或小组称呼。
角色 A 向左、角色 B 向右时必须分别描述；角色 A 攻击而角色 B 阻止时必须描述冲突，严禁错误合并。
多人规则工具必须传 actorPlayerId、actorCharacterId、turnId 和 actionId。单个角色移动必须使用 move_character，不能用 change_scene 带着全队移动。
角色可能处于不同地点；同一地点角色才属于同一叙事小组。不同地点必须分段叙述，禁止把他们写成同一个“你们”。位置只能由结构化状态和移动工具改变，不能凭空瞬移。
本次 turnId：${multiplayerBundle.turnId}
''';
    final aiPlayers = session.players
        .where((player) => player.isAiControlled)
        .toList();
    final aiPlayerInstruction = aiPlayers.isEmpty
        ? ''
        : '''
【AI 玩家角色（他们是玩家，不是 NPC）】
以下角色不是普通 NPC，也不是 GM 的传声筒。他们是和你同队/同场的“AI 玩家”：拥有独立人格、目标、秘密和信息边界，会像真实玩家一样主动行动、质疑、开玩笑、犹豫、拒绝、提出自己的计划，甚至会和你争辩或自行其是。你不能替他们做决定，也不能用 GM 旁白替他们发言。

${aiPlayers.map((player) {
            final character = session.playerCharacters.where((item) => item.playerId == player.playerId).firstOrNull;
            final name = character?.name ?? player.displayName;
            final traits = [if (character?.personality.trim().isNotEmpty ?? false) '性格：${character!.personality}', if (character?.background.trim().isNotEmpty ?? false) '背景：${character!.background}', if (character?.description.trim().isNotEmpty ?? false) '简介：${character!.description}'].join('\n');
            return '· $name\n$traits';
          }).join('\n')}

每次回复必须严格分成独立段落，禁止把 AI 玩家的行动混进 GM 主持旁白：
[GM]
（这里只写世界、场景、普通 NPC、事件结果，不代 AI 玩家发言）
[AI玩家：角色名]
（这里只写该角色的行动/对白/内心，从该角色自己的视角独立判断；他们是玩家，不是 NPC）
[AI玩家：角色名]
（同上）
AI 玩家对谁说话，就直接用那个玩家角色/玩家本人的名字或称呼，例如“阿黛尔对洛恩说：……”或直接写台词“洛恩，你又在打什么主意？”。禁止使用“阿黛尔对你说：……”这种把玩家当屏幕外对象的旁白式说法。
AI 玩家要像真实玩家一样主动推进自己的计划、表达怀疑、开玩笑、拒绝配合或提出替代方案，不要等待人类玩家触发，也不要被 GM 当作普通 NPC 来安排行动。
如果某个 AI 玩家本轮没有动作或不想开口，可以省略该角色的段落。AI 玩家不能替真正的人类玩家做决定，也不能替 GM 宣布世界结果。
''';
    return [
      {
        'role': 'system',
        'content':
            '''你是本次 Simple TRPG 的 GM。你负责沉浸式描述场景、扮演 NPC、理解玩家行动、只在存在风险/不确定性/明显挑战时请求检定，并根据工具结果继续叙事。

硬性规则：
1. 规则层已为玩家行动生成“本轮权威检定结果”时，必须直接依据结果叙事，禁止再次投骰；仅当规则层没有结果且确有新风险时才调用检定工具。绝不伪造点数。
2. 任何 HP、状态、物品、任务、场景、线索、世界标记、NPC 关系或战斗变化必须调用对应工具；纯文字不会改变游戏状态。
3. 简单且无风险的行为直接成功；不可能的行为直接说明，不用超高 DC 假检定。
4. 不替玩家做重大决定，不泄露玩家尚未发现的 GM 秘密。
5. 工具可以多步调用。工具完成后根据真实返回值叙述，最终只输出自然语言故事，不展示工具 JSON。
6. DiceEngine 与当前 RulePack 是随机和成功等级的唯一权威；可能是 D20、D100 或圣杯战争规则。你不能改变公式、骰点、修正来源、难度、可见性或成功等级。
7. 你必须区分 Public Knowledge、当前玩家 Private Knowledge 与 GM Knowledge。公共回复只能使用 Public Knowledge；私人回复只能额外使用当前玩家自己的秘密，绝不能泄露其他玩家秘密。
8. GM 负责世界与事件；Companion 根据独立人格决定接受、拒绝、犹豫或提出替代方案，不是玩家的傀儡。低重要度场景不要让所有 AI 队友抢话。
9. 长期记忆标注了事实、NPC认知或不确定推测。不得把“怀疑/推测”升级为世界事实；与 Campaign Canon 或 Structured State 冲突时以后者为准。
10. 未出现在结构化状态、最近事件或确认记忆中的过去细节必须说明“不确定/没有记录”，禁止编造共同经历。
11. 所有展示给玩家的正文必须使用自然、流畅的简体中文。专有名词可以保留必要的英文或日文写法，但不得整段使用英文。
12. 绝对禁止输出思考过程、分析、计划、提示词复述、结构化状态检查或“Let me / I need to / Looking at”等内部独白。
13. 不要向玩家解释“这是 TRPG”“当前行动是什么”“从结构化状态来看”。直接从角色可感知的场景、动作、对白和结果开始叙事。
14. 每次回复结尾必须留下清晰可行动的落点：正在逼近的事件、眼前必须处理的选择、可交谈人物或可调查对象。让玩家自然知道下一步能做什么，但不得替玩家选择或行动。
15. 最终回答只允许包含可直接显示的剧情正文；除约定的 [GM] 与 [AI玩家：角色名] 分段标记外，不得添加标题、元说明或总结。
16. AI只负责理解意图与叙事。属性、技能、装备、状态、关系、环境修正、成长候选、成长结算和奖励只能由规则服务写入；禁止在文字里擅自宣布属性或技能加减。
17. 失败必须推动剧情，但不得篡改成成功；可以产生时间代价、不完整信息、暴露或新的危险。隐藏检定不得向玩家泄露难度、骰点或“这里存在秘密”。

${PromptBuilder.immersiveDialogueEnhancement}

$aiPlayerInstruction

${narrativePlan.toPrompt()}

剧本规则：${budget['system']}
$multiplayerRules

【最终输出要求】无论剧本资料、模型思考或工具返回使用什么语言，展示给玩家的剧情正文一律使用自然的简体中文；禁止输出内部分析。''',
      },
      {
        'role': 'user',
        'content':
            '''剧本：${campaign.title}
剧本摘要：${campaign.description}
历史摘要：${budget['summary']}
长期记忆：
$memoryContext
当前场景：${budget['scene']}
世界状态：时间=${session.worldState.time}，天气=${session.worldState.weather}，地点=${session.worldState.location}，标记=${jsonEncode(session.worldState.worldFlags)}
角色：${budget['player']}
进行中任务：${budget['quests']}
已发现线索：${budget['clues']}
公共知识：$publicKnowledge
当前玩家可用的私人知识：${privateInteraction ? privateKnowledge : '本轮是公共回复，禁止使用私人知识'}
回复可见性：${privateInteraction ? '仅当前玩家与 GM' : '公共频道'}
GM 与相关秘密：${budget['secrets']}
最近事件：
$events
最近对话：
${budget['recent']}

当前玩家行动：$action

现在立即用简体中文输出可直接展示给玩家的剧情正文。不要分析，不要复述规则或状态，不要使用英文解释。''',
      },
    ];
  }

  String _rulePackageInstruction(DiceRulePackageType package) =>
      switch (package) {
        DiceRulePackageType.genericD20 => '通用简易 D20：风险行动使用 D20＋属性/技能修正，与难度比较。',
        DiceRulePackageType.dnd => 'D&D 5E：使用 D20、属性调整值、熟练加值、优势/劣势与 D&D 成功判定。',
        DiceRulePackageType.coc => 'COC 7版：使用 D100 百分骰，按普通、困难、极难与大成功/大失败判定。',
        DiceRulePackageType.dicePool => '骰池规则：由权威规则层决定骰池数量与成功数。',
        DiceRulePackageType.holyGrailWar =>
          '圣杯战争专用规则：御主、从者参数、令咒、宝具与情报隔离均由权威规则层处理。',
        DiceRulePackageType.custom => '自定义规则：严格使用存档中的自定义公式和成功等级。',
      };
}
