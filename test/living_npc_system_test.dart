import 'package:flutter_test/flutter_test.dart';

import 'package:ai_tavern/models/trpg_game_models.dart';
import 'package:ai_tavern/models/trpg_living_npc_models.dart';
import 'package:ai_tavern/models/trpg_models.dart';
import 'package:ai_tavern/services/trpg/living_npc_service.dart';

void main() {
  const service = LivingNPCService();

  test('玩家救 NPC 后关系与长期记忆在一天后仍保留', () {
    var session = service.ensureInitialized(_session());
    session = service.applyRelationshipEvent(
      session,
      npcId: 'doctor',
      targetCharacter: 'character-a',
      reason: '玩家从火场救出医生',
      trust: 30,
      respect: 10,
      memoryImportance: 120,
    );
    session = service.advanceTime(session, minutes: 1440);
    final relation = session.livingNpcState.relationships.singleWhere(
      (value) => value.sourceNpc == 'doctor',
    );
    expect(relation.trust, 30);
    expect(
      session.livingNpcState.memories.any(
        (value) => value.npcId == 'doctor' && value.permanent,
      ),
      isTrue,
    );
  });

  test('玩家欺骗 NPC 会降低信任并提高怀疑', () {
    final session = service.applyRelationshipEvent(
      _session(),
      npcId: 'doctor',
      targetCharacter: 'character-a',
      reason: '玩家谎称没有进入地下室',
      trust: -40,
      suspicion: 50,
    );
    final relation = session.livingNpcState.relationships.single;
    expect(relation.trust, -40);
    expect(relation.suspicion, 50);
  });

  test('玩家离开三天后重要 NPC 会产生主动行动', () {
    final session = service.advanceTime(_session(), minutes: 4320);
    expect(session.livingNpcState.recentActions, isNotEmpty);
    expect(
      session.eventLog.any(
        (value) =>
            value.type == TRPGEventType.npcAction ||
            value.type == TRPGEventType.npcDiscovery,
      ),
      isTrue,
    );
  });

  test('NPC 秘密只对明确知情者可见', () {
    var session = service.ensureInitialized(_session());
    final canon = session.livingNpcState.secrets.singleWhere(
      (value) => value.ownerNpc == 'doctor',
    );
    expect(session.livingNpcState.forViewer('player-a').secrets, isEmpty);
    session = service.revealSecret(
      session,
      secretId: canon.secretId,
      receiverId: 'player-a',
    );
    expect(
      session.livingNpcState.forViewer('player-a').secrets.single.content,
      contains('实验事故'),
    );
    expect(session.livingNpcState.forViewer('player-b').secrets, isEmpty);
  });

  test('NPC 死亡保留死亡事实并改变现场 NPC 记忆', () {
    final session = service.killNpc(
      _session(),
      npcId: 'doctor',
      killerId: 'enemy',
      reason: '保护患者时遇袭',
    );
    expect(session.livingNpcState.brains['doctor']!.status, NPCLifeStatus.dead);
    expect(session.worldState.npcs.first.alive, isFalse);
    expect(
      session.livingNpcState.memories.any(
        (value) => value.npcId == 'nurse' && value.kind == NPCMemoryKind.trauma,
      ),
      isTrue,
    );
  });

  test('NPC 与 NPC 关系作为有向边保存', () {
    final session = service.applyRelationshipEvent(
      _session(),
      npcId: 'nurse',
      targetCharacter: 'doctor',
      reason: '护士保护医生的研究资料',
      trust: 20,
      affection: 15,
    );
    final relation = const NPCRelationshipGraph().relation(
      session.livingNpcState,
      'nurse',
      'doctor',
    );
    expect(relation?.trust, 20);
    expect(relation?.affection, 15);
  });

  test('Save Load 保持 NPC Brain、关系、秘密与时间', () {
    var session = service.applyRelationshipEvent(
      _session(),
      npcId: 'doctor',
      targetCharacter: 'character-a',
      reason: '共同调查',
      trust: 12,
    );
    session = service.advanceTime(session, minutes: 90);
    final restored = TRPGSession.fromJson(session.toJson());
    expect(restored.schemaVersion, trpgSchemaVersion);
    expect(restored.livingNpcState.worldMinute, 90);
    expect(restored.livingNpcState.brains.keys, contains('doctor'));
    expect(restored.livingNpcState.relationships.single.trust, 12);
    expect(restored.livingNpcState.secrets, isNotEmpty);
  });

  test('时间推进会执行 NPC 每日计划并同步位置', () {
    var session = service.ensureInitialized(_session());
    final doctor = session.livingNpcState.brains['doctor']!;
    session = session.copyWith(
      livingNpcState: session.livingNpcState.copyWith(
        brains: {
          ...session.livingNpcState.brains,
          'doctor': doctor.copyWith(
            beliefs: {...doctor.beliefs, 'knows_location_basement': true},
            schedule: const [
              NPCScheduleEntry(
                minuteOfDay: 18 * 60,
                actionType: NPCActionType.move,
                locationId: 'basement',
                description: '去地下室寻找研究资料',
              ),
            ],
          ),
        },
      ),
    );
    session = service.advanceTime(session, minutes: 18 * 60);
    expect(
      session.livingNpcState.brains['doctor']!.currentLocation,
      'basement',
    );
    expect(
      session.immersionState.npcInstances
          .singleWhere((value) => value.npcId == 'doctor')
          .locationId,
      'basement',
    );
  });

  test('多人模式中同一 NPC 对不同玩家保持独立关系', () {
    var session = _session(mode: TRPGMode.multiplayer);
    session = service.applyRelationshipEvent(
      session,
      npcId: 'doctor',
      targetCharacter: 'character-a',
      reason: 'A 救了医生',
      trust: 30,
    );
    session = service.applyRelationshipEvent(
      session,
      npcId: 'doctor',
      targetCharacter: 'character-b',
      reason: 'B 欺骗医生',
      trust: -25,
      suspicion: 30,
    );
    final relations = session.livingNpcState.relationships;
    expect(
      relations
          .singleWhere((value) => value.targetCharacter == 'character-a')
          .trust,
      30,
    );
    expect(
      relations
          .singleWhere((value) => value.targetCharacter == 'character-b')
          .trust,
      -25,
    );
  });

  test('NPC 私有上下文不会获得其他 NPC 的未来信息', () {
    var session = service.addMemory(
      _session(),
      npcId: 'doctor',
      content: '明天港口会发生爆炸',
      importance: 100,
      kind: NPCMemoryKind.beliefChange,
      knownBy: const ['doctor'],
    );
    final nurseContext = service.buildNpcContext(
      session,
      npcId: 'nurse',
      interactingCharacterId: 'character-a',
    );
    final doctorContext = service.buildNpcContext(
      session,
      npcId: 'doctor',
      interactingCharacterId: 'character-a',
    );
    expect(nurseContext, isNot(contains('港口会发生爆炸')));
    expect(doctorContext, contains('港口会发生爆炸'));
  });
}

TRPGSession _session({TRPGMode mode = TRPGMode.solo}) {
  final now = DateTime(2026, 8, 21);
  return TRPGSession(
    id: 'living-npc-test',
    title: 'Living NPC Test',
    mode: mode,
    createdAt: now,
    updatedAt: now,
    lastPlayedAt: now,
    campaignId: 'test-campaign',
    players: [
      TRPGPlayer(
        playerId: 'player-a',
        displayName: 'A',
        characterId: 'character-a',
        joinedAt: now,
      ),
      if (mode == TRPGMode.multiplayer)
        TRPGPlayer(
          playerId: 'player-b',
          displayName: 'B',
          characterId: 'character-b',
          joinedAt: now,
        ),
    ],
    playerCharacters: const [
      PlayerCharacter(id: 'character-a', playerId: 'player-a', name: 'A角色'),
      PlayerCharacter(id: 'character-b', playerId: 'player-b', name: 'B角色'),
    ],
    worldState: const WorldState(
      time: '第1天 00:00',
      currentScene: SceneState(
        sceneId: 'clinic-scene',
        locationId: 'clinic',
        title: '诊所',
        npcIds: ['doctor', 'nurse'],
      ),
      npcs: [
        NPCState(npcId: 'doctor', name: '医生', locationId: 'clinic'),
        NPCState(npcId: 'nurse', name: '护士', locationId: 'clinic'),
      ],
    ),
    immersionState: const TRPGImmersionState(
      campaignSnapshot: {
        'locations': [
          {'id': 'clinic', 'name': '诊所'},
          {'id': 'basement', 'name': '地下室'},
        ],
        'npcs': [
          {
            'npcId': 'doctor',
            'name': '医生',
            'role': 'majorNpc',
            'locationId': 'clinic',
            'personality': '谨慎，善良，固执',
            'privateNotes': '医生隐瞒了一场实验事故。',
            'metadata': {
              'goal': '寻找失踪患者',
              'values': ['救人'],
              'fears': ['失去病人'],
              'knownLocationIds': ['clinic', 'basement'],
              'safeLocationIds': ['clinic'],
              'speechStyle': '温和但坚定',
            },
          },
          {
            'npcId': 'nurse',
            'name': '护士',
            'role': 'npc',
            'locationId': 'clinic',
            'personality': '认真，敏锐',
          },
        ],
      },
      npcInstances: [
        NPCInstanceState(npcId: 'doctor', locationId: 'clinic'),
        NPCInstanceState(npcId: 'nurse', locationId: 'clinic'),
      ],
    ),
  );
}
