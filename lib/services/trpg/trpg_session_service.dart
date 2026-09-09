import 'package:uuid/uuid.dart';

import '../../models/trpg_models.dart';
import '../../models/campaign_models.dart';
import '../../models/trpg_dice_models.dart';
import '../../models/trpg_game_models.dart';
import '../../models/trpg_party_models.dart';
import '../../repositories/trpg_session_repository.dart';
import 'living_npc_service.dart';
import 'world_generator.dart';
import 'faction_simulation_service.dart';
import 'holy_grail_war_manager.dart';
import 'campaign_opening_briefing.dart';

class TRPGSessionService {
  TRPGSessionService(this._repository);

  final TRPGSessionRepository _repository;
  static const _uuid = Uuid();

  Future<TRPGSession> createSolo({
    required Campaign campaign,
    CampaignDocument? campaignDocument,
    required String playerName,
    required String characterName,
    required String characterBackground,
    String? characterAvatar,
    required Map<String, num> stats,
    int maxHp = 20,
    String? gmProviderConfigRef,
    List<PlayerCharacter> aiPlayerCharacters = const [],
    DiceRulePackageType rulePackage = DiceRulePackageType.genericD20,
  }) async {
    final now = DateTime.now();
    final playerId = _uuid.v4();
    final characterId = _uuid.v4();
    final aiPlayers = aiPlayerCharacters
        .map(
          (character) => TRPGPlayer(
            playerId: character.playerId,
            displayName: character.name,
            characterId: character.id,
            role: TRPGPlayerRole.player,
            joinedAt: now,
            isReady: true,
            isAiControlled: true,
          ),
        )
        .toList();
    final holyGrail =
        campaignDocument?.campaignType == CampaignType.holyGrailWar;
    final openingLocationId = holyGrail
        ? 'fuyuki_city'
        : campaign.id == 'mist_harbor_test'
        ? 'old_harbor'
        : 'inn';
    final openingSceneId = holyGrail
        ? 'hgw_summoning_night'
        : campaign.id == 'mist_harbor_test'
        ? 'mist_harbor_arrival'
        : 'inn_opening';
    final openingBriefing = const CampaignOpeningBriefing().build(
      campaign: campaign,
      document: campaignDocument,
      playerCharacters: [
        characterName,
        ...aiPlayerCharacters.map((character) => character.name),
      ],
    );
    final session = TRPGSession(
      id: _uuid.v4(),
      title: campaign.title,
      mode: TRPGMode.solo,
      createdAt: now,
      updatedAt: now,
      lastPlayedAt: now,
      status: TRPGSessionStatus.active,
      campaignId: campaign.id,
      gmProviderConfigRef: gmProviderConfigRef,
      players: [
        TRPGPlayer(
          playerId: playerId,
          displayName: playerName,
          characterId: characterId,
          joinedAt: now,
          isReady: true,
        ),
        ...aiPlayers,
      ],
      playerCharacters: [
        PlayerCharacter(
          id: characterId,
          playerId: playerId,
          name: characterName,
          avatar: characterAvatar,
          background: characterBackground,
          stats: stats,
          hp: maxHp.clamp(1, 999),
          maxHp: maxHp.clamp(1, 999),
          skills: const {
            'athletics': 0,
            'stealth': 0,
            'investigation': 2,
            'perception': 2,
            'persuasion': 0,
            'deception': 0,
          },
        ),
        ...aiPlayerCharacters,
      ],
      characterLocations: {
        characterId: CharacterLocationState(
          characterId: characterId,
          sceneId: openingSceneId,
          locationId: openingLocationId,
          enteredAt: now,
        ),
        for (final character in aiPlayerCharacters)
          character.id: CharacterLocationState(
            characterId: character.id,
            sceneId: openingSceneId,
            locationId: openingLocationId,
            enteredAt: now,
          ),
      },
      currentScene: campaign.opening,
      campaignState: CampaignState(
        currentLocationId: campaign.id == 'mist_harbor_test'
            ? 'old_harbor'
            : '',
        activeQuests: campaign.id == 'mist_harbor_test'
            ? const ['missing_keeper']
            : const [],
        quests: campaign.id == 'mist_harbor_test'
            ? [
                QuestState(
                  questId: 'missing_keeper',
                  title: '寻找失踪的调查员',
                  description: '查清调查员伊莱在旧港失踪的原因。',
                  objectives: const [
                    QuestObjective(
                      id: 'find_clue',
                      description: '在港区找到伊莱留下的线索',
                    ),
                    QuestObjective(
                      id: 'enter_warehouse',
                      description: '进入旧港仓库',
                    ),
                    QuestObjective(
                      id: 'find_investigator',
                      description: '找到失踪的调查员',
                    ),
                  ],
                  status: QuestStatus.active,
                  discoveredAt: now,
                ),
              ]
            : const [],
        clues: campaign.id == 'mist_harbor_test'
            ? const [
                ClueState(
                  clueId: 'muddy_bootprints',
                  name: '泥泞脚印',
                  description: '从守卫亭延伸到封锁仓库侧门的脚印。',
                ),
                ClueState(
                  clueId: 'altered_logbook',
                  name: '被涂改的航海日志',
                  description: '记录着夜间走私船和仓库地下室的秘密。',
                ),
              ]
            : const [],
      ),
      worldState: WorldState(
        time: '开场',
        weather: campaign.id == 'mist_harbor_test' ? '浓雾' : '',
        location: campaign.id == 'mist_harbor_test' ? '旧港仓库外' : '旅店',
        currentScene: campaign.id == 'mist_harbor_test'
            ? const SceneState(
                sceneId: 'mist_harbor_arrival',
                locationId: 'old_harbor',
                title: '旧港仓库外',
                description: '浓雾笼罩港口，封锁线在雨中发亮。',
                atmosphere: '深夜、细雨、警戒',
                npcIds: ['guard_hale'],
                tags: ['investigation', 'harbor'],
              )
            : const SceneState(
                sceneId: 'inn_opening',
                locationId: 'inn',
                title: '陌生旅店',
                description: '雨夜中的旅店大厅。',
              ),
        npcs: campaign.id == 'mist_harbor_test'
            ? const [
                NPCState(
                  npcId: 'guard_hale',
                  name: '守卫哈勒',
                  locationId: 'old_harbor',
                  knownToPlayer: true,
                ),
                NPCState(
                  npcId: 'missing_investigator',
                  name: '调查员伊莱',
                  locationId: 'warehouse_basement',
                  knownToPlayer: true,
                ),
              ]
            : const [],
      ),
      gmState: GMState(
        privateNotes: campaign.secrets.join('\n'),
        plotHooks: campaign.quests
            .map((item) => item['title'].toString())
            .toList(),
      ),
      ruleState: RuleState(
        diceSettings: DiceSettings(
          rulePackage: holyGrail
              ? DiceRulePackageType.holyGrailWar
              : rulePackage,
        ),
      ),
      immersionState: campaignDocument == null
          ? const TRPGImmersionState()
          : TRPGImmersionState(
              campaignSnapshot: campaignDocument.toJson(),
              npcInstances: campaignDocument.npcs
                  .map(
                    (npc) => NPCInstanceState(
                      npcId: npc.npcId,
                      sourceCharacterId: npc.sourceCharacterId,
                      relationship: npc.relationship,
                      locationId: npc.locationId,
                      knownToPlayers: npc.knownToPlayers,
                      inventory: npc.inventory,
                    ),
                  )
                  .toList(),
              timeline: [
                SessionTimelineEntry(
                  id: _uuid.v4(),
                  title: '开团导语',
                  detail: openingBriefing,
                  createdAt: now,
                ),
              ],
              privateKnowledge: campaignDocument.clues
                  .where(
                    (clue) =>
                        clue.discovered &&
                        clue.visibility != InformationVisibility.public,
                  )
                  .map(
                    (clue) => PrivateKnowledge(
                      id: clue.id,
                      title: clue.name,
                      content: clue.description,
                      visibility: clue.visibility,
                      createdAt: now,
                    ),
                  )
                  .toList(),
            ),
      chatHistory: [
        TRPGMessage(
          id: _uuid.v4(),
          messageType: TRPGMessageType.gmMessage,
          content: openingBriefing,
          createdAt: now,
        ),
      ],
      eventLog: [
        TRPGEvent(
          id: _uuid.v4(),
          type: TRPGEventType.sceneChange,
          timestamp: now,
          payload: {
            'scene': {
              'id': openingSceneId,
              'title': holyGrail
                  ? '冬木市 · 召唤之夜'
                  : campaign.id == 'mist_harbor_test'
                  ? '旧港仓库外'
                  : '陌生旅店',
              'description': campaign.opening,
            },
          },
        ),
      ],
    );
    final initialized = session.copyWith(
      partyGroups: const PartyGroupManager().rebuild(
        session.characterLocations,
      ),
    );
    final withGeneratedWorld = campaignDocument == null
        ? initialized
        : const WorldGenerationRuntime().initializeSession(
            initialized,
            campaignDocument,
          );
    final withLivingNpcs = const LivingNPCService().ensureInitialized(
      withGeneratedWorld,
    );
    final withFactions = const FactionManager().ensureInitialized(
      withLivingNpcs,
    );
    final holyGrailManager = const HolyGrailWarManager();
    final withHolyGrail = holyGrailManager.initialize(
      withFactions,
      campaign: campaignDocument,
    );
    final ready = holyGrailManager.prepareOpening(withHolyGrail);
    await _repository.upsert(ready);
    return ready;
  }

  Future<void> save(TRPGSession session) => _repository.upsert(session);
  Future<TRPGSession?> restore(String id) async {
    final stored = await _repository.getById(id);
    if (stored == null) return null;
    final withLiving = const LivingNPCService().ensureInitialized(stored);
    final withFactions = const FactionManager().ensureInitialized(withLiving);
    const holyGrailManager = HolyGrailWarManager();
    final migrated = holyGrailManager.prepareOpening(
      holyGrailManager.initialize(withFactions),
    );
    if (migrated.toJson().toString() != stored.toJson().toString()) {
      await _repository.upsert(migrated);
    }
    return migrated;
  }

  Future<void> delete(String id) => _repository.delete(id);

  TRPGSession changeAIHostProvider(TRPGSession session, AIHostConfig config) =>
      session.copyWith(
        aiHostConfig: config,
        gmStateSnapshot: createSnapshotOf(session),
        updatedAt: DateTime.now(),
      );

  GMStateSnapshot createSnapshot(TRPGSession session) =>
      createSnapshotOf(session);

  static GMStateSnapshot createSnapshotOf(
    TRPGSession session,
  ) => GMStateSnapshot(
    campaignSummary: session.gmState.campaignSummary,
    currentScene: session.currentScene,
    worldStateSummary:
        '${session.worldState.time} ${session.worldState.weather} ${session.worldState.location}'
            .trim(),
    playersSummary: session.playerCharacters
        .map((item) => '${item.name} HP ${item.hp}/${item.maxHp}')
        .join('\n'),
    activeQuestSummary: session.campaignState.activeQuests.join('\n'),
    hiddenGmNotes: session.gmState.privateNotes,
    recentEvents: session.eventLog.reversed
        .take(20)
        .map((item) => item.type.name)
        .toList()
        .reversed
        .toList(),
    recentMessages: session.chatHistory.reversed
        .take(20)
        .map((item) => item.content)
        .toList()
        .reversed
        .toList(),
  );
}
